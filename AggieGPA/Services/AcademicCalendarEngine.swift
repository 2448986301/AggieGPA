import Foundation

/// A read-only deadline used by the academic-load calendar.
///
/// The calendar deliberately consumes snapshots rather than SwiftData models. This keeps
/// density and sorting deterministic, makes the visual layer cheap to refresh, and avoids
/// allowing a calendar tap to mutate an official grade record.
nonisolated struct AcademicCalendarItemSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let courseID: UUID
    let courseCode: String
    let courseTitle: String
    let title: String
    let dueDate: Date
    let categoryName: String
    let categoryType: GradeCategoryType
    let assessmentWeight: Decimal
    let possiblePoints: Decimal
    let status: GradeItemStatus
    let isCompleted: Bool
    let courseColorIndex: Int

    var isExam: Bool {
        categoryType == .midterm || categoryType == .finalExam
    }

    var isActive: Bool {
        status != .dropped && status != .excused && status != .notCounted
    }

    init(
        id: UUID,
        courseID: UUID,
        courseCode: String,
        courseTitle: String,
        title: String,
        dueDate: Date,
        categoryName: String,
        categoryType: GradeCategoryType,
        assessmentWeight: Decimal,
        possiblePoints: Decimal,
        status: GradeItemStatus,
        isCompleted: Bool,
        courseColorIndex: Int
    ) {
        self.id = id
        self.courseID = courseID
        self.courseCode = courseCode
        self.courseTitle = courseTitle
        self.title = title
        self.dueDate = dueDate
        self.categoryName = categoryName
        self.categoryType = categoryType
        self.assessmentWeight = max(0, assessmentWeight)
        self.possiblePoints = max(0, possiblePoints)
        self.status = status
        self.isCompleted = isCompleted
        self.courseColorIndex = max(0, courseColorIndex)
    }
}

/// Sendable value inputs used to prepare the calendar away from SwiftUI's render pass.
/// SwiftData models stay on the main actor; only these immutable values cross into the
/// preparation task. This keeps a navigation tap responsive even when a store contains
/// a large gradebook.
nonisolated struct AcademicCalendarCourseInput: Equatable, Sendable {
    let id: UUID
    let courseCode: String
    let courseTitle: String
    let courseColorIndex: Int
}

nonisolated struct AcademicCalendarCategoryInput: Equatable, Sendable {
    let id: UUID
    let name: String
    let categoryType: GradeCategoryType
    let weight: Decimal
    let calculationMode: CategoryCalculationMode
}

nonisolated struct AcademicCalendarGradeItemInput: Equatable, Sendable {
    let id: UUID
    let courseID: UUID
    let categoryID: UUID?
    let title: String
    let dueDate: Date?
    let earnedPoints: Decimal?
    let percentageOverride: Decimal?
    let possiblePoints: Decimal
    let multiplier: Decimal
    let status: GradeItemStatus
    let isIncluded: Bool
    let isDropped: Bool
    let isExcused: Bool
    let isDeleted: Bool
    let isExtraCredit: Bool
}

nonisolated enum AcademicLoadLevel: String, CaseIterable, Codable, Sendable {
    case none
    case light
    case moderate
    case heavy
    case peak
}

nonisolated struct AcademicCalendarDaySummary: Equatable, Sendable {
    let date: Date
    let items: [AcademicCalendarItemSnapshot]
    let assessmentWeight: Decimal
    let examCount: Int
    let completedCount: Int

    var itemCount: Int { items.count }
    var loadLevel: AcademicLoadLevel {
        AcademicCalendarEngine.loadLevel(
            itemCount: itemCount,
            examCount: examCount,
            assessmentWeight: assessmentWeight
        )
    }
}

