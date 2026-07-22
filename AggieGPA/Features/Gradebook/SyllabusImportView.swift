import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct SyllabusImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var policies: [CourseGradingPolicy]
    @Query private var existingCategories: [GradingCategory]
    @Query private var scales: [GradeScale]
    let course: CourseRecord

    @State private var sourceText = ""
    @State private var result: SyllabusParseResult?
    @State private var source = SyllabusImportSource.pastedText
    @State private var showFileImporter = false
    @State private var showScanner = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didSave = false
    @State private var modelStatus = OnDeviceSyllabusParser.availability()

    private var courseCategories: [GradingCategory] { existingCategories.filter { $0.course?.persistentModelID == course.persistentModelID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    HStack {
                        Button("Choose PDF or Image", systemImage: "folder") { showFileImporter = true }
                        Spacer()
                        if VNDocumentCameraViewController.isSupported {
                            Button("Scan", systemImage: "doc.viewfinder") { showScanner = true }
                        }
                    }
                    TextEditor(text: $sourceText)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if sourceText.isEmpty { Text("Paste syllabus grading rules here").foregroundStyle(.tertiary).padding(.top, 8).allowsHitTesting(false) }
                        }
                        .accessibilityIdentifier("syllabusTextEditor")
                    Button("Extract Rules", systemImage: "sparkles") { parse() }
                        .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                        .accessibilityIdentifier("parseSyllabusButton")
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Refine with On-Device Model", systemImage: "apple.intelligence") {
                            Task { await refineOnDevice() }
                        }
                        .disabled(modelStatus != .available || sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                        Text(modelStatus.message).font(.caption).foregroundStyle(.secondary)
                        Text("Optional. The syllabus stays on this device; deterministic checks and your confirmation still apply.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if isWorking { Section { ProgressView("Reading syllabus on this device…") } }
                if let result { review(result) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                if didSave {
                    Section { Label("Confirmed grading rules saved.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Import Syllabus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(didSave ? "Done" : "Cancel") { dismiss() } } }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image]) { selection in
                guard case .success(let url) = selection else { return }
                source = url.pathExtension.lowercased() == "pdf" ? .pdf : .image
                Task { await extract(url) }
            }
            .sheet(isPresented: $showScanner) {
                DocumentScannerView { images in
                    source = .camera
                    Task { await extract(images) }
                }
            }
        }
    }

    @ViewBuilder private func review(_ parsed: SyllabusParseResult) -> some View {
        Section("Recognition Preview") {
            LabeledContent("Confidence", value: "\(Int((parsed.confidence * 100).rounded()))%")
            LabeledContent("Suggested method", value: parsed.suggestedMethod.displayName)
            ForEach(parsed.categories.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Category", text: categoryBinding(index, \.name)).font(.headline)
                    HStack {
                        if parsed.categories[index].weight != nil {
                            TextField("Weight", text: decimalBinding(index, keyPath: \.weight)).keyboardType(.decimalPad)
                            Text("%")
                        } else {
                            Text("\(compact(parsed.categories[index].possiblePoints ?? 0)) possible points")
                        }
                        Spacer()
                        Text("\(Int((parsed.categories[index].confidence * 100).rounded()))%")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Recognition confidence")
                            .accessibilityValue("\(Int((parsed.categories[index].confidence * 100).rounded())) percent")
                    }
                    Text(parsed.categories[index].sourceLine).font(.caption2).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
        }
        if !parsed.manualReviewReasons.isEmpty {
            Section("Manual Review Required") {
                ForEach(parsed.manualReviewReasons, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Manual review required")
        }
        Section("Original Text") {
            DisclosureGroup("Show extracted text") { Text(parsed.sourceText).font(.caption).textSelection(.enabled) }
        }
        Section {
            Text("Please verify these rules against your syllabus.").font(.headline)
            if !courseCategories.isEmpty {
                Text("This course already has categories. To avoid silently overwriting entered work, merge the recognized rules manually.")
                    .foregroundStyle(.orange)
            }
            Button("Confirm and Save Rules") { confirm() }
                .disabled(parsed.categories.isEmpty || !courseCategories.isEmpty || didSave)
                .accessibilityIdentifier("confirmSyllabusRulesButton")
        }
    }

    private func parse(confidence: Double = 1) {
        result = SyllabusRuleParser.parse(sourceText, extractionConfidence: confidence)
        errorMessage = nil
    }

    private func extract(_ url: URL) async {
        isWorking = true; defer { isWorking = false }
        do {
            let extraction = try await SyllabusTextExtractor.extract(from: url)
            sourceText = extraction.text; parse(confidence: extraction.confidence)
        } catch { errorMessage = error.localizedDescription }
    }

    private func extract(_ images: [UIImage]) async {
        isWorking = true; defer { isWorking = false }
        do {
            var texts: [String] = []; var confidences: [Double] = []
            for image in images {
                guard let cgImage = image.cgImage else { continue }
                let extraction = try await SyllabusTextExtractor.recognize(cgImage)
                texts.append(extraction.text); confidences.append(extraction.confidence)
            }
            sourceText = texts.joined(separator: "\n")
            parse(confidence: confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count))
        } catch { errorMessage = error.localizedDescription }
    }

    private func refineOnDevice() async {
        isWorking = true; defer { isWorking = false }
        do {
            result = try await OnDeviceSyllabusParser.parse(sourceText)
            errorMessage = nil
        } catch {
            modelStatus = OnDeviceSyllabusParser.availability()
            errorMessage = "On-device refinement was unavailable. Local rule parsing still works: \(error.localizedDescription)"
            parse()
        }
    }

    private func confirm() {
        guard let result, courseCategories.isEmpty else { return }
        let policy = policies.first { $0.course?.persistentModelID == course.persistentModelID } ?? CourseGradingPolicy(course: course)
        if policy.modelContext == nil { modelContext.insert(policy) }
        policy.gradingMethod = result.suggestedMethod
        policy.syllabusImportSource = source
        policy.importStatus = result.requiresManualReview ? .needsReview : .confirmed
        policy.manualReviewReason = result.manualReviewReasons.joined(separator: "\n")
        policy.updatedAt = .now
        for (index, candidate) in result.categories.enumerated() {
            let category = GradingCategory(
                course: course, name: candidate.name, categoryType: candidate.categoryType,
                weight: candidate.weight ?? 0, calculationMode: candidate.calculationMode,
                dropLowestCount: result.dropLowestCategoryNames.contains { candidate.name.localizedCaseInsensitiveContains($0) } ? 1 : 0,
                isExtraCredit: candidate.categoryType == .extraCredit, sortOrder: index
            )
            modelContext.insert(category)
        }
        if !result.gradeBoundaries.isEmpty {
            let scale = scales.first { $0.course?.persistentModelID == course.persistentModelID } ?? GradeScale(course: course)
            if scale.modelContext == nil { modelContext.insert(scale) }
            scale.name = "Syllabus Scale"; scale.boundaries = result.gradeBoundaries
            scale.isCommonTemplate = false; scale.requiresManualReview = result.requiresManualReview
        }
        do { try modelContext.save(); didSave = true }
        catch { errorMessage = "The confirmed rules could not be saved: \(error.localizedDescription)" }
    }

    private func categoryBinding(_ index: Int, _ keyPath: WritableKeyPath<SyllabusCategoryCandidate, String>) -> Binding<String> {
        Binding(get: { result?.categories[index][keyPath: keyPath] ?? "" }, set: { result?.categories[index][keyPath: keyPath] = $0 })
    }

    private func decimalBinding(_ index: Int, keyPath: WritableKeyPath<SyllabusCategoryCandidate, Decimal?>) -> Binding<String> {
        Binding(get: { result?.categories[index][keyPath: keyPath].map(compact) ?? "" }, set: { result?.categories[index][keyPath: keyPath] = DecimalFormatters.decimal(from: $0) })
    }
}

private extension GradingMethod {
    var displayName: String {
        switch self { case .weightedCategories: "Weighted categories"; case .totalPoints: "Total points"; case .hybrid: "Hybrid"; case .manualLetterGradeOnly: "Manual letter only" }
    }
}

private struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.completion((0..<scan.pageCount).map { scan.imageOfPage(at: $0) }); parent.dismiss()
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) { parent.dismiss() }
    }
}
