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

    func testForecastTargetButtonKeepsIntrinsicInteractionBounds() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        exerciseForecastTargetInteractions(app: app, chinese: false)
    }

    func testForecastTargetButtonKeepsIntrinsicInteractionBoundsInSimplifiedChinese() {
        let app = makeApp(extraArguments: ["--screenshot-demo", "--screenshot-chinese"])
        exerciseForecastTargetInteractions(app: app, chinese: true)
    }

    func testFineTuningPercentageUsesPillBoundsAndTracksControls() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        openDemoGradebook(app: app)

        let sectionPicker = app.descendants(matching: .any)["courseDetailSectionPicker"]
        XCTAssertTrue(sectionPicker.waitForExistence(timeout: 5))
        sectionPicker.coordinate(withNormalizedOffset: CGVector(dx: 5.0 / 6.0, dy: 0.5)).tap()

        let fineTuning = app.buttons["Fine-tune assignments"]
        for _ in 0..<2 where !fineTuning.exists {
            app.swipeUp()
        }
        XCTAssertTrue(fineTuning.waitForExistence(timeout: 5))
        fineTuning.tap()

        let percentage = app.descendants(matching: .any)["85 percent assumed for Homework 3"]
        scrollTo(percentage, in: app)
        XCTAssertTrue(percentage.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(percentage.frame.height, 44)
        XCTAssertGreaterThan(percentage.frame.width, percentage.frame.height)

        let slider = app.sliders["Homework 3 assumption"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let increment = app.buttons["Increment"].firstMatch
        XCTAssertTrue(increment.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            increment.tap()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["91 percent assumed for Homework 3"]
                .waitForExistence(timeout: 3)
        )
    }

    func testCourseDetailModuleTitlesStayInsideReadableBounds() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        exerciseCourseDetailModuleTitleBounds(app: app, chinese: false)
    }

    func testCourseDetailModuleTitlesStayInsideReadableBoundsInSimplifiedChinese() {
        let app = makeApp(extraArguments: ["--screenshot-demo", "--screenshot-chinese"])
        exerciseCourseDetailModuleTitleBounds(app: app, chinese: true)
    }

    func testCourseDataLabelsStayVerbatimInSimplifiedChinese() {
        let app = makeApp(extraArguments: ["--screenshot-demo", "--screenshot-chinese"])
        openDemoGradebook(app: app)

        XCTAssertTrue(app.staticTexts["General Chemistry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["普通化学"].exists)
        for label in ["Homework", "Homework 1", "Homework 2", "Homework 3"] {
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.staticTexts["作业"].exists)
        XCTAssertFalse(app.staticTexts["作业 1"].exists)

        let finalExam = app.staticTexts["Final Exam"]
        scrollTo(finalExam, in: app)
        for label in ["Labs", "Lab 1", "Midterms", "Midterm 1", "Final Exam"] {
            XCTAssertTrue(app.staticTexts[label].exists)
        }
        XCTAssertFalse(app.staticTexts["实验"].exists)
        XCTAssertFalse(app.staticTexts["期中考试"].exists)
        XCTAssertFalse(app.staticTexts["期末考试"].exists)
    }

    func testProfileDataStaysVerbatimAndBackgroundTapDismissesKeyboardInSimplifiedChinese() {
        let app = makeApp(extraArguments: ["--screenshot-demo", "--screenshot-chinese"])
        app.buttons.matching(identifier: "gearshape").firstMatch.tap()

        let major = app.textFields["settingsMajorField"]
        XCTAssertTrue(major.waitForExistence(timeout: 5))
        XCTAssertEqual(major.value as? String, "Biological Sciences")
        XCTAssertFalse(app.staticTexts["生物科学"].exists)

        major.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["个人信息"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        let majorGPAToggle = app.switches["settingsShowMajorGPAToggle"]
        XCTAssertTrue(majorGPAToggle.waitForExistence(timeout: 3))
        let originalToggleValue = majorGPAToggle.value as? String
        majorGPAToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let toggleChanged = NSPredicate { _, _ in
            majorGPAToggle.value as? String != originalToggleValue
        }
        expectation(for: toggleChanged, evaluatedWith: nil)
        waitForExpectations(timeout: 3)

        let gradingBasisPicker = app.descendants(matching: .any)["settingsDefaultGradingBasisPicker"]
        XCTAssertTrue(gradingBasisPicker.isHittable)
    }

    func testEmptyGradebookBlankTapsDoNotOpenSetupSheetsAndActionsStayBounded() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        openDemoCourse(app: app, courseCode: "BIS 002B")

        let emptyStateTitle = app.staticTexts["How is this course graded?"]
        XCTAssertTrue(emptyStateTitle.waitForExistence(timeout: 5))

        let template = app.buttons["useGradeTemplateSetupButton"]
        let syllabus = app.buttons["importSyllabusSetupButton"]
        let manual = app.buttons["manualGradeSetupButton"]
        for button in [template, syllabus, manual] {
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertLessThanOrEqual(button.frame.width, 320)
        }
        XCTAssertEqual(template.frame.width, syllabus.frame.width, accuracy: 2)
        XCTAssertEqual(syllabus.frame.width, manual.frame.width, accuracy: 2)

        for point in [
            CGVector(dx: 0.04, dy: 0.55),
            CGVector(dx: 0.96, dy: 0.55),
            CGVector(dx: 0.04, dy: 0.72),
            CGVector(dx: 0.96, dy: 0.72),
        ] {
            app.coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(emptyStateTitle.exists)
            XCTAssertFalse(app.navigationBars["Import Syllabus"].exists)
            XCTAssertFalse(app.navigationBars["Grading Policy"].exists)
            XCTAssertFalse(app.navigationBars["Grade Breakdown"].exists)
        }

        scrollTo(syllabus, in: app)
        XCTAssertTrue(syllabus.isHittable)
        syllabus.tap()
        XCTAssertTrue(app.navigationBars["Import Syllabus"].waitForExistence(timeout: 5))
    }

    func testFocusNextUsesReliableDemoWorkAndCanBeHidden() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        exerciseFocusNext(app: app, hideLabel: "Hide Focus Next", reasonFragment: "course grade")
    }

    func testFocusNextUsesReliableDemoWorkAndCanBeHiddenInSimplifiedChinese() {
        let app = makeApp(extraArguments: ["--screenshot-demo", "--screenshot-chinese"])
        exerciseFocusNext(app: app, hideLabel: "隐藏下一步建议", reasonFragment: "课程总评")
    }

    func testFocusNextShortcutOpensScoreEntryInsteadOfGradeItemEditor() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        let focusItem = app.buttons["focusNextItem-Homework 3"]
        XCTAssertTrue(focusItem.waitForExistence(timeout: 5))
        focusItem.tap()

        XCTAssertTrue(app.textFields["recordEarnedPointsField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["recordPossiblePointsField"].exists)
        XCTAssertFalse(app.textFields["gradeItemTitleField"].exists)
    }

    func testSemesterMapShowsCurrentWeekAndDatedWork() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        exerciseSemesterMap(app: app, navigationTitle: "Semester Map", termStatus: "Starts", itemTitle: "Homework 1")
    }

    func testSemesterMapShowsCurrentWeekAndDatedWorkInSimplifiedChinese() {
        let app = makeApp(extraArguments: ["--screenshot-demo", "--screenshot-chinese"])
        exerciseSemesterMap(app: app, navigationTitle: "学期进度", termStatus: "开始", itemTitle: "作业 1")
    }

    func testSemesterMapScreenshotLaunchOpensTimeline() {
        let app = makeApp(extraArguments: ["--screenshot-demo", "--screenshot-semester-map"])
        XCTAssertTrue(app.navigationBars["Semester Map"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(identifier: "semesterMapOverview").count,
            0
        )
    }

    private func exerciseSemesterMap(
        app: XCUIApplication,
        navigationTitle: String,
        termStatus: String,
        itemTitle: String
    ) {
        let mapButton = app.buttons["semesterMapButton"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 5))
        mapButton.tap()

        XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(identifier: "semesterMapOverview").count,
            0
        )
        XCTAssertTrue(app.staticTexts[termStatus].exists)
        XCTAssertTrue(app.staticTexts[itemTitle].exists)
        if app.frame.width >= 700 {
            XCTAssertGreaterThan(
                app.descendants(matching: .any).matching(identifier: "semesterMapExpandedTimeline").count,
                0
            )
        } else {
            XCTAssertGreaterThan(
                app.descendants(matching: .any).matching(identifier: "semesterMapCompactTimeline").count,
                0
            )
        }
    }

    private func exerciseFocusNext(app: XCUIApplication, hideLabel: String, reasonFragment: String) {
        let itemTitle = hideLabel == "隐藏下一步建议" ? "作业 3" : "Homework 3"
        let focusTitle = app.descendants(matching: .any)["focusNextTitle"]
        XCTAssertTrue(focusTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[itemTitle].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", reasonFragment)).firstMatch.exists
        )

        let hideButton = app.buttons["hideFocusNextButton"]
        XCTAssertEqual(hideButton.label, hideLabel)
        XCTAssertTrue(hideButton.isHittable)
        hideButton.tap()
        XCTAssertFalse(focusTitle.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts[itemTitle].exists)
    }

    private func exerciseCourseDetailModuleTitleBounds(app: XCUIApplication, chinese: Bool) {
        openDemoGradebook(app: app)

        let sectionPicker = app.descendants(matching: .any)["courseDetailSectionPicker"]
        XCTAssertTrue(sectionPicker.waitForExistence(timeout: 5))

        sectionPicker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let breakdownTitle = app.staticTexts["gradeBreakdownTitle"]
        XCTAssertTrue(breakdownTitle.waitForExistence(timeout: 5))
        assertReadableLeadingBoundary(breakdownTitle, in: app)
        if chinese {
            XCTAssertTrue(app.staticTexts["目前已有 70% 的课程权重完成评分。"].exists)
        }

        sectionPicker.coordinate(withNormalizedOffset: CGVector(dx: 5.0 / 6.0, dy: 0.5)).tap()

        let forecastTitle = app.staticTexts["forecastGoalTitle"]
        XCTAssertTrue(forecastTitle.waitForExistence(timeout: 5))
        assertReadableLeadingBoundary(forecastTitle, in: app)
    }

    private func assertReadableLeadingBoundary(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let readableInset: CGFloat = 8
        XCTAssertGreaterThanOrEqual(
            element.frame.minX,
            app.frame.minX + readableInset,
            "The title must not touch or cross the List clipping boundary.",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX - readableInset, file: file, line: line)
    }

    private func exerciseForecastTargetInteractions(app: XCUIApplication, chinese: Bool) {
        openDemoGradebook(app: app)

        let sectionPicker = app.descendants(matching: .any)["courseDetailSectionPicker"]
        XCTAssertTrue(sectionPicker.waitForExistence(timeout: 5))
        sectionPicker.coordinate(withNormalizedOffset: CGVector(dx: 5.0 / 6.0, dy: 0.5)).tap()

        if chinese {
            XCTAssertTrue(app.descendants(matching: .any)["稳妥"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["按当前表现"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["冲刺"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["稳妥 70%"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["冲刺 95%"].exists)
        }

        let targetButton = app.buttons["forecastTargetButton"]
        XCTAssertTrue(targetButton.waitForExistence(timeout: 5))
        print("Forecast target button frame: \(targetButton.frame)")
        XCTAssertLessThanOrEqual(targetButton.frame.width, 120)
        XCTAssertLessThanOrEqual(targetButton.frame.height, 60)

        let resetLabel = chinese ? "恢复默认" : "Reset"
        let targetGradeTitle = chinese ? "目标成绩" : "Target Grade"
        let saveLabel = chinese ? "保存" : "Save"
        let resetButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", resetLabel)).firstMatch
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5))
        XCTAssertFalse(targetButton.frame.intersects(resetButton.frame))

        targetButton.press(forDuration: 2)
        XCTAssertTrue(app.navigationBars[targetGradeTitle].waitForExistence(timeout: 5))
        app.buttons[saveLabel].tap()
        XCTAssertTrue(targetButton.waitForExistence(timeout: 5))

        XCTAssertTrue(resetButton.isHittable)
        resetButton.tap()
        XCTAssertTrue(targetButton.exists)

        let start = targetButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let outside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.9))
        start.press(forDuration: 2, thenDragTo: outside)
        XCTAssertFalse(app.navigationBars[targetGradeTitle].exists)
        XCTAssertTrue(targetButton.exists)
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
        let whatIf = app.staticTexts["Try a GPA forecast"]
        XCTAssertTrue(whatIf.waitForExistence(timeout: 5))
        whatIf.tap()
        let saveScenario = app.buttons["Save Scenario"]
        scrollTo(saveScenario, in: app)
        saveScenario.tap()
        XCTAssertTrue(app.staticTexts["Scenario saved. Estimated results were updated; official records were not changed."].waitForExistence(timeout: 5))

        let saveToRecords = app.buttons["Save to Records"]
        scrollTo(saveToRecords, in: app)
        saveToRecords.tap()
        let confirmation = app.alerts["Apply this scenario to official records?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["Cancel"].exists)
    }

    func testGPAOverviewAdaptsAtLargestAccessibilityTextSize() {
        let app = makeApp(extraArguments: [
            "--screenshot-demo",
            "--screenshot-tab=planner",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ])
        let overview = app.descendants(matching: .any)["gpaOverview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(overview.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(overview.frame.maxX, app.frame.maxX)
        XCTAssertTrue(app.staticTexts["Official results"].exists)
        XCTAssertTrue(app.staticTexts["Estimated results"].exists)
    }

    func testGPAOverviewUsesNaturalSimplifiedChineseLabels() {
        let app = makeApp(extraArguments: [
            "--screenshot-demo",
            "--screenshot-chinese",
            "--screenshot-tab=planner",
        ])
        XCTAssertTrue(app.descendants(matching: .any)["gpaOverview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["正式成绩"].exists)
        XCTAssertTrue(app.staticTexts["预计成绩"].exists)
        XCTAssertTrue(app.staticTexts["本学期 GPA"].exists)
    }

    func testSettingsUsesNaturalSimplifiedChineseLabels() {
        let app = makeApp(extraArguments: [
            "--screenshot-demo",
            "--screenshot-chinese",
            "--screenshot-tab=settings",
        ])
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["个人信息"].exists)
        XCTAssertTrue(app.staticTexts["目标 GPA"].exists)
        XCTAssertTrue(
            app.textFields.matching(NSPredicate(format: "value == %@", "生物科学")).firstMatch.exists
        )

        let siriAI = app.buttons["Siri AI"]
        scrollTo(siriAI, in: app)
        XCTAssertTrue(siriAI.exists)
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
        for version in ["1.4.0", "1.3.1", "1.3.0", "1.2.0", "1.1.2", "1.1.1", "1.1.0", "1.0"] {
            let versionLabel = app.staticTexts["Version \(version)"]
            scrollTo(versionLabel, in: app)
            XCTAssertTrue(versionLabel.exists, "Version \(version) should appear in version history")
        }
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

    func testEditingRecordedScorePreservesExistingValuesUntilSave() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        openDemoGradebook(app: app)

        let homework = app.staticTexts["Homework 1"].firstMatch
        XCTAssertTrue(homework.waitForExistence(timeout: 5))
        homework.swipeRight()
        let editScore = app.buttons["Edit Score"].firstMatch
        XCTAssertTrue(editScore.waitForExistence(timeout: 5))
        editScore.tap()

        let earned = app.textFields["recordEarnedPointsField"]
        let possible = app.textFields["recordPossiblePointsField"]
        XCTAssertTrue(earned.waitForExistence(timeout: 5))
        XCTAssertEqual(earned.value as? String, "18")
        XCTAssertEqual(possible.value as? String, "20")
        XCTAssertTrue(app.navigationBars["Edit Score"].exists)

        app.buttons["Cancel"].tap()
        let unchangedRow = app.descendants(matching: .any)["gradeItemRow-Homework 1"]
        XCTAssertTrue(unchangedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(unchangedRow.label.contains("18 / 20"))
    }

    func testEditAssignmentDetailsOpensExistingItemInsteadOfNewItem() {
        let app = makeApp(extraArguments: ["--screenshot-demo"])
        openDemoGradebook(app: app)

        let homework = app.staticTexts["Homework 1"].firstMatch
        XCTAssertTrue(homework.waitForExistence(timeout: 5))
        homework.press(forDuration: 1)

        let editDetails = app.buttons["Edit Assignment Details"]
        XCTAssertTrue(editDetails.waitForExistence(timeout: 5))
        editDetails.tap()

        XCTAssertTrue(app.navigationBars["Edit Grade Item"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["gradeItemTitleField"].value as? String, "Homework 1")
        XCTAssertFalse(app.navigationBars["New Grade Item"].exists)
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
        XCTAssertTrue(homework.exists, "The row must remain until destructive deletion is confirmed.")
        XCTAssertFalse(app.buttons["undoGradeItemDeleteButton"].exists)
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
        openDemoCourse(app: app, courseCode: "CHE 002A")
    }

    private func openDemoCourse(app: XCUIApplication, courseCode: String) {
        app.buttons.matching(identifier: "books.vertical").firstMatch.tap()
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Fall 2026' OR label CONTAINS '2026 秋季学期'")
        ).firstMatch.tap()
        app.staticTexts[courseCode].tap()
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
