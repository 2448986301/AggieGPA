import Charts
import SwiftData
import SwiftUI

private enum DashboardDestination: Hashable {
    case semesterMap
    case academicCalendar
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Environment(\.todayReferenceDate) private var todayReferenceDate
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query private var allCourses: [CourseRecord]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var gradingCategories: [GradingCategory]
    @Query private var gradeItems: [GradeItem]
    @Query private var gradeScales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    let preferences: UserPreferences
    let onOpenGPA: () -> Void
    @State private var showAddCourse = false
    @State private var showNewTerm = false
    @State private var addAction: TodayAddAction?
    @State private var availableWidth: CGFloat = 0
    @State private var navigationPath = NavigationPath()
    @State private var didOpenScreenshotSemesterMap = false
    @State private var didOpenScreenshotAcademicCalendar = false
    @State private var editingTimelineItem: GradeItem?
    @State private var scoringTimelineItem: GradeItem?
    @AppStorage("showFocusNext") private var showFocusNext = true

    private var todayNow: Date { todayReferenceDate ?? .now }

    private var includedTerms: [AcademicTerm] {
        terms.filter { !$0.isDeleted && $0.isIncludedInCumulativeGPA }
    }
    /// Query course records directly instead of traversing `AcademicTerm.courses`.
    ///
    /// SwiftData can retain a deleted object in an already-materialized inverse
    /// relationship while it refreshes a store. A dashboard must never dereference
    /// that stale object during launch, because doing so traps before the view can
    /// update. The direct query contains only live course records.
    private var courses: [CourseRecord] {
        let includedTermModelIDs = Set(includedTerms.map(\.persistentModelID))
        return allCourses.filter { course in
            guard !course.isDeleted, let term = course.term, !term.isDeleted else { return false }
            return includedTermModelIDs.contains(term.persistentModelID)
        }
    }
    private var liveCourseModelIDs: Set<PersistentIdentifier> {
        Set(courses.map(\.persistentModelID))
    }
    private var livePolicies: [CourseGradingPolicy] {
        policies.filter { !$0.isDeleted && isAttachedToLiveCourse($0.course) }
    }
    private var liveCategories: [GradingCategory] {
        gradingCategories.filter { !$0.isDeleted && isAttachedToLiveCourse($0.course) }
    }
    private var liveGradeItems: [GradeItem] {
        gradeItems.filter { !$0.isDeleted && isAttachedToLiveCourse($0.course) }
    }
    private var liveGradeScales: [GradeScale] {
        gradeScales.filter { !$0.isDeleted && isAttachedToLiveCourse($0.course) }
    }
    private var liveForecasts: [ForecastScenario] {
        forecasts.filter { !$0.isDeleted && isAttachedToLiveCourse($0.course) }
    }
    private var inputs: [CourseCalculationInput] { courses.map(CourseCalculationInput.init) }
    private var planningInputs: [GPAPlanningCourseInput] {
        GPAPlanningEngine.makeInputs(
            courses: courses,
            policies: livePolicies,
            categories: liveCategories,
            items: liveGradeItems,
            scales: liveGradeScales,
            forecasts: liveForecasts
        )
    }
    private var planningSnapshot: GPAPlanningSnapshot {
        GPAPlanningEngine.resolve(
            inputs: planningInputs,
            scenario: GPAPlanningScenarioInput(targetGPA: preferences.targetGPA),
            fallbackTargetUnits: 12
        )
    }
    private var currentEstimatedGrades: [UUID: CourseGrade] {
        estimatedCurrentGrades(from: planningInputs)
    }

    private func estimatedCurrentGrades(
        from planningInputs: [GPAPlanningCourseInput]
    ) -> [UUID: CourseGrade] {
        Dictionary(uniqueKeysWithValues: planningInputs.compactMap { input in
            guard input.isPending,
                  let currentGrade = input.currentGrade,
                  currentGrade.gradePointValue != nil else { return nil }
            return (input.id, currentGrade)
        })
    }
    private var currentTerm: AcademicTerm? { includedTerms.last }
    private var recordedCurrent: GPAResult {
        guard let id = currentTerm?.id else { return .empty }
        return GPAService.quarter(inputs, termID: id)
    }
    private var current: GPAResult {
        guard let id = currentTerm?.id else { return .empty }
        let termInputs = inputs.filter { $0.termID == id }
        let termGrades = currentEstimatedGrades.filter { courseID, _ in
            termInputs.contains { $0.id == courseID }
        }
        return GPAService.live(termInputs, currentGrades: termGrades)
    }
    private var major: GPAResult { GPAService.major(inputs) }
    private var upper: GPAResult { GPAService.upperDivision(inputs) }
    private var projectedGrades: [UUID: CourseGrade] {
        projectedGrades(from: planningInputs)
    }

