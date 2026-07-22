import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var gradingCategories: [GradingCategory]
    @Query private var gradeItems: [GradeItem]
    @Query private var gradeScales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    let preferences: UserPreferences
    @State private var showAddCourse = false
    @State private var showNewTerm = false

    private var includedTerms: [AcademicTerm] { terms.filter(\.isIncludedInCumulativeGPA) }
    private var courses: [CourseRecord] { includedTerms.flatMap(\.courses) }
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
            guard let scenario = forecasts.first(where: { $0.course?.id == course.id && $0.isSelectedForGPAForecast }),
                  let grade = ProjectedGPAService.courseGrade(from: gradeResult(for: course, forecast: scenario).projectedLetterGrade) else { return nil }
            return (course.id, grade)
        })
    }
    private var projectedCumulative: ProjectedGPAResult { ProjectedGPAService.calculate(inputs, projectedGrades: projectedGrades) }
    private var projectedQuarter: ProjectedGPAResult {
        ProjectedGPAService.calculate(inputs, projectedGrades: projectedGrades, termID: currentTerm?.id)
    }
    private var upcomingItems: [GradeItem] {
        gradeItems.filter { item in item.dueDate.map { $0 >= Calendar.autoupdatingCurrent.startOfDay(for: .now) } ?? false && !item.isExcused && !item.isDropped }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var attentionItems: [String] {
        var messages = gradeItems.filter { ($0.status == .missing) || (($0.dueDate ?? .distantFuture) < .now && $0.earnedPoints == nil && !$0.isExcused) }
            .prefix(3).map { "\($0.course?.courseCode ?? "Course"): \($0.title) needs attention" }
        for course in courses {
            let result = gradeResult(for: course, forecast: forecasts.first { $0.course?.id == course.id && $0.isSelectedForGPAForecast })
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
                    LazyVStack(spacing: DesignSystem.Spacing.medium) {
                        heroCard
                        secondaryMetrics
                        if !projectedCumulative.projectedCourseIDs.isEmpty { projectedMetrics }
                        if !upcomingItems.isEmpty { upcomingSection }
                        if !attentionItems.isEmpty { attentionSection }
                        if !terms.isEmpty { trendChart }
                        recentCourses
                        DisclaimerBanner()
                    }
                    .padding()
                }
                .refreshable { try? await Task.sleep(for: .milliseconds(250)) }
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Course", systemImage: "plus") { showAddCourse = true }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("dashboardAddCourse")
                }
            }
            .sheet(isPresented: $showAddCourse) {
                if terms.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.medium) {
                        ContentUnavailableView("Add a term first", systemImage: "calendar.badge.plus",
                                               description: Text("Create the term for this course, then add your course."))
                        Button("Add Your First Term") { showAddCourse = false; showNewTerm = true }
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
        }
    }

    private var greeting: String { AppCopy.greeting(name: preferences.displayName, locale: locale) }

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
                    .animation(reduceMotion ? nil : DesignSystem.Motion.spring, value: cumulative.gpa)
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
        .glassCard(tint: DesignSystem.ColorToken.ice)
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
        .padding().glassCard(tint: DesignSystem.ColorToken.gold)
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
        }.frame(maxWidth: .infinity, alignment: .leading).padding().glassCard(tint: DesignSystem.ColorToken.warning)
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
        terms.map { term in
            let result = GPAService.quarter(term.courses.map(CourseCalculationInput.init), termID: term.id)
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
            Text("Recently updated").font(.headline)
            if courses.isEmpty {
                Text("No courses yet").foregroundStyle(.secondary)
            } else {
                ForEach(courses.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(4)) { course in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(course.courseCode).font(.headline)
                            Text(course.courseTitle.isEmpty ? course.term?.displayName ?? "Course" : course.courseTitle)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text(course.grade.rawValue).font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                    if course.id != courses.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(4).last?.id { Divider() }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card))
    }

    private func gradeResult(for course: CourseRecord, forecast: ForecastScenario?) -> CourseGradeCalculationResult {
        let input = CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policies.first { $0.course?.id == course.id }, categories: gradingCategories,
            items: gradeItems, gradeScale: gradeScales.first { $0.course?.id == course.id }, forecast: forecast
        )
        return CourseGradeCalculationEngine.calculate(input)
    }
}
