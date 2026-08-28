import Foundation
import Darwin.Mach

#if canImport(llama)
@preconcurrency import llama

private nonisolated final class LlamaCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

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
    struct Generation: Sendable {
        var text: String
        var firstTokenSeconds: Double?
        var totalSeconds: Double
        var generatedTokens: Int
        var peakObservedMemoryBytes: UInt64?
    }

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocabulary: OpaquePointer
    private let generationCancellation: LlamaCancellationFlag
    private var batch: llama_batch
    private let contextLength: Int

    private init(modelURL: URL, cancellationFlag: LlamaCancellationFlag) throws {
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
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = 8_192
        contextParameters.n_batch = 2_048
        contextParameters.n_ubatch = 512
        contextParameters.n_threads = Int32(threads)
        contextParameters.n_threads_batch = Int32(threads)
        contextParameters.offload_kqv = true
        contextParameters.no_perf = false

        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            llama_backend_free()
            throw LlamaEngineError.contextCreationFailed
        }

        model = loadedModel
        context = loadedContext
        vocabulary = llama_model_get_vocab(loadedModel)
        generationCancellation = cancellationFlag
        batch = llama_batch_init(2_048, 0, 1)
        contextLength = Int(llama_n_ctx(loadedContext))
    }

    isolated deinit {
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    static func load(modelURL: URL) async throws -> LlamaInferenceEngine {
        let cancellationFlag = LlamaCancellationFlag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try LlamaInferenceEngine(modelURL: modelURL, cancellationFlag: cancellationFlag)
            }.value
        } onCancel: {
            cancellationFlag.cancel()
        }
    }

    /// Lets the resource manager stop an in-flight decode when thermal state
    /// becomes critical or the app is backgrounded. The next inference gets a
    /// fresh engine rather than reusing a cancelled context.
    func cancelGeneration() {
        generationCancellation.cancel()
    }

    func generateJSON(prompt: String, maximumTokens: Int = 1_536) async throws -> Generation {
        try Task.checkCancellation()
        llama_memory_clear(llama_get_memory(context), true)

        let tokens = try tokenize(prompt)
        guard tokens.count + maximumTokens < contextLength else { throw ProviderError.contextTooLarge }

        let started = ContinuousClock.now
        var peakMemory = observedMemoryBytes()
        var offset = 0
        while offset < tokens.count {
            try Task.checkCancellation()
            let end = min(offset + 2_048, tokens.count)
            aggieLlamaBatchClear(&batch)
            for tokenIndex in offset..<end {
                let isFinalPromptToken = tokenIndex == tokens.count - 1
                aggieLlamaBatchAdd(&batch, token: tokens[tokenIndex], position: Int32(tokenIndex), logits: isFinalPromptToken)
            }
            guard llama_decode(context, batch) == 0 else { throw LlamaEngineError.decodeFailed }
            offset = end
            peakMemory = maxOptional(peakMemory, observedMemoryBytes())
        }

        let sampler = try makeJSONSampler()
        defer { llama_sampler_free(sampler) }
        var output = ""
        var pendingBytes: [CChar] = []
        var generated = 0
        var firstTokenSeconds: Double?

        while generated < maximumTokens {
            try Task.checkCancellation()
            let token = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
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
            aggieLlamaBatchAdd(&batch, token: token, position: Int32(tokens.count + generated), logits: true)
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
    struct Generation: Sendable {
        var text: String
        var firstTokenSeconds: Double?
        var totalSeconds: Double
        var generatedTokens: Int
        var peakObservedMemoryBytes: UInt64?
    }

    static func load(modelURL: URL) async throws -> LlamaInferenceEngine {
        throw ProviderError.unavailable(String(localized: "The open-source local model runtime is not linked in this build."))
    }

    func cancelGeneration() {}

    func generateJSON(prompt: String, maximumTokens: Int = 1_536) async throws -> Generation {
        throw ProviderError.unavailable(String(localized: "The open-source local model runtime is not linked in this build."))
    }
}
#endif
