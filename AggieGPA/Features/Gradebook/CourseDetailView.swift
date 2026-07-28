import AppIntents
import SwiftData
import SwiftUI

private enum CourseDetailSection: String, CaseIterable, Identifiable {
    case gradebook = "Assignments & Exams"
    case breakdown = "Grade Breakdown"
    case forecast = "What Do I Need?"
    var id: String { rawValue }

    var compactTitle: LocalizedStringKey {
        switch self {
        case .gradebook: "Items"
        case .breakdown: "Breakdown"
        case .forecast: "Goal"
        }
    }

    var symbol: String {
        switch self {
        case .gradebook: "checklist"
        case .breakdown: "chart.bar"
        case .forecast: "target"
        }
    }
}

private struct ScoreImpactBaseline {
    let itemID: UUID
    let currentGrade: Decimal?
    let projectedFinal: Decimal?
    let projectedLetter: GradeLetter?
    let termGPA: Decimal?
}

struct CourseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    @Query private var allCourses: [CourseRecord]

    let course: CourseRecord
    let preferences: UserPreferences
    let initialItemID: UUID?
    @State private var section = CourseDetailSection.gradebook
    @State private var editingCategory: GradingCategory?
    @State private var editingItem: GradeItem?
    @State private var showCategoryEditor = false
    @State private var categoryPendingDeletion: GradingCategory?
    @State private var showItemEditor = false
    @State private var showPolicyEditor = false
    @State private var showForecastEditor = false
    @State private var showSyllabusImport = false
    @State private var showSetup = false
    @State private var quickCategory: GradingCategory?
    @State private var scoringItem: GradeItem?
    @State private var showTargetPicker = false
    @State private var editingForecast: ForecastScenario?
    @State private var deletedItem: DeletedGradeItem?
    @State private var itemPendingDeletion: GradeItem?
    @State private var scoreBaseline: ScoreImpactBaseline?
    @State private var scoreImpact: ScoreImpactPresentation?

    init(course: CourseRecord, preferences: UserPreferences, initialItemID: UUID? = nil) {
        self.course = course
        self.preferences = preferences
        self.initialItemID = initialItemID
    }

    private func belongsToCourse(_ relatedCourse: CourseRecord?) -> Bool {
        relatedCourse?.persistentModelID == course.persistentModelID
    }
    private var policy: CourseGradingPolicy? { policies.first { belongsToCourse($0.course) } }
    private var courseCategories: [GradingCategory] {
        categories.filter { belongsToCourse($0.course) }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
    private var courseItems: [GradeItem] { items.filter { belongsToCourse($0.course) } }
    private var scale: GradeScale? { scales.first { belongsToCourse($0.course) } }
    private var courseForecasts: [ForecastScenario] {
        forecasts.filter { belongsToCourse($0.course) }.sorted { $0.createdAt < $1.createdAt }
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
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            secondaryDetailContent
        }
        .overlay(alignment: .bottom) { feedbackBanner }
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
        .alert("Delete this category?", isPresented: isShowingCategoryDeletionAlert) {
            Button("Delete Category", role: .destructive) {
                if let categoryPendingDeletion { deleteCategory(categoryPendingDeletion) }
                categoryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { categoryPendingDeletion = nil }
        } message: {
            Text("Assignments and scores in this category will be kept as unassigned work.")
        }
        .alert(itemDeletionTitle, isPresented: isShowingItemDeletionAlert) {
            Button("Delete Assignment", role: .destructive) {
                if let itemPendingDeletion { delete(itemPendingDeletion) }
                itemPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { itemPendingDeletion = nil }
        } message: {
            Text(itemDeletionMessage)
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
        .sheet(item: $quickCategory) { category in
            QuickGradeItemView(course: course, categories: courseCategories, category: category)
        }
        .sheet(item: $scoringItem) { item in
            RecordScoreView(item: item) { change in
                completeScoreUpdate(item, change: change)
            }
        }
        .sheet(isPresented: $showTargetPicker) { SimpleTargetPickerView(course: course, policy: policy) }
        .sheet(isPresented: $showForecastEditor) {
            ForecastEditorView(course: course, policy: policy, forecast: editingForecast)
        }
        .task { openInitialItemIfNeeded() }
        .task(id: scoreImpact?.id) { await autoDismissScoreImpact() }
        .sensoryFeedback(.success, trigger: scoreImpact?.id)
        .sensoryFeedback(.warning, trigger: deletedItem?.id)
        .appEntityIdentifier(EntityIdentifier(for: CourseEntity.self, identifier: course.id.uuidString))
    }

    @ViewBuilder private var feedbackBanner: some View {
        if deletedItem != nil {
            AggieFeedbackBanner(
                "Assignment deleted",
                message: "Undo restores the assignment and its recorded score.",
                systemImage: "trash"
            ) {
                undoButton
            }
            .padding(.vertical, DesignSystem.Spacing.small)
            .transition(DesignSystem.Motion.feedbackTransition(reduceMotion: reduceMotion))
            .accessibilityIdentifier("gradeItemUndoBanner")
        } else if let scoreImpact {
            ScoreImpactBanner(
                impact: scoreImpact,
                undo: undoScoreUpdate,
                dismiss: dismissScoreImpact
            )
            .padding(.vertical, DesignSystem.Spacing.small)
            .transition(DesignSystem.Motion.feedbackTransition(reduceMotion: reduceMotion))
        }
    }

    private func openInitialItemIfNeeded() {
        guard let initialItemID else { return }
        guard let item = courseItems.first(where: { $0.id == initialItemID }) else { return }
        section = .gradebook
        editingItem = item
        showItemEditor = true
    }

    private var isShowingCategoryDeletionAlert: Binding<Bool> {
        Binding(
            get: { categoryPendingDeletion != nil },
            set: { if !$0 { categoryPendingDeletion = nil } }
        )
    }

    private var isShowingItemDeletionAlert: Binding<Bool> {
        Binding(
            get: { itemPendingDeletion != nil },
            set: { if !$0 { itemPendingDeletion = nil } }
        )
    }

    private var secondaryDetailContent: some View {
        List {
            Section {
                gradeHero
                    .listRowInsets(EdgeInsets(top: DesignSystem.Spacing.small, leading: 0, bottom: DesignSystem.Spacing.small, trailing: 0))
                    .listRowBackground(Color.clear)

                Picker("Course detail", selection: sectionBinding) {
                    ForEach(CourseDetailSection.allCases) { section in
                        Label(section.compactTitle, systemImage: section.symbol).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("courseDetailSectionPicker")
                .accessibilityHint("Switches between assignments, grade breakdown, and goal estimate")
                .listRowBackground(Color.clear)
            }

            activeSectionContent

            Section {
                DisclaimerBanner()
                    .padding(.bottom, feedbackIsVisible ? 76 : 0)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder private var activeSectionContent: some View {
        switch section {
        case .gradebook:
            if policy == nil {
                Section {
                    ContentUnavailableView {
                        Label("How is this course graded?", systemImage: "list.clipboard")
                    } description: {
                        Text("Import a syllabus, choose a template, or set it up manually.")
                    } actions: {
                        Button("Use a Template") { showSetup = true }.buttonStyle(.glass)
                        Button("Import Syllabus") { showSyllabusImport = true }
                        Button("Set It Up Manually") { showPolicyEditor = true }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xLarge)
                    .listRowBackground(Color.clear)
                }
            } else {
                gradebookSections
            }
        case .breakdown:
            breakdownContent
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        case .forecast:
            forecastContent
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private var gradebookSections: some View {
        Section {
            HStack {
                Text("Assignments & Exams").font(.title2.bold())
                Spacer()
                addGradeItemMenu
            }
            .listRowBackground(Color.clear)
        }

        ForEach(courseCategories) { category in
            Section {
                let categoryItems = courseItems.filter { $0.category?.id == category.id }.sorted(by: itemSort)
                if categoryItems.isEmpty {
                    Text("No assignments or exams yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categoryItems) { itemRow($0) }
                }
            } header: {
                categoryListHeader(category)
            }
        }

        if courseCategories.isEmpty && courseItems.isEmpty {
            Section {
                ContentUnavailableView(
                    "No assignments or exams",
                    systemImage: "tray",
                    description: Text("Add your first item to start tracking scores.")
                )
                .padding(.vertical, DesignSystem.Spacing.large)
            }
        }

        let unassigned = courseItems.filter { $0.category == nil }
        if !unassigned.isEmpty {
            Section("Unassigned") {
                ForEach(unassigned.sorted(by: itemSort)) { itemRow($0) }
            }
        }
    }

    private var gradeHero: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            ViewThatFits(in: .horizontal) {
                courseIdentityAndGrade(horizontal: true)
                courseIdentityAndGrade(horizontal: false)
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
        .contentSurface()
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
                Menu("Add", systemImage: "plus") {
                    if courseCategories.isEmpty {
                        Button("Add Grade Item", systemImage: "plus") { editingItem = nil; showItemEditor = true }
                    } else {
                        ForEach(courseCategories) { category in
                            Button(category.name, systemImage: category.addSymbol) { quickCategory = category }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add assignment or exam")
            }
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
                Button("Edit") {
                    editingCategory = category
                    showCategoryEditor = true
                }
                .buttonStyle(.bordered)
                Menu {
                    Button("Edit Category", systemImage: "pencil") {
                        editingCategory = category
                        showCategoryEditor = true
                    }
                    Button("Delete Category", systemImage: "trash", role: .destructive) {
                        categoryPendingDeletion = category
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Options for \(category.name)")
            }
            let categoryItems = courseItems.filter { $0.category?.id == category.id }.sorted(by: itemSort)
            if categoryItems.isEmpty {
                Text("No assignments or exams yet").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                ForEach(categoryItems) { itemRow($0) }
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
    }

    private func itemGroup(title: String, items: [GradeItem]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text(title).font(.headline)
            ForEach(items.sorted(by: itemSort)) { itemRow($0) }
        }
        .padding(DesignSystem.Spacing.medium).contentSurface()
    }

    private func itemRow(_ item: GradeItem) -> some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: item.status.icon).foregroundStyle(item.status.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(item.status.localizedLabelKey))
                    if let due = item.dueDate { Text(due, style: .date) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(score(item)).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(DesignSystem.Motion.emphasized(reduceMotion: reduceMotion), value: score(item))
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button("Record Score") { beginScoring(item) }
                .tint(DesignSystem.ColorToken.navyRaised)
            Button("Edit") {
                editingItem = item
                showItemEditor = true
            }
            .tint(DesignSystem.ColorToken.gold)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete") { requestDelete(item) }
                .tint(.red)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous))
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .move(edge: .trailing))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("gradeItemRow-\(item.title)")
        .accessibilityLabel(itemAccessibilityLabel(item))
        .accessibilityHint("Swipe left for score, editing, and deletion actions.")
    }

    private var addGradeItemMenu: some View {
        Menu {
            if courseCategories.isEmpty {
                Button("Add Grade Item", systemImage: "plus") {
                    editingItem = nil
                    showItemEditor = true
                }
            } else {
                ForEach(courseCategories) { category in
                    Button(category.name, systemImage: category.addSymbol) { quickCategory = category }
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
                .font(.body.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.glass(.regular.tint(DesignSystem.ColorToken.gold.opacity(0.32)).interactive()))
        .buttonBorderShape(.capsule)
        .foregroundStyle(.primary)
        .accessibilityLabel("Add assignment or exam")
    }

    private func categoryListHeader(_ category: GradingCategory) -> some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(.headline)
                Text("Worth \(percent(category.weight)) of course")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Edit Category", systemImage: "pencil") {
                    editingCategory = category
                    showCategoryEditor = true
                }
                Button("Delete Category", systemImage: "trash", role: .destructive) {
                    categoryPendingDeletion = category
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Options for \(category.name)")
        }
        .textCase(nil)
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
                .padding(DesignSystem.Spacing.medium).contentSurface()
            }
            if !result.issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Calculation Details", systemImage: "checklist") .font(.headline)
                    ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                        Text("• \(issue.message)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .contentSurface()
            }
        }
    }

    @ViewBuilder private var forecastContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignSystem.Spacing.medium) {
                    forecastGoalTitle
                    Spacer(minLength: DesignSystem.Spacing.small)
                    forecastTargetButton
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    forecastGoalTitle
                    forecastTargetButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if result.requiresManualReview {
                ContentUnavailableView("Goal estimate unavailable", systemImage: "exclamationmark.triangle", description: Text("Check the course setup first."))
            } else {
                WhatIfPlaygroundView(
                    course: course,
                    policy: policy,
                    categories: courseCategories,
                    items: courseItems,
                    gradeScale: scale,
                    scenarios: courseForecasts,
                    allCourses: allCourses,
                    selectedScenario: forecast
                )
            }
            Text("This is an estimate based on your setup and recorded scores. It is not an official final grade.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var forecastGoalTitle: some View {
        Text("I want to finish with")
            .font(.title2.bold())
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    private var forecastTargetButton: some View {
        Button(policy?.targetPercentage.map { "\(compact($0))%" } ?? "Set target") {
            showTargetPicker = true
        }
        .frame(minWidth: 72)
        .fixedSize()
        .buttonStyle(.glass(.regular.tint(DesignSystem.ColorToken.gold.opacity(0.32)).interactive()))
        .buttonBorderShape(.capsule)
        .foregroundStyle(.primary)
    }

    @ViewBuilder private func courseIdentityAndGrade(horizontal: Bool) -> some View {
        if horizontal {
            HStack(alignment: .top) {
                courseIdentity
                Spacer(minLength: DesignSystem.Spacing.medium)
                courseGradeValue
            }
        } else {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                courseIdentity
                courseGradeValue.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var courseIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.courseCode).font(.title3.bold())
            Text(course.courseTitle.isEmpty ? "Course" : course.courseTitle)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Current Course Grade")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var courseGradeValue: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(percent(result.calculatedCurrentPercentage))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(
                    DesignSystem.Motion.emphasized(reduceMotion: reduceMotion),
                    value: result.calculatedCurrentPercentage
                )
            Text(result.currentLetterGrade?.rawValue ?? "No letter prediction")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(result.requiresManualReview ? DesignSystem.ColorToken.warning : DesignSystem.ColorToken.gold)
        }
    }

    private func requestDelete(_ item: GradeItem) {
        itemPendingDeletion = item
    }

    private func delete(_ item: GradeItem) {
        let snapshot = DeletedGradeItem(item)
        withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
            modelContext.delete(item)
            do {
                try modelContext.save()
                GradeItemNotificationService.cancel(identifier: snapshot.notificationIdentifier)
                deletedItem = snapshot
                scoreImpact = nil
            } catch {
                modelContext.rollback()
            }
        }
    }

    private func deleteCategory(_ category: GradingCategory) {
        // Preserve every assignment and recorded score: only remove the grouping.
        for item in courseItems where item.category?.id == category.id {
            item.category = nil
            item.updatedAt = .now
        }
        modelContext.delete(category)
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
        do {
            try modelContext.save()
            let reminder = GradeItemReminderSnapshot(restored)
            Task { try? await GradeItemNotificationService.sync(reminder) }
            withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
                self.deletedItem = nil
            }
        } catch {
            modelContext.rollback()
        }
    }

    private func beginScoring(_ item: GradeItem) {
        scoreBaseline = ScoreImpactBaseline(
            itemID: item.id,
            currentGrade: result.calculatedCurrentPercentage,
            projectedFinal: result.projectedFinalPercentage,
            projectedLetter: result.projectedLetterGrade,
            termGPA: projectedTermGPA(for: result.projectedLetterGrade)
        )
        scoringItem = item
    }

    private func completeScoreUpdate(_ item: GradeItem, change: RecordedScoreChange) {
        guard let baseline = scoreBaseline, baseline.itemID == item.id else { return }
        let updated = result
        let impact = ScoreImpactPresentation(
            itemID: item.id,
            itemTitle: item.title,
            change: change,
            currentGradeBefore: baseline.currentGrade,
            currentGradeAfter: updated.calculatedCurrentPercentage,
            projectedFinalBefore: baseline.projectedFinal,
            projectedFinalAfter: updated.projectedFinalPercentage,
            projectedLetterBefore: baseline.projectedLetter,
            projectedLetterAfter: updated.projectedLetterGrade,
            termGPABefore: baseline.termGPA,
            termGPAAfter: projectedTermGPA(for: updated.projectedLetterGrade)
        )
        scoreBaseline = nil
        withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
            scoreImpact = impact
        }
    }

    private func projectedTermGPA(for letter: GradeLetter?) -> Decimal? {
        guard let projectedGrade = ProjectedGPAService.courseGrade(from: letter) else { return nil }
        return ProjectedGPAService.calculate(
            allCourses.filter { !$0.isDeleted }.map(CourseCalculationInput.init),
            projectedGrades: [course.id: projectedGrade],
            termID: course.term?.id
        ).projected.gpa
    }

    private func undoScoreUpdate() {
        guard let impact = scoreImpact,
              let item = courseItems.first(where: { $0.id == impact.itemID }) else { return }
        item.earnedPoints = impact.change.previousEarnedPoints
        item.possiblePoints = impact.change.previousPossiblePoints
        item.status = impact.change.previousStatus
        item.updatedAt = impact.change.previousUpdatedAt
        do {
            try modelContext.save()
            dismissScoreImpact()
        } catch {
            modelContext.rollback()
        }
    }

    private func dismissScoreImpact() {
        withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
            scoreImpact = nil
        }
    }

    private func autoDismissScoreImpact() async {
        guard let id = scoreImpact?.id else { return }
        try? await Task.sleep(for: .seconds(8))
        guard !Task.isCancelled, scoreImpact?.id == id else { return }
        dismissScoreImpact()
    }

    private var feedbackIsVisible: Bool {
        deletedItem != nil || scoreImpact != nil
    }

    private var sectionBinding: Binding<CourseDetailSection> {
        Binding(
            get: { section },
            set: { section = $0 }
        )
    }

    private var undoButton: some View {
        Button("Undo") { undoDelete() }
            .fontWeight(.semibold)
            .accessibilityIdentifier("undoGradeItemDeleteButton")
    }

    private var itemDeletionTitle: LocalizedStringKey {
        itemPendingDeletion.map(hasRecordedScore) == true ? "Delete this graded assignment?" : "Delete this assignment?"
    }

    private var itemDeletionMessage: LocalizedStringKey {
        itemPendingDeletion.map(hasRecordedScore) == true ? "This assignment already has a recorded score. Delete it?" : "This assignment will be deleted."
    }

    private func hasRecordedScore(_ item: GradeItem) -> Bool {
        item.status == .graded || item.earnedPoints != nil
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

private extension GradingCategory {
    var addSymbol: String {
        switch categoryType {
        case .homework: "square.and.pencil"
        case .quiz: "questionmark.circle"
        case .lab: "testtube.2"
        case .midterm, .finalExam: "calendar.badge.plus"
        case .project: "folder.badge.plus"
        case .discussion: "bubble.left.and.bubble.right"
        case .participation: "person.2"
        case .attendance: "checkmark.circle"
        case .presentation: "rectangle.on.rectangle"
        case .extraCredit: "plus.circle.fill"
        case .custom: "plus.circle"
        }
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
    let id: UUID; let title: String; let categoryID: UUID?; let dueDate: Date?; let earned: Decimal?; let possible: Decimal
    let override: Decimal?; let status: GradeItemStatus; let included: Bool; let extra: Bool; let dropped: Bool
    let excused: Bool; let multiplier: Decimal; let notes: String; let reminderEnabled: Bool
    let reminderLeadTime: ReminderLeadTime; let customReminderDate: Date?; let notificationIdentifier: String
    let createdAt: Date; let updatedAt: Date

    init(_ item: GradeItem) {
        id = item.id; title = item.title; categoryID = item.category?.id; dueDate = item.dueDate; earned = item.earnedPoints
        possible = item.possiblePoints; override = item.percentageOverride; status = item.status; included = item.isIncluded
        extra = item.isExtraCredit; dropped = item.isDropped; excused = item.isExcused; multiplier = item.multiplier; notes = item.notes
        reminderEnabled = item.reminderEnabled; reminderLeadTime = item.reminderLeadTime
        customReminderDate = item.customReminderDate; notificationIdentifier = item.notificationIdentifier
        createdAt = item.createdAt; updatedAt = item.updatedAt
    }

    func restore(course: CourseRecord, categories: [GradingCategory]) -> GradeItem {
        GradeItem(id: id, course: course, category: categories.first { $0.id == categoryID }, title: title, dueDate: dueDate,
                  earnedPoints: earned, possiblePoints: possible, percentageOverride: override, status: status,
                  isIncluded: included, isExtraCredit: extra, isDropped: dropped, isExcused: excused,
                  multiplier: multiplier, notes: notes, reminderEnabled: reminderEnabled,
                  reminderLeadTime: reminderLeadTime, customReminderDate: customReminderDate,
                  notificationIdentifier: notificationIdentifier, createdAt: createdAt, updatedAt: updatedAt)
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
    var displayName: String { localizedLabelKey }
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
