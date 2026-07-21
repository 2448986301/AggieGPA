import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case unsupportedSchema(Int)
    case invalidFile
    case fileAccess

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "This backup uses schema version \(version), which this version of Aggie GPA cannot import."
        case .invalidFile: "This file is not a valid Aggie GPA backup. Your current data was not changed."
        case .fileAccess: "The selected file could not be read. Check file access and try again."
        }
    }
}

@MainActor
enum BackupService {
    static func makeEnvelope(terms: [AcademicTerm], scenarios: [PlannerScenario], preferences: UserPreferences) -> BackupEnvelope {
        let termDTOs = terms.map {
            BackupEnvelope.TermDTO(id: $0.id, academicYear: $0.academicYear, termType: $0.termType,
                                   displayName: $0.displayName, startDate: $0.startDate, endDate: $0.endDate,
                                   isIncludedInCumulativeGPA: $0.isIncludedInCumulativeGPA, notes: $0.notes,
                                   createdAt: $0.createdAt, updatedAt: $0.updatedAt, sortOrder: $0.sortOrder)
        }
        let courseDTOs = terms.flatMap(\.courses).map {
            BackupEnvelope.CourseDTO(id: $0.id, termID: $0.term?.id, courseCode: $0.courseCode,
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
                    BackupEnvelope.SimulatedCourseDTO(id: $0.id, sourceCourseID: $0.sourceCourseID,
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
        return BackupEnvelope(schemaVersion: BackupEnvelope.currentSchemaVersion, exportDate: .now,
                              appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                              terms: termDTOs, courses: courseDTOs,
                              plannerScenarios: scenarioDTOs, preferences: preferenceDTO)
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
            guard envelope.schemaVersion == BackupEnvelope.currentSchemaVersion else {
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
        return ImportPreview(envelope: envelope,
                             duplicateTermCount: envelope.terms.filter { termIDs.contains($0.id) }.count,
                             duplicateCourseCount: envelope.courses.filter { courseIDs.contains($0.id) }.count)
    }

    static func apply(_ envelope: BackupEnvelope, mode: ImportMode, context: ModelContext,
                      existingTerms: [AcademicTerm], existingScenarios: [PlannerScenario],
                      preferences: UserPreferences) throws {
        if mode == .replace {
            existingScenarios.forEach(context.delete)
            existingTerms.forEach(context.delete)
            try context.save()
        }

        let existingTermIDs = mode == .merge ? Set(existingTerms.map(\.id)) : []
        let existingCourseIDs = mode == .merge ? Set(existingTerms.flatMap(\.courses).map(\.id)) : []
        let existingScenarioIDs = mode == .merge ? Set(existingScenarios.map(\.id)) : []
        var termsByID = Dictionary(uniqueKeysWithValues: (mode == .merge ? existingTerms : []).map { ($0.id, $0) })

        for dto in envelope.terms where !existingTermIDs.contains(dto.id) {
            let term = AcademicTerm(id: dto.id, academicYear: dto.academicYear, termType: dto.termType,
                                    displayName: dto.displayName, startDate: dto.startDate, endDate: dto.endDate,
                                    isIncludedInCumulativeGPA: dto.isIncludedInCumulativeGPA, notes: dto.notes,
                                    createdAt: dto.createdAt, updatedAt: dto.updatedAt, sortOrder: dto.sortOrder)
            context.insert(term)
            termsByID[dto.id] = term
        }
        for dto in envelope.courses where !existingCourseIDs.contains(dto.id) {
            let course = CourseRecord(id: dto.id, courseCode: dto.courseCode, courseTitle: dto.courseTitle,
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
        for dto in envelope.plannerScenarios where !existingScenarioIDs.contains(dto.id) {
            let scenario = PlannerScenario(id: dto.id, name: dto.name, scenarioType: dto.scenarioType,
                                           associatedTerm: dto.associatedTermID.flatMap { termsByID[$0] },
                                           createdAt: dto.createdAt, updatedAt: dto.updatedAt, sortOrder: dto.sortOrder)
            context.insert(scenario)
            dto.courses.forEach {
                context.insert(SimulatedCourse(id: $0.id, sourceCourseID: $0.sourceCourseID,
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
    }
}
