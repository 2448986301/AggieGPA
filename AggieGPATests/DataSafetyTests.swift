import SwiftData
import XCTest
@testable import AggieGPA

@MainActor
final class DataSafetyTests: XCTestCase {
    func testJSONExportImportRoundTripPreservesData() throws {
        let preferences = UserPreferences(displayName: "Student")
        let term = AcademicTerm(academicYear: "2026–2027", termType: .fall, displayName: "Fall 2026")
        let course = CourseRecord(courseCode: "CHE 002A", courseTitle: "General Chemistry",
                                  units: 5, grade: .aMinus, term: term, isMajorCourse: true)
        term.courses = [course]
        let envelope = BackupService.makeEnvelope(terms: [term], scenarios: [], preferences: preferences)
        let decoded = try BackupService.decode(BackupService.encode(envelope))
        XCTAssertEqual(decoded.terms.first?.id, envelope.terms.first?.id)
        XCTAssertEqual(decoded.terms.first?.academicYear, envelope.terms.first?.academicYear)
        XCTAssertEqual(decoded.terms.first?.termType, envelope.terms.first?.termType)
        XCTAssertEqual(decoded.terms.first?.displayName, envelope.terms.first?.displayName)
        XCTAssertEqual(decoded.terms.first?.createdAt.timeIntervalSince1970 ?? 0,
                       envelope.terms.first?.createdAt.timeIntervalSince1970 ?? 0, accuracy: 0.000_001)
        XCTAssertEqual(decoded.courses.first?.id, envelope.courses.first?.id)
        XCTAssertEqual(decoded.courses.first?.termID, envelope.courses.first?.termID)
        XCTAssertEqual(decoded.courses.first?.courseCode, envelope.courses.first?.courseCode)
        XCTAssertEqual(decoded.courses.first?.units, envelope.courses.first?.units)
        XCTAssertEqual(decoded.courses.first?.grade, envelope.courses.first?.grade)
        XCTAssertEqual(decoded.courses.first?.isMajorCourse, envelope.courses.first?.isMajorCourse)
        XCTAssertEqual(decoded.preferences, envelope.preferences)
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
        let envelope = BackupService.makeEnvelope(terms: [term], scenarios: [], preferences: preferences)
        let preview = BackupService.preview(envelope, existingTerms: [term])
        XCTAssertEqual(preview.duplicateTermCount, 1)
        XCTAssertEqual(preview.duplicateCourseCount, 1)
    }

    func testCSVContainsRequiredFieldsAndEscapesNotes() {
        let term = AcademicTerm(academicYear: "2026–2027", termType: .fall, displayName: "Fall 2026")
        let course = CourseRecord(courseCode: "PSC 001", courseTitle: "Psychology, General",
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
        let recreated = CourseRecord(courseCode: original.courseCode, courseTitle: original.courseTitle,
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

    func testDemoDataCanBeFullyCleared() throws {
        let schema = Schema([AcademicTerm.self, CourseRecord.self, PlannerScenario.self,
                             SimulatedCourse.self, GradeCategory.self, CourseGradePlan.self,
                             UserPreferences.self, BackupSnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let preferences = UserPreferences()
        context.insert(preferences)
        DemoDataService.load(into: context, preferences: preferences)
        let loaded = try context.fetch(FetchDescriptor<CourseRecord>())
        XCTAssertEqual(loaded.count, 4)
        DemoDataService.clear(from: context, courses: loaded, preferences: preferences)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CourseRecord>()).isEmpty)
        XCTAssertFalse(preferences.demoDataLoaded)
    }
}

@MainActor
private struct FailingAuthenticator: DeviceAuthenticating {
    func authenticate(reason: String) async -> Bool { false }
}
