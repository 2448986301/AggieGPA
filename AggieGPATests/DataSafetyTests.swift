import SwiftData
import XCTest

@testable import AggieGPA

@MainActor
final class DataSafetyTests: XCTestCase {
  func testJSONExportImportRoundTripPreservesData() throws {
    let preferences = UserPreferences(displayName: "Student")
    let term = AcademicTerm(academicYear: "2026–2027", termType: .fall, displayName: "Fall 2026")
    let course = CourseRecord(
      courseCode: "CHE 002A", courseTitle: "General Chemistry",
      units: 5, grade: .aMinus, term: term, isMajorCourse: true)
    term.courses = [course]
    let envelope = BackupService.makeEnvelope(
      terms: [term], scenarios: [], preferences: preferences)
    let decoded = try BackupService.decode(BackupService.encode(envelope))
    XCTAssertEqual(decoded.terms.first?.id, envelope.terms.first?.id)
    XCTAssertEqual(decoded.terms.first?.academicYear, envelope.terms.first?.academicYear)
    XCTAssertEqual(decoded.terms.first?.termType, envelope.terms.first?.termType)
    XCTAssertEqual(decoded.terms.first?.displayName, envelope.terms.first?.displayName)
    XCTAssertEqual(
      decoded.terms.first?.createdAt.timeIntervalSince1970 ?? 0,
      envelope.terms.first?.createdAt.timeIntervalSince1970 ?? 0, accuracy: 0.000_001)
    XCTAssertEqual(decoded.courses.first?.id, envelope.courses.first?.id)
    XCTAssertEqual(decoded.courses.first?.termID, envelope.courses.first?.termID)
    XCTAssertEqual(decoded.courses.first?.courseCode, envelope.courses.first?.courseCode)
    XCTAssertEqual(decoded.courses.first?.units, envelope.courses.first?.units)
    XCTAssertEqual(decoded.courses.first?.grade, envelope.courses.first?.grade)
    XCTAssertEqual(decoded.courses.first?.isMajorCourse, envelope.courses.first?.isMajorCourse)
    XCTAssertEqual(decoded.preferences, envelope.preferences)
  }

  func testV2BackupPreservesGradebookReminderForecastAndSiriSettings() throws {
    let preferences = UserPreferences(displayName: "Student")
    let term = AcademicTerm(academicYear: "2026–2027", termType: .fall)
    let course = CourseRecord(courseCode: "CHE 002A", units: 5, grade: .inProgress, term: term)
    term.courses = [course]
    let policy = CourseGradingPolicy(course: course, targetPercentage: 90)
    let category = GradingCategory(
      course: course, name: "Homework", categoryType: .homework, weight: 100)
    let item = GradeItem(
      course: course, category: category, title: "Homework 1", dueDate: .now,
      earnedPoints: 18, possiblePoints: 20, status: .graded,
      reminderEnabled: true, reminderLeadTime: .threeDays)
    let scale = GradeScale(
      course: course, name: "Syllabus", boundaries: [.init(letter: .a, minimumPercentage: 93)])
    let forecast = ForecastScenario(
      course: course, name: "Expected", kind: .expected,
      assumedRemainingPercentage: 85, isSelectedForGPAForecast: true)
    let siri = SiriAccessSettings(isSiriAccessEnabled: true, allowAssignmentSummaries: true)
    let envelope = BackupService.makeEnvelope(
      terms: [term], scenarios: [], preferences: preferences,
      policies: [policy], categories: [category], items: [item],
      scales: [scale], forecasts: [forecast], siriSettings: siri)
    let decoded = try BackupService.decode(BackupService.encode(envelope))
    XCTAssertEqual(decoded.schemaVersion, 2)
    XCTAssertEqual(decoded.gradingPolicies?.first?.targetPercentage, 90)
    XCTAssertEqual(decoded.gradeItems?.first?.reminderLeadTime, .threeDays)
    XCTAssertEqual(decoded.forecastScenarios?.first?.isSelectedForGPAForecast, true)
    XCTAssertEqual(decoded.siriSettings?.allowAssignmentSummaries, true)
  }

