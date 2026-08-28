import Foundation
import SwiftData

/// The three user-facing stages of a course outcome.  A pending/NG record is
/// never treated as a missing GPA calculation: it resolves to Current, or to
/// Projected when a real forecast/plan is present.
enum GPAPlanningStage: String, Codable, Equatable, Sendable {
    case current
    case projected
    case final
    case unavailable
    case excluded
}

enum GPAPlanningTargetStatus: String, Equatable, Sendable {
    case noData
    case reached
    case reachable
    case notReachable
}

/// Immutable, UI-independent input produced from the gradebook and GradeEngine.
/// Views never need to know how a percentage becomes a letter grade.
struct GPAPlanningCourseInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let courseCode: String
    let courseTitle: String
    let units: Decimal
    let termID: UUID?
    let isIncludedInGPA: Bool
    let gradingBasis: GradingBasis
    let officialGrade: CourseGrade
    let currentGrade: CourseGrade?
    let currentPercentage: Decimal?
    let forecastGrade: CourseGrade?
    let forecastPercentage: Decimal?
    let hasForecast: Bool
    /// The confirmed scale used to turn a letter-only plan assumption into a
    /// transparent percentage boundary. This is not a fabricated forecast;
    /// it is the minimum percentage for the selected letter.
    let gradeScale: CourseGradeScaleInput?

    init(
        id: UUID,
        courseCode: String,
        courseTitle: String,
        units: Decimal,
        termID: UUID?,
        isIncludedInGPA: Bool,
        gradingBasis: GradingBasis,
        officialGrade: CourseGrade,
        currentGrade: CourseGrade?,
        currentPercentage: Decimal?,
        forecastGrade: CourseGrade?,
        forecastPercentage: Decimal?,
        hasForecast: Bool,
        gradeScale: CourseGradeScaleInput? = nil
    ) {
        self.id = id
        self.courseCode = courseCode
        self.courseTitle = courseTitle
        self.units = units
        self.termID = termID
        self.isIncludedInGPA = isIncludedInGPA
        self.gradingBasis = gradingBasis
        self.officialGrade = officialGrade
        self.currentGrade = currentGrade
        self.currentPercentage = currentPercentage
        self.forecastGrade = forecastGrade
        self.forecastPercentage = forecastPercentage
        self.hasForecast = hasForecast
        self.gradeScale = gradeScale
    }

    var isPending: Bool { officialGrade.isPending }
    var isGPAEligible: Bool {
        isIncludedInGPA && gradingBasis == .letter && units > 0
    }
}

struct GPAPlanningCourseState: Identifiable, Equatable, Sendable {
    let id: UUID
    let courseCode: String
    let courseTitle: String
    let units: Decimal
    let termID: UUID?
    let isIncludedInGPA: Bool
    /// Whether this course is a letter-graded, positive-unit course that is
    /// eligible for the planning GPA. Keeping this resolved here prevents
    /// views from re-implementing eligibility rules when showing final-grade
    /// progress or scenario controls.
    let isGPAEligible: Bool
    let officialGrade: CourseGrade
    let currentGrade: CourseGrade?
    let currentPercentage: Decimal?
    let projectedGrade: CourseGrade?
    let projectedPercentage: Decimal?
    let projectedPercentageIsBoundary: Bool
    let finalGrade: CourseGrade?
    let selectedGrade: CourseGrade?
    let stage: GPAPlanningStage
    let hasForecast: Bool

    var idValue: UUID { id }
}

struct GPAPlanningScenarioInput: Equatable, Sendable {
    let id: UUID?
    let name: String
    let targetGPA: Decimal
    let selectedCourseIDs: Set<UUID>?
    let assumedGrades: [UUID: CourseGrade]

    init(
        id: UUID? = nil,
        name: String = "Current plan",
        targetGPA: Decimal,
        selectedCourseIDs: Set<UUID>? = nil,
        assumedGrades: [UUID: CourseGrade] = [:]
    ) {
        self.id = id
        self.name = name
        self.targetGPA = targetGPA
        self.selectedCourseIDs = selectedCourseIDs
        self.assumedGrades = assumedGrades
    }
}

private extension CourseGradeScaleInput {
    func minimumPercentage(for grade: CourseGrade) -> Decimal? {
        boundaries
            .sorted { $0.minimumPercentage > $1.minimumPercentage }
            .first { $0.letter.rawValue == grade.rawValue }?
            .minimumPercentage
    }
}

