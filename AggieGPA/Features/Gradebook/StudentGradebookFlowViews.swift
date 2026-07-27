import SwiftData
import SwiftUI

/// The short, student-facing path deliberately keeps scoring rules out of the
/// first screen. The existing editors remain available from Course Settings.
struct GradeBreakdownSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: CourseRecord
    @State private var selection: Template = .homeworkLabsMidtermsFinal

    private enum Template: String, CaseIterable, Identifiable {
        case homeworkExams, homeworkQuizzesExams, homeworkLabsMidtermsFinal, points
        var id: String { rawValue }
        var title: String {
            switch self {
            case .homeworkExams: "Homework & Exams"
            case .homeworkQuizzesExams: "Homework, Quizzes & Exams"
            case .homeworkLabsMidtermsFinal: "Labs, Midterms & Final"
            case .points: "Points-Based Course"
            }
        }
        var categories: [(String, GradeCategoryType, Decimal)] {
            switch self {
            case .homeworkExams: [("Homework", .homework, 40), ("Exams", .midterm, 60)]
            case .homeworkQuizzesExams: [("Homework", .homework, 35), ("Quizzes", .quiz, 15), ("Exams", .midterm, 50)]
            case .homeworkLabsMidtermsFinal: [("Homework", .homework, 20), ("Labs", .lab, 20), ("Midterms", .midterm, 30), ("Final Exam", .finalExam, 30)]
            case .points: [("Course points", .custom, 100)]
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("How is this course graded?")
                        .font(.title3.bold())
                    Text("Choose a simple starting point. You can adjust details later in Course Settings.")
                        .foregroundStyle(.secondary)
                }
                Section("Use a Template") {
                    ForEach(Template.allCases) { template in
                        Button {
                            selection = template
                        } label: {
                            HStack {
                                Text(template.title)
                                Spacer()
                                if selection == template { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Preview") {
                    ForEach(selection.categories, id: \.0) { category in
                        LabeledContent(category.0, value: "\(compact(category.2))%")
                    }
                    LabeledContent("Total", value: "100%")
                        .fontWeight(.semibold)
                }
            }
            .navigationTitle("Grade Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use This Template") { save() }
                        .accessibilityIdentifier("useGradeTemplateButton")
                }
            }
        }
    }

    private func save() {
        let policy = CourseGradingPolicy(course: course, gradingMethod: selection == .points ? .totalPoints : .weightedCategories)
        modelContext.insert(policy)
        let scale = GradeScale(course: course, name: "Common Scale Template", boundaries: Self.standardScale, isCommonTemplate: true)
        modelContext.insert(scale)
        for (index, definition) in selection.categories.enumerated() {
            modelContext.insert(GradingCategory(course: course, name: definition.0, categoryType: definition.1,
                                                weight: definition.2, calculationMode: .totalPoints, sortOrder: index))
        }
        try? modelContext.save()
        dismiss()
    }

    private static let standardScale: [GradeScaleBoundary] = [
        GradeScaleBoundary(letter: .aPlus, minimumPercentage: 97), GradeScaleBoundary(letter: .a, minimumPercentage: 93),
        GradeScaleBoundary(letter: .aMinus, minimumPercentage: 90), GradeScaleBoundary(letter: .bPlus, minimumPercentage: 87),
        GradeScaleBoundary(letter: .b, minimumPercentage: 83), GradeScaleBoundary(letter: .bMinus, minimumPercentage: 80),
        GradeScaleBoundary(letter: .cPlus, minimumPercentage: 77), GradeScaleBoundary(letter: .c, minimumPercentage: 73),
        GradeScaleBoundary(letter: .cMinus, minimumPercentage: 70), GradeScaleBoundary(letter: .dPlus, minimumPercentage: 67),
        GradeScaleBoundary(letter: .d, minimumPercentage: 63), GradeScaleBoundary(letter: .dMinus, minimumPercentage: 60),
        GradeScaleBoundary(letter: .f, minimumPercentage: 0)
    ]
}

