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
        app.buttons["Course Settings"].tap()
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

    func testFinalizeCourseDeletionKeepsQuarterAndDashboardUsable() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        app.tabBars.buttons["Courses"].tap()
        app.staticTexts["Fall 2026"].tap()
        let course = app.staticTexts["CHE 002A"]
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.swipeLeft()
        app.buttons["Delete"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Fall 2026"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["todayAddButton"].waitForExistence(timeout: 5))
    }

    func testClearDemoDataKeepsDashboardUsable() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        app.tabBars.buttons["Settings"].tap()
        let clearDemoData = app.buttons["Clear Demo Data"]
        scrollTo(clearDemoData, in: app)
        XCTAssertTrue(clearDemoData.waitForExistence(timeout: 5))
        clearDemoData.tap()
        XCTAssertTrue(app.buttons["Load Demo Data"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["No courses yet"].waitForExistence(timeout: 5))
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

    func testAboutShowsCurrentVersionAndVersionHistory() {
        let app = makeApp(extraArguments: ["--screenshot-tab=settings"])
        completeOnboarding(app: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let about = app.buttons["About"]
        scrollTo(about, in: app)
        about.tap()
        XCTAssertTrue(app.descendants(matching: .any)["appVersion"].waitForExistence(timeout: 5))
        let whatsNew = app.staticTexts["What’s New"]
        XCTAssertTrue(whatsNew.waitForExistence(timeout: 5))
        whatsNew.tap()
        XCTAssertTrue(app.descendants(matching: .any)["versionHistoryView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Version 1.3.1"].exists)
        XCTAssertTrue(app.staticTexts["Version 1.3.0"].exists)
        XCTAssertTrue(app.staticTexts["Version 1.2.0"].exists)
        XCTAssertTrue(app.staticTexts["Version 1.1.2"].exists)
        XCTAssertTrue(app.staticTexts["Version 1.1.1"].exists)
        XCTAssertTrue(app.staticTexts["Version 1.1.0"].exists)
        XCTAssertTrue(app.staticTexts["Version 1.0"].exists)
    }

    func testWhatsNewAppearsOnceForAnExistingStudent() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-in-memory", "--screenshot-demo", "--screenshot-whats-new", "-lastSeenReleaseNotesVersion", ""]
        app.launch()
        let sheet = app.descendants(matching: .any)["whatsNewSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        app.buttons["whatsNewGetStarted"].tap()
        XCTAssertFalse(sheet.exists)

        app.terminate()
        app.launchArguments = ["--uitest-in-memory", "--screenshot-demo"]
        app.launch()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
    }

    func testVersionHistoryAtLargestAccessibilityTextSize() {
        let app = makeApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])
        completeOnboarding(app: app)
        app.tabBars.buttons["Settings"].tap()
        let about = app.buttons["About"]
        scrollTo(about, in: app)
        about.tap()
        app.buttons["whatsNewLink"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["versionHistoryView"].waitForExistence(timeout: 5))
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

    func testStudentCoreFlowRecordsAnUpcomingScore() {
        let app = makeApp()
        completeOnboarding(app: app, loadDemo: true)
        openDemoGradebook(app: app)

        let upcomingHomework = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Homework 3'")).firstMatch
        XCTAssertTrue(upcomingHomework.waitForExistence(timeout: 5))
        upcomingHomework.tap()

        let earned = app.textFields["recordEarnedPointsField"]
        XCTAssertTrue(earned.waitForExistence(timeout: 5))
        earned.tap()
        earned.typeText("20")
        app.buttons["saveRecordedScoreButton"].tap()

        XCTAssertTrue(app.staticTexts["Current course grade updated for CHE 002A."].waitForExistence(timeout: 5))
        let gradedHomework = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Homework 3, Graded'")).firstMatch
        XCTAssertTrue(gradedHomework.waitForExistence(timeout: 5))
    }

    func testGradedAssignmentDeleteRequiresConfirmationAndCanUndo() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        openDemoGradebook(app: app)

        let homework = app.staticTexts["Homework 1"].firstMatch
        XCTAssertTrue(homework.waitForExistence(timeout: 5))
        homework.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let deletionAlert = app.alerts.firstMatch
        XCTAssertTrue(deletionAlert.waitForExistence(timeout: 5))
        deletionAlert.buttons["Delete Assignment"].tap()
        XCTAssertTrue(app.buttons["undoGradeItemDeleteButton"].waitForExistence(timeout: 5))
        app.buttons["undoGradeItemDeleteButton"].tap()
        XCTAssertTrue(homework.waitForExistence(timeout: 5))
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
        let siriLink = app.buttons["Siri AI"]
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
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Fall 2026'")).firstMatch.tap()
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
