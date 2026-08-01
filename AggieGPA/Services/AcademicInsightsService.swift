import Foundation
import CryptoKit
import SwiftData

enum AcademicInsightSeverity: Int, CaseIterable, Sendable {
    case positive
    case informative
    case attention
    case urgent
}

struct AcademicInsight: Identifiable, Equatable, Sendable {
    let id: UUID
    let courseID: UUID
    let itemID: UUID?
    let severity: AcademicInsightSeverity
    let symbolName: String
    let title: String
    let detail: String
    let calculationBasis: String
}

@MainActor
enum AcademicInsightsService {
    static func makeInsights(
        courses: [CourseRecord], policies: [CourseGradingPolicy],
        categories: [GradingCategory], items: [GradeItem], scales: [GradeScale],
        forecasts: [ForecastScenario], locale: Locale, now: Date = .now
    ) -> [AcademicInsight] {
        courses.filter { !$0.isDeleted }.flatMap { course in
            makeInsights(
                course: course,
                policy: policies.first { $0.course?.id == course.id && !$0.isDeleted },
                categories: categories.filter { $0.course?.id == course.id && !$0.isDeleted },
                items: items.filter { $0.course?.id == course.id && !$0.isDeleted },
                scale: scales.first { $0.course?.id == course.id && !$0.isDeleted },
                forecast: forecasts.first { $0.course?.id == course.id && $0.isSelectedForGPAForecast && !$0.isDeleted },
                locale: locale, now: now
            )
        }
    }

    static func makeInsights(
        course: CourseRecord, policy: CourseGradingPolicy?, categories: [GradingCategory],
        items: [GradeItem], scale: GradeScale?, forecast: ForecastScenario?,
        locale: Locale, now: Date = .now
    ) -> [AcademicInsight] {
        let input = CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policy, categories: categories, items: items,
            gradeScale: scale, forecast: forecast
        )
        let result = CourseGradeCalculationEngine.calculate(input)
        var insights: [AcademicInsight] = []
        let titlePrefix = course.courseCode

        if policy == nil {
            insights.append(insight(
                course: course, severity: .attention, symbol: "slider.horizontal.3",
                title: localized("Grading method is not set", locale),
                detail: localized("Choose a grading method before relying on course calculations.", locale),
                basis: localized("No course grading policy is saved.", locale)
            ))
        }

        if let issue = result.issues.first(where: { issue in
            switch issue { case .weightTotalBelow100, .weightTotalAbove100: true; default: false }
        }) {
            switch issue {
            case .weightTotalBelow100(let total):
                insights.append(insight(
                    course: course, severity: .attention, symbol: "chart.pie",
                    title: localized("Course weights need review", locale),
                    detail: format("Category weights total %@, below 100%%.", locale, percent(total)),
                    basis: format("The calculation engine requires category weights to total 100%%; current total: %@.", locale, percent(total))
                ))
            case .weightTotalAbove100(let total):
                insights.append(insight(
                    course: course, severity: .attention, symbol: "chart.pie",
                    title: localized("Course weights need review", locale),
                    detail: format("Category weights total %@, above 100%%.", locale, percent(total)),
                    basis: format("The calculation engine requires category weights to total 100%%; current total: %@.", locale, percent(total))
                ))
            default: break
            }
        }

        guard !items.isEmpty else {
            insights.append(insight(
                course: course, severity: .informative, symbol: "tray",
                title: localized("Not enough graded work yet", locale),
                detail: localized("Add assignments or exams and record scores before academic insights can compare performance.", locale),
                basis: localized("This course has no assignment or exam records.", locale)
            ))
            return insights
        }

        if scale == nil || scale?.isLetterPredictionEnabled == false {
            insights.append(insight(
                course: course, severity: .informative, symbol: "textformat.123",
                title: localized("Grade scale is incomplete", locale),
                detail: localized("A percentage can still be calculated, but letter-target guidance needs a confirmed grade scale.", locale),
                basis: localized("The course has no enabled confirmed grade scale.", locale)
            ))
        }

        for breakdown in result.categoryBreakdown {
            guard let average = breakdown.average, let target = targetPercentage(policy) else { continue }
            guard average + 10 < target else { continue }
            insights.append(insight(
                course: course, severity: .attention, symbol: "arrow.down.right",
                title: format("%@ is below the course target", locale, breakdown.name),
                detail: format("%@ is at %@, more than 10 points below the %@ target.", locale, breakdown.name, percent(average), percent(target)),
                basis: format("Category average %@ compared with target %@; based on %@ graded item(s).", locale, percent(average), percent(target), "\(breakdown.gradedItems)")
            ))
        }

