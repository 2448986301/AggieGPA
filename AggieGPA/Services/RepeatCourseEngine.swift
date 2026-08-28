import Foundation

/// Undergraduate repeat estimate based on UC Davis DDR A540(F), verified 2026-07-21.
/// When a course would partially exceed the 16-unit limit, all grades remain included.
/// Complex, mismatched, or multiple-repeat cases are surfaced for manual review.
enum RepeatCourseEngine {
    static let replacementLimit: Decimal = 16

    static func evaluate(_ courses: [CourseCalculationInput]) -> RepeatEvaluation {
        var included = Set(courses.map(\.id))
        var excluded = Set<UUID>()
        var afterLimit = Set<UUID>()
        var manual = Set<UUID>()
        var warnings: [String] = []
        var used: Decimal = 0

        let grouped = Dictionary(grouping: courses.compactMap { course -> (UUID, CourseCalculationInput)? in
            guard let group = course.repeatGroupID else { return nil }
            return (group, course)
        }, by: \.0)

        let chronologicalGroups = grouped.sorted { lhs, rhs in
            let lhsDate = lhs.value.map(\.1.attemptedAt).max() ?? .distantPast
            let rhsDate = rhs.value.map(\.1.attemptedAt).max() ?? .distantPast
            if lhsDate == rhsDate { return lhs.key.uuidString < rhs.key.uuidString }
            return lhsDate < rhsDate
        }
        for (groupID, pairs) in chronologicalGroups {
            let attempts = pairs.map(\.1).sorted { $0.repeatAttemptOrder < $1.repeatAttemptOrder }
            guard attempts.count == 2 else {
                manual.insert(groupID)
                warnings.append("\(attempts.first?.courseCode ?? "Repeat course") has more than two or incomplete attempts; verify manually.")
                continue
            }

            let first = attempts[0]
            let latest = attempts[1]
            if attempts.contains(where: { $0.grade.gradePointValue == nil }) || first.units != latest.units {
                manual.insert(groupID)
                warnings.append("\(first.courseCode) has non-letter grades or mismatched units; verify manually.")
                continue
            }

            if attempts.contains(where: { $0.repeatHandlingMode == .includeBoth }) {
                continue
            }
            if attempts.contains(where: { $0.repeatHandlingMode == .manualReview }) {
                manual.insert(groupID)
                warnings.append("\(first.courseCode) is marked for manual repeat review.")
                continue
            }

            if used + latest.units <= replacementLimit {
                included.remove(first.id)
                excluded.insert(first.id)
                included.insert(latest.id)
                used += latest.units
            } else {
                afterLimit.formUnion([first.id, latest.id])
                warnings.append("\(first.courseCode) exceeds or partially exceeds the 16-unit replacement limit; both attempts are included in this estimate.")
            }
        }

        return RepeatEvaluation(
            includedIDs: included, excludedIDs: excluded, repeatUnitsUsed: used,
            repeatUnitsRemaining: max(0, replacementLimit - used),
            includedAfterLimit: afterLimit, manualReviewGroupIDs: manual, warnings: warnings
        )
    }
}
