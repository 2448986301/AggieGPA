import Foundation
import SwiftData

struct StoreBootstrapResult {
    let container: ModelContainer
    let errorMessage: String?
}

@MainActor
enum PersistentStoreService {
    static let configurationName = "AggieGPA"

    static var v1Schema: Schema { Schema(AggieGPASchemaV1.models) }
    static var v2Schema: Schema { Schema(versionedSchema: AggieGPASchemaV2.self) }

    static func makeContainer(inMemory: Bool) -> StoreBootstrapResult {
        let configuration = ModelConfiguration(
            configurationName,
            schema: v2Schema,
            isStoredInMemoryOnly: inMemory
        )

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
            let recovery = ModelConfiguration(
                "AggieGPARecovery",
                schema: v2Schema,
                isStoredInMemoryOnly: true
            )
            guard let container = try? ModelContainer(
                for: v2Schema,
                migrationPlan: AggieGPAMigrationPlan.self,
                configurations: [recovery]
            ) else {
                fatalError("Aggie GPA could not initialize a recovery container: \(error.localizedDescription)")
            }
            return StoreBootstrapResult(
                container: container,
                errorMessage: "Aggie GPA could not safely open or migrate your local data. The original store was not deleted or replaced. Close the app and keep the migration backup before trying again."
            )
        }
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
