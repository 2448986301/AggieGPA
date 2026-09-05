import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct SyllabusImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Query private var policies: [CourseGradingPolicy]
    @Query private var existingCategories: [GradingCategory]
    @Query private var existingItems: [GradeItem]
    @Query private var scales: [GradeScale]
    let course: CourseRecord

    @State private var pastedText = ""
    @State private var document: SyllabusTextExtractor.Document?
    @State private var draft: SyllabusImportDraft?
    @State private var phase: SyllabusAnalysisPhase = .idle
    @State private var analysisTask: Task<Void, Never>?
    @State private var modelTask: Task<Void, Never>?
    @State private var documentLoadTask: Task<Void, Never>?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var modelAvailability = OnDeviceSyllabusParser.availability()
    @State private var modelSnapshot: AIModelStoreSnapshot?
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @State private var showModelImporter = false
    @State private var showScanner = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var didSave = false
    @State private var activityIsPressed = false

    private var isWorking: Bool {
        analysisTask != nil || modelTask != nil || documentLoadTask != nil || photoLoadTask != nil
    }
    private var activityContentInset: CGFloat {
        guard activityState != nil else { return 0 }
        // Reserve only the compact resting footprint. The held detail surface
        // floats upward from the same bottom anchor instead of relaying out
        // the List and exposing a large white safe-area block.
        return 112
    }
    private var courseCategories: [GradingCategory] { existingCategories.filter { $0.course?.persistentModelID == course.persistentModelID } }
    private var courseItems: [GradeItem] { existingItems.filter { $0.course?.persistentModelID == course.persistentModelID } }
    private var usesTestProvider: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
            || ProcessInfo.processInfo.arguments.contains("--uitest-in-memory")
            || ProcessInfo.processInfo.arguments.contains("--screenshot-demo")
    }
    private var canAnalyze: Bool { modelAvailability == .available || usesTestProvider }
    private var activityState: AcademicAIActivityState? {
        // Downloads expose real percentage progress below. The orb is reserved
        // for the genuinely indeterminate model/analysis work that follows.
        guard analysisTask != nil || documentLoadTask != nil || (modelTask != nil && phase == .loadingModel) else {
            return nil
        }
        switch phase {
        case .downloadingModel:
            return nil
        case .loadingModel, .modelFallback:
            return .preparingModel
        case .reading:
            // Reading is the first instant of syllabus analysis. Present the
            // stable analysis state immediately so a tap never flashes the
            // later "Preparing Result" state before work has begun.
            return .reasoningSyllabus
        case .analyzingPage, .analyzingGrading, .organizingAssessments:
            return .reasoningSyllabus
        case .repairingStructuredOutput, .retryingRelevantSection:
            return .weavingSections
        case .usingPartialResult, .usingLocalFallback, .validating:
            return .shapingResult
        case .idle, .needsReview, .complete, .unavailable:
            return .reasoningSyllabus
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Group {
                    // A regular iPad window can still present this flow in a
                    // compact 580pt popover. Keep the two-column review only
                    // when both columns have room; otherwise a single list
                    // preserves a reachable, ordered review flow.
                    if horizontalSizeClass == .regular, geometry.size.width >= 760, let draft {
                        HStack(spacing: 0) {
                            List {
                                statusSection
                                sourceSection
                                modelSection
                                sourcePreview
                                if let errorMessage { errorSection(errorMessage) }
                            }
                            .frame(minWidth: 340, idealWidth: 420, maxWidth: 520)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                Color.clear.frame(height: activityContentInset)
                            }
                            Divider()
                            List { review(draft) }
                                .safeAreaInset(edge: .bottom, spacing: 0) {
                                    Color.clear.frame(height: activityContentInset)
                                }
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        List {
                            statusSection
                            sourceSection
                            modelSection
                            if let draft { review(draft) }
                            sourcePreview
                            if let errorMessage { errorSection(errorMessage) }
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            Color.clear.frame(height: activityContentInset)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Import Syllabus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSave ? "Done" : "Cancel") {
                        cancelAll(cancelModelDownload: true)
                        dismiss()
                    }
                }
                if isWorking, activityState == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cancel Analysis") { cancelAll(cancelModelDownload: true) }
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image, .plainText]) { selection in
                guard case .success(let url) = selection else { return }
                load(url)
            }
            .fileImporter(isPresented: $showModelImporter, allowedContentTypes: [.data]) { selection in
                guard case .success(let url) = selection else { return }
                importModel(url)
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                loadSelectedPhotos(items)
            }
            .sheet(isPresented: $showScanner) { DocumentScannerView { images in load(images) } }
            .task {
                while !Task.isCancelled {
                    await refreshModelState()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            // Leaving the flow detaches the view from progress updates. It
            // must not cancel the durable background model download.
            .onDisappear { cancelAll(cancelModelDownload: false) }
            // Keep the activity affordance attached to the visible window
            // edge. In a sheet containing a GeometryReader and List, a
            // safe-area inset can otherwise be positioned after the List's
            // content instead of at the viewport bottom.
            .overlay(alignment: .bottom) {
                activityOverlay
            }
        }
    }

    private var sourceSection: some View {
        Section("Syllabus Source") {
            Button("Choose PDF, Image, or Text", systemImage: "folder") { showFileImporter = true }
                .disabled(isWorking)
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            .disabled(isWorking)
            if VNDocumentCameraViewController.isSupported {
                Button("Scan Pages", systemImage: "doc.viewfinder") { showScanner = true }
                    .disabled(isWorking)
            }

            Text("The local model reads text extracted by PDFKit. Scanned pages without embedded text can still be entered manually.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $pastedText)
                .frame(minHeight: 112)
                .accessibilityIdentifier("syllabusTextEditor")
                .overlay(alignment: .topLeading) {
                    if pastedText.isEmpty {
                        Text("Paste syllabus text")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            Button("Analyze Pasted Text", systemImage: "doc.text.magnifyingglass") {
                let source = SyllabusTextExtractor.Document(
                    pages: [.init(number: 1, text: pastedText, image: nil)],
                    source: .pastedText
                )
                document = source
                // Pass the freshly created document directly. Reading the
                // @State value again in the same action is timing-sensitive
                // in an adaptive iPad sheet and can otherwise skip analysis.
                analyze(document: source)
            }
            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || !canAnalyze)
            .accessibilityIdentifier("parseSyllabusButton")
            if let document, document.source != .pastedText {
                Button("Analyze Selected Syllabus", systemImage: "play.circle") { analyze() }
                    .disabled(isWorking || !canAnalyze)
            }
        }
    }

    private var modelSection: some View {
        Section("On-Device Analysis") {
            Label("Runs On Device", systemImage: "iphone.gen3.radiowaves.left.and.right")
                .font(.headline)
            Text("Syllabus text stays on this iPhone or iPad. No account, API key, cloud inference, or Apple Intelligence is used.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if case .runtimeUnavailable = modelAvailability {
                Label(modelAvailability.message(locale: locale), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if let record = recommendedModelRecord {
                modelDownloadContent(for: record)
            } else {
                LabeledContent("Model download") {
                    Text(OnDeviceAIModelLibrary.recommendedDescriptor.storageLabel)
                }
                Button("Download Local Model", systemImage: "arrow.down.circle") { downloadModel() }
                    .disabled(isWorking)
                Button("Import GGUF from Files", systemImage: "square.and.arrow.down") {
                    showModelImporter = true
                }
                .disabled(isWorking)
            }

            Button("Use Manual Rule Recognition", systemImage: "text.magnifyingglass") {
                guard let source = manualSourceDocument else {
                    errorMessage = AppLocalization.string("Choose a syllabus or paste its grading section first.", locale: locale)
                    return
                }
                document = source
                analyze(mode: .localRules, document: source)
            }
            .disabled(isWorking || manualSourceDocument == nil)
        }
    }

    private var recommendedModelRecord: AIModelRecord? {
        modelSnapshot?.records.first { $0.id == OnDeviceAIModelLibrary.recommendedDescriptor.id }
    }

    @ViewBuilder
    private func modelDownloadContent(for record: AIModelRecord) -> some View {
        switch record.state {
        case .ready:
            Label(OnDeviceAIModelLibrary.activeModelName, systemImage: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.ColorToken.success)
        case .downloading:
            LabeledContent("Model download") {
                Text(OnDeviceAIModelLibrary.recommendedDescriptor.storageLabel)
            }
            if let progress = record.downloadProgress {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                Text(downloadProgressLabel(progress))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Pause", systemImage: "pause.circle") {
                    Task { await OnDeviceAIModelLibrary.pauseRecommendedDownload() }
                }
                Button("Cancel", systemImage: "xmark.circle") {
                    cancelAll(cancelModelDownload: true)
                }
            }
            .buttonStyle(.bordered)
        case .paused:
            if let progress = record.downloadProgress {
                ProgressView(value: progress.fraction ?? 0)
                Text(downloadProgressLabel(progress))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button("Resume Download", systemImage: "play.circle") { downloadModel() }
                .disabled(isWorking)
            Button("Cancel", systemImage: "xmark.circle") {
                cancelAll(cancelModelDownload: true)
            }
            .buttonStyle(.bordered)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Button("Retry Download", systemImage: "arrow.clockwise") { downloadModel() }
                .disabled(isWorking)
        case .notInstalled:
            LabeledContent("Model download") {
                Text(OnDeviceAIModelLibrary.recommendedDescriptor.storageLabel)
            }
            Button("Download Local Model", systemImage: "arrow.down.circle") { downloadModel() }
                .disabled(isWorking)
            Button("Import GGUF from Files", systemImage: "square.and.arrow.down") {
                showModelImporter = true
            }
            .disabled(isWorking)
        }
    }

    @ViewBuilder private var statusSection: some View {
        if activityState == nil, isWorking || phase != .idle {
            Section("Analysis Status") {
                HStack(spacing: DesignSystem.Spacing.small) {
                    if case .downloadingModel(let download) = phase,
                       let fraction = download.fraction {
                        ProgressView(value: fraction)
                            .frame(maxWidth: 120)
                    } else if isWorking {
                        ProgressView()
                    }
                    Text(phase.displayText(locale: locale))
                }
                if case .downloadingModel(let download) = phase {
                    LabeledContent("Download progress") {
                        Text(downloadProgressLabel(download))
                            .monospacedDigit()
                    }
                }
                if let draft, let provider = draft.providerName {
                    LabeledContent("Provider", value: providerLabel(provider))
                    if let model = draft.modelName { LabeledContent("Model", value: model) }
                }
            }
        }
    }

    @ViewBuilder
    private var activityOverlay: some View {
        AcademicAIActivityOverlay(
            state: activityState,
            onCancel: { cancelAll(cancelModelDownload: true) },
            isExpanded: $activityIsPressed
        )
    }

    @ViewBuilder private var sourcePreview: some View {
        if let document {
            Section("Source Preview") {
                ForEach(document.pages, id: \.number) { page in
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                        Text(
                            String(
                                format: AppLocalization.string("Page %lld", locale: locale),
                                Int64(page.number)
                            )
                        )
                        .font(.headline)
                        if let image = page.image {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous))
                        } else if let text = page.text {
                            Text(text).font(.caption).lineLimit(10).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func review(_ currentDraft: SyllabusImportDraft) -> some View {
        Section {
            reviewStatusRow(for: currentDraft)
            LabeledContent("Grading method", value: gradingModeLabel(currentDraft.gradingMode))
                // Section headers are not consistently materialized in the
                // iPad regular-width List accessibility tree. Keep the
                // review landmark on a concrete row as well so UI tests and
                // assistive navigation can reach the same content.
                .accessibilityIdentifier("syllabusReviewImportSection")
            LabeledContent("Categories found") {
                Text(
                    String(
                        format: AppLocalization.string("%lld grading categories", locale: locale),
                        Int64(currentDraft.categories.count)
                    )
                )
            }
            if currentDraft.weightTotal > 0 {
                LabeledContent("Weight total") {
                    Text("\(compact(currentDraft.weightTotal))%")
                }
            }
        } header: {
            Text("Extracted grading information")
                .accessibilityIdentifier("syllabusReviewImportSection")
        }

        Section {
            DisclosureGroup {
                ForEach(Array(currentDraft.categories.enumerated()), id: \.element.id) { index, category in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                            TextField("Category", text: categoryBinding(index, \.name))
                                .font(.headline)
                            HStack {
                                TextField("Weight", text: categoryWeightBinding(index))
                                    .keyboardType(.decimalPad)
                                Text("%").foregroundStyle(.secondary)
                                Spacer()
                            }
                            if let points = category.totalPoints {
                                LabeledContent("Total points", value: compact(points))
                            }
                            if category.dropLowestCount > 0 {
                                Label("Drop lowest: \(category.dropLowestCount)", systemImage: "arrow.down.to.line.compact")
                                    .font(.subheadline)
                            }
                            if let evidence = category.evidence { evidenceDisclosure(evidence) }
                            Button("Remove Category", role: .destructive) { draft?.categories.remove(at: index) }
                        }
                        .padding(.vertical, DesignSystem.Spacing.xSmall)
                    } label: {
                        HStack {
                            Text(category.name.isEmpty ? AppLocalization.string("Unnamed category", locale: locale) : category.name)
                            Spacer()
                            if let weight = category.weightPercent {
                                Text("\(compact(weight))%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else if category.totalPoints != nil {
                                Text(AppLocalization.string("Points", locale: locale))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Add Missing Category", systemImage: "plus") {
                    draft?.categories.append(
                        .init(name: "", normalizedType: .custom, weightPercent: nil, totalPoints: nil, parentCategory: nil, dropLowestCount: 0, isExtraCredit: false, evidence: nil, confidence: 1)
                    )
                }
            } label: {
                Label(
                    String(
                        format: AppLocalization.string("%lld grading categories", locale: locale),
                        Int64(currentDraft.categories.count)
                    ),
                    systemImage: "square.stack.3d.up"
                )
            }

            if !currentDraft.assessments.isEmpty {
                DisclosureGroup {
                    ForEach(Array(currentDraft.assessments.enumerated()), id: \.element.id) { index, assessment in
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                            Text(assessment.title).font(.headline)
                            if let category = assessment.category { Text(category).foregroundStyle(.secondary) }
                            if let points = assessment.possiblePoints { LabeledContent("Points", value: compact(points)) }
                            if let evidence = assessment.evidence { evidenceDisclosure(evidence) }
                            Button("Remove Item", role: .destructive) { draft?.assessments.remove(at: index) }
                        }
                        .padding(.vertical, DesignSystem.Spacing.xSmall)
                    }
                } label: {
                    Label(
                        String(
                            format: AppLocalization.string("%lld assignments and exams", locale: locale),
                            Int64(currentDraft.assessments.count)
                        ),
                        systemImage: "checklist"
                    )
                }
            }

            if !currentDraft.gradeScale.isEmpty {
                DisclosureGroup {
                    ForEach(currentDraft.gradeScale) { boundary in
                        LabeledContent(boundary.letterGrade.rawValue) {
                            Text(
                                String(
                                    format: AppLocalization.string("%@%% and above", locale: locale),
                                    compact(boundary.minimumPercent)
                                )
                            )
                        }
                    }
                } label: {
                    Label(
                        String(
                            format: AppLocalization.string("%lld grade scale levels", locale: locale),
                            Int64(currentDraft.gradeScale.count)
                        ),
                        systemImage: "textformat.123"
                    )
                }
            }

            if !currentDraft.rules.isEmpty {
                DisclosureGroup {
                    ForEach(currentDraft.rules) { rule in
                        DisclosureGroup {
                            if let category = rule.categoryName { LabeledContent("Category", value: category) }
                            ForEach(rule.evidence.indices, id: \.self) { index in
                                evidenceRow(rule.evidence[index])
                            }
                        } label: {
                            Label(rule.description, systemImage: "list.bullet.clipboard")
                        }
                    }
                } label: {
                    Label(
                        String(
                            format: AppLocalization.string("%lld grading rules", locale: locale),
                            Int64(currentDraft.rules.count)
                        ),
                        systemImage: "list.bullet.clipboard"
                    )
                }
            }
        } header: {
            Text("Edit extracted details")
        }

        Section {
            if !courseCategories.isEmpty || !courseItems.isEmpty {
                Label("Existing grades are kept", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Confirm & Import") { confirm() }
                .disabled(currentDraft.categories.isEmpty || didSave)
                .accessibilityIdentifier("confirmSyllabusRulesButton")
            Button("Analyze Again", systemImage: "arrow.clockwise") { analyze() }
                .disabled(isWorking || document == nil || !canAnalyze)
        } footer: {
            Text("You can edit the details before confirming.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private func reviewStatusRow(for currentDraft: SyllabusImportDraft) -> some View {
        let issues = reviewIssueMessages(for: currentDraft)
        if issues.isEmpty {
            Label("Ready to review", systemImage: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.ColorToken.success)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("syllabusReviewStatus")
        } else {
            DisclosureGroup {
                ForEach(issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Needs Review", locale: locale))
                        .font(.headline)
                    Text(
                        String(
                            format: AppLocalization.string(
                                issues.count == 1 ? "1 item needs your attention" : "%lld items need your attention",
                                locale: locale
                            ),
                            Int64(issues.count)
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("syllabusReviewStatus")
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.ColorToken.error)
            Button("Use Manual Rule Recognition") {
                if let source = manualSourceDocument {
                    document = source
                    analyze(mode: .localRules, document: source)
                }
            }
            .disabled(manualSourceDocument == nil || isWorking)
        }
    }

    private func evidenceDisclosure(_ evidence: SyllabusEvidence) -> some View {
        DisclosureGroup("View Source") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                Text(
                    String(
                        format: AppLocalization.string("Page %lld: %@", locale: locale),
                        Int64(evidence.page),
                        evidence.excerpt
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func evidenceRow(_ evidence: GradingEvidence) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let page = evidence.sourcePage {
                Text(
                    String(
                        format: AppLocalization.string("Page %lld", locale: locale),
                        Int64(page)
                    )
                )
                .font(.caption.bold())
            }
            Text(evidence.sourceText).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func reviewIssueMessages(for draft: SyllabusImportDraft) -> [String] {
        var issues: [String] = []
        if draft.categories.isEmpty {
            issues.append(AppLocalization.string("Grading categories not found", locale: locale))
        }
        if draft.gradingMode == .unknown || draft.weightTotal == 0 {
            issues.append(AppLocalization.string("Grading method needs confirmation", locale: locale))
        }
        if !draft.analysisWarnings.isEmpty {
            issues.append(AppLocalization.string("Check the extracted source details", locale: locale))
        }
        if issues.isEmpty && (draft.requiresReview || draft.overallConfidence < 0.75) {
            issues.append(AppLocalization.string("Review the extracted grading information", locale: locale))
        }
        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
    }

    private func load(_ url: URL) {
        documentLoadTask?.cancel()
        errorMessage = nil
        phase = .reading
        documentLoadTask = Task { @MainActor in
            defer { documentLoadTask = nil }
            do {
                let loadedDocument = try await Task.detached(priority: .userInitiated) {
                    try SyllabusTextExtractor.read(url: url)
                }.value
                try Task.checkCancellation()
                document = loadedDocument
                if canAnalyze { analyze(document: loadedDocument) }
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }

    private func load(_ images: [UIImage]) {
        do {
            document = try SyllabusTextExtractor.read(images: images)
            if canAnalyze { analyze() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) {
        photoLoadTask?.cancel()
        errorMessage = nil
        photoLoadTask = Task {
            defer { photoLoadTask = nil; selectedPhotos = [] }
            do {
                var images: [UIImage] = []
                for item in items {
                    try Task.checkCancellation()
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
                    images.append(image)
                }
                guard !images.isEmpty else { throw SyllabusTextExtractor.ExtractionError.noReadableContent }
                load(images)
            } catch is CancellationError {
                phase = .idle
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func downloadModel() {
        modelTask?.cancel()
        errorMessage = nil
        phase = .downloadingModel(.starting)
        modelTask = Task {
            defer { modelTask = nil }
            do {
                _ = try await OnDeviceAIModelLibrary.prepareRecommended { download in
                    Task { @MainActor in phase = .downloadingModel(download) }
                }
                await refreshModelState()
                phase = .idle
            } catch is CancellationError {
                await refreshModelState()
                phase = .idle
            } catch {
                await refreshModelState()
                modelAvailability = .downloadRequired
                let message = localizedModelError(error)
                phase = .unavailable(message)
                errorMessage = message
            }
        }
    }

    private func importModel(_ url: URL) {
        modelTask?.cancel()
        errorMessage = nil
        phase = .loadingModel
        modelTask = Task {
            defer { modelTask = nil }
            do {
                _ = try await OnDeviceAIModelLibrary.importModel(from: url)
                modelAvailability = .available
                phase = .idle
            } catch is CancellationError {
                phase = .idle
            } catch {
                modelAvailability = .downloadRequired
                let message = localizedModelError(error)
                phase = .unavailable(message)
                errorMessage = message
            }
        }
    }

    private func analyze() {
        guard let document else { return }
        analyze(document: document)
    }

    private func analyze(document: SyllabusTextExtractor.Document) {
        let mode: SyllabusAnalysisMode = usesTestProvider ? .localRules : .onDevice
        analyze(mode: mode, document: document)
    }

    private func analyze(mode: SyllabusAnalysisMode, document: SyllabusTextExtractor.Document) {
        guard mode == .localRules || canAnalyze else {
            errorMessage = OnDeviceSyllabusParser.availability().message(locale: locale)
            return
        }
        analysisTask?.cancel()
        errorMessage = nil
        draft = nil
        didSave = false
        phase = .reading
        analysisTask = Task {
            defer { analysisTask = nil }
            do {
                let output = try await OnDeviceSyllabusParser.extract(document: document, mode: mode) { newPhase in
                    Task { @MainActor in phase = newPhase }
                }
                try Task.checkCancellation()
                draft = output
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .unavailable(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshModelState() async {
        let runtimeAvailability = OnDeviceSyllabusParser.availability(locale: locale)
        let storeSnapshot = await OnDeviceAIModelLibrary.snapshot()
        modelSnapshot = storeSnapshot

        guard runtimeAvailability != .runtimeUnavailable else {
            modelAvailability = .runtimeUnavailable
            return
        }
        modelAvailability = recommendedModelRecord?.state == .ready ? .available : .downloadRequired
    }

    private func cancelAll(cancelModelDownload: Bool) {
        analysisTask?.cancel()
        documentLoadTask?.cancel()
        photoLoadTask?.cancel()
        if cancelModelDownload {
            modelTask?.cancel()
            Task { await OnDeviceAIModelLibrary.cancelRecommendedDownload() }
        }
        analysisTask = nil
        documentLoadTask = nil
        photoLoadTask = nil
        if cancelModelDownload { modelTask = nil }
        activityIsPressed = false
        if phase != .complete && phase != .needsReview { phase = .idle }
    }

    private func confirm() {
        guard let draft else { return }
        let policy = policies.first { $0.course?.persistentModelID == course.persistentModelID } ?? CourseGradingPolicy(course: course)
        if policy.modelContext == nil { modelContext.insert(policy) }
        switch draft.gradingMode {
        case .weightedCategories: policy.gradingMethod = .weightedCategories
        case .pointsBased: policy.gradingMethod = .totalPoints
        case .mixed: policy.gradingMethod = .hybrid
        case .unknown: policy.gradingMethod = draft.categories.contains { $0.weightPercent != nil } ? .weightedCategories : .totalPoints
        }
        policy.syllabusImportSource = draft.source
        policy.importStatus = .confirmed
        policy.manualReviewReason = (draft.analysisWarnings.map(\.message) + draft.rules.map(\.description)).joined(separator: "\n")
        // Keep the extracted text and page boundaries with the course. This
        // is the local source used by the later Course Detail Ask/Search
        // action; it avoids making students select the same PDF again.
        if let document { SyllabusSourceStore.save(document: document, for: policy.id) }
        policy.updatedAt = .now

        var categoriesByName = Dictionary(uniqueKeysWithValues: courseCategories.map { ($0.name.lowercased(), $0) })
        for (index, candidate) in draft.categories.enumerated() {
            let key = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, categoriesByName[key] == nil else { continue }
            let category = GradingCategory(
                course: course,
                name: candidate.name,
                categoryType: candidate.normalizedType,
                weight: candidate.weightPercent ?? 0,
                calculationMode: candidate.weightPercent == nil ? .totalPoints : .weightedCategory,
                dropLowestCount: candidate.dropLowestCount,
                isExtraCredit: candidate.isExtraCredit,
                sortOrder: courseCategories.count + index
            )
            modelContext.insert(category)
            categoriesByName[key] = category
        }
        for assessment in draft.assessments where !courseItems.contains(where: { $0.title.caseInsensitiveCompare(assessment.title) == .orderedSame }) {
            let category = assessment.category.flatMap { categoriesByName[$0.lowercased()] }
            modelContext.insert(
                GradeItem(
                    course: course,
                    category: category,
                    title: assessment.title,
                    dueDate: assessment.dueDate,
                    possiblePoints: assessment.possiblePoints ?? 0,
                    percentageOverride: assessment.weightPercent,
                    isExtraCredit: assessment.type == .extraCredit
                )
            )
        }
        if !draft.gradeScale.isEmpty {
            let scale = scales.first { $0.course?.persistentModelID == course.persistentModelID } ?? GradeScale(course: course)
            if scale.modelContext == nil { modelContext.insert(scale) }
            scale.name = "Syllabus Scale"
            scale.boundaries = draft.gradeScale.map { .init(letter: $0.letterGrade, minimumPercentage: $0.minimumPercent) }
            scale.requiresManualReview = false
        }

        do {
            try modelContext.save()
            didSave = true
        } catch {
            modelContext.rollback()
            errorMessage = String(
                format: AppLocalization.string("The confirmed import could not be saved: %@", locale: locale),
                error.localizedDescription
            )
        }
    }

    private func courseBinding(_ keyPath: WritableKeyPath<SyllabusCourseInformation, String?>) -> Binding<String> {
        Binding(get: { draft?.courseInformation[keyPath: keyPath] ?? "" }, set: { draft?.courseInformation[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func categoryBinding(_ index: Int, _ keyPath: WritableKeyPath<SyllabusCategoryDraft, String>) -> Binding<String> {
        Binding(get: { draft?.categories[index][keyPath: keyPath] ?? "" }, set: { draft?.categories[index][keyPath: keyPath] = $0 })
    }

    private func categoryWeightBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft?.categories[index].weightPercent.map(compact) ?? "" }, set: { draft?.categories[index].weightPercent = DecimalFormatters.decimal(from: $0) })
    }

    private func gradingModeLabel(_ mode: AnalyzedGradingMode) -> String {
        switch mode {
        case .weightedCategories: AppLocalization.string("Weighted Categories", locale: locale)
        case .pointsBased: AppLocalization.string("Points Based", locale: locale)
        case .mixed: AppLocalization.string("Mixed Grading", locale: locale)
        case .unknown: AppLocalization.string("Needs Review", locale: locale)
        }
    }

    private var manualSourceDocument: SyllabusTextExtractor.Document? {
        if let document { return document }
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return .init(pages: [.init(number: 1, text: text, image: nil)], source: .pastedText)
    }

    private func secondsLabel(_ seconds: Double) -> String {
        String(format: AppLocalization.string("%.2f s", locale: locale), seconds)
    }

    private func downloadProgressLabel(_ progress: ModelDownloadProgress) -> String {
        let received = ByteCountFormatter.string(fromByteCount: progress.receivedBytes, countStyle: .file)
        let expected = ByteCountFormatter.string(fromByteCount: progress.expectedBytes, countStyle: .file)
        let percent = Int(((progress.fraction ?? 0) * 100).rounded())
        return String(
            format: AppLocalization.string("%1$lld%% · %2$@ of %3$@", locale: locale),
            Int64(percent),
            received,
            expected
        )
    }

    private func thermalStateLabel(_ state: String) -> String {
        switch state {
        case "nominal": AppLocalization.string("Normal", locale: locale)
        case "fair": AppLocalization.string("Warm", locale: locale)
        case "serious": AppLocalization.string("Hot", locale: locale)
        case "critical": AppLocalization.string("Very Hot", locale: locale)
        default: AppLocalization.string("Unknown", locale: locale)
        }
    }

    private func providerLabel(_ provider: String) -> String {
        switch provider {
        case "Local Rule Recognition":
            AppLocalization.string("Local Rule Recognition", locale: locale)
        default:
            provider
        }
    }

    private func localizedModelError(_ error: any Error) -> String {
        if let providerError = error as? ProviderError {
            return providerError.message(locale: locale)
        }
        if let modelError = error as? AIModelStoreError {
            return modelError.message(locale: locale)
        }
        return error.localizedDescription
    }
}

private struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.completion((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            parent.dismiss()
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) { parent.dismiss() }
    }
}
