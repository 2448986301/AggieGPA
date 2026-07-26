import Foundation

/// Course aliases are intentionally stored separately from private course notes.
/// They are limited to short, user-selected names suitable for Siri and Spotlight.
nonisolated enum SiriAliasStore {
    private static let prefix = "siriCourseAliases."

    static func aliases(for courseID: UUID) -> [String] {
        (UserDefaults.standard.stringArray(forKey: prefix + courseID.uuidString) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func save(_ rawValue: String, for courseID: UUID) {
        let aliases = rawValue
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        UserDefaults.standard.set(Array(Set(aliases)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, forKey: prefix + courseID.uuidString)
    }
}
