import ImageIO
import Vision

/// Deterministic, on-device fallback for a vision-model load failure. It is
/// intentionally separate from the multimodal path so the UI can report that
/// the image model was unavailable without pretending OCR was visual reasoning.
nonisolated enum SyllabusImageTextRecognizer {
    static func recognize(data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            return ""
        }
        return recognize(image: image)
    }

    static func recognize(image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        return request.results?
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n") ?? ""
    }
}
