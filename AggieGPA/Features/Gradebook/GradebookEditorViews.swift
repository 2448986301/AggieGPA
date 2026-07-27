import SwiftData
import SwiftUI
import UserNotifications

struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: CourseRecord
    let category: GradingCategory?
    let nextSortOrder: Int
    @State private var name: String
    @State private var type: GradeCategoryType
    @State private var weightText: String
    @State private var mode: CategoryCalculationMode
    @State private var dropLowest: Int
    @State private var isExtraCredit: Bool
    @State private var validation: String?
    @State private var showMoreOptions = false

    init(course: CourseRecord, category: GradingCategory?, nextSortOrder: Int) {
        self.course = course; self.category = category; self.nextSortOrder = nextSortOrder
        _name = State(initialValue: category?.name ?? "")
        _type = State(initialValue: category?.categoryType ?? .homework)
        _weightText = State(initialValue: category.map { compact($0.weight) } ?? "")
        _mode = State(initialValue: category?.calculationMode ?? .totalPoints)
        _dropLowest = State(initialValue: category?.dropLowestCount ?? 0)
        _isExtraCredit = State(initialValue: category?.isExtraCredit ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Required details") {
                    TextField("Name", text: $name).accessibilityIdentifier("categoryNameField")
                    Picker("Type", selection: $type) { ForEach(GradeCategoryType.allCases) { Text($0.displayName).tag($0) } }
                    TextField("Weight percent", text: $weightText).keyboardType(.decimalPad)
                }
                Section("Optional details") {
                    DisclosureGroup("More Options", isExpanded: $showMoreOptions) {
                    Picker("Item calculation", selection: $mode) {
                        Text("Total points").tag(CategoryCalculationMode.totalPoints)
                        Text("Equal items").tag(CategoryCalculationMode.equalItems)
                        Text("Custom / manual review").tag(CategoryCalculationMode.custom)
                    }
                    Stepper("Drop lowest: \(dropLowest)", value: $dropLowest, in: 0...20)
                    Toggle("Extra-credit category", isOn: $isExtraCredit)
                    }
                }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("saveCategoryButton") }
            }
        }.presentationDetents([.medium, .large])
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { validation = "Enter a category name."; return }
        guard let weight = DecimalFormatters.decimal(from: weightText), weight >= 0, weight <= 100 else { validation = "Enter a weight from 0 to 100."; return }
        if let category {
            category.name = clean; category.categoryType = type; category.weight = weight; category.calculationMode = mode
            category.dropLowestCount = dropLowest; category.isExtraCredit = isExtraCredit; category.updatedAt = .now
        } else {
            modelContext.insert(GradingCategory(course: course, name: clean, categoryType: type, weight: weight,
                                                calculationMode: mode, dropLowestCount: dropLowest,
                                                isExtraCredit: isExtraCredit, sortOrder: nextSortOrder))
        }
        try? modelContext.save(); dismiss()
    }
}

