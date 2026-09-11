import SwiftData
import SwiftUI

private struct DeletedCourseSnapshot {
    let modelID: PersistentIdentifier
    let code: String
    let title: String
    let units: Decimal
    let grade: CourseGrade
    let gradingBasis: GradingBasis
    let institution: InstitutionType
    let isMajor: Bool
    let isUpper: Bool
    let included: Bool
    let transfer: Bool
    let notes: String
    let policies: [CourseGradingPolicy]
    let categories: [GradingCategory]
    let items: [GradeItem]
    let scales: [GradeScale]
    let forecasts: [ForecastScenario]
}

struct TermDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var courses: [CourseRecord]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    @Query private var reminderDefaults: [CourseReminderDefaults]
    let term: AcademicTerm
    let preferences: UserPreferences
    @State private var showAdd = false
    @State private var editingCourse: CourseRecord?
    @State private var coursePendingDeletion: CourseRecord?
    @State private var deleted: DeletedCourseSnapshot?

    private var termCourses: [CourseRecord] {
        courses.filter { !$0.isDeleted && $0.term?.persistentModelID == term.persistentModelID }
    }
    private var inputs: [CourseCalculationInput] { termCourses.map(CourseCalculationInput.init) }
    private var eligibleFinalCourses: [CourseRecord] {
        termCourses.filter { $0.isIncludedInGPA && $0.gradingBasis == .letter && $0.units > 0 }
    }
    private var finalGradeCount: Int {
        eligibleFinalCourses.filter { !$0.grade.isPending }.count
    }
    private var finalGPA: GPAResult? {
        guard !eligibleFinalCourses.isEmpty,
              finalGradeCount == eligibleFinalCourses.count else { return nil }
        return GPAService.quarter(inputs, termID: term.id)
    }
    private var currentEstimatedGrades: [UUID: CourseGrade] {
        Dictionary(uniqueKeysWithValues: termCourses.compactMap { course in
            guard course.grade.isPending,
                  let scale = scales.first(where: { $0.course?.persistentModelID == course.persistentModelID }),
                  let letter = CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
                      course: course,
                      policy: policies.first { $0.course?.persistentModelID == course.persistentModelID },
                      categories: categories.filter { $0.course?.persistentModelID == course.persistentModelID },
                      items: items.filter { $0.course?.persistentModelID == course.persistentModelID },
                      gradeScale: scale,
                      forecast: nil
                  )).currentLetterGrade,
                  let grade = ProjectedGPAService.courseGrade(from: letter) else { return nil }
            return (course.id, grade)
        })
    }
    private var currentResult: GPAResult {
        GPAService.live(inputs, currentGrades: currentEstimatedGrades)
    }
    private var sortedCourses: [CourseRecord] { termCourses.sorted { $0.courseCode < $1.courseCode } }
    private var visibleCourses: [CourseRecord] { sortedCourses.filter { $0.persistentModelID != deleted?.modelID } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current GPA").font(.caption).foregroundStyle(.secondary)
                            Text(DecimalFormatters.string(currentResult.gpa, precision: preferences.decimalPrecision))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(verbatim: AppCopy.units(currentResult.attemptedUnits, locale: locale))
                            Text(verbatim: AppCopy.points(currentResult.gradePoints, locale: locale))
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(verbatim: AppLocalization.string(
                        "Current grades use course work. Final grades replace estimates when the final report arrives.",
                        locale: locale
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let finalGPA {
                        Text(verbatim: String(
                            format: AppLocalization.string("Final GPA: %@", locale: locale),
                            locale: locale,
                            DecimalFormatters.string(finalGPA.gpa, precision: preferences.decimalPrecision)
                        ))
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } else if !eligibleFinalCourses.isEmpty {
                        Text(verbatim: String(
                            format: AppLocalization.string("Final grades %lld of %lld available", locale: locale),
                            locale: locale,
                            Int64(finalGradeCount),
                            Int64(eligibleFinalCourses.count)
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .contentSurface(radius: DesignSystem.Radius.card)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(
                    top: DesignSystem.Spacing.small,
                    leading: 0,
                    bottom: DesignSystem.Spacing.small,
                    trailing: 0
                ))
            }
            Section("Courses") {
                if visibleCourses.isEmpty {
                    ContentUnavailableView("No courses", systemImage: "book.closed",
                                           description: Text("Add the first course for this quarter."))
                }
                ForEach(visibleCourses) { course in
                    NavigationLink {
                        CourseDetailView(course: course, preferences: preferences)
                    } label: {
                        CourseRow(course: course)
                    }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingCourse = course }
                            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(course) }
                            Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(course) }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                editingCourse = course
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                requestDelete(course)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            }
            Section {
                DisclaimerBanner()
                    .padding(.bottom, deleted == nil ? 0 : 68)
            }
        }
        .navigationTitle(AppCopy.termName(term, locale: locale))
        .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Course", systemImage: "plus") { showAdd = true }
                        .accessibilityIdentifier("addCourseButton")
                }
        }
        .sheet(isPresented: $showAdd) { CourseEditorView(term: term) }
        .sheet(item: $editingCourse) { CourseEditorView(term: term, course: $0) }
        .alert("Delete this course?", isPresented: isShowingCourseDeletionAlert) {
            Button("Delete Course", role: .destructive) {
                if let coursePendingDeletion { remove(coursePendingDeletion) }
                coursePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { coursePendingDeletion = nil }
        } message: {
            Text("Assignments, grading rules, and forecasts for this course will be deleted. You can undo before leaving this screen.")
        }
        .overlay(alignment: .bottom) {
            if deleted != nil {
                AggieFeedbackBanner("Course deleted", systemImage: "trash") {
                    Button("Undo") { undoDelete() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("undoDeleteButton")
                }
                .padding(.bottom, DesignSystem.Spacing.small)
                .transition(DesignSystem.Motion.feedbackTransition(reduceMotion: reduceMotion))
            }
        }
        .onDisappear { finalizePendingDelete() }
    }

    private var isShowingCourseDeletionAlert: Binding<Bool> {
        Binding(
            get: { coursePendingDeletion != nil },
            set: { if !$0 { coursePendingDeletion = nil } }
        )
    }

    private func requestDelete(_ course: CourseRecord) {
        coursePendingDeletion = course
    }

    private func remove(_ course: CourseRecord) {
        let courseModelID = course.persistentModelID
        func belongsToCourse(_ relatedCourse: CourseRecord?) -> Bool {
            relatedCourse?.persistentModelID == courseModelID
        }
        let snapshot = DeletedCourseSnapshot(modelID: courseModelID, code: course.courseCode, title: course.courseTitle,
                                             units: course.units, grade: course.grade, gradingBasis: course.gradingBasis,
                                             institution: course.institution, isMajor: course.isMajorCourse,
                                             isUpper: course.isUpperDivision, included: course.isIncludedInGPA,
                                             transfer: course.isTransferCourse, notes: course.notes,
                                             policies: policies.filter { belongsToCourse($0.course) },
                                             categories: categories.filter { belongsToCourse($0.course) },
                                             items: items.filter { belongsToCourse($0.course) },
                                             scales: scales.filter { belongsToCourse($0.course) },
                                             forecasts: forecasts.filter { belongsToCourse($0.course) })
        withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
            deleted = snapshot
        }
    }

    private func undoDelete() {
        guard deleted != nil else { return }
        withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
            self.deleted = nil
        }
    }

    private func finalizePendingDelete() {
        guard let deleted else { return }
        let notificationIdentifiers = deleted.items.map(\.notificationIdentifier)
        deleted.items.forEach(modelContext.delete)
        deleted.categories.forEach(modelContext.delete)
        deleted.policies.forEach(modelContext.delete)
        deleted.scales.forEach(modelContext.delete)
        deleted.forecasts.forEach(modelContext.delete)
        if let course = termCourses.first(where: { $0.persistentModelID == deleted.modelID }) {
            let deletedCourseID = course.id
            reminderDefaults
                .filter { $0.courseID == deletedCourseID }
                .forEach(modelContext.delete)
            course.term = nil
            modelContext.delete(course)
        }
        do {
            try modelContext.save()
            notificationIdentifiers.forEach { GradeItemNotificationService.cancel(identifier: $0) }
            self.deleted = nil
        } catch {
            modelContext.rollback()
        }
    }

    private func duplicate(_ course: CourseRecord) {
        modelContext.insert(CourseRecord(courseCode: course.courseCode, courseTitle: course.courseTitle,
                                         units: course.units, grade: course.grade, gradingBasis: course.gradingBasis,
                                         institution: course.institution, term: term, isMajorCourse: course.isMajorCourse,
                                         isUpperDivision: course.isUpperDivision, isIncludedInGPA: course.isIncludedInGPA,
                                         isTransferCourse: course.isTransferCourse, notes: course.notes))
        try? modelContext.save()
    }
}

