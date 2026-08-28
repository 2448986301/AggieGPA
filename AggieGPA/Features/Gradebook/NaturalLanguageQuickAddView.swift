import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// A preview-first natural-language entry point for assignments and exams.
/// Parsing is deliberately reversible: no model is written until the user
/// confirms the complete draft.
struct NaturalLanguageQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query private var allCategories: [GradingCategory]

    let courses: [CourseRecord]
    private let initialInput: String?
    private let autoPreview: Bool

    @State private var input = ""
    @State private var draft: NaturalLanguageQuickAddDraft?
    @State private var lastPreviewInput: String?
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var parseTask: Task<Void, Never>?
    @State private var activityState: AcademicAIActivityState?
    @State private var activityIsPressed = false
    @FocusState private var inputFocused: Bool
    @State private var sheetDetent: PresentationDetent = .medium

    init(courses: [CourseRecord], initialInput: String? = nil, autoPreview: Bool = false) {
        self.courses = courses
        self.initialInput = initialInput
        self.autoPreview = autoPreview
        _input = State(initialValue: initialInput ?? "")
    }

    private var activityContentInset: CGFloat {
        guard activityState != nil else { return 0 }
        // Expansion is a transient overlay anchored above the compact pill;
        // it must not push the form or keyboard-safe content during a hold.
        return 112
    }

    private var usesVisualDemoDelay: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-demo-slow-quick-add")
    }

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                if let draft {
                    previewSection(draft)
                } else {
                    Section("Preview") {
                        ContentUnavailableView(
                            "Quick Add Draft",
                            systemImage: "text.badge.plus",
                            description: Text("Enter a note, then preview it before anything is saved.")
                        )
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(DesignSystem.ColorToken.warning)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if draft == nil {
                        Button {
                            handlePreviewTap()
                        } label: {
                            if isParsing {
                                Label("Preparing Preview…", systemImage: "hourglass")
                            } else {
                                Label("Preview Quick Add", systemImage: "wand.and.stars")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.ColorToken.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DesignSystem.Spacing.medium)
                        .padding(.vertical, DesignSystem.Spacing.small)
                        .disabled(isParsing)
                        .accessibilityIdentifier("previewQuickAddButton")
                    }

                    Color.clear.frame(height: activityContentInset)
                }
                .background(.bar)
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm & Add", systemImage: "checkmark.circle.fill") {
                        confirm()
                    }
                    .disabled(!(draft?.isReadyForConfirmation ?? false))
                    .accessibilityIdentifier("confirmQuickAddButton")
                }
            }
            .onDisappear { cancelParsing() }
            .onChange(of: input) { _, _ in lastPreviewInput = nil }
            .task {
                guard autoPreview, draft == nil, !input.isEmpty else { return }
                preview()
            }
            .overlay(alignment: .bottom) {
                AcademicAIActivityOverlay(
                    state: activityState,
                    onCancel: cancelParsing,
                    isExpanded: $activityIsPressed
                )
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
    }

    private var inputSection: some View {
        Section {
            TextEditor(text: $input)
                .frame(minHeight: 92)
                .focused($inputFocused)
                .accessibilityIdentifier("quickAddInput")
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("CHE Lab 4 Friday 11:59 PM, 20 points, remind me one day before.\nCHE实验4周五晚上11:59截止，20分，提前一天。")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text("Natural Language Quick Add")
        } footer: {
            Text("English and Simplified Chinese are supported. The app uses a local model when available and otherwise shows a deterministic manual fallback.")
        }
    }

    @ViewBuilder
    private func previewSection(_ value: NaturalLanguageQuickAddDraft) -> some View {
        Section("Quick Add Draft") {
            LabeledContent("Course", value: value.courseCode.isEmpty ? "—" : value.courseCode)
            TextField("Title", text: titleBinding)
                .accessibilityIdentifier("quickAddTitleField")
            Picker("Type", selection: typeBinding) {
                ForEach(GradeCategoryType.allCases) { type in
                    Text(typeLabel(type)).tag(type)
                }
            }
            if value.dueDate != nil {
                DatePicker("Due date", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("quickAddDueDatePicker")
            } else {
                LabeledContent("Due date", value: "Not set")
            }
            TextField("Possible points", text: pointsBinding)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("quickAddPointsField")
            TextField("Category", text: categoryBinding)
                .accessibilityIdentifier("quickAddCategoryField")
            Picker("Reminder", selection: reminderBinding) {
                Text("Not set").tag(0)
                Text("1 day before").tag(24)
                Text("3 days before").tag(72)
                Text("1 week before").tag(168)
            }
            LabeledContent("Confidence", value: "\(Int((value.confidence * 100).rounded()))%")
            LabeledContent("Source", value: sourceLabel(value.source))
            Text("Nothing is saved until you tap Confirm & Add.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("quickAddNoSaveNotice")
        }

        if !value.warnings.isEmpty {
            Section("Needs Review") {
                ForEach(value.warnings, id: \.self) { warning in
                    Label(localizedWarning(warning), systemImage: "exclamationmark.circle")
                        .foregroundStyle(DesignSystem.ColorToken.warning)
                }
            }
        }

    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { draft?.title ?? "" },
            set: { draft?.title = $0 }
        )
    }

    private var pointsBinding: Binding<String> {
        Binding(
            get: { draft?.possiblePoints.map(DecimalFormatters.compact) ?? "" },
            set: { draft?.possiblePoints = DecimalFormatters.decimal(from: $0) }
        )
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { draft?.categoryName ?? "" },
            set: { draft?.categoryName = $0 }
        )
    }

    private var typeBinding: Binding<GradeCategoryType> {
        Binding(
            get: { draft?.type ?? .homework },
            set: { draft?.type = $0 }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { draft?.dueDate ?? .now },
            set: { draft?.dueDate = $0 }
        )
    }

    private var reminderBinding: Binding<Int> {
        Binding(
            get: { draft?.reminderLeadTimeHours ?? 0 },
            set: { draft?.reminderLeadTimeHours = $0 == 0 ? nil : $0 }
        )
    }

    private func preview() {
        preview(text: input)
    }

    private func handlePreviewTap() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, lastPreviewInput != trimmed else { return }
        lastPreviewInput = trimmed
        dismissKeyboard()
        sheetDetent = .large
        preview()
    }

    private func dismissKeyboard() {
        inputFocused = false
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.endEditing(true)
            }
        }
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func preview(text inputText: String) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cancelParsing()
        let referenceDate = Date()
        let courseCodes = courses.map(\.courseCode)
        isParsing = true
        errorMessage = nil
        activityState = nil
        activityIsPressed = false
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

        // Keep the no-model path immediate. A normal Quick Add tap should
        // never wait for an async provider just to discover that there is no
        // compatible model; the deterministic parser is the complete manual
        // fallback and is also the stable UI-test path.
        if isUITesting {
            if usesVisualDemoDelay {
                activityState = .shapingResult
                parseTask = Task { @MainActor in
                    defer {
                        isParsing = false
                        activityState = nil
                        activityIsPressed = false
                        parseTask = nil
                    }
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    draft = NaturalLanguageQuickAddParser.parse(
                        text,
                        referenceDate: referenceDate,
                        availableCourseCodes: courseCodes
                    )
                }
                return
            }
            draft = NaturalLanguageQuickAddParser.parse(
                text,
                referenceDate: referenceDate,
                availableCourseCodes: courseCodes
            )
            isParsing = false
            return
        }

        parseTask = Task { @MainActor in
            defer {
                isParsing = false
                activityState = nil
                activityIsPressed = false
            }
            let availability = OnDeviceSyllabusParser.availability(locale: locale)
            guard availability == .available else {
                draft = NaturalLanguageQuickAddParser.parse(
                    text,
                    referenceDate: referenceDate,
                    availableCourseCodes: courseCodes
                )
                return
            }
            activityState = .shapingResult
            let mode: SyllabusAnalysisMode = .onDevice
            let provider = AIProviderFactory.make(mode: mode)
            do {
                let parsed = try await provider.parseQuickAdd(
                    input: text,
                    referenceDate: referenceDate,
                    availableCourseCodes: courseCodes
                )
                guard !Task.isCancelled else { return }
                draft = parsed
            } catch {
                guard !Task.isCancelled else { return }
                draft = NaturalLanguageQuickAddParser.parse(
                    text,
                    referenceDate: referenceDate,
                    availableCourseCodes: courseCodes
                )
                errorMessage = "The local model was unavailable, so a manual fallback was prepared."
            }
        }
    }

    private func confirm() {
        guard let draft, draft.isReadyForConfirmation else { return }
        let normalizedCode = draft.courseCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let course = courses.first(where: { course in
            let code = course.courseCode.lowercased()
            return code == normalizedCode || code.split(separator: " ").first.map(String.init) == normalizedCode
        }) else {
            errorMessage = "The selected course is no longer available."
            return
        }
        guard let points = draft.possiblePoints, points > 0 else {
            errorMessage = "Possible points must be greater than zero."
            return
        }

        let courseCategories = allCategories
            .filter { !$0.isDeleted && $0.course?.persistentModelID == course.persistentModelID }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        let requestedName = draft.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let category = courseCategories.first(where: {
            !requestedName.isEmpty && $0.name.caseInsensitiveCompare(requestedName) == .orderedSame
        }) ?? courseCategories.first(where: { $0.categoryType == draft.type }) ?? {
            let created = GradingCategory(
                course: course,
                name: requestedName.isEmpty ? NaturalLanguageQuickAddParser.defaultCategory(for: draft.type) : requestedName,
                categoryType: draft.type,
                weight: 0,
                calculationMode: .totalPoints,
                sortOrder: courseCategories.count
            )
            modelContext.insert(created)
            return created
        }()

        let reminder = reminderConfiguration(hours: draft.reminderLeadTimeHours, dueDate: draft.dueDate)
        let item = GradeItem(
            course: course,
            category: category,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: draft.dueDate,
            possiblePoints: points,
            status: .upcoming,
            reminderEnabled: draft.reminderLeadTimeHours != nil,
            reminderLeadTime: reminder.leadTime,
            customReminderDate: reminder.customDate
        )
        modelContext.insert(item)
        do {
            try modelContext.save()
            let snapshot = GradeItemReminderSnapshot(item)
            Task {
                if snapshot.enabled {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                }
                try? await GradeItemNotificationService.sync(snapshot)
            }
            dismiss()
        } catch {
            errorMessage = "The Quick Add draft could not be saved."
        }
    }

    private func reminderConfiguration(hours: Int?, dueDate: Date?) -> (leadTime: ReminderLeadTime, customDate: Date?) {
        switch hours {
        case 24: return (.oneDay, nil)
        case 72: return (.threeDays, nil)
        case 168: return (.oneWeek, nil)
        case let value? where value > 0:
            let custom = dueDate.flatMap { Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -value, to: $0) }
            return (.custom, custom)
        default: return (.oneDay, nil)
        }
    }

    private func cancelParsing() {
        parseTask?.cancel()
        parseTask = nil
        isParsing = false
        activityState = nil
        activityIsPressed = false
    }

    private func sourceLabel(_ source: NaturalLanguageQuickAddSource) -> String {
        switch source {
        case .localModel: return AppLocalization.string("On-device local model", locale: locale)
        case .deterministicFallback: return AppLocalization.string("Manual fallback", locale: locale)
        }
    }

    private func localizedWarning(_ warning: String) -> String {
        AppLocalization.string(warning, locale: locale)
    }

    private func typeLabel(_ type: GradeCategoryType) -> String {
        switch type {
        case .homework: return AppLocalization.string("Homework", locale: locale)
        case .quiz: return AppLocalization.string("Quiz", locale: locale)
        case .lab: return AppLocalization.string("Lab", locale: locale)
        case .midterm: return AppLocalization.string("Midterm", locale: locale)
        case .finalExam: return AppLocalization.string("Final Exam", locale: locale)
        case .project: return AppLocalization.string("Project", locale: locale)
        default: return type.rawValue
        }
    }
}
