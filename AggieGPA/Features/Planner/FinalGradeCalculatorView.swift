import SwiftUI

private struct EditableCategory: Identifiable {
    let id = UUID()
    var name: String
    var weight: String
    var earned: String
    var possible: String
    var missing = false
    var extraCredit = false
}

struct FinalGradeCalculatorView: View {
    @State private var courseName = ""
    @State private var target = "90"
    @State private var finalWeight = "25"
    @State private var categories = [
        EditableCategory(name: "Homework", weight: "20", earned: "180", possible: "200"),
        EditableCategory(name: "Midterms", weight: "55", earned: "150", possible: "180")
    ]

    private var result: FinalGradeResult? {
        guard let targetValue = DecimalFormatters.decimal(from: target),
              let finalValue = DecimalFormatters.decimal(from: finalWeight) else { return nil }
        let inputs = categories.compactMap { category -> GradeCategoryInput? in
            guard let weight = DecimalFormatters.decimal(from: category.weight),
                  let earned = DecimalFormatters.decimal(from: category.earned),
                  let possible = DecimalFormatters.decimal(from: category.possible) else { return nil }
            return GradeCategoryInput(name: category.name, weight: weight, earnedPoints: earned,
                                      possiblePoints: possible, isExtraCredit: category.extraCredit,
                                      isMissing: category.missing)
        }
        guard inputs.count == categories.count else { return nil }
        return FinalGradeService.calculate(categories: inputs, targetPercentage: targetValue, finalExamWeight: finalValue)
    }

    var body: some View {
        Form {
            Section("Course") {
                TextField("Course name", text: $courseName)
                TextField("Target overall percentage", text: $target).keyboardType(.decimalPad)
                TextField("Final exam weight", text: $finalWeight).keyboardType(.decimalPad)
            }
            Section("Categories") {
                ForEach($categories) { $category in
                    DisclosureGroup(category.name.isEmpty ? "Category" : category.name) {
                        TextField("Name", text: $category.name)
                        TextField("Weight %", text: $category.weight).keyboardType(.decimalPad)
                        TextField("Earned points", text: $category.earned).keyboardType(.decimalPad)
                        TextField("Possible points", text: $category.possible).keyboardType(.decimalPad)
                        Toggle("Missing score", isOn: $category.missing)
                        Toggle("Extra credit", isOn: $category.extraCredit)
                    }
                }.onDelete { categories.remove(atOffsets: $0) }
                Button("Add Category", systemImage: "plus") {
                    categories.append(EditableCategory(name: "Custom", weight: "0", earned: "0", possible: "0"))
                }
            }
            Section("Estimate") {
                if let result {
                    LabeledContent("Current percentage", value: DecimalFormatters.string(result.currentPercentage, precision: 2) + "%")
                    LabeledContent("Completed weight", value: DecimalFormatters.string(result.completedWeight, precision: 1) + "%")
                    LabeledContent("Remaining weight", value: DecimalFormatters.string(result.remainingWeight, precision: 1) + "%")
                    LabeledContent("Final score needed", value: DecimalFormatters.string(result.finalExamNeeded, precision: 2) + "%")
                    LabeledContent("Best possible", value: DecimalFormatters.string(result.bestPossible, precision: 2) + "%")
                    LabeledContent("Worst possible", value: DecimalFormatters.string(result.worstPossible, precision: 2) + "%")
                    if !result.weightsAreComplete {
                        Label("Weights do not total 100%. This is a partial setup, so final results may be misleading.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if !result.targetIsReachable {
                        Label("The selected target is not reachable under these assumptions.", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Enter non-negative points and weights from 0 to 100.").foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Aggie GPA does not assume an official grading scale. Check your syllabus and enter your professor's category weights and letter-grade boundaries.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Final Grade")
    }
}

