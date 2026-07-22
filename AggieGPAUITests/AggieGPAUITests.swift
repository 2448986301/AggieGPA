import XCTest

@MainActor
final class AggieGPAUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCompleteOnboarding() {
        let app = makeApp()
        completeOnboarding(app: app)
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
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

    func testOpenCourseGradebook() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        app.tabBars.buttons["Courses"].tap()
        app.staticTexts["Fall 2026"].tap()
        app.staticTexts["CHE 002A"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["courseGradeHero"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["courseDetailSectionPicker"].exists)
    }

    func testSyllabusRecognitionRequiresReviewBeforeSaving() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        openDemoGradebook(app: app)
        app.buttons["Gradebook actions"].tap()
        app.buttons["Import Grading Policy"].tap()
        let editor = app.textViews["syllabusTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Homework 30%\nMidterm 30%\nFinal 40%")
        app.buttons["parseSyllabusButton"].tap()
        XCTAssertTrue(app.staticTexts["Recognition Preview"].waitForExistence(timeout: 5))
        let confirm = app.buttons["confirmSyllabusRulesButton"]
        scrollTo(confirm, in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    }

    func testGradebookRemainsReachableAtLargestAccessibilityTextSize() {
        let app = makeApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])
        completeOnboarding(app: app, loadDemo: true)
        openDemoGradebook(app: app)
        XCTAssertTrue(app.descendants(matching: .any)["courseGradeHero"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["courseDetailSectionPicker"].exists)
    }

    func testDeleteAndUndo() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        app.tabBars.buttons["Courses"].tap()
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
        app.tabBars.buttons["GPA"].tap()
        app.staticTexts["Projected GPA"].tap()
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

    func testTodayGlobalAddShowsStudentActions() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        let add = app.buttons["todayAddButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.buttons["Add Assignment"].exists)
        XCTAssertTrue(app.buttons["Add Exam"].exists)
        XCTAssertTrue(app.buttons["Record Score"].exists)
    }

    func testTodayAssignmentAsksForCourseWhenSeveralCoursesExist() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        app.buttons["todayAddButton"].tap()
        app.buttons["Add Assignment"].tap()
        XCTAssertTrue(app.navigationBars["Which course?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CHE 002A"].exists)
        XCTAssertTrue(app.staticTexts["BIS 002B"].exists)
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

    func testSiriAccessDefaultsOff() {
        let app = makeApp()
        completeOnboarding(app: app)
        app.tabBars.buttons["Settings"].tap()
        let siriLink = app.buttons["Siri & Shortcuts Access"]
        scrollTo(siriLink, in: app)
        siriLink.tap()
        let siriToggle = app.switches["Enable Siri Access"]
        XCTAssertTrue(siriToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(siriToggle.value as? String, "0")
    }

    private func makeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-in-memory"] + extraArguments
        app.launch()
        return app
    }

    private func openDemoGradebook(app: XCUIApplication) {
        app.tabBars.buttons["Courses"].tap()
        app.staticTexts["Fall 2026"].tap()
        app.staticTexts["CHE 002A"].tap()
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
        app.tabBars.buttons["Courses"].tap()
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
