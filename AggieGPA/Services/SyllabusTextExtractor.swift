import Foundation
import PDFKit
import UIKit

/// Reads document-native text and page images. This type deliberately contains no Vision or OCR API.
enum SyllabusTextExtractor {
    struct Page: @unchecked Sendable {
        let number: Int
        let text: String?
        let image: CGImage?
    }

    struct Document: @unchecked Sendable {
        let pages: [Page]
        let source: SyllabusImportSource
    }

    enum ExtractionError: LocalizedError {
        case unreadableFile, unsupportedTextDocument, noReadableContent

        var errorDescription: String? {
            switch self {
            case .unreadableFile: String(localized: "The selected syllabus could not be read.")
            case .unsupportedTextDocument: String(localized: "This text document format is not supported. Paste its text instead.")
            case .noReadableContent: String(localized: "No readable text or image pages were found.")
            }
        }
    }

    static func read(url: URL) throws -> Document {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return try readPDF(url) }
        if ["txt", "text", "md", "csv"].contains(ext) {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
                throw ExtractionError.unsupportedTextDocument
            }
            return Document(pages: [Page(number: 1, text: text, image: nil)], source: .pastedText)
        }
        if let image = UIImage(contentsOfFile: url.path)?.cgImage {
            return Document(pages: [Page(number: 1, text: nil, image: image)], source: .image)
        }
        throw ExtractionError.unsupportedTextDocument
    }

    static func read(images: [UIImage]) throws -> Document {
        let pages = images.enumerated().compactMap { offset, image in
            image.cgImage.map { Page(number: offset + 1, text: nil, image: $0) }
        }
        guard !pages.isEmpty else { throw ExtractionError.noReadableContent }
        return Document(pages: pages, source: .camera)
    }

    private static func readPDF(_ url: URL) throws -> Document {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadableFile }
        let pages = (0..<document.pageCount).compactMap { index -> Page? in
            guard let page = document.page(at: index) else { return nil }
            let nativeText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let nativeText, !nativeText.isEmpty { return Page(number: index + 1, text: nativeText, image: nil) }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = min(2, max(1.25, 144 / max(bounds.width / 72, 1)))
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            UIGraphicsBeginImageContextWithOptions(size, true, 1)
            UIColor.white.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
            guard let context = UIGraphicsGetCurrentContext() else { UIGraphicsEndImageContext(); return nil }
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            let image = UIGraphicsGetImageFromCurrentImageContext()?.cgImage
            UIGraphicsEndImageContext()
            return image.map { Page(number: index + 1, text: nil, image: $0) }
        }
        guard !pages.isEmpty else { throw ExtractionError.noReadableContent }
        return Document(pages: pages, source: .pdf)
    }
}