struct GPAPlanningOpportunity: Equatable, Sendable {
    let courseID: UUID
    let courseCode: String
    let from: CourseGrade
    let to: CourseGrade
    let gain: Decimal
}

struct GPAPlanningSnapshot: Equatable, Sendable {
    let courses: [GPAPlanningCourseState]
    let current: GPAResult
    let projected: GPAResult
    /// Final GPA is intentionally nil until every eligible letter course has
    /// a final/recorded grade.  This is not a synonym for the transcript-only
    /// result used internally by the legacy import/export APIs.
    let final: GPAResult?
    let targetGPA: Decimal
    let deltaToTarget: Decimal?
    let targetResult: TargetGPAResult?
    let targetStatus: GPAPlanningTargetStatus
    let biggestOpportunity: GPAPlanningOpportunity?
    let selectedCourseIDs: Set<UUID>
    /// Final-report progress is scoped to the courses included in this plan.
    /// A partial count is informational only; `final` remains nil until every
    /// eligible course has a final grade.
    let eligibleFinalGradeCount: Int
    let eligibleCourseCount: Int

    var hasFinalGPA: Bool { final?.gpa != nil }
    var allEligibleCoursesFinalized: Bool {
        eligibleCourseCount > 0 && eligibleFinalGradeCount == eligibleCourseCount
    }
    var hasPendingFinalGrades: Bool {
        eligibleFinalGradeCount < eligibleCourseCount
    }
    var hasProjectedOutcome: Bool {
        courses.contains { $0.stage == .projected }
    }
}

