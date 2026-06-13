import Foundation

// Draft/DTO types are nonisolated by design: their Codable conformances must be usable
// inside the non-main GeminiClient/OpenFoodFactsClient actors (the project default is
// MainActor isolation). Nothing here touches SwiftData — drafts are pure values, and the
// ModelContext is only involved when the user confirms the review screen.

nonisolated enum ParseConfidence: String, Codable, Sendable {
    case high, medium, low
}

/// The editable state behind the receipt review screen.
nonisolated struct ReceiptDraft: Sendable {
    var storeRawName: String
    var storeNormalizedName: String
    var date: Date
    var paymentMethod: PaymentMethod
    var lines: [LineDraft]
    var subtotalMinor: Int?
    var vatLines: [VatLine]
    /// The total printed on the receipt (what was actually charged).
    var totalMinor: Int?
    var confidence: ParseConfidence
    var warnings: [String]
    /// Processed JPEG pages — the same bytes sent to Gemini, persisted on save.
    var pages: [Data]

    /// Sum of all line totals including negatives (deposits, discounts).
    var lineSumMinor: Int { lines.reduce(0) { $0 + $1.lineTotalMinor } }

    /// Mismatch between extracted lines and the printed total, with the cash-rounding
    /// tolerance: ±1 cent normally, ±5 cents for cash with no Pyöristys line extracted.
    var totalMismatchMinor: Int? {
        guard let totalMinor else { return nil }
        let diff = lineSumMinor - totalMinor
        let hasRoundingLine = lines.contains { $0.rawName.lowercased().contains("pyöristys") }
        let tolerance = (paymentMethod == .cash && !hasRoundingLine) ? 5 : 1
        return abs(diff) <= tolerance ? nil : diff
    }
}

nonisolated struct LineDraft: Identifiable, Sendable {
    var id = UUID()
    var rawName: String
    var canonicalName: String
    /// App-language translation of canonicalName from Gemini; nil/"" when already app-language.
    var translatedName: String? = nil
    /// Detected BCP-47 language of the printed line.
    var sourceLanguage: String? = nil
    var quantity: Double
    var unit: UnitKind
    var lineTotalMinor: Int
    var isDiscountOrDeposit: Bool
    var uncertain: Bool
    var uncertaintyReason: String?
    var suggestedCategoryUUID: UUID?
    var chosenCategoryUUID: UUID?
    var resolution: ProductResolution
    var sortOrder: Int

    /// EUR per unit, derived — never authoritative.
    var unitPrice: Double {
        quantity != 0 ? Double(lineTotalMinor) / 100.0 / quantity : 0
    }
}

/// How a line's raw name was resolved to a canonical product (§3.4 of the plan).
nonisolated enum ProductResolution: Sendable, Equatable {
    /// Exact alias hit — user-validated truth, green chip.
    case confirmedAlias(productUUID: UUID)
    /// Local fuzzy match ≥ threshold — yellow chip.
    case fuzzySuggested(productUUID: UUID, score: Double)
    /// Gemini's proposal, no local match — blue chip; Product is created on save.
    case newProduct
    /// Discount/deposit/rounding lines never become products.
    case notAProduct

    var productUUID: UUID? {
        switch self {
        case .confirmedAlias(let id), .fuzzySuggested(let id, _): id
        case .newProduct, .notAProduct: nil
        }
    }
}

/// Result of the product-package-photo identification flow.
nonisolated struct ProductIdentification: Codable, Sendable {
    var productName: String
    var sourceLanguage: String?
    var translatedName: String?
    var brand: String?
    var size: String?
    var confidence: String
}
