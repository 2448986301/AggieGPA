import SwiftData
import SwiftUI

private enum CourseDetailSection: String, CaseIterable, Identifiable {
    case gradebook = "Assignments & Exams"
    case breakdown = "Grade Breakdown"
    case forecast = "What Do I Need?"
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
    @State private var showSetup = false
    @State private var showQuickAssignment = false
    @State private var showQuickExam = false
    @State private var scoringItem: GradeItem?
    @State private var showTargetPicker = false
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
    private var nextItem: GradeItem? {
        courseItems.filter { $0.earnedPoints == nil && !$0.isExcused && !$0.isDropped }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.medium) {
                gradeHero
                Picker("Course detail", selection: $section) {
                    ForEach(CourseDetailSection.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
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
                Menu("Course Settings", systemImage: "ellipsis.circle") {
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
        .sheet(isPresented: $showSetup) { GradeBreakdownSetupView(course: course) }
        .sheet(isPresented: $showQuickAssignment) { QuickGradeItemView(course: course, categories: courseCategories, isExam: false) }
        .sheet(isPresented: $showQuickExam) { QuickGradeItemView(course: course, categories: courseCategories, isExam: true) }
        .sheet(item: $scoringItem) { item in RecordScoreView(item: item) }
        .sheet(isPresented: $showTargetPicker) { SimpleTargetPickerView(course: course, policy: policy) }
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
                    Text(course.courseCode).font(.title3.bold())
                    Text(course.courseTitle.isEmpty ? "Course" : course.courseTitle)
                        .font(.headline)
                    Text("Current Course Grade")
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
            Text("Based on graded work")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack(spacing: DesignSystem.Spacing.large) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Graded so far").font(.caption).foregroundStyle(.secondary)
                    Text("\(percent(result.gradedWeight))").font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next up").font(.caption).foregroundStyle(.secondary)
                    Text(nextItem?.title ?? "Nothing due").font(.headline).lineLimit(1)
                }
            }
            Label("Final recorded grade: \(course.grade.rawValue)", systemImage: "checkmark.seal")
                .font(.caption).foregroundStyle(.secondary)
            if result.requiresManualReview {
                Label("Check Course Settings before relying on predictions.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(DesignSystem.ColorToken.warning)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .glassCard(tint: DesignSystem.ColorToken.navy)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course.courseCode), calculated current grade \(percent(result.calculatedCurrentPercentage)), official grade \(course.grade.rawValue)")
        .accessibilityValue(result.requiresManualReview ? "Manual review required" : "Grading policy checked")
        .accessibilityIdentifier("courseGradeHero")
    }

    @ViewBuilder private var gradebookContent: some View {
        if policy == nil {
            ContentUnavailableView {
                Label("How is this course graded?", systemImage: "list.clipboard")
            } description: {
                Text("Import a syllabus, choose a template, or set it up manually.")
            } actions: {
                Button("Use a Template") { showSetup = true }.buttonStyle(.borderedProminent)
                Button("Import Syllabus") { showSyllabusImport = true }
                Button("Set It Up Manually") { showPolicyEditor = true }
            }
            .padding(.vertical, DesignSystem.Spacing.xLarge)
        } else {
            HStack {
                Text("Assignments & Exams").font(.title2.bold())
                Spacer()
                Button("Add", systemImage: "plus") { showQuickAssignment = true }
                    .buttonStyle(.borderedProminent)
            }
            HStack(spacing: DesignSystem.Spacing.small) {
                Button("+ Add Assignment") { showQuickAssignment = true }
                Button("+ Add Exam") { showQuickExam = true }
            }
            .buttonStyle(.glass)
            ForEach(courseCategories) { category in
                categorySection(category)
            }
            if courseCategories.isEmpty && courseItems.isEmpty {
                ContentUnavailableView("No assignments or exams", systemImage: "tray", description: Text("Add your first item to start tracking scores."))
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
                    Text("Worth \(percent(category.weight)) of course")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            let categoryItems = courseItems.filter { $0.category?.id == category.id }.sorted(by: itemSort)
            if categoryItems.isEmpty {
                Text("No assignments or exams yet").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
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
            scoringItem = item
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(itemAccessibilityLabel(item))
        .accessibilityHint("Records or updates this score")
        .contextMenu {
            Button("Record Score", systemImage: "pencil") { scoringItem = item }
            if item.status != .submitted {
                Button("Mark Submitted", systemImage: "paperplane") { updateStatus(item, to: .submitted) }
            }
            if item.status != .missing {
                Button("Mark Missing", systemImage: "exclamationmark.circle") { updateStatus(item, to: .missing) }
            }
            if item.status != .excused {
                Button("Mark Excused", systemImage: "minus.circle") { updateStatus(item, to: .excused) }
            }
            Button("Edit", systemImage: "slider.horizontal.3") { editingItem = item; showItemEditor = true }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
        }
    }

    @ViewBuilder private var breakdownContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Grade Breakdown").font(.title2.bold())
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
                        .accessibilityLabel("\(category.name) graded progress")
                        .accessibilityValue(percent(category.gradedFraction * 100))
                    HStack {
                        Text("\(category.gradedItems) graded · \(category.remainingItems) ungraded")
                        Spacer()
                        Text("Worth \(percent(category.weight)) of course")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                .padding().glassCard()
            }
            if !result.issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Calculation Details", systemImage: "checklist") .font(.headline)
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
                Text("I want to finish with").font(.title2.bold())
                Spacer()
                Button(policy?.targetPercentage.map { "\(compact($0))%" } ?? "Set target") { showTargetPicker = true }
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
                ContentUnavailableView("Goal estimate unavailable", systemImage: "exclamationmark.triangle", description: Text("Check the course setup first."))
            } else if policy?.targetPercentage == nil {
                ContentUnavailableView("Set a target", systemImage: "chart.line.uptrend.xyaxis", description: Text("Choose the course percentage you want, and we’ll show what you need on remaining work."))
            } else {
                if let required = result.requiredRemainingAverage {
                    forecastMetric("You need on remaining work", value: percent(required), detail: result.targetFeasibility.displayName)
                }
                if let finalNeeded = result.finalExamNeeded {
                    forecastMetric("You need on the final", value: percent(finalNeeded), detail: "Only when one final remains")
                }
            }
            Text("This is an estimate based on your setup and recorded scores. It is not an official final grade.")
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

    private func updateStatus(_ item: GradeItem, to status: GradeItemStatus) {
        item.status = status
        item.updatedAt = .now
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

    private func itemAccessibilityLabel(_ item: GradeItem) -> String {
        var parts = [item.title, item.status.displayName, score(item)]
        if let dueDate = item.dueDate {
            parts.append("due \(dueDate.formatted(date: .long, time: .shortened))")
        }
        if item.isDropped { parts.append("dropped") }
        if item.isExcused { parts.append("excused") }
        return parts.joined(separator: ", ")
    }
}

private struct SimpleTargetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let course: CourseRecord
    let policy: CourseGradingPolicy?
    @State private var target: Double

    init(course: CourseRecord, policy: CourseGradingPolicy?) {
        self.course = course; self.policy = policy
        _target = State(initialValue: policy.map { decimalDouble($0.targetPercentage ?? 90) } ?? 90)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("I want to finish with") {
                    Text("\(Int(target.rounded()))%").font(.largeTitle.bold())
                    Slider(value: $target, in: 50...100, step: 1)
                    HStack { Button("A- 90%") { target = 90 }; Button("B+ 87%") { target = 87 }; Button("A 93%") { target = 93 } }
                }
            }
            .navigationTitle("Target Grade")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
        }
    }

    private func save() {
        let saved = policy ?? CourseGradingPolicy(course: course)
        if policy == nil { modelContext.insert(saved) }
        saved.targetPercentage = Decimal(target); saved.updatedAt = .now
        try? modelContext.save(); dismiss()
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
