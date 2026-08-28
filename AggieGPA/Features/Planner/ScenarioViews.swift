import SwiftData
import SwiftUI

/// Saved / pinned plans store inputs only. Opening one always resolves against
/// the latest gradebook through GPAPlanningEngine.
struct ScenarioListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlannerScenario.sortOrder, order: .reverse) private var scenarios: [PlannerScenario]
    @Query private var courses: [CourseRecord]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    let preferences: UserPreferences

    private var inputs: [GPAPlanningCourseInput] {
        GPAPlanningEngine.makeInputs(courses: courses, policies: policies, categories: categories,
                                     items: items, scales: scales, forecasts: forecasts)
    }

    var body: some View {
        List {
            if scenarios.isEmpty {
                ContentUnavailableView("No saved plans", systemImage: "pin.slash",
                                       description: Text("Create a plan from GPA Overview to save its inputs."))
            }
            ForEach(scenarios) { scenario in
                let input = GPAPlanningEngine.scenario(from: scenario, fallbackTarget: preferences.targetGPA)
                let snapshot = GPAPlanningEngine.resolve(inputs: inputs, scenario: input, fallbackTargetUnits: 12)
                NavigationLink {
                    GPAFullSimulationView(preferences: preferences, initialScenario: input)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(verbatim: scenario.name).font(.headline)
                            Spacer()
                            Image(systemName: "pin.fill").foregroundStyle(DesignSystem.ColorToken.gold)
                        }
                        Text("Current \(DecimalFormatters.string(snapshot.current.gpa, precision: preferences.decimalPrecision)) · Projected \(DecimalFormatters.string(snapshot.projected.gpa, precision: preferences.decimalPrecision))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("Target \(DecimalFormatters.string(input.targetGPA, precision: preferences.decimalPrecision)) · \(snapshot.courses.count) courses")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                }
                .accessibilityIdentifier("savedPlan-\(scenario.id.uuidString)")
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(scenario) }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        modelContext.delete(scenario)
                        try? modelContext.save()
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { scenarios[$0] }.forEach(modelContext.delete)
                try? modelContext.save()
            }
        }
        .navigationTitle("Saved Plans")
        .accessibilityIdentifier("gpaSavedPlansList")
    }

    private func duplicate(_ scenario: PlannerScenario) {
        let copy = PlannerScenario(
            name: scenario.name + " Copy",
            scenarioType: scenario.scenarioType,
            sortOrder: (scenarios.map(\.sortOrder).max() ?? -1) + 1,
            targetGPA: scenario.targetGPA,
            selectedCourseIDs: scenario.selectedCourseIDs,
            assumedGrades: scenario.assumedGrades
        )
        modelContext.insert(copy)
        try? modelContext.save()
    }
}

/// Compatibility destination retained for old serialized routes. It now opens
/// the shared Create Plan flow rather than maintaining a second GPA calculator.
@available(*, deprecated, message: "Use TargetGPAView")
struct FutureQuarterPlannerView: View {
    let preferences: UserPreferences

    var body: some View {
        TargetGPAView(preferences: preferences)
    }
}
