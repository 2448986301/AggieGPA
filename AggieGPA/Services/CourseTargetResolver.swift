import Foundation

/// Resolves the single deterministic course target used by grade calculations.
/// An explicitly entered percentage always wins. Letter targets are interpreted
/// through the course's own scale instead of a global hard-coded threshold.
nonisolated enum CourseTargetResolver {
    static func percentage(
        explicitPercentage: Decimal?,
        targetLetterGrade: GradeLetter?,
        gradeScale: CourseGradeScaleInput?
    ) -> Decimal? {
        if let explicitPercentage { return explicitPercentage }
        guard let targetLetterGrade,
              let gradeScale,
              gradeScale.isEnabled else { return nil }
        return gradeScale.boundaries
            .filter { $0.letter == targetLetterGrade }
            .map(\.minimumPercentage)
            .max()
    }
}