struct QuickGradeItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: CourseRecord
    let categories: [GradingCategory]
    let category: GradingCategory
    @State private var title = ""
    @State private var dueDate = Date()
    @State private var possible = "100"
    @State private var showMore = false
    @State private var categoryID: UUID?
    @State private var validation: String?
    @FocusState private var focusedField: Field?

    private enum Field { case title, points }

    init(course: CourseRecord, categories: [GradingCategory], category: GradingCategory) {
        self.course = course; self.categories = categories; self.category = category
        _categoryID = State(initialValue: category.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Required details") {
                    LabeledContent("Category", value: selectedCategory.name)
                        .foregroundStyle(.secondary)
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("quickGradeItemTitleField")
                        .focused($focusedField, equals: .title)
                    DatePicker(isExam ? "Exam date" : "Due date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Optional details") {
                    DisclosureGroup("More Options", isExpanded: $showMore) {
                        Picker("Category", selection: $categoryID) {
                            ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                        }
                        TextField("Possible points", text: $possible)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .points)
                    }
                }
                if let validation {
                    Section { Label(validation, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isExam ? "Add Exam" : "Add Grade Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton(identifier: "saveQuickGradeItemButton")
                }
            }
            .onChange(of: title) { _, _ in validation = nil }
            .onChange(of: possible) { _, _ in validation = nil }
            .onChange(of: categoryID) { _, _ in validation = nil }
        }
        .presentationDetents([.medium, .large])
    }

    private var isExam: Bool {
        selectedCategory.categoryType == .midterm || selectedCategory.categoryType == .finalExam
    }

    private var selectedCategory: GradingCategory {
        categories.first { $0.id == categoryID } ?? category
    }

    private func saveButton(identifier: String) -> some View {
        Button {
            focusedField = nil
            save()
        } label: {
            Label("Save", systemImage: "checkmark")
                .fontWeight(.semibold)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier(identifier)
    }

    private func save() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { validation = "Enter a name."; return }
        guard let points = DecimalFormatters.decimal(from: possible), points > 0 else { validation = "Enter possible points greater than zero."; return }
        modelContext.insert(GradeItem(course: course, category: categories.first { $0.id == categoryID }, title: clean,
                                      dueDate: dueDate, possiblePoints: points, status: .upcoming))
        try? modelContext.save(); dismiss()
    }
}

struct RecordScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: GradeItem
    let onSaved: (() -> Void)?
    @State private var earned: String
    @State private var possible: String
    @State private var validation: String?
    @FocusState private var focusedField: Field?

    private enum Field { case earned, possible }

    init(item: GradeItem, onSaved: (() -> Void)? = nil) {
        self.item = item
        self.onSaved = onSaved
        _earned = State(initialValue: item.earnedPoints.map(compact) ?? "")
        _possible = State(initialValue: compact(item.possiblePoints))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(item.title) {
                    LabeledContent("Course", value: item.course?.courseCode ?? "Course")
                        .foregroundStyle(.secondary)
                }
                Section("Required details") {
                    TextField("Earned points", text: $earned)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .earned)
                        .accessibilityIdentifier("recordEarnedPointsField")
                    TextField("Possible points", text: $possible)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .possible)
                        .accessibilityIdentifier("recordPossiblePointsField")
                }
                if let validation {
                    Section { Label(validation, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Record Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { saveButton }
            }
            .onChange(of: earned) { _, _ in validation = nil }
            .onChange(of: possible) { _, _ in validation = nil }
        }
        .presentationDetents([.medium, .large])
    }

    private var saveButton: some View {
        Button {
            focusedField = nil
            save()
        } label: {
            Label("Save", systemImage: "checkmark")
                .fontWeight(.semibold)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("saveRecordedScoreButton")
    }

    private func save() {
        guard let earnedValue = DecimalFormatters.decimal(from: earned), let possibleValue = DecimalFormatters.decimal(from: possible), possibleValue > 0 else {
            validation = "Enter valid earned and possible points."; return
        }
        item.earnedPoints = earnedValue; item.possiblePoints = possibleValue; item.status = .graded; item.updatedAt = .now
        try? modelContext.save()
        onSaved?()
        dismiss()
    }
}
