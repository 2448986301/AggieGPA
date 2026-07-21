import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    let preferences: UserPreferences
    @State private var showAddCourse = false

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

    var body: some View {
        NavigationStack {
            ZStack {
                CampusBackground()
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.medium) {
                        heroCard
                        secondaryMetrics
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
                    ContentUnavailableView("Add a quarter first", systemImage: "calendar.badge.plus",
                                           description: Text("Open Quarters to create the term that this course belongs to."))
                        .presentationDetents([.medium])
                } else {
                    CourseEditorView(term: currentTerm ?? terms[0])
                }
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
}
