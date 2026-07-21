import Foundation
import SwiftData

@MainActor
enum DemoDataService {
    static func load(into context: ModelContext, preferences: UserPreferences) {
        guard !preferences.demoDataLoaded else { return }
        let term = AcademicTerm(academicYear: preferences.firstAcademicYear, termType: .fall,
                                displayName: "Fall 2026", sortOrder: 0)
        context.insert(term)
        let samples: [(String, String, Decimal, CourseGrade, Bool, Bool)] = [
            ("CHE 002A", "General Chemistry", 5, .aMinus, true, false),
            ("BIS 002B", "Introduction to Biology", 5, .bPlus, true, false),
            ("UWP 007", "Writing in Science", 4, .a, false, false),
            ("PSC 001", "General Psychology", 4, .b, false, false)
        ]
        for sample in samples {
            let course = CourseRecord(courseCode: sample.0, courseTitle: sample.1,
                                      units: sample.2, grade: sample.3, term: term,
                                      isMajorCourse: sample.4, isUpperDivision: sample.5,
                                      isDemoData: true)
            context.insert(course)
        }
        preferences.demoDataLoaded = true
        try? context.save()
    }

    static func clear(from context: ModelContext, courses: [CourseRecord], preferences: UserPreferences) {
        courses.filter(\.isDemoData).forEach(context.delete)
        preferences.demoDataLoaded = false
        try? context.save()
    }
}

