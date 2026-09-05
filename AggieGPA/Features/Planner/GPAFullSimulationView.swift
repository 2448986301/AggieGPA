import SwiftData
import SwiftUI

/// Full Simulation is the What-If experience. It edits scenario
/// inputs only; the shared planning engine recalculates Projected GPA on every
/// change and never writes an official course grade.
struct GPAFullSimulationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var hasInitializedSelection = false
    @State private var savedMessage: String?
    @State private var cachedPlanningInputs: [GPAPlanningCourseInput] = []
    @State private var cachedSnapshot: GPAPlanningSnapshot
    @State private var scenarioPersistenceTask: Task<Void, Never>?

    init(preferences: UserPreferences, initialScenario: GPAPlanningScenarioInput? = nil) {
        self.preferences = preferences
        self.initialScenario = initialScenario
        let scenario = initialScenario ?? GPAPlanningScenarioInput(targetGPA: preferences.targetGPA)
        _targetText = State(initialValue: DecimalFormatters.compact(scenario.targetGPA))
        _planName = State(initialValue: scenario.name == "Current plan" ? "My GPA plan" : scenario.name)
        _selectedCourseIDs = State(initialValue: scenario.selectedCourseIDs ?? [])
        _includeAllCourses = State(initialValue: scenario.selectedCourseIDs == nil)
        _assumedGrades = State(initialValue: scenario.assumedGrades)
        _cachedSnapshot = State(initialValue: GPAPlanningEngine.resolve(
            inputs: [],
            scenario: scenario,
            fallbackTargetUnits: 12
        ))
    }

    private var planningInputs: [GPAPlanningCourseInput] {
        cachedPlanningInputs
    }

    private var targetGPA: Decimal {
        DecimalFormatters.decimal(from: targetText) ?? preferences.targetGPA
    }

    private var scenario: GPAPlanningScenarioInput {
        GPAPlanningScenarioInput(
            id: initialScenario?.id,
            name: planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My GPA plan" : planName,
            targetGPA: targetGPA,
            selectedCourseIDs: includeAllCourses ? nil : selectedCourseIDs,
            assumedGrades: assumedGrades
        )
    }

    private var snapshot: GPAPlanningSnapshot {
        cachedSnapshot
    }

    private var planningDataRevision: Int {
        var hasher = Hasher()
        for course in courses { hasher.combine(course.id); hasher.combine(course.updatedAt) }
        for policy in policies { hasher.combine(policy.id); hasher.combine(policy.updatedAt) }
        for category in categories { hasher.combine(category.id); hasher.combine(category.updatedAt) }
        for item in items { hasher.combine(item.id); hasher.combine(item.updatedAt) }
        for scale in scales { hasher.combine(scale.id); hasher.combine(scale.updatedAt) }
        for forecast in forecasts { hasher.combine(forecast.id); hasher.combine(forecast.updatedAt) }
        for plan in savedPlans { hasher.combine(plan.id); hasher.combine(plan.updatedAt) }
        return hasher.finalize()
    }

    private var selectableCourses: [GPAPlanningCourseState] {
        snapshot.courses.filter { $0.isIncludedInGPA }
    }

    var body: some View {
        ZStack {
            CampusBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    summary
                    targetSection
                    courseSection
                    impactSection
                    saveSection
                }
                .frame(maxWidth: 1_180, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.large)
            }
            .safeAreaPadding(.bottom, horizontalSizeClass == .compact ? 96 : DesignSystem.Spacing.large)
        }
        .navigationTitle("Full Simulation")
        .navigationBarTitleDisplayMode(.inline)
        // Let iOS 27 reveal the navigation material only after content reaches
        // the scroll edge; an always-visible material creates a large opaque
        // band over the initial What-If content.
        .toolbarBackground(.automatic, for: .navigationBar)
        .onAppear { initializeSelectionIfNeeded() }
        .task(id: planningDataRevision) { refreshPlanningCache() }
        .animation(DesignSystem.Motion.quick(reduceMotion: reduceMotion), value: snapshot.projected.gpa)
        .accessibilityIdentifier("gpaFullSimulation")
    }

    private var summary: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                Text("GPA path").font(.headline)
                if let final = snapshot.final?.gpa {
                    metric("Final GPA", final, identifier: "fullSimulationFinalGPA")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DesignSystem.Spacing.large) {
                        metric("Current GPA", snapshot.current.gpa, identifier: "fullSimulationCurrentGPA")
                        metric("Projected GPA", snapshot.projected.gpa, identifier: "fullSimulationProjectedGPA")
                        metric("Target GPA", snapshot.targetGPA, identifier: "fullSimulationTargetGPA")
                    }
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        metric("Current GPA", snapshot.current.gpa, identifier: "fullSimulationCurrentGPA")
                        metric("Projected GPA", snapshot.projected.gpa, identifier: "fullSimulationProjectedGPA")
                        metric("Target GPA", snapshot.targetGPA, identifier: "fullSimulationTargetGPA")
                    }
                }
                if snapshot.eligibleCourseCount > 0 {
                    Text(verbatim: finalGradeProgressText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("fullSimulationFinalGradeProgress")
                }
                if let delta = snapshot.deltaToTarget {
                    Label(AppCopy.targetDelta(delta, locale: locale),
                          systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(delta >= 0 ? DesignSystem.ColorToken.success : DesignSystem.ColorToken.warning)
                        .accessibilityIdentifier("fullSimulationTargetDelta")
                }
            }
        }
        .accessibilityIdentifier("gpaSimulationSummary")
    }

    private var targetSection: some View {
        AppSection("Target and scope", subtitle: "Choose the courses this plan should include") {
            HStack {
                TextField("Target GPA", text: $targetText)
                    .keyboardType(.decimalPad)
                    .roundedInputSurface()
                    .accessibilityIdentifier("gpaSimulationTargetField")
                Text("/ 4.0").foregroundStyle(.secondary)
            }
            Toggle("Include all eligible courses", isOn: Binding(
                get: { includeAllCourses },
                set: { newValue in
                    includeAllCourses = newValue
                    if newValue { selectedCourseIDs = Set(planningInputs.filter(\.isGPAEligible).map(\.id)) }
                }
            ))
            .accessibilityIdentifier("gpaSimulationIncludeAllToggle")
            if let targetResult = snapshot.targetResult {
                Label(targetStatusText(targetResult), systemImage: targetStatusSymbol)
                    .foregroundStyle(targetStatusColor)
                    .accessibilityIdentifier("gpaSimulationTargetFeasibility")
            }
        }
    }

    private var courseSection: some View {
        AppSection("Courses and scenarios", subtitle: "Current is where you are; choose a grade to preview the finish") {
            if selectableCourses.isEmpty {
                Text("No GPA-eligible courses are in this plan.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(selectableCourses) { course in
                        courseRow(course)
                        if course.id != selectableCourses.last?.id { Divider() }
                    }
                }
            }
        }
        .accessibilityIdentifier("gpaSimulationCourses")
    }

    private func courseRow(_ course: GPAPlanningCourseState) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: course.courseCode).font(.headline)
                    if let title = course.courseTitle.nilIfEmpty { Text(verbatim: title).font(.caption).foregroundStyle(.secondary) }
                    Text(verbatim: courseStageDescription(course))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !includeAllCourses && course.officialGrade.isPending {
                    Toggle("Include", isOn: Binding(
                        get: { selectedCourseIDs.contains(course.id) },
                        set: { included in
                            if included { selectedCourseIDs.insert(course.id) }
                            else { selectedCourseIDs.remove(course.id) }
                        }
                    ))
                    .labelsHidden()
                    .accessibilityLabel(Text(verbatim: AppLocalization.formatted(
                        "Include %@", locale: locale, course.courseCode
                    )))
                }
            }
            if course.officialGrade.isPending {
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    ForEach(alternativeIDs(for: course), id: \.self) { rawValue in
                        Button(rawValue) {
                            if let grade = CourseGrade(rawValue: rawValue) {
                                setAssumption(grade, for: course.id)
                            }
                        }
                        .modifier(GradeAlternativeButtonStyle(isSelected: course.selectedGrade?.rawValue == rawValue))
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .accessibilityIdentifier("gpaSimulationGrade-\(course.courseCode)-\(rawValue)")
                    }
                    if assumedGrades[course.id] != nil {
                        Button("Use Current") { clearAssumption(for: course.id) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                    Spacer()
                    Text(DecimalFormatters.string(snapshot.projected.gpa, precision: preferences.decimalPrecision))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                        .accessibilityIdentifier("gpaSimulationCourseImpact-\(course.courseCode)")
                }
            }
        }
        .padding(.vertical, DesignSystem.Spacing.small)
        .opacity(includeAllCourses || selectedCourseIDs.contains(course.id) || !course.officialGrade.isPending ? 1 : 0.52)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gpaSimulationCourse-\(course.courseCode)")
    }

    private var impactSection: some View {
        AppSection("Impact and opportunity") {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                impactMetric("GPA impact", value: snapshot.deltaToTarget)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Target").font(.caption).foregroundStyle(.secondary)
                    Text(targetStatusTitle).font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let opportunity = snapshot.biggestOpportunity {
                AppInteractiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Biggest Opportunity").font(.headline)
                        Text(verbatim: opportunity.courseCode)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } trailing: {
                    Text("\(opportunity.from.rawValue) → \(opportunity.to.rawValue)")
                        .font(.headline.monospaced())
                }
                .accessibilityIdentifier("gpaSimulationBiggestOpportunity")
            }
        }
        .accessibilityIdentifier("gpaSimulationImpact")
    }

    private var saveSection: some View {
        AppSection("Save this plan", subtitle: "Only the inputs are saved; results recalculate from current course data") {
            TextField("Plan name", text: $planName)
                .roundedInputSurface()
                .accessibilityIdentifier("gpaSimulationPlanName")
            Button("Save Plan", systemImage: "pin") { savePlan() }
                .buttonStyle(.glass(.regular.tint(.accentColor.opacity(0.24)).interactive()))
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("gpaSimulationSavePlan")
            NavigationLink { ScenarioListView(preferences: preferences) } label: {
                Label("View Saved Plans", systemImage: "pin")
            }
            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(DesignSystem.ColorToken.success)
                    .accessibilityIdentifier("gpaSimulationSavedMessage")
            }
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: Decimal?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(DecimalFormatters.string(value, precision: preferences.decimalPrecision))
                .font(DesignSystem.Typography.metric).monospacedDigit()
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func impactMetric(_ title: LocalizedStringKey, value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map { ($0 >= 0 ? "+" : "") + DecimalFormatters.compact($0) } ?? "—")
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func alternatives(for course: GPAPlanningCourseState) -> [CourseGrade] {
        var values: [CourseGrade] = [.bPlus, .aMinus, .a]
        if let current = course.currentGrade, !values.contains(current) { values.insert(current, at: 0) }
        return values
    }

    private func alternativeIDs(for course: GPAPlanningCourseState) -> [String] {
        alternatives(for: course).map(\.rawValue)
    }

    private func courseStageDescription(_ course: GPAPlanningCourseState) -> String {
        switch course.stage {
        case .final:
            return String(
                format: AppLocalization.string("Final %@", locale: locale),
                locale: locale,
                course.finalGrade?.rawValue ?? course.officialGrade.rawValue
            )
        case .projected:
            let projected = course.selectedGrade?.rawValue ?? "—"
            let percentage = course.projectedPercentage.map { value in
                let formatted = DecimalFormatters.compact(value)
                return course.projectedPercentageIsBoundary ? "≥\(formatted)%" : "\(formatted)%"
            }
            let value = [percentage, projected].compactMap { $0 }.joined(separator: " · ")
            return String(
                format: AppLocalization.string("Projected %@", locale: locale),
                locale: locale,
                value
            )
        case .current:
            return String(
                format: AppLocalization.string("Current %@ · Choose projected", locale: locale),
                locale: locale,
                course.currentGrade?.rawValue ?? "—"
            )
        case .excluded:
            return AppLocalization.string("Not included in GPA", locale: locale)
        case .unavailable:
            return AppLocalization.string("Current grade unavailable", locale: locale)
        }
    }

    private var finalGradeProgressText: String {
        String(
            format: AppLocalization.string("Final grades %lld of %lld available", locale: locale),
            locale: locale,
            Int64(snapshot.eligibleFinalGradeCount),
            Int64(snapshot.eligibleCourseCount)
        )
    }

    private var targetStatusTitle: LocalizedStringKey {
        switch snapshot.targetStatus {
        case .reached: "Target reached"
        case .reachable: "Target is reachable"
        case .notReachable: "Target needs a stronger plan"
        case .noData: "Need more grade data"
        }
    }

    private func targetStatusText(_ result: TargetGPAResult) -> LocalizedStringKey {
        result.isReachable ? "Target is reachable" : "Target is not reachable with this scope"
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

    private func initializeSelectionIfNeeded() {
        guard !hasInitializedSelection else { return }
        hasInitializedSelection = true
        if includeAllCourses {
            selectedCourseIDs = Set(planningInputs.filter(\.isGPAEligible).map(\.id))
        }
    }

    private func savePlan() {
        if GPAPlanningEngine.persistActiveScenario(
            scenario,
            in: modelContext,
            savedPlans: savedPlans
        ) != nil {
            savedMessage = "Plan saved. Results will recalculate from your current courses."
        } else {
            savedMessage = "Couldn’t save this plan."
        }
    }

    private func setAssumption(_ grade: CourseGrade, for courseID: UUID) {
        assumedGrades[courseID] = grade
        refreshSnapshot()
        // A selection is immediately active. The explicit Save Plan action
        // remains available for naming the scenario, but course rows and
        // course detail should never wait for a second hidden commit step.
        scheduleScenarioPersistence(scenario)
    }

    private func clearAssumption(for courseID: UUID) {
        assumedGrades.removeValue(forKey: courseID)
        refreshSnapshot()
        scheduleScenarioPersistence(scenario)
    }

    private func refreshPlanningCache() {
        cachedPlanningInputs = GPAPlanningEngine.makeInputs(
            courses: courses,
            policies: policies,
            categories: categories,
            items: items,
            scales: scales,
            forecasts: forecasts
        )
        refreshSnapshot()
    }

    private func refreshSnapshot() {
        cachedSnapshot = GPAPlanningEngine.resolve(
            inputs: cachedPlanningInputs,
            scenario: scenario,
            fallbackTargetUnits: 12
        )
    }

    private func scheduleScenarioPersistence(_ scenario: GPAPlanningScenarioInput) {
        scenarioPersistenceTask?.cancel()
        let plans = savedPlans
        scenarioPersistenceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                _ = GPAPlanningEngine.persistActiveScenario(
                    scenario,
                    in: modelContext,
                    savedPlans: plans
                )
            } catch {
                // A newer grade tap replaced this pending save.
            }
        }
    }
}

private struct GradeAlternativeButtonStyle: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
