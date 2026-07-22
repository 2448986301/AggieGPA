import Foundation

struct ProjectedGPAResult: Equatable {
    let official: GPAResult
    let projected: GPAResult
    let projectedCourseIDs: Set<UUID>
}

enum ProjectedGPAService {
    static func calculate(
        _ courses: [CourseCalculationInput],
        projectedGrades: [UUID: CourseGrade],
        termID: UUID? = nil
    ) -> ProjectedGPAResult {
        let scoped = termID.map { id in courses.filter { $0.termID == id } } ?? courses
        let official = GPAService.calculate(scoped)
        var used = Set<UUID>()
        let projectedInputs = scoped.map { course -> CourseCalculationInput in
            var copy = course
            if course.grade.isPending, let projected = projectedGrades[course.id], projected.gradePointValue != nil {
                copy.grade = projected; used.insert(course.id)
            }
            return copy
        }
        return ProjectedGPAResult(official: official, projected: GPAService.calculate(projectedInputs), projectedCourseIDs: used)
    }

    static func courseGrade(from letter: GradeLetter?) -> CourseGrade? {
        letter.flatMap { CourseGrade(rawValue: $0.rawValue) }
    }
}
