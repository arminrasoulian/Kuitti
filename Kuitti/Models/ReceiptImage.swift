import Foundation
import SwiftData

/// One receipt page per row. A dedicated model (instead of Data on Transaction) so that
/// multi-page long receipts work, the known [Data]-doesn't-externalize quirk is avoided,
/// and transaction fetches never touch blob rows.
@Model
final class ReceiptImage {
    var uuid: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var pageIndex: Int = 0
    var capturedAt: Date = Date()

    var transaction: Transaction?

    init(imageData: Data, pageIndex: Int) {
        self.imageData = imageData
        self.pageIndex = pageIndex
    }
}
