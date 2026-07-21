import SwiftData
import SwiftUI

@main
struct AggieGPAApp: App {
    private let container: ModelContainer
    @State private var privacyLock = PrivacyLockService()

    init() {
        let schema = Schema([
            AcademicTerm.self, CourseRecord.self, PlannerScenario.self,
            SimulatedCourse.self, GradeCategory.self, CourseGradePlan.self,
            UserPreferences.self, BackupSnapshot.self
        ])
        let arguments = ProcessInfo.processInfo.arguments
        let inMemory = arguments.contains("--uitest-in-memory") || arguments.contains("--screenshot-demo")
        let configuration = ModelConfiguration("AggieGPA", schema: schema, isStoredInMemoryOnly: inMemory)
        if let primaryContainer = try? ModelContainer(for: schema, configurations: [configuration]) {
            container = primaryContainer
        } else {
            let recoveryConfiguration = ModelConfiguration(
                "AggieGPARecovery",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            do {
                container = try ModelContainer(for: schema, configurations: [recoveryConfiguration])
            } catch {
                fatalError("Aggie GPA could not initialize a safe local data store.")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(privacyLock)
        }
        .modelContainer(container)
    }
}
