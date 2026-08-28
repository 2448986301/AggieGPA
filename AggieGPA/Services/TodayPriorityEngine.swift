import Foundation

/// A read-only representation of a grade item used to decide what deserves
/// attention on Today. Keeping the engine on snapshots prevents SwiftData
/// objects from becoming hidden mutable inputs to a ranking decision.
nonisolated struct TodayTaskSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let courseID: UUID
    let courseCode: String
    let title: String
    let dueDate: Date?
    let categoryName: String?
    let categoryType: GradeCategoryType?
    let categoryCalculationMode: CategoryCalculationMode?
    let categoryItemCount: Int
    let courseImpact: Decimal
    let status: GradeItemStatus
    let hasRecordedScore: Bool
    let reminderEnabled: Bool
    let isIncluded: Bool
    let isDropped: Bool
    let isExcused: Bool

    var isCompleted: Bool {
        hasRecordedScore || status == .graded || status == .submitted
    }

    var isActive: Bool {
        isIncluded && !isDropped && !isExcused
            && status != .dropped && status != .excused && status != .notCounted
    }

    init(
        id: UUID,
        courseID: UUID,
        courseCode: String,
        title: String,
        dueDate: Date?,
        categoryName: String?,
        categoryType: GradeCategoryType?,
        categoryCalculationMode: CategoryCalculationMode? = nil,
        categoryItemCount: Int = 0,
        courseImpact: Decimal,
        status: GradeItemStatus,
        hasRecordedScore: Bool = false,
        reminderEnabled: Bool = false,
        isIncluded: Bool = true,
        isDropped: Bool = false,
        isExcused: Bool = false
    ) {
        self.id = id
        self.courseID = courseID
        self.courseCode = courseCode
        self.title = title
        self.dueDate = dueDate
        self.categoryName = categoryName
        self.categoryType = categoryType
        self.categoryCalculationMode = categoryCalculationMode
        self.categoryItemCount = max(0, categoryItemCount)
        self.courseImpact = max(0, courseImpact)
        self.status = status
        self.hasRecordedScore = hasRecordedScore
        self.reminderEnabled = reminderEnabled
        self.isIncluded = isIncluded
        self.isDropped = isDropped
        self.isExcused = isExcused
    }
}

nonisolated struct TodayCourseAlertSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let courseCode: String
    let reason: TodayCourseAlertReason

    init(id: UUID, courseCode: String, reason: TodayCourseAlertReason) {
        self.id = id
        self.courseCode = courseCode
        self.reason = reason
    }
}

nonisolated enum TodayCourseAlertReason: String, Codable, Equatable, Sendable {
    case gradingPolicyReview
    case gradeScaleReview
}

nonisolated enum TodayAttentionReason: String, Codable, Equatable, Sendable {
    case overdue
    case missing
    case dueToday
    case gradingPolicyReview
    case gradeScaleReview
}

nonisolated struct TodayAttention: Equatable, Identifiable, Sendable {
    let id: UUID
    let courseID: UUID
    let courseCode: String
    let item: TodayTaskSnapshot?
    let reason: TodayAttentionReason

    init(
        id: UUID,
        courseID: UUID,
        courseCode: String,
        item: TodayTaskSnapshot? = nil,
        reason: TodayAttentionReason
    ) {
        self.id = id
        self.courseID = courseID
        self.courseCode = courseCode
        self.item = item
        self.reason = reason
    }
}

nonisolated struct TodayPriorityPlan: Equatable, Sendable {
    let next: TodayTaskSnapshot?
    let dueToday: [TodayTaskSnapshot]
    let highImpact: [TodayTaskSnapshot]
    let needsAttention: [TodayAttention]
    let timeline: [TodayTaskSnapshot]

    static let empty = TodayPriorityPlan(
        next: nil,
        dueToday: [],
        highImpact: [],
        needsAttention: [],
        timeline: []
    )
}

