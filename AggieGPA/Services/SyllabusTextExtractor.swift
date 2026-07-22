import Foundation
import PDFKit
import UIKit
import Vision

enum SyllabusTextExtractor {
    struct ExtractionResult: Sendable {
        let text: String
        let confidence: Double
    }

    static func extract(from url: URL) async throws -> ExtractionResult {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadableFile }
            let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ExtractionError.noText }
            return ExtractionResult(text: text, confidence: 1)
        }
        let data = try Data(contentsOf: url)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { throw ExtractionError.unreadableFile }
        return try await recognize(cgImage)
    }

    static func recognize(_ image: CGImage) async throws -> ExtractionResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let candidates = observations.compactMap { observation -> (String, Float)? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return (candidate.string, candidate.confidence)
                }
                let text = candidates.map(\.0).joined(separator: "\n")
                guard !text.isEmpty else { continuation.resume(throwing: ExtractionError.noText); return }
                let confidence = candidates.isEmpty ? 0 : candidates.reduce(0) { $0 + Double($1.1) } / Double(candidates.count)
                continuation.resume(returning: ExtractionResult(text: text, confidence: confidence))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum ExtractionError: LocalizedError {
        case unreadableFile, noText
        var errorDescription: String? {
            switch self { case .unreadableFile: "The selected syllabus could not be read."; case .noText: "No readable text was found." }
        }
    }
}
