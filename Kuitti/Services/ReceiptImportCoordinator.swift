import Foundation
import Observation
import UIKit

/// The single entry point for "import these receipt page images" — decoupled from where the
/// images came from. RootTabView observes `pending` and drives the confirm → scan/parse flow.
@Observable
@MainActor
final class ReceiptImportCoordinator {
    struct Pending: Identifiable {
        let id = UUID()
        var images: [UIImage]
        var needsConfirmation: Bool
    }

    /// The current request awaiting presentation, or nil.
    var pending: Pending?

    /// Funnel for every caller: the Scan hub's library picker (`needsConfirmation: false`,
    /// the user already chose), the share / `.onOpenURL` path (`true`), and — in the future —
    /// a Share Extension. Empty image sets are ignored.
    ///
    /// TODO: Top-row Share Extension. Kuitti currently receives shared receipts as a document
    /// handler ("Copy to Kuitti" — see `CFBundleDocumentTypes` in project.yml and
    /// `RootTabView.onOpenURL`), which appears in the share sheet's *actions* list, not the top
    /// app-icon row. To upgrade to the app row later:
    ///   1. Add a `KuittiShare` app-extension target with an `NSExtensionActivationRule` for
    ///      images/PDF.
    ///   2. Add an App Group (`group.com.personal.kuitti`) entitlement to both the app and the
    ///      extension, plus a `kuitti://` URL scheme.
    ///   3. The extension writes the shared item into the App-Group inbox and opens the host
    ///      app; `RootTabView` drains that inbox and calls `request(...)` below — reusing this
    ///      exact confirm/parse path unchanged. (Requires the Apple account to allow App Groups
    ///      for device installs.)
    func request(images: [UIImage], needsConfirmation: Bool) {
        guard !images.isEmpty else { return }
        pending = Pending(images: images, needsConfirmation: needsConfirmation)
    }

    func clear() {
        pending = nil
    }
}
