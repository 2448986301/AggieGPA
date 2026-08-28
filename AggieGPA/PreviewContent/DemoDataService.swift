import Foundation
import SwiftData

@MainActor
enum DemoDataService {
    static func load(into context: ModelContext, preferences: UserPreferences) {
        if preferences.demoDataLoaded {
            supplementExistingDemoGradebooks(in: context)
            try? context.save()
            return
        }

        let term = AcademicTerm(
            academicYear: preferences.firstAcademicYear,
            termType: .fall,
            displayName: "Fall 2026",
            startDate: demoDate(month: 9, day: 21),
            endDate: demoDate(month: 12, day: 11),
            sortOrder: 0
        )
        context.insert(term)
        let samples: [(String, String, Decimal, CourseGrade, Bool, Bool)] = [
            ("CHE 002A", "General Chemistry", 5, .noGrade, true, false),
            // Demo coursework has not received Final Reports yet. Current
            // percentages come from the gradebook; Final/Projected remain
            // separate so every course exercises the same planning lifecycle.
            ("BIS 002B", "Introduction to Biology", 5, .noGrade, true, false),
            ("UWP 007", "Writing in Science", 4, .noGrade, false, false),
            ("PSC 001", "General Psychology", 4, .noGrade, false, false)
        ]
        var demoCourses: [CourseRecord] = []
        var chemistry: CourseRecord?
        for sample in samples {
            let course = CourseRecord(courseCode: sample.0, courseTitle: sample.1,
                                      units: sample.2, grade: sample.3, term: term,
                                      isMajorCourse: sample.4, isUpperDivision: sample.5,
                                      isDemoData: true)
            context.insert(course)
            demoCourses.append(course)
            if sample.0 == "CHE 002A" { chemistry = course }
        }
        if let chemistry {
            let chemistryPolicy = CourseGradingPolicy(
                course: chemistry,
                targetPercentage: 90,
                syllabusImportSource: .pastedText,
                importStatus: .confirmed
            )
            context.insert(chemistryPolicy)
            SyllabusSourceStore.save(
                sourceText: "Homework 20%. Labs 20%. Midterms 30%. Final Exam 30%. Late homework may be submitted within 48 hours with a 10% penalty.",
                pagesData: nil,
                source: .pastedText,
                for: chemistryPolicy.id
            )
            let scale = GradeScale(course: chemistry, name: "Common Scale Template", boundaries: standardScale, isCommonTemplate: true)
            context.insert(scale)
            let homework = GradingCategory(course: chemistry, name: "Homework", categoryType: .homework, weight: 20, sortOrder: 0)
            let labs = GradingCategory(course: chemistry, name: "Labs", categoryType: .lab, weight: 20, sortOrder: 1)
            let midterms = GradingCategory(course: chemistry, name: "Midterms", categoryType: .midterm, weight: 30, sortOrder: 2)
            let final = GradingCategory(course: chemistry, name: "Final Exam", categoryType: .finalExam, weight: 30, sortOrder: 3)
            [homework, labs, midterms, final].forEach(context.insert)
            context.insert(GradeItem(course: chemistry, category: homework, title: "Homework 1", dueDate: demoDate(month: 9, day: 25, hour: 23, minute: 59), earnedPoints: 18, possiblePoints: 20, status: .graded))
            context.insert(GradeItem(course: chemistry, category: homework, title: "Homework 2", dueDate: demoDate(month: 10, day: 2, hour: 23, minute: 59), earnedPoints: 19, possiblePoints: 20, status: .graded))
            context.insert(GradeItem(course: chemistry, category: homework, title: "Homework 3", dueDate: demoDate(month: 10, day: 23, hour: 23, minute: 59), possiblePoints: 20, status: .upcoming))
            context.insert(GradeItem(course: chemistry, category: labs, title: "Lab 1", dueDate: demoDate(month: 10, day: 6, hour: 17), earnedPoints: 45, possiblePoints: 50, status: .graded))
            context.insert(GradeItem(course: chemistry, category: midterms, title: "Midterm 1", dueDate: demoDate(month: 10, day: 16, hour: 10), earnedPoints: 84, possiblePoints: 100, status: .graded))
            context.insert(GradeItem(course: chemistry, category: final, title: "Final Exam", dueDate: demoDate(month: 12, day: 10, hour: 10), possiblePoints: 100, status: .upcoming))
            context.insert(ForecastScenario(
                course: chemistry,
                name: "Planned",
                kind: .expected,
                assumedRemainingPercentage: 87,
                isSelectedForGPAForecast: true
            ))
        }
        for course in demoCourses where course.id != chemistry?.id {
            addDemoGradebook(for: course, context: context)
        }
        preferences.demoDataLoaded = true
        try? context.save()
    }

