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
    let term: AcademicTerm
    let preferences: UserPreferences
    @State private var showAdd = false
    @State private var editingCourse: CourseRecord?
    @State private var deleted: DeletedCourseSnapshot?

    private var termCourses: [CourseRecord] {
        courses.filter { !$0.isDeleted && $0.term?.persistentModelID == term.persistentModelID }
    }
    private var result: GPAResult { GPAService.quarter(termCourses.map(CourseCalculationInput.init), termID: term.id) }
    private var sortedCourses: [CourseRecord] { termCourses.sorted { $0.courseCode < $1.courseCode } }
    private var visibleCourses: [CourseRecord] { sortedCourses.filter { $0.persistentModelID != deleted?.modelID } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quarter GPA").font(.caption).foregroundStyle(.secondary)
                            Text(DecimalFormatters.string(result.gpa, precision: preferences.decimalPrecision))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(verbatim: AppCopy.units(result.attemptedUnits, locale: locale))
                            Text(verbatim: AppCopy.points(result.gradePoints, locale: locale))
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("This quarter, based on courses currently included in GPA.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                            Button("Delete", systemImage: "trash", role: .destructive) { remove(course) }
                        }
                        .swipeActions(edge: .leading) { Button("Edit") { editingCourse = course }.tint(.blue) }
                        .swipeActions(edge: .trailing) { Button("Delete", role: .destructive) { remove(course) } }
                }
            }
            Section {
                DisclaimerBanner()
                    .padding(.bottom, deleted == nil ? 0 : 68)
            }
        }
        .navigationTitle(term.displayName)
        .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Course", systemImage: "plus") { showAdd = true }
                        .accessibilityIdentifier("addCourseButton")
                }
        }
        .sheet(isPresented: $showAdd) { CourseEditorView(term: term) }
        .sheet(item: $editingCourse) { CourseEditorView(term: term, course: $0) }
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

private struct CourseRow: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
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
        let forecast = forecasts.first { isAttachedToLiveCourse($0.course) && belongsToCourse($0.course) && $0.isSelectedForGPAForecast }
        return CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policies.first { isAttachedToLiveCourse($0.course) && belongsToCourse($0.course) }, categories: liveCategories,
            items: liveItems, gradeScale: scales.first { isAttachedToLiveCourse($0.course) && belongsToCourse($0.course) }, forecast: forecast
        ))
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
    }

    private var courseIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.courseCode).font(.headline).foregroundStyle(.primary)
            if !course.courseTitle.isEmpty { Text(course.courseTitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack {
                Text(verbatim: AppCopy.units(course.units, locale: locale))
                if course.isMajorCourse { Label("Major", systemImage: "star.fill") }
                if course.isRepeatCourse { Label("Repeat", systemImage: "arrow.triangle.2.circlepath") }
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var courseGrade: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing) {
            if course.grade.isPending, let current = gradeResult.calculatedCurrentPercentage {
                Text("Current \(compact(current))%").font(.headline).foregroundStyle(.primary)
                if let projected = gradeResult.projectedLetterGrade {
                    Text("Projected \(projected.rawValue)").font(.caption2).foregroundStyle(DesignSystem.ColorToken.gold)
                } else {
                    Text("\(compact(gradeResult.gradedWeight))% graded").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Official \(course.grade.rawValue)").font(.headline).foregroundStyle(.primary)
                Text(course.isIncludedInGPA ? "Included" : "Excluded").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