struct GradeItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: CourseRecord
    let categories: [GradingCategory]
    let item: GradeItem?
    @State private var title: String
    @State private var categoryID: UUID?
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var earnedText: String
    @State private var possibleText: String
    @State private var status: GradeItemStatus
    @State private var extraCredit: Bool
    @State private var excused: Bool
    @State private var dropped: Bool
    @State private var notes: String
    @State private var reminderEnabled: Bool
    @State private var reminderLeadTime: ReminderLeadTime
    @State private var customReminderDate: Date
    @State private var validation: String?
    @State private var saveAnother = false
    @State private var showMoreOptions = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, earned, possible }

    init(course: CourseRecord, categories: [GradingCategory], item: GradeItem?) {
        self.course = course; self.categories = categories; self.item = item
        _title = State(initialValue: item?.title ?? "")
        _categoryID = State(initialValue: item?.category?.id ?? categories.first?.id)
        _hasDueDate = State(initialValue: item?.dueDate != nil)
        _dueDate = State(initialValue: item?.dueDate ?? .now)
        _earnedText = State(initialValue: item?.earnedPoints.map(compact) ?? "")
        _possibleText = State(initialValue: item.map { compact($0.possiblePoints) } ?? "")
        _status = State(initialValue: item?.status ?? .upcoming)
        _extraCredit = State(initialValue: item?.isExtraCredit ?? false)
        _excused = State(initialValue: item?.isExcused ?? false)
        _dropped = State(initialValue: item?.isDropped ?? false)
        _notes = State(initialValue: item?.notes ?? "")
        _reminderEnabled = State(initialValue: item?.reminderEnabled ?? false)
        _reminderLeadTime = State(initialValue: item?.reminderLeadTime ?? ((item?.category?.categoryType == .midterm || item?.category?.categoryType == .finalExam) ? .threeDays : .oneDay))
        _customReminderDate = State(initialValue: item?.customReminderDate ?? item?.dueDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Required details") {
                    TextField("Title", text: $title)
                        .focused($focusedField, equals: .title)
                        .accessibilityIdentifier("gradeItemTitleField")
                    Picker("Category", selection: $categoryID) {
                        Text("Unassigned").tag(nil as UUID?)
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Status", selection: $status) { ForEach(GradeItemStatus.allCases) { Text(LocalizedStringKey($0.localizedLabelKey)).tag($0) } }
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute]) }
                }
                Section("Score") {
                    TextField("Earned points (optional)", text: $earnedText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .earned)
                    TextField("Possible points", text: $possibleText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .possible)
                }
                Section("Optional details") {
                    DisclosureGroup("More Options", isExpanded: $showMoreOptions) {
                        Toggle("Extra credit", isOn: $extraCredit)
                        Toggle("Excused", isOn: $excused)
                        Toggle("Dropped", isOn: $dropped)
                        TextField("Optional notes", text: $notes, axis: .vertical)
                        Toggle("Remind me", isOn: $reminderEnabled)
                        if reminderEnabled {
                            Picker("Lead time", selection: $reminderLeadTime) {
                                Text("1 day before").tag(ReminderLeadTime.oneDay)
                                Text("3 days before").tag(ReminderLeadTime.threeDays)
                                Text("1 week before").tag(ReminderLeadTime.oneWeek)
                                Text("Custom").tag(ReminderLeadTime.custom)
                            }
                            if reminderLeadTime == .custom { DatePicker("Reminder date", selection: $customReminderDate) }
                            Text("iOS will ask for notification permission when you save an enabled reminder.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if item == nil { Toggle("Save and add another", isOn: $saveAnother) }
                    }
                }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(item == nil ? "New Grade Item" : "Edit Grade Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { saveButton }
            }
        }
        .presentationDetents([.large])
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
        .accessibilityIdentifier("saveGradeItemButton")
    }

    private func save() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { validation = "Enter a title."; return }
        guard let possible = DecimalFormatters.decimal(from: possibleText), possible > 0 else { validation = "Possible points must be greater than zero."; return }
        let earned = earnedText.isEmpty ? nil : DecimalFormatters.decimal(from: earnedText)
        guard earnedText.isEmpty || earned != nil else { validation = "Enter a valid earned score."; return }
        let selectedCategory = categories.first { $0.id == categoryID }
        let savedItem: GradeItem
        if let item {
            item.title = clean; item.category = selectedCategory; item.dueDate = hasDueDate ? dueDate : nil
            item.earnedPoints = earned; item.possiblePoints = possible; item.status = status
            item.isExtraCredit = extraCredit; item.isExcused = excused; item.isDropped = dropped
            item.notes = notes; item.updatedAt = .now
            item.reminderEnabled = reminderEnabled; item.reminderLeadTime = reminderLeadTime
            item.customReminderDate = reminderLeadTime == .custom ? customReminderDate : nil
            savedItem = item
        } else {
            let newItem = GradeItem(course: course, category: selectedCategory, title: clean,
                                    dueDate: hasDueDate ? dueDate : nil, earnedPoints: earned,
                                    possiblePoints: possible, status: status, isExtraCredit: extraCredit,
                                    isDropped: dropped, isExcused: excused, notes: notes,
                                    reminderEnabled: reminderEnabled, reminderLeadTime: reminderLeadTime,
                                    customReminderDate: reminderLeadTime == .custom ? customReminderDate : nil)
            modelContext.insert(newItem); savedItem = newItem
        }
        try? modelContext.save()
        let reminder = GradeItemReminderSnapshot(savedItem)
        Task {
            do {
                if reminder.enabled {
                    let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                    guard allowed else { return }
                }
                try await GradeItemNotificationService.sync(reminder)
            } catch { }
        }
        if saveAnother && item == nil { title = ""; earnedText = ""; possibleText = ""; status = .upcoming; validation = nil }
        else { dismiss() }
    }
}

