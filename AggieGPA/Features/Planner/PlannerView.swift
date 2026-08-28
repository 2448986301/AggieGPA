import Charts
import SwiftData
import SwiftUI

/// GPA Overview. All displayed values come from GPAPlanningEngine so the
/// overview, Create Plan, Full Simulation, and saved plans cannot drift apart.
struct PlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query private var courses: [CourseRecord]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    @Query(sort: \PlannerScenario.sortOrder, order: .reverse) private var savedPlans: [PlannerScenario]
    let preferences: UserPreferences

    @State private var inlineAssumptions: [UUID: CourseGrade] = [:]
    @State private var showDemo = false
    @State private var showJourney = false
    @State private var showAllWhatIfCourses = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumberSize: CGFloat = 54

    private var heroNumberFontWeight: Font.Weight {
        (legibilityWeight ?? .regular) == .bold ? .heavy : .bold
    }

    private var includedTermIDs: Set<UUID> {
        Set(terms.filter { !$0.isDeleted && $0.isIncludedInCumulativeGPA }.map(\.id))
    }

    private var liveCourses: [CourseRecord] {
        courses.filter { course in
            guard !course.isDeleted else { return false }
            guard let termID = course.term?.id else { return true }
            return includedTermIDs.contains(termID)
        }
    }

    private var planningInputs: [GPAPlanningCourseInput] {
        GPAPlanningEngine.makeInputs(courses: liveCourses, policies: policies, categories: categories,
                                     items: items, scales: scales, forecasts: forecasts)
    }

    private var activeSavedPlan: PlannerScenario? {
        savedPlans.first { $0.scenarioType == .custom }
    }

    private var planningScenario: GPAPlanningScenarioInput {
        let saved = GPAPlanningEngine.scenario(from: activeSavedPlan, fallbackTarget: preferences.targetGPA)
        return GPAPlanningScenarioInput(
            id: saved.id,
            name: saved.name,
            targetGPA: saved.targetGPA,
            selectedCourseIDs: saved.selectedCourseIDs,
            assumedGrades: saved.assumedGrades.merging(inlineAssumptions) { _, inline in inline }
        )
    }

    private var snapshot: GPAPlanningSnapshot {
        GPAPlanningEngine.resolve(inputs: planningInputs, scenario: planningScenario, fallbackTargetUnits: 12)
    }

    private var hasGPAContext: Bool {
        snapshot.current.gpa != nil || snapshot.projected.gpa != nil || snapshot.final?.gpa != nil
    }

    private var pendingStates: [GPAPlanningCourseState] {
        snapshot.courses.filter { $0.officialGrade.isPending && $0.isIncludedInGPA }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CampusBackground()
                ScrollView {
                    Group {
                        if hasGPAContext {
                            if horizontalSizeClass == .regular {
                                iPadPlannerContent
                            } else {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xLarge) {
                                    hero
                                    createPlanLink
                                    journeyDisclosure
                                    biggestOpportunity
                                    whatIf
                                    pathToTarget
                                    savedPlansSection
                                }
                            }
                        } else {
                            emptyState
                        }
                    }
                    .frame(maxWidth: 1_180, alignment: .leading)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, DesignSystem.Spacing.large)
                }
                .safeAreaPadding(.bottom, horizontalSizeClass == .compact ? 96 : DesignSystem.Spacing.large)
            }
            .navigationTitle("GPA")
            // Keep the title compact inside the tab destination. The system
            // owns the scroll-edge material: it stays clear at rest and only
            // becomes glass when content crosses the navigation edge.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.automatic, for: .navigationBar)
            .sheet(isPresented: $showDemo) { GPAIsolatedDemoView() }
        }
        .accessibilityIdentifier("gpaOverview")
    }

    private var iPadPlannerContent: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xLarge) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xLarge) {
                AppCard { hero }
                createPlanLink
                if !journeyPoints.isEmpty { AppCard { journeyDisclosure } }
                savedPlansSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xLarge) {
                biggestOpportunity
                whatIf
                pathToTarget
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            if let final = snapshot.final?.gpa {
                Text(DecimalFormatters.string(final, precision: preferences.decimalPrecision))
                    .font(.system(size: heroNumberSize, weight: heroNumberFontWeight, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(DesignSystem.Motion.emphasized(reduceMotion: reduceMotion), value: final)
                    .accessibilityIdentifier("gpaHeroFinal")
                Text("Final GPA").font(.headline).foregroundStyle(.secondary)
            } else {
                Text(DecimalFormatters.string(snapshot.current.gpa, precision: preferences.decimalPrecision))
                    .font(.system(size: heroNumberSize, weight: heroNumberFontWeight, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(DesignSystem.Motion.emphasized(reduceMotion: reduceMotion), value: snapshot.current.gpa)
                    .accessibilityIdentifier("gpaHeroCurrent")
                Text("Current GPA").font(.headline).foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.large) {
                    if snapshot.final?.gpa != nil { heroMetric("Current", value: snapshot.current.gpa) }
                    heroMetric("Projected", value: snapshot.projected.gpa)
                        .accessibilityIdentifier("gpaHeroProjected")
                    heroMetric("Target", value: snapshot.targetGPA)
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    if snapshot.final?.gpa != nil { heroMetric("Current", value: snapshot.current.gpa) }
                    heroMetric("Projected", value: snapshot.projected.gpa)
                        .accessibilityIdentifier("gpaHeroProjected")
                    heroMetric("Target", value: snapshot.targetGPA)
                }
            }

            if snapshot.eligibleCourseCount > 0 {
                Text(verbatim: finalGradeProgressText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("gpaFinalGradeProgress")
            }

            if let delta = snapshot.deltaToTarget {
                Text(verbatim: AppCopy.targetDelta(delta, locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(delta >= 0 ? DesignSystem.ColorToken.success : DesignSystem.ColorToken.gold)
                    .accessibilityIdentifier("gpaTargetDelta")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gpaHero")
    }

    private func heroMetric(_ label: LocalizedStringKey, value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(DecimalFormatters.string(value, precision: preferences.decimalPrecision))
                .font(DesignSystem.Typography.metric)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(DesignSystem.Motion.emphasized(reduceMotion: reduceMotion), value: value)
        }
    }

    @ViewBuilder private var journey: some View {
        if !journeyPoints.isEmpty {
            AppSection("GPA Journey", subtitle: "Current, projected, and target") {
                VStack(alignment: .leading, spacing: 0) {
                    Chart {
                        ForEach(journeyPoints) { point in
                            if let current = point.current {
                                LineMark(x: .value("Term", point.label), y: .value("Current GPA", decimalDouble(current)))
                                    .foregroundStyle(DesignSystem.ColorToken.navyRaised)
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("Term", point.label), y: .value("Current GPA", decimalDouble(current)))
                                    .foregroundStyle(DesignSystem.ColorToken.navyRaised)
                            }
                            if let projected = point.projected, projected != point.current {
                                PointMark(x: .value("Term", point.label), y: .value("Projected GPA", decimalDouble(projected)))
                                    .symbolSize(90)
                                    .symbol(.diamond)
                                    .foregroundStyle(DesignSystem.ColorToken.gold)
                            }
                        }
                        RuleMark(y: .value("Target GPA", decimalDouble(snapshot.targetGPA)))
                            .foregroundStyle(DesignSystem.ColorToken.gold.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                    .chartYScale(domain: 0...4.1)
                    .chartYAxis { AxisMarks(values: [0, 1, 2, 3, 4]) }
                    .frame(minHeight: 210)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Chart's internal accessibility representation is not a
                // stable XCUI element across iOS releases. Expose one
                // semantic wrapper so VoiceOver and UI tests receive the
                // same localized summary without changing the visual chart.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: AppLocalization.string("GPA journey chart", locale: locale)))
                .accessibilityValue(journeyAccessibilitySummary)
                .accessibilityIdentifier("gpaJourneyChart")
            }
        }
    }

    @ViewBuilder private var journeyDisclosure: some View {
        if !journeyPoints.isEmpty {
            DisclosureGroup(isExpanded: $showJourney) {
                journey
            } label: {
                Label("View GPA journey", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("gpaJourneyDisclosure")
        }
    }

    @ViewBuilder private var biggestOpportunity: some View {
        AppSection("Biggest Opportunity") {
            if let opportunity = snapshot.biggestOpportunity {
                Group {
                    if horizontalSizeClass == .regular { opportunityContent(opportunity) }
                    else { AppCard { opportunityContent(opportunity) } }
                }
                .accessibilityIdentifier("gpaBiggestOpportunity")
            } else {
                Text("Add a projected grade to reveal the highest-impact course change.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func opportunityContent(_ opportunity: GPAPlanningOpportunity) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            AppInteractiveRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: opportunity.courseCode).font(.title3.bold())
                    Text("\(opportunity.from.rawValue) → \(opportunity.to.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } trailing: {
                Text("+\(DecimalFormatters.string(opportunity.gain, precision: 3))")
                    .font(.headline.monospaced())
                    .foregroundStyle(DesignSystem.ColorToken.gold)
            }
            NavigationLink {
                GPAFullSimulationView(preferences: preferences, initialScenario: planningScenario)
            } label: {
                Label("View Full Simulation", systemImage: "arrow.up.right")
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("gpaBiggestOpportunityAction")
        }
    }

    @ViewBuilder private var whatIf: some View {
        AppSection("What-If", subtitle: "Choose a projected grade; Current stays unchanged") {
            if pendingStates.isEmpty {
                Text("No current letter-graded courses are waiting for a grade.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Projected GPA uses a selected forecast. Courses without one continue using their Current grade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(visibleWhatIfStates) { state in
                        AppInteractiveRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: state.courseCode).font(.headline)
                                Text(currentAndProjectedDescription(for: state))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } trailing: {
                            HStack(spacing: DesignSystem.Spacing.xSmall) {
                                ForEach([CourseGrade.bPlus, .aMinus, .a]) { grade in
                                    assumptionButton(grade, courseID: state.id, courseCode: state.courseCode)
                                }
                            }
                        }
                        if state.id != visibleWhatIfStates.last?.id { Divider() }
                    }
                }
                .sensoryFeedback(.selection, trigger: inlineAssumptions)

                if pendingStates.count > visibleWhatIfStates.count {
                    Button(showAllWhatIfCourses ? "Show fewer courses" : "Choose another course") {
                        withAnimation(DesignSystem.Motion.quick(reduceMotion: reduceMotion)) {
                            showAllWhatIfCourses.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Projected GPA").font(.headline)
                    Spacer()
                    Text(DecimalFormatters.string(snapshot.projected.gpa, precision: preferences.decimalPrecision))
                        .font(DesignSystem.Typography.metric)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(DesignSystem.Motion.emphasized(reduceMotion: reduceMotion), value: snapshot.projected.gpa)
                        .accessibilityIdentifier("gpaWhatIfProjected")
                }

            }

        }
        .accessibilityIdentifier("gpaWhatIf")
    }

    private func assumptionButton(_ grade: CourseGrade, courseID: UUID, courseCode: String) -> some View {
        let selected = snapshot.courses.first(where: { $0.id == courseID }).map {
            $0.stage == .projected && $0.selectedGrade == grade
        } ?? false
        let identifier = "gpaOverviewAssume-\(courseCode)-\(grade.rawValue)"
        return Group {
            if selected {
                Button(grade.rawValue) { setAssumption(grade, for: courseID) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(identifier)
            } else {
                Button(grade.rawValue) { setAssumption(grade, for: courseID) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(identifier)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityLabel(Text(verbatim: AppLocalization.formatted(
            "Assume %@", locale: locale, grade.rawValue
        )))
    }

    private var pathToTarget: some View {
        AppSection("Path to Target") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                    pathMetric("Current", value: snapshot.current.gpa)
                    pathMetric("Projected", value: snapshot.projected.gpa)
                    pathMetric("Target", value: snapshot.targetGPA)
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    pathMetric("Current", value: snapshot.current.gpa)
                    pathMetric("Projected", value: snapshot.projected.gpa)
                    pathMetric("Target", value: snapshot.targetGPA)
                }
            }

            AppInteractiveRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(targetStatusTitle).font(.headline)
                    if let required = snapshot.targetResult?.requiredFutureGPA {
                        Text(verbatim: AppLocalization.formatted(
                            "Required future average: %@",
                            locale: locale,
                            DecimalFormatters.string(required, precision: 3)
                        ))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } trailing: {
                Image(systemName: targetStatusSymbol).foregroundStyle(targetStatusColor).accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("gpaPathToTarget")
    }

    private var createPlanLink: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            NavigationLink {
                TargetGPAView(preferences: preferences, initialScenario: planningScenario)
            } label: {
                Label("Create Plan", systemImage: "target")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("gpaBuildPlan")

            // Full Simulation remains reachable even when there are no pending
            // inline What-If rows (for example, when all courses are finalized).
            NavigationLink {
                GPAFullSimulationView(preferences: preferences, initialScenario: planningScenario)
            } label: {
                Label("Open Full Simulation", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("openFullSimulation")
        }
    }

    private func pathMetric(_ label: LocalizedStringKey, value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(DecimalFormatters.string(value, precision: preferences.decimalPrecision))
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var savedPlansSection: some View {
        if !savedPlans.isEmpty {
            AppSection("Saved Plans") {
                NavigationLink { ScenarioListView(preferences: preferences) } label: {
                    Label("View Saved Plans", systemImage: "pin")
                }
                .accessibilityIdentifier("gpaSavedPlans")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("See where your semester could take you.", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Add current courses or explore an isolated sample without changing your records.")
        } actions: {
            NavigationLink { QuartersView(preferences: preferences) } label: { Text("Add Courses") }
                .buttonStyle(.borderedProminent)
            Button("Try Demo") { showDemo = true }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 440)
        .accessibilityIdentifier("gpaEmptyState")
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

    private var journeyPoints: [GPAJourneyPoint] {
        terms.filter { !$0.isDeleted && $0.isIncludedInCumulativeGPA }.compactMap { term in
            let ids = Set(planningInputs.filter { $0.termID == term.id }.map(\.id))
            guard !ids.isEmpty else { return nil }
            let scopedInputs = planningInputs.filter { ids.contains($0.id) }
            let scopedScenario = GPAPlanningScenarioInput(
                targetGPA: planningScenario.targetGPA,
                selectedCourseIDs: ids,
                assumedGrades: planningScenario.assumedGrades.filter { ids.contains($0.key) }
            )
            let scoped = GPAPlanningEngine.resolve(inputs: scopedInputs, scenario: scopedScenario)
            guard scoped.current.gpa != nil || scoped.projected.gpa != nil else { return nil }
            return GPAJourneyPoint(termID: term.id, label: AppCopy.termName(term, locale: locale),
                                   current: scoped.current.gpa, projected: scoped.projected.gpa)
        }
    }

    private var journeyAccessibilitySummary: String {
        let current = DecimalFormatters.string(snapshot.current.gpa, precision: preferences.decimalPrecision)
        let projected = DecimalFormatters.string(snapshot.projected.gpa, precision: preferences.decimalPrecision)
        let target = DecimalFormatters.string(snapshot.targetGPA, precision: preferences.decimalPrecision)
        return AppLocalization.formatted(
            "GPA journey summary: Current %@, projected %@, target %@.",
            locale: locale,
            current,
            projected,
            target
        )
    }

    private func setAssumption(_ grade: CourseGrade, for courseID: UUID) {
        withAnimation(DesignSystem.Motion.emphasized(reduceMotion: reduceMotion)) {
            inlineAssumptions[courseID] = grade
        }
        // Keep the inline What-If control and Full Simulation on the same
        // active scenario. Course detail and course rows resolve this plan
        // immediately, so there is no second, view-local projection state.
        let saved = GPAPlanningEngine.scenario(from: activeSavedPlan, fallbackTarget: preferences.targetGPA)
        let selectedCourseIDs = saved.selectedCourseIDs.map { $0.union([courseID]) }
        let updated = GPAPlanningScenarioInput(
            id: saved.id,
            name: saved.name,
            targetGPA: saved.targetGPA,
            selectedCourseIDs: selectedCourseIDs,
            assumedGrades: saved.assumedGrades.merging([courseID: grade]) { _, new in new }
        )
        _ = GPAPlanningEngine.persistActiveScenario(
            updated,
            in: modelContext,
            savedPlans: savedPlans
        )
    }

    private var visibleWhatIfStates: [GPAPlanningCourseState] {
        if showAllWhatIfCourses { return pendingStates }
        return Array(pendingStates.prefix(horizontalSizeClass == .regular ? 4 : 3))
    }

    private func currentAndProjectedDescription(for state: GPAPlanningCourseState) -> String {
        let current = state.currentGrade?.rawValue ?? "—"
        if state.stage == .projected, let projected = state.projectedGrade {
            return String(
                format: AppLocalization.string("Current %@ · Projected %@", locale: locale),
                locale: locale,
                current,
                projected.rawValue
            )
        }
        return String(
            format: AppLocalization.string("Current %@ · Choose projected", locale: locale),
            locale: locale,
            current
        )
    }

    private var finalGradeProgressText: String {
        String(
            format: AppLocalization.string("Final grades %lld of %lld available", locale: locale),
            locale: locale,
            Int64(snapshot.eligibleFinalGradeCount),
            Int64(snapshot.eligibleCourseCount)
        )
    }
}

private struct GPAJourneyPoint: Identifiable {
    let termID: UUID
    let label: String
    let current: Decimal?
    let projected: Decimal?
    var id: UUID { termID }
}

private struct GPAIsolatedDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var assumption = CourseGrade.aMinus
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumberSize: CGFloat = 54

    private var heroNumberFontWeight: Font.Weight {
        (legibilityWeight ?? .regular) == .bold ? .heavy : .bold
    }

    private var projected: Decimal {
        switch assumption {
        case .bPlus: Decimal(string: "3.487")!
        case .aMinus: Decimal(string: "3.541")!
        case .a, .aPlus: Decimal(string: "3.583")!
        default: Decimal(string: "3.423")!
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xLarge) {
                    Text("3.423")
                        .font(.system(size: heroNumberSize, weight: heroNumberFontWeight, design: .rounded))
                        .monospacedDigit()
                    Text("Current GPA").font(.headline).foregroundStyle(.secondary)
                    AppSection("What-If") {
                        AppInteractiveRow { Text("CHE 002A").font(.headline) } trailing: {
                            Picker("Assumed grade", selection: $assumption) {
                                Text("B+").tag(CourseGrade.bPlus)
                                Text("A-").tag(CourseGrade.aMinus)
                                Text("A").tag(CourseGrade.a)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 220)
                        }
                        Text("Projected GPA \(DecimalFormatters.string(projected, precision: 3))")
                            .font(DesignSystem.Typography.metric)
                    }
                    Text("This demo never writes to SwiftData.").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(DesignSystem.Spacing.large)
            }
            .navigationTitle("GPA Demo")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