/// The sole GPA planning composition layer.  It delegates all grade math to
/// CourseGradeCalculationEngine, GPAService, ProjectedGPAService, and
/// TargetGPAService, then exposes one resolved state for every planning view.
enum GPAPlanningEngine {
    static func resolve(
        inputs: [GPAPlanningCourseInput],
        scenario: GPAPlanningScenarioInput,
        fallbackTargetUnits: Decimal = 0
    ) -> GPAPlanningSnapshot {
        let selectedIDs = scenario.selectedCourseIDs
            ?? Set(inputs.filter(\.isIncludedInGPA).map(\.id))
        let scoped = inputs.filter { selectedIDs.contains($0.id) }

        let calculationInputs = scoped.map { input in
            CourseCalculationInput(
                id: input.id,
                courseCode: input.courseCode,
                units: input.units,
                grade: input.officialGrade,
                isIncludedInGPA: input.isIncludedInGPA,
                termID: input.termID
            )
        }

        var currentGrades: [UUID: CourseGrade] = [:]
        var projectedGrades: [UUID: CourseGrade] = [:]
        var states: [GPAPlanningCourseState] = []

        for input in scoped {
            let finalGrade = input.officialGrade.isPending ? nil : input.officialGrade
            let currentGrade = finalGrade ?? input.currentGrade
            if let currentGrade, currentGrade.gradePointValue != nil {
                currentGrades[input.id] = currentGrade
            }

            guard input.officialGrade.isPending else {
                states.append(GPAPlanningCourseState(
                    id: input.id,
                    courseCode: input.courseCode,
                    courseTitle: input.courseTitle,
                    units: input.units,
                    termID: input.termID,
                    isIncludedInGPA: input.isIncludedInGPA,
                    isGPAEligible: input.isGPAEligible,
                    officialGrade: input.officialGrade,
                    currentGrade: currentGrade,
                    currentPercentage: input.currentPercentage,
                    projectedGrade: nil,
                    projectedPercentage: nil,
                    projectedPercentageIsBoundary: false,
                    finalGrade: finalGrade,
                    selectedGrade: finalGrade,
                    stage: input.isGPAEligible ? .final : .excluded,
                    hasForecast: false
                ))
                continue
            }

            let assumed = scenario.assumedGrades[input.id]
            let projected = assumed ?? input.forecastGrade
            let projectedPercentage: Decimal?
            let projectedPercentageIsBoundary: Bool
            if let projected {
                if assumed != nil {
                    projectedPercentage = input.gradeScale?.minimumPercentage(for: projected)
                    projectedPercentageIsBoundary = projectedPercentage != nil
                } else if let forecastPercentage = input.forecastPercentage {
                    projectedPercentage = forecastPercentage
                    projectedPercentageIsBoundary = false
                } else {
                    projectedPercentage = input.gradeScale?.minimumPercentage(for: projected)
                    projectedPercentageIsBoundary = projectedPercentage != nil
                }
            } else {
                projectedPercentage = nil
                projectedPercentageIsBoundary = false
            }
            if let projected, projected.gradePointValue != nil {
                projectedGrades[input.id] = projected
            }
            let stage: GPAPlanningStage
            if !input.isGPAEligible {
                stage = .excluded
            } else if projected != nil {
                stage = .projected
            } else if currentGrade != nil {
                stage = .current
            } else {
                stage = .unavailable
            }
            states.append(GPAPlanningCourseState(
                id: input.id,
                courseCode: input.courseCode,
                courseTitle: input.courseTitle,
                units: input.units,
                termID: input.termID,
                isIncludedInGPA: input.isIncludedInGPA,
                isGPAEligible: input.isGPAEligible,
                officialGrade: input.officialGrade,
                currentGrade: currentGrade,
                currentPercentage: input.currentPercentage,
                projectedGrade: projected,
                projectedPercentage: projectedPercentage,
                projectedPercentageIsBoundary: projectedPercentageIsBoundary,
                finalGrade: nil,
                selectedGrade: projected ?? currentGrade,
                stage: stage,
                hasForecast: input.hasForecast || assumed != nil
            ))
        }

        let current = GPAService.live(calculationInputs, currentGrades: currentGrades)
        let projected = ProjectedGPAService.calculate(
            calculationInputs,
            projectedGrades: projectedGrades,
            currentGrades: currentGrades
        ).projected

        let eligibleLetterCourses = scoped.filter { $0.isGPAEligible }
        let pendingEligibleCourses = eligibleLetterCourses.filter(\.isPending)
        let final: GPAResult? = eligibleLetterCourses.isEmpty || !pendingEligibleCourses.isEmpty
            ? nil
            : GPAService.cumulative(calculationInputs)

        let futureUnits = pendingEligibleCourses.reduce(Decimal.zero) { $0 + $1.units }
        let effectiveFutureUnits = futureUnits > 0 ? futureUnits : fallbackTargetUnits
        let targetResult: TargetGPAResult? = current.gpa.flatMap { currentGPA in
            guard effectiveFutureUnits > 0 else { return nil }
            return TargetGPAService.calculate(
                currentGPA: currentGPA,
                currentUnits: current.attemptedUnits,
                targetGPA: scenario.targetGPA,
                futureUnits: effectiveFutureUnits
            )
        }
        let delta = projected.gpa.map { $0 - scenario.targetGPA }
        let targetStatus: GPAPlanningTargetStatus
        if let projectedGPA = projected.gpa {
            targetStatus = projectedGPA >= scenario.targetGPA ? .reached : (targetResult?.isReachable == true ? .reachable : .notReachable)
        } else if targetResult != nil {
            targetStatus = targetResult?.isReachable == true ? .reachable : .notReachable
        } else {
            targetStatus = .noData
        }

        let opportunity = biggestOpportunity(
            inputs: scoped,
            calculationInputs: calculationInputs,
            currentGrades: currentGrades,
            projectedGrades: projectedGrades,
            states: states,
            baseline: projected.gpa
        )

        let eligibleCourseCount = eligibleLetterCourses.count
        let eligibleFinalGradeCount = eligibleLetterCourses.count - pendingEligibleCourses.count

        return GPAPlanningSnapshot(
            courses: states.sorted { $0.courseCode < $1.courseCode },
            current: current,
            projected: projected,
            final: final,
            targetGPA: scenario.targetGPA,
            deltaToTarget: delta,
            targetResult: targetResult,
            targetStatus: targetStatus,
            biggestOpportunity: opportunity,
            selectedCourseIDs: selectedIDs,
            eligibleFinalGradeCount: eligibleFinalGradeCount,
            eligibleCourseCount: eligibleCourseCount
        )
    }

    private static func biggestOpportunity(
        inputs: [GPAPlanningCourseInput],
        calculationInputs: [CourseCalculationInput],
        currentGrades: [UUID: CourseGrade],
        projectedGrades: [UUID: CourseGrade],
        states: [GPAPlanningCourseState],
        baseline: Decimal?
    ) -> GPAPlanningOpportunity? {
        guard let baseline else { return nil }
        let order: [CourseGrade] = [
            .f, .dMinus, .d, .dPlus, .cMinus, .c, .cPlus,
            .bMinus, .b, .bPlus, .aMinus, .a, .aPlus
        ]
        return states.compactMap { state -> GPAPlanningOpportunity? in
            guard state.officialGrade.isPending,
                  state.isIncludedInGPA,
                  let from = state.selectedGrade,
                  let index = order.firstIndex(of: from), index + 1 < order.count else { return nil }
            let to = order[index + 1]
            var candidate = projectedGrades
            candidate[state.id] = to
            let candidateGPA = ProjectedGPAService.calculate(
                calculationInputs,
                projectedGrades: candidate,
                currentGrades: currentGrades
            ).projected.gpa
            guard let candidateGPA, candidateGPA > baseline else { return nil }
            return GPAPlanningOpportunity(
                courseID: state.id,
                courseCode: state.courseCode,
                from: from,
                to: to,
                gain: candidateGPA - baseline
            )
        }
        .max {
            if $0.gain != $1.gain { return $0.gain < $1.gain }
            return $0.courseCode > $1.courseCode
        }
    }
}

