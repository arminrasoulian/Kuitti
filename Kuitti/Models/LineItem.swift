import Foundation
import SwiftData

@Model
final class LineItem {
    var uuid: UUID = UUID()
    // Exactly as printed on the receipt: "BANAANI LUOMU".
    var rawName: String = ""
    // Resolved canonical name or user edit, in the receipt's ORIGINAL language.
    var displayName: String = ""
    // App-language (English) translation of displayName. Empty when already in the app
    // language or untranslated (manual entries, discounts without a translation). Lets
    // Transaction Detail / Review dual-display even for product-less lines.
    var translatedName: String = ""
    // A measurement (0.612 kg / 2 pcs), not money — Double is fine.
    var quantity: Double = 1
    var unitRaw: String = UnitKind.piece.rawValue
    // AUTHORITATIVE money, EUR cents. Negative for discount/deposit-return lines.
    var lineTotalMinor: Int = 0
    // DERIVED lineTotal/quantity in EUR — kept as Double because unit prices are inherently
    // fractional-cent and Swift Charts needs Plottable. Recomputed on any edit, never summed.
    var unitPrice: Double = 0
    var isDiscountOrDeposit: Bool = false
    var quantityIsUncertain: Bool = false
    // DENORMALIZED copy of transaction.date — SwiftData can't sort across optional
    // relationships; TransactionEditor keeps it in lockstep.
    var purchaseDate: Date = Date()
    var sortOrder: Int = 0
    var notes: String = ""

    var transaction: Transaction?
    var category: Category?
    var product: Product?

    var unit: UnitKind {
        get { UnitKind(rawValue: unitRaw) ?? .piece }
        set { unitRaw = newValue.rawValue }
    }

    init(rawName: String, displayName: String, quantity: Double, unit: UnitKind, lineTotalMinor: Int, sortOrder: Int = 0) {
        self.rawName = rawName
        self.displayName = displayName
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.lineTotalMinor = lineTotalMinor
        self.sortOrder = sortOrder
        self.unitPrice = quantity != 0 ? Double(lineTotalMinor) / 100.0 / quantity : 0
    }
}