struct GradingPolicyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: CourseRecord
    let policy: CourseGradingPolicy?
    let scale: GradeScale?
    @State private var method: GradingMethod
    @State private var normalize: Bool
    @State private var missingPolicy: MissingItemPolicy
    @State private var confirmed: Bool
    @State private var targetText: String
    @State private var useCommonScale: Bool
    @State private var validation: String?

    init(course: CourseRecord, policy: CourseGradingPolicy?, scale: GradeScale?) {
        self.course = course; self.policy = policy; self.scale = scale
        _method = State(initialValue: policy?.gradingMethod ?? .weightedCategories)
        _normalize = State(initialValue: policy?.normalizeCurrentGrade ?? true)
        _missingPolicy = State(initialValue: policy?.missingItemPolicy ?? .excludeUntilGraded)
        _confirmed = State(initialValue: policy?.missingPolicyConfirmed ?? false)
        _targetText = State(initialValue: policy?.targetPercentage.map(compact) ?? "")
        _useCommonScale = State(initialValue: scale?.isCommonTemplate ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Calculation") {
                    Picker("Method", selection: $method) {
                        Text("Weighted categories").tag(GradingMethod.weightedCategories)
                        Text("Total points").tag(GradingMethod.totalPoints)
                        Text("Hybrid").tag(GradingMethod.hybrid)
                        Text("Manual letter only").tag(GradingMethod.manualLetterGradeOnly)
                    }
                    Toggle("Normalize current grade over graded work", isOn: $normalize)
                    Picker("Ungraded and missing work", selection: $missingPolicy) {
                        Text("Exclude until graded").tag(MissingItemPolicy.excludeUntilGraded)
                        Text("Count missing as zero").tag(MissingItemPolicy.countMissingAsZero)
                    }
                    if missingPolicy == .countMissingAsZero {
                        Toggle("I confirm missing items should count as zero", isOn: $confirmed)
                    }
                }
                Section("Target") { TextField("Target percentage (optional)", text: $targetText).keyboardType(.decimalPad) }
                Section("Letter Prediction") {
                    Toggle("Use common scale template", isOn: $useCommonScale)
                    Text("The common scale is only a starting template. Confirm it matches this syllabus before relying on letter predictions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
            }
            .navigationTitle("Grading Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("saveGradingPolicyButton") }
            }
        }
    }

    private func save() {
        let target = targetText.isEmpty ? nil : DecimalFormatters.decimal(from: targetText)
        guard targetText.isEmpty || (target != nil && target! >= 0 && target! <= 100) else { validation = "Enter a target from 0 to 100."; return }
        let savedPolicy = policy ?? CourseGradingPolicy(course: course)
        if policy == nil { modelContext.insert(savedPolicy) }
        savedPolicy.gradingMethod = method; savedPolicy.normalizeCurrentGrade = normalize
        savedPolicy.missingItemPolicy = missingPolicy
        savedPolicy.missingPolicyConfirmed = missingPolicy == .countMissingAsZero && confirmed
        savedPolicy.targetPercentage = target; savedPolicy.updatedAt = .now

        if useCommonScale {
            let savedScale = scale ?? GradeScale(course: course)
            if scale == nil { modelContext.insert(savedScale) }
            savedScale.name = "Common Scale Template"
            savedScale.boundaries = Self.commonScale
            savedScale.isCommonTemplate = true
            savedScale.isLetterPredictionEnabled = true
            savedScale.requiresManualReview = true
            savedScale.updatedAt = .now
        } else if let scale {
            scale.isLetterPredictionEnabled = false; scale.updatedAt = .now
        }
        try? modelContext.save(); dismiss()
    }

    private static let commonScale: [GradeScaleBoundary] = [
        GradeScaleBoundary(letter: .aPlus, minimumPercentage: 97),
        GradeScaleBoundary(letter: .a, minimumPercentage: 93),
        GradeScaleBoundary(letter: .aMinus, minimumPercentage: 90),
        GradeScaleBoundary(letter: .bPlus, minimumPercentage: 87),
        GradeScaleBoundary(letter: .b, minimumPercentage: 83),
        GradeScaleBoundary(letter: .bMinus, minimumPercentage: 80),
        GradeScaleBoundary(letter: .cPlus, minimumPercentage: 77),
        GradeScaleBoundary(letter: .c, minimumPercentage: 73),
        GradeScaleBoundary(letter: .cMinus, minimumPercentage: 70),
        GradeScaleBoundary(letter: .dPlus, minimumPercentage: 67),
        GradeScaleBoundary(letter: .d, minimumPercentage: 63),
        GradeScaleBoundary(letter: .dMinus, minimumPercentage: 60),
        GradeScaleBoundary(letter: .f, minimumPercentage: 0)
    ]
}

