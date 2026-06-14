import Foundation
import PDFKit
import UniformTypeIdentifiers
import UIKit

/// Turns a shared/opened receipt file (image or PDF) into page images for the import flow.
/// Only rasterizes — downscaling/JPEG stays the job of `ImageProcessor` inside the flow.
/// Used by the "Open in / Copy to Kuitti" path and the Scan hub's "Files" picker.
enum ReceiptFileLoader {
    /// Cap pages from a multi-page PDF so a huge document can't balloon memory.
    static let maxPDFPages = 10
    private static let pdfRenderScale: CGFloat = 2

    static func images(from url: URL) -> [UIImage] {
        let type = UTType(filenameExtension: url.pathExtension)
        if type == .pdf || url.pathExtension.lowercased() == "pdf" {
            if let document = PDFDocument(url: url) {
                return images(from: document)
            }
            return []
        }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return [] }
        return [image]
    }

    static func images(from data: Data, type: UTType) -> [UIImage] {
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(data: data) else { return [] }
            return images(from: document)
        }
        guard let image = UIImage(data: data) else { return [] }
        return [image]
    }

    private static func images(from document: PDFDocument) -> [UIImage] {
        let count = min(document.pageCount, maxPDFPages)
        guard count > 0 else { return [] }
        return (0..<count).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * pdfRenderScale, height: bounds.height * pdfRenderScale)
            guard size.width > 0, size.height > 0 else { return nil }
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: pdfRenderScale, y: -pdfRenderScale)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
        }
    }
}