    private struct DemoCategoryDefinition {
        let name: String
        let type: GradeCategoryType
        let weight: Decimal
        let mode: CategoryCalculationMode
    }

    private struct DemoItemDefinition {
        let categoryName: String
        let title: String
        let dueDate: Date
        let earnedPoints: Decimal?
        let possiblePoints: Decimal
        let status: GradeItemStatus
    }

    private struct DemoGradebookProfile {
        let gradingMethod: GradingMethod
        let targetPercentage: Decimal
        let categories: [DemoCategoryDefinition]
        let items: [DemoItemDefinition]
    }

    /// Adds a complete, clearly labeled local example gradebook to a demo course.
    /// Existing user data is never passed to this helper; the supplement path only
    /// calls it for demo courses that do not already have grade items.
    private static func addDemoGradebook(
        for course: CourseRecord,
        context: ModelContext,
        existingPolicy: CourseGradingPolicy? = nil,
        existingCategories: [GradingCategory] = [],
        existingScale: GradeScale? = nil
    ) {
        guard let profile = profile(for: course.courseCode) else { return }

        if let existingPolicy {
            existingPolicy.gradingMethod = profile.gradingMethod
            existingPolicy.targetPercentage = profile.targetPercentage
            if SyllabusSourceStore.source(for: existingPolicy.id) == nil {
                existingPolicy.syllabusImportSource = .pastedText
                existingPolicy.importStatus = .confirmed
                SyllabusSourceStore.save(
                    sourceText: demoSyllabusText(for: course.courseCode),
                    pagesData: nil,
                    source: .pastedText,
                    for: existingPolicy.id
                )
            }
        } else {
            let policy = CourseGradingPolicy(
                course: course,
                gradingMethod: profile.gradingMethod,
                targetPercentage: profile.targetPercentage,
                syllabusImportSource: .pastedText,
                importStatus: .confirmed
            )
            context.insert(policy)
            SyllabusSourceStore.save(
                sourceText: demoSyllabusText(for: course.courseCode),
                pagesData: nil,
                source: .pastedText,
                for: policy.id
            )
        }

        let categories: [GradingCategory]
        if existingCategories.isEmpty {
            categories = profile.categories.enumerated().map { index, definition in
                let category = GradingCategory(
                    course: course,
                    name: definition.name,
                    categoryType: definition.type,
                    weight: definition.weight,
                    calculationMode: definition.mode,
                    sortOrder: index
                )
                context.insert(category)
                return category
            }
        } else {
            categories = existingCategories.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        }

        if existingScale == nil {
            context.insert(GradeScale(
                course: course,
                name: "Common Scale Template",
                boundaries: standardScale,
                isCommonTemplate: true
            ))
        }

        let categoryByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0) })
        for definition in profile.items {
            guard let category = categoryByName[definition.categoryName] else { continue }
            context.insert(GradeItem(
                course: course,
                category: category,
                title: definition.title,
                dueDate: definition.dueDate,
                earnedPoints: definition.earnedPoints,
                possiblePoints: definition.possiblePoints,
                status: definition.status
            ))
        }
    }

    private static func demoSyllabusText(for courseCode: String) -> String {
        switch courseCode {
        case "BIS 002B":
            return "Homework 25%. Quizzes 15%. Midterms 25%. Final Exam 35%. The lowest quiz may be dropped."
        case "PSC 001":
            return "Homework 20%. Midterms 35%. Final Exam 45%. Late work requires instructor approval."
        case "UWP 007":
            return "Projects 40%. Participation 20%. Final Portfolio 40%. Contact the instructor about late work."
        default:
            return "Review the course syllabus for grading categories, final exam weight, and late-work policies."
        }
    }

    private static func profile(for courseCode: String) -> DemoGradebookProfile? {
        switch courseCode {
        case "BIS 002B":
            return DemoGradebookProfile(
                gradingMethod: .weightedCategories,
                targetPercentage: 88,
                categories: [
                    DemoCategoryDefinition(name: "Homework", type: .homework, weight: 25, mode: .weightedCategory),
                    DemoCategoryDefinition(name: "Quizzes", type: .quiz, weight: 20, mode: .weightedCategory),
                    DemoCategoryDefinition(name: "Midterms", type: .midterm, weight: 25, mode: .weightedCategory),
                    DemoCategoryDefinition(name: "Final Exam", type: .finalExam, weight: 30, mode: .weightedCategory)
                ],
                items: [
                    DemoItemDefinition(categoryName: "Homework", title: "Homework 1", dueDate: demoDate(month: 9, day: 25, hour: 23, minute: 59), earnedPoints: 7, possiblePoints: 10, status: .graded),
                    DemoItemDefinition(categoryName: "Homework", title: "Homework 2", dueDate: demoDate(month: 10, day: 2, hour: 23, minute: 59), earnedPoints: 8, possiblePoints: 10, status: .graded),
                    DemoItemDefinition(categoryName: "Homework", title: "Homework 3", dueDate: demoDate(month: 10, day: 23, hour: 23, minute: 59), earnedPoints: nil, possiblePoints: 10, status: .upcoming),
                    DemoItemDefinition(categoryName: "Quizzes", title: "Quiz 1", dueDate: demoDate(month: 9, day: 29, hour: 23, minute: 59), earnedPoints: 15, possiblePoints: 20, status: .graded),
                    DemoItemDefinition(categoryName: "Quizzes", title: "Quiz 2", dueDate: demoDate(month: 10, day: 13, hour: 23, minute: 59), earnedPoints: nil, possiblePoints: 20, status: .upcoming),
                    DemoItemDefinition(categoryName: "Midterms", title: "Midterm 1", dueDate: demoDate(month: 10, day: 16, hour: 10), earnedPoints: 72, possiblePoints: 100, status: .graded),
                    DemoItemDefinition(categoryName: "Final Exam", title: "Final Exam", dueDate: demoDate(month: 12, day: 10, hour: 10), earnedPoints: nil, possiblePoints: 100, status: .upcoming)
                ]
            )
        case "UWP 007":
            return DemoGradebookProfile(
                gradingMethod: .weightedCategories,
                targetPercentage: 90,
                categories: [
                    DemoCategoryDefinition(name: "Essays", type: .project, weight: 60, mode: .weightedCategory),
                    DemoCategoryDefinition(name: "Presentation", type: .presentation, weight: 20, mode: .weightedCategory),
                    DemoCategoryDefinition(name: "Final Portfolio", type: .finalExam, weight: 20, mode: .weightedCategory)
                ],
                items: [
                    DemoItemDefinition(categoryName: "Essays", title: "Essay 1", dueDate: demoDate(month: 9, day: 28, hour: 23, minute: 59), earnedPoints: 38, possiblePoints: 50, status: .graded),
                    DemoItemDefinition(categoryName: "Essays", title: "Essay 2", dueDate: demoDate(month: 10, day: 19, hour: 23, minute: 59), earnedPoints: 41, possiblePoints: 50, status: .graded),
                    DemoItemDefinition(categoryName: "Presentation", title: "Research Presentation", dueDate: demoDate(month: 11, day: 6, hour: 17), earnedPoints: 14, possiblePoints: 20, status: .graded),
                    DemoItemDefinition(categoryName: "Final Portfolio", title: "Final Portfolio", dueDate: demoDate(month: 12, day: 8, hour: 23, minute: 59), earnedPoints: nil, possiblePoints: 100, status: .upcoming)
                ]
            )
        case "PSC 001":
            return DemoGradebookProfile(
                gradingMethod: .weightedCategories,
                targetPercentage: 85,
                categories: [
                    DemoCategoryDefinition(name: "Quizzes", type: .quiz, weight: 20, mode: .weightedCategory),
                    DemoCategoryDefinition(name: "Midterms", type: .midterm, weight: 35, mode: .weightedCategory),
                    DemoCategoryDefinition(name: "Final Exam", type: .finalExam, weight: 45, mode: .weightedCategory)
                ],
                items: [
                    DemoItemDefinition(categoryName: "Quizzes", title: "Quiz 1", dueDate: demoDate(month: 9, day: 30, hour: 23, minute: 59), earnedPoints: 7, possiblePoints: 10, status: .graded),
                    DemoItemDefinition(categoryName: "Quizzes", title: "Quiz 2", dueDate: demoDate(month: 10, day: 21, hour: 23, minute: 59), earnedPoints: 8, possiblePoints: 10, status: .graded),
                    DemoItemDefinition(categoryName: "Midterms", title: "Midterm 1", dueDate: demoDate(month: 10, day: 17, hour: 10), earnedPoints: 74, possiblePoints: 100, status: .graded),
                    DemoItemDefinition(categoryName: "Midterms", title: "Midterm 2", dueDate: demoDate(month: 11, day: 14, hour: 10), earnedPoints: nil, possiblePoints: 100, status: .upcoming),
                    DemoItemDefinition(categoryName: "Final Exam", title: "Final Exam", dueDate: demoDate(month: 12, day: 11, hour: 10), earnedPoints: nil, possiblePoints: 100, status: .upcoming)
                ]
            )
        default:
            return nil
        }
    }

    private static func supplementExistingDemoGradebooks(in context: ModelContext) {
        guard let courses = try? context.fetch(FetchDescriptor<CourseRecord>()),
              let policies = try? context.fetch(FetchDescriptor<CourseGradingPolicy>()),
              let categories = try? context.fetch(FetchDescriptor<GradingCategory>()),
              let items = try? context.fetch(FetchDescriptor<GradeItem>()),
              let scales = try? context.fetch(FetchDescriptor<GradeScale>()) else { return }

        for course in courses where course.isDemoData {
            var courseItems = items.filter { $0.course?.id == course.id }
            if let policy = policies.first(where: { $0.course?.id == course.id }),
               SyllabusSourceStore.source(for: policy.id) == nil {
                policy.syllabusImportSource = .pastedText
                policy.importStatus = .confirmed
                SyllabusSourceStore.save(
                    sourceText: demoSyllabusText(for: course.courseCode),
                    pagesData: nil,
                    source: .pastedText,
                    for: policy.id
                )
            }
            if course.courseCode == "CHE 002A",
               !courseItems.contains(where: { $0.title == "Final Exam" }),
               let finalCategory = categories.first(where: {
                   $0.course?.id == course.id && $0.categoryType == .finalExam
               }) {
                let finalExam = GradeItem(
                    course: course,
                    category: finalCategory,
                    title: "Final Exam",
                    dueDate: demoDate(month: 12, day: 10, hour: 10),
                    possiblePoints: 100,
                    status: .upcoming
                )
                context.insert(finalExam)
                courseItems.append(finalExam)
            }
            if courseItems.isEmpty {
                addDemoGradebook(
                    for: course,
                    context: context,
                    existingPolicy: policies.first { $0.course?.id == course.id },
                    existingCategories: categories.filter { $0.course?.id == course.id },
                    existingScale: scales.first { $0.course?.id == course.id }
                )
            } else {
                restoreProfileScores(for: course, items: courseItems)
            }
        }
    }

    /// Demo data is intentionally deterministic so screenshots and UI tests stay
    /// repeatable. When an older demo store already contains the item structure,
    /// restore the varied sample scores without touching any non-demo course.
    private static func restoreProfileScores(for course: CourseRecord, items: [GradeItem]) {
        guard let profile = profile(for: course.courseCode) else { return }
        for item in items {
            guard item.earnedPoints == nil,
                  let definition = profile.items.first(where: { $0.title == item.title }),
                  let earnedPoints = definition.earnedPoints else { continue }
            item.earnedPoints = earnedPoints
            item.possiblePoints = definition.possiblePoints
            item.status = .graded
            item.updatedAt = .now
        }
    }

    private static let standardScale: [GradeScaleBoundary] = [
        GradeScaleBoundary(letter: .a, minimumPercentage: 93), GradeScaleBoundary(letter: .aMinus, minimumPercentage: 90),
        GradeScaleBoundary(letter: .bPlus, minimumPercentage: 87), GradeScaleBoundary(letter: .b, minimumPercentage: 83),
        GradeScaleBoundary(letter: .bMinus, minimumPercentage: 80), GradeScaleBoundary(letter: .c, minimumPercentage: 70),
        GradeScaleBoundary(letter: .d, minimumPercentage: 60), GradeScaleBoundary(letter: .f, minimumPercentage: 0)
    ]

    private static func demoDate(month: Int, day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar.date(from: DateComponents(
            year: 2026,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )) ?? .now
    }

    static func clear(from context: ModelContext, courses: [CourseRecord], preferences: UserPreferences) throws {
        let demoCourses = courses.filter(\.isDemoData)
        let demoCourseModelIDs = Set(demoCourses.map(\.persistentModelID))

        do {
            let policies = try context.fetch(FetchDescriptor<CourseGradingPolicy>())
            let categories = try context.fetch(FetchDescriptor<GradingCategory>())
            let items = try context.fetch(FetchDescriptor<GradeItem>())
            let scales = try context.fetch(FetchDescriptor<GradeScale>())
            let forecasts = try context.fetch(FetchDescriptor<ForecastScenario>())
            let reminderDefaults = try context.fetch(FetchDescriptor<CourseReminderDefaults>())
            let notificationIdentifiers = items
                .filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }
                .map(\.notificationIdentifier)

            // Delete dependents first, then detach the inverse relationship before
            // deleting demo courses. This leaves no stale course reference for the
            // next Dashboard or import refresh to dereference.
            items.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)
            categories.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)
            policies.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach {
                SyllabusSourceStore.remove(policyID: $0.id)
                context.delete($0)
            }
            scales.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)
            forecasts.filter { isLinkedToDemoCourse($0.course, demoCourseModelIDs: demoCourseModelIDs) }.forEach(context.delete)
            let demoCourseIDs = Set(demoCourses.map(\.id))
            reminderDefaults.filter { demoCourseIDs.contains($0.courseID) }.forEach(context.delete)

            var demoTermsByModelID: [PersistentIdentifier: AcademicTerm] = [:]
            for course in demoCourses {
                if let term = course.term {
                    demoTermsByModelID[term.persistentModelID] = term
                }
            }
            let termsContainingOnlyDemoCourses = demoTermsByModelID.values.filter { term in
                term.courses.allSatisfy { $0.isDemoData }
            }
            for course in demoCourses {
                course.term = nil
                context.delete(course)
            }
            termsContainingOnlyDemoCourses.forEach(context.delete)
            preferences.demoDataLoaded = false
            try context.save()
            notificationIdentifiers.forEach { GradeItemNotificationService.cancel(identifier: $0) }
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func isLinkedToDemoCourse(
        _ course: CourseRecord?, demoCourseModelIDs: Set<PersistentIdentifier>
    ) -> Bool {
        course.map { demoCourseModelIDs.contains($0.persistentModelID) } ?? false
    }
}
