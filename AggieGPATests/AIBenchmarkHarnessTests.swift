import Foundation
import XCTest
@testable import AggieGPA

/// A small, deterministic benchmark runner kept in the test target so it can
/// be executed without shipping benchmark-only storage or UI. It measures the
/// same AIProvider contract used by syllabus import and writes a machine-
/// readable report. A local fallback run is useful evidence, but is never
/// presented as a language-model runtime result.
final class AIBenchmarkHarnessTests: XCTestCase {
    func testFallbackBenchmarkRunsEveryFixedCaseAndWritesReport() async throws {
        let report = try await AIBenchmarkRunner.run(provider: NoAIProvider(), benchmarkKind: .deterministicFallback)
        XCTAssertEqual(report.cases.count, AIBenchmarkDataset.cases.count)
        XCTAssertTrue(report.cases.allSatisfy { $0.executionStatus == .completed })
        XCTAssertEqual(report.datasetRevision, 2)
        XCTAssertEqual(report.cases.filter { $0.qualityStatus == .notAssessed }.map(\.id).sorted(), ["quick-add-en", "quick-add-zh"])
        XCTAssertEqual(report.aggregate.casesNotAssessed, 2)
        XCTAssertEqual(report.aggregate.requiredFactsTotal, 15, "Unassessed Quick Add facts must not dilute syllabus accuracy metrics.")
        XCTAssertEqual(report.runtime.providerName, "Local Rule Recognition")
        XCTAssertFalse(report.runtime.isLanguageModel)

        let url = AIBenchmarkRunner.defaultReportURL
        try AIBenchmarkRunner.write(report, to: url)
        let encoded = try Data(contentsOf: url)
        XCTAssertFalse(encoded.isEmpty)
        print("AI benchmark report: \(url.path)")
        print(String(decoding: encoded, as: UTF8.self))
    }

    func testRuntimeProbeRecordsUnavailablePiecesWithoutDownloadingAnything() throws {
        let probe = AIBenchmarkRuntimeProbe.current()
        XCTAssertFalse(probe.modelDownloadAttempted)
        XCTAssertFalse(probe.realModelBenchmarkClaimed)
        XCTAssertNotNil(probe.llamaCpp)
        XCTAssertNotNil(probe.mlxSwift)
        XCTAssertNotNil(probe.appleFoundationModels)

        let url = AIBenchmarkRunner.runtimeProbeURL
        try AIBenchmarkRunner.write(probe, to: url)
        print("AI runtime probe: \(url.path)")
    }
}

private enum AIBenchmarkRunner {
    static let defaultReportURL = URL(fileURLWithPath: "/private/tmp/AggieGPA-ai-benchmark-fallback.json")
    static let runtimeProbeURL = URL(fileURLWithPath: "/private/tmp/AggieGPA-ai-runtime-probe.json")

