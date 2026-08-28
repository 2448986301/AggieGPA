import AppIntents
import SwiftData
import SwiftUI

private enum CourseDetailSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case gradebook = "Assignments & Exams"
    case breakdown = "Grade Breakdown"
    case forecast = "What Do I Need?"
    var id: String { rawValue }

    var compactTitle: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .gradebook: "Items"
        case .breakdown: "Breakdown"
        case .forecast: "Goal"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
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
    @Environment(\.accessibilityShowButtonShapes) private var showButtonShapes
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    @Query private var allCourses: [CourseRecord]
    @Query(sort: \PlannerScenario.sortOrder, order: .reverse) private var savedPlans: [PlannerScenario]

    let course: CourseRecord
    let preferences: UserPreferences
    let initialItemID: UUID?
    let initialScoringItemID: UUID?
    @State private var section: CourseDetailSection
    @State private var editingCategory: GradingCategory?
    @State private var editingItem: GradeItem?
    @State private var showCategoryEditor = false
    @State private var categoryPendingDeletion: GradingCategory?
    @State private var showNewItemEditor = false
    @State private var showPolicyEditor = false
    @State private var showForecastEditor = false
    @State private var showSyllabusImport = false
    @State private var showSyllabusQuestion = false
    @State private var showSetup = false
    @State private var showCourseTemplates = false
    @State private var showTemplateSave = false
    @State private var showBulkCreate = false
    @State private var quickCategory: GradingCategory?
    @State private var scoringItem: GradeItem?
    @State private var showTargetPicker = false
    @State private var showProjectedGradePicker = false
    @State private var showFinalGradePicker = false
    @State private var editingForecast: ForecastScenario?
    @State private var deletedItem: DeletedGradeItem?
    @State private var itemPendingDeletion: GradeItem?
    @State private var scoreBaseline: ScoreImpactBaseline?
    @State private var scoreImpact: ScoreImpactPresentation?
    @State private var bulkCreatedItemIDs: [UUID]?
    @State private var hasOpenedInitialDestination = false
    @State private var showAllInsights = false

    init(
        course: CourseRecord,
        preferences: UserPreferences,
        initialItemID: UUID? = nil,
        initialScoringItemID: UUID? = nil
    ) {
        self.course = course
        self.preferences = preferences
        self.initialItemID = initialItemID
        self.initialScoringItemID = initialScoringItemID
        _section = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--screenshot-grade-breakdown")
                ? .breakdown
                : .overview
        )
    }

    private func belongsToCourse(_ relatedCourse: CourseRecord?) -> Bool {
        relatedCourse?.persistentModelID == course.persistentModelID
    }
    private var policy: CourseGradingPolicy? { policies.first { belongsToCourse($0.course) } }
    private var syllabusSource: SyllabusSourceStore.StoredSource? {
        guard let policy else { return nil }
        return SyllabusSourceStore.source(for: policy.id)
    }
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
    private var calculationInput: CourseGradeCalculationInput {
        CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policy, categories: courseCategories, items: courseItems,
            gradeScale: scale, forecast: forecast
        )
    }
    private var result: CourseGradeCalculationResult {
        CourseGradeCalculationEngine.calculate(calculationInput)
    }
    private var currentResult: CourseGradeCalculationResult {
        CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policy, categories: courseCategories, items: courseItems,
            gradeScale: scale, forecast: nil as ForecastScenario?
        ))
    }
    private var planningState: GPAPlanningCourseState? {
        GPAPlanningEngine.state(
            for: course,
            policies: policies,
            categories: categories,
            items: items,
            scales: scales,
            forecasts: forecasts,
            savedPlans: savedPlans,
            fallbackTarget: preferences.targetGPA
        )
    }
    private var upcomingItems: [GradeItem] {
        courseItems.filter {
            $0.earnedPoints == nil
                && $0.percentageOverride == nil
                && $0.status != .graded
                && $0.status != .notCounted
                && $0.isIncluded
                && !$0.isExcused
                && !$0.isDropped
        }
        .sorted {
            ($0.dueDate ?? .distantFuture, $0.title)
                < ($1.dueDate ?? .distantFuture, $1.title)
        }
    }
    private var nextItem: GradeItem? { upcomingItems.first }
    private var biggestOpportunity: CourseGradeOpportunity? {
        CourseGradeOpportunityEngine.biggestOpportunity(for: calculationInput)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            secondaryDetailContent
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            feedbackBanner
                // A NavigationStack inside TabView reports the device safe area, not the
                // visible top edge of the floating system tab bar. Keep transient actions
                // above that native chrome so Undo remains readable and tappable.
                .padding(.bottom, feedbackBannerTabBarClearance)
        }
        .navigationTitle(course.courseCode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Course Settings", systemImage: "ellipsis.circle") {
                    Section("Gradebook") {
                        Button("Grading Policy", systemImage: "slider.horizontal.3") { showPolicyEditor = true }
                        Button("Add Category", systemImage: "folder.badge.plus") { editingCategory = nil; showCategoryEditor = true }
                        Button("Add Grade Item", systemImage: "plus") { showNewItemEditor = true }
                    }
                    Section("Create and Reuse") {
                        Button("Create Multiple", systemImage: "checklist") { showBulkCreate = true }
                            .accessibilityIdentifier("createMultipleButton")
                        Button("Save as Course Template", systemImage: "rectangle.3.group") { showTemplateSave = true }
                            .accessibilityIdentifier("saveCourseTemplateButton")
                        Button("Browse Course Templates", systemImage: "square.grid.2x2") { showCourseTemplates = true }
                            .accessibilityIdentifier("browseCourseTemplatesButton")
                    }
                    Section("Import") {
                        Button("Import Grading Policy", systemImage: "doc.text.magnifyingglass") { showSyllabusImport = true }
                            .accessibilityIdentifier("importGradingPolicyButton")
                    }
                }
                .accessibilityIdentifier("courseSettingsMenu")
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
        .sheet(isPresented: $showNewItemEditor) {
            GradeItemEditorView(course: course, categories: courseCategories, item: nil)
        }
        .sheet(item: $editingItem) { item in
            GradeItemEditorView(course: course, categories: courseCategories, item: item)
                .id(item.id)
        }
        .sheet(isPresented: $showPolicyEditor) {
            GradingPolicyEditorView(course: course, policy: policy, scale: scale)
        }
        .sheet(isPresented: $showSyllabusImport) {
            SyllabusImportView(course: course)
        }
        .sheet(isPresented: $showSyllabusQuestion) {
            SyllabusQuestionView(course: course, policy: policy, source: syllabusSource)
        }
        .sheet(isPresented: $showSetup) { GradeBreakdownSetupView(course: course) }
        .sheet(isPresented: $showCourseTemplates) { CourseTemplatesView() }
        .sheet(isPresented: $showTemplateSave) {
            CourseTemplateSaveView(course: course, policy: policy, categories: courseCategories, scale: scale)
        }
        .sheet(isPresented: $showBulkCreate) {
            BulkCreateView(course: course, categories: courseCategories) { ids in
                withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
                    bulkCreatedItemIDs = ids
                    deletedItem = nil
                    scoreImpact = nil
                }
            }
        }
        .sheet(item: $quickCategory) { category in
            QuickGradeItemView(course: course, categories: courseCategories, category: category)
        }
        .sheet(item: $scoringItem) { item in
            RecordScoreView(item: item) { change in
                completeScoreUpdate(item, change: change)
            }
            .id(item.id)
        }
        .sheet(isPresented: $showTargetPicker) { SimpleTargetPickerView(course: course, policy: policy) }
        .sheet(isPresented: $showForecastEditor) {
            ForecastEditorView(course: course, policy: policy, forecast: editingForecast)
        }
        .confirmationDialog("Set Projected Grade", isPresented: $showProjectedGradePicker, titleVisibility: .visible) {
            ForEach(projectedGradeOptions, id: \.self) { grade in
                Button(grade.rawValue) { setProjectedGrade(grade) }
            }
            Button("Use Current") { clearProjectedGrade() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose a grade for this plan. It will update GPA Overview and Full Simulation.")
        }
        .confirmationDialog("Record Final Grade", isPresented: $showFinalGradePicker, titleVisibility: .visible) {
            ForEach(projectedGradeOptions, id: \.self) { grade in
                Button(grade.rawValue) { recordFinalGrade(grade) }
            }
            Button("Set NG") { recordFinalGrade(.noGrade) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Final Grade replaces this course's Current and Projected values.")
        }
        .sheet(isPresented: $showAllInsights) {
            AcademicInsightsFlowView(preferences: preferences)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task(id: courseItems.map(\.id)) { openInitialDestinationIfNeeded() }
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
            .transition(.opacity)
            .accessibilityIdentifier("gradeItemUndoBanner")
        } else if bulkCreatedItemIDs != nil {
            AggieFeedbackBanner(
                "Items created",
                message: "Undo removes all items created in this batch.",
                systemImage: "checklist"
            ) {
                Button("Undo") { undoBulkCreate() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("undoBulkCreateButton")
            }
            .padding(.vertical, DesignSystem.Spacing.small)
            .transition(.opacity)
            .accessibilityIdentifier("bulkCreateUndoBanner")
        } else if let scoreImpact {
            ScoreImpactBanner(
                impact: scoreImpact,
                undo: undoScoreUpdate,
                dismiss: dismissScoreImpact
            )
            .padding(.vertical, DesignSystem.Spacing.small)
            .transition(.opacity)
        }
    }

    private var feedbackBannerTabBarClearance: CGFloat {
        horizontalSizeClass == .compact ? 52 : 0
    }

    private func openInitialDestinationIfNeeded() {
        guard !hasOpenedInitialDestination else { return }
        if let initialScoringItemID,
           let item = courseItems.first(where: { $0.id == initialScoringItemID }) {
            section = .gradebook
            hasOpenedInitialDestination = true
            beginScoring(item)
        } else if let initialItemID,
                  let item = courseItems.first(where: { $0.id == initialItemID }) {
            section = .gradebook
            hasOpenedInitialDestination = true
            editingItem = item
        } else if initialScoringItemID == nil, initialItemID == nil {
            // A course without a grading policy needs setup before the
            // overview can answer meaningful grade questions. Open its
            // gradebook setup state directly; courses with a policy retain
            // the overview landing page.
            if policy == nil, courseItems.isEmpty {
                section = .gradebook
            }
            hasOpenedInitialDestination = true
        }
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
                VStack(spacing: DesignSystem.Spacing.small) {
                    gradeHero

                    Divider()
                        .padding(.horizontal, DesignSystem.Spacing.medium)

                    Picker("Course detail", selection: sectionBinding) {
                        ForEach(CourseDetailSection.allCases) { section in
                            Text(section.compactTitle).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("courseDetailSectionPicker")
                    .accessibilityHint(Text(verbatim: AppLocalization.string(
                        "Switches between overview, assignments, grade breakdown, and goal estimate",
                        locale: locale
                    )))
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                }
                .listRowInsets(EdgeInsets(
                    top: DesignSystem.Spacing.small,
                    leading: 0,
                    bottom: DesignSystem.Spacing.small,
                    trailing: 0
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            activeSectionContent

            Section {
                DisclaimerBanner()
                    .padding(.bottom, feedbackIsVisible ? 76 : 0)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(DesignSystem.Spacing.small))
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(true, for: [.leading, .trailing])
        // iOS 27's floating tab bar overlays the bottom of a nested detail
        // list. Keep the final action reachable above that native chrome.
        .safeAreaPadding(.bottom, horizontalSizeClass == .compact ? 96 : DesignSystem.Spacing.large)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder private var activeSectionContent: some View {
        switch section {
        case .overview:
            overviewContent
        case .gradebook:
            if policy == nil {
                Section {
                    gradebookSetupEmptyState
                        .padding(.vertical, DesignSystem.Spacing.medium)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                gradebookSections
            }
        case .breakdown:
            breakdownContent
        case .forecast:
            forecastContent
                .listRowInsets(detailModuleRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private var overviewContent: some View {
        Section {
            if let biggestOpportunity {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: biggestOpportunity.itemTitle)
                                .font(.headline)
                            Text(verbatim: biggestOpportunity.categoryName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: DesignSystem.Spacing.small)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Course impact")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(percent(biggestOpportunity.courseImpact))
                                .font(.headline.monospacedDigit())
                        }
                    }

                    if let requiredScore = biggestOpportunity.requiredScorePercentage,
                       let projected = biggestOpportunity.projectedAtRequiredScore {
                        Text(
                            String(
                                format: AppLocalization.string(
                                    "A %@ score on %@ could bring the projected course grade to approximately %@, with other forecast assumptions unchanged.",
                                    locale: locale
                                ),
                                percent(requiredScore),
                                biggestOpportunity.itemTitle,
                                percent(projected)
                            )
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(
                            String(
                                format: AppLocalization.string(
                                    "%@ has the highest remaining impact and could affect up to %@ of the course result.",
                                    locale: locale
                                ),
                                biggestOpportunity.itemTitle,
                                percent(biggestOpportunity.courseImpact)
                            )
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("courseBiggestOpportunity")

                Button {
                    withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
                        section = .forecast
                    }
                } label: {
                    HStack {
                        Text("Explore Goal")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("courseBiggestOpportunityAction")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No reliable opportunity yet")
                        .font(.headline)
                    Text("Add remaining assignments and confirm the grading policy to compare their course impact.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("courseBiggestOpportunity")
            }
        } header: {
            Text("Biggest Opportunity")
                .accessibilityIdentifier("courseDetailOverview")
        }

        Section {
            if upcomingItems.isEmpty {
                Text("Nothing due")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcomingItems.prefix(3)) { item in
                    Button {
                        beginScoring(item)
                    } label: {
                        overviewGradeItemRow(item)
                    }
                    .buttonStyle(.plain)
                }

                Button("View All Assignments & Exams") {
                    section = .gradebook
                }
            }
        } header: {
            Text("Upcoming")
                .accessibilityIdentifier("courseUpcomingSection")
        }

        Section {
            if result.categoryBreakdown.isEmpty {
                Button("Set Up Grade Breakdown") {
                    section = .gradebook
                }
            } else {
                ForEach(result.categoryBreakdown.prefix(3), id: \.id) { category in
                    gradeBreakdownRow(category)
                }

                Button("View Full Breakdown") {
                    section = .breakdown
                }
            }
        } header: {
            Text("Grade Breakdown")
                .accessibilityIdentifier("courseGradeBreakdownSection")
        }

        Section {
            if courseItems.isEmpty {
                Text("No assignments or exams yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(courseItems.sorted(by: itemSort).prefix(3)) { item in
                    Button {
                        if hasRecordedScore(item) {
                            beginScoring(item)
                        } else {
                            editingItem = item
                        }
                    } label: {
                        overviewGradeItemRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("View All Assignments & Exams") {
                section = .gradebook
            }
        } header: {
            Text("Assignments")
                .accessibilityIdentifier("courseAssignmentsSection")
        }

        Section {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                if academicInsights.isEmpty {
                    Text("No deterministic alerts from the saved course data.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(academicInsights.prefix(2)) { insight in
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                            Image(systemName: insight.symbolName)
                                .foregroundStyle(insightTint(for: insight.severity))
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: insight.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(verbatim: insight.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    Button("View All") {
                        showAllInsights = true
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("academicInsightsSummary")
        } header: {
            VStack(alignment: .leading) {
                Text("Academic Insights")
                    .accessibilityIdentifier("courseInsightsSection")
            }
            .accessibilityElement(children: .contain)
        }

        Section {
            if syllabusSource != nil {
                Button {
                    showSyllabusQuestion = true
                } label: {
                    Label("Ask about this syllabus", systemImage: "text.book.closed")
                }
                .accessibilityIdentifier("askAboutSyllabusButton")
            }
            Button {
                showSyllabusImport = true
            } label: {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Label(syllabusActionTitle, systemImage: "doc.text.magnifyingglass")
                    Spacer(minLength: DesignSystem.Spacing.small)
                    Text(syllabusStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Syllabus")
                .accessibilityIdentifier("courseSyllabusSection")
        } footer: {
            Text("Import once, then ask questions about this course's saved syllabus anytime.")
        }
    }

    private func overviewGradeItemRow(_ item: GradeItem) -> some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: item.status.icon)
                .foregroundStyle(item.status.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.title)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(item.status.localizedLabelKey))
                    if let dueDate = item.dueDate {
                        Text(dueDate, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSystem.Spacing.small)
            Text(score(item))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(itemAccessibilityLabel(item))
    }

    private func insightTint(for severity: AcademicInsightSeverity) -> Color {
        switch severity {
        case .positive: DesignSystem.ColorToken.success
        case .informative: .secondary
        case .attention: DesignSystem.ColorToken.gold
        case .urgent: DesignSystem.ColorToken.warning
        }
    }

    private var syllabusActionTitle: LocalizedStringKey {
        switch policy?.importStatus {
        case .draft, .needsReview, .confirmed, .failed: "Review Grading Policy"
        case .notImported, nil: "Import Grading Policy"
        }
    }

    private var syllabusStatusText: LocalizedStringKey {
        switch policy?.importStatus {
        case .draft: "Draft"
        case .needsReview: "Needs review"
        case .confirmed: "Confirmed"
        case .failed: "Import failed"
        case .notImported, nil: "Not imported"
        }
    }

    private var detailModuleRowInsets: EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: DesignSystem.Spacing.medium,
            bottom: 0,
            trailing: DesignSystem.Spacing.medium
        )
    }

    private var gradebookSetupEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: DesignSystem.Spacing.small) {
                Text("How is this course graded?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Import a syllabus, choose a template, or set it up manually.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DesignSystem.Spacing.small) {
                gradebookSetupButton(
                    "Use a Template",
                    systemImage: "rectangle.3.group",
                    tint: DesignSystem.ColorToken.gold.opacity(0.32),
                    identifier: "useGradeTemplateSetupButton"
                ) {
                    showSetup = true
                }

                gradebookSetupButton(
                    "Import Syllabus",
                    systemImage: "doc.text.magnifyingglass",
                    identifier: "importSyllabusSetupButton"
                ) {
                    showSyllabusImport = true
                }

                gradebookSetupButton(
                    "Set It Up Manually",
                    systemImage: "slider.horizontal.3",
                    identifier: "manualGradeSetupButton"
                ) {
                    showPolicyEditor = true
                }
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
    }

    private func gradebookSetupButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        tint: Color? = nil,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(
            .glass(
                tint.map { .regular.tint($0).interactive() }
                    ?? .regular.interactive()
            )
        )
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .foregroundStyle(.primary)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var gradebookSections: some View {
        HStack {
            Text("Assignments & Exams").font(.title2.bold())
            Spacer()
            addGradeItemMenu
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

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
        VStack(alignment: .leading, spacing: 0) {
            gradeHeroSummary
        }
        .padding(DesignSystem.Spacing.large)
        .contentSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("courseGradeHero")
    }

    private var gradeHeroSummary: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: course.courseCode)
                    .font(.title3.bold())
                if !course.courseTitle.isEmpty {
                    Text(verbatim: course.courseTitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.large) {
                    currentGradeMetric
                        .frame(maxWidth: .infinity, alignment: .leading)
                    projectedGradeMetric
                        .frame(maxWidth: .infinity, alignment: .leading)
                    targetGradeMetric
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    currentGradeMetric
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.large) {
                        projectedGradeMetric
                            .frame(maxWidth: .infinity, alignment: .leading)
                        targetGradeMetric
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    currentGradeMetric
                    projectedGradeMetric
                    targetGradeMetric
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Based on graded work · \(percent(result.gradedWeight)) graded")
                Button {
                    showFinalGradePicker = true
                } label: {
                    Label(course.grade.isPending ? "Final grade · Not recorded" : "Final Grade: \(course.grade.rawValue)",
                          systemImage: course.grade.isPending ? "clock" : "checkmark.seal")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: AppLocalization.string("Final Grade", locale: locale)))
                .accessibilityValue(Text(verbatim: course.grade.isPending
                    ? AppLocalization.string("Final grade · Not recorded", locale: locale)
                    : AppLocalization.formatted(
                        "Final Grade: %@",
                        locale: locale,
                        course.grade.rawValue
                    )))
                .accessibilityHint(Text(verbatim: AppLocalization.string(
                    "Opens final grade settings",
                    locale: locale
                )))
                .accessibilityIdentifier("courseFinalGradeMetric")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if result.requiresManualReview {
                Label("Check Course Settings before relying on predictions.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(DesignSystem.ColorToken.warning)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("courseGradeSummary")
    }

    private var currentGradeMetric: some View {
        gradeMetric(
            title: "Current Grade",
            value: percent(planningState?.currentPercentage ?? result.calculatedCurrentPercentage),
            detail: planningState?.currentGrade?.rawValue ?? result.currentLetterGrade?.rawValue,
            emphasized: true,
            identifier: "courseCurrentGradeMetric",
            accessibilityTitle: "Current"
        )
    }

    private var projectedGradeMetric: some View {
        Button {
            guard course.grade.isPending else { return }
            showProjectedGradePicker = true
        } label: {
            let projected = planningState?.projectedGrade
            let projectedPercentage = projectedPercentageText
            gradeMetricVisual(
                title: "Projected Grade",
                value: projectedPercentage ?? projected?.rawValue ?? "—",
                detail: projected == nil ? nil : projected?.rawValue,
                emphasized: false
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: AppLocalization.string("Projected", locale: locale)))
        .accessibilityValue(projectedGradeAccessibilityValue)
        .accessibilityHint(Text(verbatim: AppLocalization.string("Opens projected grade choices", locale: locale)))
        .accessibilityIdentifier("courseProjectedGradeMetric")
        .overlay {
            if showButtonShapes {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
                    .strokeBorder(.tint.opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    private var projectedGradeAccessibilityValue: String {
        let parts = [projectedPercentageText, planningState?.projectedGrade?.rawValue]
            .compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    /// A forecast has a measured percentage. A letter-only plan assumption is
    /// shown at the confirmed scale boundary (≥93% · A), making the source
    /// clear instead of presenting a made-up exact score.
    private var projectedPercentageText: String? {
        guard let state = planningState, let percentage = state.projectedPercentage else { return nil }
        let formatted = percent(percentage)
        return state.projectedPercentageIsBoundary ? "≥\(formatted)" : formatted
    }

    private var targetGradeMetric: some View {
        Button {
            showTargetPicker = true
        } label: {
            gradeMetricVisual(
                title: "Target",
                value: targetGradeValue,
                detail: policy?.targetPercentage == nil ? policy?.targetLetterGrade?.rawValue : nil,
                emphasized: false
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: AppLocalization.string("Target", locale: locale)))
        .accessibilityValue(targetGradeAccessibilityValue)
        .accessibilityHint(Text(verbatim: AppLocalization.string("Opens target grade settings", locale: locale)))
        .accessibilityIdentifier("courseTargetGradeMetric")
        .overlay {
            if showButtonShapes {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
                    .strokeBorder(.tint.opacity(0.55), lineWidth: 1.5)
            }
        }
    }

    private func gradeMetric(
        title: LocalizedStringKey,
        value: String,
        detail: String?,
        emphasized: Bool,
        identifier: String,
        accessibilityTitle: LocalizedStringKey? = nil
    ) -> some View {
        gradeMetricVisual(title: title, value: value, detail: detail, emphasized: emphasized)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityTitle ?? title))
            .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: " "))
            .accessibilityIdentifier(identifier)
    }

    private func gradeMetricVisual(
        title: LocalizedStringKey,
        value: String,
        detail: String?,
        emphasized: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: value)
                    .font(emphasized ? DesignSystem.Typography.heroNumber : DesignSystem.Typography.metric)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let detail {
                    Text(verbatim: detail)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var targetGradeValue: String {
        if let target = policy?.targetPercentage {
            return percent(target)
        }
        if let letter = policy?.targetLetterGrade {
            return letter.rawValue
        }
        return AppLocalization.string("Set target", locale: locale)
    }

    private var targetGradeAccessibilityValue: String {
        if let target = policy?.targetPercentage {
            return percent(target)
        }
        if let letter = policy?.targetLetterGrade {
            return letter.rawValue
        }
        return AppLocalization.string("Not set", locale: locale)
    }

    private func categorySection(_ category: GradingCategory) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: category.name).font(.headline)
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
                .accessibilityLabel(Text(verbatim: AppLocalization.formatted(
                    "Options for %@", locale: locale, category.name
                )))
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
                Text(verbatim: item.title).foregroundStyle(.primary)
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
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .move(edge: .trailing))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("gradeItemRow-\(item.title)")
        .accessibilityLabel(itemAccessibilityLabel(item))
        .accessibilityHint(Text(verbatim: AppLocalization.string(
            "Swipe right to record or edit the score. Swipe left to delete. Long press to edit assignment details.",
            locale: locale
        )))
        .contextMenu {
            Button("Edit Assignment Details", systemImage: "pencil") {
                editingItem = item
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if hasRecordedScore(item) {
                Button {
                    beginScoring(item)
                } label: {
                    Label("Edit Score", systemImage: "pencil.and.list.clipboard")
                }
                .tint(DesignSystem.ColorToken.navyRaised)
            } else {
                Button {
                    beginScoring(item)
                } label: {
                    Label("Record Score", systemImage: "checkmark.circle")
                }
                .tint(DesignSystem.ColorToken.navyRaised)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                requestDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous))
    }

    private var addGradeItemMenu: some View {
        Menu {
            if courseCategories.isEmpty {
                Button("Add Grade Item", systemImage: "plus") {
                    showNewItemEditor = true
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
        .accessibilityLabel(Text(verbatim: AppLocalization.string("Add assignment or exam", locale: locale)))
    }

    private func categoryListHeader(_ category: GradingCategory) -> some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: category.name).font(.headline)
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
            .accessibilityLabel(Text(verbatim: AppLocalization.formatted(
                "Options for %@", locale: locale, category.name
            )))
        }
        .textCase(nil)
    }

    @ViewBuilder private var breakdownContent: some View {
        Section {
            if result.categoryBreakdown.isEmpty {
                ContentUnavailableView("No breakdown yet", systemImage: "chart.bar.xaxis", description: Text("Add grading categories and scores first."))
            } else {
                ForEach(result.categoryBreakdown, id: \.id) { category in
                    gradeBreakdownRow(category)
                }
            }
        } header: {
            VStack(alignment: .leading) {
                Text("Grade Breakdown")
                    .accessibilityIdentifier("gradeBreakdownTitle")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("courseGradeBreakdownSection")
        }

        if !result.categoryBreakdown.isEmpty {
            Section {
                gradeExplanation
            }
        }

        if !result.issues.isEmpty {
            Section("Calculation Details") {
                ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                    Text(verbatim: issue.message(locale: locale))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func gradeBreakdownRow(_ category: CategoryGradeBreakdown) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
                    Text(verbatim: category.name)
                        .font(.headline)
                    Spacer(minLength: DesignSystem.Spacing.small)
                    Text(percent(category.average))
                        .font(.title3.bold().monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: category.name)
                        .font(.headline)
                    Text(percent(category.average))
                        .font(.title3.bold().monospacedDigit())
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignSystem.Spacing.large) {
                    breakdownMetric("Course weight", value: percent(category.weight))
                    breakdownMetric("Target", value: gradeBreakdownTargetReference)
                    breakdownMetric(
                        "Contribution",
                        value: "\(compact(category.contribution)) / \(compact(category.weight))"
                    )
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    LabeledContent("Course weight") {
                        Text(verbatim: percent(category.weight))
                            .monospacedDigit()
                    }
                    LabeledContent("Target") {
                        Text(verbatim: gradeBreakdownTargetReference)
                            .monospacedDigit()
                    }
                    LabeledContent("Contribution") {
                        Text(verbatim: "\(compact(category.contribution)) / \(compact(category.weight))")
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
            }

            Text("\(category.gradedItems) graded · \(category.remainingItems) ungraded")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gradeBreakdownCategory-\(category.id.uuidString)")
    }

    private func breakdownMetric(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gradeBreakdownTargetReference: String {
        if let target = calculationInput.targetPercentage {
            return percent(target)
        }
        if let letter = policy?.targetLetterGrade {
            return letter.rawValue
        }
        return "—"
    }

    private var gradeExplanation: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                ForEach(result.categoryBreakdown, id: \.id) { category in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
                            Text(verbatim: category.name)
                                .lineLimit(2)
                            Spacer(minLength: DesignSystem.Spacing.small)
                            gradeExplanationValue(category)
                        }
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                            Text(verbatim: category.name)
                            gradeExplanationValue(category)
                        }
                    }
                }

                Divider()

                Text(
                    String(
                        format: AppLocalization.string("%@ of the course weight has graded work.", locale: locale),
                        percent(result.gradedWeight)
                    )
                )
                .font(.subheadline)

                Label(
                    "Ungraded work is excluded from the current grade, not counted as zero.",
                    systemImage: "checkmark.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                if let category = highestContributionCategory {
                    Text(
                        String(
                            format: AppLocalization.string("%@ currently contributes the most to this grade.", locale: locale),
                            category.name
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if let lowest = result.worstPossiblePercentage,
                   let highest = result.bestPossiblePercentage {
                    HStack {
                        Text("Possible final range")
                        Spacer()
                        Text("\(percent(lowest)) – \(percent(highest))")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
            .padding(.top, DesignSystem.Spacing.small)
        } label: {
            Label("Why This Grade?", systemImage: "questionmark.circle")
                .font(.headline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gradeExplanation")
    }

    private var highestContributionCategory: CategoryGradeBreakdown? {
        result.categoryBreakdown
            .filter { $0.average != nil }
            .max { $0.contribution < $1.contribution }
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
                    HStack {
                        Spacer(minLength: 0)
                        forecastTargetButton
                    }
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
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .accessibilityIdentifier("forecastGoalTitle")
    }

    @ViewBuilder
    private func gradeExplanationValue(_ category: CategoryGradeBreakdown) -> some View {
        if let average = category.average {
            Text(
                "\(percent(average)) × \(percent(category.contributionBasis)) = \(percent(category.contribution))"
            )
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Not graded yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var forecastTargetButton: some View {
        Button {
            showTargetPicker = true
        } label: {
            Text(policy?.targetPercentage.map { "\(compact($0))%" } ?? "Set target")
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.small)
                .contentShape(.interaction, Capsule())
                .glassEffect(
                    .regular.tint(DesignSystem.ColorToken.gold.opacity(0.32)).interactive(),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .foregroundStyle(.primary)
        .frame(minHeight: 44)
        .contentShape(Capsule())
        .accessibilityIdentifier("forecastTargetButton")
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
            Group {
                if course.courseTitle.isEmpty {
                    Text("Course")
                } else {
                    Text(verbatim: course.courseTitle)
                }
            }
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
            if let currentLetterGrade = result.currentLetterGrade {
                Text(currentLetterGrade.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result.requiresManualReview ? DesignSystem.ColorToken.warning : DesignSystem.ColorToken.gold)
            } else {
                Text("No letter prediction")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result.requiresManualReview ? DesignSystem.ColorToken.warning : DesignSystem.ColorToken.gold)
            }
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

    private var projectedGradeOptions: [CourseGrade] {
        CourseGrade.allCases.filter { $0.gradePointValue != nil }
    }

    private func setProjectedGrade(_ grade: CourseGrade) {
        guard course.grade.isPending else { return }
        let active = GPAPlanningEngine.activeScenario(
            from: savedPlans,
            fallbackTarget: preferences.targetGPA
        )
        let selectedCourseIDs = active.selectedCourseIDs.map { $0.union([course.id]) }
        var assumptions = active.assumedGrades
        assumptions[course.id] = grade
        let updated = GPAPlanningScenarioInput(
            id: active.id,
            name: active.name,
            targetGPA: active.targetGPA,
            selectedCourseIDs: selectedCourseIDs,
            assumedGrades: assumptions
        )
        _ = GPAPlanningEngine.persistActiveScenario(
            updated,
            in: modelContext,
            savedPlans: savedPlans
        )
    }

    private func clearProjectedGrade() {
        let active = GPAPlanningEngine.activeScenario(
            from: savedPlans,
            fallbackTarget: preferences.targetGPA
        )
        guard active.id != nil || !active.assumedGrades.isEmpty else { return }
        var assumptions = active.assumedGrades
        assumptions.removeValue(forKey: course.id)
        let updated = GPAPlanningScenarioInput(
            id: active.id,
            name: active.name,
            targetGPA: active.targetGPA,
            selectedCourseIDs: active.selectedCourseIDs,
            assumedGrades: assumptions
        )
        _ = GPAPlanningEngine.persistActiveScenario(
            updated,
            in: modelContext,
            savedPlans: savedPlans
        )
    }

    private func recordFinalGrade(_ grade: CourseGrade) {
        course.grade = grade
        course.updatedAt = .now
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

    private func undoBulkCreate() {
        guard let bulkCreatedItemIDs else { return }
        do {
            try BulkCreationService.remove(ids: bulkCreatedItemIDs, course: course, context: modelContext)
            withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
                self.bulkCreatedItemIDs = nil
            }
        } catch {
            // Keep the banner visible so the one-step undo remains available for a retry.
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
        let currentGrade = ProjectedGPAService.courseGrade(from: currentResult.currentLetterGrade)
        let currentGrades = currentGrade.map { [course.id: $0] } ?? [:]
        return ProjectedGPAService.calculate(
            allCourses.filter { !$0.isDeleted }.map(CourseCalculationInput.init),
            projectedGrades: [course.id: projectedGrade], currentGrades: currentGrades,
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
        deletedItem != nil || bulkCreatedItemIDs != nil || scoreImpact != nil
    }

    private var academicInsights: [AcademicInsight] {
        AcademicInsightsService.makeInsights(
            course: course, policy: policy, categories: courseCategories, items: courseItems,
            scale: scale, forecast: forecast, locale: locale
        ).sorted { $0.severity.rawValue > $1.severity.rawValue }
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
        if let override = item.percentageOverride {
            return String(
                format: AppLocalization.string("%@ override", locale: locale),
                percent(override)
            )
        }
        guard let earned = item.earnedPoints else { return "— / \(compact(item.possiblePoints))" }
        return "\(compact(earned)) / \(compact(item.possiblePoints))"
    }

    private func itemAccessibilityLabel(_ item: GradeItem) -> String {
        var parts = [
            item.title,
            AppLocalization.string(item.status.localizedLabelKey, locale: locale),
            score(item),
        ]
        if let dueDate = item.dueDate {
            let formattedDate = dueDate.formatted(
                Date.FormatStyle(date: .long, time: .shortened).locale(locale)
            )
            parts.append(
                String(
                    format: AppLocalization.string("Due %@.", locale: locale),
                    formattedDate
                )
            )
        }
        if item.isDropped {
            parts.append(AppLocalization.string("Dropped", locale: locale))
        }
        if item.isExcused {
            parts.append(AppLocalization.string("Excused", locale: locale))
        }
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
    func message(locale: Locale) -> String {
        switch self {
        case .emptyGradebook:
            AppLocalization.string("No counted grade items yet.", locale: locale)
        case .noGradeScale:
            AppLocalization.string("No confirmed course grade scale; letter prediction is hidden.", locale: locale)
        case .missingPolicyNeedsConfirmation:
            AppLocalization.string("Confirm before missing items count as zero.", locale: locale)
        case .weightTotalBelow100(let value):
            String(
                format: AppLocalization.string("Category weights total %@, below 100%%.", locale: locale),
                percent(value)
            )
        case .weightTotalAbove100(let value):
            String(
                format: AppLocalization.string("Category weights total %@, above 100%%.", locale: locale),
                percent(value)
            )
        case .invalidCategoryWeight(let name):
            String(
                format: AppLocalization.string("%@ has an invalid weight.", locale: locale),
                name
            )
        case .unsupportedCustomCategory(let name):
            String(
                format: AppLocalization.string("%@ uses a custom rule requiring manual review.", locale: locale),
                name
            )
        case .invalidPossiblePoints(let title):
            String(
                format: AppLocalization.string("%@ needs possible points greater than zero.", locale: locale),
                title
            )
        case .invalidMultiplier(let title):
            String(
                format: AppLocalization.string("%@ has an invalid multiplier.", locale: locale),
                title
            )
        case .gradedItemMissingScore(let title):
            String(
                format: AppLocalization.string("%@ is graded but has no score.", locale: locale),
                title
            )
        case .dropCountRemovesAll(let name):
            String(
                format: AppLocalization.string("The drop rule removes every item in %@.", locale: locale),
                name
            )
        case .invalidDropCount(let name):
            String(
                format: AppLocalization.string("%@ has an invalid drop rule.", locale: locale),
                name
            )
        case .unassignedItems:
            AppLocalization.string("Assign all items to a weighted category.", locale: locale)
        case .hybridNeedsDirectItems:
            AppLocalization.string("The hybrid policy needs direct-point items.", locale: locale)
        case .gradingPolicyNeedsConfirmation:
            AppLocalization.string("Confirm the imported grading policy before relying on predictions.", locale: locale)
        }
    }
}
