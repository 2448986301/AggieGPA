import SwiftData
import SwiftUI

/// Create Plan is the progressive-disclosure entry point for target planning. It
/// edits the same scenario inputs used by Full Simulation and saves only those
/// inputs, never a stale GPA result.
struct TargetGPAView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Query private var courses: [CourseRecord]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    @Query(sort: \PlannerScenario.sortOrder, order: .reverse) private var savedPlans: [PlannerScenario]
    let preferences: UserPreferences
    let initialScenario: GPAPlanningScenarioInput?

    @State private var targetText: String
    @State private var planName: String
    @State private var selectedCourseIDs: Set<UUID>
    @State private var includeAllCourses: Bool
    @State private var assumedGrades: [UUID: CourseGrade]
    @State private var initialized = false
    @State private var showSimulation = false
    @State private var savedScenario: GPAPlanningScenarioInput?
    @State private var message: String?

    init(preferences: UserPreferences, initialScenario: GPAPlanningScenarioInput? = nil) {
        self.preferences = preferences
        self.initialScenario = initialScenario
        let scenario = initialScenario ?? GPAPlanningScenarioInput(targetGPA: preferences.targetGPA)
        _targetText = State(initialValue: DecimalFormatters.compact(scenario.targetGPA))
        _planName = State(initialValue: scenario.name == "Current plan" ? "My GPA plan" : scenario.name)
        _selectedCourseIDs = State(initialValue: scenario.selectedCourseIDs ?? [])
        _includeAllCourses = State(initialValue: scenario.selectedCourseIDs == nil)
        _assumedGrades = State(initialValue: scenario.assumedGrades)
    }

    private var inputs: [GPAPlanningCourseInput] {
        GPAPlanningEngine.makeInputs(courses: courses, policies: policies, categories: categories,
                                     items: items, scales: scales, forecasts: forecasts)
    }

    private var targetGPA: Decimal { DecimalFormatters.decimal(from: targetText) ?? preferences.targetGPA }

    private var scenario: GPAPlanningScenarioInput {
        GPAPlanningScenarioInput(id: initialScenario?.id,
                                 name: planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My GPA plan" : planName,
                                 targetGPA: targetGPA,
                                 selectedCourseIDs: includeAllCourses ? nil : selectedCourseIDs,
                                 assumedGrades: assumedGrades)
    }

    private var snapshot: GPAPlanningSnapshot {
        GPAPlanningEngine.resolve(inputs: inputs, scenario: scenario, fallbackTargetUnits: 12)
    }

    private var eligibleCourses: [GPAPlanningCourseInput] {
        inputs.filter(\.isGPAEligible).sorted { $0.courseCode < $1.courseCode }
    }

    var body: some View {
        ZStack {
            CampusBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    summary
                    planControls
                    courseScope
                    optionalAssumptions
                    createAction
                }
                .frame(maxWidth: 1_180, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.large)
            }
            .safeAreaPadding(.bottom, horizontalSizeClass == .compact ? 96 : DesignSystem.Spacing.large)
        }
        .navigationTitle("Create Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .onAppear { initializeIfNeeded() }
        .navigationDestination(isPresented: $showSimulation) {
            GPAFullSimulationView(preferences: preferences, initialScenario: savedScenario ?? scenario)
        }
        .accessibilityIdentifier("gpaCreatePlan")
    }

    private var summary: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                Text("Your GPA path").font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DesignSystem.Spacing.large) {
                        metric("Current GPA", snapshot.current.gpa, identifier: "createPlanCurrentGPA")
                        metric("Projected GPA", snapshot.projected.gpa, identifier: "createPlanProjectedGPA")
                        metric("Target GPA", targetGPA, identifier: "createPlanTargetGPA")
                    }
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        metric("Current GPA", snapshot.current.gpa, identifier: "createPlanCurrentGPA")
                        metric("Projected GPA", snapshot.projected.gpa, identifier: "createPlanProjectedGPA")
                        metric("Target GPA", targetGPA, identifier: "createPlanTargetGPA")
                    }
                }
                Label(targetStatusTitle, systemImage: targetStatusSymbol)
                    .foregroundStyle(targetStatusColor)
                    .accessibilityIdentifier("createPlanTargetFeasibility")
            }
        }
        .accessibilityIdentifier("createPlanSummary")
    }

    private var planControls: some View {
        AppSection("Plan basics", subtitle: "Set the finish line first") {
            HStack {
                TextField("Target GPA", text: $targetText)
                    .keyboardType(.decimalPad)
                    .roundedInputSurface()
                    .accessibilityIdentifier("createPlanTargetField")
                Text("/ 4.0").foregroundStyle(.secondary)
            }
            TextField("Plan name", text: $planName)
                .roundedInputSurface()
                .accessibilityIdentifier("createPlanNameField")
        }
    }

    private var courseScope: some View {
        AppSection("Courses to include", subtitle: "Use all eligible courses or choose a smaller scope") {
            Toggle("Include all eligible courses", isOn: Binding(
                get: { includeAllCourses },
                set: { value in
                    includeAllCourses = value
                    if value { selectedCourseIDs = Set(eligibleCourses.map(\.id)) }
                }
            ))
            .accessibilityIdentifier("createPlanIncludeAllToggle")
            ForEach(eligibleCourses) { course in
                Toggle(isOn: Binding(
                    get: { includeAllCourses || selectedCourseIDs.contains(course.id) },
                    set: { included in
                        includeAllCourses = false
                        if included { selectedCourseIDs.insert(course.id) }
                        else { selectedCourseIDs.remove(course.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: course.courseCode).font(.headline)
                        Text(course.currentGrade?.rawValue ?? "Current grade unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(Text(verbatim: AppLocalization.formatted(
                    "Include %@", locale: locale, course.courseCode
                )))
                .accessibilityIdentifier("createPlanCourse-\(course.courseCode)")
            }
        }
    }

    private var optionalAssumptions: some View {
        AppSection("Optional assumed grades", subtitle: "These are private planning inputs, not final records") {
            let pending = snapshot.courses.filter { $0.officialGrade.isPending && $0.isIncludedInGPA }
            if pending.isEmpty {
                Text("No pending letter-graded courses are available for assumptions.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(pending) { course in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: course.courseCode).font(.headline)
                            Text(course.currentGrade?.rawValue ?? "Current —")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Assumed grade", selection: Binding(
                            get: { assumedGrades[course.id] ?? course.currentGrade ?? .bPlus },
                            set: { assumedGrades[course.id] = $0 }
                        )) {
                            ForEach([CourseGrade.bPlus, .aMinus, .a]) { grade in
                                Text(grade.rawValue).tag(grade)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 210)
                        .accessibilityIdentifier("createPlanAssumption-\(course.courseCode)")
                    }
                }
            }
        }
    }

    private var createAction: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Button("Create Plan", systemImage: "arrow.right") { createPlan() }
                .buttonStyle(.glass(.regular.tint(.accentColor.opacity(0.24)).interactive()))
                .buttonBorderShape(.capsule)
                .font(.headline)
                .accessibilityIdentifier("createPlanButton")
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: Decimal?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(DecimalFormatters.string(value, precision: preferences.decimalPrecision))
                .font(DesignSystem.Typography.metric).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(identifier)
    }

    private var targetStatusTitle: LocalizedStringKey {
        switch snapshot.targetStatus {
        case .reached: "Target reached"
        case .reachable: "Target is reachable"
        case .notReachable: "Target needs a stronger plan"
        case .noData: "Add grades to check the target"
        }
    }

    private var targetStatusSymbol: String {
        switch snapshot.targetStatus {
        case .reached, .reachable: "checkmark.circle"
        case .notReachable: "exclamationmark.triangle"
        case .noData: "questionmark.circle"
        }
    }

    private var targetStatusColor: Color {
        switch snapshot.targetStatus {
        case .reached, .reachable: DesignSystem.ColorToken.success
        case .notReachable: DesignSystem.ColorToken.warning
        case .noData: .secondary
        }
    }

    private func initializeIfNeeded() {
        guard !initialized else { return }
        initialized = true
        if includeAllCourses { selectedCourseIDs = Set(eligibleCourses.map(\.id)) }
    }

    private func createPlan() {
        let cleanName = planName.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = PlannerScenario(name: cleanName.isEmpty ? "My GPA plan" : cleanName,
                                    scenarioType: .custom,
                                    sortOrder: (savedPlans.map(\.sortOrder).max() ?? -1) + 1,
                                    targetGPA: targetGPA,
                                    selectedCourseIDs: includeAllCourses ? nil : selectedCourseIDs,
                                    assumedGrades: assumedGrades)
        modelContext.insert(saved)
        do {
            try modelContext.save()
            savedScenario = GPAPlanningScenarioInput(id: saved.id, name: saved.name,
                                                     targetGPA: targetGPA,
                                                     selectedCourseIDs: includeAllCourses ? nil : selectedCourseIDs,
                                                     assumedGrades: assumedGrades)
            message = "Plan created. Opening Full Simulation."
            showSimulation = true
        } catch {
            modelContext.rollback()
            message = "Couldn’t create this plan."
        }
    }
}
