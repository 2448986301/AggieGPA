import SwiftData
import SwiftUI

private enum WhatIfPreset: String, CaseIterable, Identifiable {
    case conservative = "Conservative"
    case expected = "Expected"
    case optimistic = "Optimistic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conservative: String(localized: "Conservative")
        case .expected: String(localized: "Expected")
        case .optimistic: String(localized: "Optimistic")
        }
    }

    var percentage: Double {
        switch self {
        case .conservative: 70
        case .expected: 85
        case .optimistic: 95
        }
    }

    var scenarioKind: ForecastScenarioKind {
        switch self {
        case .conservative: .conservative
        case .expected: .expected
        case .optimistic: .bestCase
        }
    }
}

struct WhatIfPlaygroundView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let course: CourseRecord
    let policy: CourseGradingPolicy?
    let categories: [GradingCategory]
    let items: [GradeItem]
    let gradeScale: GradeScale?
    let scenarios: [ForecastScenario]
    let allCourses: [CourseRecord]

    @State private var preset: WhatIfPreset
    @State private var defaultAssumption: Double
    @State private var assumptions: [UUID: Double]
    @State private var scenarioName: String
    @State private var savedConfirmation: String?
    @State private var showsFineTuning = false
    @State private var showsScenarioTools = false

    init(
        course: CourseRecord,
        policy: CourseGradingPolicy?,
        categories: [GradingCategory],
        items: [GradeItem],
        gradeScale: GradeScale?,
        scenarios: [ForecastScenario],
        allCourses: [CourseRecord],
        selectedScenario: ForecastScenario?
    ) {
        self.course = course
        self.policy = policy
        self.categories = categories
        self.items = items
        self.gradeScale = gradeScale
        self.scenarios = scenarios
        self.allCourses = allCourses

        let startingValue = selectedScenario.map { decimalDouble($0.assumedRemainingPercentage) } ?? WhatIfPreset.expected.percentage
        let startingPreset = WhatIfPreset.allCases.first { $0.percentage == startingValue } ?? .expected
        let ungraded = items.filter(Self.isAdjustable)
        _preset = State(initialValue: startingPreset)
        _defaultAssumption = State(initialValue: startingValue)
        _assumptions = State(initialValue: Dictionary(uniqueKeysWithValues: ungraded.map { item in
            (item.id, selectedScenario?.itemAssumptions[item.id].map(decimalDouble) ?? startingValue)
        }))
        _scenarioName = State(initialValue: selectedScenario?.name ?? startingPreset.displayName)
    }

    private var adjustableItems: [GradeItem] {
        items.filter(Self.isAdjustable).sorted {
            ($0.dueDate ?? .distantFuture, $0.title) < ($1.dueDate ?? .distantFuture, $1.title)
        }
    }

    private var forecastInput: CourseForecastInput {
        CourseForecastInput(
            assumedRemainingPercentage: roundedDecimal(defaultAssumption),
            itemPercentages: Dictionary(uniqueKeysWithValues: assumptions.map { ($0.key, roundedDecimal($0.value)) })
        )
    }

    private var result: CourseGradeCalculationResult {
        CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course,
            policy: policy,
            categories: categories,
            items: items,
            gradeScale: gradeScale,
            forecastInput: forecastInput
        ))
    }

    private var currentResult: CourseGradeCalculationResult {
        CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course,
            policy: policy,
            categories: categories,
            items: items,
            gradeScale: gradeScale,
            forecast: nil as ForecastScenario?
        ))
    }

    private var projectedTermGPA: Decimal? {
        guard let projectedGrade = ProjectedGPAService.courseGrade(from: result.projectedLetterGrade) else { return nil }
        return ProjectedGPAService.calculate(
            allCourses.filter { !$0.isDeleted }.map(CourseCalculationInput.init),
            projectedGrades: [course.id: projectedGrade],
            termID: course.term?.id
        ).projected.gpa
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            HStack {
                Label("What-If Playground", systemImage: "slider.horizontal.3")
                    .font(.title3.bold())
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise") { reset() }
                    .buttonStyle(.glass(.regular.interactive()))
                    .buttonBorderShape(.capsule)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("whatIfResetButton")
            }

            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                    controls
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    outcome
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                controls
                outcome
            }

            Button {
                withAnimation(DesignSystem.Motion.quick(reduceMotion: reduceMotion)) {
                    showsScenarioTools.toggle()
                }
            } label: {
                scenarioToolsLabel
            }
            .buttonStyle(.glass(.regular.interactive()))
            .buttonBorderShape(.roundedRectangle(radius: DesignSystem.Radius.compact))
            .foregroundStyle(.primary)

            if showsScenarioTools {
                scenarioComparison
                saveControls
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: result.projectedLetterGrade?.rawValue)
        .animation(
            reduceMotion ? nil : DesignSystem.Motion.quick(reduceMotion: false),
            value: result.projectedFinalPercentage
        )
        .accessibilityIdentifier("whatIfPlayground")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Picker("Assumption preset", selection: $preset) {
                ForEach(WhatIfPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: preset) { _, newValue in apply(newValue) }

            if adjustableItems.isEmpty {
                ContentUnavailableView(
                    "No remaining work",
                    systemImage: "checkmark.circle",
                    description: Text("Add an ungraded assignment or exam to explore outcomes.")
                )
            } else {
                Button {
                    withAnimation(DesignSystem.Motion.quick(reduceMotion: reduceMotion)) {
                        showsFineTuning.toggle()
                    }
                } label: {
                    fineTuningLabel
                }
                .buttonStyle(.glass(.regular.interactive()))
                .buttonBorderShape(.roundedRectangle(radius: DesignSystem.Radius.compact))
                .foregroundStyle(.primary)

                if showsFineTuning {
                    VStack(spacing: 0) {
                        ForEach(adjustableItems) { item in
                            assumptionRow(item)
                            if item.id != adjustableItems.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .contentSurface()
                    .transition(.opacity)
                }
            }
        }
    }

    private func assumptionRow(_ item: GradeItem) -> some View {
        let binding = assumptionBinding(for: item)
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(LocalizedStringKey(item.category?.name ?? "Unassigned"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Percent", value: binding, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(item.title) assumed percentage")
                Text("%").foregroundStyle(.secondary)
            }
            HStack(spacing: DesignSystem.Spacing.small) {
                Slider(value: binding, in: 0...100, step: 1)
                    .accessibilityLabel("\(item.title) assumption")
                Stepper("", value: binding, in: 0...100, step: 1)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .padding(.vertical, DesignSystem.Spacing.small)
    }

    private var outcome: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Live outcome").font(.headline)
            HStack(spacing: DesignSystem.Spacing.small) {
                metric(
                    "Current grade",
                    currentResult.calculatedCurrentPercentage.map(formattedPercent) ?? "—",
                    detail: currentResult.currentLetterGrade?.rawValue ?? "Based on graded work"
                )
                metric(
                    "Predicted final",
                    result.projectedFinalPercentage.map(formattedPercent) ?? "—",
                    detail: result.projectedLetterGrade?.rawValue ?? "Letter unavailable"
                )
            }
            HStack(spacing: DesignSystem.Spacing.small) {
                metric(
                    "Projected term GPA",
                    projectedTermGPA.map { DecimalFormatters.string($0, precision: 3) } ?? "—",
                    detail: course.term?.displayName ?? "Current term"
                )
                metric(
                    "Distance to target",
                    targetDistance,
                    detail: targetDetail
                )
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
    }

    @ViewBuilder private var fineTuningLabel: some View {
        if showsFineTuning {
            Label("Hide assignment details", systemImage: "chevron.up")
                .frame(maxWidth: .infinity)
        } else {
            Label("Fine-tune assignments", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var scenarioToolsLabel: some View {
        if showsScenarioTools {
            Label("Hide saved plans", systemImage: "chevron.up")
                .frame(maxWidth: .infinity)
        } else if scenarios.isEmpty {
            Label("Save this plan", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        } else {
            HStack {
                Label("Saved plans", systemImage: "square.and.arrow.down")
                Text("\(scenarios.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.08), in: Capsule())
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var scenarioComparison: some View {
        if !scenarios.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Saved comparisons").font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        ForEach(scenarios) { scenario in
                            let scenarioResult = result(for: scenario)
                            Button {
                                load(scenario)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(scenario.name).fontWeight(.semibold)
                                    Text(scenarioResult.projectedFinalPercentage.map(formattedPercent) ?? "—")
                                        .font(.headline.monospacedDigit())
                                    Text(scenarioResult.projectedLetterGrade?.rawValue ?? "No letter")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minWidth: 112, alignment: .leading)
                            }
                            .buttonStyle(.glass(.regular.interactive()))
                            .buttonBorderShape(.roundedRectangle(radius: DesignSystem.Radius.compact))
                            .foregroundStyle(.primary)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var saveControls: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack(spacing: DesignSystem.Spacing.small) {
                TextField("Scenario name", text: $scenarioName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("whatIfScenarioName")
                Button("Save Scenario", systemImage: "square.and.arrow.down") { saveScenario() }
                    .buttonStyle(.glass(.regular.tint(.accentColor.opacity(0.24)).interactive()))
                    .buttonBorderShape(.capsule)
                    .foregroundStyle(.primary)
                    .disabled(scenarioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveWhatIfScenario")
            }
            if let savedConfirmation {
                Label(savedConfirmation, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Text("Assumptions stay separate from recorded scores and official grades.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var targetDistance: String {
        guard let target = policy?.targetPercentage, let projected = result.projectedFinalPercentage else { return "—" }
        let distance = projected - target
        let prefix = distance > 0 ? "+" : ""
        return "\(prefix)\(DecimalFormatters.string(distance, precision: 1))%"
    }

    private var targetDetail: String {
        guard let target = policy?.targetPercentage else { return "Set a target first" }
        return String(
            format: String(localized: "Target: %@"),
            "\(compact(target))%"
        )
    }

    private func assumptionBinding(for item: GradeItem) -> Binding<Double> {
        Binding(
            get: { assumptions[item.id] ?? defaultAssumption },
            set: { assumptions[item.id] = min(100, max(0, $0)) }
        )
    }

    private func apply(_ preset: WhatIfPreset) {
        defaultAssumption = preset.percentage
        assumptions = Dictionary(uniqueKeysWithValues: adjustableItems.map { ($0.id, preset.percentage) })
        scenarioName = preset.displayName
        savedConfirmation = nil
    }

    private func reset() {
        apply(.expected)
        showsFineTuning = false
    }

    private func load(_ scenario: ForecastScenario) {
        defaultAssumption = decimalDouble(scenario.assumedRemainingPercentage)
        assumptions = Dictionary(uniqueKeysWithValues: adjustableItems.map { item in
            (item.id, scenario.itemAssumptions[item.id].map(decimalDouble) ?? defaultAssumption)
        })
        scenarioName = scenario.name
        savedConfirmation = nil
    }

    private func saveScenario() {
        let cleanName = scenarioName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        for candidate in scenarios { candidate.isSelectedForGPAForecast = false }
        let saved = ForecastScenario(
            course: course,
            name: cleanName,
            kind: preset.scenarioKind,
            assumedRemainingPercentage: roundedDecimal(defaultAssumption),
            itemAssumptions: forecastInput.itemPercentages,
            isSelectedForGPAForecast: true
        )
        modelContext.insert(saved)
        do {
            try modelContext.save()
            withAnimation(DesignSystem.Motion.quick(reduceMotion: reduceMotion)) {
                savedConfirmation = String(localized: "Plan saved")
            }
        } catch {
            modelContext.rollback()
        }
    }

    private func result(for scenario: ForecastScenario) -> CourseGradeCalculationResult {
        CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course,
            policy: policy,
            categories: categories,
            items: items,
            gradeScale: gradeScale,
            forecast: scenario
        ))
    }

    private static func isAdjustable(_ item: GradeItem) -> Bool {
        item.earnedPoints == nil && item.status != .graded && !item.isDropped && !item.isExcused && item.isIncluded
    }

    private func roundedDecimal(_ value: Double) -> Decimal {
        Decimal(Int(value.rounded()))
    }

    private func formattedPercent(_ value: Decimal) -> String {
        "\(compact(value))%"
    }
}
