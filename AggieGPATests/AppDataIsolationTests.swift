import SwiftData
import XCTest
@testable import AggieGPA

@MainActor
final class AppDataIsolationTests: XCTestCase {
    func testNormalLaunchUsesDurableData() {
        XCTAssertFalse(AppDataIsolation.isEnabled(arguments: ["AggieGPA"], environment: [:], testRuntimeLoaded: false))
    }

    func testEveryPreviewAndUITestFlagIsIsolated() {
        for flag in ["--uitest-in-memory", "--ui-testing", "--screenshot-demo"] {
            XCTAssertTrue(AppDataIsolation.isEnabled(arguments: ["AggieGPA", flag], environment: [:], testRuntimeLoaded: false))
        }
    }

    func testRegeneratedDescriptorDoesNotNeedCustomArguments() {
        for key in ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier", "XCInjectBundleInto"] {
            XCTAssertTrue(AppDataIsolation.isEnabled(arguments: ["AggieGPA"], environment: [key: "present"], testRuntimeLoaded: false))
        }
        XCTAssertTrue(AppDataIsolation.isEnabled(arguments: ["AggieGPA"], environment: [:], testRuntimeLoaded: true))
    }

    func testEmptyMarkersAndUnrelatedArgumentsDoNotHideUserData() {
        XCTAssertFalse(AppDataIsolation.isEnabled(arguments: ["AggieGPA", "--ordinary-launch"], environment: ["XCTestBundlePath": "", "OTHER_TEST_FLAG": "1"], testRuntimeLoaded: false))
    }

    func testActualHostCannotOpenDurableStoreWhenCallerRequestsIt() throws {
        XCTAssertTrue(AppDataIsolation.isEnabled)
        XCTAssertTrue(PersistentStoreService.makeConfiguration(inMemory: false).isStoredInMemoryOnly)
        let result = PersistentStoreService.makeContainer(inMemory: false)
        XCTAssertNil(result.errorMessage)
        XCTAssertTrue(result.container.configurations.allSatisfy(\.isStoredInMemoryOnly))
        let context = ModelContext(result.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannerScenario>()), 0)
        context.insert(PlannerScenario(name: "Isolation sentinel", scenarioType: .custom))
        try context.save()
        let separate = PersistentStoreService.makeContainer(inMemory: false)
        XCTAssertEqual(try ModelContext(separate.container).fetchCount(FetchDescriptor<PlannerScenario>()), 0)
    }

    func testAppIntentFactoryAlsoHonorsTestIsolation() throws {
        let container = try PersistentStoreService.makeAppIntentContainer()
        XCTAssertTrue(container.configurations.allSatisfy(\.isStoredInMemoryOnly))
    }
}