struct CourseRow: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    @Query(sort: \PlannerScenario.sortOrder, order: .reverse) private var savedPlans: [PlannerScenario]
    @Query private var allCourses: [CourseRecord]
    let course: CourseRecord
    var compactLayout = false
    private var usesStackedLayout: Bool { compactLayout || dynamicTypeSize.isAccessibilitySize }
    private var liveCourseModelIDs: Set<PersistentIdentifier> {
        Set(allCourses.filter { !$0.isDeleted }.map(\.persistentModelID))
    }
    private func belongsToCourse(_ relatedCourse: CourseRecord?) -> Bool {
        relatedCourse?.persistentModelID == course.persistentModelID
    }
    private func isAttachedToLiveCourse(_ relatedCourse: CourseRecord?) -> Bool {
        relatedCourse.map { liveCourseModelIDs.contains($0.persistentModelID) } ?? false
    }
    private var gradeResult: CourseGradeCalculationResult {
        let liveCategories = categories.filter { isAttachedToLiveCourse($0.course) }
        let liveItems = items.filter { isAttachedToLiveCourse($0.course) }
        let forecast = selectedForecast
        return CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policies.first { isAttachedToLiveCourse($0.course) && belongsToCourse($0.course) }, categories: liveCategories,
            items: liveItems, gradeScale: scales.first { isAttachedToLiveCourse($0.course) && belongsToCourse($0.course) }, forecast: forecast
        ))
    }
    private var selectedForecast: ForecastScenario? {
        forecasts.first {
            isAttachedToLiveCourse($0.course) && belongsToCourse($0.course) && $0.isSelectedForGPAForecast
        }
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
            fallbackTarget: 0
        )
    }
    var body: some View {
        // Resolve each model snapshot once per update, not once per text label.
        let state = planningState
        let result = gradeResult
        Group {
            if compactLayout {
                compactCourseRow(state: state, result: result)
            } else if usesStackedLayout {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    courseIdentity
                    courseGrade(state: state, result: result)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack {
                    courseIdentity
                    Spacer(minLength: DesignSystem.Spacing.small)
                    courseGrade(state: state, result: result)
                        .frame(width: 168, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("courseRow-\(course.courseCode)")
    }

    private func compactCourseRow(state: GPAPlanningCourseState?, result: CourseGradeCalculationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Keep the grade attached to its course heading, not styled as a
            // second heading. Larger text can wrap this single logical group.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: course.courseCode)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    Text(verbatim: compactPrimaryGrade(state: state, result: result))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: course.courseCode).font(.headline).foregroundStyle(.primary)
                    Text(verbatim: compactPrimaryGrade(state: state, result: result))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            if !course.courseTitle.isEmpty {
                Text(verbatim: course.courseTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            courseMetadata
            courseGrade(state: state, result: result, showPrimary: false)
        }
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func compactPrimaryGrade(state: GPAPlanningCourseState?, result: CourseGradeCalculationResult) -> String {
        guard course.grade.isPending else {
            return AppLocalization.formatted("Final %@", locale: locale, course.grade.rawValue)
        }
        guard let current = state?.currentPercentage ?? result.calculatedCurrentPercentage,
              let letter = state?.currentGrade?.rawValue ?? result.currentLetterGrade?.rawValue else {
            return AppLocalization.string("Current —", locale: locale)
        }
        return AppLocalization.formatted("Current %@%% · %@", locale: locale, compact(current), letter)
    }

    private var courseMetadata: some View {
        HStack(spacing: 6) { courseMetadataItems }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var courseMetadataItems: some View {
        Text(verbatim: AppCopy.units(course.units, locale: locale))
            .fixedSize(horizontal: true, vertical: false)
        if course.isMajorCourse {
            Label("Major", systemImage: "star.fill")
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
        }
        if course.isRepeatCourse {
            Label("Repeat", systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var courseIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.courseCode).font(.headline).foregroundStyle(.primary)
            if !course.courseTitle.isEmpty {
                Text(verbatim: course.courseTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            courseMetadata
        }
    }

    private func courseGrade(state: GPAPlanningCourseState?, result: CourseGradeCalculationResult, showPrimary: Bool = true) -> some View {
        VStack(alignment: usesStackedLayout ? .leading : .trailing) {
            if course.grade.isPending {
                if showPrimary {
                    Text(verbatim: compactPrimaryGrade(state: state, result: result))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                if let projected = state?.projectedGrade {
                    let projectedPercentage = state?.projectedPercentage.map { value in
                        let formatted = compact(value)
                        return state?.projectedPercentageIsBoundary == true ? "≥\(formatted)%" : "\(formatted)%"
                    }
                    let projectedValue = [projectedPercentage, projected.rawValue]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    Text(verbatim: String(
                        format: AppLocalization.string("Projected %@", locale: locale),
                        locale: locale,
                        projectedValue
                    ))
                        .font(.caption2)
                        // Sidebar selection already uses the accent color.
                        // Semantic text stays readable on its selected surface.
                        .foregroundStyle(compactLayout
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(DesignSystem.ColorToken.gold))
                } else {
                    Text(verbatim: String(
                        format: AppLocalization.string("%@%% graded", locale: locale),
                        locale: locale,
                        compact(result.gradedWeight)
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: AppLocalization.string("Final report pending", locale: locale))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                if showPrimary {
                    Text(verbatim: compactPrimaryGrade(state: state, result: result))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Text(course.isIncludedInGPA ? "Included" : "Excluded").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
