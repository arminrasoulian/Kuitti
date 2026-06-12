import Foundation
import SwiftData

/// Cached mapping of (store, raw receipt text) → canonical product.
/// Logical key is (store, normalizedRawName) — enforced by upsert code, not a constraint.
@Model
final class ProductAlias {
    var uuid: UUID = UUID()
    var rawName: String = ""
    var normalizedRawName: String = ""
    var sourceRaw: String = AliasSource.user.rawValue
    var hitCount: Int = 0
    var createdAt: Date = Date()
    var lastUsedAt: Date = Date()

    // nil = store-agnostic alias.
    var store: Store?
    var product: Product?

    var source: AliasSource {
        get { AliasSource(rawValue: sourceRaw) ?? .user }
        set { sourceRaw = newValue.rawValue }
    }

    init(rawName: String, normalizedRawName: String, source: AliasSource) {
        self.rawName = rawName
        self.normalizedRawName = normalizedRawName
        self.sourceRaw = source.rawValue
    }
}
