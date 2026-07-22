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
    terms: [AcademicTerm], scenarios: [PlannerScenario], preferences: UserPreferences,
    policies: [CourseGradingPolicy] = [], categories: [GradingCategory] = [],
    items: [GradeItem] = [],
    scales: [GradeScale] = [], forecasts: [ForecastScenario] = [],
    siriSettings: SiriAccessSettings? = nil
  ) -> BackupEnvelope {
    let termDTOs = terms.map {
      BackupEnvelope.TermDTO(
        id: $0.id, academicYear: $0.academicYear, termType: $0.termType,
        displayName: $0.displayName, startDate: $0.startDate, endDate: $0.endDate,
        isIncludedInCumulativeGPA: $0.isIncludedInCumulativeGPA, notes: $0.notes,
        createdAt: $0.createdAt, updatedAt: $0.updatedAt, sortOrder: $0.sortOrder)
    }
    let courseDTOs = terms.flatMap(\.courses).map {
      BackupEnvelope.CourseDTO(
        id: $0.id, termID: $0.term?.id, courseCode: $0.courseCode,
        courseTitle: $0.courseTitle, units: $0.units, grade: $0.grade,
        gradingBasis: $0.gradingBasis, institution: $0.institution,
        isMajorCourse: $0.isMajorCourse, isUpperDivision: $0.isUpperDivision,
        isIncludedInGPA: $0.isIncludedInGPA, isTransferCourse: $0.isTransferCourse,
        isRepeatCourse: $0.isRepeatCourse, repeatGroupID: $0.repeatGroupID,
        repeatAttemptOrder: $0.repeatAttemptOrder,
        repeatHandlingMode: $0.repeatHandlingMode, targetGrade: $0.targetGrade,
        notes: $0.notes, customColor: $0.customColor,
        createdAt: $0.createdAt, updatedAt: $0.updatedAt, isDemoData: $0.isDemoData)
    }
    let scenarioDTOs = scenarios.map { scenario in
      BackupEnvelope.ScenarioDTO(
        id: scenario.id, name: scenario.name, scenarioType: scenario.scenarioType,
        associatedTermID: scenario.associatedTerm?.id, createdAt: scenario.createdAt,
        updatedAt: scenario.updatedAt, sortOrder: scenario.sortOrder,
        courses: scenario.simulatedCourses.map {
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
      defaultGradingBasis: preferences.defaultGradingBasis)
    return BackupEnvelope(
      schemaVersion: BackupEnvelope.currentSchemaVersion, exportDate: .now,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
      terms: termDTOs, courses: courseDTOs,
      plannerScenarios: scenarioDTOs, preferences: preferenceDTO,
      gradingPolicies: policies.compactMap { policy in
        guard let courseID = policy.course?.id else { return nil }
        return .init(
          id: policy.id, courseID: courseID, gradingMethod: policy.gradingMethod,
          normalizeCurrentGrade: policy.normalizeCurrentGrade,
          missingItemPolicy: policy.missingItemPolicy,
          missingPolicyConfirmed: policy.missingPolicyConfirmed,
          targetPercentage: policy.targetPercentage,
          targetLetterGrade: policy.targetLetterGrade,
          syllabusImportSource: policy.syllabusImportSource,
          importStatus: policy.importStatus, manualReviewReason: policy.manualReviewReason,
          lastCalculatedAt: policy.lastCalculatedAt, createdAt: policy.createdAt,
          updatedAt: policy.updatedAt)
      },
      gradingCategories: categories.compactMap { category in
        guard let courseID = category.course?.id else { return nil }
        return .init(
          id: category.id, courseID: courseID, name: category.name,
          categoryType: category.categoryType,
          weight: category.weight, calculationMode: category.calculationMode,
          dropLowestCount: category.dropLowestCount, isExtraCredit: category.isExtraCredit,
          isIncluded: category.isIncluded, sortOrder: category.sortOrder,
          createdAt: category.createdAt, updatedAt: category.updatedAt)
      },
      gradeItems: items.compactMap { item in
        guard let courseID = item.course?.id else { return nil }
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
        guard let courseID = scale.course?.id else { return nil }
        return .init(
          id: scale.id, courseID: courseID, name: scale.name, boundaries: scale.boundaries,
          isLetterPredictionEnabled: scale.isLetterPredictionEnabled,
          isCommonTemplate: scale.isCommonTemplate,
          curveNote: scale.curveNote, requiresManualReview: scale.requiresManualReview,
          createdAt: scale.createdAt, updatedAt: scale.updatedAt)
      },
      forecastScenarios: forecasts.compactMap { forecast in
        guard let courseID = forecast.course?.id else { return nil }
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

  static func preview(_ envelope: BackupEnvelope, existingTerms: [AcademicTerm]) -> ImportPreview {
    let termIDs = Set(existingTerms.map(\.id))
    let courseIDs = Set(existingTerms.flatMap(\.courses).map(\.id))
    return ImportPreview(
      envelope: envelope,
      duplicateTermCount: envelope.terms.filter { termIDs.contains($0.id) }.count,
      duplicateCourseCount: envelope.courses.filter { courseIDs.contains($0.id) }.count)
  }

  static func apply(
    _ envelope: BackupEnvelope, mode: ImportMode, context: ModelContext,
    existingTerms: [AcademicTerm], existingScenarios: [PlannerScenario],
    preferences: UserPreferences
  ) throws {
    do {
      let existingPolicies = try context.fetch(FetchDescriptor<CourseGradingPolicy>())
      let existingCategories = try context.fetch(FetchDescriptor<GradingCategory>())
      let existingItems = try context.fetch(FetchDescriptor<GradeItem>())
      let existingScales = try context.fetch(FetchDescriptor<GradeScale>())
      let existingForecasts = try context.fetch(FetchDescriptor<ForecastScenario>())
      let existingSiri = try context.fetch(FetchDescriptor<SiriAccessSettings>())
      let replacedNotificationIdentifiers = mode == .replace ? existingItems.map(\.notificationIdentifier) : []
      if mode == .replace {
        existingItems.forEach(context.delete)
        existingCategories.forEach(context.delete)
        existingPolicies.forEach(context.delete)
        existingScales.forEach(context.delete)
        existingForecasts.forEach(context.delete)
        existingScenarios.forEach(context.delete)
        existingTerms.forEach(context.delete)
      }

      let existingTermIDs = mode == .merge ? Set(existingTerms.map(\.id)) : []
      let existingCourseIDs = mode == .merge ? Set(existingTerms.flatMap(\.courses).map(\.id)) : []
      let existingScenarioIDs = mode == .merge ? Set(existingScenarios.map(\.id)) : []
      var termsByID = Dictionary(
        uniqueKeysWithValues: (mode == .merge ? existingTerms : []).map { ($0.id, $0) })

      for dto in envelope.terms where !existingTermIDs.contains(dto.id) {
        let term = AcademicTerm(
          id: dto.id, academicYear: dto.academicYear, termType: dto.termType,
          displayName: dto.displayName, startDate: dto.startDate, endDate: dto.endDate,
          isIncludedInCumulativeGPA: dto.isIncludedInCumulativeGPA, notes: dto.notes,
          createdAt: dto.createdAt, updatedAt: dto.updatedAt, sortOrder: dto.sortOrder)
        context.insert(term)
        termsByID[dto.id] = term
      }
      for dto in envelope.courses where !existingCourseIDs.contains(dto.id) {
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
      }
      let allCourses = try context.fetch(FetchDescriptor<CourseRecord>())
      let coursesByID = Dictionary(uniqueKeysWithValues: allCourses.map { ($0.id, $0) })
      let policyIDs = mode == .merge ? Set(existingPolicies.map(\.id)) : []
      for dto in envelope.gradingPolicies ?? [] where !policyIDs.contains(dto.id) {
        guard let course = coursesByID[dto.courseID] else { continue }
        context.insert(
          CourseGradingPolicy(
            id: dto.id, course: course, gradingMethod: dto.gradingMethod,
            normalizeCurrentGrade: dto.normalizeCurrentGrade,
            missingItemPolicy: dto.missingItemPolicy,
            missingPolicyConfirmed: dto.missingPolicyConfirmed,
            targetPercentage: dto.targetPercentage,
            targetLetterGrade: dto.targetLetterGrade,
            syllabusImportSource: dto.syllabusImportSource,
            importStatus: dto.importStatus, manualReviewReason: dto.manualReviewReason,
            lastCalculatedAt: dto.lastCalculatedAt, createdAt: dto.createdAt,
            updatedAt: dto.updatedAt))
      }
      let categoryIDs = mode == .merge ? Set(existingCategories.map(\.id)) : []
      var categoriesByID = Dictionary(
        uniqueKeysWithValues: (mode == .merge ? existingCategories : []).map { ($0.id, $0) })
      for dto in envelope.gradingCategories ?? [] where !categoryIDs.contains(dto.id) {
        guard let course = coursesByID[dto.courseID] else { continue }
        let category = GradingCategory(
          id: dto.id, course: course, name: dto.name, categoryType: dto.categoryType,
          weight: dto.weight, calculationMode: dto.calculationMode,
          dropLowestCount: dto.dropLowestCount, isExtraCredit: dto.isExtraCredit,
          isIncluded: dto.isIncluded, sortOrder: dto.sortOrder,
          createdAt: dto.createdAt, updatedAt: dto.updatedAt)
        context.insert(category)
        categoriesByID[dto.id] = category
      }
      let itemIDs = mode == .merge ? Set(existingItems.map(\.id)) : []
      var importedReminderSnapshots: [GradeItemReminderSnapshot] = []
      for dto in envelope.gradeItems ?? [] where !itemIDs.contains(dto.id) {
        guard let course = coursesByID[dto.courseID] else { continue }
        let item = GradeItem(
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
        if item.reminderEnabled { importedReminderSnapshots.append(GradeItemReminderSnapshot(item)) }
      }
      let scaleIDs = mode == .merge ? Set(existingScales.map(\.id)) : []
      for dto in envelope.gradeScales ?? [] where !scaleIDs.contains(dto.id) {
        guard let course = coursesByID[dto.courseID] else { continue }
        context.insert(
          GradeScale(
            id: dto.id, course: course, name: dto.name, boundaries: dto.boundaries,
            isLetterPredictionEnabled: dto.isLetterPredictionEnabled,
            isCommonTemplate: dto.isCommonTemplate, curveNote: dto.curveNote,
            requiresManualReview: dto.requiresManualReview, createdAt: dto.createdAt,
            updatedAt: dto.updatedAt))
      }
      let forecastIDs = mode == .merge ? Set(existingForecasts.map(\.id)) : []
      for dto in envelope.forecastScenarios ?? [] where !forecastIDs.contains(dto.id) {
        guard let course = coursesByID[dto.courseID] else { continue }
        context.insert(
          ForecastScenario(
            id: dto.id, course: course, name: dto.name, kind: dto.kind,
            assumedRemainingPercentage: dto.assumedRemainingPercentage,
            itemAssumptions: dto.itemAssumptions,
            isSelectedForGPAForecast: dto.isSelectedForGPAForecast,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt))
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
          createdAt: dto.createdAt, updatedAt: dto.updatedAt, sortOrder: dto.sortOrder)
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
      try context.save()
      replacedNotificationIdentifiers.forEach { GradeItemNotificationService.cancel(identifier: $0) }
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
}
