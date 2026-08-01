import SwiftData
import SwiftUI

private enum BulkCreationPreset: String, CaseIterable, Identifiable {
    case homework
    case quizzes
    case labs
    case midterms
    case custom

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .homework: "Homework 1–10"
        case .quizzes: "Quiz 1–5"
        case .labs: "Lab 1–10"
        case .midterms: "Midterm 1–3"
        case .custom: "Custom"
        }
    }

    var defaultPrefix: String? {
        switch self {
        case .homework: "Homework"
        case .quizzes: "Quiz"
        case .labs: "Lab"
        case .midterms: "Midterm"
        case .custom: nil
        }
    }

    var defaultCount: Int? {
        switch self {
        case .homework, .labs: 10
        case .quizzes: 5
        case .midterms: 3
        case .custom: nil
        }
    }
}

struct BulkCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var allItems: [GradeItem]
    @Query private var reminderDefaults: [CourseReminderDefaults]

    let course: CourseRecord
    let categories: [GradingCategory]
    let onCreated: ([UUID]) -> Void

    @State private var preset: BulkCreationPreset = .homework
    @State private var configuration: BulkCreationConfiguration
    @State private var possiblePointsText: String
    @State private var drafts: [BulkGradeItemDraft] = []
    @State private var errorMessage: String?
    @State private var didApplyReminderDefaults = false

    init(
        course: CourseRecord,
        categories: [GradingCategory],
        onCreated: @escaping ([UUID]) -> Void = { _ in }
    ) {
        self.course = course
        self.categories = categories
        self.onCreated = onCreated
        let calendar = Calendar.autoupdatingCurrent
        let firstDueDate = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        let firstCategory = categories.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.first
        _configuration = State(initialValue: BulkCreationConfiguration(
            prefix: "Homework", startNumber: 1, count: 10, intervalDays: 7,
            firstDueDate: firstDueDate, possiblePoints: 10,
            categoryName: firstCategory?.name ?? "Unassigned", categoryID: firstCategory?.id,
            reminderEnabled: false,
            reminderLeadTime: .oneDay,
            customReminderDate: nil
        ))
        _possiblePointsText = State(initialValue: DecimalFormatters.compact(10))
    }

    private var existingItems: [GradeItem] {
        allItems.filter { !$0.isDeleted && $0.course?.id == course.id }
    }

    private var validation: BulkCreationValidation {
        BulkCreationService.validate(drafts, existingItems: existingItems)
    }

    private var includedDrafts: [BulkGradeItemDraft] { drafts.filter(\.isIncluded) }

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    formContent.frame(minWidth: 560)
                } else {
                    formContent
                }
            }
            .navigationTitle("Create Multiple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Items", systemImage: "checkmark.circle.fill") { createItems() }
                        .disabled(includedDrafts.isEmpty || validation.hasBlockingDuplicates)
                        .accessibilityIdentifier("confirmBulkCreateButton")
                }
            }
            .onAppear { rebuildPreviewIfNeeded() }
            .onChange(of: configuration) { _, _ in rebuildPreview() }
            .onChange(of: possiblePointsText) { _, newValue in
                guard let points = DecimalFormatters.decimal(from: newValue) else { return }
                configuration.possiblePoints = points
            }
            .alert("Couldn’t create items", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please review the preview and try again.")
            }
        }
    }

    private var formContent: some View {
        Form {
            Section("Pattern") {
                Picker("Preset", selection: $preset) {
                    ForEach(BulkCreationPreset.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .onChange(of: preset) { _, newValue in applyPreset(newValue) }
                TextField("Name prefix", text: $configuration.prefix)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("bulkCreatePrefixField")
                Stepper(value: $configuration.startNumber, in: 0...999) {
                    LabeledContent("Starting number", value: String(configuration.startNumber))
                }
                Stepper(value: $configuration.count, in: 1...100) {
                    LabeledContent("Number of items", value: String(configuration.count))
                }
                Stepper(value: $configuration.intervalDays, in: 0...60) {
                    LabeledContent("Days between items", value: String(configuration.intervalDays))
                }
            }

            Section("Defaults") {
                DatePicker("First due date", selection: $configuration.firstDueDate, displayedComponents: [.date, .hourAndMinute])
                TextField("Possible points", text: $possiblePointsText)
                    .keyboardType(.decimalPad)
                if categories.isEmpty {
                    LabeledContent("Category", value: "Unassigned")
                } else {
                    Picker("Category", selection: categoryBinding) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(categories.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }) { category in
                            Text(verbatim: category.name).tag(Optional(category.id))
                        }
                    }
                }
                Toggle("Set reminders", isOn: $configuration.reminderEnabled)
                if configuration.reminderEnabled {
                    Picker("Reminder lead time", selection: $configuration.reminderLeadTime) {
                        Text("1 day before").tag(ReminderLeadTime.oneDay)
                        Text("3 days before").tag(ReminderLeadTime.threeDays)
                        Text("1 week before").tag(ReminderLeadTime.oneWeek)
                        Text("Custom").tag(ReminderLeadTime.custom)
                    }
                    if configuration.reminderLeadTime == .custom {
                        DatePicker("Reminder date", selection: customReminderDateBinding, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }

            Section {
                if drafts.isEmpty {
                    ContentUnavailableView("Preview unavailable", systemImage: "list.bullet.rectangle", description: Text("Enter a prefix and positive points to preview the items."))
                } else {
                    ForEach($drafts) { $draft in
                        BulkDraftRow(draft: $draft) {
                            draft.isIncluded.toggle()
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Preview")
                    Spacer()
                    Text("\(includedDrafts.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if validation.hasBlockingDuplicates {
                    Label("Remove duplicate names or dates before creating items.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DesignSystem.ColorToken.warning)
                } else if validation.duplicateDateCount > 0 {
                    Text("Some dates match existing records.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing is saved until you tap Create Items.")
                }
            }
        }
    }

    private var categoryBinding: Binding<UUID?> {
        Binding(
            get: { configuration.categoryID },
            set: { newValue in
                configuration.categoryID = newValue
                configuration.categoryName = newValue.flatMap { id in categories.first { $0.id == id }?.name } ?? "Unassigned"
            }
        )
    }

    private func applyPreset(_ value: BulkCreationPreset) {
        guard let prefix = value.defaultPrefix, let count = value.defaultCount else { return }
        configuration.prefix = prefix
        configuration.count = count
        configuration.startNumber = 1
    }

    private func rebuildPreviewIfNeeded() {
        guard drafts.isEmpty else { return }
        if !didApplyReminderDefaults,
           let defaults = reminderDefaults.first(where: { $0.courseID == course.id }) {
            configuration.reminderEnabled = defaults.reminderEnabled
            configuration.reminderLeadTime = defaults.reminderLeadTime
            configuration.customReminderDate = defaults.customReminderDate
            didApplyReminderDefaults = true
        } else {
            didApplyReminderDefaults = true
        }
        rebuildPreview()
    }

    private var customReminderDateBinding: Binding<Date> {
        Binding(
            get: { configuration.customReminderDate ?? configuration.firstDueDate.addingTimeInterval(-86_400) },
            set: { configuration.customReminderDate = $0 }
        )
    }

    private func rebuildPreview() {
        drafts = BulkCreationService.preview(configuration)
    }

    private func createItems() {
        do {
            let ids = try BulkCreationService.insert(
                drafts, course: course, categories: categories, context: modelContext
            )
            onCreated(ids)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The items could not be created. Your existing data was preserved."
        }
    }
}

private struct BulkDraftRow: View {
    @Binding var draft: BulkGradeItemDraft
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            Button(action: toggle) {
                Image(systemName: draft.isIncluded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.isIncluded ? DesignSystem.ColorToken.gold : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.isIncluded ? "Remove from preview" : "Restore to preview")

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: draft.title)
                    .font(.headline)
                    .strikethrough(!draft.isIncluded)
                Text(draft.dueDate, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(draft.categoryName) · \(DecimalFormatters.compact(draft.possiblePoints)) pts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .opacity(draft.isIncluded ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}
