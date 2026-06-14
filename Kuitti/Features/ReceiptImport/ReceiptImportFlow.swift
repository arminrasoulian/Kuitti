import Foundation
import Observation
import SwiftData
import UIKit

/// Owns the multi-step scan → parse → review → save state. Created when the scan flow
/// is presented (fullScreenCover), discarded when it ends — no global state, no stale
/// drafts. The draft is plain value types: nothing touches the ModelContext until the
/// user confirms, so cancel is free.
@Observable
final class ReceiptImportFlow {
    enum Step: Equatable {
        case capture
        case parsing
        case review
        case saving
        case failed(message: String, retryable: Bool)
    }

    var step: Step = .capture
    var pages: [Data] = []
    var draft: ReceiptDraft?

    private let gemini: GeminiClient

    init(gemini: GeminiClient) {
        self.gemini = gemini
    }

    func setCaptured(images: [UIImage]) {
        pages = images.compactMap(ImageProcessor.processReceiptPage)
    }

    /// Start the flow from images already in hand (shared in, or picked from the library),
    /// skipping the camera and going straight to parsing.
    func beginImport(images: [UIImage], modelContext: ModelContext) async {
        setCaptured(images: images)
        guard !pages.isEmpty else {
            step = .failed(message: "Couldn't read that receipt. Try a clearer image.", retryable: false)
            return
        }
        await parse(modelContext: modelContext)
    }

    func parse(modelContext: ModelContext) async {
        guard !pages.isEmpty else { return }
        step = .parsing
        do {
            let service = ReceiptImportService(gemini: gemini)
            draft = try await service.parse(pages: pages, modelContext: modelContext)
            step = .review
        } catch {
            let appError = AppError(wrapping: error)
            Log.gemini.error("Receipt parse failed: \(String(describing: error))")
            step = .failed(message: appError.userMessage, retryable: appError.isRetryable)
        }
    }

    @discardableResult
    func save(account: Account?, modelContext: ModelContext) throws -> Transaction {
        guard let draft else { throw AppError.persistence(.modelNotFound) }
        step = .saving
        do {
            let editor = TransactionEditor(context: modelContext)
            let transaction = try editor.saveReceipt(draft: draft, account: account)
            return transaction
        } catch {
            step = .review
            throw error
        }
    }

    /// Re-run the Gemini call on the same pages (e.g. after a transient failure).
    func retry(modelContext: ModelContext) async {
        await parse(modelContext: modelContext)
    }

    func reset() {
        step = .capture
        pages = []
        draft = nil
    }
}
