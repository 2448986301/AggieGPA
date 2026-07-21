import XCTest

@MainActor
final class AggieGPAUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCompleteOnboarding() {
        let app = makeApp()
        completeOnboarding(app: app)
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].exists)
    }

    func testAddQuarter() {
        let app = makeApp()
        completeOnboarding(app: app)
        addQuarter(app: app)
        XCTAssertTrue(app.staticTexts["Fall 2026"].exists)
    }

    func testAddCourse() {
        let app = makeApp()
        completeOnboarding(app: app)
        addQuarter(app: app)
        app.staticTexts["Fall 2026"].tap()
        app.buttons["addCourseButton"].tap()
        app.textFields["courseCodeField"].tap()
        app.textFields["courseCodeField"].typeText("CHE 002A")
        app.textFields["courseUnitsField"].tap()
        app.textFields["courseUnitsField"].typeText("5")
        app.buttons["saveCourseButton"].tap()
        XCTAssertTrue(app.staticTexts["CHE 002A"].exists)
    }

    func testEditCourse() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        app.tabBars.buttons["Quarters"].tap()
        app.staticTexts["Fall 2026"].tap()
        app.staticTexts["CHE 002A"].tap()
        XCTAssertTrue(app.navigationBars["Edit Course"].exists)
    }

    func testDeleteAndUndo() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        app.tabBars.buttons["Quarters"].tap()
        app.staticTexts["Fall 2026"].tap()
        let course = app.staticTexts["CHE 002A"]
        course.swipeLeft()
        app.buttons["Delete"].tap()
        app.buttons["undoDeleteButton"].tap()
        XCTAssertTrue(app.staticTexts["CHE 002A"].exists)
    }

    func testOpenWhatIfAndCreateScenario() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        app.tabBars.buttons["Planner"].tap()
        app.staticTexts["What-If GPA"].tap()
        let saveScenario = app.buttons["Save Scenario"]
        scrollTo(saveScenario, in: app)
        saveScenario.tap()
        XCTAssertTrue(app.staticTexts["Scenario saved. Official records were not changed."].exists)
    }

    func testExportDataFlow() {
        let app = makeApp()
        completeOnboarding(app: app)
        app.tabBars.buttons["Settings"].tap()
        let dataLink = app.buttons["Import, Export & Backups"]
        scrollTo(dataLink, in: app)
        dataLink.tap()
        XCTAssertTrue(app.buttons["exportJSONButton"].exists)
    }

    func testOpenSettings() {
        let app = makeApp()
        completeOnboarding(app: app)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    func testAppearancePickerHasDarkMode() {
        let app = makeApp()
        completeOnboarding(app: app)
        app.tabBars.buttons["Settings"].tap()
        let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance,'")).firstMatch
        scrollTo(appearance, in: app)
        appearance.tap()
        XCTAssertTrue(app.buttons["Dark"].exists || app.staticTexts["Dark"].exists)
    }

    func testOpenPrivacyLockSetting() {
        let app = makeApp()
        completeOnboarding(app: app)
        app.tabBars.buttons["Settings"].tap()
        let privacyToggle = app.switches["privacyLockToggle"]
        scrollTo(privacyToggle, in: app)
        XCTAssertTrue(privacyToggle.exists)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-in-memory"]
        app.launch()
        return app
    }

    private func completeOnboarding(app: XCUIApplication, loadDemo: Bool = false) {
        for _ in 0..<3 { app.buttons["onboardingContinue"].tap() }
        if loadDemo {
            let toggle = app.switches["Load clearly labeled demo data"]
            if toggle.exists { toggle.tap() }
        }
        app.buttons["onboardingFinish"].tap()
    }

    private func addQuarter(app: XCUIApplication) {
        app.tabBars.buttons["Quarters"].tap()
        app.buttons["addQuarterButton"].tap()
        app.buttons["saveQuarterButton"].tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
    }
}
