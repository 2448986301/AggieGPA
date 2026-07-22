import SwiftData
import SwiftUI

private struct DeletedCourseSnapshot {
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
}

struct TermDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
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
    }

    private func remove(_ course: CourseRecord) {
        deleted = DeletedCourseSnapshot(code: course.courseCode, title: course.courseTitle,
                                        units: course.units, grade: course.grade, gradingBasis: course.gradingBasis,
                                        institution: course.institution, isMajor: course.isMajorCourse,
                                        isUpper: course.isUpperDivision, included: course.isIncludedInGPA,
                                        transfer: course.isTransferCourse, notes: course.notes)
        modelContext.delete(course)
        try? modelContext.save()
    }

    private func undoDelete() {
        guard let deleted else { return }
        modelContext.insert(CourseRecord(courseCode: deleted.code, courseTitle: deleted.title,
                                         units: deleted.units, grade: deleted.grade, gradingBasis: deleted.gradingBasis,
                                         institution: deleted.institution, term: term, isMajorCourse: deleted.isMajor,
                                         isUpperDivision: deleted.isUpper, isIncludedInGPA: deleted.included,
                                         isTransferCourse: deleted.transfer, notes: deleted.notes))
        self.deleted = nil
        try? modelContext.save()
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
    let course: CourseRecord
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
                Text(course.grade.rawValue).font(.title3.bold()).foregroundStyle(.primary)
                Text(course.isIncludedInGPA ? "Included" : "Excluded").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