struct ForecastEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allForecasts: [ForecastScenario]
    let course: CourseRecord
    let policy: CourseGradingPolicy?
    let forecast: ForecastScenario?
    @State private var name: String
    @State private var kind: ForecastScenarioKind
    @State private var assumption: Double
    @State private var targetText: String
    @State private var validation: String?

    init(course: CourseRecord, policy: CourseGradingPolicy?, forecast: ForecastScenario?) {
        self.course = course; self.policy = policy; self.forecast = forecast
        _name = State(initialValue: forecast?.name ?? "Expected")
        _kind = State(initialValue: forecast?.kind ?? .expected)
        _assumption = State(initialValue: forecast.map { decimalDouble($0.assumedRemainingPercentage) } ?? 85)
        _targetText = State(initialValue: policy?.targetPercentage.map(compact) ?? "90")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expected Scenario") {
                    TextField("Scenario name", text: $name)
                    Picker("Preset", selection: $kind) {
                        Text("Best case").tag(ForecastScenarioKind.bestCase)
                        Text("Expected").tag(ForecastScenarioKind.expected)
                        Text("Conservative").tag(ForecastScenarioKind.conservative)
                        Text("Finals goal").tag(ForecastScenarioKind.finalsGoal)
                        Text("Custom").tag(ForecastScenarioKind.custom)
                    }
                    Text("Assume \(Int(assumption.rounded()))% on remaining work").font(.headline)
                    Slider(value: $assumption, in: 0...100, step: 1)
                    TextField("Target course percentage", text: $targetText).keyboardType(.decimalPad)
                }
                Section { Text("This scenario is stored locally and can be changed without altering entered scores.").font(.footnote).foregroundStyle(.secondary) }
                if let validation { Section { Text(validation).foregroundStyle(.red) } }
            }
            .navigationTitle("Forecast Scenario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityIdentifier("saveForecastButton") }
            }
            .onChange(of: kind) { _, newValue in
                switch newValue {
                case .bestCase: assumption = 100
                case .expected: assumption = 85
                case .conservative: assumption = 70
                case .finalsGoal, .custom: break
                }
            }
        }.presentationDetents([.medium])
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { validation = "Enter a scenario name."; return }
        guard let target = DecimalFormatters.decimal(from: targetText), target >= 0, target <= 100 else { validation = "Enter a target from 0 to 100."; return }
        let savedPolicy = policy ?? CourseGradingPolicy(course: course)
        if policy == nil { modelContext.insert(savedPolicy) }
        savedPolicy.targetPercentage = target; savedPolicy.updatedAt = .now
        let savedForecast = forecast ?? ForecastScenario(course: course, name: cleanName, kind: kind)
        if forecast == nil { modelContext.insert(savedForecast) }
        savedForecast.name = cleanName
        savedForecast.kind = kind
        savedForecast.assumedRemainingPercentage = Decimal(Int(assumption.rounded()))
        for candidate in allForecasts where candidate.course?.persistentModelID == course.persistentModelID {
            candidate.isSelectedForGPAForecast = candidate.id == savedForecast.id
        }
        savedForecast.isSelectedForGPAForecast = true
        savedForecast.updatedAt = .now
        try? modelContext.save(); dismiss()
    }
}

private extension GradeCategoryType {
    var displayName: String { rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }
}
