import SwiftData
import SwiftUI

struct ScenarioListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlannerScenario.sortOrder) private var scenarios: [PlannerScenario]
    let preferences: UserPreferences

    var body: some View {
        List {
            if scenarios.isEmpty {
                ContentUnavailableView("No saved scenarios", systemImage: "square.3.layers.3d",
                                       description: Text("Save one from What-If or Future Quarter Planner."))
            }
            ForEach(scenarios) { scenario in
                let result = GPAService.cumulative(scenario.simulatedCourses.map(CourseCalculationInput.init))
                VStack(alignment: .leading, spacing: 6) {
                    Text(scenario.name).font(.headline)
                    Text("Scenario GPA \(DecimalFormatters.string(result.gpa, precision: preferences.decimalPrecision)) · \(scenario.simulatedCourses.count) courses")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(scenario) }
                    Button("Delete", systemImage: "trash", role: .destructive) { modelContext.delete(scenario); try? modelContext.save() }
                }
            }
            .onDelete { offsets in offsets.map { scenarios[$0] }.forEach(modelContext.delete); try? modelContext.save() }
        }
        .navigationTitle("Scenarios")
    }

    private func duplicate(_ scenario: PlannerScenario) {
        let copy = PlannerScenario(name: scenario.name + " Copy", scenarioType: scenario.scenarioType)
        modelContext.insert(copy)
        scenario.simulatedCourses.forEach {
            modelContext.insert(SimulatedCourse(sourceCourseID: $0.sourceCourseID, courseCode: $0.courseCode,
                                                 units: $0.units, grade: $0.grade,
                                                 isIncludedInGPA: $0.isIncludedInGPA,
                                                 isMajorCourse: $0.isMajorCourse,
                                                 isUpperDivision: $0.isUpperDivision,
                                                 confidence: $0.confidence, notes: $0.notes, scenario: copy))
        }
        try? modelContext.save()
    }
}

struct FutureQuarterPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    let preferences: UserPreferences
    @State private var name = "Future Quarter"
    @State private var code = ""
    @State private var units = "4"
    @State private var grade = CourseGrade.aMinus
    @State private var planned: [CourseCalculationInput] = []
    @State private var message: String?

    private var result: GPAResult { GPAService.cumulative(planned) }

    var body: some View {
        Form {
            Section("Estimated quarter") {
                LabeledContent("Expected GPA", value: DecimalFormatters.string(result.gpa, precision: preferences.decimalPrecision))
                Text("All courses here are Planning Only and never enter official records automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Add planned course") {
                TextField("Course code", text: $code).textInputAutocapitalization(.characters)
                TextField("Expected units", text: $units).keyboardType(.decimalPad)
                Picker("Expected grade", selection: $grade) { ForEach(CourseGrade.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
                Button("Add") { addCourse() }
            }
            Section("Plan") {
                ForEach(planned) { item in
                    HStack { Text(item.courseCode); Spacer(); Text("\(DecimalFormatters.compact(item.units)) · \(item.grade.rawValue)") }
                }.onDelete { planned.remove(atOffsets: $0) }
            }
            Section("Save") {
                TextField("Scenario name", text: $name)
                Button("Save Planning Scenario") { save() }
                if let message { Text(LocalizedStringKey(message)).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Future Quarter")
    }

    private func addCourse() {
        guard let unitValue = DecimalFormatters.decimal(from: units), unitValue > 0,
              !code.trimmingCharacters(in: .whitespaces).isEmpty else { message = "Enter a course code and valid units."; return }
        planned.append(CourseCalculationInput(courseCode: code.uppercased(), units: unitValue, grade: grade))
        code = ""
        message = nil
    }

    private func save() {
        let scenario = PlannerScenario(name: name.isEmpty ? "Future Quarter" : name, scenarioType: .expected)
        modelContext.insert(scenario)
        planned.forEach { modelContext.insert(SimulatedCourse(courseCode: $0.courseCode, units: $0.units,
                                                               grade: $0.grade, scenario: scenario)) }
        try? modelContext.save()
        message = "Planning scenario saved. Official records were not changed."
    }
}
