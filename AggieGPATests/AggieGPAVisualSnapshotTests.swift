import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import AggieGPA

@MainActor
final class AggieGPAVisualSnapshotTests: XCTestCase {
    func testActivityCapsulesStayCompactInEnglishLightOnIPhone() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "en",
                colorScheme: .light,
                width: 390,
                height: 844
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-english-light"
        )
    }

    func testActivityCapsulesStayCompactInSimplifiedChineseDarkOnIPhone() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "zh-Hans",
                colorScheme: .dark,
                width: 390,
                height: 844
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-zh-Hans-dark"
        )
    }

    func testActivityCapsulesStayCompactInSimplifiedChineseLightOnIPhone() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "zh-Hans",
                colorScheme: .light,
                width: 390,
                height: 844
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-zh-Hans-light"
        )
    }

    func testActivityCapsulesStayCompactInEnglishDarkOnIPhone() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "en",
                colorScheme: .dark,
                width: 390,
                height: 844
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-english-dark"
        )
    }

    func testActivityWorkspaceFitsAnIPadLandscapeSurface() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "en",
                colorScheme: .light,
                width: 1024,
                height: 768
            ),
            as: .image(layout: .fixed(width: 1024, height: 768)),
            named: "ipad-landscape-english-light"
        )
    }

    func testActivityWorkspaceFitsAnIPadPortraitSurface() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "zh-Hans",
                colorScheme: .light,
                width: 768,
                height: 1024
            ),
            as: .image(layout: .fixed(width: 768, height: 1024)),
            named: "ipad-portrait-zh-Hans-light"
        )
    }

    func testActivityCapsulesRemainReadableAtAccessibilityDynamicType() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "zh-Hans",
                colorScheme: .dark,
                width: 390,
                height: 844,
                dynamicTypeSize: .accessibility3,
                accessibilityOverrides: .init(reduceMotion: true)
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-zh-Hans-dark-accessibility3"
        )
    }

    func testActivityCapsulesUseAnOpaqueAccessibleFallbackWhenTransparencyIsReduced() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "zh-Hans",
                colorScheme: .dark,
                width: 1024,
                height: 768,
                accessibilityOverrides: .init(reduceMotion: true, reduceTransparency: true)
            ),
            as: .image(layout: .fixed(width: 1024, height: 768)),
            named: "ipad-landscape-zh-Hans-dark-reduce-transparency"
        )
    }

    func testActivityCapsuleRemainsReadableWithHighContrastAndAccessibilityText() {
        assertSnapshot(
            of: activityReview(
                localeIdentifier: "zh-Hans",
                colorScheme: .dark,
                width: 390,
                height: 844,
                dynamicTypeSize: .accessibility3,
                accessibilityOverrides: .init(reduceMotion: true, reduceTransparency: true)
            )
            .environment(\._accessibilityReduceMotion, true)
            .environment(\._accessibilityReduceTransparency, true)
            .environment(\._colorSchemeContrast, .increased),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-zh-Hans-dark-accessibility3-high-contrast",
            record: .missing
        )
    }

    func testGPAOverviewRemainsReadableWithAccessibilitySettingsOnIPhone() throws {
        let fixture = try makeSnapshotFixture(language: .simplifiedChinese, appearance: .light)
        assertSnapshot(
            of: accessibleAppSurface(
                MainTabView(preferences: fixture.preferences, initialSelection: .planner),
                fixture: fixture,
                localeIdentifier: "zh-Hans",
                colorScheme: .light,
                width: 390,
                height: 844,
                horizontalSizeClass: .compact,
                dynamicTypeSize: .accessibility3,
                accessibilityReduceMotion: true,
                accessibilityReduceTransparency: true,
                colorSchemeContrast: .increased,
                differentiateWithoutColor: true,
                legibilityWeight: .bold
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-gpa-zh-Hans-light-accessibility3-high-contrast",
            record: .missing
        )
    }

    func testCourseDetailUsesVisibleBoundariesWhenButtonShapesAreEnabled() throws {
        let fixture = try makeSnapshotFixture(language: .simplifiedChinese, appearance: .light)
        assertSnapshot(
            of: appSurface(
                NavigationStack {
                    CourseDetailView(course: fixture.chemistry, preferences: fixture.preferences)
                },
                fixture: fixture,
                localeIdentifier: "zh-Hans",
                colorScheme: .light,
                width: 390,
                height: 844,
                horizontalSizeClass: .compact
            )
            .environment(\._accessibilityReduceMotion, true)
            .environment(\._accessibilityShowButtonShapes, true),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-course-detail-zh-Hans-button-shapes"
        )
    }

    func testTodaySurfaceStaysStableInEnglishLightOnIPhone() throws {
        let fixture = try makeSnapshotFixture(language: .english, appearance: .light)
        assertSnapshot(
            of: appSurface(
                MainTabView(preferences: fixture.preferences, initialSelection: .dashboard),
                fixture: fixture,
                localeIdentifier: "en",
                colorScheme: .light,
                width: 390,
                height: 844,
                horizontalSizeClass: .compact
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-today-english-light"
        )
    }

    func testGPAOverviewStaysStableInSimplifiedChineseDarkOnIPhone() throws {
        let fixture = try makeSnapshotFixture(language: .simplifiedChinese, appearance: .dark)
        assertSnapshot(
            of: appSurface(
                MainTabView(preferences: fixture.preferences, initialSelection: .planner),
                fixture: fixture,
                localeIdentifier: "zh-Hans",
                colorScheme: .dark,
                width: 390,
                height: 844,
                horizontalSizeClass: .compact
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-gpa-zh-Hans-dark"
        )
    }

    func testCoursesSurfaceStaysStableInSimplifiedChineseLightOnIPhone() throws {
        let fixture = try makeSnapshotFixture(language: .simplifiedChinese, appearance: .light)
        assertSnapshot(
            of: appSurface(
                MainTabView(preferences: fixture.preferences, initialSelection: .quarters),
                fixture: fixture,
                localeIdentifier: "zh-Hans",
                colorScheme: .light,
                width: 390,
                height: 844,
                horizontalSizeClass: .compact
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-courses-zh-Hans-light"
        )
    }

    func testSettingsSurfaceStaysStableInEnglishDarkOnIPhone() throws {
        let fixture = try makeSnapshotFixture(language: .english, appearance: .dark)
        assertSnapshot(
            of: appSurface(
                MainTabView(preferences: fixture.preferences, initialSelection: .settings),
                fixture: fixture,
                localeIdentifier: "en",
                colorScheme: .dark,
                width: 390,
                height: 844,
                horizontalSizeClass: .compact
            ),
            as: .image(layout: .fixed(width: 390, height: 844)),
            named: "iphone-settings-english-dark"
        )
    }

    private func activityReview(
        localeIdentifier: String,
        colorScheme: ColorScheme,
        width: CGFloat,
        height: CGFloat,
        dynamicTypeSize: DynamicTypeSize = .medium,
        accessibilityOverrides: AcademicAIActivityAccessibilityOverrides = .init()
    ) -> some View {
        AcademicAIActivityReviewView()
            .frame(width: width, height: height)
            .environment(\.locale, Locale(identifier: localeIdentifier))
            .environment(\.colorScheme, colorScheme)
            .environment(\.verticalSizeClass, height >= width ? .regular : .compact)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.academicAIActivityAccessibilityOverrides, accessibilityOverrides)
            .orbFrozenTime(0)
    }

    private struct SnapshotFixture {
        let container: ModelContainer
        let preferences: UserPreferences
        let chemistry: CourseRecord
        let referenceDate: Date
    }

    private func appSurface<Content: View>(
        _ content: Content,
        fixture: SnapshotFixture,
        localeIdentifier: String,
        colorScheme: ColorScheme,
        width: CGFloat,
        height: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass
    ) -> some View {
        content
            .frame(width: width, height: height)
            .modelContainer(fixture.container)
            .environment(\.locale, Locale(identifier: localeIdentifier))
            .environment(\.colorScheme, colorScheme)
            .environment(\.horizontalSizeClass, horizontalSizeClass)
            .environment(\.verticalSizeClass, height >= width ? .regular : .compact)
            .environment(\.todayReferenceDate, fixture.referenceDate)
            .orbFrozenTime(0)
    }

    private func accessibleAppSurface<Content: View>(
        _ content: Content,
        fixture: SnapshotFixture,
        localeIdentifier: String,
        colorScheme: ColorScheme,
        width: CGFloat,
        height: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass,
        dynamicTypeSize: DynamicTypeSize,
        accessibilityReduceMotion: Bool,
        accessibilityReduceTransparency: Bool,
        colorSchemeContrast: ColorSchemeContrast,
        differentiateWithoutColor: Bool,
        legibilityWeight: LegibilityWeight?
    ) -> some View {
        appSurface(
            content,
            fixture: fixture,
            localeIdentifier: localeIdentifier,
            colorScheme: colorScheme,
            width: width,
            height: height,
            horizontalSizeClass: horizontalSizeClass
        )
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\._accessibilityReduceMotion, accessibilityReduceMotion)
        .environment(\._accessibilityReduceTransparency, accessibilityReduceTransparency)
        .environment(\._colorSchemeContrast, colorSchemeContrast)
        .environment(\._accessibilityDifferentiateWithoutColor, differentiateWithoutColor)
        .environment(\.legibilityWeight, legibilityWeight)
    }

    private func makeSnapshotFixture(
        language: AppLanguage,
        appearance: AppAppearance
    ) throws -> SnapshotFixture {
        let configuration = ModelConfiguration(
            "AggieGPASnapshotTests",
            schema: PersistentStoreService.v4Schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: PersistentStoreService.v4Schema,
            migrationPlan: AggieGPAMigrationPlan.self,
            configurations: [configuration]
        )
        let context = container.mainContext
        let preferences = UserPreferences(
            displayName: "Alex",
            major: "Biological Sciences",
            targetGPA: 3.5,
            firstAcademicYear: "2026–2027",
            appearance: appearance,
            language: language,
            onboardingCompleted: true
        )
        context.insert(preferences)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let term = AcademicTerm(
            academicYear: "2026–2027",
            termType: .fall,
            displayName: "Fall 2026",
            startDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)),
            endDate: calendar.date(from: DateComponents(year: 2026, month: 12, day: 11)),
            sortOrder: 0
        )
        context.insert(term)

        let chemistry = CourseRecord(
            courseCode: "CHE 002A",
            courseTitle: "General Chemistry",
            units: 5,
            grade: .noGrade,
            term: term,
            isMajorCourse: true,
            isUpperDivision: false
        )
        let biology = CourseRecord(
            courseCode: "BIS 002B",
            courseTitle: "Introduction to Biology",
            units: 5,
            grade: .bPlus,
            term: term,
            isMajorCourse: true,
            isUpperDivision: false
        )
        let psychology = CourseRecord(
            courseCode: "PSC 001",
            courseTitle: "General Psychology",
            units: 4,
            grade: .aMinus,
            term: term
        )
        [chemistry, biology, psychology].forEach(context.insert)

        let policy = CourseGradingPolicy(
            course: chemistry,
            targetPercentage: 90,
            syllabusImportSource: .pastedText,
            importStatus: .confirmed
        )
        let scale = GradeScale(
            course: chemistry,
            name: "Common Scale Template",
            boundaries: [
                GradeScaleBoundary(letter: .a, minimumPercentage: 93),
                GradeScaleBoundary(letter: .aMinus, minimumPercentage: 90),
                GradeScaleBoundary(letter: .bPlus, minimumPercentage: 87),
                GradeScaleBoundary(letter: .b, minimumPercentage: 83),
                GradeScaleBoundary(letter: .c, minimumPercentage: 70),
                GradeScaleBoundary(letter: .f, minimumPercentage: 0)
            ],
            isCommonTemplate: true
        )
        let homework = GradingCategory(
            course: chemistry,
            name: "Homework",
            categoryType: .homework,
            weight: 50,
            sortOrder: 0
        )
        let finalExam = GradingCategory(
            course: chemistry,
            name: "Final Exam",
            categoryType: .finalExam,
            weight: 50,
            sortOrder: 1
        )
        let gradedHomework = GradeItem(
            course: chemistry,
            category: homework,
            title: "Homework 1",
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)),
            earnedPoints: 18,
            possiblePoints: 20,
            status: .graded
        )
        let upcomingFinal = GradeItem(
            course: chemistry,
            category: finalExam,
            title: "Final Exam",
            dueDate: calendar.date(from: DateComponents(year: 2026, month: 12, day: 10)),
            possiblePoints: 100,
            status: .upcoming
        )
        let forecast = ForecastScenario(
            course: chemistry,
            name: "Planned",
            kind: .expected,
            assumedRemainingPercentage: 87,
            isSelectedForGPAForecast: true
        )
        context.insert(policy)
        context.insert(scale)
        context.insert(homework)
        context.insert(finalExam)
        context.insert(gradedHomework)
        context.insert(upcomingFinal)
        context.insert(forecast)
        try context.save()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27))!
        return SnapshotFixture(
            container: container,
            preferences: preferences,
            chemistry: chemistry,
            referenceDate: referenceDate
        )
    }
}
