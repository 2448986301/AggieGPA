import AppIntents
import Foundation
import SwiftUI

/// iOS 27's system search schema gives Siri a native, non-App-Shortcut route
/// into Aggie GPA. It is intentionally limited to app content search; grades
/// and GPA remain custom intents because the SDK has no education schema.
@AppIntent(schema: .system.searchInApp)
struct SearchAggieGPAIntent: ShowInAppSearchResultsIntent {
    var criteria: StringSearchCriteria

    init() {
        criteria = StringSearchCriteria(term: "")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let term = criteria.term.trimmingCharacters(in: .whitespacesAndNewlines)
        SiriExecutionTrace.record("schema-search-started")
        PendingSiriNavigationStore.save(.init(kind: .search, query: term))
        NotificationCenter.default.post(name: .openSearchFromSiri, object: term)
        let normalized = term.lowercased()
        if normalized.contains("assignment") || normalized.contains("homework") || normalized.contains("作业") {
            let items = SiriSharedSnapshotStore.upcomingAssignments(days: 7) ?? []
            let dialog = items.isEmpty
                ? "No assignments are due in the next seven days."
                : items.map { "\($0.courseCode) \($0.title)" }.joined(separator: "; ")
            SiriExecutionTrace.record("schema-search-completed", itemCount: items.count)
            return .result(dialog: IntentDialog(stringLiteral: dialog), view: UpcomingAssignmentsSnippetView(items: items))
        }

        let dialog = term.isEmpty ? "Open Aggie GPA to search your courses and coursework." : "Searching Aggie GPA for \(term)."
        SiriExecutionTrace.record("schema-search-completed")
        return .result(dialog: IntentDialog(stringLiteral: dialog), view: AggieGPASearchSnippetView(query: term))
    }
}

private nonisolated struct AggieGPASearchSnippetView: View {
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Aggie GPA", systemImage: "magnifyingglass")
                .font(.headline)
            Text(query.isEmpty ? "Courses and coursework" : query)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
