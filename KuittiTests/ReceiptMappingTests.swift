import Foundation
import SwiftData
import Testing
@testable import Kuitti

/// Golden-fixture tests for the Gemini wire format → ReceiptDraft mapping: the decode
/// boundary, money precision, unit conversion, uncertainty propagation, and validation.
struct ReceiptMappingTests {

    /// A realistic K-Market receipt: weight-priced produce, a PANTTI deposit,
    /// a Plussa discount, cash rounding, and 14% VAT.
    static let kMarketJSON = """
    {
      "isReceipt": true,
      "store": { "rawName": "K-Market Munkkivuori", "normalizedName": "K-Market" },
      "date": "2026-06-10",
      "time": "17:42:00",
      "paymentMethod": "cash",
      "lineItems": [
        { "rawName": "KURKKU SUOMI", "canonicalName": "Kurkku", "quantity": 0.652, "unit": "kg",
          "unitPrice": "2.99", "lineTotal": "1.95", "suggestedCategory": "Groceries",
          "uncertain": false, "uncertaintyReason": null, "isDiscountOrDeposit": false },
        { "rawName": "BANAANI", "canonicalName": "Banaani", "quantity": 1, "unit": "pcs",
          "unitPrice": "1.20", "lineTotal": "1.20", "suggestedCategory": "Groceries",
          "uncertain": true, "uncertaintyReason": "no quantity printed; product may be weight-priced", "isDiscountOrDeposit": false },
        { "rawName": "KOFF III 0,33L", "canonicalName": "Koff III 0,33L", "quantity": 6, "unit": "pcs",
          "unitPrice": "0.89", "lineTotal": "5.34", "suggestedCategory": "Groceries",
          "uncertain": false, "uncertaintyReason": null, "isDiscountOrDeposit": false },
        { "rawName": "PANTTI 0,15", "canonicalName": "Pantti", "quantity": 6, "unit": "pcs",
          "unitPrice": "0.15", "lineTotal": "0.90", "suggestedCategory": "Groceries",
          "uncertain": false, "uncertaintyReason": null, "isDiscountOrDeposit": true },
        { "rawName": "PLUSSA-ETU", "canonicalName": "Plussa-etu", "quantity": 1, "unit": "pcs",
          "unitPrice": "-0.50", "lineTotal": "-0.50", "suggestedCategory": "Groceries",
          "uncertain": false, "uncertaintyReason": null, "isDiscountOrDeposit": true },
        { "rawName": "PYÖRISTYS", "canonicalName": "Pyöristys", "quantity": 1, "unit": "pcs",
          "unitPrice": "0.01", "lineTotal": "0.01", "suggestedCategory": "Groceries",
          "uncertain": false, "uncertaintyReason": null, "isDiscountOrDeposit": true }
      ],
      "vatBreakdown": [
        { "rate": 14, "amount": "1.09", "base": "7.81" }
      ],
      "subtotal": "8.89",
      "total": "8.90",
      "currency": "EUR",
      "confidence": "high",
      "warnings": []
    }
    """

    static let notAReceiptJSON = """
    {
      "isReceipt": false,
      "store": { "rawName": null, "normalizedName": null },
      "date": null, "time": null, "paymentMethod": "unknown",
      "lineItems": [], "vatBreakdown": [],
      "subtotal": null, "total": null, "currency": "EUR",
      "confidence": "low",
      "warnings": ["The image shows a cat, not a receipt."]
    }
    """

    @Test func kMarketFixtureMapsFaithfully() throws {
        let context = try makeContext()
        let dto = try JSONDecoder().decode(GeminiReceiptDTO.self, from: Data(Self.kMarketJSON.utf8))
        let categoryMap = ReceiptImportService.categoryUUIDMap(modelContext: context)
        let draft = try ReceiptImportService.draft(from: dto, pages: [], categoryMap: categoryMap, modelContext: context)

        #expect(draft.storeNormalizedName == "K-Market")
        #expect(draft.paymentMethod == .cash)
        #expect(draft.lines.count == 6)

        let kurkku = draft.lines[0]
        #expect(kurkku.lineTotalMinor == 195)
        #expect(kurkku.unit == .kilogram)
        #expect(abs(kurkku.quantity - 0.652) < 0.0001)

        let banaani = draft.lines[1]
        #expect(banaani.lineTotalMinor == 120)  // the 1.20 Double trap, exactly 120
        #expect(banaani.uncertain)
        #expect(banaani.uncertaintyReason?.contains("weight") == true)

        let pantti = draft.lines[3]
        #expect(pantti.isDiscountOrDeposit)
        #expect(pantti.resolution == .notAProduct)

        let plussa = draft.lines[4]
        #expect(plussa.lineTotalMinor == -50)

        #expect(draft.totalMinor == 890)
        #expect(draft.subtotalMinor == 889)
        #expect(draft.vatLines.first?.taxMinor == 109)
        #expect(draft.vatLines.first?.baseMinor == 781)
        // 195+120+534+90-50+1 = 890 = printed total → no mismatch.
        #expect(draft.lineSumMinor == 890)
        #expect(draft.totalMismatchMinor == nil)
        // Category resolved to the seeded groceries category.
        #expect(draft.lines[0].suggestedCategoryUUID != nil)
    }

