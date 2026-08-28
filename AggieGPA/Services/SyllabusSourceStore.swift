import Foundation

/// The confirmed syllabus source is kept as a small, app-private file keyed
/// by the grading-policy ID. Keeping the source outside the SwiftData schema
/// lets existing stores migrate without changing or re-writing grade records,
/// while still retaining page boundaries for course-scoped questions after the
/// import sheet has been dismissed.
enum SyllabusSourceStore {
    struct StoredSource: Codable, Equatable, Sendable {
        let policyID: UUID
        let sourceText: String?
        let pagesData: Data?
        let sourceRawValue: String
        let updatedAt: Date

        var source: SyllabusImportSource {
            SyllabusImportSource(rawValue: sourceRawValue) ?? .pastedText
        }
    }

    private static let lock = NSLock()

    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AggieGPA", isDirectory: true)
        return support.appendingPathComponent("SyllabusSources.json", isDirectory: false)
    }

    static func source(for policyID: UUID) -> StoredSource? {
        withLock {
            readAll()[policyID.uuidString]
        }
    }

    static func save(document: SyllabusTextExtractor.Document, for policyID: UUID) {
        let sourceText = SyllabusTextExtractor.storedText(from: document)
        let pagesData = SyllabusTextExtractor.storedPageData(from: document)
        guard sourceText != nil || pagesData != nil else { return }
        let stored = StoredSource(
            policyID: policyID,
            sourceText: sourceText,
            pagesData: pagesData,
            sourceRawValue: document.source.rawValue,
            updatedAt: .now
        )
        withLock {
            var all = readAll()
            all[policyID.uuidString] = stored
            writeAll(all)
        }
    }

    static func save(sourceText: String?, pagesData: Data?, source: SyllabusImportSource, for policyID: UUID) {
        guard sourceText != nil || pagesData != nil else { return }
        let stored = StoredSource(
            policyID: policyID,
            sourceText: sourceText,
            pagesData: pagesData,
            sourceRawValue: source.rawValue,
            updatedAt: .now
        )
        withLock {
            var all = readAll()
            all[policyID.uuidString] = stored
            writeAll(all)
        }
    }

    static func remove(policyID: UUID) {
        withLock {
            var all = readAll()
            all.removeValue(forKey: policyID.uuidString)
            writeAll(all)
        }
    }

    static func removeAll() {
        withLock {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func readAll() -> [String: StoredSource] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: StoredSource].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func writeAll(_ values: [String: StoredSource]) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(values)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // A missing source file is a safe fallback: the course still
            // retains its grading policy and the UI offers Import Syllabus.
        }
    }
}
