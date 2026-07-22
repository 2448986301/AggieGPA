import SwiftData
import SwiftUI

private enum CourseDetailSection: String, CaseIterable, Identifiable {
    case gradebook = "Gradebook"
    case breakdown = "Breakdown"
    case forecast = "Forecast"
    var id: String { rawValue }
}

struct CourseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]

    let course: CourseRecord
    let preferences: UserPreferences
    @State private var section = CourseDetailSection.gradebook
    @State private var editingCategory: GradingCategory?
    @State private var editingItem: GradeItem?
    @State private var showCategoryEditor = false
    @State private var showItemEditor = false
    @State private var showPolicyEditor = false
    @State private var showForecastEditor = false
    @State private var showSyllabusImport = false
    @State private var editingForecast: ForecastScenario?
    @State private var deletedItem: DeletedGradeItem?

    private var policy: CourseGradingPolicy? { policies.first { $0.course?.id == course.id } }
    private var courseCategories: [GradingCategory] {
        categories.filter { $0.course?.id == course.id }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
    private var courseItems: [GradeItem] { items.filter { $0.course?.id == course.id } }
    private var scale: GradeScale? { scales.first { $0.course?.id == course.id } }
    private var courseForecasts: [ForecastScenario] {
        forecasts.filter { $0.course?.id == course.id }.sorted { $0.createdAt < $1.createdAt }
    }
    private var forecast: ForecastScenario? {
        courseForecasts.first(where: \.isSelectedForGPAForecast)
            ?? courseForecasts.first { $0.kind == .expected }
            ?? courseForecasts.first
    }
    private var result: CourseGradeCalculationResult {
        CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policy, categories: courseCategories, items: courseItems,
            gradeScale: scale, forecast: forecast
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.medium) {
                gradeHero
                Picker("Course detail", selection: $section) {
                    ForEach(CourseDetailSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("courseDetailSectionPicker")

                switch section {
                case .gradebook: gradebookContent
                case .breakdown: breakdownContent
                case .forecast: forecastContent
                }
                DisclaimerBanner().padding(.top, DesignSystem.Spacing.small)
            }
            .padding()
        }
        .background(CampusBackground())
        .navigationTitle(course.courseCode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Gradebook actions", systemImage: "ellipsis.circle") {
                    Button("Grading Policy", systemImage: "slider.horizontal.3") { showPolicyEditor = true }
                    Button("Add Category", systemImage: "folder.badge.plus") { editingCategory = nil; showCategoryEditor = true }
                    Button("Add Grade Item", systemImage: "plus") { editingItem = nil; showItemEditor = true }
                    Divider()
                    Button("Import Grading Policy", systemImage: "doc.text.magnifyingglass") { showSyllabusImport = true }
                }
            }
        }
        .sheet(isPresented: $showCategoryEditor) {
            CategoryEditorView(course: course, category: editingCategory, nextSortOrder: courseCategories.count)
        }
        .sheet(isPresented: $showItemEditor) {
            GradeItemEditorView(course: course, categories: courseCategories, item: editingItem)
        }
        .sheet(isPresented: $showPolicyEditor) {
            GradingPolicyEditorView(course: course, policy: policy, scale: scale)
        }
        .sheet(isPresented: $showSyllabusImport) {
            SyllabusImportView(course: course)
        }
        .sheet(isPresented: $showForecastEditor) {
            ForecastEditorView(course: course, policy: policy, forecast: editingForecast)
        }
        .safeAreaInset(edge: .bottom) {
            if deletedItem != nil {
                HStack {
                    Text("Grade item deleted")
                    Spacer()
                    Button("Undo") { undoDelete() }.bold()
                }
                .padding()
                .glassEffect(.regular, in: Capsule())
                .padding(.horizontal)
            }
        }
    }

    private var gradeHero: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.courseTitle.isEmpty ? course.courseCode : course.courseTitle)
                        .font(.headline)
                    Text("Calculated current grade")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(percent(result.calculatedCurrentPercentage))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(result.currentLetterGrade?.rawValue ?? "No letter prediction")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.requiresManualReview ? DesignSystem.ColorToken.warning : DesignSystem.ColorToken.gold)
                }
            }
            Divider()
            HStack {
                Label("Official: \(course.grade.rawValue)", systemImage: "checkmark.seal")
                Spacer()
                Label("\(percent(result.gradedWeight)) graded", systemImage: "chart.pie")
            }
            .font(.caption).foregroundStyle(.secondary)
            if result.requiresManualReview {
                Label("Review the grading policy before relying on forecasts.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(DesignSystem.ColorToken.warning)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .glassCard(tint: DesignSystem.ColorToken.navy)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("courseGradeHero")
    }

    @ViewBuilder private var gradebookContent: some View {
        if policy == nil {
            ContentUnavailableView {
                Label("Gradebook not set up", systemImage: "list.clipboard")
            } description: {
                Text("Choose how this course is graded before adding scores.")
            } actions: {
                Button("Set Up Gradebook") { showPolicyEditor = true }.buttonStyle(.borderedProminent)
            }
            .padding(.vertical, DesignSystem.Spacing.xLarge)
        } else {
            HStack {
                Text("Grade Items").font(.title2.bold())
                Spacer()
                Button("Category", systemImage: "folder.badge.plus") { editingCategory = nil; showCategoryEditor = true }
                Button("Item", systemImage: "plus") { editingItem = nil; showItemEditor = true }
                    .buttonStyle(.borderedProminent)
            }
            ForEach(courseCategories) { category in
                categorySection(category)
            }
            if courseCategories.isEmpty && courseItems.isEmpty {
                ContentUnavailableView("No grade items", systemImage: "tray", description: Text("Add a category or your first assignment."))
                    .padding(.vertical, DesignSystem.Spacing.large)
            }
            let unassigned = courseItems.filter { $0.category == nil }
            if !unassigned.isEmpty {
                itemGroup(title: "Unassigned", items: unassigned)
            }
        }
    }

    private func categorySection(_ category: GradingCategory) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).font(.headline)
                    Text("\(percent(category.weight)) weight · \(category.calculationMode.displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit \(category.name)", systemImage: "pencil") {
                    editingCategory = category; showCategoryEditor = true
                }.labelStyle(.iconOnly)
            }
            let categoryItems = courseItems.filter { $0.category?.id == category.id }.sorted(by: itemSort)
            if categoryItems.isEmpty {
                Text("No items in this category").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                ForEach(categoryItems) { itemRow($0) }
            }
        }
        .padding()
        .glassCard()
    }

    private func itemGroup(title: String, items: [GradeItem]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text(title).font(.headline)
            ForEach(items.sorted(by: itemSort)) { itemRow($0) }
        }
        .padding().glassCard()
    }

    private func itemRow(_ item: GradeItem) -> some View {
        Button {
            editingItem = item; showItemEditor = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: item.status.icon).foregroundStyle(item.status.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(item.status.displayName)
                        if let due = item.dueDate { Text(due, style: .date) }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(score(item)).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingItem = item; showItemEditor = true }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
        }
    }

    @ViewBuilder private var breakdownContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Category Breakdown").font(.title2.bold())
            if result.categoryBreakdown.isEmpty {
                ContentUnavailableView("No breakdown yet", systemImage: "chart.bar.xaxis", description: Text("Add grading categories and scores first."))
            }
            ForEach(result.categoryBreakdown, id: \.id) { category in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(category.name).font(.headline)
                        Spacer()
                        Text(percent(category.average)).font(.headline.monospacedDigit())
                    }
                    ProgressView(value: decimalDouble(category.gradedFraction))
                    HStack {
                        Text("\(category.gradedItems) graded · \(category.remainingItems) remaining")
                        Spacer()
                        Text("\(percent(category.contribution)) contribution")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                .padding().glassCard()
            }
            if !result.issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Checks", systemImage: "checklist") .font(.headline)
                    ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                        Text("• \(issue.message)").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding().glassCard(tint: DesignSystem.ColorToken.warning)
            }
        }
    }

    @ViewBuilder private var forecastContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            HStack {
                Text("Forecast").font(.title2.bold())
                Spacer()
                if forecast != nil {
                    Button("Edit", systemImage: "slider.horizontal.3") { editingForecast = forecast; showForecastEditor = true }
                }
                Button("New", systemImage: "plus") { editingForecast = nil; showForecastEditor = true }
                    .buttonStyle(.borderedProminent)
            }
            if courseForecasts.count > 1 {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(courseForecasts) { scenario in
                            Button {
                                select(scenario)
                            } label: {
                                Label(scenario.name, systemImage: scenario.id == forecast?.id ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            if result.requiresManualReview {
                ContentUnavailableView("Forecast unavailable", systemImage: "exclamationmark.triangle", description: Text("Fix the grading-policy checks shown in Breakdown first."))
            } else if forecast == nil {
                ContentUnavailableView("No forecast scenario", systemImage: "chart.line.uptrend.xyaxis", description: Text("Choose an expected average for remaining work."))
            } else {
                forecastMetric("Projected final", value: percent(result.projectedFinalPercentage), detail: result.projectedLetterGrade?.rawValue ?? "No letter prediction")
                HStack(spacing: DesignSystem.Spacing.medium) {
                    forecastMetric("Best possible", value: percent(result.bestPossiblePercentage), detail: "100% remaining")
                    forecastMetric("Floor", value: percent(result.worstPossiblePercentage), detail: "0% remaining")
                }
                if let required = result.requiredRemainingAverage {
                    forecastMetric("Needed on remaining work", value: percent(required), detail: result.targetFeasibility.displayName)
                }
                if let finalNeeded = result.finalExamNeeded {
                    forecastMetric("Final exam needed", value: percent(finalNeeded), detail: "Only when one final remains")
                }
            }
            Text("Forecasts are estimates from the grading policy and scores you entered, not official course grades.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func forecastMetric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding().glassCard()
    }

    private func delete(_ item: GradeItem) {
        deletedItem = DeletedGradeItem(item)
        GradeItemNotificationService.cancel(identifier: item.notificationIdentifier)
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func select(_ scenario: ForecastScenario) {
        for candidate in courseForecasts { candidate.isSelectedForGPAForecast = candidate.id == scenario.id }
        try? modelContext.save()
    }

    private func undoDelete() {
        guard let deletedItem else { return }
        let restored = deletedItem.restore(course: course, categories: courseCategories)
        modelContext.insert(restored)
        try? modelContext.save()
        self.deletedItem = nil
    }

    private func itemSort(_ lhs: GradeItem, _ rhs: GradeItem) -> Bool {
        (lhs.dueDate ?? .distantFuture, lhs.title) < (rhs.dueDate ?? .distantFuture, rhs.title)
    }

    private func score(_ item: GradeItem) -> String {
        if let override = item.percentageOverride { return "\(percent(override)) override" }
        guard let earned = item.earnedPoints else { return "— / \(compact(item.possiblePoints))" }
        return "\(compact(earned)) / \(compact(item.possiblePoints))"
    }
}

private struct DeletedGradeItem {
    let title: String; let categoryID: UUID?; let dueDate: Date?; let earned: Decimal?; let possible: Decimal
    let override: Decimal?; let status: GradeItemStatus; let included: Bool; let extra: Bool; let dropped: Bool
    let excused: Bool; let multiplier: Decimal; let notes: String

    init(_ item: GradeItem) {
        title = item.title; categoryID = item.category?.id; dueDate = item.dueDate; earned = item.earnedPoints
        possible = item.possiblePoints; override = item.percentageOverride; status = item.status; included = item.isIncluded
        extra = item.isExtraCredit; dropped = item.isDropped; excused = item.isExcused; multiplier = item.multiplier; notes = item.notes
    }

    func restore(course: CourseRecord, categories: [GradingCategory]) -> GradeItem {
        GradeItem(course: course, category: categories.first { $0.id == categoryID }, title: title, dueDate: dueDate,
                  earnedPoints: earned, possiblePoints: possible, percentageOverride: override, status: status,
                  isIncluded: included, isExtraCredit: extra, isDropped: dropped, isExcused: excused,
                  multiplier: multiplier, notes: notes)
    }
}

func compact(_ value: Decimal) -> String { DecimalFormatters.compact(value) }
private func percent(_ value: Decimal?) -> String { value.map { "\(compact($0))%" } ?? "—" }
func decimalDouble(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }

private extension CategoryCalculationMode {
    var displayName: String {
        switch self { case .weightedCategory: "Weighted"; case .totalPoints: "Total points"; case .equalItems: "Equal items"; case .custom: "Custom" }
    }
}

private extension GradeItemStatus {
    var displayName: String { rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }
    var icon: String {
        switch self { case .graded: "checkmark.circle.fill"; case .missing: "exclamationmark.circle.fill"; case .excused: "minus.circle"; case .dropped: "arrow.down.circle"; case .submitted: "paperplane.fill"; case .notCounted: "nosign"; case .upcoming: "clock" }
    }
    var tint: Color { self == .missing ? DesignSystem.ColorToken.warning : (self == .graded ? DesignSystem.ColorToken.success : .secondary) }
}

private extension TargetFeasibility {
    var displayName: String {
        switch self { case .noTarget: "No target"; case .alreadyReached: "Target already reached"; case .achievable: "Target is achievable"; case .impossible: "Target is not mathematically reachable"; case .manualReviewRequired: "Policy review required" }
    }
}

private extension GradeCalculationIssue {
    var message: String {
        switch self {
        case .emptyGradebook: "No counted grade items yet."
        case .noGradeScale: "No confirmed course grade scale; letter prediction is hidden."
        case .missingPolicyNeedsConfirmation: "Confirm before missing items count as zero."
        case .weightTotalBelow100(let value): "Category weights total \(percent(value)), below 100%."
        case .weightTotalAbove100(let value): "Category weights total \(percent(value)), above 100%."
        case .invalidCategoryWeight(let name): "\(name) has an invalid weight."
        case .unsupportedCustomCategory(let name): "\(name) uses a custom rule requiring manual review."
        case .invalidPossiblePoints(let title): "\(title) needs possible points greater than zero."
        case .invalidMultiplier(let title): "\(title) has an invalid multiplier."
        case .gradedItemMissingScore(let title): "\(title) is graded but has no score."
        case .dropCountRemovesAll(let name): "The drop rule removes every item in \(name)."
        case .unassignedItems: "Assign all items to a weighted category."
        case .hybridNeedsDirectItems: "The hybrid policy needs direct-point items."
        }
    }
}