    private func projectedGrades(
        from planningInputs: [GPAPlanningCourseInput]
    ) -> [UUID: CourseGrade] {
        Dictionary(uniqueKeysWithValues: planningInputs.compactMap { input in
            guard input.hasForecast,
                  let forecastGrade = input.forecastGrade,
                  forecastGrade.gradePointValue != nil else { return nil }
            return (input.id, forecastGrade)
        })
    }
    private var projectedQuarter: ProjectedGPAResult {
        let resolvedInputs = planningInputs
        return ProjectedGPAService.calculate(
            inputs,
            projectedGrades: projectedGrades(from: resolvedInputs),
            currentGrades: estimatedCurrentGrades(from: resolvedInputs),
            termID: currentTerm?.id
        )
    }
    private var upcomingItems: [GradeItem] {
        liveGradeItems.filter { item in
            item.dueDate.map { $0 >= Calendar.autoupdatingCurrent.startOfDay(for: todayNow) } ?? false
                && !hasRecordedScore(item)
                && item.status != .submitted
                && !item.isExcused
                && !item.isDropped
        }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var attentionItems: [String] {
        var messages = liveGradeItems.filter {
            ($0.status == .missing)
                || (($0.dueDate ?? .distantFuture) < todayNow
                    && $0.earnedPoints == nil
                    && $0.status != .submitted
                    && !$0.isExcused)
        }
            .prefix(3).map { "\($0.course?.courseCode ?? "Course"): \($0.title) needs attention" }
        for course in courses {
            let result = gradeResult(for: course, forecast: liveForecasts.first { belongsToCourse($0.course, course) && $0.isSelectedForGPAForecast })
            if result.requiresManualReview { messages.append("\(course.courseCode): grading policy needs review") }
            else if result.issues.contains(.noGradeScale) { messages.append("\(course.courseCode): grade scale missing") }
        }
        return Array(messages.prefix(5))
    }
    private var focusRecommendations: [GradeItem] {
        focusRecommendations(for: todayPlan)
    }

    private func focusRecommendations(for plan: TodayPriorityPlan) -> [GradeItem] {
        let rankedIDs = ([plan.next] + plan.highImpact)
            .compactMap { $0?.id }
        var seen = Set<UUID>()
        let ranked: [GradeItem] = rankedIDs.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return liveGradeItems.first(where: { $0.id == id })
        }
        // SwiftData may publish the item query one render before the derived
        // snapshot plan. Keep the card deterministic during that short window
        // instead of dropping the entire Focus Next surface.
        if ranked.isEmpty, let fallback = upcomingItems.first {
            return [fallback]
        }
        return ranked
    }

    private var todayTaskSnapshots: [TodayTaskSnapshot] {
        let eligibleItems = liveGradeItems.filter {
            $0.isIncluded
                && !$0.isDropped
                && !$0.isExcused
                && $0.status != .notCounted
        }
        let itemsByCategory = Dictionary(grouping: eligibleItems) { $0.category?.persistentModelID }

        return liveGradeItems.compactMap { item in
            guard let course = item.course,
                  liveCourseModelIDs.contains(course.persistentModelID) else { return nil }
            let category = item.category
            let categoryItems = itemsByCategory[category?.persistentModelID] ?? []
            let categoryPossiblePoints = categoryItems.reduce(Decimal.zero) { $0 + $1.possiblePoints }
            let impact = TodayPriorityEngine.courseImpact(
                categoryWeight: category?.weight ?? 0,
                itemPossiblePoints: item.possiblePoints,
                categoryPossiblePoints: categoryPossiblePoints,
                percentageOverride: item.percentageOverride,
                calculationMode: category?.calculationMode,
                categoryItemCount: categoryItems.count
            )
            return TodayTaskSnapshot(
                id: item.id,
                courseID: course.id,
                courseCode: course.courseCode,
                title: item.title,
                dueDate: item.dueDate,
                categoryName: category?.name,
                categoryType: category?.categoryType,
                categoryCalculationMode: category?.calculationMode,
                categoryItemCount: categoryItems.count,
                courseImpact: impact,
                status: item.status,
                hasRecordedScore: hasRecordedScore(item),
                reminderEnabled: item.reminderEnabled,
                isIncluded: item.isIncluded,
                isDropped: item.isDropped,
                isExcused: item.isExcused
            )
        }
    }

    private var todayCourseAlerts: [TodayCourseAlertSnapshot] {
        courses.compactMap { course in
            let result = gradeResult(
                for: course,
                forecast: liveForecasts.first {
                    belongsToCourse($0.course, course) && $0.isSelectedForGPAForecast
                }
            )
            if result.requiresManualReview {
                return TodayCourseAlertSnapshot(
                    id: course.id,
                    courseCode: course.courseCode,
                    reason: .gradingPolicyReview
                )
            }
            if result.issues.contains(.noGradeScale) {
                return TodayCourseAlertSnapshot(
                    id: course.id,
                    courseCode: course.courseCode,
                    reason: .gradeScaleReview
                )
            }
            return nil
        }
    }

    private var todayPlan: TodayPriorityPlan {
        TodayPriorityEngine.makePlan(
            items: todayTaskSnapshots,
            courseAlerts: todayCourseAlerts,
            now: todayNow
        )
    }

    private func hasRecordedScore(_ item: GradeItem) -> Bool {
        item.earnedPoints != nil || item.percentageOverride != nil || item.status == .graded
    }

    private var academicInsights: [AcademicInsight] {
        AcademicInsightsService.makeInsights(
            courses: courses, policies: livePolicies, categories: liveCategories,
            items: liveGradeItems, scales: liveGradeScales, forecasts: liveForecasts,
            locale: locale
        ).sorted { $0.severity.rawValue > $1.severity.rawValue }
    }

