import Foundation
import Testing
import UniformTypeIdentifiers
import UIKit
@testable import Kuitti

/// Rasterizing shared receipt files (images + PDFs) into page images for the import flow.
@MainActor
struct ReceiptFileLoaderTests {
    @Test func pdfDataRendersOnePerPage() {
        let pdf = Self.makePDF(pages: 2)
        let images = ReceiptFileLoader.images(from: pdf, type: .pdf)
        #expect(images.count == 2)
        #expect(images.allSatisfy { $0.size.width > 0 && $0.size.height > 0 })
    }

    @Test func imageDataYieldsOneImage() {
        let jpeg = Self.makeJPEG()
        let images = ReceiptFileLoader.images(from: jpeg, type: .jpeg)
        #expect(images.count == 1)
    }

    @Test func junkDataYieldsNothing() {
        #expect(ReceiptFileLoader.images(from: Data([0x00, 0x01, 0x02]), type: .jpeg).isEmpty)
        #expect(ReceiptFileLoader.images(from: Data("not a pdf".utf8), type: .pdf).isEmpty)
    }

    // MARK: - Fixtures

    private static func makePDF(pages: Int) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 300)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for _ in 0..<pages {
                context.beginPage()
                UIColor.black.setFill()
                UIRectFill(CGRect(x: 20, y: 20, width: 60, height: 20))
            }
        }
    }

    private static func makeJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }
}
