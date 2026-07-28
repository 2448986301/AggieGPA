import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
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
    private var cumulative: GPAResult { GPAService.cumulative(inputs) }
    private var currentTerm: AcademicTerm? { includedTerms.last }
    private var current: GPAResult {
        guard let id = currentTerm?.id else { return .empty }
        return GPAService.quarter(inputs, termID: id)
    }
    private var major: GPAResult { GPAService.major(inputs) }
    private var upper: GPAResult { GPAService.upperDivision(inputs) }
    private var projectedGrades: [UUID: CourseGrade] {
        Dictionary(uniqueKeysWithValues: courses.compactMap { course in
            guard let scenario = liveForecasts.first(where: { belongsToCourse($0.course, course) && $0.isSelectedForGPAForecast }),
                  let grade = ProjectedGPAService.courseGrade(from: gradeResult(for: course, forecast: scenario).projectedLetterGrade) else { return nil }
            return (course.id, grade)
        })
    }
    private var projectedCumulative: ProjectedGPAResult { ProjectedGPAService.calculate(inputs, projectedGrades: projectedGrades) }
    private var projectedQuarter: ProjectedGPAResult {
        ProjectedGPAService.calculate(inputs, projectedGrades: projectedGrades, termID: currentTerm?.id)
    }
    private var upcomingItems: [GradeItem] {
        liveGradeItems.filter { item in item.dueDate.map { $0 >= Calendar.autoupdatingCurrent.startOfDay(for: .now) } ?? false && !item.isExcused && !item.isDropped }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var attentionItems: [String] {
        var messages = liveGradeItems.filter { ($0.status == .missing) || (($0.dueDate ?? .distantFuture) < .now && $0.earnedPoints == nil && !$0.isExcused) }
            .prefix(3).map { "\($0.course?.courseCode ?? "Course"): \($0.title) needs attention" }
        for course in courses {
            let result = gradeResult(for: course, forecast: liveForecasts.first { belongsToCourse($0.course, course) && $0.isSelectedForGPAForecast })
            if result.requiresManualReview { messages.append("\(course.courseCode): grading policy needs review") }
            else if result.issues.contains(.noGradeScale) { messages.append("\(course.courseCode): grade scale missing") }
        }
        return Array(messages.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CampusBackground()
                ScrollView {
                    Group {
                        if availableWidth >= 900 {
                            HStack(alignment: .top, spacing: DesignSystem.Spacing.large) {
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                                    todayTasks
                                    gpaSummary
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                                    recentCourses
                                    if !attentionItems.isEmpty { attentionSection }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            LazyVStack(spacing: DesignSystem.Spacing.medium) {
                                todayTasks
                                recentCourses
                                gpaSummary
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
                }
                .refreshable { await Task.yield() }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add", systemImage: "plus") {
                        Button("Add Assignment", systemImage: "square.and.pencil") { present(.assignment) }
                        Button("Add Exam", systemImage: "calendar.badge.plus") { present(.exam) }
                        Button("Add Course", systemImage: "book.closed") { present(.course) }
                        Button("Record Score", systemImage: "checkmark.circle") { present(.score) }
                        Button("Import Syllabus", systemImage: "doc.text.viewfinder") { present(.syllabus) }
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
        }
    }

    private var greeting: String { AppCopy.greeting(name: preferences.displayName, locale: locale) }

    private func present(_ action: TodayAddAction) {
        addAction = action
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
                            Text(item.title).font(.headline)
                            if let due = item.dueDate { Text(due, style: .relative).font(.caption).foregroundStyle(.secondary) }
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
    }

    private var gpaSummary: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("GPA Summary").font(.title3.bold())
            ViewThatFits(in: .horizontal) {
                HStack {
                    gpaMetric("Cumulative GPA", value: DecimalFormatters.string(cumulative.gpa, precision: preferences.decimalPrecision), alignment: .leading)
                    Spacer(minLength: DesignSystem.Spacing.medium)
                    gpaMetric("Projected GPA", value: DecimalFormatters.string(projectedQuarter.projected.gpa, precision: preferences.decimalPrecision), alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    gpaMetric("Cumulative GPA", value: DecimalFormatters.string(cumulative.gpa, precision: preferences.decimalPrecision), alignment: .leading)
                    gpaMetric("Projected GPA", value: DecimalFormatters.string(projectedQuarter.projected.gpa, precision: preferences.decimalPrecision), alignment: .leading)
                }
            }
            Button("See more", action: onOpenGPA)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
        .accessibilityElement(children: .combine)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            HStack {
                Label("Cumulative GPA", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text(verbatim: AppCopy.units(cumulative.attemptedUnits, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if cumulative.gpa == nil {
                ContentUnavailableView("Ready when you are", systemImage: "book.closed",
                                       description: Text("Add a quarter and your first letter-graded course."))
            } else {
                Text(DecimalFormatters.string(cumulative.gpa, precision: preferences.decimalPrecision))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                    .animation(
                        DesignSystem.Motion.emphasized(reduceMotion: reduceMotion),
                        value: cumulative.gpa
                    )
                    .accessibilityLabel("Cumulative GPA \(DecimalFormatters.string(cumulative.gpa, precision: preferences.decimalPrecision))")
                HStack {
                    Label {
                        Text(verbatim: AppCopy.currentGPA(DecimalFormatters.string(current.gpa, precision: preferences.decimalPrecision), locale: locale))
                    } icon: {
                        Image(systemName: current.gpa ?? 0 >= cumulative.gpa ?? 0 ? "arrow.up.right" : "arrow.down.right")
                    }
                    Spacer()
                    Text(verbatim: AppCopy.targetGPA(DecimalFormatters.string(preferences.targetGPA, precision: 2), locale: locale))
                }
                .font(.subheadline.weight(.medium))
                ProgressView(value: min(1, NSDecimalNumber(decimal: cumulative.gpa ?? 0).doubleValue /
                                          max(0.01, NSDecimalNumber(decimal: preferences.targetGPA).doubleValue)))
                    .tint(DesignSystem.ColorToken.gold)
                Text(verbatim: AppCopy.gradePoints(cumulative.gradePoints, locale: locale))
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
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.compact))
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
                    Text(DecimalFormatters.string(projectedCumulative.projected.gpa, precision: preferences.decimalPrecision)).font(.title2.bold())
                }
            }
            Text("Uses selected course forecast scenarios only where no official grade exists. Official GPA above is unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(DesignSystem.Spacing.medium).contentSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Projected GPA")
        .accessibilityValue("Current quarter \(DecimalFormatters.string(projectedQuarter.projected.gpa, precision: preferences.decimalPrecision)), cumulative \(DecimalFormatters.string(projectedCumulative.projected.gpa, precision: preferences.decimalPrecision))")
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Upcoming").font(.headline)
            ForEach(Array(upcomingItems.prefix(5))) { item in
                HStack {
                    VStack(alignment: .leading) { Text(item.title); Text(item.course?.courseCode ?? "Course").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let due = item.dueDate { Text(due, style: .relative).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.compact))
        .accessibilityElement(children: .combine)
    }

    private var trendData: [(String, Double)] {
        includedTerms.map { term in
            let termCourses = courses.filter { $0.term?.persistentModelID == term.persistentModelID }
            let result = GPAService.quarter(termCourses.map(CourseCalculationInput.init), termID: term.id)
            return (term.displayName, NSDecimalNumber(decimal: result.gpa ?? 0).doubleValue)
        }
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
                .accessibilityLabel("Quarter GPA trend")
                .accessibilityValue(trendData.map { "\($0.0), \(String(format: "%.3f", $0.1))" }.joined(separator: "; "))
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
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
                                Text(course.courseTitle.isEmpty ? course.term?.displayName ?? "Course" : course.courseTitle)
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

private enum TodayAddAction: String, Identifiable {
    case assignment, exam, course, score, syllabus
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
                        Text(course.courseTitle).foregroundStyle(.secondary)
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
    var body: some View {
        NavigationStack {
            List {
                ForEach(items.filter { $0.course.map { courseModelIDs.contains($0.persistentModelID) } ?? false }) { item in
                    NavigationLink(item.title) { RecordScoreView(item: item) }
                }
            }
            .navigationTitle("Record Score")
        }
    }
}
