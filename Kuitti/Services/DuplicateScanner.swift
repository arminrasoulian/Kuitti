import Foundation
import Observation
import SwiftData

/// Proactive duplicate-product detection. Holds the current suggestions for the tab badge,
/// the Products banner, the Settings entry, and the post-scan nudge. `refresh` snapshots
/// products on the main actor, then scores off-main on Sendable fingerprints (the heavy
/// pairwise pass) and publishes the result back on the main actor. Non-throwing and
/// log-on-error, like RecurringService — a failed scan must never disrupt the app.
@Observable
@MainActor
final class DuplicateScanner {
    private(set) var candidates: [ProductSimilarity.Candidate] = []
    /// A high-confidence suggestion involving a just-saved product, for the post-scan nudge.
    /// Set by `refresh(context:nudgeAround:)`; consumed (cleared) by the Scan hub.
    var pendingNudge: ProductSimilarity.Candidate?

    var count: Int { candidates.count }
    var hasSuggestions: Bool { !candidates.isEmpty }

    /// `nudgeAround`: product UUIDs from a just-saved receipt — if any are in a high-confidence
    /// pair, `pendingNudge` is set so the Scan hub can offer an immediate merge.
    func refresh(context: ModelContext, nudgeAround savedProductIDs: Set<UUID> = []) {
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let fingerprints = products.map { product in
            ProductSimilarity.Fingerprint(
                id: product.uuid,
                canonicalName: product.canonicalName,
                normalizedKey: product.normalizedKey,
                translatedName: product.translatedName,
                translatedNormalizedKey: product.translatedNormalizedKey,
                sourceLanguage: product.sourceLanguage,
                ean: product.ean,
                unit: product.defaultUnit,
                purchaseCount: product.purchaseCount
            )
        }
        let dismissed = Set(
            ((try? context.fetch(FetchDescriptor<DismissedDuplicatePair>())) ?? []).map(\.pairKey)
        )
        Task {
            let result = await Task.detached(priority: .utility) {
                ProductSimilarity.duplicates(in: fingerprints, excluding: dismissed)
            }.value
            self.candidates = result
            if !savedProductIDs.isEmpty {
                self.pendingNudge = result.first {
                    $0.confidence == .high && (savedProductIDs.contains($0.a) || savedProductIDs.contains($0.b))
                }
            }
        }
    }
}