        let overdue = items.filter { item in
            guard let due = item.dueDate, due < now, !hasRecordedScore(item) else { return false }
            return item.status != .excused && item.status != .dropped && !item.isExcused && !item.isDropped
        }.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        for item in overdue.prefix(2) {
            insights.append(insight(
                course: course, item: item, severity: .urgent, symbol: "clock.badge.exclamationmark",
                title: format("%@ is overdue", locale, item.title),
                detail: format("%@ has no recorded score and its due date has passed.", locale, item.title),
                basis: format("Due %@; earned points are empty.", locale, item.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            ))
        }

        let missing = items.filter { $0.status == .missing && !$0.isExcused && !$0.isDropped }
        if let item = missing.first {
            insights.append(insight(
                course: course, item: item, severity: .urgent, symbol: "exclamationmark.triangle",
                title: format("%@ is marked missing", locale, item.title),
                detail: localized("Review the item status or record a score if the work was completed.", locale),
                basis: localized("The saved grade-item status is Missing.", locale)
            ))
        }

        let upcoming = items.filter { item in
            guard let due = item.dueDate, !hasRecordedScore(item) else { return false }
            guard due >= now else { return false }
            let limit = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: now) ?? now
            return due <= limit && !item.isExcused && !item.isDropped
        }.sorted { itemImpact($0, categories: categories, items: items) > itemImpact($1, categories: categories, items: items) }
        if let item = upcoming.first {
            let impact = itemImpact(item, categories: categories, items: items)
            insights.append(insight(
                course: course, item: item, severity: impact >= 8 ? .attention : .informative,
                symbol: "calendar.badge.clock",
                title: format("%@ is due soon", locale, item.title),
                detail: format("This item is due within 7 days and can affect about %@ of the calculated course result.", locale, percent(impact)),
                basis: format("Estimated influence: category weight and item points produce about %@ of course weight.", locale, percent(impact))
            ))
        }

        let highImpactCandidates = items.filter { item in
            !item.isDropped && !item.isExcused && item.possiblePoints > 0
        }
        if let highImpactItem = highImpactCandidates.max(by: { lhs, rhs in
            itemImpact(lhs, categories: categories, items: items)
                < itemImpact(rhs, categories: categories, items: items)
        }) {
            let impact = itemImpact(highImpactItem, categories: categories, items: items)
            if impact > 0 {
                insights.append(insight(
                    course: course, item: highImpactItem, severity: .informative,
                    symbol: "scalemass",
                    title: format("%@ has a high course impact", locale, highImpactItem.title),
                    detail: format("This single item contributes about %@ of the calculated course result when it is included.", locale, percent(impact)),
                    basis: format("Category weight and this item's possible points produce an estimated course influence of %@.", locale, percent(impact))
                ))
            }
        }

        if let required = requiredAverage(result: result, policy: policy) {
            let severity: AcademicInsightSeverity = required <= 100 ? .informative : .attention
            insights.append(insight(
                course: course, severity: severity, symbol: "target",
                title: required <= 100 ? localized("Your target remains reachable", locale) : localized("Your target is not mathematically reachable", locale),
                detail: format("The remaining work needs an average of %@.", locale, percent(required)),
                basis: format("Current earned course credit: %@; remaining weight: %@.", locale, percent(result.earnedCourseCredit), percent(result.remainingWeight))
            ))
        } else if let target = targetPercentage(policy), result.targetFeasibility == .alreadyReached {
            insights.append(insight(
                course: course, severity: .positive, symbol: "checkmark.circle",
                title: localized("Your target has been reached", locale),
                detail: format("The calculated current result is already at or above %@.", locale, percent(target)),
                basis: format("Current calculated percentage: %@.", locale, percent(result.calculatedCurrentPercentage))
            ))
        }

