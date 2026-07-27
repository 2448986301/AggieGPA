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
            Section {
                targetSummary
                    .listRowInsets(EdgeInsets(top: DesignSystem.Spacing.small, leading: 0, bottom: DesignSystem.Spacing.small, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            Section("Inputs") {
                decimalField("Current GPA", text: $currentGPA)
                decimalField("Current GPA units", text: $currentUnits)
                decimalField("Target GPA", text: $targetGPA)
                decimalField("Future units", text: $futureUnits)
                Button("Use my records") { useRecords() }
            }
            Section("Calculation details") {
                DisclosureGroup("Formula and assumptions") {
                    Text("Required future GPA = (target × (current units + future units) − current GPA × current units) ÷ future units.")
                    Text("Maximum future GPA is assumed to be 4.0. No intermediate value is rounded. Grade combinations are examples, not unique answers.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Target GPA")
        .onAppear { if targetGPA.isEmpty { targetGPA = DecimalFormatters.compact(preferences.targetGPA); useRecords() } }
    }

    private func decimalField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).keyboardType(.decimalPad)
    }

    @ViewBuilder private var targetSummary: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Label("Your target", systemImage: "target")
                .font(.headline)
            if let result {
                if result.isReachable, let required = result.requiredFutureGPA {
                    Text(DecimalFormatters.string(required, precision: 3))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("Average GPA needed across your remaining future units")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label("This target is not reachable with the selected future units.", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(DesignSystem.ColorToken.warning)
                    Text("At a 4.0 future GPA, your highest possible final GPA is \(DecimalFormatters.string(result.maximumFinalGPA, precision: 3)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let extra = result.additionalUnitsNeeded, extra > 0 {
                    LabeledContent("Additional units at 4.0 needed", value: DecimalFormatters.string(extra, precision: 2))
                        .font(.footnote)
                }
            } else {
                Text("Enter GPA values from 0 to 4 and future units greater than 0 to see your target.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .contentSurface(radius: DesignSystem.Radius.card)
        .accessibilityElement(children: .combine)
    }

    private func useRecords() {
        let official = GPAService.cumulative(courses.map(CourseCalculationInput.init))
        currentGPA = DecimalFormatters.compact(official.gpa ?? 0)
        currentUnits = DecimalFormatters.compact(official.attemptedUnits)
        if targetGPA.isEmpty { targetGPA = DecimalFormatters.compact(preferences.targetGPA) }
    }
}
