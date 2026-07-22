import SwiftData
import SwiftUI

private struct DeletedCourseSnapshot {
    let id: UUID
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

    private var result: GPAResult { GPAService.quarter(term.courses.map(CourseCalculationInput.init), termID: term.id) }
    private var sortedCourses: [CourseRecord] { term.courses.sorted { $0.courseCode < $1.courseCode } }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Quarter GPA").font(.caption).foregroundStyle(.secondary)
                        Text(DecimalFormatters.string(result.gpa, precision: preferences.decimalPrecision))
                            .font(.largeTitle.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(verbatim: AppCopy.units(result.attemptedUnits, locale: locale))
                        Text(verbatim: AppCopy.points(result.gradePoints, locale: locale))
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section("Courses") {
                if sortedCourses.isEmpty {
                    ContentUnavailableView("No courses", systemImage: "book.closed",
                                           description: Text("Add the first course for this quarter."))
                }
                ForEach(sortedCourses) { course in
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
            Section { DisclaimerBanner() }
        }
        .navigationTitle(term.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Course", systemImage: "plus") { showAdd = true }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("addCourseButton")
            }
        }
        .sheet(isPresented: $showAdd) { CourseEditorView(term: term) }
        .sheet(item: $editingCourse) { CourseEditorView(term: term, course: $0) }
        .safeAreaInset(edge: .bottom) {
            if deleted != nil {
                HStack {
                    Text("Course deleted")
                    Spacer()
                    Button("Undo") { undoDelete() }.bold().accessibilityIdentifier("undoDeleteButton")
                }
                .padding()
                .glassEffect(.regular, in: Capsule())
                .padding(.horizontal)
            }
        }
        .onDisappear { finalizePendingDelete() }
    }

    private func remove(_ course: CourseRecord) {
        deleted = DeletedCourseSnapshot(id: course.id, code: course.courseCode, title: course.courseTitle,
                                        units: course.units, grade: course.grade, gradingBasis: course.gradingBasis,
                                        institution: course.institution, isMajor: course.isMajorCourse,
                                        isUpper: course.isUpperDivision, included: course.isIncludedInGPA,
                                        transfer: course.isTransferCourse, notes: course.notes,
                                        policies: policies.filter { $0.course?.id == course.id },
                                        categories: categories.filter { $0.course?.id == course.id },
                                        items: items.filter { $0.course?.id == course.id },
                                        scales: scales.filter { $0.course?.id == course.id },
                                        forecasts: forecasts.filter { $0.course?.id == course.id })
        modelContext.delete(course)
        try? modelContext.save()
    }

    private func undoDelete() {
        guard let deleted else { return }
        let restored = CourseRecord(id: deleted.id, courseCode: deleted.code, courseTitle: deleted.title,
                                    units: deleted.units, grade: deleted.grade, gradingBasis: deleted.gradingBasis,
                                    institution: deleted.institution, term: term, isMajorCourse: deleted.isMajor,
                                    isUpperDivision: deleted.isUpper, isIncludedInGPA: deleted.included,
                                    isTransferCourse: deleted.transfer, notes: deleted.notes)
        modelContext.insert(restored)
        deleted.policies.forEach { $0.course = restored }
        deleted.categories.forEach { $0.course = restored }
        deleted.items.forEach { $0.course = restored }
        deleted.scales.forEach { $0.course = restored }
        deleted.forecasts.forEach { $0.course = restored }
        self.deleted = nil
        try? modelContext.save()
    }

    private func finalizePendingDelete() {
        guard let deleted else { return }
        let notificationIdentifiers = deleted.items.map(\.notificationIdentifier)
        deleted.items.forEach(modelContext.delete)
        deleted.categories.forEach(modelContext.delete)
        deleted.policies.forEach(modelContext.delete)
        deleted.scales.forEach(modelContext.delete)
        deleted.forecasts.forEach(modelContext.delete)
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
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    let course: CourseRecord
    private var gradeResult: CourseGradeCalculationResult {
        let forecast = forecasts.first { $0.course?.id == course.id && $0.isSelectedForGPAForecast }
        return CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policies.first { $0.course?.id == course.id }, categories: categories,
            items: items, gradeScale: scales.first { $0.course?.id == course.id }, forecast: forecast
        ))
    }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.courseCode).font(.headline).foregroundStyle(.primary)
                if !course.courseTitle.isEmpty { Text(course.courseTitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                HStack {
                    Text(verbatim: AppCopy.units(course.units, locale: locale))
                    if course.isMajorCourse { Label("Major", systemImage: "star.fill") }
                    if course.isRepeatCourse { Label("Repeat", systemImage: "arrow.triangle.2.circlepath") }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
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
        .accessibilityElement(children: .combine)
    }
}