    /// A non-Finnish receipt: source language + translation flow into the draft, and the
    /// fallback category resolves by seed identifier even when its name isn't the constant
    /// (proving existing installs with a localized fallback name still categorize).
    static let germanJSON = """
    {
      "isReceipt": true,
      "store": { "rawName": "REWE", "normalizedName": "REWE" },
      "date": "2026-06-10", "time": null, "paymentMethod": "card",
      "lineItems": [
        { "rawName": "VOLLMILCH 1L", "canonicalName": "Vollmilch 1L", "sourceLanguage": "de",
          "translatedName": "Whole milk 1L", "quantity": 1, "unit": "pcs",
          "unitPrice": "1.09", "lineTotal": "1.09", "suggestedCategory": "Nichtvorhanden",
          "uncertain": false, "uncertaintyReason": null, "isDiscountOrDeposit": false }
      ],
      "vatBreakdown": [], "subtotal": null, "total": "1.09",
      "currency": "EUR", "confidence": "high", "warnings": []
    }
    """

    @Test func translationFieldsMapAndFallbackResolvesBySeedID() throws {
        let context = try makeContext()
        // Rename the seeded fallback category away from the constant — only the seed
        // identifier should be used to find it.
        let fallback = ReceiptImportService.fallbackCategory(modelContext: context)
        fallback?.name = "Sekalaista"
        try context.save()

        let dto = try JSONDecoder().decode(GeminiReceiptDTO.self, from: Data(Self.germanJSON.utf8))
        let categoryMap = ReceiptImportService.categoryUUIDMap(modelContext: context)
        let draft = try ReceiptImportService.draft(from: dto, pages: [], categoryMap: categoryMap, modelContext: context)

        let line = draft.lines[0]
        #expect(line.sourceLanguage == "de")
        #expect(line.translatedName == "Whole milk 1L")
        // Unknown category → fell back to the renamed seed-other category by its seed ID.
        #expect(line.suggestedCategoryUUID == fallback?.uuid)
    }

    @Test func notAReceiptThrowsWithModelReason() throws {
        let context = try makeContext()
        let dto = try JSONDecoder().decode(GeminiReceiptDTO.self, from: Data(Self.notAReceiptJSON.utf8))
        #expect(throws: GeminiError.self) {
            _ = try ReceiptImportService.draft(from: dto, pages: [], categoryMap: [:], modelContext: context)
        }
    }

    @Test func gramsConvertToKilograms() {
        let (unit, quantity) = ReceiptImportService.mapUnit("g", quantity: 500)
        #expect(unit == .kilogram)
        #expect(quantity == 0.5)
    }

    @Test func paymentMethodMapping() {
        #expect(ReceiptImportService.mapPaymentMethod("mobile") == .mobilePay)
        #expect(ReceiptImportService.mapPaymentMethod("other") == .other)
        #expect(ReceiptImportService.mapPaymentMethod("nonsense") == .unknown)
    }

    @Test func cashRoundingTolerance() throws {
        // Cash receipt, 4-cent gap, no Pyöristys line extracted → tolerated.
        var draft = ReceiptDraft(
            storeRawName: "", storeNormalizedName: "Lidl", date: Date(),
            paymentMethod: .cash,
            lines: [LineDraft(rawName: "X", canonicalName: "X", quantity: 1, unit: .piece,
                              lineTotalMinor: 496, isDiscountOrDeposit: false, uncertain: false,
                              uncertaintyReason: nil, suggestedCategoryUUID: nil,
                              chosenCategoryUUID: nil, resolution: .newProduct, sortOrder: 0)],
            subtotalMinor: nil, vatLines: [], totalMinor: 500,
            confidence: .high, warnings: [], pages: []
        )
        #expect(draft.totalMismatchMinor == nil)

        // Card receipt with the same gap → flagged.
        draft.paymentMethod = .card
        #expect(draft.totalMismatchMinor == -4)
    }

    @Test func receiptSaveRoundTrip() throws {
        let context = try makeContext()
        let dto = try JSONDecoder().decode(GeminiReceiptDTO.self, from: Data(Self.kMarketJSON.utf8))
        let categoryMap = ReceiptImportService.categoryUUIDMap(modelContext: context)
        let draft = try ReceiptImportService.draft(from: dto, pages: [Data([0xFF])], categoryMap: categoryMap, modelContext: context)

        let editor = TransactionEditor(context: context)
        let account = try context.fetch(FetchDescriptor<Account>()).first
        let transaction = try editor.saveReceipt(draft: draft, account: account)

        #expect(transaction.amountMinor == 890)
        #expect(transaction.source == .receiptScan)
        #expect(transaction.store?.name == "K-Market")
        #expect(transaction.lineItems?.count == 6)
        #expect(transaction.receiptImages?.count == 1)

        // Product linking: 3 real products created, discount/deposit lines none.
        let products = try context.fetch(FetchDescriptor<Product>())
        #expect(products.count == 3)
        let banaani = products.first { $0.canonicalName == "Banaani" }
        #expect(banaani?.purchaseCount == 1)
        #expect(banaani?.lastStoreName == "K-Market")

        // The learning step: aliases minted for the product lines.
        let aliases = try context.fetch(FetchDescriptor<ProductAlias>())
        #expect(aliases.count == 3)

        // Second receipt from the same store now resolves at step 1 (alias, zero AI).
        let matcher = ProductMatcher(context: context)
        let store = transaction.store
        let resolution = matcher.resolve(rawName: "BANAANI", proposedCanonical: "whatever", unit: .piece, store: store)
        #expect(resolution == .confirmedAlias(productUUID: banaani!.uuid))
    }
}
