import Foundation
import SwiftData

@MainActor
enum DemoDataService {
    static func load(into context: ModelContext, preferences: UserPreferences) {
        guard !preferences.demoDataLoaded else { return }
        let term = AcademicTerm(
            academicYear: preferences.firstAcademicYear,
            termType: .fall,
            displayName: "Fall 2026",
            startDate: demoDate(month: 9, day: 21),
            endDate: demoDate(month: 12, day: 11),
            sortOrder: 0
        )
        context.insert(term)
        let samples: [(String, String, Decimal, CourseGrade, Bool, Bool)] = [
            ("CHE 002A", "General Chemistry", 5, .noGrade, true, false),
            ("BIS 002B", "Introduction to Biology", 5, .bPlus, true, false),
            ("UWP 007", "Writing in Science", 4, .a, false, false),
            ("PSC 001", "General Psychology", 4, .b, false, false)
        ]
        var chemistry: CourseRecord?
        for sample in samples {
            let course = CourseRecord(courseCode: sample.0, courseTitle: sample.1,
                                      units: sample.2, grade: sample.3, term: term,
                                      isMajorCourse: sample.4, isUpperDivision: sample.5,
                                      isDemoData: true)
            context.insert(course)
            if sample.0 == "CHE 002A" { chemistry = course }
        }
        if let chemistry {
            context.insert(CourseGradingPolicy(course: chemistry, targetPercentage: 90))
            let scale = GradeScale(course: chemistry, name: "Common Scale Template", boundaries: standardScale, isCommonTemplate: true)
            context.insert(scale)
            let homework = GradingCategory(course: chemistry, name: "Homework", categoryType: .homework, weight: 20, sortOrder: 0)
            let labs = GradingCategory(course: chemistry, name: "Labs", categoryType: .lab, weight: 20, sortOrder: 1)
            let midterms = GradingCategory(course: chemistry, name: "Midterms", categoryType: .midterm, weight: 30, sortOrder: 2)
            let final = GradingCategory(course: chemistry, name: "Final Exam", categoryType: .finalExam, weight: 30, sortOrder: 3)
            [homework, labs, midterms, final].forEach(context.insert)
            context.insert(GradeItem(course: chemistry, category: homework, title: "Homework 1", dueDate: demoDate(month: 9, day: 25, hour: 23, minute: 59), earnedPoints: 18, possiblePoints: 20, status: .graded))
            context.insert(GradeItem(course: chemistry, category: homework, title: "Homework 2", dueDate: demoDate(month: 10, day: 2, hour: 23, minute: 59), earnedPoints: 19, possiblePoints: 20, status: .graded))
            context.insert(GradeItem(course: chemistry, category: homework, title: "Homework 3", dueDate: demoDate(month: 10, day: 23, hour: 23, minute: 59), possiblePoints: 20, status: .upcoming))
            context.insert(GradeItem(course: chemistry, category: labs, title: "Lab 1", dueDate: demoDate(month: 10, day: 6, hour: 17), earnedPoints: 45, possiblePoints: 50, status: .graded))
            context.insert(GradeItem(course: chemistry, category: midterms, title: "Midterm 1", dueDate: demoDate(month: 10, day: 16, hour: 10), earnedPoints: 84, possiblePoints: 100, status: .graded))
        }
        preferences.demoDataLoaded = true
        try? context.save()
    }

    private static let standardScale: [GradeScaleBoundary] = [
        GradeScaleBoundary(letter: .a, minimumPercentage: 93), GradeScaleBoundary(letter: .aMinus, minimumPercentage: 90),
        GradeScaleBoundary(letter: .bPlus, minimumPercentage: 87), GradeScaleBoundary(letter: .b, minimumPercentage: 83),
        GradeScaleBoundary(letter: .bMinus, minimumPercentage: 80), GradeScaleBoundary(letter: .c, minimumPercentage: 70),
        GradeScaleBoundary(letter: .d, minimumPercentage: 60), GradeScaleBoundary(letter: .f, minimumPercentage: 0)
    ]

    private static func demoDate(month: Int, day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(from: DateComponents(
            year: 2026,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )) ?? .now
    }

    static func clear(from context: ModelContext, courses: [CourseRecord], preferences: UserPreferences) throws {
        let demoCourses = courses.filter(\.isDemoData)
        let demoCourseModelIDs = Set(demoCourses.map(\.persistentModelID))

        do {
            let policies = try context.fetch(FetchDescriptor<CourseGradingPolicy>())
            let categories = try context.fetch(FetchDescriptor<GradingCategory>())
            let items = try context.fetch(FetchDescriptor<GradeItem>())
            let scales = try context.fetch(FetchDescriptor<GradeScale>())
            let forecasts = try context.fetch(FetchDescriptor<ForecastScenario>())
            let notificationIdentifiers = items
                .filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }
                .map(\.notificationIdentifier)

            // Delete dependents first, then detach the inverse relationship before
            // deleting demo courses. This leaves no stale course reference for the
            // next Dashboard or import refresh to dereference.
            items.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)
            categories.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)
            policies.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)
            scales.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)
            forecasts.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)

            var demoTermsByModelID: [PersistentIdentifier: AcademicTerm] = [:]
            for course in demoCourses {
                if let term = course.term {
                    demoTermsByModelID[term.persistentModelID] = term
                }
            }
            let termsContainingOnlyDemoCourses = demoTermsByModelID.values.filter { term in
                term.courses.allSatisfy { $0.isDemoData }
            }
            for course in demoCourses {
                course.term = nil
                context.delete(course)
            }
            termsContainingOnlyDemoCourses.forEach(context.delete)
            preferences.demoDataLoaded = false
            try context.save()
            notificationIdentifiers.forEach { GradeItemNotificationService.cancel(identifier: $0) }
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func isLinkedToDemoCourse(
        _ course: CourseRecord?, demoCourseModelIDs: Set<PersistentIdentifier>
    ) -> Bool {
        course.map { demoCourseModelIDs.contains($0.persistentModelID) } ?? false
    }
}
