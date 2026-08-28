import Foundation
import SwiftData

/// A small, local-only read snapshot for App Intents.
/// It prevents Siri's out-of-process host from contending with the live SwiftData store.
nonisolated enum SiriSharedSnapshotStore {
    private static let appGroupIdentifier = "group.com.easonzhou.aggiegpa"
    private static let key = "siriSharedSnapshot.v1"

    nonisolated struct Assignment: Codable, Sendable {
        let id: String
        let courseID: String
        let courseCode: String
        let title: String
        let dueDate: Date?
        let category: String
        let status: String
    }

    nonisolated struct Exam: Codable, Sendable {
        let id: String
        let courseID: String
        let courseCode: String
        let title: String
        let dueDate: Date?
        let examType: String
        let status: String
    }

    nonisolated struct Course: Codable, Sendable {
        let id: String
        let code: String
        let title: String
        let termName: String
        let aliases: [String]
    }

    nonisolated struct Snapshot: Codable, Sendable {
        let isEnabled: Bool
        let allowsAssignmentSummaries: Bool
        let courses: [Course]
        let assignments: [Assignment]
        let exams: [Exam]

        init(
            isEnabled: Bool,
            allowsAssignmentSummaries: Bool,
            courses: [Course],
            assignments: [Assignment],
            exams: [Exam] = []
        ) {
            self.isEnabled = isEnabled
            self.allowsAssignmentSummaries = allowsAssignmentSummaries
            self.courses = courses
            self.assignments = assignments
            self.exams = exams
        }

        private enum CodingKeys: String, CodingKey {
            case isEnabled, allowsAssignmentSummaries, courses, assignments, exams
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
            allowsAssignmentSummaries = try values.decode(Bool.self, forKey: .allowsAssignmentSummaries)
            courses = try values.decode([Course].self, forKey: .courses)
            assignments = try values.decode([Assignment].self, forKey: .assignments)
            // v1 snapshots written before exam support remain readable.
            exams = try values.decodeIfPresent([Exam].self, forKey: .exams) ?? []
        }
    }

    static func save(courses: [CourseRecord], gradeItems: [GradeItem], settings: SiriAccessSettings?) {
        let isEnabled = settings?.isSiriAccessEnabled == true
        let allowsAssignmentSummaries = isEnabled && settings?.allowAssignmentSummaries == true
        let validCourses = Set(courses.filter { !$0.isDeleted }.map(\.id))
        let courseSnapshots = isEnabled ? courses.filter { !$0.isDeleted }.map { course in
            Course(id: course.id.uuidString, code: course.courseCode, title: course.courseTitle,
                   termName: course.term?.displayName ?? "No term", aliases: SiriAliasStore.aliases(for: course.id))
        } : []
        let eligibleItems = allowsAssignmentSummaries ? gradeItems.filter { item in
            guard let course = item.course else { return false }
            return validCourses.contains(course.id) && !item.isExcused && !item.isDropped
        } : []
        let assignments = eligibleItems.compactMap { item -> Assignment? in
            guard let course = item.course,
                  item.category?.categoryType != .midterm,
                  item.category?.categoryType != .finalExam else { return nil }
            return Assignment(id: item.id.uuidString, courseID: course.id.uuidString, courseCode: course.courseCode,
                              title: item.title, dueDate: item.dueDate, category: item.category?.name ?? "Assignment", status: item.status.rawValue)
        }
        let exams = eligibleItems.compactMap { item -> Exam? in
            guard let course = item.course,
                  item.category?.categoryType == .midterm || item.category?.categoryType == .finalExam else { return nil }
            return Exam(id: item.id.uuidString, courseID: course.id.uuidString, courseCode: course.courseCode,
                        title: item.title, dueDate: item.dueDate, examType: item.category?.name ?? "Exam", status: item.status.rawValue)
        }
        let snapshot = Snapshot(isEnabled: isEnabled,
                                allowsAssignmentSummaries: allowsAssignmentSummaries,
                                courses: courseSnapshots,
                                assignments: assignments,
                                exams: exams)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    static func courses(ids: [String]? = nil, matching query: String? = nil) -> [CourseEntity]? {
        guard let snapshot = load(),
              snapshot.isEnabled else { return nil }
        let normalized = query.map(AppIntentDataService.normalizeCourseCode)
        return snapshot.courses.compactMap { course -> CourseEntity? in
            if let ids, !ids.contains(course.id) { return nil }
            if let query, !query.isEmpty {
                let codeMatches = AppIntentDataService.normalizeCourseCode(course.code) == normalized
                let textMatches = course.code.localizedCaseInsensitiveContains(query)
                    || course.title.localizedCaseInsensitiveContains(query)
                    || course.aliases.contains { alias in
                        alias.localizedCaseInsensitiveCompare(query) == .orderedSame
                            || alias.localizedCaseInsensitiveContains(query)
                            || query.localizedCaseInsensitiveContains(alias)
                    }
                guard codeMatches || textMatches else { return nil }
            }
            return CourseEntity(id: course.id, code: course.code, title: course.title, termName: course.termName, aliases: course.aliases)
        }
    }

    static func upcomingAssignments(days: Int, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> [AssignmentEntity]? {
        guard let snapshot = load() else { return nil }
        return upcomingAssignments(in: snapshot, days: days, now: now, calendar: calendar)
    }

    static func upcomingExams(days: Int, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> [ExamEntity]? {
        guard let snapshot = load() else { return nil }
        return upcomingExams(in: snapshot, days: days, now: now, calendar: calendar)
    }

    static func upcomingAssignments(in snapshot: Snapshot, days: Int, now: Date, calendar: Calendar) -> [AssignmentEntity]? {
        guard snapshot.isEnabled,
              snapshot.allowsAssignmentSummaries else { return nil }
        guard let range = upcomingRange(days: days, now: now, calendar: calendar) else { return [] }
        return snapshot.assignments.compactMap { item in
            guard let dueDate = item.dueDate, range.contains(dueDate) else { return nil }
            return AssignmentEntity(id: item.id, courseID: item.courseID, courseCode: item.courseCode, title: item.title,
                                    dueDate: dueDate, category: item.category, status: item.status)
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    static func upcomingExams(in snapshot: Snapshot, days: Int, now: Date, calendar: Calendar) -> [ExamEntity]? {
        guard snapshot.isEnabled,
              snapshot.allowsAssignmentSummaries else { return nil }
        guard let range = upcomingRange(days: days, now: now, calendar: calendar) else { return [] }
        return snapshot.exams.compactMap { item in
            guard let dueDate = item.dueDate, range.contains(dueDate) else { return nil }
            return ExamEntity(id: item.id, courseID: item.courseID, courseCode: item.courseCode, title: item.title,
                              dueDate: dueDate, examType: item.examType, status: item.status)
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private static func load() -> Snapshot? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static func upcomingRange(days: Int, now: Date, calendar: Calendar) -> Range<Date>? {
        guard days > 0 else { return nil }
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
        return start..<end
    }
}

/// A privacy-safe, local execution breadcrumb used by the in-app Siri diagnostics.
/// It records only execution stages and item counts, never course names or grades.
nonisolated enum SiriExecutionTrace {
    private static let appGroupIdentifier = "group.com.easonzhou.aggiegpa"
    private static let key = "siriExecutionTrace.v1"
    private static let historyKey = "siriExecutionTraceHistory.v1"
    private static let maximumEntryCount = 24

    nonisolated struct Entry: Codable, Sendable {
        let stage: String
        let itemCount: Int?
        let timestamp: Date
    }

    static func record(_ stage: String, itemCount: Int? = nil) {
        let entry = Entry(stage: stage, itemCount: itemCount, timestamp: .now)
        guard let data = try? JSONEncoder().encode(entry),
              let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(data, forKey: key)
        var entries = history(defaults: defaults)
        entries.append(entry)
        if entries.count > maximumEntryCount {
            entries.removeFirst(entries.count - maximumEntryCount)
        }
        defaults.set(try? JSONEncoder().encode(entries), forKey: historyKey)
        defaults.synchronize()
    }

    static func latest() -> Entry? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    static func latestIntentExecution() -> Entry? {
        history().last { !$0.stage.hasPrefix("spotlight-index") }
    }

    static func history() -> [Entry] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return [] }
        return history(defaults: defaults)
    }

    private static func history(defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: historyKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }
}
