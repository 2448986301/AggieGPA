import SwiftUI

/// A small, course-scoped question surface for a syllabus that has already
/// been imported. It deliberately performs evidence-first local retrieval from
/// the course's saved text/page source and never asks the student to pick the
/// same PDF again.
struct SyllabusQuestionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let course: CourseRecord
    let policy: CourseGradingPolicy?
    let source: SyllabusSourceStore.StoredSource?
    private let document: SyllabusTextExtractor.Document?

    @State private var query = ""
    @State private var result: SyllabusPolicySearchResult?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    init(
        course: CourseRecord,
        policy: CourseGradingPolicy?,
        source: SyllabusSourceStore.StoredSource?
    ) {
        self.course = course
        self.policy = policy
        self.source = source
        let sourceKind: SyllabusImportSource = {
            source?.source ?? policy?.syllabusImportSource ?? .pastedText
        }()
        self.document = SyllabusTextExtractor.document(
            storedPageData: source?.pagesData,
            fallbackText: source?.sourceText,
            source: sourceKind
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(
                        AppLocalization.string("Ask a question about this syllabus", locale: locale),
                        text: $query,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("syllabusPolicyQuery")

                    Button(AppLocalization.string("Ask", locale: locale), systemImage: "magnifyingglass") {
                        search()
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching || document == nil)
                    .accessibilityIdentifier("searchSyllabusPolicyButton")
                } header: {
                    Label(
                        AppLocalization.string("Ask about this syllabus", locale: locale),
                        systemImage: "text.book.closed"
                    )
                } footer: {
                    Text(AppLocalization.string("Answers use the syllabus saved for this course and show the source page.", locale: locale))
                }

                if isSearching {
                    Section {
                        AcademicAIActivityView(
                            state: .searchingSyllabus,
                            allowsCancellation: true,
                            onCancel: { cancelSearch() }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                if let result {
                    resultSection(result)
                }
            }
            .navigationTitle(AppLocalization.string("Ask about this syllabus", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Done", locale: locale)) {
                        cancelSearch()
                        dismiss()
                    }
                }
            }
            .onDisappear { cancelSearch() }
        }
    }

    @ViewBuilder
    private func resultSection(_ result: SyllabusPolicySearchResult) -> some View {
        switch result.status {
        case .emptyQuery:
            EmptyView()
        case .noMatchingEvidence:
            Section {
                Label(
                    AppLocalization.string("No matching syllabus policy was found.", locale: locale),
                    systemImage: "questionmark.circle"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("syllabusPolicyNoEvidence")
            }
        case .evidenceFound:
            Section {
                Text(answerText(for: result))
                    .textSelection(.enabled)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("syllabusPolicyExplanation")

                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(evidenceSummary(result.matches.count))
                }
                .font(.subheadline)
                .foregroundStyle(DesignSystem.ColorToken.success)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("syllabusPolicyEvidenceSummary")
            } header: {
                Label(AppLocalization.string("Answer from syllabus", locale: locale), systemImage: "text.book.closed")
                    .accessibilityIdentifier("syllabusPolicyResult")
            }

            Section {
                ForEach(result.matches) { evidence in
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                        Text(pageLabel(evidence.page))
                            .font(.subheadline.weight(.semibold))
                        Text(evidence.sourceText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        String(
                            format: AppLocalization.string("Page %lld: %@", locale: locale),
                            Int64(evidence.page),
                            evidence.sourceText
                        )
                    )
                    .accessibilityIdentifier("syllabusPolicyEvidence-\(evidence.page)")
                }
            } header: {
                Label(AppLocalization.string("Syllabus Evidence", locale: locale), systemImage: "quote.opening")
            }
        }
    }

    private func search() {
        guard let document else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        isSearching = true
        result = nil
        searchTask = Task { @MainActor in
            // Yield once so the text field/button responds immediately before
            // the in-memory index begins its work off the main actor.
            await Task.yield()
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                SyllabusPolicySearchEngine.searchSemantic(query: trimmed, in: document)
            }.value
            guard !Task.isCancelled else { return }
            result = found
            isSearching = false
            searchTask = nil
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    private func answerText(for result: SyllabusPolicySearchResult) -> String {
        let intro = String(
            format: AppLocalization.string(
                "The cited syllabus text answers \"%@\". Check the page before relying on it.",
                locale: locale
            ),
            result.query
        )
        let excerpts = result.matches.prefix(2).map {
            String(
                format: AppLocalization.string("Page %lld: %@", locale: locale),
                Int64($0.page),
                $0.sourceText
            )
        }.joined(separator: "\n")
        return excerpts.isEmpty ? intro : "\(intro)\n\n\(excerpts)"
    }

    private func pageLabel(_ page: Int) -> String {
        String(format: AppLocalization.string("Page %lld", locale: locale), Int64(page))
    }

    private func evidenceSummary(_ count: Int) -> String {
        if count == 1 { return AppLocalization.string("1 source found", locale: locale) }
        return String(format: AppLocalization.string("%lld sources found", locale: locale), Int64(count))
    }
}
