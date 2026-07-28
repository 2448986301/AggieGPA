import SwiftData
import SwiftUI

struct PlannerView: View {
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query private var courses: [CourseRecord]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    @Query(sort: \PlannerScenario.sortOrder, order: .reverse) private var savedWhatIfScenarios: [PlannerScenario]
    let preferences: UserPreferences

    private var includedTerms: [AcademicTerm] {
        terms.filter { !$0.isDeleted && $0.isIncludedInCumulativeGPA }
    }

    private var liveCourses: [CourseRecord] {
        let includedTermIDs = Set(includedTerms.map(\.persistentModelID))
        return courses.filter { !$0.isDeleted && ($0.term.map { includedTermIDs.contains($0.persistentModelID) } ?? false) }
    }

    private var inputs: [CourseCalculationInput] { liveCourses.map(CourseCalculationInput.init) }
    private var currentTerm: AcademicTerm? { includedTerms.last }
    private var officialCumulative: GPAResult { GPAService.cumulative(inputs) }
    private var officialCurrent: GPAResult {
        guard let currentTerm else { return .empty }
        return GPAService.quarter(inputs, termID: currentTerm.id)
    }
    private var activeWhatIfScenario: PlannerScenario? {
        savedWhatIfScenarios.first { $0.scenarioType == .custom }
    }
    private var projectedGrades: [UUID: CourseGrade] {
        var grades: [UUID: CourseGrade] = Dictionary(uniqueKeysWithValues: liveCourses.compactMap { course -> (UUID, CourseGrade)? in
            guard let scenario = forecasts.first(where: { belongsToCourse($0.course, course) && $0.isSelectedForGPAForecast }),
                  let grade = ProjectedGPAService.courseGrade(from: gradeResult(for: course, forecast: scenario).projectedLetterGrade) else { return nil }
            return (course.id, grade)
        })
        let liveCourseIDs = Set(liveCourses.map(\.id))
        for simulated in activeWhatIfScenario?.simulatedCourses ?? [] {
            guard let sourceCourseID = simulated.sourceCourseID, liveCourseIDs.contains(sourceCourseID) else { continue }
            grades[sourceCourseID] = simulated.grade
        }
        return grades
    }
    private var projectedCurrent: ProjectedGPAResult {
        ProjectedGPAService.calculate(inputs, projectedGrades: projectedGrades, termID: currentTerm?.id)
    }
    private var projectedCumulative: ProjectedGPAResult {
        ProjectedGPAService.calculate(inputs, projectedGrades: projectedGrades)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    gpaOverview
                        .listRowInsets(EdgeInsets(top: DesignSystem.Spacing.small, leading: 0, bottom: DesignSystem.Spacing.small, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section("Plan your GPA") {
                    NavigationLink { WhatIfView(preferences: preferences) } label: {
                        PlannerRow(icon: "chart.line.uptrend.xyaxis", title: "Try a GPA forecast", subtitle: "Explore changes without altering official grades")
                    }
                    NavigationLink { TargetGPAView(preferences: preferences) } label: {
                        PlannerRow(icon: "target", title: "Target GPA", subtitle: "Find the future average you need")
                    }
                }
                Section("Explore") {
                    NavigationLink { FinalGradeCalculatorView() } label: {
                        PlannerRow(icon: "percent", title: "Course grade calculator", subtitle: "Try a course calculation without changing your records")
                    }
                    NavigationLink { ScenarioListView(preferences: preferences) } label: {
                        PlannerRow(icon: "square.3.layers.3d", title: "Assumed grades", subtitle: "Compare saved grade plans")
                    }
                    NavigationLink { FutureQuarterPlannerView(preferences: preferences) } label: {
                        PlannerRow(icon: "calendar.badge.clock", title: "Future terms", subtitle: "Keep planned courses separate")
                    }
                }
                Section { DisclaimerBanner() }
            }
            .navigationTitle("GPA")
        }
    }

    private var gpaOverview: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Label("GPA overview", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            Text("Official results")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.medium) {
                gpaValue("Cumulative GPA", value: officialCumulative.gpa, detail: AppCopy.units(officialCumulative.attemptedUnits, locale: .current))
                Spacer(minLength: DesignSystem.Spacing.small)
                gpaValue("This term GPA", value: officialCurrent.gpa, detail: currentTerm?.displayName ?? "No current term", alignment: .trailing)
            }

            Divider()

            Text("Estimated results")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.medium) {
                projectedValue("Estimated term", result: projectedCurrent)
                Spacer(minLength: DesignSystem.Spacing.small)
                projectedValue("Estimated overall", result: projectedCumulative, alignment: .trailing)
            }
            Text(projectedGrades.isEmpty
                 ? "No estimate yet. Add one from a course."
                 : "Estimates never change your official GPA.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(DesignSystem.Spacing.medium)
        .contentSurface(radius: DesignSystem.Radius.card)
        .accessibilityElement(children: .combine)
    }

    private func gpaValue(_ title: LocalizedStringKey, value: Decimal?, detail: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(DecimalFormatters.string(value, precision: preferences.decimalPrecision))
                .font(.title2.weight(.bold).monospacedDigit())
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func projectedValue(_ title: LocalizedStringKey, result: ProjectedGPAResult, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(result.projectedCourseIDs.isEmpty
                 ? "—"
                 : DecimalFormatters.string(result.projected.gpa, precision: preferences.decimalPrecision))
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(result.projectedCourseIDs.isEmpty ? .secondary : DesignSystem.ColorToken.gold)
            Text(result.projectedCourseIDs.isEmpty ? "No forecast" : "Estimated")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func belongsToCourse(_ relatedCourse: CourseRecord?, _ course: CourseRecord) -> Bool {
        relatedCourse?.persistentModelID == course.persistentModelID
    }

    private func gradeResult(for course: CourseRecord, forecast: ForecastScenario?) -> CourseGradeCalculationResult {
        CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course,
            policy: policies.first { belongsToCourse($0.course, course) },
            categories: categories,
            items: items,
            gradeScale: scales.first { belongsToCourse($0.course, course) },
            forecast: forecast
        ))
    }
}

private struct PlannerRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(DesignSystem.ColorToken.gold)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