    var body: some View {
        let plan = todayPlan
        let insights = academicInsights
        let resolvedPlanningSnapshot = planningSnapshot

        NavigationStack(path: $navigationPath) {
            ZStack {
                CampusBackground()
                ScrollView {
                    Group {
                        if availableWidth >= 900 {
                            iPadDashboardContent(
                                plan: plan,
                                insights: insights,
                                planningSnapshot: resolvedPlanningSnapshot
                            )
                        } else {
                            LazyVStack(spacing: DesignSystem.Spacing.medium) {
                                todayPrioritySection(plan: plan)
                                todayTasks
                                if !plan.dueToday.isEmpty { dueTodaySection(plan: plan) }
                                if !plan.highImpact.isEmpty { highImpactSection(plan: plan) }
                                if !plan.needsAttention.isEmpty { todayNeedsAttentionSection(plan: plan) }
                                recentCourses
                                if !insights.isEmpty {
                                    academicInsightsSection(insights: insights)
                                }
                                gpaSummary(snapshot: resolvedPlanningSnapshot)
                            }
                        }
                    }
                    .frame(maxWidth: 1_180, alignment: .leading)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, DesignSystem.Spacing.small)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { availableWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, width in availableWidth = width }
                        }
                    }
                    Color.clear
                        .frame(height: horizontalSizeClass == .compact ? 120 : 24)
                        .accessibilityHidden(true)
                }
                .refreshable { await Task.yield() }
                // The iOS 27 floating tab bar overlays scroll content. Leave
                // enough native safe-area clearance for the final Today actions
                // to remain tappable instead of sitting underneath it.
                .safeAreaPadding(.bottom, horizontalSizeClass == .compact ? 96 : DesignSystem.Spacing.large)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: DashboardDestination.semesterMap) {
                        Label("Semester Map", systemImage: "calendar.day.timeline.leading")
                    }
                    .accessibilityIdentifier("semesterMapButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: DashboardDestination.academicCalendar) {
                        Label("Academic Calendar", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("academicCalendarButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add", systemImage: "plus") {
                        Button("Add Assignment", systemImage: "square.and.pencil") { present(.assignment) }
                        Button("Add Exam", systemImage: "calendar.badge.plus") { present(.exam) }
                        Button("Add Course", systemImage: "book.closed") { present(.course) }
                        Button("Record Score", systemImage: "checkmark.circle") { present(.score) }
                        Button("Import Syllabus", systemImage: "doc.text.viewfinder") { present(.syllabus) }
                        Button("Quick Add", systemImage: "text.badge.plus") { present(.quickAdd) }
                    }
                        .accessibilityIdentifier("dashboardAddCourse")
                }
            }
            .sheet(isPresented: $showAddCourse) {
                if terms.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.medium) {
                        ContentUnavailableView("Add a term first", systemImage: "calendar.badge.plus",
                                               description: Text("Create the term for this course, then add your course."))
                        Button("Add Your First Term") {
                            showAddCourse = false
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(300))
                                showNewTerm = true
                            }
                        }
                            .buttonStyle(.borderedProminent)
                    }
                        .presentationDetents([.medium])
                } else {
                    CourseEditorView(term: currentTerm ?? terms[0])
                }
            }
            .sheet(isPresented: $showNewTerm) {
                TermEditorView(defaultAcademicYear: preferences.firstAcademicYear)
            }
            .sheet(item: $addAction) { action in
                TodayAddDestination(action: action, term: currentTerm, courses: courses)
            }
            .sheet(item: $editingTimelineItem) { item in
                if let course = item.course {
                    GradeItemEditorView(course: course, categories: categories(for: item), item: item)
                        .id(item.id)
                }
            }
            .sheet(item: $scoringTimelineItem) { item in
                RecordScoreView(item: item)
                    .id(item.id)
            }
            .navigationDestination(for: DashboardDestination.self) { destination in
                switch destination {
                case .semesterMap:
                    SemesterMapView(preferences: preferences)
                case .academicCalendar:
                    AcademicCalendarView(preferences: preferences)
                }
            }
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--screenshot-academic-calendar"), !didOpenScreenshotAcademicCalendar {
                    didOpenScreenshotAcademicCalendar = true
                    await Task.yield()
                    navigationPath.append(DashboardDestination.academicCalendar)
                } else if (arguments.contains("--screenshot-semester-map")
                            || arguments.contains("--screenshot-academic-timeline")),
                          !didOpenScreenshotSemesterMap {
                    didOpenScreenshotSemesterMap = true
                    await Task.yield()
                    navigationPath.append(DashboardDestination.semesterMap)
                }
            }
        }
    }

    /// A regular-width composition with an explicit material split:
    /// cards carry focused decisions on the leading side, while the trailing
    /// side stays open for scanning priorities and deterministic signals.
    @ViewBuilder
    private func iPadDashboardContent(
        plan: TodayPriorityPlan,
        insights: [AcademicInsight],
        planningSnapshot: GPAPlanningSnapshot
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xLarge) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                todayPrioritySection(plan: plan)
                todayTasks
                recentCourses
                if !insights.isEmpty {
                    iPadAcademicInsightsSection(insights: insights)
                }
                gpaSummary(snapshot: planningSnapshot)
                if !attentionItems.isEmpty {
                    attentionSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                if !plan.dueToday.isEmpty {
                    dueTodaySection(plan: plan)
                }
                if !plan.highImpact.isEmpty {
                    highImpactSection(plan: plan)
                }
                if !plan.needsAttention.isEmpty {
                    todayNeedsAttentionSection(plan: plan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String { AppCopy.greeting(name: preferences.displayName, locale: locale) }

    private func present(_ action: TodayAddAction) {
        addAction = action
    }

    private var todayPrioritySection: some View {
        todayPrioritySection(plan: todayPlan)
    }

    private func todayPrioritySection(plan: TodayPriorityPlan) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("What matters today?")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("todayPriorityTitle")
            Text("Next, due today, high impact, and needs attention.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if showFocusNext && !focusRecommendations(for: plan).isEmpty {
                focusNextSection(plan: plan)
            } else if plan.next == nil {
                ContentUnavailableView(
                    "You’re all caught up.",
                    systemImage: "checkmark.circle",
                    description: Text("Add an assignment or exam when something needs your attention.")
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("todayPrioritySection")
    }

    private var todayTasks: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text(upcomingItems.isEmpty ? "Today" : "Upcoming")
                .font(.title2.bold())
            if upcomingItems.isEmpty {
                ContentUnavailableView("You’re all caught up.", systemImage: "checkmark.circle",
                                       description: Text("Add an assignment or exam when something is due."))
            } else {
                ForEach(Array(upcomingItems.prefix(5))) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.course?.courseCode ?? "Course").font(.caption.weight(.semibold)).foregroundStyle(DesignSystem.ColorToken.gold)
                            Text(verbatim: item.title).font(.headline)
                            if let due = item.dueDate {
                                relativeDueDateText(due)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if differentiateWithoutColor {
                                Text(verbatim: AppLocalization.string(item.status.localizedLabelKey, locale: locale))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: item.earnedPoints == nil ? "clock" : "checkmark.circle")
                            .foregroundStyle(item.earnedPoints == nil ? DesignSystem.ColorToken.gold : .secondary)
                    }
                    .padding(.vertical, 4)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .offset(y: DesignSystem.Spacing.xSmall))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
        .animation(
            DesignSystem.Motion.standard(reduceMotion: reduceMotion),
            value: Array(upcomingItems.prefix(5)).map(\.id)
        )
        .accessibilityIdentifier("upcomingItemsSection")
    }

    private var dueTodaySection: some View {
        dueTodaySection(plan: todayPlan)
    }

    private func dueTodaySection(plan: TodayPriorityPlan) -> some View {
        AppSection("Due Today", subtitle: "A short list of work that can move today.") {
            ForEach(plan.dueToday, id: \.id) { snapshot in
                if let item = liveGradeItems.first(where: { $0.id == snapshot.id }) {
                    timelineActionRow(item, emphasize: true, context: "dueToday")
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .accessibilityIdentifier("todayDueTodaySection")
    }

    private var highImpactSection: some View {
        highImpactSection(plan: todayPlan)
    }

    private func highImpactSection(plan: TodayPriorityPlan) -> some View {
        AppSection("High Impact", subtitle: "Remaining work with the largest deterministic course influence.") {
            ForEach(plan.highImpact, id: \.id) { snapshot in
                if let item = liveGradeItems.first(where: { $0.id == snapshot.id }) {
                    timelineActionRow(item, emphasize: true, context: "highImpact")
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .accessibilityIdentifier("todayHighImpactSection")
    }

    private var todayNeedsAttentionSection: some View {
        todayNeedsAttentionSection(plan: todayPlan)
    }

    private func todayNeedsAttentionSection(plan: TodayPriorityPlan) -> some View {
        AppSection("Needs Attention", subtitle: "Resolve the most time-sensitive academic issues first.") {
            ForEach(plan.needsAttention) { attention in
                if let item = attention.item,
                   let liveItem = liveGradeItems.first(where: { $0.id == item.id }),
                   let course = liveItem.course {
                    NavigationLink {
                        CourseDetailView(
                            course: course,
                            preferences: preferences,
                            initialScoringItemID: liveItem.id
                        )
                    } label: {
                        attentionRow(attention, item: liveItem)
                    }
                    .buttonStyle(.plain)
                } else if let course = courses.first(where: { $0.id == attention.courseID }) {
                    NavigationLink {
                        CourseDetailView(course: course, preferences: preferences)
                    } label: {
                        attentionRow(attention, item: nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .accessibilityIdentifier("todayNeedsAttentionSection")
    }

    private func attentionRow(_ attention: TodayAttention, item: GradeItem?) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.ColorToken.warning)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.map { "\($0.course?.courseCode ?? attention.courseCode) · \($0.title)" } ?? "\(attention.courseCode) · \(attentionReason(attention.reason))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(attentionReason(attention.reason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignSystem.Spacing.small)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("todayAttention-\(attention.id.uuidString)")
    }

    private func attentionReason(_ reason: TodayAttentionReason) -> String {
        if AppCopy.isChinese(locale) {
            switch reason {
            case .overdue: return "已逾期，需要处理"
            case .missing: return "标记为缺交，请检查状态"
            case .dueToday: return "今天到期"
            case .gradingPolicyReview: return "评分规则需要确认"
            case .gradeScaleReview: return "成绩等级需要确认"
            }
        }
        switch reason {
        case .overdue: return "Overdue — take action"
        case .missing: return "Marked missing — review the status"
        case .dueToday: return "Due today"
        case .gradingPolicyReview: return "Grading policy needs review"
        case .gradeScaleReview: return "Grade scale needs review"
        }
    }

    @ViewBuilder
    private func timelineActionRow(_ item: GradeItem, emphasize: Bool, context: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            Image(systemName: todayStatusSymbol(item.status))
                .foregroundStyle(emphasize ? DesignSystem.ColorToken.gold : todayStatusColor(item.status))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.title)
                    .font(emphasize ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(.primary)
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    Text(item.course?.courseCode ?? "Course")
                    if let dueDate = item.dueDate { Text(dueDate, style: .date) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if differentiateWithoutColor {
                    Text(verbatim: AppLocalization.string(item.status.localizedLabelKey, locale: locale))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DesignSystem.Spacing.small)
            Menu {
                if !hasRecordedScore(item) && item.status != .submitted {
                    Button("Mark Complete", systemImage: "checkmark.circle") {
                        markComplete(item)
                    }
                }
                let scoreLabel: LocalizedStringKey = hasRecordedScore(item) ? "Edit Score" : "Add Grade"
                Button {
                    scoringTimelineItem = item
                } label: {
                    Label(scoreLabel, systemImage: "checkmark.circle")
                }
                Button("Edit Assignment Details", systemImage: "pencil") {
                    editingTimelineItem = item
                }
                let reminderLabel: LocalizedStringKey = item.reminderEnabled ? "Edit Reminder" : "Set Reminder"
                Button {
                    editingTimelineItem = item
                } label: {
                    Label(reminderLabel, systemImage: "bell")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text(verbatim: String(
                format: AppLocalization.string("Actions for %@", locale: locale), item.title
            )))
        .accessibilityIdentifier("todayActions-\(context)-\(item.id.uuidString)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("todayTimelineItem-\(context)-\(item.title)")
    }

    private func markComplete(_ item: GradeItem) {
        item.status = .submitted
        item.updatedAt = .now
        GradeItemNotificationService.cancel(identifier: item.notificationIdentifier)
        try? modelContext.save()
    }

    private func categories(for item: GradeItem) -> [GradingCategory] {
        guard let course = item.course else { return [] }
        return liveCategories
            .filter { $0.course?.persistentModelID == course.persistentModelID }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private func todayStatusSymbol(_ status: GradeItemStatus) -> String {
        switch status {
        case .graded: "checkmark.circle.fill"
        case .missing: "exclamationmark.circle.fill"
        case .excused: "minus.circle"
        case .dropped: "arrow.down.circle"
        case .submitted: "paperplane.fill"
        case .notCounted: "nosign"
        case .upcoming: "clock"
        }
    }

    private func todayStatusColor(_ status: GradeItemStatus) -> Color {
        status == .missing ? DesignSystem.ColorToken.warning : (status == .graded ? DesignSystem.ColorToken.success : .secondary)
    }

    private func gpaSummary(snapshot: GPAPlanningSnapshot) -> some View {
        gpaSummaryContent(snapshot: snapshot)
            .padding(DesignSystem.Spacing.medium)
            .contentSurface()
    }

    private func gpaSummaryContent(snapshot: GPAPlanningSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("GPA Summary").font(.title3.bold())
            ViewThatFits(in: .horizontal) {
                HStack {
                    gpaMetric("Current GPA", value: DecimalFormatters.string(snapshot.current.gpa, precision: preferences.decimalPrecision), alignment: .leading)
                    Spacer(minLength: DesignSystem.Spacing.medium)
                    gpaMetric("Projected GPA", value: DecimalFormatters.string(snapshot.projected.gpa, precision: preferences.decimalPrecision), alignment: .trailing)
                    Spacer(minLength: DesignSystem.Spacing.medium)
                    if let final = snapshot.final?.gpa {
                        gpaMetric("Final GPA", value: DecimalFormatters.string(final, precision: preferences.decimalPrecision), alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    gpaMetric("Current GPA", value: DecimalFormatters.string(snapshot.current.gpa, precision: preferences.decimalPrecision), alignment: .leading)
                    gpaMetric("Projected GPA", value: DecimalFormatters.string(snapshot.projected.gpa, precision: preferences.decimalPrecision), alignment: .leading)
                    if let final = snapshot.final?.gpa {
                        gpaMetric("Final GPA", value: DecimalFormatters.string(final, precision: preferences.decimalPrecision), alignment: .leading)
                    }
                }
            }
            if snapshot.final == nil {
                Text(verbatim: finalGradeProgressText(for: snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("dashboardFinalGradeProgress")
            }
            Button("See more", action: onOpenGPA)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func finalGradeProgressText(for snapshot: GPAPlanningSnapshot) -> String {
        String(
            format: AppLocalization.string("Final grades %lld of %lld available", locale: locale),
            locale: locale,
            Int64(snapshot.eligibleFinalGradeCount),
            Int64(snapshot.eligibleCourseCount)
        )
    }

    private var academicInsightsSection: some View {
        academicInsightsSection(insights: academicInsights)
    }

    private func academicInsightsSection(insights: [AcademicInsight]) -> some View {
        AcademicInsightsSummaryView(
            insights: insights,
            courses: courses,
            items: liveGradeItems,
            preferences: preferences,
            limit: 3
        )
    }

    private var iPadAcademicInsightsSection: some View {
        iPadAcademicInsightsSection(insights: academicInsights)
    }

    private func iPadAcademicInsightsSection(insights: [AcademicInsight]) -> some View {
        AcademicInsightsSummaryView(
            insights: insights,
            courses: courses,
            items: liveGradeItems,
            preferences: preferences,
            limit: 3,
            usesOuterSurface: true
        )
    }

    private var focusNextSection: some View {
        focusNextSection(plan: todayPlan)
    }

    private func focusNextSection(plan: TodayPriorityPlan) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                Label("Focus Next", systemImage: "scope")
                    .font(.headline)
                    .accessibilityIdentifier("focusNextTitle")
                Spacer()
                Button("Hide Focus Next", systemImage: "xmark") {
                    withAnimation(DesignSystem.Motion.quick(reduceMotion: reduceMotion)) {
                        showFocusNext = false
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("hideFocusNextButton")
            }

            ForEach(focusRecommendations(for: plan)) { item in
                if let course = item.course {
                    NavigationLink {
                        CourseDetailView(
                            course: course,
                            preferences: preferences,
                            initialScoringItemID: item.id
                        )
                    } label: {
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                            Image(systemName: focusSymbol(for: item))
                                .foregroundStyle(DesignSystem.ColorToken.gold)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(course.courseCode) · \(item.title)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(focusReason(for: item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: DesignSystem.Spacing.small)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: AppLocalization.formatted(
                        "Open score entry for %@", locale: locale, item.title
                    )))
                    .accessibilityIdentifier("focusNextItem-\(item.title)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: DesignSystem.Spacing.xSmall)))
        .accessibilityElement(children: .contain)
    }

    private func focusReason(for item: GradeItem) -> String {
        let dueDescription: String
        if let due = item.dueDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.unitsStyle = .full
            let start = Calendar.autoupdatingCurrent.startOfDay(for: todayNow)
            let dueDay = Calendar.autoupdatingCurrent.startOfDay(for: due)
            dueDescription = formatter.localizedString(for: dueDay, relativeTo: start)
        } else {
            dueDescription = AppCopy.isChinese(locale) ? "未设置日期" : "No due date"
        }

        if let category = item.category, category.weight > 0 {
            let categoryName = category.name
            if AppCopy.isChinese(locale) {
                return "\(dueDescription)到期 · \(categoryName)占课程总评的 \(compact(category.weight))%。"
            }
            return String(
                format: "Due %@ · %@ is worth %@ of the course grade.",
                dueDescription,
                categoryName,
                "\(compact(category.weight))%"
            )
        }
        return AppCopy.isChinese(locale) ? "\(dueDescription)到期。" : "Due \(dueDescription)."
    }

    private func focusSymbol(for item: GradeItem) -> String {
        switch item.category?.categoryType {
        case .finalExam, .midterm:
            "calendar.badge.clock"
        case .lab:
            "flask"
        case .quiz:
            "questionmark.circle"
        default:
            "checklist"
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            HStack {
                Label(planningSnapshot.final?.gpa == nil ? "Current GPA" : "Final GPA", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text(verbatim: AppCopy.units(planningSnapshot.current.attemptedUnits, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if planningSnapshot.current.gpa == nil {
                ContentUnavailableView("Ready when you are", systemImage: "book.closed",
                                       description: Text("Add a quarter and your first letter-graded course."))
            } else {
                let primaryGPA = planningSnapshot.final?.gpa ?? planningSnapshot.current.gpa
                Text(DecimalFormatters.string(primaryGPA, precision: preferences.decimalPrecision))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                    .animation(
                        DesignSystem.Motion.emphasized(reduceMotion: reduceMotion),
                        value: primaryGPA
                    )
                    .accessibilityLabel(Text(verbatim: AppLocalization.formatted(
                        planningSnapshot.final?.gpa == nil ? "Current GPA %@" : "Final GPA %@",
                        locale: locale,
                        DecimalFormatters.string(primaryGPA, precision: preferences.decimalPrecision)
                    )))
                HStack {
                    Label {
                        Text(verbatim: AppCopy.currentGPA(DecimalFormatters.string(current.gpa, precision: preferences.decimalPrecision), locale: locale))
                    } icon: {
                        Image(systemName: current.gpa ?? 0 >= planningSnapshot.current.gpa ?? 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    Spacer()
                    Text(verbatim: AppCopy.targetGPA(DecimalFormatters.string(preferences.targetGPA, precision: 2), locale: locale))
                }
                .font(.subheadline.weight(.medium))
                ProgressView(value: min(1, NSDecimalNumber(decimal: primaryGPA ?? 0).doubleValue /
                                          max(0.01, NSDecimalNumber(decimal: preferences.targetGPA).doubleValue)))
                    .tint(DesignSystem.ColorToken.gold)
                Text(verbatim: AppCopy.gradePoints(planningSnapshot.current.gradePoints, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: planningSnapshot.final?.gpa.map {
                    String(format: AppLocalization.string("Final GPA: %@", locale: locale), locale: locale,
                           DecimalFormatters.string($0, precision: preferences.decimalPrecision))
                } ?? finalGradeProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .contentSurface()
    }

    private var secondaryMetrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.Spacing.small) {
            if preferences.showMajorGPA { metricCard("Major GPA", result: major, icon: "star") }
            if preferences.showUpperDivisionGPA { metricCard("Upper-Division", result: upper, icon: "graduationcap") }
            metricCard("Current Quarter", result: current, icon: "calendar")
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "checkmark.circle")
                Text("Courses").font(.caption).foregroundStyle(.secondary)
                Text("\(courses.count)").font(.title2.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var projectedMetrics: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Label("Projected GPA", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
            HStack {
                VStack(alignment: .leading) {
                    Text("Projected Current Quarter").font(.caption).foregroundStyle(.secondary)
                    Text(DecimalFormatters.string(projectedQuarter.projected.gpa, precision: preferences.decimalPrecision)).font(.title2.bold())
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Projected Cumulative").font(.caption).foregroundStyle(.secondary)
                    Text(DecimalFormatters.string(planningSnapshot.projected.gpa, precision: preferences.decimalPrecision)).font(.title2.bold())
                }
            }
            Text("Projected GPA uses current coursework and selected forecasts. Final grades replace estimates as they arrive.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(DesignSystem.Spacing.medium).contentSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: AppLocalization.string("Projected GPA", locale: locale)))
        .accessibilityValue(AppLocalization.formatted(
            "Current quarter %@, cumulative %@",
            locale: locale,
            DecimalFormatters.string(projectedQuarter.projected.gpa, precision: preferences.decimalPrecision),
            DecimalFormatters.string(planningSnapshot.projected.gpa, precision: preferences.decimalPrecision)
        ))
    }

    private var finalGradeProgressText: String {
        String(
            format: AppLocalization.string("Final grades %lld of %lld available", locale: locale),
            locale: locale,
            Int64(planningSnapshot.eligibleFinalGradeCount),
            Int64(planningSnapshot.eligibleCourseCount)
        )
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Upcoming").font(.headline)
            ForEach(Array(upcomingItems.prefix(5))) { item in
                HStack {
                    VStack(alignment: .leading) { Text(verbatim: item.title); Text(item.course?.courseCode ?? "Course").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let due = item.dueDate {
                        relativeDueDateText(due)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
        )
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Label("Attention Needed", systemImage: "exclamationmark.triangle").font(.headline)
            ForEach(attentionItems, id: \.self) { Text($0).font(.subheadline) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
    }

    private func metricCard(_ title: LocalizedStringKey, result: GPAResult, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(DecimalFormatters.string(result.gpa, precision: preferences.decimalPrecision)).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var trendData: [(String, Double)] {
        includedTerms.map { term in
            let termCourses = courses.filter { $0.term?.persistentModelID == term.persistentModelID }
            let result = GPAService.quarter(termCourses.map(CourseCalculationInput.init), termID: term.id)
            return (AppCopy.termName(term, locale: locale), NSDecimalNumber(decimal: result.gpa ?? 0).doubleValue)
        }
    }

    private var trendAccessibilityValue: String {
        let pointSeparator = AppCopy.isChinese(locale) ? "，" : ", "
        let listSeparator = AppCopy.isChinese(locale) ? "；" : "; "
        let points = trendData
            .map { "\($0.0)\(pointSeparator)\(String(format: "%.3f", $0.1))" }
            .joined(separator: listSeparator)
        return AppLocalization.formatted("GPA trend data: %@", locale: locale, points)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("GPA Trend").font(.headline)
            if trendData.count > 1 {
                Chart(trendData, id: \.0) { point in
                    LineMark(x: .value("Quarter", point.0), y: .value("GPA", point.1))
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Quarter", point.0), y: .value("GPA", point.1))
                        .foregroundStyle(DesignSystem.ColorToken.navyRaised)
                }
                .chartYScale(domain: 0...4)
                .frame(height: 190)
                .accessibilityLabel(Text(verbatim: AppLocalization.string("Quarter GPA trend", locale: locale)))
                .accessibilityValue(trendAccessibilityValue)
            } else if let point = trendData.first {
                LabeledContent {
                    Text(point.1, format: .number.precision(.fractionLength(preferences.decimalPrecision)))
                        .font(.title3.bold())
                } label: {
                    Label("Add another quarter to see a trend line", systemImage: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 80)
            }
        }
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
        )
    }

    private var recentCourses: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("My Courses").font(.title2.bold())
            if courses.isEmpty {
                Text("No courses yet").foregroundStyle(.secondary)
            } else {
                ForEach(courses.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(4)) { course in
                    NavigationLink {
                        CourseDetailView(course: course, preferences: preferences)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(course.courseCode).font(.headline)
                                Group {
                                    if !course.courseTitle.isEmpty {
                                        Text(verbatim: course.courseTitle)
                                    } else if let term = course.term {
                                        Text(verbatim: AppCopy.termName(term, locale: locale))
                                    } else {
                                        Text("Course")
                                    }
                                }
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            let result = gradeResult(for: course, forecast: liveForecasts.first { belongsToCourse($0.course, course) && $0.isSelectedForGPAForecast })
                            VStack(alignment: .trailing) {
                                Text(result.calculatedCurrentPercentage.map { "\(compact($0))%" } ?? "No scores")
                                    .font(.headline)
                                    .contentTransition(.numericText())
                                    .animation(
                                        DesignSystem.Motion.emphasized(reduceMotion: reduceMotion),
                                        value: result.calculatedCurrentPercentage
                                    )
                                Text(result.currentLetterGrade?.rawValue ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    if course.id != courses.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(4).last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
    }

    private func gpaMetric(_ title: LocalizedStringKey, value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
                .animation(DesignSystem.Motion.emphasized(reduceMotion: reduceMotion), value: value)
        }
        .accessibilityElement(children: .combine)
    }

    private func gradeResult(for course: CourseRecord, forecast: ForecastScenario?) -> CourseGradeCalculationResult {
        let input = CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: livePolicies.first { belongsToCourse($0.course, course) }, categories: liveCategories,
            items: liveGradeItems, gradeScale: liveGradeScales.first { belongsToCourse($0.course, course) }, forecast: forecast
        )
        return CourseGradeCalculationEngine.calculate(input)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.string(key, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }

    private func relativeDueDateText(_ date: Date) -> Text {
        guard let todayReferenceDate else {
            return Text(date, style: .relative)
        }
        return Text(
            verbatim: TodaySnapshotRelativeDateFormatter.string(
                from: todayReferenceDate,
                to: date,
                locale: locale
            )
        )
    }

    private func isAttachedToLiveCourse(_ course: CourseRecord?) -> Bool {
        course.map { liveCourseModelIDs.contains($0.persistentModelID) } ?? false
    }

    private func belongsToCourse(_ relatedCourse: CourseRecord?, _ course: CourseRecord) -> Bool {
        // `id` is app data and traps if a relationship still points at an object
        // SwiftData has deleted. Its persistent model identifier remains readable,
        // so use it for relationship matching at this boundary.
        relatedCourse?.persistentModelID == course.persistentModelID
    }
}

private enum TodaySnapshotRelativeDateFormatter {
    static func string(from referenceDate: Date, to date: Date, locale: Locale) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.month, .day], from: referenceDate, to: date)
        let months = components.month ?? 0
        let days = components.day ?? 0

        if AppCopy.isChinese(locale) {
            if months > 0 && days > 0 { return "\(months)个月\(days)天后" }
            if months > 0 { return "\(months)个月后" }
            if days > 0 { return "\(days)天后" }
            return "今天"
        }

        let monthUnit = months == 1 ? "mth" : "mths"
        let dayUnit = days == 1 ? "day" : "days"
        if months > 0 && days > 0 { return "\(months) \(monthUnit), \(days) \(dayUnit)" }
        if months > 0 { return "\(months) \(monthUnit)" }
        if days > 0 { return "\(days) \(dayUnit)" }
        return "today"
    }
}

private enum TodayAddAction: String, Identifiable {
    case assignment, exam, course, score, syllabus, quickAdd
    var id: String { rawValue }
}

private struct TodayAddDestination: View {
    let action: TodayAddAction
    let term: AcademicTerm?
    let courses: [CourseRecord]

    var body: some View {
        switch action {
        case .course:
            if let term { CourseEditorView(term: term) } else { termUnavailable }
        case .score:
            if courses.isEmpty { unavailable } else { ScorePickerView(courses: courses) }
        case .quickAdd:
            if courses.isEmpty { unavailable } else { NaturalLanguageQuickAddView(courses: courses) }
        case .assignment, .exam, .syllabus:
            if courses.isEmpty { unavailable }
            else if let course = courses.first, courses.count == 1 { destination(for: course) }
            else { GradeActionCoursePicker(courses: courses, action: action) }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView("Add a course first", systemImage: "book.closed", description: Text("Create a course before adding work or scores."))
    }

    private var termUnavailable: some View {
        ContentUnavailableView("Add a term first", systemImage: "calendar.badge.plus", description: Text("Create a term before adding a course."))
    }

    @ViewBuilder
    private func destination(for course: CourseRecord) -> some View {
        switch action {
        case .assignment:
            QuickGradeItemDestination(course: course, isExam: false)
        case .exam:
            QuickGradeItemDestination(course: course, isExam: true)
        case .syllabus:
            SyllabusImportView(course: course)
        case .quickAdd:
            NaturalLanguageQuickAddView(courses: courses)
        case .course, .score:
            EmptyView()
        }
    }
}

private struct GradeActionCoursePicker: View {
    let courses: [CourseRecord]
    let action: TodayAddAction

    var body: some View {
        NavigationStack {
            List(courses) { course in
                NavigationLink {
                    destination(for: course)
                } label: {
                    VStack(alignment: .leading) {
                        Text(course.courseCode).font(.headline)
                        Text(verbatim: course.courseTitle).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Which course?")
        }
    }

    @ViewBuilder
    private func destination(for course: CourseRecord) -> some View {
        switch action {
        case .assignment:
            QuickGradeItemDestination(course: course, isExam: false)
        case .exam:
            QuickGradeItemDestination(course: course, isExam: true)
        case .syllabus:
            SyllabusImportView(course: course)
        case .quickAdd:
            NaturalLanguageQuickAddView(courses: courses)
        case .course, .score:
            EmptyView()
        }
    }
}

private struct QuickGradeItemDestination: View {
    @Query private var gradingCategories: [GradingCategory]
    let course: CourseRecord
    let isExam: Bool

    private func belongsToCourse(_ relatedCourse: CourseRecord?) -> Bool {
        relatedCourse?.persistentModelID == course.persistentModelID
    }

    var body: some View {
        let categories = gradingCategories.filter { belongsToCourse($0.course) }.sorted { $0.sortOrder < $1.sortOrder }
        if let category = categories.first(where: { isExam
            ? ($0.categoryType == .midterm || $0.categoryType == .finalExam)
            : $0.categoryType == .homework
        }) ?? categories.first {
            QuickGradeItemView(course: course, categories: categories, category: category)
        } else {
            GradeItemEditorView(course: course, categories: [], item: nil)
        }
    }
}

private struct ScorePickerView: View {
    @Query private var items: [GradeItem]
    let courses: [CourseRecord]
    private var courseModelIDs: Set<PersistentIdentifier> { Set(courses.map(\.persistentModelID)) }
    private var scoreableItems: [GradeItem] {
        items
            .filter {
                ($0.course.map { courseModelIDs.contains($0.persistentModelID) } ?? false)
                    && !$0.isDropped
                    && !$0.isExcused
            }
            .sorted {
                ($0.dueDate ?? .distantFuture, $0.title)
                    < ($1.dueDate ?? .distantFuture, $1.title)
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if scoreableItems.isEmpty {
                    ContentUnavailableView(
                        "No assignments or exams",
                        systemImage: "checkmark.circle",
                        description: Text("Add an assignment or exam before recording a score.")
                    )
                } else {
                    List(scoreableItems) { item in
                        NavigationLink {
                            RecordScoreView(item: item)
                                .id(item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: item.title)
                                    .font(.body.weight(.medium))
                                HStack(spacing: DesignSystem.Spacing.xSmall) {
                                    Text(item.course?.courseCode ?? "Course")
                                    Text(item.earnedPoints.map { "\(compact($0)) / \(compact(item.possiblePoints))" }
                                         ?? "\(compact(item.possiblePoints)) points")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Record Score")
        }
    }
}
