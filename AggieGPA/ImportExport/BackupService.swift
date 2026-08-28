import Foundation
import SwiftData

enum BackupError: LocalizedError {
  case unsupportedSchema(Int)
  case invalidFile
  case fileAccess

  var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version):
      "This backup uses schema version \(version), which this version of Aggie GPA cannot import."
    case .invalidFile:
      "This file is not a valid Aggie GPA backup. Your current data was not changed."
    case .fileAccess: "The selected file could not be read. Check file access and try again."
    }
  }
}

@MainActor
enum BackupService {
  static func makeEnvelope(
    terms: [AcademicTerm], courses: [CourseRecord]? = nil, scenarios: [PlannerScenario], preferences: UserPreferences,
    policies: [CourseGradingPolicy] = [], categories: [GradingCategory] = [],
    items: [GradeItem] = [],
    scales: [GradeScale] = [], forecasts: [ForecastScenario] = [],
    siriSettings: SiriAccessSettings? = nil,
    templates: [CourseTemplate] = [],
    reminderDefaults: [CourseReminderDefaults] = []
  ) -> BackupEnvelope {
    let liveTerms = terms.filter { !$0.isDeleted }
    let liveCourses = (courses ?? terms.flatMap(\.courses)).filter { !$0.isDeleted && !$0.isDemoData }
    let termIDsByModelID = Dictionary(uniqueKeysWithValues: liveTerms.map { ($0.persistentModelID, $0.id) })
    let liveCourseModelIDs = Set(liveCourses.map(\.persistentModelID))
    let liveCourseIDs = Set(liveCourses.map(\.id))
    let termDTOs = liveTerms.map {
      BackupEnvelope.TermDTO(
        id: $0.id, academicYear: $0.academicYear, termType: $0.termType,
        displayName: $0.displayName, startDate: $0.startDate, endDate: $0.endDate,
        isIncludedInCumulativeGPA: $0.isIncludedInCumulativeGPA, notes: $0.notes,
        createdAt: $0.createdAt, updatedAt: $0.updatedAt, sortOrder: $0.sortOrder)
    }
    let courseDTOs = liveCourses.map {
      BackupEnvelope.CourseDTO(
        id: $0.id, termID: $0.term.flatMap { termIDsByModelID[$0.persistentModelID] }, courseCode: $0.courseCode,
        courseTitle: $0.courseTitle, units: $0.units, grade: $0.grade,
        gradingBasis: $0.gradingBasis, institution: $0.institution,
        isMajorCourse: $0.isMajorCourse, isUpperDivision: $0.isUpperDivision,
        isIncludedInGPA: $0.isIncludedInGPA, isTransferCourse: $0.isTransferCourse,
        isRepeatCourse: $0.isRepeatCourse, repeatGroupID: $0.repeatGroupID,
        repeatAttemptOrder: $0.repeatAttemptOrder,
        repeatHandlingMode: $0.repeatHandlingMode, targetGrade: $0.targetGrade,
        notes: $0.notes, customColor: $0.customColor,
        // These optional fields remain decodable for backups created by an
        // intermediate development build. New backups store defaults below.
        defaultReminderEnabled: nil,
        defaultReminderLeadTime: nil,
        defaultCustomReminderDate: nil,
        createdAt: $0.createdAt, updatedAt: $0.updatedAt, isDemoData: $0.isDemoData)
    }
    let scenarioDTOs = scenarios.map { scenario in
      BackupEnvelope.ScenarioDTO(
        id: scenario.id, name: scenario.name, scenarioType: scenario.scenarioType,
        associatedTermID: scenario.associatedTerm?.id, createdAt: scenario.createdAt,
        updatedAt: scenario.updatedAt, sortOrder: scenario.sortOrder,
        targetGPA: scenario.targetGPA,
        selectedCourseIDs: scenario.selectedCourseIDs.map(Array.init),
        assumedGrades: scenario.assumedGrades.reduce(into: [:]) { $0[$1.key] = $1.value.rawValue },
        courses: scenario.visibleSimulatedCourses.map {
          BackupEnvelope.SimulatedCourseDTO(
            id: $0.id, sourceCourseID: $0.sourceCourseID,
            courseCode: $0.courseCode, units: $0.units,
            grade: $0.grade, isIncludedInGPA: $0.isIncludedInGPA,
            isMajorCourse: $0.isMajorCourse, isUpperDivision: $0.isUpperDivision,
            confidence: $0.confidence, notes: $0.notes)
        })
    }
    let preferenceDTO = BackupEnvelope.PreferencesDTO(
      displayName: preferences.displayName, major: preferences.major,
      targetGPA: preferences.targetGPA, firstAcademicYear: preferences.firstAcademicYear,
      decimalPrecision: preferences.decimalPrecision, appearance: preferences.appearance,
      language: preferences.language,
      hapticsEnabled: preferences.hapticsEnabled, showMajorGPA: preferences.showMajorGPA,
      showUpperDivisionGPA: preferences.showUpperDivisionGPA,
      showRepeatSummary: preferences.showRepeatSummary,
      defaultGradingBasis: preferences.defaultGradingBasis,
      privacyLockEnabled: preferences.privacyLockEnabled,
      privacyLockDelay: preferences.privacyLockDelay,
      preferredAppIcon: preferences.preferredAppIcon,
      onboardingCompleted: preferences.onboardingCompleted,
      demoDataLoaded: preferences.demoDataLoaded)
    return BackupEnvelope(
      schemaVersion: BackupEnvelope.currentSchemaVersion, exportDate: .now,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
      terms: termDTOs, courses: courseDTOs,
      plannerScenarios: scenarioDTOs, preferences: preferenceDTO,
      gradingPolicies: policies.compactMap { policy in
        guard let course = policy.course, liveCourseModelIDs.contains(course.persistentModelID) else { return nil }
        let courseID = course.id
        return .init(
          id: policy.id, courseID: courseID, gradingMethod: policy.gradingMethod,
          normalizeCurrentGrade: policy.normalizeCurrentGrade,
          missingItemPolicy: policy.missingItemPolicy,
          missingPolicyConfirmed: policy.missingPolicyConfirmed,
          targetPercentage: policy.targetPercentage,
          targetLetterGrade: policy.targetLetterGrade,
          syllabusImportSource: policy.syllabusImportSource,
          importStatus: policy.importStatus, manualReviewReason: policy.manualReviewReason,
          syllabusSourceText: SyllabusSourceStore.source(for: policy.id)?.sourceText,
          syllabusSourcePagesData: SyllabusSourceStore.source(for: policy.id)?.pagesData,
          lastCalculatedAt: policy.lastCalculatedAt, createdAt: policy.createdAt,
          updatedAt: policy.updatedAt)
      },
      gradingCategories: categories.compactMap { category in
        guard let course = category.course, liveCourseModelIDs.contains(course.persistentModelID) else { return nil }
        let courseID = course.id
        return .init(
          id: category.id, courseID: courseID, name: category.name,
          categoryType: category.categoryType,
          weight: category.weight, calculationMode: category.calculationMode,
          dropLowestCount: category.dropLowestCount, isExtraCredit: category.isExtraCredit,
          isIncluded: category.isIncluded, sortOrder: category.sortOrder,
          createdAt: category.createdAt, updatedAt: category.updatedAt)
      },
      gradeItems: items.compactMap { item in
        guard let course = item.course, liveCourseModelIDs.contains(course.persistentModelID) else { return nil }
        let courseID = course.id
        return .init(
          id: item.id, courseID: courseID, categoryID: item.category?.id, title: item.title,
          dueDate: item.dueDate, earnedPoints: item.earnedPoints,
          possiblePoints: item.possiblePoints,
          percentageOverride: item.percentageOverride, status: item.status,
          isIncluded: item.isIncluded,
          isExtraCredit: item.isExtraCredit, isDropped: item.isDropped, isExcused: item.isExcused,
          multiplier: item.multiplier, notes: item.notes, reminderEnabled: item.reminderEnabled,
          reminderLeadTime: item.reminderLeadTime, customReminderDate: item.customReminderDate,
          notificationIdentifier: item.notificationIdentifier, createdAt: item.createdAt,
          updatedAt: item.updatedAt)
      },
      gradeScales: scales.compactMap { scale in
        guard let course = scale.course, liveCourseModelIDs.contains(course.persistentModelID) else { return nil }
        let courseID = course.id
        return .init(
          id: scale.id, courseID: courseID, name: scale.name, boundaries: scale.boundaries,
          isLetterPredictionEnabled: scale.isLetterPredictionEnabled,
          isCommonTemplate: scale.isCommonTemplate,
          curveNote: scale.curveNote, requiresManualReview: scale.requiresManualReview,
          createdAt: scale.createdAt, updatedAt: scale.updatedAt)
      },
      forecastScenarios: forecasts.compactMap { forecast in
        guard let course = forecast.course, liveCourseModelIDs.contains(course.persistentModelID) else { return nil }
        let courseID = course.id
        return .init(
          id: forecast.id, courseID: courseID, name: forecast.name, kind: forecast.kind,
          assumedRemainingPercentage: forecast.assumedRemainingPercentage,
          itemAssumptions: forecast.itemAssumptions,
          isSelectedForGPAForecast: forecast.isSelectedForGPAForecast,
          createdAt: forecast.createdAt, updatedAt: forecast.updatedAt)
      },
      siriSettings: siriSettings.map {
        .init(
          id: $0.id, isSiriAccessEnabled: $0.isSiriAccessEnabled,
          allowAssignmentSummaries: $0.allowAssignmentSummaries,
          allowDetailedScores: $0.allowDetailedScores, allowGPAResponses: $0.allowGPAResponses,
          allowCreatingDrafts: $0.allowCreatingDrafts, createdAt: $0.createdAt,
          updatedAt: $0.updatedAt)
      },
      courseTemplates: templates.filter { !$0.isDeleted }.map {
        .init(
          id: $0.id, name: $0.name, sourceCourseID: $0.sourceCourseID,
          gradingMethod: $0.gradingMethod, normalizeCurrentGrade: $0.normalizeCurrentGrade,
          missingItemPolicy: $0.missingItemPolicy, missingPolicyConfirmed: $0.missingPolicyConfirmed,
          targetPercentage: $0.targetPercentage, targetLetterGrade: $0.targetLetterGrade,
          categories: $0.categories, gradeScale: $0.gradeScale,
          defaultReminderEnabled: $0.defaultReminderEnabled,
          defaultReminderLeadTime: $0.defaultReminderLeadTime,
          defaultCustomReminderDate: $0.defaultCustomReminderDate,
          isBuiltIn: $0.isBuiltIn, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
      },
      courseReminderDefaults: reminderDefaults.filter { liveCourseIDs.contains($0.courseID) }.map {
        .init(
          courseID: $0.courseID, reminderEnabled: $0.reminderEnabled,
          reminderLeadTime: $0.reminderLeadTime, customReminderDate: $0.customReminderDate,
          createdAt: $0.createdAt, updatedAt: $0.updatedAt)
      })
  }

  static func encode(_ envelope: BackupEnvelope) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    // Numeric seconds preserve Date's binary value across a round-trip.
    encoder.dateEncodingStrategy = .secondsSince1970
    return try encoder.encode(envelope)
  }