    static func run(
        provider: any OnDeviceAIProvider,
        benchmarkKind: AIBenchmarkKind
    ) async throws -> AIBenchmarkReport {
        let started = ContinuousClock.now
        var results: [AIBenchmarkCaseResult] = []

        for benchmarkCase in AIBenchmarkDataset.cases {
            let caseStarted = ContinuousClock.now
            if benchmarkCase.kind == .quickAdd {
                results.append(.init(
                    id: benchmarkCase.id,
                    kind: benchmarkCase.kind.rawValue,
                    language: benchmarkCase.language,
                    executionStatus: .completed,
                    qualityStatus: .notAssessed,
                    durationSeconds: seconds(from: caseStarted, to: .now),
                    requiredFacts: AIBenchmarkFactEvaluator.notAssessedQuickAddFacts(benchmarkCase),
                    hallucinatedValues: [],
                    jsonOutputValid: nil,
                    extractionAccuracy: nil,
                    ruleAccuracy: nil,
                    providerName: provider.providerName,
                    modelName: nil,
                    metrics: nil,
                    crashOrOOMObserved: false,
                    error: nil
                ))
                continue
            }
            let document = SyllabusTextExtractor.Document(
                pages: [SyllabusTextExtractor.Page(number: 1, text: benchmarkCase.input, image: nil)],
                source: .pastedText
            )
            do {
                let result = try await provider.analyze(document: document) { _ in }
                let factResults = AIBenchmarkFactEvaluator.evaluate(benchmarkCase, analysis: result.analysis)
                let hallucinatedValues = AIBenchmarkFactEvaluator.hallucinatedValues(
                    in: result.analysis,
                    source: benchmarkCase.input
                )
                results.append(.init(
                    id: benchmarkCase.id,
                    kind: benchmarkCase.kind.rawValue,
                    language: benchmarkCase.language,
                    executionStatus: .completed,
                    qualityStatus: factResults.allSatisfy(\.satisfied) && hallucinatedValues.isEmpty ? .pass : .needsReview,
                    durationSeconds: seconds(from: caseStarted, to: .now),
                    requiredFacts: factResults,
                    hallucinatedValues: hallucinatedValues,
                    jsonOutputValid: nil,
                    extractionAccuracy: nil,
                    ruleAccuracy: nil,
                    providerName: result.providerName,
                    modelName: result.modelName,
                    metrics: result.metrics,
                    crashOrOOMObserved: false,
                    error: nil
                ))
            } catch {
                results.append(.init(
                    id: benchmarkCase.id,
                    kind: benchmarkCase.kind.rawValue,
                    language: benchmarkCase.language,
                    executionStatus: .failed,
                    qualityStatus: .notAssessed,
                    durationSeconds: seconds(from: caseStarted, to: .now),
                    requiredFacts: benchmarkCase.requiredFacts.map { .init(fact: $0, satisfied: false, reason: "Provider failed before quality evaluation.") },
                    hallucinatedValues: [],
                    jsonOutputValid: nil,
                    extractionAccuracy: nil,
                    ruleAccuracy: nil,
                    providerName: provider.providerName,
                    modelName: nil,
                    metrics: nil,
                    crashOrOOMObserved: false,
                    error: String(describing: error)
                ))
            }
        }

        let modelName = results.compactMap(\.modelName).first
        let isLanguageModel = provider is OpenSourceLocalProvider
        let modelQuantization: String? = modelName.flatMap { $0.contains("Q4") ? "Q4_K_M" : nil }
        let modelFileBytes: Int64? = isLanguageModel ? OnDeviceAIRuntimeAvailability.modelFileBytes : nil
        let runtime = AIBenchmarkRuntimeSummary(
            providerName: provider.providerName,
            modelName: modelName,
            isLanguageModel: isLanguageModel,
            modelQuantization: modelQuantization,
            modelFileBytes: modelFileBytes,
            completedWithoutCrash: true,
            modelDownloadAttempted: false
        )

        let completedCount = results.filter { $0.executionStatus == .completed }.count
        let qualityPassCount = results.filter { $0.qualityStatus == .pass }.count
        let assessedResults = results.filter { $0.qualityStatus != .notAssessed }
        let facts = assessedResults.flatMap(\.requiredFacts)
        let hallucinations = assessedResults.flatMap(\.hallucinatedValues)
        let observedThermalStates: [String] = Array(Set(results.compactMap { $0.metrics?.thermalState })).sorted()
        let hallucinationRate: Double? = assessedResults.isEmpty
            ? nil
            : Double(assessedResults.filter { !$0.hallucinatedValues.isEmpty }.count) / Double(assessedResults.count)
        let jsonSuccesses = assessedResults.compactMap { value -> Double? in
            guard let valid = value.jsonOutputValid else { return nil }
            return valid ? 1 : 0
        }
        let jsonSuccessRate: Double? = jsonSuccesses.average
        let extractionAccuracy: Double? = assessedResults.compactMap { $0.extractionAccuracy }.average
        let ruleAccuracy: Double? = assessedResults.compactMap { $0.ruleAccuracy }.average
        let firstTokenSeconds: Double? = assessedResults.compactMap { $0.metrics?.firstTokenSeconds }.min()
        let peakMemoryBytes: UInt64? = assessedResults.compactMap { $0.metrics?.peakObservedMemoryBytes }.max()
        let aggregate = AIBenchmarkAggregate(
            casesCompleted: completedCount,
            casesWithQualityPass: qualityPassCount,
            casesNotAssessed: results.filter { $0.qualityStatus == .notAssessed }.count,
            requiredFactsSatisfied: facts.filter(\.satisfied).count,
            requiredFactsTotal: facts.count,
            hallucinatedValueCount: hallucinations.count,
            firstTokenSecondsObserved: firstTokenSeconds,
            peakMemoryBytesObserved: peakMemoryBytes,
            thermalStatesObserved: observedThermalStates,
            batteryAndPowerMeasured: false,
            jsonSuccessRate: jsonSuccessRate,
            extractionAccuracy: extractionAccuracy,
            ruleAccuracy: ruleAccuracy,
            hallucinationRate: hallucinationRate,
            crashOrOOMObserved: results.contains { $0.crashOrOOMObserved }
        )

        return AIBenchmarkReport(
            schemaVersion: 2,
            datasetRevision: AIBenchmarkDataset.revision,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            benchmarkKind: benchmarkKind,
            runtime: runtime,
            totalDurationSeconds: seconds(from: started, to: .now),
            cases: results,
            aggregate: aggregate
        )
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

private enum AIBenchmarkKind: String, Codable {
    case deterministicFallback
    case languageModelRuntime
}

private struct AIBenchmarkRuntimeSummary: Codable {
    var providerName: String
    var modelName: String?
    var isLanguageModel: Bool
    var modelQuantization: String?
    var modelFileBytes: Int64?
    var completedWithoutCrash: Bool
    var modelDownloadAttempted: Bool
}

private struct AIBenchmarkReport: Codable {
    var schemaVersion: Int
    var datasetRevision: Int
    var generatedAt: String
    var benchmarkKind: AIBenchmarkKind
    var runtime: AIBenchmarkRuntimeSummary
    var totalDurationSeconds: Double
    var cases: [AIBenchmarkCaseResult]
    var aggregate: AIBenchmarkAggregate
}

private struct AIBenchmarkCaseResult: Codable {
    enum ExecutionStatus: String, Codable { case completed, failed }
    enum QualityStatus: String, Codable { case pass, needsReview, notAssessed }

    var id: String
    var kind: String
    var language: String
    var executionStatus: ExecutionStatus
    var qualityStatus: QualityStatus
    var durationSeconds: Double
    var requiredFacts: [AIBenchmarkFactResult]
    var hallucinatedValues: [String]
    var jsonOutputValid: Bool?
    var extractionAccuracy: Double?
    var ruleAccuracy: Double?
    var providerName: String
    var modelName: String?
    var metrics: OnDeviceAIRuntimeMetrics?
    var crashOrOOMObserved: Bool
    var error: String?
}

private struct AIBenchmarkFactResult: Codable {
    var fact: String
    var satisfied: Bool
    var reason: String
}

private struct AIBenchmarkAggregate: Codable {
    var casesCompleted: Int
    var casesWithQualityPass: Int
    var casesNotAssessed: Int
    var requiredFactsSatisfied: Int
    var requiredFactsTotal: Int
    var hallucinatedValueCount: Int
    var firstTokenSecondsObserved: Double?
    var peakMemoryBytesObserved: UInt64?
    var thermalStatesObserved: [String]
    var batteryAndPowerMeasured: Bool
    var jsonSuccessRate: Double?
    var extractionAccuracy: Double?
    var ruleAccuracy: Double?
    var hallucinationRate: Double?
    var crashOrOOMObserved: Bool
}

struct AIBenchmarkRuntimeProbe: Codable {
    struct Component: Codable {
        var available: Bool
        var status: String
    }

    var generatedAt: String
    var llamaCpp: Component
    var mlxSwift: Component
    var appleFoundationModels: Component
    var modelInstalled: Bool
    var modelFileBytes: Int64?
    var modelDownloadAttempted: Bool
    var realModelBenchmarkClaimed: Bool

    static func current() -> AIBenchmarkRuntimeProbe {
        let llamaAvailable = OnDeviceAIRuntimeAvailability.llamaCppLinked
        let mlxAvailable = OnDeviceAIRuntimeAvailability.mlxSwiftLinked
        let foundationAvailable = OnDeviceAIRuntimeAvailability.appleFoundationModelsAvailable
        let modelInstalled = OnDeviceAIRuntimeAvailability.modelInstalled
        return .init(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            llamaCpp: .init(available: llamaAvailable, status: llamaAvailable ? "linked; not benchmarked by this probe" : "not linked in this build"),
            mlxSwift: .init(available: mlxAvailable, status: mlxAvailable ? "linked; not benchmarked by this probe" : "not linked in this build"),
            appleFoundationModels: .init(available: foundationAvailable, status: foundationAvailable ? "available; not benchmarked by this probe" : "provider is an explicit unavailable placeholder"),
            modelInstalled: modelInstalled,
            modelFileBytes: OnDeviceAIRuntimeAvailability.modelFileBytes,
            modelDownloadAttempted: false,
            realModelBenchmarkClaimed: false
        )
    }
}

private extension Collection where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private enum AIBenchmarkFactEvaluator {
    static func notAssessedQuickAddFacts(_ benchmarkCase: AIBenchmarkCase) -> [AIBenchmarkFactResult] {
        benchmarkCase.requiredFacts.map {
            .init(
                fact: $0,
                satisfied: false,
                reason: "Not assessed: OnDeviceAIProvider currently exposes syllabus GradingAnalysis only; assignment Quick Add requires its separate structured contract."
            )
        }
    }

    static func evaluate(_ benchmarkCase: AIBenchmarkCase, analysis: GradingAnalysis) -> [AIBenchmarkFactResult] {
        benchmarkCase.requiredFacts.map { fact in
            let result: (Bool, String)
            switch fact {
            case "weights total 100":
                let weights = analysis.categories.compactMap(\.weightPercent)
                let total = weights.reduce(Decimal.zero, +)
                result = (!weights.isEmpty && total == 100, "Recognized category weights total \(decimalText(total))%.")
            case "six distinct categories":
                result = (analysis.categories.count >= 6, "Recognized \(analysis.categories.count) distinct categories.")
            case "total points 1000":
                let points = analysis.categories.compactMap(\.totalPoints).reduce(Decimal.zero, +)
                result = (points == 1000, "Recognized category points total \(decimalText(points)).")
            case "mixed method requires review":
                result = (analysis.gradingMode == .mixed && analysis.warnings.contains { $0.requiresReview }, "Mode=\(analysis.gradingMode.rawValue), warnings=\(analysis.warnings.count).")
            case "drop count 2":
                result = (analysis.categories.contains { $0.dropLowestCount == 2 } || analysis.rules.contains { $0.kind == .dropLowest && $0.count == 2 }, "Drop-lowest values were not normalized to two.")
            case "total count 10":
                result = (analysis.categories.contains { $0.totalCount == 10 } || analysis.rules.contains { $0.totalCount == 10 }, "Total count 10 was not extracted.")
            case "best 4 of 5":
                result = (analysis.categories.contains { $0.bestCount == 4 && $0.totalCount == 5 } || analysis.rules.contains { $0.kind == .bestNOfM && $0.count == 4 && $0.totalCount == 5 }, "Best-N-of-M values were not extracted.")
            case "conditional replacement rule":
                result = (analysis.rules.contains { $0.kind == .replacementExam }, "No replacement-exam rule was returned.")
            case "extra credit separate from denominator":
                result = (analysis.categories.contains { $0.isExtraCredit } || analysis.rules.contains { $0.kind == .extraCredit }, "No explicit extra-credit structure was returned.")
            case "custom A threshold 94":
                result = (analysis.gradingScale.contains { $0.letter == .a && $0.minimumPercent == 94 }, "A threshold 94 was not extracted.")
            case "missing values stay nil":
                result = (analysis.categories.allSatisfy { $0.weightPercent == nil && $0.totalPoints == nil } || analysis.categories.isEmpty, "A concrete category value was returned for an ambiguous input.")
            case "manual review":
                result = (analysis.warnings.contains { $0.requiresReview }, "No review-required warning was returned.")
            case "conflict preserved":
                result = (analysis.warnings.contains { $0.code.contains("conflict") || $0.code.contains("duplicate") }, "No conflict warning was returned.")
            case "both evidence pages":
                result = (analysis.evidence.contains { $0.sourcePage == 2 } || analysis.categories.contains { $0.evidence.contains { $0.sourcePage == 2 } }, "No page-2 evidence was returned.")
            case "late-page grading facts retained":
                result = (analysis.categories.contains { $0.name.localizedCaseInsensitiveContains("homework") || $0.name.localizedCaseInsensitiveContains("project") || $0.name.localizedCaseInsensitiveContains("final") }, "No late-page grading categories were returned.")
            default:
                result = (false, "No evaluator exists for this fixed fact.")
            }
            return .init(fact: fact, satisfied: result.0, reason: result.1)
        }
    }

    static func hallucinatedValues(in analysis: GradingAnalysis, source: String) -> [String] {
        let normalizedSource = source.replacingOccurrences(of: ",", with: "")
        var values: [String] = []
        let decimals = analysis.categories.compactMap(\.weightPercent) + analysis.categories.compactMap(\.totalPoints)
            + analysis.gradingScale.map(\.minimumPercent)
        for value in decimals {
            let text = decimalText(value)
            if !normalizedSource.contains(text) { values.append(text) }
        }
        return Array(Set(values)).sorted()
    }

    private static func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
