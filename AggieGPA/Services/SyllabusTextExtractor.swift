import Foundation
import PDFKit
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Reads document-native text and page images. This type deliberately contains no Vision or OCR API.
nonisolated enum SyllabusTextExtractor {
    struct StoredPage: Codable, Equatable, Sendable {
        let number: Int
        let text: String
    }

    struct Page: @unchecked Sendable {
        let number: Int
        let text: String?
        let image: CGImage?
        /// A bounded, orientation-correct copy kept for the on-device vision
        /// runtime. `CGImage` is useful for the preview, but it is not a
        /// portable inference input and cannot survive a detached task by
        /// itself.
        let imageData: Data?

        init(number: Int, text: String?, image: CGImage?, imageData: Data? = nil) {
            self.number = number
            self.text = text
            self.image = image
            self.imageData = imageData ?? image.flatMap(SyllabusTextExtractor.encodedImageData)
        }
    }

    struct Document: @unchecked Sendable {
        let pages: [Page]
        let source: SyllabusImportSource
    }

    static func storedPageData(from document: Document) -> Data? {
        let pages = document.pages.compactMap { page -> StoredPage? in
            guard let text = page.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return StoredPage(number: page.number, text: text)
        }
        guard !pages.isEmpty else { return nil }
        return try? JSONEncoder().encode(pages)
    }

    static func storedText(from document: Document) -> String? {
        let text = document.pages.compactMap { page in
            page.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    static func document(
        storedPageData: Data?,
        fallbackText: String?,
        source: SyllabusImportSource = .pastedText
    ) -> Document? {
        if let data = storedPageData,
           let pages = try? JSONDecoder().decode([StoredPage].self, from: data),
           !pages.isEmpty {
            return Document(
                pages: pages.map { Page(number: $0.number, text: $0.text, image: nil) },
                source: source
            )
        }
        guard let fallbackText = fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines), !fallbackText.isEmpty else {
            return nil
        }
        return Document(pages: [Page(number: 1, text: fallbackText, image: nil)], source: source)
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
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = normalizedImage(from: source),
           let imageData = encodedImageData(from: image) {
            return Document(
                pages: [Page(number: 1, text: nil, image: image, imageData: imageData)],
                source: .image
            )
        }
        throw ExtractionError.unsupportedTextDocument
    }

    static func read(images: [UIImage]) throws -> Document {
        let pages = try images.enumerated().map { offset, image in
            guard image.size.width > 0, image.size.height > 0 else {
                throw ExtractionError.noReadableContent
            }
            let scale = min(CGFloat(1), CGFloat(2048) / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let normalized = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let cgImage = normalized.cgImage else { throw ExtractionError.noReadableContent }
            guard let imageData = encodedImageData(from: cgImage) else {
                throw ExtractionError.noReadableContent
            }
            return Page(
                number: offset + 1,
                text: nil,
                image: cgImage,
                imageData: imageData
            )
        }
        guard !pages.isEmpty else { throw ExtractionError.noReadableContent }
        return Document(pages: pages, source: .camera)
    }

    /// Decode a bounded, orientation-correct raster without first allocating
    /// the full-resolution camera image. Preserve every selected page.
    static func readImageData(_ data: Data, number: Int) throws -> Page {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = normalizedImage(from: source) else {
            throw ExtractionError.noReadableContent
        }
        guard let imageData = encodedImageData(from: image) else {
            throw ExtractionError.noReadableContent
        }
        return Page(number: number, text: nil, image: image, imageData: imageData)
    }

    private static func normalizedImage(from source: CGImageSource) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
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
            return image.flatMap { image -> Page? in
                guard let imageData = encodedImageData(from: image) else { return nil }
                return Page(
                    number: index + 1,
                    text: nil,
                    image: image,
                    imageData: imageData
                )
            }
        }
        guard !pages.isEmpty else { throw ExtractionError.noReadableContent }
        return Document(pages: pages, source: .pdf)
    }

    /// Keep the inference payload bounded and independent from the source
    /// provider. JPEG is sufficient for syllabus pages and avoids retaining a
    /// potentially huge Photos/Files original in memory while analysis runs.
    private static func encodedImageData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