  func testV1BackupStillDecodesWithEmptyV11Collections() throws {
    let envelope = BackupService.makeEnvelope(
      terms: [], scenarios: [], preferences: UserPreferences())
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: BackupService.encode(envelope)) as? [String: Any])
    json["schemaVersion"] = 1
    [
      "gradingPolicies", "gradingCategories", "gradeItems", "gradeScales", "forecastScenarios",
      "siriSettings",
    ].forEach { json.removeValue(forKey: $0) }
    let decoded = try BackupService.decode(try JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(decoded.schemaVersion, 1)
    XCTAssertNil(decoded.gradeItems)
  }

  func testReplaceImportRestoresV11RelationshipsAndRemovesPreviousAcademicData() throws {
    let sourceTerm = AcademicTerm(academicYear: "2027–2028", termType: .winter)
    let sourceCourse = CourseRecord(courseCode: "BIS 002A", units: 5, grade: .inProgress, term: sourceTerm)
    sourceTerm.courses = [sourceCourse]
    let policy = CourseGradingPolicy(course: sourceCourse, targetPercentage: 92)
    let category = GradingCategory(course: sourceCourse, name: "Exams", categoryType: .midterm, weight: 100)
    let item = GradeItem(course: sourceCourse, category: category, title: "Midterm", earnedPoints: 88,
                         possiblePoints: 100, status: .graded, reminderEnabled: true)
    let forecast = ForecastScenario(course: sourceCourse, name: "Expected", kind: .expected,
                                    assumedRemainingPercentage: 90, isSelectedForGPAForecast: true)
    let envelope = BackupService.makeEnvelope(
      terms: [sourceTerm], scenarios: [], preferences: UserPreferences(displayName: "Imported"),
      policies: [policy], categories: [category], items: [item], forecasts: [forecast])

    let container = PersistentStoreService.makeContainer(inMemory: true).container
    let context = ModelContext(container)
    let oldTerm = AcademicTerm(academicYear: "2026–2027", termType: .fall)
    let oldCourse = CourseRecord(courseCode: "OLD 001", units: 4, grade: .a, term: oldTerm)
    oldTerm.courses = [oldCourse]
    let destinationPreferences = UserPreferences(displayName: "Before")
    context.insert(oldTerm)
    context.insert(oldCourse)
    context.insert(destinationPreferences)
    try context.save()

    try BackupService.apply(envelope, mode: .replace, context: context,
                            existingTerms: [oldTerm], existingScenarios: [], preferences: destinationPreferences)

    let importedCourses = try context.fetch(FetchDescriptor<CourseRecord>())
    let importedItems = try context.fetch(FetchDescriptor<GradeItem>())
    XCTAssertEqual(importedCourses.map(\.courseCode), ["BIS 002A"])
    XCTAssertEqual(importedItems.first?.course?.id, sourceCourse.id)
    XCTAssertEqual(importedItems.first?.category?.id, category.id)
    XCTAssertEqual(try context.fetch(FetchDescriptor<ForecastScenario>()).first?.course?.id, sourceCourse.id)
    XCTAssertEqual(destinationPreferences.displayName, "Imported")
  }

  func testCorruptedJSONDoesNotMutateExistingData() {
    let term = AcademicTerm(academicYear: "2026–2027", termType: .fall)
    let before = [term]
    XCTAssertThrowsError(try BackupService.decode(Data("{broken".utf8)))
    XCTAssertEqual(before.count, 1)
    XCTAssertEqual(before[0].id, term.id)
  }

  func testDuplicateImportDetection() {
    let preferences = UserPreferences()
    let term = AcademicTerm(academicYear: "2026–2027", termType: .fall)
    let course = CourseRecord(courseCode: "BIS 002B", units: 5, grade: .bPlus, term: term)
    term.courses = [course]
    let envelope = BackupService.makeEnvelope(
      terms: [term], scenarios: [], preferences: preferences)
    let preview = BackupService.preview(envelope, existingTerms: [term])
    XCTAssertEqual(preview.duplicateTermCount, 1)
    XCTAssertEqual(preview.duplicateCourseCount, 1)
  }

  func testCSVContainsRequiredFieldsAndEscapesNotes() {
    let term = AcademicTerm(academicYear: "2026–2027", termType: .fall, displayName: "Fall 2026")
    let course = CourseRecord(
      courseCode: "PSC 001", courseTitle: "Psychology, General",
      units: 4, grade: .a, term: term, notes: "Quoted \"note\"")
    term.courses = [course]
    let csv = CSVService.export(terms: [term])
    XCTAssertTrue(csv.contains("\"Academic Year\""))
    XCTAssertTrue(csv.contains("\"Course Code\""))
    XCTAssertTrue(csv.contains("\"Psychology, General\""))
    XCTAssertTrue(csv.contains("\"Quoted \"\"note\"\"\""))
  }

  func testDeletedCourseCanBeRecreatedForUndo() {
    let original = CourseRecord(courseCode: "UWP 007", courseTitle: "Writing", units: 4, grade: .b)
    let recreated = CourseRecord(
      courseCode: original.courseCode, courseTitle: original.courseTitle,
      units: original.units, grade: original.grade)
    XCTAssertEqual(recreated.courseCode, original.courseCode)
    XCTAssertEqual(recreated.units, original.units)
    XCTAssertEqual(recreated.grade, original.grade)
  }

  func testFailedAuthenticationDoesNotDeleteData() async {
    let service = PrivacyLockService(authenticator: FailingAuthenticator())
    let records = [CourseCalculationInput(courseCode: "CHE 002A", units: 5, grade: .a)]
    service.lockNow()
    await service.authenticate()
    XCTAssertTrue(service.isLocked)
    XCTAssertEqual(records.count, 1)
    XCTAssertNotNil(service.errorMessage)
  }

  func testImmediatePrivacyLockDoesNotAuthenticateRepeatedlyWhileActive() async {
    let authenticator = CountingAuthenticator()
    let service = PrivacyLockService(authenticator: authenticator)
    let preferences = UserPreferences(privacyLockEnabled: true, privacyLockDelay: .immediately)

    await service.handleForeground(preferences: preferences)
    await service.handleForeground(preferences: preferences)

    XCTAssertEqual(authenticator.attemptCount, 1)
    XCTAssertFalse(service.isLocked)
  }

  func testImmediatePrivacyLockAuthenticatesOnceAfterEachBackground() async {
    let authenticator = CountingAuthenticator()
    let service = PrivacyLockService(authenticator: authenticator)
    let preferences = UserPreferences(privacyLockEnabled: true, privacyLockDelay: .immediately)

    await service.handleForeground(preferences: preferences)
    service.prepareForBackground()
    await service.handleForeground(preferences: preferences)
    await service.handleForeground(preferences: preferences)

    XCTAssertEqual(authenticator.attemptCount, 2)
  }

  func testDemoDataCanBeFullyCleared() throws {
    let schema = Schema([
      AcademicTerm.self, CourseRecord.self, PlannerScenario.self,
      SimulatedCourse.self, GradeCategory.self, CourseGradePlan.self,
      UserPreferences.self, BackupSnapshot.self, CourseGradingPolicy.self,
      GradingCategory.self, GradeItem.self, GradeScale.self, ForecastScenario.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    let preferences = UserPreferences()
    let personalTerm = AcademicTerm(academicYear: "2026–2027", termType: .winter)
    let personalCourse = CourseRecord(courseCode: "UWP 001", units: 4, grade: .inProgress, term: personalTerm)
    context.insert(preferences)
    context.insert(personalTerm)
    context.insert(personalCourse)
    try context.save()
    DemoDataService.load(into: context, preferences: preferences)
    let loaded = try context.fetch(FetchDescriptor<CourseRecord>())
    XCTAssertEqual(loaded.count, 5)
    try DemoDataService.clear(from: context, courses: loaded, preferences: preferences)
    XCTAssertEqual(try context.fetch(FetchDescriptor<CourseRecord>()).map(\.courseCode), ["UWP 001"])
    XCTAssertTrue(try context.fetch(FetchDescriptor<CourseGradingPolicy>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<GradingCategory>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<GradeItem>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<GradeScale>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<ForecastScenario>()).isEmpty)
    XCTAssertFalse(preferences.demoDataLoaded)
  }
}

@MainActor
private struct FailingAuthenticator: DeviceAuthenticating {
  func authenticate(reason: String) async -> Bool { false }
}

@MainActor
private final class CountingAuthenticator: DeviceAuthenticating {
  private(set) var attemptCount = 0

  func authenticate(reason: String) async -> Bool {
    attemptCount += 1
    return true
  }
}
