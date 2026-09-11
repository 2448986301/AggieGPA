import XCTest

/// Opt-in forensic navigation against a disposable Simulator copy, never a phone.
final class StorePreservationUITests: XCTestCase {
    func testOrdinaryNavigationDoesNotEditAssumedGrades() throws {
#if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["AGGIE_ISOLATED_SIMULATOR_PERSISTENCE_CHECK"] == "1" else {
            throw XCTSkip("Requires a separately provisioned disposable Simulator database")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let releaseContinue = app.buttons.matching(NSPredicate(format: "label == 'Continue' OR label == '继续'" )).firstMatch
        if releaseContinue.waitForExistence(timeout: 2) { releaseContinue.tap() }
        let gpa = app.tabBars.buttons["GPA"]
        XCTAssertTrue(gpa.waitForExistence(timeout: 8))
        for _ in 0..<3 {
            gpa.tap()
            let full = app.descendants(matching: .any)["openFullSimulation"].firstMatch
            for _ in 0..<8 {
                if full.exists && full.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(full.waitForExistence(timeout: 5))
            full.tap()
            XCTAssertTrue(app.descendants(matching: .any)["gpaFullSimulation"].waitForExistence(timeout: 5))
            app.swipeUp()
            app.swipeDown()
            app.navigationBars.buttons.firstMatch.tap()
            app.tabBars.buttons.matching(NSPredicate(format: "label == 'Settings' OR label == '设置'" )).firstMatch.tap()
            let siri = app.buttons["Siri AI"].firstMatch
            for _ in 0..<4 {
                if siri.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(siri.isHittable)
            siri.tap()
            XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.terminate()
#else
        throw XCTSkip("Persistent navigation is prohibited on physical devices")
#endif
    }
}
