import SwiftData
import SwiftUI

struct TargetGPAView: View {
    @Query private var courses: [CourseRecord]
    let preferences: UserPreferences
    @State private var currentGPA = ""
    @State private var currentUnits = ""
    @State private var targetGPA = ""
    @State private var futureUnits = "32"

    private var result: TargetGPAResult? {
        guard let gpa = DecimalFormatters.decimal(from: currentGPA),
              let units = DecimalFormatters.decimal(from: currentUnits),
              let target = DecimalFormatters.decimal(from: targetGPA),
              let future = DecimalFormatters.decimal(from: futureUnits) else { return nil }
        return TargetGPAService.calculate(currentGPA: gpa, currentUnits: units,
                                          targetGPA: target, futureUnits: future)
    }

    var body: some View {
        Form {
            Section("Inputs") {
                decimalField("Current GPA", text: $currentGPA)
                decimalField("Current GPA units", text: $currentUnits)
                decimalField("Target GPA", text: $targetGPA)
                decimalField("Future units", text: $futureUnits)
                Button("Use my records") { useRecords() }
            }
            Section("Result") {
                if let result {
                    if result.isReachable, let required = result.requiredFutureGPA {
                        Text("Across \(futureUnits) future units, you would need an average GPA of \(DecimalFormatters.string(required, precision: 3)).")
                            .font(.headline)
                    } else {
                        Label("This target is not mathematically reachable within the selected number of future units if the maximum future GPA is 4.0.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    LabeledContent("Highest possible final GPA", value: DecimalFormatters.string(result.maximumFinalGPA, precision: 3))
                    if let extra = result.additionalUnitsNeeded, extra > 0 {
                        LabeledContent("Additional units at 4.0 needed", value: DecimalFormatters.string(extra, precision: 2))
                    }
                } else {
                    Text("Enter valid GPA values from 0 to 4 and future units greater than 0.").foregroundStyle(.secondary)
                }
            }
            Section("Formula and assumptions") {
                Text("Required future GPA = (target × (current units + future units) − current GPA × current units) ÷ future units.")
                Text("Maximum future GPA is assumed to be 4.0. No intermediate value is rounded. Grade combinations are examples, not unique answers.")
            }.font(.footnote)
        }
        .navigationTitle("Target GPA")
        .onAppear { if targetGPA.isEmpty { targetGPA = DecimalFormatters.compact(preferences.targetGPA); useRecords() } }
    }

    private func decimalField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).keyboardType(.decimalPad)
    }

    private func useRecords() {
        let official = GPAService.cumulative(courses.map(CourseCalculationInput.init))
        currentGPA = DecimalFormatters.compact(official.gpa ?? 0)
        currentUnits = DecimalFormatters.compact(official.attemptedUnits)
        if targetGPA.isEmpty { targetGPA = DecimalFormatters.compact(preferences.targetGPA) }
    }
}

