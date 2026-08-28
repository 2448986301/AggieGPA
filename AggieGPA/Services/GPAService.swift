import Foundation

enum GPAService {
    static func calculate(
        _ courses: [CourseCalculationInput],
        filter: (CourseCalculationInput) -> Bool = { _ in true },
        applyingRepeatRules: Bool = true
    ) -> GPAResult {
        calculate(courses, filter: filter, applyingRepeatRules: applyingRepeatRules) { $0.grade }
    }

    /// Calculates the live/current GPA without changing the official grade on
    /// any course. Finalized GPA-bearing grades remain authoritative; a
    /// pending/NG course may contribute its deterministic gradebook estimate.
    /// This is deliberately separate from `calculate` so an estimate can never
    /// be persisted as an official transcript grade.
    static func live(
        _ courses: [CourseCalculationInput],
        currentGrades: [UUID: CourseGrade],
        filter: (CourseCalculationInput) -> Bool = { _ in true },
        applyingRepeatRules: Bool = true
    ) -> GPAResult {
        calculate(courses, filter: filter, applyingRepeatRules: applyingRepeatRules) { course in
            guard course.grade.gradePointValue == nil, course.grade.isPending else {
                return course.grade
            }
            return currentGrades[course.id]
        }
    }

    private static func calculate(
        _ courses: [CourseCalculationInput],
        filter: (CourseCalculationInput) -> Bool,
        applyingRepeatRules: Bool,
        grade: (CourseCalculationInput) -> CourseGrade?
    ) -> GPAResult {
        let repeatEvaluation = applyingRepeatRules ? RepeatCourseEngine.evaluate(courses) : nil
        var units: Decimal = 0
        var points: Decimal = 0
        var included = 0
        var excluded = 0

        for course in courses where filter(course) {
            let repeatIncluded = repeatEvaluation?.includedIDs.contains(course.id) ?? true
            let effectiveGrade = grade(course)
            guard course.isIncludedInGPA, repeatIncluded, course.units > 0,
                  let value = effectiveGrade?.gradePointValue else {
                excluded += 1
                continue
            }
            units += course.units
            points += course.units * value
            included += 1
        }

        guard units > 0 else {
            return GPAResult(gpa: nil, attemptedUnits: 0, gradePoints: 0,
                             includedCourseCount: 0, excludedCourseCount: excluded)
        }
        return GPAResult(gpa: points / units, attemptedUnits: units, gradePoints: points,
                         includedCourseCount: included, excludedCourseCount: excluded)
    }

    static func cumulative(_ courses: [CourseCalculationInput]) -> GPAResult {
        calculate(courses)
    }

    static func major(_ courses: [CourseCalculationInput]) -> GPAResult {
        calculate(courses, filter: \CourseCalculationInput.isMajorCourse)
    }

    static func upperDivision(_ courses: [CourseCalculationInput]) -> GPAResult {
        calculate(courses, filter: \CourseCalculationInput.isUpperDivision)
    }

    static func quarter(_ courses: [CourseCalculationInput], termID: UUID) -> GPAResult {
        calculate(courses, filter: { $0.termID == termID })
    }
}
