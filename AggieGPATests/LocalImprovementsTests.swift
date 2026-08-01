import SwiftData
import XCTest

@testable import AggieGPA

@MainActor
final class LocalImprovementsTests: XCTestCase {
    func testCourseTemplateCreationCopiesStructureButNotGradeItemsOrNotes() throws {
        let container = PersistentStoreService.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let term = AcademicTerm(academicYear: "2026–2027", termType: .fall)
        let source = CourseRecord(
            courseCode: "CHE 002A", courseTitle: "Chemistry", units: 5, grade: .inProgress,
            term: term, notes: "Private source note"
        )
        let sourceCategory = GradingCategory(
            course: source, name: "Homework", categoryType: .homework, weight: 60,
            calculationMode: .weightedCategory
        )
        let duplicateCategory = GradingCategory(
            course: source, name: " homework ", categoryType: .homework, weight: 40,
            calculationMode: .weightedCategory, sortOrder: 1
        )
        let sourceItem = GradeItem(
            course: source, category: sourceCategory, title: "Homework 1", earnedPoints: 8,
            possiblePoints: 10, status: .graded, notes: "Private item note",
            reminderEnabled: true, reminderLeadTime: .threeDays
        )
        let scale = GradeScale(
            course: source, name: "Syllabus Scale",
            boundaries: [.init(letter: .a, minimumPercentage: 93)]
        )
        let template = CourseTemplateService.capture(
            name: "Chemistry Structure", course: source, policy: nil,
            categories: [sourceCategory, duplicateCategory], scale: scale, items: [sourceItem]
        )
        context.insert(term)
        context.insert(source)
        context.insert(sourceCategory)
        context.insert(duplicateCategory)
        context.insert(sourceItem)
        context.insert(scale)
        context.insert(template)
        try context.save()

        let created = try CourseTemplateService.createCourse(
            from: template, courseCode: "CHE 002B", courseTitle: "New Chemistry",
            units: 5, term: term, gradingBasis: .letter,
            copyCommonSettings: true, copyReminders: true, context: context
        )

        XCTAssertEqual(created.grade, .noGrade)
        XCTAssertEqual(created.notes, "")
        let defaults = try XCTUnwrap(try context.fetch(FetchDescriptor<CourseReminderDefaults>()).first { $0.courseID == created.id })
        XCTAssertTrue(defaults.reminderEnabled)
        XCTAssertEqual(defaults.reminderLeadTime, .threeDays)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GradeItem>()).filter { $0.course?.id == created.id }.count, 0)
        let createdCategories = try context.fetch(FetchDescriptor<GradingCategory>()).filter { $0.course?.id == created.id }
        XCTAssertEqual(createdCategories.count, 1)
        XCTAssertEqual(createdCategories.first?.name, "Homework")
        XCTAssertEqual(try context.fetch(FetchDescriptor<GradeScale>()).filter { $0.course?.id == created.id }.count, 1)
    }

    func testCourseTemplateRenameAndDeletePersistLocally() throws {
        let container = PersistentStoreService.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let template = CourseTemplate(name: "Old Name")
        context.insert(template)
        try context.save()

        template.name = "Renamed Template"
        template.isBuiltIn = false
        template.updatedAt = .now
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseTemplate>()).first?.name, "Renamed Template")
        XCTAssertFalse(try XCTUnwrap(try context.fetch(FetchDescriptor<CourseTemplate>()).first).isBuiltIn)

        context.delete(template)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<CourseTemplate>()).isEmpty)
    }

    func testBulkPreviewSupportsPresetsIntervalsAndIndividualCancellationWithoutWriting() throws {
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let configuration = BulkCreationConfiguration(
            prefix: "Lab", startNumber: 3, count: 3, intervalDays: 7,
            firstDueDate: firstDate, possiblePoints: 25,
            categoryName: "Labs", categoryID: nil,
            reminderEnabled: true, reminderLeadTime: .oneDay, customReminderDate: nil
        )
        var drafts = BulkCreationService.preview(configuration)
        XCTAssertEqual(drafts.map(\.title), ["Lab 3", "Lab 4", "Lab 5"])
        XCTAssertEqual(drafts[1].dueDate.timeIntervalSince(drafts[0].dueDate), 7 * 24 * 60 * 60, accuracy: 0.01)

        drafts[1].isIncluded = false
        XCTAssertEqual(drafts.filter(\.isIncluded).count, 2)

        let container = PersistentStoreService.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let course = CourseRecord(courseCode: "LAB 001", units: 2, grade: .inProgress)
        context.insert(course)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<GradeItem>()).isEmpty)
    }

    func testBulkCreationBlocksDuplicateNamesAndDatesAndCanUndoAsOneOperation() throws {
        let container = PersistentStoreService.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let course = CourseRecord(courseCode: "BIS 002", units: 4, grade: .inProgress)
        let category = GradingCategory(course: course, name: "Homework", weight: 100)
        let existing = GradeItem(
            course: course, category: category, title: "Homework 1",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000), possiblePoints: 10
        )
        context.insert(course)
        context.insert(category)
        context.insert(existing)
        try context.save()

        let configuration = BulkCreationConfiguration(
            prefix: "Homework", startNumber: 1, count: 2, intervalDays: 0,
            firstDueDate: existing.dueDate ?? .now, possiblePoints: 10,
            categoryName: "Homework", categoryID: category.id,
            reminderEnabled: false, reminderLeadTime: .oneDay, customReminderDate: nil
        )
        let drafts = BulkCreationService.preview(configuration)
        let validation = BulkCreationService.validate(drafts, existingItems: [existing])
        XCTAssertTrue(validation.hasBlockingDuplicates)
        XCTAssertGreaterThan(validation.duplicateDateCount, 0)
        XCTAssertThrowsError(try BulkCreationService.insert(drafts, course: course, categories: [category], context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<GradeItem>()).count, 1)

        let validConfiguration = BulkCreationConfiguration(
            prefix: "Quiz", startNumber: 1, count: 2, intervalDays: 7,
            firstDueDate: Date(timeIntervalSince1970: 1_800_100_000), possiblePoints: 20,
            categoryName: "Homework", categoryID: category.id,
            reminderEnabled: false, reminderLeadTime: .oneDay, customReminderDate: nil
        )
        let ids = try BulkCreationService.insert(
            BulkCreationService.preview(validConfiguration), course: course,
            categories: [category], context: context
        )
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GradeItem>()).count, 3)
        try BulkCreationService.remove(ids: ids, course: course, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GradeItem>()).count, 1)
    }

    func testAcademicInsightsUseDeterministicRulesAndExplainInsufficientData() {
        let course = CourseRecord(courseCode: "MAT 021A", units: 4, grade: .inProgress)
        let category = GradingCategory(course: course, name: "Homework", categoryType: .homework, weight: 80)
        let policy = CourseGradingPolicy(course: course, targetPercentage: 90)
        let scored = GradeItem(
            course: course, category: category, title: "Homework 1", earnedPoints: 50,
            possiblePoints: 100, status: .graded
        )
        let insights = AcademicInsightsService.makeInsights(
            course: course, policy: policy, categories: [category], items: [scored],
            scale: nil, forecast: nil, locale: Locale(identifier: "en_US_POSIX"), now: .now
        )
        let repeatedInsights = AcademicInsightsService.makeInsights(
            course: course, policy: policy, categories: [category], items: [scored],
            scale: nil, forecast: nil, locale: Locale(identifier: "en_US_POSIX"), now: .now
        )
        XCTAssertEqual(insights.map(\.id), repeatedInsights.map(\.id))
        XCTAssertTrue(insights.contains { $0.title == "Course weights need review" })
        XCTAssertTrue(insights.contains { $0.title == "Grade scale is incomplete" })
        XCTAssertTrue(insights.allSatisfy { !$0.calculationBasis.isEmpty })

        let emptyInsights = AcademicInsightsService.makeInsights(
            course: course, policy: policy, categories: [category], items: [],
            scale: nil, forecast: nil, locale: Locale(identifier: "en_US_POSIX"), now: .now
        )
        XCTAssertTrue(emptyInsights.contains { $0.title == "Not enough graded work yet" })
        XCTAssertFalse(emptyInsights.contains { $0.title == "Your target remains reachable" })
    }

    func testBackupPreviewAndRoundTripIncludeTemplatesAndCounts() throws {
        let preferences = UserPreferences(displayName: "Student")
        let term = AcademicTerm(academicYear: "2026–2027", termType: .fall)
        let course = CourseRecord(
            courseCode: "PSC 001", units: 4, grade: .inProgress, term: term
        )
        let category = GradingCategory(course: course, name: "Quizzes", categoryType: .quiz, weight: 100)
        let item = GradeItem(course: course, category: category, title: "Quiz 1", possiblePoints: 20)
        let template = CourseTemplate(
            name: "Quiz Course", sourceCourseID: course.id,
            categories: [CourseTemplateCategorySnapshot(name: "Quizzes", categoryType: .quiz, weight: 100)],
            defaultReminderEnabled: true, defaultReminderLeadTime: .oneWeek
        )
        let reminderDefaults = CourseReminderDefaults(
            courseID: course.id, reminderEnabled: true, reminderLeadTime: .oneWeek)
        let envelope = BackupService.makeEnvelope(
            terms: [term], courses: [course], scenarios: [], preferences: preferences,
            categories: [category], items: [item], templates: [template], reminderDefaults: [reminderDefaults]
        )
        let decoded = try BackupService.decode(BackupService.encode(envelope))
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.courseTemplates?.first?.name, "Quiz Course")
        XCTAssertEqual(decoded.courseReminderDefaults?.first?.reminderLeadTime, .oneWeek)

        let preview = BackupService.preview(
            envelope, existingTerms: [term], existingCourses: [course],
            existingItems: [item], existingTemplates: [template], existingReminderDefaults: [reminderDefaults]
        )
        XCTAssertEqual(preview.duplicateTermCount, 1)
        XCTAssertEqual(preview.duplicateCourseCount, 1)
        XCTAssertEqual(preview.duplicateItemCount, 1)
        XCTAssertEqual(preview.duplicateTemplateCount, 1)
        XCTAssertEqual(preview.duplicateReminderDefaultCount, 1)
        XCTAssertEqual(preview.newItemCount, 0)
    }

    func testBackupMergeUpdatesExistingDataAndAddsReminderDefaults() throws {
        let container = PersistentStoreService.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let destinationPreferences = UserPreferences(displayName: "Before")
        let destinationTermID = UUID()
        let destinationCourseID = UUID()
        let destinationTerm = AcademicTerm(id: destinationTermID, academicYear: "2026–2027", termType: .fall)
        let destinationCourse = CourseRecord(
            id: destinationCourseID, courseCode: "OLD 001", units: 4, grade: .inProgress, term: destinationTerm
        )
        context.insert(destinationPreferences)
        context.insert(destinationTerm)
        context.insert(destinationCourse)
        try context.save()

        let sourceTerm = AcademicTerm(id: destinationTermID, academicYear: "2026–2027", termType: .fall, displayName: "Fall 2026")
        let sourceCourse = CourseRecord(
            id: destinationCourseID, courseCode: "NEW 001", courseTitle: "Updated", units: 5,
            grade: .a, term: sourceTerm
        )
        let defaults = CourseReminderDefaults(courseID: destinationCourseID, reminderEnabled: true, reminderLeadTime: .threeDays)
        let envelope = BackupService.makeEnvelope(
            terms: [sourceTerm], courses: [sourceCourse], scenarios: [], preferences: UserPreferences(displayName: "Imported"),
            reminderDefaults: [defaults]
        )

        try BackupService.apply(
            envelope, mode: .merge, context: context,
            existingTerms: [destinationTerm], existingScenarios: [], preferences: destinationPreferences
        )

        let savedCourse = try XCTUnwrap(try context.fetch(FetchDescriptor<CourseRecord>()).first)
        XCTAssertEqual(savedCourse.courseCode, "NEW 001")
        XCTAssertEqual(savedCourse.units, 5)
        XCTAssertEqual(destinationPreferences.displayName, "Imported")
        let savedDefaults = try XCTUnwrap(try context.fetch(FetchDescriptor<CourseReminderDefaults>()).first)
        XCTAssertTrue(savedDefaults.reminderEnabled)
        XCTAssertEqual(savedDefaults.reminderLeadTime, .threeDays)
    }

    func testBackupFailureRollsBackCourseChanges() throws {
        let container = PersistentStoreService.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let preferences = UserPreferences(displayName: "Before")
        let term = AcademicTerm(academicYear: "2026–2027", termType: .fall)
        let course = CourseRecord(courseCode: "OLD 001", units: 4, grade: .inProgress, term: term)
        context.insert(preferences)
        context.insert(term)
        context.insert(course)
        try context.save()

        let importedTerm = AcademicTerm(id: term.id, academicYear: term.academicYear, termType: term.termType)
        let importedCourse = CourseRecord(id: course.id, courseCode: "CHANGED 001", units: 5, grade: .a, term: importedTerm)
        let duplicateTemplateID = UUID()
        let firstTemplate = CourseTemplate(id: duplicateTemplateID, name: "One")
        let secondTemplate = CourseTemplate(id: duplicateTemplateID, name: "Two")
        let envelope = BackupService.makeEnvelope(
            terms: [importedTerm], courses: [importedCourse], scenarios: [], preferences: UserPreferences(),
            templates: [firstTemplate, secondTemplate]
        )

        XCTAssertThrowsError(
            try BackupService.apply(
                envelope, mode: .merge, context: context,
                existingTerms: [term], existingScenarios: [], preferences: preferences
            )
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<CourseRecord>()).first?.courseCode, "OLD 001")
        XCTAssertTrue(try context.fetch(FetchDescriptor<CourseTemplate>()).isEmpty)
    }
}
