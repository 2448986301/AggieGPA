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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    courseIdentity
                    courseGrade
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack {
                    courseIdentity
                    Spacer(minLength: DesignSystem.Spacing.small)
                    courseGrade
                        .frame(width: 168, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("courseRow-\(course.courseCode)")
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
            HStack {
                Text(verbatim: AppCopy.units(course.units, locale: locale))
                if course.isMajorCourse { Label("Major", systemImage: "star.fill") }
                if course.isRepeatCourse { Label("Repeat", systemImage: "arrow.triangle.2.circlepath") }
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var courseGrade: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing) {
            if course.grade.isPending {
                if let current = planningState?.currentPercentage ?? gradeResult.calculatedCurrentPercentage,
                   let currentLetter = planningState?.currentGrade?.rawValue ?? gradeResult.currentLetterGrade?.rawValue {
                    Text(verbatim: String(
                        format: AppLocalization.string("Current %@%% · %@", locale: locale),
                        locale: locale,
                        compact(current),
                        currentLetter
                    ))
                        .font(.headline)
                        .foregroundStyle(.primary)
                } else {
                    Text(verbatim: AppLocalization.string("Current —", locale: locale))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                if let projected = planningState?.projectedGrade {
                    let projectedPercentage = planningState?.projectedPercentage.map { value in
                        let formatted = compact(value)
                        return planningState?.projectedPercentageIsBoundary == true ? "≥\(formatted)%" : "\(formatted)%"
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
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                } else {
                    Text(verbatim: String(
                        format: AppLocalization.string("%@%% graded", locale: locale),
                        locale: locale,
                        compact(gradeResult.gradedWeight)
                    ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: AppLocalization.string("Final report pending", locale: locale))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: String(
                    format: AppLocalization.string("Final %@", locale: locale),
                    locale: locale,
                    course.grade.rawValue
                ))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(course.isIncludedInGPA ? "Included" : "Excluded").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
