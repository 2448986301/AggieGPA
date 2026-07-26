import SwiftData
import SwiftUI

struct CourseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let term: AcademicTerm
    let course: CourseRecord?

    @State private var code: String
    @State private var title: String
    @State private var unitsText: String
    @State private var grade: CourseGrade
    @State private var gradingBasis: GradingBasis
    @State private var institution: InstitutionType
    @State private var isMajor: Bool
    @State private var isUpper: Bool
    @State private var isTransfer: Bool
    @State private var includeInGPA: Bool
    @State private var isRepeat: Bool
    @State private var attemptNumber: Int
    @State private var repeatMode: RepeatHandlingMode
    @State private var notes: String
    @State private var siriAliases: String
    @State private var validationMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case code, units }

    init(term: AcademicTerm, course: CourseRecord? = nil) {
        self.term = term
        self.course = course
        _code = State(initialValue: course?.courseCode ?? "")
        _title = State(initialValue: course?.courseTitle ?? "")
        _unitsText = State(initialValue: course.map { DecimalFormatters.compact($0.units) } ?? "")
        _grade = State(initialValue: course?.grade ?? .a)
        _gradingBasis = State(initialValue: course?.gradingBasis ?? .letter)
        _institution = State(initialValue: course?.institution ?? .ucDavis)
        _isMajor = State(initialValue: course?.isMajorCourse ?? false)
        _isUpper = State(initialValue: course?.isUpperDivision ?? false)
        _isTransfer = State(initialValue: course?.isTransferCourse ?? false)
        _includeInGPA = State(initialValue: course?.isIncludedInGPA ?? true)
        _isRepeat = State(initialValue: course?.isRepeatCourse ?? false)
        _attemptNumber = State(initialValue: max(1, course?.repeatAttemptOrder ?? 1))
        _repeatMode = State(initialValue: course?.repeatHandlingMode ?? .manualReview)
        _notes = State(initialValue: course?.notes ?? "")
        _siriAliases = State(initialValue: course.map { SiriAliasStore.aliases(for: $0.id).joined(separator: ", ") } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Course code, e.g. CHE 002A", text: $code)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .code)
                        .accessibilityIdentifier("courseCodeField")
                    TextField("Units", text: $unitsText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .units)
                        .accessibilityIdentifier("courseUnitsField")
                    Picker("Grade", selection: $grade) {
                        ForEach(CourseGrade.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .accessibilityIdentifier("courseGradePicker")
                }
                Section("Details") {
                    TextField("Course title", text: $title)
                    Picker("Grading basis", selection: $gradingBasis) {
                        ForEach(GradingBasis.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    Picker("Institution", selection: $institution) {
                        ForEach(InstitutionType.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    Toggle("Major course", isOn: $isMajor)
                    Toggle("Upper-division course", isOn: $isUpper)
                    Toggle("Transfer course", isOn: $isTransfer)
                    Toggle("Include in GPA estimate", isOn: $includeInGPA)
                }
                if !institution.defaultIncludesInUCGPA && includeInGPA {
                    Section {
                        Label("Non-UC coursework, AP/IB, and most transfer work normally do not enter the UC GPA. Keep this enabled only for personal planning.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Section("Repeat course") {
                    Toggle("This is a repeat attempt", isOn: $isRepeat)
                    if isRepeat {
                        Stepper("Attempt number: \(attemptNumber)", value: $attemptNumber, in: 1...5)
                        Picker("Handling", selection: $repeatMode) {
                            ForEach(RepeatHandlingMode.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                        Text("Estimated only. Verify with your official transcript or academic advisor.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
                Section("Siri Aliases") {
                    TextField("For example: Chemistry, Chem 2A, 化学", text: $siriAliases, axis: .vertical)
                    Text("Use short names you naturally say. Separate aliases with commas.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let validationMessage {
                    Section { Label(validationMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(course == nil ? "New Course" : "Edit Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.accessibilityIdentifier("saveCourseButton")
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasUnsavedInput)
        .safeAreaInset(edge: .bottom) {
            if focusedField != nil {
                HStack {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    private var hasUnsavedInput: Bool { !code.isEmpty || !unitsText.isEmpty || !title.isEmpty || !notes.isEmpty }

    private func save() {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else { validationMessage = "Enter a course code."; return }
        guard let units = DecimalFormatters.decimal(from: unitsText), units > 0, InputValidator.validUnits(units) else {
            validationMessage = "Enter units greater than 0 and no more than 50."; return
        }
        if let course {
            course.courseCode = normalizedCode
            course.courseTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            course.units = units
            course.grade = grade
            course.gradingBasis = gradingBasis
            course.institution = institution
            course.isMajorCourse = isMajor
            course.isUpperDivision = isUpper
            course.isTransferCourse = isTransfer
            course.isIncludedInGPA = includeInGPA
            course.isRepeatCourse = isRepeat
            course.repeatAttemptOrder = attemptNumber
            course.repeatHandlingMode = repeatMode
            course.notes = notes
            course.updatedAt = .now
            SiriAliasStore.save(siriAliases, for: course.id)
        } else {
            let record = CourseRecord(courseCode: normalizedCode,
                                             courseTitle: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                             units: units, grade: grade, gradingBasis: gradingBasis,
                                             institution: institution, term: term, isMajorCourse: isMajor,
                                             isUpperDivision: isUpper, isIncludedInGPA: includeInGPA,
                                             isTransferCourse: isTransfer, isRepeatCourse: isRepeat,
                                             repeatAttemptOrder: attemptNumber, repeatHandlingMode: repeatMode,
                                             notes: notes)
            modelContext.insert(record)
            SiriAliasStore.save(siriAliases, for: record.id)
        }
        try? modelContext.save()
        dismiss()
    }
}
