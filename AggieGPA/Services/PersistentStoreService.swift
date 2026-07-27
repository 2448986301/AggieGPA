import Foundation
import SwiftData

struct StoreBootstrapResult {
    let container: ModelContainer
    let errorMessage: String?
}

@MainActor
enum PersistentStoreService {
    static let configurationName = "AggieGPA"
    nonisolated static let appGroupIdentifier = "group.com.easonzhou.aggiegpa"

    static var v1Schema: Schema { Schema(AggieGPASchemaV1.models) }
    static var v2Schema: Schema { Schema(versionedSchema: AggieGPASchemaV2.self) }

    static func makeContainer(inMemory: Bool) -> StoreBootstrapResult {
        // The Simulator does not always grant the production App Group. In that environment,
        // continue with the existing app-private store instead of presenting a recovery screen.
        // Physical builds still migrate once to, and then use, the shared App Group store.
        if !inMemory, appGroupStoreURL() != nil {
            do {
                try migrateLegacyStoreToAppGroupIfNeeded()
            } catch {
                return StoreBootstrapResult(container: makeRecoveryContainer(), errorMessage: "Aggie GPA could not safely prepare the local Siri data store. Your original data was not deleted or replaced. \(error.localizedDescription)")
            }
        }
        let configuration = makeConfiguration(inMemory: inMemory)

        do {
            if !inMemory {
                try createVerifiedV1RecoveryBackupIfNeeded(storeURL: configuration.url)
            }
            let container = try ModelContainer(
                for: v2Schema,
                migrationPlan: AggieGPAMigrationPlan.self,
                configurations: [configuration]
            )
            return StoreBootstrapResult(container: container, errorMessage: nil)
        } catch {
            let container = makeRecoveryContainer()
            return StoreBootstrapResult(
                container: container,
                errorMessage: "Aggie GPA could not safely open or migrate your local data. The original store was not deleted or replaced. Close the app and keep the migration backup before trying again."
            )
        }
    }

    /// Opens the same durable store as the app for App Intents.
    ///
    /// This deliberately has no in-memory recovery fallback: returning an empty database to
    /// Siri would be indistinguishable from a valid "no results" answer. When a Simulator
    /// does not expose the production App Group, `makeConfiguration` selects the same
    /// app-private store used by the app instead.
    static func makeAppIntentContainer() throws -> ModelContainer {
        let configuration = makeConfiguration(inMemory: false)
        return try ModelContainer(
            for: v2Schema,
            migrationPlan: AggieGPAMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeConfiguration(inMemory: Bool) -> ModelConfiguration {
        if !inMemory {
            let storeURL = appGroupStoreURL() ?? legacyStoreURL()
            return ModelConfiguration(configurationName, schema: v2Schema, url: storeURL)
        }
        return ModelConfiguration(
            configurationName,
            schema: v2Schema,
            isStoredInMemoryOnly: inMemory
        )
    }

    private static func makeRecoveryContainer() -> ModelContainer {
        let recovery = ModelConfiguration("AggieGPARecovery", schema: v2Schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: v2Schema, migrationPlan: AggieGPAMigrationPlan.self, configurations: [recovery]) else {
            fatalError("Aggie GPA could not initialize a recovery container.")
        }
        return container
    }

    private static func appGroupStoreURL() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return nil }
        let support = container.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return support.appending(path: "\(configurationName).store", directoryHint: .notDirectory)
    }

    /// Copies the legacy app-private SQLite store once, preserving the source files.
    /// The shared group is local-only and lets the app and its App Intents use exactly the same records.
    private static func migrateLegacyStoreToAppGroupIfNeeded() throws {
        guard let destination = appGroupStoreURL() else { throw StoreError.appGroupUnavailable }
        let legacy = legacyStoreURL()
        guard legacy.standardizedFileURL != destination.standardizedFileURL else { return }
        let manager = FileManager.default
        guard manager.fileExists(atPath: legacy.path) else { return }
        if manager.fileExists(atPath: destination.path) {
            guard try !sharedStoreContainsUserData(at: destination) else { return }
            for suffix in ["", "-wal", "-shm"] {
                let emptyStoreFile = URL(fileURLWithPath: destination.path + suffix)
                if manager.fileExists(atPath: emptyStoreFile.path) { try manager.removeItem(at: emptyStoreFile) }
            }
        }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: legacy.path + suffix)
            guard manager.fileExists(atPath: source.path) else { continue }
            try manager.copyItem(at: source, to: URL(fileURLWithPath: destination.path + suffix))
        }
    }

    private static func legacyStoreURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(configurationName).store", isDirectory: false)
    }

    private static func sharedStoreContainsUserData(at url: URL) throws -> Bool {
        let configuration = ModelConfiguration(configurationName, schema: v2Schema, url: url)
        let container = try ModelContainer(for: v2Schema, migrationPlan: AggieGPAMigrationPlan.self, configurations: [configuration])
        let context = ModelContext(container)
        let preferences = try context.fetch(FetchDescriptor<UserPreferences>())
        let terms = try context.fetch(FetchDescriptor<AcademicTerm>())
        let courses = try context.fetch(FetchDescriptor<CourseRecord>())
        let items = try context.fetch(FetchDescriptor<GradeItem>())
        return !preferences.isEmpty || !terms.isEmpty || !courses.isEmpty || !items.isEmpty
    }

    private enum StoreError: LocalizedError {
        case appGroupUnavailable
        var errorDescription: String? { "The local shared App Group is unavailable." }
    }

    static func createVerifiedV1RecoveryBackupIfNeeded(storeURL: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: storeURL.path) else { return }

        let support = storeURL.deletingLastPathComponent()
        let directory = support.appending(path: "MigrationBackups", directoryHint: .isDirectory)
        let marker = directory.appending(path: "v1-backup-verified.marker")
        guard !manager.fileExists(atPath: marker.path) else { return }

        let v1Configuration = ModelConfiguration(configurationName, schema: v1Schema, url: storeURL)
        let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Configuration])
        let context = ModelContext(v1Container)
        let terms = try context.fetch(FetchDescriptor<AcademicTerm>())
        let scenarios = try context.fetch(FetchDescriptor<PlannerScenario>())
        let preferences = try context.fetch(FetchDescriptor<UserPreferences>()).first ?? UserPreferences()
        let envelope = BackupService.makeEnvelope(terms: terms, scenarios: scenarios, preferences: preferences)
        let data = try BackupService.encode(envelope)
        _ = try BackupService.decode(data)

        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let backupURL = directory.appending(path: "pre-v1.1-\(Int(Date.now.timeIntervalSince1970)).json")
        try data.write(to: backupURL, options: [.atomic, .completeFileProtection])
        try Data(backupURL.lastPathComponent.utf8).write(to: marker, options: .atomic)
    }
}
