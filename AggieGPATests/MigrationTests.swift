import Foundation
import SwiftData
import XCTest
@testable import AggieGPA

@MainActor
final class MigrationTests: XCTestCase {
    func testV1DiskStoreMigratesThroughCurrentSchemaAndPreservesOfficialRecords() throws {
        let fixture = try makeTemporaryFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let storeURL = fixture.appending(path: "AggieGPA.store")
        let termID = UUID()
        let courseID = UUID()
        try createV1Store(at: storeURL, termID: termID, courseID: courseID)

        try PersistentStoreService.createVerifiedV1RecoveryBackupIfNeeded(storeURL: storeURL)
        let backupDirectory = fixture.appending(path: "MigrationBackups", directoryHint: .isDirectory)
        let backupFiles = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
        let backupURL = try XCTUnwrap(backupFiles.first { $0.pathExtension == "json" })
        let decoded = try BackupService.decode(Data(contentsOf: backupURL))
        XCTAssertEqual(decoded.courses.first?.id, courseID)
        XCTAssertEqual(decoded.courses.first?.grade, .aMinus)

        try verifyMigratedStore(at: storeURL, termID: termID, courseID: courseID)
    }

    private func verifyMigratedStore(at storeURL: URL, termID: UUID, courseID: UUID) throws {
        let configuration = ModelConfiguration("AggieGPA", schema: PersistentStoreService.v4Schema, url: storeURL)
        let container = try ModelContainer(for: PersistentStoreService.v4Schema,
                                           migrationPlan: AggieGPAMigrationPlan.self,
                                           configurations: [configuration])
        let context = ModelContext(container)
        let migratedTerms = try context.fetch(FetchDescriptor<AcademicTerm>())
        let migratedCourses = try context.fetch(FetchDescriptor<CourseRecord>())
        let migratedPreferences = try context.fetch(FetchDescriptor<UserPreferences>())

        XCTAssertEqual(migratedTerms.map(\.id), [termID])
        XCTAssertEqual(migratedCourses.map(\.id), [courseID])
        XCTAssertEqual(migratedCourses.first?.grade, .aMinus)
        XCTAssertEqual(migratedCourses.first?.units, 5)
        XCTAssertEqual(migratedPreferences.first?.targetGPA, Decimal(string: "3.8"))
        XCTAssertTrue(try context.fetch(FetchDescriptor<CourseTemplate>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CourseReminderDefaults>()).isEmpty)

        let course = try XCTUnwrap(migratedCourses.first)
        let policy = CourseGradingPolicy(course: course, targetLetterGrade: .aMinus)
        let category = GradingCategory(course: course, name: "Homework", categoryType: .homework, weight: 20)
        let item = GradeItem(course: course, category: category, title: "Homework 1", earnedPoints: 18,
                             possiblePoints: 20, status: .graded)
        context.insert(policy)
        context.insert(category)
        context.insert(item)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseGradingPolicy>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GradingCategory>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GradeItem>()).first?.earnedPoints, 18)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseRecord>()).first?.grade, .aMinus)
    }

    func testV141StoreOpensIn2AndBackupRestoresAllSupportedUserData() throws {
        let fixture = try makeTemporaryFixtureDirectory()
        let storeURL = fixture.appending(path: "AggieGPA.store")
        let fixtureIDs = try createV141Store(at: storeURL)
        defer {
            SyllabusSourceStore.remove(policyID: fixtureIDs.policyID)
            try? FileManager.default.removeItem(at: fixture)
        }

        let currentConfiguration = ModelConfiguration(
            "AggieGPA", schema: PersistentStoreService.v4Schema, url: storeURL)
        let currentContainer = try ModelContainer(
            for: PersistentStoreService.v4Schema,
            migrationPlan: AggieGPAMigrationPlan.self,
            configurations: [currentConfiguration])
        let currentContext = ModelContext(currentContainer)
        let terms = try currentContext.fetch(FetchDescriptor<AcademicTerm>())
        let courses = try currentContext.fetch(FetchDescriptor<CourseRecord>())
        let scenarios = try currentContext.fetch(FetchDescriptor<PlannerScenario>())
        let preferences = try XCTUnwrap(try currentContext.fetch(FetchDescriptor<UserPreferences>()).first)
        let policies = try currentContext.fetch(FetchDescriptor<CourseGradingPolicy>())
        let categories = try currentContext.fetch(FetchDescriptor<GradingCategory>())
        let items = try currentContext.fetch(FetchDescriptor<GradeItem>())
        let scales = try currentContext.fetch(FetchDescriptor<GradeScale>())
        let forecasts = try currentContext.fetch(FetchDescriptor<ForecastScenario>())
        let siriSettings = try currentContext.fetch(FetchDescriptor<SiriAccessSettings>()).first
        let templates = try currentContext.fetch(FetchDescriptor<CourseTemplate>())
        let reminderDefaults = try currentContext.fetch(FetchDescriptor<CourseReminderDefaults>())

        let sourceText = "Homework 40%; Midterm 25%; Final 35%."
        let sourcePages = Data("page-1\npage-2".utf8)
        SyllabusSourceStore.save(
            sourceText: sourceText,
            pagesData: sourcePages,
            source: .pdf,
            for: fixtureIDs.policyID)

        XCTAssertEqual(terms.map(\.id), [fixtureIDs.termID])
        XCTAssertEqual(courses.map(\.id), [fixtureIDs.courseID])
        XCTAssertEqual(courses.first?.grade, .aMinus)
        XCTAssertEqual(courses.first?.targetGrade, .a)
        XCTAssertEqual(policies.first?.importStatus, .confirmed)
        XCTAssertEqual(categories.first?.weight, Decimal(40))
        XCTAssertEqual(items.first?.earnedPoints, Decimal(18))
        XCTAssertEqual(scales.first?.boundaries.first?.minimumPercentage, Decimal(93))
        XCTAssertEqual(forecasts.first?.itemAssumptions[fixtureIDs.itemID], Decimal(88))
        XCTAssertEqual(scenarios.first?.targetGPA, Decimal(string: "3.75"))
        XCTAssertEqual(scenarios.first?.selectedCourseIDs, Set([fixtureIDs.courseID]))
        XCTAssertEqual(scenarios.first?.assumedGrades[fixtureIDs.courseID], .a)
        XCTAssertEqual(preferences.language, .simplifiedChinese)
        XCTAssertTrue(preferences.privacyLockEnabled)
        XCTAssertEqual(preferences.privacyLockDelay, .fiveMinutes)
        XCTAssertEqual(preferences.preferredAppIcon, .tinted)
        XCTAssertTrue(preferences.onboardingCompleted)
        XCTAssertTrue(preferences.demoDataLoaded)
        XCTAssertEqual(siriSettings?.allowGPAResponses, true)
        XCTAssertEqual(templates.first?.defaultReminderLeadTime, .oneWeek)
        XCTAssertEqual(reminderDefaults.first?.reminderLeadTime, .threeDays)

        let envelope = BackupService.makeEnvelope(
            terms: terms,
            courses: courses,
            scenarios: scenarios,
            preferences: preferences,
            policies: policies,
            categories: categories,
            items: items,
            scales: scales,
            forecasts: forecasts,
            siriSettings: siriSettings,
            templates: templates,
            reminderDefaults: reminderDefaults)
        let decoded = try BackupService.decode(BackupService.encode(envelope))

        XCTAssertEqual(decoded.preferences.privacyLockEnabled, true)
        XCTAssertEqual(decoded.preferences.privacyLockDelay, .fiveMinutes)
        XCTAssertEqual(decoded.preferences.preferredAppIcon, .tinted)
        XCTAssertEqual(decoded.preferences.onboardingCompleted, true)
        XCTAssertEqual(decoded.preferences.demoDataLoaded, true)
        XCTAssertEqual(decoded.plannerScenarios.first?.targetGPA, Decimal(string: "3.75"))
        XCTAssertEqual(decoded.plannerScenarios.first?.selectedCourseIDs, [fixtureIDs.courseID])
        XCTAssertEqual(decoded.plannerScenarios.first?.assumedGrades?[fixtureIDs.courseID], CourseGrade.a.rawValue)
        XCTAssertEqual(decoded.gradingPolicies?.first?.syllabusSourceText, sourceText)
        XCTAssertEqual(decoded.gradingPolicies?.first?.syllabusSourcePagesData, sourcePages)

        let restoreContainer = PersistentStoreService.makeContainer(inMemory: true).container
        let restoreContext = ModelContext(restoreContainer)
        let restoredPreferences = UserPreferences()
        restoreContext.insert(restoredPreferences)
        try restoreContext.save()
        try BackupService.apply(
            decoded,
            mode: .merge,
            context: restoreContext,
            existingTerms: [],
            existingScenarios: [],
            preferences: restoredPreferences)

        let restoredCourse = try XCTUnwrap(try restoreContext.fetch(FetchDescriptor<CourseRecord>()).first)
        let restoredPolicy = try XCTUnwrap(try restoreContext.fetch(FetchDescriptor<CourseGradingPolicy>()).first)
        let restoredScenario = try XCTUnwrap(try restoreContext.fetch(FetchDescriptor<PlannerScenario>()).first)
        let restoredPreferencesValue = try XCTUnwrap(try restoreContext.fetch(FetchDescriptor<UserPreferences>()).first)
        XCTAssertEqual(restoredCourse.id, fixtureIDs.courseID)
        XCTAssertEqual(restoredCourse.grade, .aMinus)
        XCTAssertEqual(restoredCourse.targetGrade, .a)
        XCTAssertEqual(try restoreContext.fetch(FetchDescriptor<GradeItem>()).first?.earnedPoints, Decimal(18))
        XCTAssertEqual(try restoreContext.fetch(FetchDescriptor<GradingCategory>()).first?.weight, Decimal(40))
        XCTAssertEqual(try restoreContext.fetch(FetchDescriptor<GradeScale>()).first?.boundaries.first?.minimumPercentage, Decimal(93))
        XCTAssertEqual(try restoreContext.fetch(FetchDescriptor<ForecastScenario>()).first?.itemAssumptions[fixtureIDs.itemID], Decimal(88))
        XCTAssertEqual(restoredScenario.targetGPA, Decimal(string: "3.75"))
        XCTAssertEqual(restoredScenario.selectedCourseIDs, Set([fixtureIDs.courseID]))
        XCTAssertEqual(restoredScenario.assumedGrades[fixtureIDs.courseID], .a)
        XCTAssertEqual(restoredPreferencesValue.language, .simplifiedChinese)
        XCTAssertTrue(restoredPreferencesValue.privacyLockEnabled)
        XCTAssertEqual(restoredPreferencesValue.privacyLockDelay, .fiveMinutes)
        XCTAssertEqual(restoredPreferencesValue.preferredAppIcon, .tinted)
        XCTAssertTrue(restoredPreferencesValue.onboardingCompleted)
        XCTAssertTrue(restoredPreferencesValue.demoDataLoaded)
        XCTAssertEqual(restoredPolicy.importStatus, .confirmed)
        let restoredSource = try XCTUnwrap(SyllabusSourceStore.source(for: fixtureIDs.policyID))
        XCTAssertEqual(restoredSource.sourceText, sourceText)
        XCTAssertEqual(restoredSource.pagesData, sourcePages)
    }

    func testV11SafeDefaultsDoNotTreatUngradedAsZero() {
        let policy = CourseGradingPolicy()
        let item = GradeItem(title: "Quiz 1", possiblePoints: 10)

        XCTAssertEqual(policy.missingItemPolicy, .excludeUntilGraded)
        XCTAssertFalse(policy.missingPolicyConfirmed)
        XCTAssertNil(item.earnedPoints)
        XCTAssertEqual(item.status, .upcoming)
    }

    private struct V141FixtureIDs {
        let termID: UUID
        let courseID: UUID
        let policyID: UUID
        let categoryID: UUID
        let itemID: UUID
    }

    private func createV141Store(at storeURL: URL) throws -> V141FixtureIDs {
        let ids = V141FixtureIDs(
            termID: UUID(), courseID: UUID(), policyID: UUID(), categoryID: UUID(), itemID: UUID())
        let configuration = ModelConfiguration(
            "AggieGPA", schema: PersistentStoreService.v4Schema, url: storeURL)
        let container = try ModelContainer(
            for: PersistentStoreService.v4Schema,
            configurations: [configuration])
        let context = ModelContext(container)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let dueDate = Date(timeIntervalSince1970: 1_700_100_000)

        let term = AcademicTerm(
            id: ids.termID,
            academicYear: "2025–2026",
            termType: .winter,
            displayName: "Winter 2026",
            startDate: createdAt,
            endDate: updatedAt,
            isIncludedInCumulativeGPA: true,
            notes: "Legacy term notes",
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortOrder: 1)
        let course = CourseRecord(
            id: ids.courseID,
            courseCode: "CHE 002A",
            courseTitle: "General Chemistry",
            units: 5,
            grade: .aMinus,
            gradingBasis: .letter,
            institution: .ucDavis,
            term: term,
            isMajorCourse: true,
            isUpperDivision: false,
            isIncludedInGPA: true,
            isTransferCourse: false,
            isRepeatCourse: false,
            targetGrade: .a,
            notes: "Official grade remains authoritative",
            customColor: "#DDAA33",
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDemoData: false)
        term.courses = [course]

        let policy = CourseGradingPolicy(
            id: ids.policyID,
            course: course,
            gradingMethod: .weightedCategories,
            normalizeCurrentGrade: false,
            missingItemPolicy: .excludeUntilGraded,
            missingPolicyConfirmed: true,
            targetPercentage: 90,
            targetLetterGrade: .aMinus,
            syllabusImportSource: .pdf,
            importStatus: .confirmed,
            manualReviewReason: "Check the final-exam rule",
            lastCalculatedAt: updatedAt,
            createdAt: createdAt,
            updatedAt: updatedAt)
        let category = GradingCategory(
            id: ids.categoryID,
            course: course,
            name: "Homework",
            categoryType: .homework,
            weight: 40,
            calculationMode: .totalPoints,
            dropLowestCount: 1,
            isExtraCredit: false,
            isIncluded: true,
            sortOrder: 0,
            createdAt: createdAt,
            updatedAt: updatedAt)
        let item = GradeItem(
            id: ids.itemID,
            course: course,
            category: category,
            title: "Problem Set 1",
            dueDate: dueDate,
            earnedPoints: 18,
            possiblePoints: 20,
            status: .graded,
            isIncluded: true,
            isExtraCredit: false,
            isDropped: false,
            isExcused: false,
            multiplier: 1,
            notes: "Imported assignment record",
            reminderEnabled: true,
            reminderLeadTime: .threeDays,
            notificationIdentifier: "migration-" + ids.itemID.uuidString,
            createdAt: createdAt,
            updatedAt: updatedAt)
        let scale = GradeScale(
            course: course,
            name: "CHE syllabus scale",
            boundaries: [
                .init(letter: .a, minimumPercentage: 93),
                .init(letter: .aMinus, minimumPercentage: 90),
            ],
            isLetterPredictionEnabled: true,
            isCommonTemplate: false,
            curveNote: "No curve recorded",
            requiresManualReview: false,
            createdAt: createdAt,
            updatedAt: updatedAt)
        let forecast = ForecastScenario(
            course: course,
            name: "Expected",
            kind: .expected,
            assumedRemainingPercentage: 85,
            itemAssumptions: [ids.itemID: 88],
            isSelectedForGPAForecast: true,
            createdAt: createdAt,
            updatedAt: updatedAt)
        let template = CourseTemplate(
            name: "Chemistry Template",
            sourceCourseID: ids.courseID,
            gradingMethod: .weightedCategories,
            normalizeCurrentGrade: false,
            missingItemPolicy: .excludeUntilGraded,
            missingPolicyConfirmed: true,
            targetPercentage: 90,
            targetLetterGrade: .aMinus,
            categories: [
                .init(
                    name: "Homework",
                    categoryType: .homework,
                    weight: 40,
                    calculationMode: .totalPoints,
                    dropLowestCount: 1)
            ],
            gradeScale: .init(
                name: "CHE syllabus scale",
                boundaries: scale.boundaries,
                isLetterPredictionEnabled: true,
                isCommonTemplate: false,
                curveNote: "No curve recorded",
                requiresManualReview: false),
            defaultReminderEnabled: true,
            defaultReminderLeadTime: .oneWeek,
            isBuiltIn: false,
            createdAt: createdAt,
            updatedAt: updatedAt)
        let reminderDefaults = CourseReminderDefaults(
            courseID: ids.courseID,
            reminderEnabled: true,
            reminderLeadTime: .threeDays,
            customReminderDate: dueDate,
            createdAt: createdAt,
            updatedAt: updatedAt)
        let siriSettings = SiriAccessSettings(
            isSiriAccessEnabled: true,
            allowAssignmentSummaries: true,
            allowDetailedScores: true,
            allowGPAResponses: true,
            allowCreatingDrafts: false,
            createdAt: createdAt,
            updatedAt: updatedAt)
        let scenario = PlannerScenario(
            name: "Winter goal",
            scenarioType: .expected,
            associatedTerm: term,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortOrder: 0,
            targetGPA: Decimal(string: "3.75"),
            selectedCourseIDs: Set([ids.courseID]),
            assumedGrades: [ids.courseID: .a])
        let simulated = SimulatedCourse(
            sourceCourseID: ids.courseID,
            courseCode: "CHE 002A",
            units: 5,
            grade: .a,
            isIncludedInGPA: true,
            isMajorCourse: true,
            isUpperDivision: false,
            confidence: 2,
            notes: "Projected course",
            scenario: scenario)
        scenario.simulatedCourses.append(simulated)
        let preferences = UserPreferences(
            displayName: "Student",
            major: "Chemistry",
            targetGPA: Decimal(string: "3.8")!,
            firstAcademicYear: "2022–2023",
            decimalPrecision: 2,
            appearance: .dark,
            language: .simplifiedChinese,
            hapticsEnabled: false,
            privacyLockEnabled: true,
            privacyLockDelay: .fiveMinutes,
            showMajorGPA: true,
            showUpperDivisionGPA: false,
            showRepeatSummary: true,
            preferredAppIcon: .tinted,
            defaultGradingBasis: .letter,
            onboardingCompleted: true,
            demoDataLoaded: true)

        context.insert(term)
        context.insert(course)
        context.insert(policy)
        context.insert(category)
        context.insert(item)
        context.insert(scale)
        context.insert(forecast)
        context.insert(template)
        context.insert(reminderDefaults)
        context.insert(siriSettings)
        context.insert(scenario)
        scenario.simulatedCourses.forEach(context.insert)
        context.insert(preferences)
        try context.save()
        return ids
    }

    private func makeTemporaryFixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AggieGPA-MigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func createV1Store(at storeURL: URL, termID: UUID, courseID: UUID) throws {
        let configuration = ModelConfiguration("AggieGPA", schema: PersistentStoreService.v1Schema, url: storeURL)
        let container = try ModelContainer(
            for: PersistentStoreService.v1Schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let term = AcademicTerm(id: termID, academicYear: "2026–2027", termType: .fall, displayName: "Fall 2026")
        let course = CourseRecord(id: courseID, courseCode: "CHE 002A", courseTitle: "General Chemistry",
                                  units: 5, grade: .aMinus, term: term, isMajorCourse: true)
        term.courses = [course]
        let preferences = UserPreferences(displayName: "Student", targetGPA: Decimal(string: "3.8")!,
                                          onboardingCompleted: true)
        context.insert(term)
        context.insert(course)
        context.insert(preferences)
        try context.save()
    }
}
