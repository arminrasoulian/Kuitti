import UIKit

/// The one image-processing step worth doing (the doc camera's crop/deskew comes free).
/// No OCR, no binarization — Gemini reads receipt pixels better than stitched OCR text,
/// and contrast tricks risk destroying faint thermal print.
nonisolated enum ImageProcessor {
    /// Receipts: short side ≈ 768 px (one Gemini tile wide), long edge ≤ 2560 px, JPEG 0.7.
    /// The same bytes are sent to Gemini and persisted on the transaction (~200–500 KB/page).
    static func processReceiptPage(_ image: UIImage) -> Data? {
        downscaled(image, shortSideTarget: 768, longSideCap: 2560)?.jpegData(compressionQuality: 0.7)
    }

    /// Product packages have large type; 1024 px long side is plenty (1–2 tiles).
    static func processProductPhoto(_ image: UIImage) -> Data? {
        downscaled(image, shortSideTarget: nil, longSideCap: 1024)?.jpegData(compressionQuality: 0.7)
    }

    private static func downscaled(_ image: UIImage, shortSideTarget: CGFloat?, longSideCap: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)

        var scale: CGFloat = 1
        if let shortSideTarget {
            scale = min(shortSideTarget / shortSide, 1)
        } else {
            scale = min(longSideCap / longSide, 1)
        }
        if longSide * scale > longSideCap {
            scale = longSideCap / longSide
        }
        guard scale < 1 else { return image }

        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