/// Calendar math for the academic-load surface. This is intentionally not an event planner:
/// the unit of meaning is a dated assessment and its influence on a course grade.
nonisolated enum AcademicCalendarEngine {
    /// Builds immutable calendar rows in one pass over category totals. The previous view
    /// implementation filtered the complete item list once per item (O(n²)) while SwiftUI
    /// was rendering the destination, which was visible as a long delay on a device.
    static func makeItemSnapshots(
        courses: [AcademicCalendarCourseInput],
        categories: [AcademicCalendarCategoryInput],
        items: [AcademicCalendarGradeItemInput],
        otherCategoryName: String
    ) -> [AcademicCalendarItemSnapshot] {
        let courseByID = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0) })
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        var categoryPossiblePoints: [UUID: Decimal] = [:]
        var categoryMultiplierTotals: [UUID: Decimal] = [:]
        for item in items where item.isIncluded && !item.isDeleted && !item.isDropped && !item.isExcused
            && item.status != .dropped && item.status != .excused && item.status != .notCounted {
            guard let categoryID = item.categoryID else { continue }
            categoryPossiblePoints[categoryID, default: .zero] += item.possiblePoints
            categoryMultiplierTotals[categoryID, default: .zero] += max(0, item.multiplier)
        }

        return items.compactMap { item in
            guard item.isIncluded,
                  !item.isDeleted,
                  !item.isDropped,
                  !item.isExcused,
                  item.status != .dropped,
                  item.status != .excused,
                  item.status != .notCounted,
                  let dueDate = item.dueDate,
                  let course = courseByID[item.courseID] else { return nil }

            let category = item.categoryID.flatMap { categoryByID[$0] }
            let weight = assessmentWeight(
                categoryWeight: category?.weight ?? 0,
                calculationMode: category?.calculationMode ?? .custom,
                itemPossiblePoints: item.possiblePoints,
                itemMultiplier: item.multiplier,
                categoryPossiblePoints: item.categoryID.flatMap { categoryPossiblePoints[$0] } ?? 0,
                categoryMultiplierTotal: item.categoryID.flatMap { categoryMultiplierTotals[$0] } ?? 0
            )
            let isCompleted = item.earnedPoints != nil
                || item.percentageOverride != nil
                || item.status == .graded
                || item.status == .submitted

            return AcademicCalendarItemSnapshot(
                id: item.id,
                courseID: course.id,
                courseCode: course.courseCode,
                courseTitle: course.courseTitle,
                title: item.title,
                dueDate: dueDate,
                categoryName: category?.name ?? otherCategoryName,
                categoryType: category?.categoryType ?? .custom,
                assessmentWeight: weight,
                possiblePoints: item.possiblePoints,
                status: item.status,
                isCompleted: isCompleted,
                courseColorIndex: course.courseColorIndex
            )
        }
        .sorted(by: sortItems)
    }

    static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(from: calendar.dateComponents([.era, .year, .month], from: day)) ?? day
    }

    static func monthGrid(for month: Date, calendar: Calendar) -> [Date] {
        let start = monthStart(for: month, calendar: calendar)
        guard let interval = calendar.dateInterval(of: .month, for: start) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        guard dayCount > 0 else { return [] }

        // A full week grid keeps weekday columns stable. Five weeks is the minimum; six is
        // used when a month crosses enough week boundaries, including DST transitions.
        let weekCount = max(5, (leadingDays + dayCount + 6) / 7)
        let cellCount = weekCount * 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: interval.start) ?? interval.start
        return (0..<cellCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    static func daySummary(
        for date: Date,
        items: [AcademicCalendarItemSnapshot],
        calendar: Calendar
    ) -> AcademicCalendarDaySummary {
        let active = items
            .filter { $0.isActive && calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted(by: sortItems)
        return AcademicCalendarDaySummary(
            date: calendar.startOfDay(for: date),
            items: active,
            assessmentWeight: active.reduce(Decimal.zero) { $0 + $1.assessmentWeight },
            examCount: active.count(where: \.isExam),
            completedCount: active.count(where: \.isCompleted)
        )
    }

    /// Groups rows by local day once instead of filtering the complete item list for every
    /// month-cell render. The returned order matches the supplied dates, so callers can use
    /// it directly for a calendar grid.
    static func daySummaries(
        for dates: [Date],
        items: [AcademicCalendarItemSnapshot],
        calendar: Calendar
    ) -> [AcademicCalendarDaySummary] {
        var buckets: [Date: [AcademicCalendarItemSnapshot]] = [:]
        for item in items where item.isActive {
            let day = calendar.startOfDay(for: item.dueDate)
            buckets[day, default: []].append(item)
        }
        return dates.map { date in
            let day = calendar.startOfDay(for: date)
            let active = (buckets[day] ?? []).sorted(by: sortItems)
            return AcademicCalendarDaySummary(
                date: day,
                items: active,
                assessmentWeight: active.reduce(Decimal.zero) { $0 + $1.assessmentWeight },
                examCount: active.count(where: \.isExam),
                completedCount: active.count(where: \.isCompleted)
            )
        }
    }

    static func sortItems(
        _ lhs: AcademicCalendarItemSnapshot,
        _ rhs: AcademicCalendarItemSnapshot
    ) -> Bool {
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        if lhs.isExam != rhs.isExam { return lhs.isExam && !rhs.isExam }
        if lhs.courseCode != rhs.courseCode { return lhs.courseCode.localizedStandardCompare(rhs.courseCode) == .orderedAscending }
        if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func loadLevel(
        itemCount: Int,
        examCount: Int,
        assessmentWeight: Decimal
    ) -> AcademicLoadLevel {
        guard itemCount > 0 else { return .none }
        // A pair of assessments totaling exactly 40% is heavy; reserve peak
        // for four or more items, two exams, or weight above that boundary.
        if itemCount >= 4 || examCount >= 2 || assessmentWeight > 40 { return .peak }
        if itemCount >= 3 || examCount >= 1 && itemCount >= 2 || assessmentWeight >= 25 { return .heavy }
        if itemCount >= 2 || assessmentWeight >= 15 { return .moderate }
        return .light
    }

    static func busiestDay(
        in days: [AcademicCalendarDaySummary]
    ) -> AcademicCalendarDaySummary? {
        days
            .filter { !$0.items.isEmpty }
            .max {
                if $0.itemCount != $1.itemCount { return $0.itemCount < $1.itemCount }
                if $0.examCount != $1.examCount { return $0.examCount < $1.examCount }
                if $0.assessmentWeight != $1.assessmentWeight { return $0.assessmentWeight < $1.assessmentWeight }
                return $0.date > $1.date
            }
    }

    /// Calculates the portion of a weighted category represented by one item.
    /// Weighted-category and equal-item policies use the item's multiplier; total-points
    /// policies use possible points. A custom policy has no reliable influence to display.
    static func assessmentWeight(
        categoryWeight: Decimal,
        calculationMode: CategoryCalculationMode,
        itemPossiblePoints: Decimal,
        itemMultiplier: Decimal,
        categoryPossiblePoints: Decimal,
        categoryMultiplierTotal: Decimal
    ) -> Decimal {
        guard categoryWeight > 0, itemMultiplier > 0 else { return 0 }
        switch calculationMode {
        case .equalItems, .weightedCategory:
            guard categoryMultiplierTotal > 0 else { return 0 }
            return categoryWeight * itemMultiplier / categoryMultiplierTotal
        case .totalPoints:
            guard categoryPossiblePoints > 0 else { return 0 }
            return categoryWeight * itemPossiblePoints * itemMultiplier / categoryPossiblePoints
        case .custom:
            return 0
        }
    }

    /// UUID hashing must not use Swift's process-randomized `hashValue`; the palette should
    /// remain visually stable between launches and on another device.
    static func stableColorIndex(seed: UUID, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let hash = seed.uuidString.unicodeScalars.reduce(UInt64(2_166_136_261)) { value, scalar in
            (value ^ UInt64(scalar.value)) &* 16_777_619
        }
        return Int(hash % UInt64(paletteCount))
    }
}
