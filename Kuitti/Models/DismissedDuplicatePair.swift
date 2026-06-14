import Foundation
import SwiftData

/// A product pair the user explicitly chose to keep separate ("Keep separate" in the
/// duplicate review). The duplicate scanner excludes these so a rejected suggestion never
/// reappears. `pairKey` is the order-independent identity (sorted UUID strings) — logical
/// uniqueness lives in code, never an @Attribute(.unique) (CloudKit ground rules).
@Model
final class DismissedDuplicatePair {
    var uuid: UUID = UUID()
    var productAUUID: UUID = UUID()
    var productBUUID: UUID = UUID()
    var pairKey: String = ""
    var createdAt: Date = Date()

    init(productA: UUID, productB: UUID) {
        self.productAUUID = productA
        self.productBUUID = productB
        self.pairKey = Self.key(productA, productB)
    }

    /// Order-independent key: sort the two UUID strings and join. The single source of
    /// truth for pair identity, shared with `ProductSimilarity.Candidate.id`. `nonisolated`
    /// so the off-main duplicate scan can build keys without hopping to the main actor.
    nonisolated static func key(_ a: UUID, _ b: UUID) -> String {
        let s1 = a.uuidString, s2 = b.uuidString
        return s1 < s2 ? "\(s1)|\(s2)" : "\(s2)|\(s1)"
    }
}
