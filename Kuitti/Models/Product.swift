import Foundation
import SwiftData

@Model
final class Product {
    var uuid: UUID = UUID()
    // "Banaani", "Arla laktoositon maito 1L"
    var canonicalName: String = ""
    // Matching key: lowercased, whitespace-collapsed, punctuation-stripped, ä/ö/å PRESERVED.
    var normalizedKey: String = ""
    var defaultUnitRaw: String = UnitKind.piece.rawValue
    // From the barcode flow. NOT unique — duplicates are merged in code (CloudKit forbids uniques).
    var ean: String?
    var brand: String?
    // Denormalized stats so the product list renders from this fetch alone.
    // Recomputed in full per affected product by TransactionEditor.
    var lastPurchasedAt: Date?
    var lastUnitPrice: Double?
    var lastStoreName: String?
    var purchaseCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \LineItem.product)
    var lineItems: [LineItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \ProductAlias.product)
    var aliases: [ProductAlias]? = []

    var defaultUnit: UnitKind {
        get { UnitKind(rawValue: defaultUnitRaw) ?? .piece }
        set { defaultUnitRaw = newValue.rawValue }
    }

    init(canonicalName: String, normalizedKey: String, defaultUnit: UnitKind = .piece) {
        self.canonicalName = canonicalName
        self.normalizedKey = normalizedKey
        self.defaultUnitRaw = defaultUnit.rawValue
    }
}
