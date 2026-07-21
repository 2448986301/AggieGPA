import Foundation
import SwiftData

@MainActor
enum SnapshotService {
    static let maximumSnapshots = 5

    static func create(envelope: BackupEnvelope, reason: String, context: ModelContext,
                       existing: [BackupSnapshot]) throws {
        let manager = FileManager.default
        guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw BackupError.fileAccess
        }
        let directory = support.appending(path: "AggieGPA/Snapshots", directoryHint: .isDirectory)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let fileName = "snapshot-\(formatter.string(from: .now).replacingOccurrences(of: ":", with: "-"))-.json"
        let data = try BackupService.encode(envelope)
        try data.write(to: directory.appending(path: fileName), options: .atomic)
        let newSnapshot = BackupSnapshot(fileName: fileName, reason: reason, byteCount: data.count)
        context.insert(newSnapshot)
        try context.save()

        let all = (existing + [newSnapshot])
            .sorted { $0.createdAt > $1.createdAt }
        for snapshot in all.dropFirst(maximumSnapshots) {
            try? manager.removeItem(at: directory.appending(path: snapshot.fileName))
            context.delete(snapshot)
        }
        try context.save()
    }
}