extension GPAPlanningEngine {
    /// Returns the single resolved state used by course rows and course detail.
    /// Active plan assumptions are applied only to courses in that plan; the
    /// same resolver then falls back to the selected forecast or current work.
    @MainActor
    static func state(
        for course: CourseRecord,
        policies: [CourseGradingPolicy],
        categories: [GradingCategory],
        items: [GradeItem],
        scales: [GradeScale],
        forecasts: [ForecastScenario],
        savedPlans: [PlannerScenario],
        fallbackTarget: Decimal
    ) -> GPAPlanningCourseState? {
        let inputs = makeInputs(
            courses: [course],
            policies: policies,
            categories: categories,
            items: items,
            scales: scales,
            forecasts: forecasts
        )
        guard let input = inputs.first else { return nil }
        let active = activeScenario(from: savedPlans, fallbackTarget: fallbackTarget)
        let planIncludesCourse = active.selectedCourseIDs == nil || active.selectedCourseIDs?.contains(course.id) == true
        let assumedGrades = planIncludesCourse
            ? active.assumedGrades.filter { $0.key == course.id }
            : [:]
        let scenario = GPAPlanningScenarioInput(
            id: active.id,
            name: active.name,
            targetGPA: active.targetGPA,
            selectedCourseIDs: [course.id],
            assumedGrades: assumedGrades
        )
        return resolve(inputs: [input], scenario: scenario).courses.first
    }

    @MainActor
    static func activeScenario(
        from savedPlans: [PlannerScenario],
        fallbackTarget: Decimal
    ) -> GPAPlanningScenarioInput {
        scenario(
            from: savedPlans.first(where: { $0.scenarioType == .custom }),
            fallbackTarget: fallbackTarget
        )
    }

    /// Makes a scenario the single active planning input set.  This is used
    /// by both GPA Overview and Full Simulation so a grade choice is visible
    /// immediately in course rows and course detail, without touching the
    /// authoritative course grade.
    @MainActor
    @discardableResult
    static func persistActiveScenario(
        _ scenario: GPAPlanningScenarioInput,
        in modelContext: ModelContext,
        savedPlans: [PlannerScenario],
        fallbackName: String = "My GPA plan"
    ) -> PlannerScenario? {
        let plan: PlannerScenario
        if let id = scenario.id,
           let existing = savedPlans.first(where: { $0.id == id }) {
            plan = existing
        } else if let existing = savedPlans.first(where: { $0.scenarioType == .custom }) {
            plan = existing
        } else {
            plan = PlannerScenario(
                name: scenario.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? fallbackName
                    : scenario.name,
                scenarioType: .custom,
                sortOrder: (savedPlans.map(\.sortOrder).max() ?? -1) + 1,
                targetGPA: scenario.targetGPA,
                selectedCourseIDs: scenario.selectedCourseIDs,
                assumedGrades: scenario.assumedGrades
            )
            modelContext.insert(plan)
        }

        plan.name = scenario.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackName
            : scenario.name
        // The newest edited scenario is the active one used by Course Detail
        // and course rows. Keep the plan list ordered by last activation.
        plan.sortOrder = max(plan.sortOrder, (savedPlans.map(\.sortOrder).max() ?? -1) + 1)
        plan.targetGPA = scenario.targetGPA
        plan.selectedCourseIDs = scenario.selectedCourseIDs
        plan.assumedGrades = scenario.assumedGrades
        plan.updatedAt = .now
        do {
            try modelContext.save()
            return plan
        } catch {
            modelContext.rollback()
            return nil
        }
    }

