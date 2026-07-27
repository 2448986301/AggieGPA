import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VisionKit
import PhotosUI

struct SyllabusImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var policies: [CourseGradingPolicy]
    @Query private var existingCategories: [GradingCategory]
    @Query private var existingItems: [GradeItem]
    @Query private var scales: [GradeScale]
    let course: CourseRecord

    @State private var pastedText = ""
    @State private var document: SyllabusTextExtractor.Document?
    @State private var draft: SyllabusImportDraft?
    @State private var phase: SyllabusAnalysisPhase = .idle
    @State private var task: Task<Void, Never>?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @State private var showScanner = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var didSave = false

    private var isWorking: Bool { task != nil || photoLoadTask != nil }
    private var courseCategories: [GradingCategory] { existingCategories.filter { $0.course?.persistentModelID == course.persistentModelID } }
    private var courseItems: [GradeItem] { existingItems.filter { $0.course?.persistentModelID == course.persistentModelID } }

    var body: some View {
        NavigationStack {
            List {
                sourceSection
                statusSection
                if let draft { review(draft) }
                if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(DesignSystem.ColorToken.error) } }
            }
            .navigationTitle("Import Syllabus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(didSave ? "Done" : "Cancel") { task?.cancel(); photoLoadTask?.cancel(); dismiss() } }
                if isWorking { ToolbarItem(placement: .confirmationAction) { Button("Cancel Analysis") { task?.cancel(); photoLoadTask?.cancel() } } }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image, .plainText]) { selection in
                guard case .success(let url) = selection else { return }
                load(url)
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                loadSelectedPhotos(items)
            }
            .sheet(isPresented: $showScanner) { DocumentScannerView { images in load(images) } }
        }
    }

    private var sourceSection: some View {
        Section("Syllabus Source") {
            Button("Choose PDF, Image, or Text", systemImage: "folder") {
                showFileImporter = true
            }
            .disabled(isWorking)

            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            .disabled(isWorking)

            if VNDocumentCameraViewController.isSupported {
                Button("Scan Pages", systemImage: "doc.viewfinder") {
                    showScanner = true
                }
                .disabled(isWorking)
            }

            Text("Choose a PDF, photos, or scanned pages. Text-based PDFs keep their original text; no OCR is used.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $pastedText).frame(minHeight: 120).overlay(alignment: .topLeading) {
                if pastedText.isEmpty { Text("Paste syllabus text").foregroundStyle(.tertiary).padding(.top, 8).allowsHitTesting(false) }
            }
            Button("Analyze Pasted Text", systemImage: "apple.intelligence") { document = .init(pages: [.init(number: 1, text: pastedText, image: nil)], source: .pastedText); analyze(mode: .onDevice) }
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            if OnDeviceSyllabusParser.availability() != .available {
                Label(OnDeviceSyllabusParser.availability().message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("You can paste text and create the grading method manually. OCR is not used.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var statusSection: some View {
        if isWorking || phase != .idle {
            Section("Analysis Status") {
                if isWorking { HStack { ProgressView(); Text(LocalizedStringKey(phase.localizationKey)) } } else { Text(LocalizedStringKey(phase.localizationKey)) }
                if OnDeviceSyllabusParser.availability() == .available { Label("Using the on-device Apple Intelligence model", systemImage: "apple.intelligence").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private func review(_ draft: SyllabusImportDraft) -> some View {
        Section("Review Import") {
            LabeledContent("Weight total", value: "\(compact(draft.weightTotal))%")
            if draft.weightTotal != 0 && draft.weightTotal != 100 { Label("Recognized category weights do not total 100%.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            TextField("Course code", text: courseBinding(\.courseCode))
            TextField("Course title", text: courseBinding(\.courseTitle))
        }
        Section("Grading Categories") {
            ForEach(draft.categories.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Category", text: categoryBinding(index, \.name)).font(.headline)
                    HStack { TextField("Weight", text: categoryWeightBinding(index)).keyboardType(.decimalPad); Text("%"); Spacer(); confidence(draft.categories[index].confidence) }
                    if let evidence = draft.categories[index].evidence { evidenceView(evidence) }
                    Button("Remove", role: .destructive) { self.draft?.categories.remove(at: index) }
                }
            }
        }
        if !draft.assessments.isEmpty { Section("Assignments and Exams") { ForEach(draft.assessments) { assessment in VStack(alignment: .leading) { Text(assessment.title); if let evidence = assessment.evidence { evidenceView(evidence) }; confidence(assessment.confidence) } } } }
        if !draft.gradeScale.isEmpty { Section("Grade Scale") { ForEach(draft.gradeScale) { Text("\($0.letterGrade.rawValue)  \(compact($0.minimumPercent))%") } } }
        if !draft.issues.isEmpty { Section("Needs Your Review") { ForEach(draft.issues) { issue in Label(issue.reason, systemImage: "exclamationmark.triangle") } } }
        Section {
            if !courseCategories.isEmpty || !courseItems.isEmpty { Text("This course already has grading data. Confirm Import will add only the reviewed categories and assessments; it will not replace existing records.").foregroundStyle(.orange) }
            Button("Confirm Import") { confirm() }.disabled(draft.categories.isEmpty || didSave)
                .accessibilityIdentifier("confirmSyllabusRulesButton")
            Text("Nothing is written to this course until you choose Confirm Import.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func confidence(_ value: Double) -> some View { Text("\(Int((value * 100).rounded()))%").font(.caption).foregroundStyle(value < 0.75 ? .orange : .secondary) }
    private func evidenceView(_ evidence: SyllabusEvidence) -> some View { Text("Page \(evidence.page): \(evidence.excerpt)").font(.caption).foregroundStyle(.secondary).lineLimit(3) }

    private func load(_ url: URL) { do { document = try SyllabusTextExtractor.read(url: url); analyze(mode: .onDevice) } catch { errorMessage = error.localizedDescription } }
    private func load(_ images: [UIImage]) { do { document = try SyllabusTextExtractor.read(images: images); analyze(mode: .onDevice) } catch { errorMessage = error.localizedDescription } }
    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) {
        photoLoadTask?.cancel()
        errorMessage = nil
        photoLoadTask = Task {
            defer { photoLoadTask = nil; selectedPhotos = [] }
            do {
                var images: [UIImage] = []
                for item in items {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    guard let image = UIImage(data: data) else { continue }
                    images.append(image)
                }
                guard !images.isEmpty else {
                    throw SyllabusTextExtractor.ExtractionError.noReadableContent
                }
                guard !Task.isCancelled else { return }
                load(images)
            } catch is CancellationError {
                phase = .idle
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    private func analyze(mode: SyllabusAnalysisMode) {
        guard let document else { return }
        errorMessage = nil; draft = nil; phase = .reading
        task = Task {
            defer { task = nil }
            do { let output = try await OnDeviceSyllabusParser.extract(document: document, mode: mode) { phase = $0 }; if !Task.isCancelled { draft = output } }
            catch is CancellationError { phase = .idle }
            catch { phase = .unavailable(error.localizedDescription); errorMessage = error.localizedDescription }
        }
    }

    private func confirm() {
        guard let draft else { return }
        let policy = policies.first { $0.course?.persistentModelID == course.persistentModelID } ?? CourseGradingPolicy(course: course)
        if policy.modelContext == nil { modelContext.insert(policy) }
        policy.gradingMethod = draft.categories.contains { $0.weightPercent != nil } ? .weightedCategories : .totalPoints
        policy.syllabusImportSource = draft.source; policy.importStatus = draft.requiresReview ? .needsReview : .confirmed; policy.manualReviewReason = draft.issues.map(\.reason).joined(separator: "\n"); policy.updatedAt = .now
        for (index, candidate) in draft.categories.enumerated() where !courseCategories.contains(where: { $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame }) {
            modelContext.insert(GradingCategory(course: course, name: candidate.name, categoryType: candidate.normalizedType, weight: candidate.weightPercent ?? 0, calculationMode: candidate.weightPercent == nil ? .totalPoints : .weightedCategory, dropLowestCount: candidate.dropLowestCount, isExtraCredit: candidate.isExtraCredit, sortOrder: courseCategories.count + index))
        }
        let categoriesByName = Dictionary(uniqueKeysWithValues: existingCategories.filter { $0.course?.persistentModelID == course.persistentModelID }.map { ($0.name.lowercased(), $0) })
        for assessment in draft.assessments where !courseItems.contains(where: { $0.title.caseInsensitiveCompare(assessment.title) == .orderedSame }) {
            let category = assessment.category.flatMap { categoriesByName[$0.lowercased()] }
            modelContext.insert(GradeItem(course: course, category: category, title: assessment.title, dueDate: assessment.dueDate, possiblePoints: assessment.possiblePoints ?? 0, percentageOverride: assessment.weightPercent, isExtraCredit: assessment.type == .extraCredit))
        }
        if !draft.gradeScale.isEmpty {
            let scale = scales.first { $0.course?.persistentModelID == course.persistentModelID } ?? GradeScale(course: course)
            if scale.modelContext == nil { modelContext.insert(scale) }
            scale.name = "Syllabus Scale"; scale.boundaries = draft.gradeScale.map { .init(letter: $0.letterGrade, minimumPercentage: $0.minimumPercent) }; scale.requiresManualReview = draft.requiresReview
        }
        do { try modelContext.save(); didSave = true } catch { errorMessage = String(localized: "The confirmed import could not be saved: \(error.localizedDescription)") }
    }

    private func courseBinding(_ keyPath: WritableKeyPath<SyllabusCourseInformation, String?>) -> Binding<String> { Binding(get: { draft?.courseInformation[keyPath: keyPath] ?? "" }, set: { draft?.courseInformation[keyPath: keyPath] = $0.isEmpty ? nil : $0 }) }
    private func categoryBinding(_ index: Int, _ keyPath: WritableKeyPath<SyllabusCategoryDraft, String>) -> Binding<String> { Binding(get: { draft?.categories[index][keyPath: keyPath] ?? "" }, set: { draft?.categories[index][keyPath: keyPath] = $0 }) }
    private func categoryWeightBinding(_ index: Int) -> Binding<String> { Binding(get: { draft?.categories[index].weightPercent.map(compact) ?? "" }, set: { draft?.categories[index].weightPercent = DecimalFormatters.decimal(from: $0) }) }
}

private struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController { let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView; init(parent: DocumentScannerView) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) { parent.completion((0..<scan.pageCount).map { scan.imageOfPage(at: $0) }); parent.dismiss() }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) { parent.dismiss() }
    }
}
