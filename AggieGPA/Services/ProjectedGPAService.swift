import Foundation

struct ProjectedGPAResult: Equatable {
    /// GPA calculated only from finalized, official GPA-bearing grades.
    let official: GPAResult
    /// GPA calculated from official grades, then a forecast, then the live
    /// current estimate when no forecast exists for a pending course.
    let projected: GPAResult
    /// Courses whose selected forecast supplied the projected value.
    let projectedCourseIDs: Set<UUID>
    /// Courses that had no forecast and therefore used their current estimate
    /// as the projected fallback.
    let currentFallbackCourseIDs: Set<UUID>

    var recorded: GPAResult { official }
}

enum ProjectedGPAService {
    static func calculate(
        _ courses: [CourseCalculationInput],
        projectedGrades: [UUID: CourseGrade],
        currentGrades: [UUID: CourseGrade] = [:],
        termID: UUID? = nil
    ) -> ProjectedGPAResult {
        let scoped = termID.map { id in courses.filter { $0.termID == id } } ?? courses
        let official = GPAService.calculate(scoped)
        var used = Set<UUID>()
        var fallback = Set<UUID>()
        let projectedInputs = scoped.map { course -> CourseCalculationInput in
            var copy = course
            guard course.grade.isPending else { return copy }
            if let projected = projectedGrades[course.id], projected.gradePointValue != nil {
                copy.grade = projected
                used.insert(course.id)
            } else if let current = currentGrades[course.id], current.gradePointValue != nil {
                copy.grade = current
                fallback.insert(course.id)
            }
            return copy
        }
        return ProjectedGPAResult(
            official: official,
            projected: GPAService.calculate(projectedInputs),
            projectedCourseIDs: used,
            currentFallbackCourseIDs: fallback
        )
    }

    static func courseGrade(from letter: GradeLetter?) -> CourseGrade? {
        letter.flatMap { CourseGrade(rawValue: $0.rawValue) }
    }
}
