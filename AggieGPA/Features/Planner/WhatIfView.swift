import SwiftData
import SwiftUI

private struct WhatIfItem: Identifiable {
    let id: UUID
    let sourceID: UUID?
    var code: String
    var units: Decimal
    var grade: CourseGrade
    var included: Bool
    var major: Bool
    var upper: Bool
}

struct WhatIfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var courses: [CourseRecord]
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    let preferences: UserPreferences
    @State private var items: [WhatIfItem] = []
    @State private var scenarioName = "Expected"
    @State private var showingApplyConfirmation = false
    @State private var statusMessage: String?

    private var officialInputs: [CourseCalculationInput] { courses.map(CourseCalculationInput.init) }
    private var simulatedInputs: [CourseCalculationInput] {
        items.map { CourseCalculationInput(id: $0.id, courseCode: $0.code, units: $0.units,
                                           grade: $0.grade, isIncludedInGPA: $0.included,
                                           isMajorCourse: $0.major, isUpperDivision: $0.upper) }
    }
    private var official: GPAResult { GPAService.cumulative(officialInputs) }
    private var simulated: GPAResult { GPAService.cumulative(simulatedInputs) }

    var body: some View {
        List {
            Section {
                HStack {
                    metric("Official", official.gpa)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    metric("What-If", simulated.gpa)
                }
                .frame(maxWidth: .infinity)
                if let lhs = official.gpa, let rhs = simulated.gpa {
                    let delta = rhs - lhs
                    Label("\(delta >= 0 ? "Increase" : "Decrease") of \(DecimalFormatters.string(abs(delta), precision: 3))",
                          systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(delta >= 0 ? .green : .orange)
                }
            }
            Section("Simulated courses") {
                ForEach($items) { $item in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(item.code).font(.headline)
                            Spacer()
                            Picker("Grade", selection: $item.grade) {
                                ForEach(CourseGrade.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                            }.labelsHidden()
                        }
                        HStack {
                            Text("\(DecimalFormatters.compact(item.units)) units").foregroundStyle(.secondary)
                            Spacer()
                            Toggle("Include", isOn: $item.included).labelsHidden()
                        }.font(.caption)
                    }
                }
                .onDelete { items.remove(atOffsets: $0) }
                Button("Add planned course", systemImage: "plus") {
                    items.append(WhatIfItem(id: UUID(), sourceID: nil, code: "PLANNED",
                                            units: 4, grade: .a, included: true, major: false, upper: false))
                }
            }
            Section("Save this forecast") {
                TextField("Scenario name", text: $scenarioName)
                Button("Save Scenario", systemImage: "square.and.arrow.down") { saveScenario() }
                Button("Reset Scenario", systemImage: "arrow.counterclockwise") { loadOfficial() }
                Text("Saving a forecast never changes official grades or GPA.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Apply to official records") {
                Label("This writes simulated grades to your official course records.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(DesignSystem.ColorToken.warning)
                Button("Save to Records", systemImage: "checkmark.seal") { showingApplyConfirmation = true }
                    .disabled(terms.isEmpty)
                    .tint(DesignSystem.ColorToken.warning)
            }
            if let statusMessage { Section { Text(LocalizedStringKey(statusMessage)).foregroundStyle(.secondary) } }
            Section {
                Text("What-If changes stay separate until you explicitly choose Save to Records.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("What-If GPA")
        .onAppear { if items.isEmpty { loadOfficial() } }
        .confirmationDialog("Apply this scenario to official records?", isPresented: $showingApplyConfirmation,
                            titleVisibility: .visible) {
            Button("Apply Changes") { applyToRecords() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing matching courses will receive the simulated grades. New planned courses will be added to the most recent quarter.")
        }
    }

    private func metric(_ title: String, _ value: Decimal?) -> some View {
        VStack { Text(title).font(.caption).foregroundStyle(.secondary); Text(DecimalFormatters.string(value, precision: preferences.decimalPrecision)).font(.title.bold()) }
            .frame(maxWidth: .infinity)
    }

    private func loadOfficial() {
        items = courses.map { WhatIfItem(id: $0.id, sourceID: $0.id, code: $0.courseCode,
                                         units: $0.units, grade: $0.grade, included: $0.isIncludedInGPA,
                                         major: $0.isMajorCourse, upper: $0.isUpperDivision) }
        statusMessage = nil
    }

    private func saveScenario() {
        let scenario = PlannerScenario(name: scenarioName.isEmpty ? "Custom" : scenarioName)
        modelContext.insert(scenario)
        for item in items {
            modelContext.insert(SimulatedCourse(sourceCourseID: item.sourceID, courseCode: item.code,
                                                 units: item.units, grade: item.grade,
                                                 isIncludedInGPA: item.included, isMajorCourse: item.major,
                                                 isUpperDivision: item.upper, scenario: scenario))
        }
        try? modelContext.save()
        statusMessage = "Scenario saved. Official records were not changed."
    }

    private func applyToRecords() {
        guard let targetTerm = terms.last else { return }
        for item in items {
            if let source = courses.first(where: { $0.id == item.sourceID }) {
                source.grade = item.grade
                source.units = item.units
                source.isIncludedInGPA = item.included
                source.updatedAt = .now
            } else {
                modelContext.insert(CourseRecord(courseCode: item.code, units: item.units,
                                                 grade: item.grade, term: targetTerm,
                                                 isMajorCourse: item.major, isUpperDivision: item.upper,
                                                 isIncludedInGPA: item.included))
            }
        }
        try? modelContext.save()
        statusMessage = "Scenario applied to records."
    }
}