        for category in categories {
            let graded = items.filter { $0.category?.id == category.id && $0.earnedPoints != nil && !$0.isDropped && !$0.isExcused }
                .sorted { ($0.dueDate ?? $0.updatedAt) < ($1.dueDate ?? $1.updatedAt) }
            let percentages = Array(graded.compactMap(scorePercentage).suffix(3))
            guard percentages.count == 3,
                  percentages[0] > percentages[1], percentages[1] > percentages[2] else { continue }
            insights.append(insight(
                course: course, severity: .attention, symbol: "chart.line.downtrend.xyaxis",
                title: format("Recent %@ scores are trending down", locale, category.name),
                detail: format("The last three recorded scores moved from %@ to %@ to %@.", locale, percent(percentages[0]), percent(percentages[1]), percent(percentages[2])),
                basis: localized("The comparison uses the three most recent scored items in this category.", locale)
            ))
        }

        if insights.isEmpty {
            insights.append(insight(
                course: course, severity: .positive, symbol: "checkmark.seal",
                title: format("%@ has no urgent academic alerts", locale, titlePrefix),
                detail: localized("Keep recording actual scores and review the calculation when new work is added.", locale),
                basis: localized("No deterministic rule produced an alert from the saved course data.", locale)
            ))
        }
        return insights
    }

    private static func insight(
        course: CourseRecord, item: GradeItem? = nil, severity: AcademicInsightSeverity,
        symbol: String, title: String, detail: String, basis: String
    ) -> AcademicInsight {
        // Insight values are recomputed from SwiftData on every view update. A random
        // identifier makes SwiftUI treat the same row as a new destination, which can
        // reset NavigationLink state and produce the apparent See All loop. Derive the
        // identity from the saved course/item and the deterministic rule instead.
        let identitySource = [
            course.id.uuidString,
            item?.id.uuidString ?? "course",
            symbol,
            title
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(identitySource.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let stableUUID = UUID(uuidString: "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))")!
        return AcademicInsight(id: stableUUID, courseID: course.id, itemID: item?.id, severity: severity,
                        symbolName: symbol, title: title, detail: detail, calculationBasis: basis)
    }

    private static func targetPercentage(_ policy: CourseGradingPolicy?) -> Decimal? {
        if let percentage = policy?.targetPercentage { return percentage }
        guard let letter = policy?.targetLetterGrade else { return nil }
        switch letter {
        case .aPlus: return 97
        case .a: return 93
        case .aMinus: return 90
        case .bPlus: return 87
        case .b: return 83
        case .bMinus: return 80
        case .cPlus: return 77
        case .c: return 73
        case .cMinus: return 70
        case .dPlus: return 67
        case .d: return 63
        case .dMinus: return 60
        case .f: return 0
        }
    }

    private static func requiredAverage(result: CourseGradeCalculationResult, policy: CourseGradingPolicy?) -> Decimal? {
        guard let target = targetPercentage(policy), result.targetFeasibility != .alreadyReached,
              !result.requiresManualReview, result.remainingWeight > 0 else { return nil }
        return max(0, (target - result.earnedCourseCredit) / result.remainingWeight * 100)
    }

    private static func itemImpact(_ item: GradeItem, categories: [GradingCategory], items: [GradeItem]) -> Decimal {
        let related = categories.first { $0.id == item.category?.id }
        let categoryItems = items.filter { $0.category?.id == related?.id && !$0.isDropped && !$0.isExcused }
        guard let category = related else { return 0 }
        if let override = item.percentageOverride { return category.weight * override / 100 }
        let total = categoryItems.reduce(Decimal.zero) { $0 + $1.possiblePoints }
        guard total > 0 else { return 0 }
        return category.weight * item.possiblePoints / total
    }

    private static func scorePercentage(_ item: GradeItem) -> Decimal? {
        if let override = item.percentageOverride { return override }
        guard let earned = item.earnedPoints, item.possiblePoints > 0 else { return nil }
        return earned / item.possiblePoints * 100
    }

    private static func hasRecordedScore(_ item: GradeItem) -> Bool {
        item.earnedPoints != nil || item.percentageOverride != nil || item.status == .graded
    }

    private static func localized(_ key: String, _ locale: Locale) -> String {
        AppLocalization.string(key, locale: locale)
    }

    private static func format(_ key: String, _ locale: Locale, _ values: CVarArg...) -> String {
        String(format: AppLocalization.string(key, locale: locale), arguments: values)
    }

    private static func percent(_ value: Decimal?) -> String {
        value.map { "\(DecimalFormatters.compact($0))%" } ?? "—"
    }
}
