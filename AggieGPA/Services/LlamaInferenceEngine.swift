import Foundation
import Darwin.Mach
#if DEBUG
import Metal
#endif

/// Stage progress, never a prediction of remaining time or total task completion.
nonisolated enum SyllabusVisionProgress: Equatable, Sendable {
    case readingImage(completedLayers: Int, totalLayers: Int)
    case organizingResult

    var fraction: Double? {
        guard case let .readingImage(completed, total) = self, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

#if canImport(llama)
@preconcurrency import llama

private nonisolated final class LlamaCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var progress: SyllabusVisionProgress?
    var encoderLayerCount: Int?

    func updateProgress(_ value: SyllabusVisionProgress?) {
        lock.lock()
        progress = value
        lock.unlock()
    }

    var currentProgress: SyllabusVisionProgress? {
        lock.lock()
        defer { lock.unlock() }
        return progress
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private nonisolated func aggieLlamaBatchClear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private nonisolated func aggieLlamaBatchAdd(
    _ batch: inout llama_batch,
    token: llama_token,
    position: llama_pos,
    logits: Bool
) {
    let index = Int(batch.n_tokens)
    batch.token[index] = token
    batch.pos[index] = position
    batch.n_seq_id[index] = 1
    batch.seq_id[index]![0] = 0
    batch.logits[index] = logits ? 1 : 0
    batch.n_tokens += 1
}

actor LlamaInferenceEngine {
    // b10375's Metal Tensor API produced non-finite Qwen2-VL vision
    // activations on A19 Pro. Use the established Metal kernels instead.
    // This process-wide backend option must be set before first initialization.
    private static let configureMetalCompatibility: Void = {
#if os(iOS) && !targetEnvironment(simulator)
        setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)
#endif
    }()
    nonisolated struct RuntimeConfiguration: Equatable, Sendable {
        let contextLength: UInt32
        let batchSize: UInt32
        let microBatchSize: UInt32

        static func production(for tier: AIBenchmarkQualityTier) -> Self {
            switch tier {
            case .efficient:
                Self(contextLength: 4_096, batchSize: 512, microBatchSize: 256)
            case .balanced:
                Self(contextLength: 4_096, batchSize: 384, microBatchSize: 192)
            case .enhanced:
                Self(contextLength: 3_072, batchSize: 256, microBatchSize: 128)
            }
        }
    }

    struct Generation: Sendable {
        var text: String
        var firstTokenSeconds: Double?
        var totalSeconds: Double
        var generatedTokens: Int
        var peakObservedMemoryBytes: UInt64?
    }

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let visionContext: OpaquePointer?
    private let vocabulary: OpaquePointer
    private nonisolated let generationCancellation: LlamaCancellationFlag
    nonisolated var visualWorkProgress: SyllabusVisionProgress? { generationCancellation.currentProgress }
    private var batch: llama_batch
    private let contextLength: Int
    private let batchSize: Int

    private init(
        modelURL: URL,
        tier: AIBenchmarkQualityTier,
        cancellationFlag: LlamaCancellationFlag,
        projectorURL: URL?,
        visionUsesGPU: Bool
    ) throws {
        _ = Self.configureMetalCompatibility
        traceNativeResources("before-load")
        llama_backend_init()
        var modelParameters = llama_model_default_params()
#if targetEnvironment(simulator)
        modelParameters.n_gpu_layers = 0
#else
        modelParameters.n_gpu_layers = -1
#endif
        modelParameters.check_tensors = true
        modelParameters.progress_callback = { _, userData in
            guard let userData else { return true }
            let flag = Unmanaged<LlamaCancellationFlag>.fromOpaque(userData).takeUnretainedValue()
            return !flag.isCancelled
        }
        modelParameters.progress_callback_user_data = Unmanaged.passUnretained(cancellationFlag).toOpaque()

        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParameters) else {
            llama_backend_free()
            throw LlamaEngineError.modelLoadFailed
        }

        let threads = max(2, min(8, ProcessInfo.processInfo.processorCount - 2))
        traceNativeResources("after-language-model")
        let runtime = RuntimeConfiguration.production(for: tier)
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = runtime.contextLength
        contextParameters.n_batch = runtime.batchSize
        contextParameters.n_ubatch = runtime.microBatchSize
        contextParameters.n_threads = Int32(threads)
        contextParameters.n_threads_batch = Int32(threads)
        contextParameters.offload_kqv = true
        contextParameters.no_perf = false
        contextParameters.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<LlamaCancellationFlag>.fromOpaque(userData).takeUnretainedValue().isCancelled
        }
        contextParameters.abort_callback_data = Unmanaged.passUnretained(cancellationFlag).toOpaque()

        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            llama_backend_free()
            throw LlamaEngineError.contextCreationFailed
        }

        let loadedVisionContext: OpaquePointer?
        if let projectorURL {
            var visionParameters = mtmd_context_params_default()
            // Physical-device acceptance uses Metal with the compatibility
            // configuration above. Model weights and image bounds are unchanged.
#if targetEnvironment(simulator)
            // MTLSimDevice traps while allocating this projector's buffers.
            // Match the text runtime's CPU-only simulator policy.
            visionParameters.use_gpu = false
#else
            visionParameters.use_gpu = visionUsesGPU
#endif
            visionParameters.warmup = false
            visionParameters.n_threads = 2
            visionParameters.image_min_tokens = 256
            visionParameters.image_max_tokens = 1_024
            visionParameters.batch_max_tokens = Int32(runtime.batchSize)
            // Observe only completed transformer layers. b10375 names these
            // nodes layer_out-N; unknown names leave progress indeterminate.
            // No tensor copies, per-token UI callbacks, or cancellation here.
            visionParameters.cb_eval = { tensor, ask, userData in
                guard let tensor, let userData else { return !ask }
                let flag = Unmanaged<LlamaCancellationFlag>.fromOpaque(userData).takeUnretainedValue()
                if !ask && flag.isCancelled { return false }
                guard let total = flag.encoderLayerCount else { return !ask }
                let name = String(cString: ggml_get_name(tensor))
                guard name.hasPrefix("layer_out-"),
                      let layer = Int(name.dropFirst("layer_out-".count)),
                      (0..<total).contains(layer) else { return !ask }
                if !ask {
                    flag.updateProgress(layer + 1 == total
                        ? .organizingResult
                        : .readingImage(completedLayers: layer + 1, totalLayers: total))
                }
                return true
            }
            visionParameters.cb_eval_user_data = Unmanaged.passUnretained(cancellationFlag).toOpaque()
            visionParameters.progress_callback = { _, userData in
                guard let userData else { return false }
                let flag = Unmanaged<LlamaCancellationFlag>.fromOpaque(userData).takeUnretainedValue()
                return !flag.isCancelled
            }
            visionParameters.progress_callback_user_data = Unmanaged.passUnretained(cancellationFlag).toOpaque()

            guard let vision = mtmd_init_from_file(projectorURL.path, loadedModel, visionParameters) else {
                llama_free(loadedContext)
                llama_model_free(loadedModel)
                llama_backend_free()
                throw LlamaEngineError.modelLoadFailed
            }
            guard mtmd_support_vision(vision) else {
                mtmd_free(vision)
                llama_free(loadedContext)
                llama_model_free(loadedModel)
                llama_backend_free()
                throw AIModelStoreError.invalidModel
            }
            loadedVisionContext = vision
        } else {
            loadedVisionContext = nil
        }

        model = loadedModel
        traceNativeResources("after-projector")
        context = loadedContext
        visionContext = loadedVisionContext
        vocabulary = llama_model_get_vocab(loadedModel)
        generationCancellation = cancellationFlag
        batch = llama_batch_init(Int32(runtime.batchSize), 0, 1)
        batchSize = Int(runtime.batchSize)
        contextLength = Int(llama_n_ctx(loadedContext))
    }

    isolated deinit {
        autoreleasepool {
            if let visionContext { mtmd_free(visionContext) }
            llama_batch_free(batch)
            llama_free(context)
            llama_model_free(model)
            llama_backend_free()
        }
        traceNativeResources("after-free")
    }

    static func load(
        modelURL: URL,
        tier: AIBenchmarkQualityTier,
        projectorURL: URL? = nil,
        visionEncoderLayerCount: Int? = nil,
        visionUsesGPU: Bool = false
    ) async throws -> LlamaInferenceEngine {
        let cancellationFlag = LlamaCancellationFlag()
        cancellationFlag.encoderLayerCount = visionEncoderLayerCount
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try autoreleasepool {
                    try LlamaInferenceEngine(
                        modelURL: modelURL,
                        tier: tier,
                        cancellationFlag: cancellationFlag,
                        projectorURL: projectorURL,
                        visionUsesGPU: visionUsesGPU
                    )
                }
            }.value
        } onCancel: {
            cancellationFlag.cancel()
        }
    }

    /// Lets the resource manager stop an in-flight decode when thermal state
    /// becomes critical or the app is backgrounded. The next inference gets a
    /// fresh engine rather than reusing a cancelled context.
    nonisolated func cancelGeneration() {
        generationCancellation.cancel()
    }

    func generateJSON(prompt: String, maximumTokens: Int = 1_536, imageData: Data? = nil) async throws -> Generation {
        // Native Metal temporaries must not wait for an executor's outer pool
        // to drain before the next request performs its memory-headroom check.
        try await withTaskCancellationHandler {
            try autoreleasepool {
                try generateJSONSynchronously(prompt: prompt, maximumTokens: maximumTokens, imageData: imageData)
            }
        } onCancel: {
            generationCancellation.cancel()
        }
    }

    private func generateJSONSynchronously(prompt: String, maximumTokens: Int, imageData: Data?) throws -> Generation {
        generationCancellation.updateProgress(nil)
        defer { generationCancellation.updateProgress(nil) }
        try Task.checkCancellation()
        llama_memory_clear(llama_get_memory(context), true)

        let tokens = imageData == nil ? try tokenize(prompt) : []
        guard maximumTokens > 0, tokens.count + maximumTokens < contextLength else { throw ProviderError.contextTooLarge }

        let started = ContinuousClock.now
        var peakMemory = observedMemoryBytes()
        var offset = 0
        if let imageData {
            if let count = generationCancellation.encoderLayerCount {
                generationCancellation.updateProgress(.readingImage(completedLayers: 0, totalLayers: count))
            }
            offset = try evaluateImage(prompt: prompt, data: imageData, maximumTokens: maximumTokens)
            generationCancellation.updateProgress(.organizingResult)
        }
        while offset < tokens.count {
            try Task.checkCancellation()
            guard !generationCancellation.isCancelled else { throw CancellationError() }
            let end = min(offset + batchSize, tokens.count)
            aggieLlamaBatchClear(&batch)
            for tokenIndex in offset..<end {
                let isFinalPromptToken = tokenIndex == tokens.count - 1
                aggieLlamaBatchAdd(&batch, token: tokens[tokenIndex], position: Int32(tokenIndex), logits: isFinalPromptToken)
            }
            guard llama_decode(context, batch) == 0 else { throw LlamaEngineError.decodeFailed }
            offset = end
            peakMemory = maxOptional(peakMemory, observedMemoryBytes())
        }

        let promptPositions = offset
        let sampler = try makeJSONSampler()
        defer { llama_sampler_free(sampler) }
        var output = ""
        var pendingBytes: [CChar] = []
        var generated = 0
        var firstTokenSeconds: Double?

        while generated < maximumTokens {
            try Task.checkCancellation()
            guard !generationCancellation.isCancelled else { throw CancellationError() }
            // Reject invalid model output before it reaches the native grammar
            // sampler, which cannot safely sample a distribution containing NaN.
            guard let logits = llama_get_logits_ith(context, -1) else {
                throw LlamaEngineError.decodeFailed
            }
            let logitCount = Int(llama_vocab_n_tokens(vocabulary))
            let invalidCount = UnsafeBufferPointer(start: logits, count: logitCount)
                .reduce(0) { $0 + ($1.isFinite ? 0 : 1) }
            guard invalidCount == 0 else {
                print("LLAMA_INVALID_LOGITS count=\(invalidCount)/\(logitCount) generated=\(generated)")
                throw LlamaEngineError.decodeFailed
            }
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocabulary, token) { break }
            pendingBytes.append(contentsOf: tokenPiece(token))
            if let decoded = String(bytes: pendingBytes.map { UInt8(bitPattern: $0) }, encoding: .utf8) {
                if !decoded.isEmpty, firstTokenSeconds == nil {
                    firstTokenSeconds = seconds(from: started, to: .now)
                }
                output.append(decoded)
                pendingBytes.removeAll(keepingCapacity: true)
            }

            aggieLlamaBatchClear(&batch)
            aggieLlamaBatchAdd(&batch, token: token, position: Int32(promptPositions + generated), logits: true)
            guard llama_decode(context, batch) == 0 else { throw LlamaEngineError.decodeFailed }
            generated += 1
            peakMemory = maxOptional(peakMemory, observedMemoryBytes())
        }

        if !pendingBytes.isEmpty {
            output.append(String(decoding: pendingBytes.map(UInt8.init(bitPattern:)), as: UTF8.self))
        }
        let elapsed = seconds(from: started, to: .now)
        return Generation(
            text: output,
            firstTokenSeconds: firstTokenSeconds,
            totalSeconds: elapsed,
            generatedTokens: generated,
            peakObservedMemoryBytes: peakMemory
        )
    }

    /// The caller supplies a verified projector paired with the loaded visual
    /// language model. Image embeddings are evaluated in this same context.
    private func evaluateImage(prompt: String, data: Data, maximumTokens: Int) throws -> Int {
        try Task.checkCancellation()
        guard let visionContext else { throw AIModelStoreError.invalidModel }
        guard !data.isEmpty else { throw SyllabusTextExtractor.ExtractionError.noReadableContent }
        let wrapper = data.withUnsafeBytes { bytes in
            mtmd_helper_bitmap_init_from_buf(
                visionContext,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                false
            )
        }
        guard let bitmap = wrapper.bitmap else { throw SyllabusTextExtractor.ExtractionError.noReadableContent }
        defer { mtmd_bitmap_free(bitmap) }
        guard let chunks = mtmd_input_chunks_init() else { throw LlamaEngineError.contextCreationFailed }
        defer { mtmd_input_chunks_free(chunks) }
        var bitmapPointer: OpaquePointer? = bitmap
        let result = prompt.withCString { text in
            var input = mtmd_input_text(text: text, text_len: prompt.utf8.count, add_special: true, parse_special: true)
            return mtmd_tokenize(visionContext, chunks, &input, &bitmapPointer, 1)
        }
        guard result == 0 else { throw LlamaEngineError.decodeFailed }
        guard Int(mtmd_helper_get_n_tokens(chunks)) + maximumTokens < contextLength else {
            throw ProviderError.contextTooLarge
        }
        try Task.checkCancellation()
        guard !generationCancellation.isCancelled else { throw CancellationError() }
        var position: llama_pos = 0
        guard mtmd_helper_eval_chunks(visionContext, context, chunks, 0, 0, Int32(batchSize), true, &position) == 0 else {
            throw LlamaEngineError.decodeFailed
        }
        try Task.checkCancellation()
        guard Int(position) + maximumTokens < contextLength else { throw ProviderError.contextTooLarge }
        return Int(position)
    }

    private func makeJSONSampler() throws -> UnsafeMutablePointer<llama_sampler> {
        let parameters = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(parameters) else { throw LlamaEngineError.samplerCreationFailed }
        let grammarSampler = Self.jsonGrammar.withCString { grammar in
            "root".withCString { root in
                llama_sampler_init_grammar(vocabulary, grammar, root)
            }
        }
        guard let grammarSampler else {
            llama_sampler_free(chain)
            throw LlamaEngineError.samplerCreationFailed
        }
        llama_sampler_chain_add(chain, grammarSampler)
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.15))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(42))
        return chain
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        let capacity = max(64, text.utf8.count + 64)
        let buffer = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        let count = llama_tokenize(vocabulary, text, Int32(text.utf8.count), buffer, Int32(capacity), true, true)
        guard count >= 0 else { throw ProviderError.contextTooLarge }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(count)))
    }

    private func tokenPiece(_ token: llama_token) -> [CChar] {
        var bytes = [CChar](repeating: 0, count: 16)
        let count = llama_token_to_piece(vocabulary, token, &bytes, Int32(bytes.count), 0, false)
        if count >= 0 { return Array(bytes.prefix(Int(count))) }
        bytes = [CChar](repeating: 0, count: Int(-count))
        let expanded = llama_token_to_piece(vocabulary, token, &bytes, Int32(bytes.count), 0, false)
        return expanded > 0 ? Array(bytes.prefix(Int(expanded))) : []
    }

    private static let jsonGrammar = #"""
    root ::= object
    value ::= object | array | string | number | ("true" | "false" | "null") ws
    object ::= "{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws
    array ::= "[" ws (value ("," ws value)*)? "]" ws
    string ::= "\"" ([^"\\] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]))* "\"" ws
    number ::= ("-"? ([0-9] | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [+-]? [0-9]+)?) ws
    ws ::= ([ \t\n] ws)?
    """#
}

private nonisolated func traceNativeResources(_ phase: String) {
#if DEBUG
    guard ProcessInfo.processInfo.environment["AGGIE_TRACE_NATIVE_RESOURCES"] == "1" else { return }
    let metalBytes = MTLCreateSystemDefaultDevice()?.currentAllocatedSize ?? 0
    var heap = malloc_statistics_t()
    malloc_zone_statistics(nil, &heap)
    print("NATIVE_RESOURCES phase=\(phase) footprint=\(observedMemoryBytes() ?? 0) available=\(os_proc_available_memory()) metal=\(metalBytes) heap-in-use=\(heap.size_in_use) heap-allocated=\(heap.size_allocated)")
#endif
}

private nonisolated func maxOptional(_ lhs: UInt64?, _ rhs: UInt64?) -> UInt64? {
    switch (lhs, rhs) {
    case (.some(let left), .some(let right)): max(left, right)
    case (.some(let value), .none), (.none, .some(let value)): value
    case (.none, .none): nil
    }
}

private nonisolated func observedMemoryBytes() -> UInt64? {
    var information = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &information) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(information.phys_footprint) : nil
}

nonisolated enum LlamaEngineError: LocalizedError {
    case modelLoadFailed
    case contextCreationFailed
    case samplerCreationFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: String(localized: "The local model could not be loaded on this device.")
        case .contextCreationFailed: String(localized: "The local model ran out of working memory before analysis began.")
        case .samplerCreationFailed: String(localized: "The structured-output validator could not be prepared.")
        case .decodeFailed: String(localized: "The local model stopped while analyzing this syllabus.")
        }
    }
}
#else
actor LlamaInferenceEngine {
    nonisolated var visualWorkProgress: SyllabusVisionProgress? { nil }
    nonisolated struct RuntimeConfiguration: Equatable, Sendable {
        let contextLength: UInt32
        let batchSize: UInt32
        let microBatchSize: UInt32

        static func production(for tier: AIBenchmarkQualityTier) -> Self {
            switch tier {
            case .efficient: Self(contextLength: 4_096, batchSize: 512, microBatchSize: 256)
            case .balanced: Self(contextLength: 4_096, batchSize: 384, microBatchSize: 192)
            case .enhanced: Self(contextLength: 3_072, batchSize: 256, microBatchSize: 128)
            }
        }
    }

    struct Generation: Sendable {
        var text: String
        var firstTokenSeconds: Double?
        var totalSeconds: Double
        var generatedTokens: Int
        var peakObservedMemoryBytes: UInt64?
    }

    static func load(
        modelURL: URL,
        tier: AIBenchmarkQualityTier,
        projectorURL: URL? = nil,
        visionEncoderLayerCount: Int? = nil,
        visionUsesGPU: Bool = false
    ) async throws -> LlamaInferenceEngine {
        throw ProviderError.unavailable(String(localized: "The open-source local model runtime is not linked in this build."))
    }

    nonisolated func cancelGeneration() {}

    func generateJSON(prompt: String, maximumTokens: Int = 1_536, imageData: Data? = nil) async throws -> Generation {
        throw ProviderError.unavailable(String(localized: "The open-source local model runtime is not linked in this build."))
    }
}
#endif
