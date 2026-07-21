import Foundation

enum GPAService {
    static func calculate(
        _ courses: [CourseCalculationInput],
        filter: (CourseCalculationInput) -> Bool = { _ in true },
        applyingRepeatRules: Bool = true
    ) -> GPAResult {
        let repeatEvaluation = applyingRepeatRules ? RepeatCourseEngine.evaluate(courses) : nil
        var units: Decimal = 0
        var points: Decimal = 0
        var included = 0
        var excluded = 0

        for course in courses where filter(course) {
            let repeatIncluded = repeatEvaluation?.includedIDs.contains(course.id) ?? true
            guard course.isIncludedInGPA, repeatIncluded, course.units > 0,
                  let value = course.grade.gradePointValue else {
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