    /// Converts SwiftData gradebook records into immutable planning inputs.
    /// This is the only place where a planning screen asks GradeEngine for a
    /// current percentage or a forecast letter.
    @MainActor
    static func makeInputs(
        courses: [CourseRecord],
        policies: [CourseGradingPolicy],
        categories: [GradingCategory],
        items: [GradeItem],
        scales: [GradeScale],
        forecasts: [ForecastScenario]
    ) -> [GPAPlanningCourseInput] {
        // SwiftData query results are already in memory here, but the arrays
        // can contain records for many courses. Group them once so opening a
        // planning screen does not rescan the entire gradebook for every
        // course. Keep the existing first-match behavior for one-to-one
        // records and preserve source order for categories/items.
        var policiesByCourseID: [PersistentIdentifier: CourseGradingPolicy] = [:]
        for policy in policies {
            guard let course = policy.course,
                  policiesByCourseID[course.persistentModelID] == nil else { continue }
            policiesByCourseID[course.persistentModelID] = policy
        }

        var scalesByCourseID: [PersistentIdentifier: GradeScale] = [:]
        for scale in scales {
            guard let course = scale.course,
                  scalesByCourseID[course.persistentModelID] == nil else { continue }
            scalesByCourseID[course.persistentModelID] = scale
        }

        var forecastsByCourseID: [PersistentIdentifier: ForecastScenario] = [:]
        for forecast in forecasts where forecast.isSelectedForGPAForecast {
            guard let course = forecast.course,
                  forecastsByCourseID[course.persistentModelID] == nil else { continue }
            forecastsByCourseID[course.persistentModelID] = forecast
        }

        var categoriesByCourseID: [PersistentIdentifier: [GradingCategory]] = [:]
        for category in categories {
            guard let course = category.course else { continue }
            categoriesByCourseID[course.persistentModelID, default: []].append(category)
        }

        var itemsByCourseID: [PersistentIdentifier: [GradeItem]] = [:]
        for item in items {
            guard let course = item.course else { continue }
            itemsByCourseID[course.persistentModelID, default: []].append(item)
        }

        return courses
            .filter { !$0.isDeleted }
            .map { course in
                let courseID = course.persistentModelID
                let policy = policiesByCourseID[courseID]
                let scale = scalesByCourseID[courseID]
                let forecast = forecastsByCourseID[courseID]
                let courseCategories = categoriesByCourseID[courseID] ?? []
                let courseItems = itemsByCourseID[courseID] ?? []
                let currentInput = CourseGradeSnapshotBuilder.makeInput(
                    course: course,
                    policy: policy,
                    categories: courseCategories,
                    items: courseItems,
                    gradeScale: scale,
                    forecast: nil as ForecastScenario?
                )
                let currentResult = CourseGradeCalculationEngine.calculate(currentInput)
                let forecastResult = forecast.map {
                    CourseGradeCalculationEngine.calculate(CourseGradeSnapshotBuilder.makeInput(
                        course: course,
                        policy: policy,
                        categories: courseCategories,
                        items: courseItems,
                        gradeScale: scale,
                        forecast: $0
                    ))
                }
                let currentGrade = course.grade.gradePointValue != nil
                    ? course.grade
                    : currentResult.currentLetterGrade.flatMap { CourseGrade(rawValue: $0.rawValue) }
                let forecastGrade = forecastResult?.projectedLetterGrade.flatMap {
                    CourseGrade(rawValue: $0.rawValue)
                }
                return GPAPlanningCourseInput(
                    id: course.id,
                    courseCode: course.courseCode,
                    courseTitle: course.courseTitle,
                    units: course.units,
                    termID: course.term?.id,
                    isIncludedInGPA: course.isIncludedInGPA,
                    gradingBasis: course.gradingBasis,
                    officialGrade: course.grade,
                    currentGrade: currentGrade,
                    currentPercentage: currentResult.calculatedCurrentPercentage,
                    forecastGrade: forecastGrade,
                    forecastPercentage: forecastResult?.projectedFinalPercentage,
                    hasForecast: forecast != nil,
                    gradeScale: currentInput.gradeScale
                )
            }
    }

    @MainActor
    static func scenario(from saved: PlannerScenario?, fallbackTarget: Decimal) -> GPAPlanningScenarioInput {
        guard let saved else {
            return GPAPlanningScenarioInput(targetGPA: fallbackTarget)
        }
        return GPAPlanningScenarioInput(
            id: saved.id,
            name: saved.name,
            targetGPA: saved.targetGPA ?? fallbackTarget,
            selectedCourseIDs: saved.selectedCourseIDs,
            assumedGrades: saved.assumedGrades.isEmpty
                ? Dictionary(uniqueKeysWithValues: saved.visibleSimulatedCourses.compactMap {
                    guard let source = $0.sourceCourseID else { return nil }
                    return (source, $0.grade)
                })
                : saved.assumedGrades
        )
    }
}
