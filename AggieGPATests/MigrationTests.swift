import Foundation
import SwiftData
import XCTest
@testable import AggieGPA

@MainActor
final class MigrationTests: XCTestCase {
    func testV1DiskStoreMigratesAndPreservesOfficialRecords() throws {
        let fixture = try makeTemporaryFixtureDirectory()
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
        let configuration = ModelConfiguration("AggieGPA", schema: PersistentStoreService.v2Schema, url: storeURL)
        let container = try ModelContainer(for: PersistentStoreService.v2Schema,
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

    func testV11SafeDefaultsDoNotTreatUngradedAsZero() {
        let policy = CourseGradingPolicy()
        let item = GradeItem(title: "Quiz 1", possiblePoints: 10)

        XCTAssertEqual(policy.missingItemPolicy, .excludeUntilGraded)
        XCTAssertFalse(policy.missingPolicyConfirmed)
        XCTAssertNil(item.earnedPoints)
        XCTAssertEqual(item.status, .upcoming)
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
