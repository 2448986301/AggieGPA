import SwiftData
import SwiftUI

struct SiriDraftConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var courses: [CourseRecord]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    let draft: SiriDraftPayload
    @State private var possibleText: String
    @State private var errorMessage: String?

    init(draft: SiriDraftPayload) {
        self.draft = draft
        _possibleText = State(initialValue: draft.possiblePoints.map { String($0) } ?? "")
    }

    private var course: CourseRecord? { UUID(uuidString: draft.courseID).flatMap { id in courses.first { $0.id == id } } }
    private var matchingItems: [GradeItem] { items.filter { $0.course?.id == course?.id && $0.title.caseInsensitiveCompare(draft.title) == .orderedSame } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Siri Draft") {
                    LabeledContent("Action", value: actionName)
                    LabeledContent("Course", value: course?.courseCode ?? "Course no longer exists")
                    LabeledContent("Title", value: draft.title)
                    if let dueDate = draft.dueDate { LabeledContent("Due", value: dueDate.formatted(date: .abbreviated, time: .shortened)) }
                    if let earned = draft.earnedPoints { LabeledContent("Earned", value: String(earned)) }
                    TextField("Possible points", text: $possibleText).keyboardType(.decimalPad)
                }
                Section {
                    Text("Nothing has been written yet. Review this summary, then confirm or discard the draft.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if draft.kind == .recordGrade && matchingItems.count != 1 {
                        Text(matchingItems.isEmpty ? "The matching grade item no longer exists." : "Multiple grade items match this title. Open the course and choose one manually.")
                            .foregroundStyle(.orange)
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Confirm Siri Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Discard", role: .destructive) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm and Save") { confirm() }
                        .disabled(course == nil || (draft.kind == .recordGrade && matchingItems.count != 1))
                        .accessibilityIdentifier("confirmSiriDraftButton")
                }
            }
        }
    }

    private var actionName: String {
        switch draft.kind { case .assignment: "Create Assignment"; case .exam: "Create Exam"; case .recordGrade: "Record Grade" }
    }

    private func confirm() {
        guard let course else { errorMessage = "The selected course no longer exists."; return }
        guard let possible = DecimalFormatters.decimal(from: possibleText), possible > 0 else { errorMessage = "Enter possible points greater than zero."; return }
        switch draft.kind {
        case .assignment, .exam:
            let desiredType: GradeCategoryType = draft.kind == .exam ? .midterm : .homework
            let category = categories.first { $0.course?.id == course.id && $0.categoryType == desiredType }
            modelContext.insert(GradeItem(course: course, category: category, title: draft.title, dueDate: draft.dueDate,
                                          possiblePoints: possible, status: .upcoming))
        case .recordGrade:
            guard let item = matchingItems.first, let earned = draft.earnedPoints else { errorMessage = "The grade draft is incomplete."; return }
            item.earnedPoints = Decimal(earned); item.possiblePoints = possible; item.status = .graded; item.updatedAt = .now
        }
        do { try modelContext.save(); dismiss() }
        catch { errorMessage = "The draft could not be saved: \(error.localizedDescription)" }
    }
}