  static func decode(_ data: Data) throws -> BackupEnvelope {
    guard !data.isEmpty else { throw BackupError.invalidFile }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      if let seconds = try? container.decode(Double.self) {
        return Date(timeIntervalSince1970: seconds)
      }
      let value = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: value) { return date }
      let standard = ISO8601DateFormatter()
      if let date = standard.date(from: value) { return date }
      throw BackupError.invalidFile
    }
    do {
      let envelope = try decoder.decode(BackupEnvelope.self, from: data)
      guard (1...BackupEnvelope.currentSchemaVersion).contains(envelope.schemaVersion) else {
        throw BackupError.unsupportedSchema(envelope.schemaVersion)
      }
      return envelope
    } catch let error as BackupError {
      throw error
    } catch {
      throw BackupError.invalidFile
    }
  }

  static func preview(
    _ envelope: BackupEnvelope,
    existingTerms: [AcademicTerm],
    existingCourses: [CourseRecord]? = nil,
    existingItems: [GradeItem] = [],
    existingTemplates: [CourseTemplate] = [],
    existingReminderDefaults: [CourseReminderDefaults] = []
  ) -> ImportPreview {
    let termIDs = Set(existingTerms.map(\.id))
    let courseIDs = Set((existingCourses ?? existingTerms.flatMap(\.courses)).filter { !$0.isDeleted }.map(\.id))
    let itemIDs = Set(existingItems.filter { !$0.isDeleted }.map(\.id))
    let templateIDs = Set(existingTemplates.filter { !$0.isDeleted }.map(\.id))
    let reminderDefaultIDs = Set(existingReminderDefaults.map(\.courseID))
    let importedItems = envelope.gradeItems ?? []
    let importedTemplates = envelope.courseTemplates ?? []
    let importedReminderDefaults = envelope.courseReminderDefaults ?? []
    return ImportPreview(
      envelope: envelope,
      duplicateTermCount: envelope.terms.filter { termIDs.contains($0.id) }.count,
      duplicateCourseCount: envelope.courses.filter { courseIDs.contains($0.id) }.count,
      duplicateItemCount: importedItems.filter { itemIDs.contains($0.id) }.count,
      duplicateTemplateCount: importedTemplates.filter { templateIDs.contains($0.id) }.count,
      duplicateReminderDefaultCount: importedReminderDefaults.filter { reminderDefaultIDs.contains($0.courseID) }.count,
      newTermCount: envelope.terms.filter { !termIDs.contains($0.id) }.count,
      newCourseCount: envelope.courses.filter { !courseIDs.contains($0.id) }.count,
      newItemCount: importedItems.filter { !itemIDs.contains($0.id) }.count,
      newTemplateCount: importedTemplates.filter { !templateIDs.contains($0.id) }.count,
      newReminderDefaultCount: importedReminderDefaults.filter { !reminderDefaultIDs.contains($0.courseID) }.count)
  }

  static func apply(
    _ envelope: BackupEnvelope, mode: ImportMode, context: ModelContext,
    existingTerms: [AcademicTerm], existingScenarios: [PlannerScenario],
    preferences: UserPreferences
  ) throws {
    do {
      try validateUniqueRecordIDs(in: envelope)
      let existingPolicies = try context.fetch(FetchDescriptor<CourseGradingPolicy>())
      let existingCategories = try context.fetch(FetchDescriptor<GradingCategory>())
      let existingItems = try context.fetch(FetchDescriptor<GradeItem>())
      let existingScales = try context.fetch(FetchDescriptor<GradeScale>())
      let existingForecasts = try context.fetch(FetchDescriptor<ForecastScenario>())
      let existingTemplates = try context.fetch(FetchDescriptor<CourseTemplate>())
      let existingReminderDefaults = try context.fetch(FetchDescriptor<CourseReminderDefaults>())
      let existingCourses = try context.fetch(FetchDescriptor<CourseRecord>())
      let existingSiri = try context.fetch(FetchDescriptor<SiriAccessSettings>())
      let replacedNotificationIdentifiers = mode == .replace ? existingItems.map(\.notificationIdentifier) : []
      if mode == .replace {
        existingItems.forEach(context.delete)
        existingCategories.forEach(context.delete)
        existingPolicies.forEach {
          SyllabusSourceStore.remove(policyID: $0.id)
          context.delete($0)
        }
        existingScales.forEach(context.delete)
        existingForecasts.forEach(context.delete)
        existingTemplates.forEach(context.delete)
        existingReminderDefaults.forEach(context.delete)
        existingScenarios.forEach(context.delete)
        for course in existingCourses {
          course.term = nil
          context.delete(course)
        }
        existingTerms.forEach(context.delete)
      }

      let existingScenarioIDs = mode == .merge ? Set(existingScenarios.map(\.id)) : []
      var termsByID = Dictionary(
        uniqueKeysWithValues: (mode == .merge ? existingTerms : []).map { ($0.id, $0) })

      for dto in envelope.terms {
        if let term = termsByID[dto.id] {
          term.academicYear = dto.academicYear
          term.termType = dto.termType
          term.displayName = dto.displayName
          term.startDate = dto.startDate
          term.endDate = dto.endDate
          term.isIncludedInCumulativeGPA = dto.isIncludedInCumulativeGPA
          term.notes = dto.notes
          term.updatedAt = dto.updatedAt
          term.sortOrder = dto.sortOrder
        } else {
          let term = AcademicTerm(
            id: dto.id, academicYear: dto.academicYear, termType: dto.termType,
            displayName: dto.displayName, startDate: dto.startDate, endDate: dto.endDate,
            isIncludedInCumulativeGPA: dto.isIncludedInCumulativeGPA, notes: dto.notes,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt, sortOrder: dto.sortOrder)
          context.insert(term)
          termsByID[dto.id] = term
        }
      }
      var coursesByID = Dictionary(uniqueKeysWithValues: (mode == .merge ? existingCourses : []).map { ($0.id, $0) })
      for dto in envelope.courses {
        if let course = coursesByID[dto.id] {
          course.courseCode = dto.courseCode
          course.courseTitle = dto.courseTitle
          course.units = dto.units
          course.grade = dto.grade
          course.gradingBasis = dto.gradingBasis
          course.institution = dto.institution
          course.term = dto.termID.flatMap { termsByID[$0] }
          course.isMajorCourse = dto.isMajorCourse
          course.isUpperDivision = dto.isUpperDivision
          course.isIncludedInGPA = dto.isIncludedInGPA
          course.isTransferCourse = dto.isTransferCourse
          course.isRepeatCourse = dto.isRepeatCourse
          course.repeatGroupID = dto.repeatGroupID
          course.repeatAttemptOrder = dto.repeatAttemptOrder
          course.repeatHandlingMode = dto.repeatHandlingMode
          course.targetGrade = dto.targetGrade
          course.notes = dto.notes
          course.customColor = dto.customColor
          course.updatedAt = dto.updatedAt
        } else {
          let course = CourseRecord(
            id: dto.id, courseCode: dto.courseCode, courseTitle: dto.courseTitle,
            units: dto.units, grade: dto.grade, gradingBasis: dto.gradingBasis,
            institution: dto.institution, term: dto.termID.flatMap { termsByID[$0] },
            isMajorCourse: dto.isMajorCourse, isUpperDivision: dto.isUpperDivision,
            isIncludedInGPA: dto.isIncludedInGPA, isTransferCourse: dto.isTransferCourse,
            isRepeatCourse: dto.isRepeatCourse, repeatGroupID: dto.repeatGroupID,
            repeatAttemptOrder: dto.repeatAttemptOrder,
            repeatHandlingMode: dto.repeatHandlingMode, targetGrade: dto.targetGrade,
            notes: dto.notes, customColor: dto.customColor,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt, isDemoData: dto.isDemoData)
          context.insert(course)
          coursesByID[dto.id] = course
        }
      }
      let allCourses = try context.fetch(FetchDescriptor<CourseRecord>())
      coursesByID = Dictionary(uniqueKeysWithValues: allCourses.map { ($0.id, $0) })
      var reminderDefaultsByCourseID = Dictionary(
        uniqueKeysWithValues: (mode == .merge ? existingReminderDefaults : []).map { ($0.courseID, $0) })
      // Import legacy optional fields from an intermediate development build.
      for dto in envelope.courses {
        guard let reminderEnabled = dto.defaultReminderEnabled,
              coursesByID[dto.id] != nil else { continue }
        let defaults = reminderDefaultsByCourseID[dto.id] ?? CourseReminderDefaults(courseID: dto.id)
        if reminderDefaultsByCourseID[dto.id] == nil { context.insert(defaults) }
        defaults.reminderEnabled = reminderEnabled
        defaults.reminderLeadTime = dto.defaultReminderLeadTime ?? .oneDay
        defaults.customReminderDate = dto.defaultCustomReminderDate
        defaults.updatedAt = dto.updatedAt
        reminderDefaultsByCourseID[dto.id] = defaults
      }
      for dto in envelope.courseReminderDefaults ?? [] {
        guard coursesByID[dto.courseID] != nil else { continue }
        let defaults = reminderDefaultsByCourseID[dto.courseID] ?? CourseReminderDefaults(courseID: dto.courseID)
        if reminderDefaultsByCourseID[dto.courseID] == nil { context.insert(defaults) }
        defaults.reminderEnabled = dto.reminderEnabled
        defaults.reminderLeadTime = dto.reminderLeadTime
        defaults.customReminderDate = dto.customReminderDate
        defaults.createdAt = dto.createdAt
        defaults.updatedAt = dto.updatedAt
        reminderDefaultsByCourseID[dto.courseID] = defaults
      }
      var policiesByID = Dictionary(uniqueKeysWithValues: (mode == .merge ? existingPolicies : []).map { ($0.id, $0) })
      for dto in envelope.gradingPolicies ?? [] {
        guard let course = coursesByID[dto.courseID] else { continue }
        if let policy = policiesByID[dto.id] {
          policy.course = course
          policy.gradingMethod = dto.gradingMethod
          policy.normalizeCurrentGrade = dto.normalizeCurrentGrade
          policy.missingItemPolicy = dto.missingItemPolicy
          policy.missingPolicyConfirmed = dto.missingPolicyConfirmed
          policy.targetPercentage = dto.targetPercentage
          policy.targetLetterGrade = dto.targetLetterGrade
          policy.syllabusImportSource = dto.syllabusImportSource
          policy.importStatus = dto.importStatus
          policy.manualReviewReason = dto.manualReviewReason
          if dto.syllabusSourceText != nil || dto.syllabusSourcePagesData != nil {
            SyllabusSourceStore.save(
              sourceText: dto.syllabusSourceText,
              pagesData: dto.syllabusSourcePagesData,
              source: dto.syllabusImportSource,
              for: policy.id
            )
          } else {
            SyllabusSourceStore.remove(policyID: policy.id)
          }
          policy.lastCalculatedAt = dto.lastCalculatedAt
          policy.updatedAt = dto.updatedAt
        } else {
          let policy = CourseGradingPolicy(
            id: dto.id, course: course, gradingMethod: dto.gradingMethod,
            normalizeCurrentGrade: dto.normalizeCurrentGrade,
            missingItemPolicy: dto.missingItemPolicy,
            missingPolicyConfirmed: dto.missingPolicyConfirmed,
            targetPercentage: dto.targetPercentage,
            targetLetterGrade: dto.targetLetterGrade,
            syllabusImportSource: dto.syllabusImportSource,
            importStatus: dto.importStatus, manualReviewReason: dto.manualReviewReason,
            lastCalculatedAt: dto.lastCalculatedAt, createdAt: dto.createdAt,
            updatedAt: dto.updatedAt)
          context.insert(policy)
          policiesByID[dto.id] = policy
          if dto.syllabusSourceText != nil || dto.syllabusSourcePagesData != nil {
            SyllabusSourceStore.save(
              sourceText: dto.syllabusSourceText,
              pagesData: dto.syllabusSourcePagesData,
              source: dto.syllabusImportSource,
              for: policy.id
            )
          }
        }
      }
      var categoriesByID = Dictionary(
        uniqueKeysWithValues: (mode == .merge ? existingCategories : []).map { ($0.id, $0) })
      for dto in envelope.gradingCategories ?? [] {
        guard let course = coursesByID[dto.courseID] else { continue }
        if let category = categoriesByID[dto.id] {
          category.course = course
          category.name = dto.name
          category.categoryType = dto.categoryType
          category.weight = dto.weight
          category.calculationMode = dto.calculationMode
          category.dropLowestCount = dto.dropLowestCount
          category.isExtraCredit = dto.isExtraCredit
          category.isIncluded = dto.isIncluded
          category.sortOrder = dto.sortOrder
          category.updatedAt = dto.updatedAt
        } else {
          let category = GradingCategory(
            id: dto.id, course: course, name: dto.name, categoryType: dto.categoryType,
            weight: dto.weight, calculationMode: dto.calculationMode,
            dropLowestCount: dto.dropLowestCount, isExtraCredit: dto.isExtraCredit,
            isIncluded: dto.isIncluded, sortOrder: dto.sortOrder,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt)
          context.insert(category)
          categoriesByID[dto.id] = category
        }
      }
      var importedReminderSnapshots: [GradeItemReminderSnapshot] = []
      var disabledReminderIdentifiers: [String] = []
      var itemsByID = Dictionary(uniqueKeysWithValues: (mode == .merge ? existingItems : []).map { ($0.id, $0) })
      for dto in envelope.gradeItems ?? [] {
        guard let course = coursesByID[dto.courseID] else { continue }
        let item: GradeItem
        if let existing = itemsByID[dto.id] {
          item = existing
          item.course = course
          item.category = dto.categoryID.flatMap { categoriesByID[$0] }
          item.title = dto.title
          item.dueDate = dto.dueDate
          item.earnedPoints = dto.earnedPoints
          item.possiblePoints = dto.possiblePoints
          item.percentageOverride = dto.percentageOverride
          item.status = dto.status
          item.isIncluded = dto.isIncluded
          item.isExtraCredit = dto.isExtraCredit
          item.isDropped = dto.isDropped
          item.isExcused = dto.isExcused
          item.multiplier = dto.multiplier
          item.notes = dto.notes
          item.reminderEnabled = dto.reminderEnabled
          item.reminderLeadTime = dto.reminderLeadTime
          item.customReminderDate = dto.customReminderDate
          item.notificationIdentifier = dto.notificationIdentifier
          item.updatedAt = dto.updatedAt
        } else {
          item = GradeItem(
            id: dto.id, course: course, category: dto.categoryID.flatMap { categoriesByID[$0] },
            title: dto.title, dueDate: dto.dueDate, earnedPoints: dto.earnedPoints,
            possiblePoints: dto.possiblePoints, percentageOverride: dto.percentageOverride,
            status: dto.status, isIncluded: dto.isIncluded, isExtraCredit: dto.isExtraCredit,
            isDropped: dto.isDropped, isExcused: dto.isExcused, multiplier: dto.multiplier,
            notes: dto.notes, reminderEnabled: dto.reminderEnabled,
            reminderLeadTime: dto.reminderLeadTime, customReminderDate: dto.customReminderDate,
            notificationIdentifier: dto.notificationIdentifier, createdAt: dto.createdAt,
            updatedAt: dto.updatedAt)
          context.insert(item)
          itemsByID[dto.id] = item
        }
        if item.reminderEnabled { importedReminderSnapshots.append(GradeItemReminderSnapshot(item)) }
        else { disabledReminderIdentifiers.append(item.notificationIdentifier) }
      }
      var scalesByID = Dictionary(uniqueKeysWithValues: (mode == .merge ? existingScales : []).map { ($0.id, $0) })
      for dto in envelope.gradeScales ?? [] {
        guard let course = coursesByID[dto.courseID] else { continue }
        if let scale = scalesByID[dto.id] {
          scale.course = course
          scale.name = dto.name
          scale.boundaries = dto.boundaries
          scale.isLetterPredictionEnabled = dto.isLetterPredictionEnabled
          scale.isCommonTemplate = dto.isCommonTemplate
          scale.curveNote = dto.curveNote
          scale.requiresManualReview = dto.requiresManualReview
          scale.updatedAt = dto.updatedAt
        } else {
          let scale = GradeScale(
            id: dto.id, course: course, name: dto.name, boundaries: dto.boundaries,
            isLetterPredictionEnabled: dto.isLetterPredictionEnabled,
            isCommonTemplate: dto.isCommonTemplate, curveNote: dto.curveNote,
            requiresManualReview: dto.requiresManualReview, createdAt: dto.createdAt,
            updatedAt: dto.updatedAt)
          context.insert(scale)
          scalesByID[dto.id] = scale
        }
      }
      var forecastsByID = Dictionary(uniqueKeysWithValues: (mode == .merge ? existingForecasts : []).map { ($0.id, $0) })
      for dto in envelope.forecastScenarios ?? [] {
        guard let course = coursesByID[dto.courseID] else { continue }
        if let forecast = forecastsByID[dto.id] {
          forecast.course = course
          forecast.name = dto.name
          forecast.kind = dto.kind
          forecast.assumedRemainingPercentage = dto.assumedRemainingPercentage
          forecast.itemAssumptions = dto.itemAssumptions
          forecast.isSelectedForGPAForecast = dto.isSelectedForGPAForecast
          forecast.updatedAt = dto.updatedAt
        } else {
          let forecast = ForecastScenario(
            id: dto.id, course: course, name: dto.name, kind: dto.kind,
            assumedRemainingPercentage: dto.assumedRemainingPercentage,
            itemAssumptions: dto.itemAssumptions,
            isSelectedForGPAForecast: dto.isSelectedForGPAForecast,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt)
          context.insert(forecast)
          forecastsByID[dto.id] = forecast
        }
      }
      var templatesByID = Dictionary(uniqueKeysWithValues: (mode == .merge ? existingTemplates : []).map { ($0.id, $0) })
      for dto in envelope.courseTemplates ?? [] {
        if let template = templatesByID[dto.id] {
          template.name = dto.name
          template.sourceCourseID = dto.sourceCourseID
          template.gradingMethod = dto.gradingMethod
          template.normalizeCurrentGrade = dto.normalizeCurrentGrade
          template.missingItemPolicy = dto.missingItemPolicy
          template.missingPolicyConfirmed = dto.missingPolicyConfirmed
          template.targetPercentage = dto.targetPercentage
          template.targetLetterGrade = dto.targetLetterGrade
          template.categories = dto.categories
          template.gradeScale = dto.gradeScale
          template.defaultReminderEnabled = dto.defaultReminderEnabled
          template.defaultReminderLeadTime = dto.defaultReminderLeadTime
          template.defaultCustomReminderDate = dto.defaultCustomReminderDate
          template.isBuiltIn = dto.isBuiltIn
          template.updatedAt = dto.updatedAt
        } else {
          let template = CourseTemplate(
            id: dto.id, name: dto.name, sourceCourseID: dto.sourceCourseID,
            gradingMethod: dto.gradingMethod, normalizeCurrentGrade: dto.normalizeCurrentGrade,
            missingItemPolicy: dto.missingItemPolicy, missingPolicyConfirmed: dto.missingPolicyConfirmed,
            targetPercentage: dto.targetPercentage, targetLetterGrade: dto.targetLetterGrade,
            categories: dto.categories, gradeScale: dto.gradeScale,
            defaultReminderEnabled: dto.defaultReminderEnabled,
            defaultReminderLeadTime: dto.defaultReminderLeadTime,
            defaultCustomReminderDate: dto.defaultCustomReminderDate,
            isBuiltIn: dto.isBuiltIn, createdAt: dto.createdAt, updatedAt: dto.updatedAt)
          context.insert(template)
          templatesByID[dto.id] = template
        }
      }
      if let dto = envelope.siriSettings {
        let settings = existingSiri.first ?? SiriAccessSettings(id: dto.id)
        if existingSiri.isEmpty { context.insert(settings) }
        settings.isSiriAccessEnabled = dto.isSiriAccessEnabled
        settings.allowAssignmentSummaries = dto.allowAssignmentSummaries
        settings.allowDetailedScores = dto.allowDetailedScores
        settings.allowGPAResponses = dto.allowGPAResponses
        settings.allowCreatingDrafts = dto.allowCreatingDrafts
        settings.updatedAt = dto.updatedAt
      }
      for dto in envelope.plannerScenarios where !existingScenarioIDs.contains(dto.id) {
        let scenario = PlannerScenario(
          id: dto.id, name: dto.name, scenarioType: dto.scenarioType,
          associatedTerm: dto.associatedTermID.flatMap { termsByID[$0] },
          createdAt: dto.createdAt, updatedAt: dto.updatedAt, sortOrder: dto.sortOrder,
          targetGPA: dto.targetGPA,
          selectedCourseIDs: dto.selectedCourseIDs.map(Set.init),
          assumedGrades: dto.assumedGrades?.reduce(into: [:]) { result, entry in
            if let grade = CourseGrade(rawValue: entry.value) { result[entry.key] = grade }
          } ?? [:])
        context.insert(scenario)
        dto.courses.forEach {
          context.insert(
            SimulatedCourse(
              id: $0.id, sourceCourseID: $0.sourceCourseID,
              courseCode: $0.courseCode, units: $0.units, grade: $0.grade,
              isIncludedInGPA: $0.isIncludedInGPA, isMajorCourse: $0.isMajorCourse,
              isUpperDivision: $0.isUpperDivision, confidence: $0.confidence,
              notes: $0.notes, scenario: scenario))
        }
      }
      preferences.displayName = envelope.preferences.displayName
      preferences.major = envelope.preferences.major
      preferences.targetGPA = envelope.preferences.targetGPA
      preferences.firstAcademicYear = envelope.preferences.firstAcademicYear
      preferences.decimalPrecision = envelope.preferences.decimalPrecision
      preferences.appearance = envelope.preferences.appearance
      if let language = envelope.preferences.language { preferences.language = language }
      preferences.hapticsEnabled = envelope.preferences.hapticsEnabled
      preferences.showMajorGPA = envelope.preferences.showMajorGPA
      preferences.showUpperDivisionGPA = envelope.preferences.showUpperDivisionGPA
      preferences.showRepeatSummary = envelope.preferences.showRepeatSummary
      preferences.defaultGradingBasis = envelope.preferences.defaultGradingBasis
      if let privacyLockEnabled = envelope.preferences.privacyLockEnabled {
        preferences.privacyLockEnabled = privacyLockEnabled
      }
      if let privacyLockDelay = envelope.preferences.privacyLockDelay {
        preferences.privacyLockDelay = privacyLockDelay
      }
      if let preferredAppIcon = envelope.preferences.preferredAppIcon {
        preferences.preferredAppIcon = preferredAppIcon
      }
      if let onboardingCompleted = envelope.preferences.onboardingCompleted {
        preferences.onboardingCompleted = onboardingCompleted
      }
      if let demoDataLoaded = envelope.preferences.demoDataLoaded {
        preferences.demoDataLoaded = demoDataLoaded
      }
      for policy in try context.fetch(FetchDescriptor<CourseGradingPolicy>()) where !policy.isDeleted {
        policy.lastCalculatedAt = .now
      }
      try context.save()
      Set(replacedNotificationIdentifiers + disabledReminderIdentifiers).forEach {
        GradeItemNotificationService.cancel(identifier: $0)
      }
      if !importedReminderSnapshots.isEmpty {
        Task {
          for reminder in importedReminderSnapshots {
            try? await GradeItemNotificationService.sync(reminder)
          }
        }
      }
    } catch {
      context.rollback()
      throw error
    }
  }

  /// A backup is a single transaction. Duplicate identifiers inside one file
  /// are ambiguous and can otherwise be silently coalesced while the import
  /// is being applied, so reject the file before mutating any model.
  private static func validateUniqueRecordIDs(in envelope: BackupEnvelope) throws {
    func requireUnique<T>(_ values: [T], key: (T) -> UUID) throws {
      var seen = Set<UUID>()
      for value in values where !seen.insert(key(value)).inserted {
        throw BackupError.invalidFile
      }
    }

    try requireUnique(envelope.terms, key: \.id)
    try requireUnique(envelope.courses, key: \.id)
    try requireUnique(envelope.plannerScenarios, key: \.id)
    try requireUnique(envelope.plannerScenarios.flatMap(\.courses), key: \.id)
    try requireUnique(envelope.gradingPolicies ?? [], key: \.id)
    try requireUnique(envelope.gradingCategories ?? [], key: \.id)
    try requireUnique(envelope.gradeItems ?? [], key: \.id)
    try requireUnique(envelope.gradeScales ?? [], key: \.id)
    try requireUnique(envelope.forecastScenarios ?? [], key: \.id)
    try requireUnique(envelope.courseTemplates ?? [], key: \.id)
    try requireUnique(envelope.courseReminderDefaults ?? [], key: \.courseID)
  }
}