/// Deterministic Today ranking. It is intentionally independent from SwiftData
/// and localization: the view can explain the selected facts in the user's
/// language without allowing copy or AI to decide priority.
nonisolated enum TodayPriorityEngine {
    static func makePlan(
        items: [TodayTaskSnapshot],
        courseAlerts: [TodayCourseAlertSnapshot] = [],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        highImpactLimit: Int = 3,
        attentionLimit: Int = 5
    ) -> TodayPriorityPlan {
        let active = items.filter { $0.isActive }
        let pending = active.filter { !$0.isCompleted }
        let timeline = active
            // Keep unscored submitted/graded work in the academic timeline so a
            // completed deadline still provides semester context, but never
            // surface an item that already has an official score as upcoming.
            .filter { $0.dueDate != nil && !$0.hasRecordedScore }
            .sorted { timelineSort($0, $1) }

        let dueToday = pending
            .filter { item in
                guard let dueDate = item.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: now)
            }
            .sorted { prioritySort($0, $1, now: now, calendar: calendar) }

        let next = pending
            .sorted { prioritySort($0, $1, now: now, calendar: calendar) }
            .first

        let highImpact = pending
            .filter { $0.courseImpact > 0 }
            .sorted {
                if $0.courseImpact != $1.courseImpact {
                    return $0.courseImpact > $1.courseImpact
                }
                return prioritySort($0, $1, now: now, calendar: calendar)
            }
            .prefix(max(0, highImpactLimit))

        let itemAlerts = pending
            .compactMap { item -> TodayAttention? in
                guard let dueDate = item.dueDate else {
                    return item.status == .missing
                        ? TodayAttention(
                            id: item.id,
                            courseID: item.courseID,
                            courseCode: item.courseCode,
                            item: item,
                            reason: .missing
                        )
                        : nil
                }
                if item.status == .missing {
                    return TodayAttention(
                        id: item.id,
                        courseID: item.courseID,
                        courseCode: item.courseCode,
                        item: item,
                        reason: .missing
                    )
                }
                if dueDate < now {
                    return TodayAttention(
                        id: item.id,
                        courseID: item.courseID,
                        courseCode: item.courseCode,
                        item: item,
                        reason: .overdue
                    )
                }
                return nil
            }
            .sorted { attentionSort($0, $1) }

        let courseAlerts = courseAlerts
            .map {
                TodayAttention(
                    id: $0.id,
                    courseID: $0.id,
                    courseCode: $0.courseCode,
                    reason: $0.reason == .gradingPolicyReview
                        ? .gradingPolicyReview
                        : .gradeScaleReview
                )
            }

        let attention = (itemAlerts + courseAlerts)
            .sorted { attentionSort($0, $1) }
            .prefix(max(0, attentionLimit))

        return TodayPriorityPlan(
            next: next,
            dueToday: dueToday,
            highImpact: Array(highImpact),
            needsAttention: Array(attention),
            timeline: timeline
        )
    }

    /// Computes the share of a weighted category that one points-based item
    /// can influence. This is a prioritization signal, not a grade calculation.
    static func courseImpact(
        categoryWeight: Decimal,
        itemPossiblePoints: Decimal,
        categoryPossiblePoints: Decimal,
        percentageOverride: Decimal? = nil,
        calculationMode: CategoryCalculationMode? = nil,
        categoryItemCount: Int = 0
    ) -> Decimal {
        guard categoryWeight > 0 else { return 0 }
        if let percentageOverride {
            return max(0, categoryWeight * percentageOverride / 100)
        }
        if calculationMode == .equalItems, categoryItemCount > 0 {
            return categoryWeight / Decimal(categoryItemCount)
        }
        guard itemPossiblePoints > 0, categoryPossiblePoints > 0 else { return 0 }
        return max(0, categoryWeight * itemPossiblePoints / categoryPossiblePoints)
    }

    private static func prioritySort(
        _ lhs: TodayTaskSnapshot,
        _ rhs: TodayTaskSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let leftScore = priorityScore(lhs, now: now, calendar: calendar)
        let rightScore = priorityScore(rhs, now: now, calendar: calendar)
        if leftScore != rightScore { return leftScore > rightScore }
        if lhs.dueDate != rhs.dueDate { return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture) }
        if lhs.courseCode != rhs.courseCode {
            return lhs.courseCode.localizedStandardCompare(rhs.courseCode) == .orderedAscending
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func priorityScore(
        _ item: TodayTaskSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Decimal {
        var score = item.courseImpact * 100
        if let dueDate = item.dueDate {
            if dueDate < now {
                score += 10_000
            } else if calendar.isDate(dueDate, inSameDayAs: now) {
                score += 7_000
            } else {
                let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)).day ?? Int.max
                if day <= 3 { score += 5_000 }
                else if day <= 7 { score += 3_000 }
                else if day <= 14 { score += 1_000 }
            }
        }
        // Category type is explanatory metadata, not a hidden tie breaker.
        // When two items have the same due urgency and course impact, the
        // stable course/title ordering below must decide the result.
        if item.status == .missing { score += 1_500 }
        return score
    }

    private static func timelineSort(_ lhs: TodayTaskSnapshot, _ rhs: TodayTaskSnapshot) -> Bool {
        if lhs.dueDate != rhs.dueDate { return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture) }
        if lhs.courseCode != rhs.courseCode {
            return lhs.courseCode.localizedStandardCompare(rhs.courseCode) == .orderedAscending
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func attentionSort(_ lhs: TodayAttention, _ rhs: TodayAttention) -> Bool {
        let left = attentionScore(lhs)
        let right = attentionScore(rhs)
        if left != right { return left > right }
        if lhs.courseCode != rhs.courseCode {
            return lhs.courseCode.localizedStandardCompare(rhs.courseCode) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func attentionScore(_ attention: TodayAttention) -> Decimal {
        switch attention.reason {
        case .overdue: return 10_000
        case .missing: return 9_000
        case .dueToday: return 8_000
        case .gradingPolicyReview: return 7_000
        case .gradeScaleReview: return 6_000
        }
    }
}
