import Foundation
import SwiftData
import Testing
@testable import Kuitti

/// The denormalized invariants the whole app leans on (price-history ordering,
/// dashboard/balance agreement, product stats).
struct TransactionEditorTests {
    @Test func dateEditSyncsLineItemPurchaseDates() throws {
        let context = try makeContext()
        let editor = TransactionEditor(context: context)
        let transaction = try editor.createManual(
            kind: .expense, date: Date(), amountMinor: 0,
            payee: "Lidl", account: nil, category: nil, notes: "", paymentMethod: .card
        )
        let item = LineItem(rawName: "X", displayName: "X", quantity: 1, unit: .piece, lineTotalMinor: 100)
        item.transaction = transaction
        context.insert(item)

        let newDate = Calendar.current.date(byAdding: .day, value: -10, to: .now)!
        transaction.date = newDate
        try editor.didEdit(transaction)

        #expect(item.purchaseDate == newDate)
    }

    @Test func lineEditRecomputesAmountAndUnitPrice() throws {
        let context = try makeContext()
        let editor = TransactionEditor(context: context)
        let transaction = try editor.createManual(
            kind: .expense, date: Date(), amountMinor: 100,
            payee: "Lidl", account: nil, category: nil, notes: "", paymentMethod: .card
        )
        let item = LineItem(rawName: "X", displayName: "X", quantity: 2, unit: .piece, lineTotalMinor: 100)
        item.transaction = transaction
        context.insert(item)

        item.lineTotalMinor = 300
        try editor.didEdit(transaction)

        // amountMinor follows the line sum; unitPrice rederives (3.00 € / 2 pcs).
        #expect(transaction.amountMinor == 300)
        #expect(abs(item.unitPrice - 1.5) < 0.0001)

        // Unless the user explicitly overrode the total.
        transaction.amountMinor = 500
        try editor.didEdit(transaction, amountOverridden: true)
        #expect(transaction.amountMinor == 500)
    }

    /// ProductMatcherTests.aliasOverwriteFixesMistakes, but through the post-save edit
    /// path (§3.4's learning step for later corrections): renaming a saved line item and
    /// re-linking its product must repoint the (store, rawName) alias — same key, source
    /// .user — and move the stats, so the next receipt resolves correctly with zero AI.
    @Test func postSaveRelinkRepointsAliasAndMovesStats() throws {
        let context = try makeContext()
        let editor = TransactionEditor(context: context)
        let matcher = ProductMatcher(context: context)
        let wrong = matcher.findOrCreateProduct(canonicalName: "Omena", defaultUnit: .kilogram)
        let store = matcher.findOrCreateStore(named: "Prisma")

        // A saved receipt line that Gemini mapped to the wrong product.
        let transaction = try editor.createManual(
            kind: .expense, date: Date(), amountMinor: 250,
            payee: "Prisma", account: nil, category: nil, notes: "", paymentMethod: .card
        )
        transaction.store = store
        let item = LineItem(rawName: "BANAANI", displayName: "Omena", quantity: 1, unit: .kilogram, lineTotalMinor: 250)
        item.transaction = transaction
        item.product = wrong
        context.insert(item)
        matcher.upsertAlias(rawName: "BANAANI", store: store, product: wrong, source: .gemini)
        try editor.didEdit(transaction)
        #expect(wrong.purchaseCount == 1)

        // The later correction: user renames the line and picks/creates "Banaani".
        let right = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)
        item.displayName = "Banaani"
        try editor.relinkProduct(for: item, to: right)

        // One alias per (store, raw name) — repointed, not duplicated, and now user truth.
        let aliases = try context.fetch(FetchDescriptor<ProductAlias>())
        #expect(aliases.count == 1)
        #expect(aliases.first?.product?.uuid == right.uuid)
        #expect(aliases.first?.source == .user)

        // Product link and stats moved off the wrong product.
        #expect(item.product?.uuid == right.uuid)
        #expect(wrong.purchaseCount == 0)
        #expect(right.purchaseCount == 1)

        // The same printed line now resolves at step 1 (exact alias), no AI involved.
        let resolution = matcher.resolve(rawName: "BANAANI", proposedCanonical: "Omena", unit: .kilogram, store: store)
        #expect(resolution == .confirmedAlias(productUUID: right.uuid))
    }

    /// A scanned non-English line carries its translation onto both the line item and the
    /// newly created product (with a normalized translation key for cross-language matching).
    @Test func saveReceiptStoresProductAndLineTranslations() throws {
        let context = try makeContext()
        let draft = ReceiptDraft(
            storeRawName: "REWE", storeNormalizedName: "REWE", date: Date(),
            paymentMethod: .card,
            lines: [LineDraft(rawName: "VOLLMILCH 1L", canonicalName: "Vollmilch 1L",
                              translatedName: "Whole milk 1L", sourceLanguage: "de",
                              quantity: 1, unit: .piece, lineTotalMinor: 109,
                              isDiscountOrDeposit: false, uncertain: false, uncertaintyReason: nil,
                              suggestedCategoryUUID: nil, chosenCategoryUUID: nil,
                              resolution: .newProduct, sortOrder: 0)],
            subtotalMinor: nil, vatLines: [], totalMinor: 109,
            confidence: .high, warnings: [], pages: []
        )
        let editor = TransactionEditor(context: context)
        let transaction = try editor.saveReceipt(draft: draft, account: nil)

        let item = transaction.lineItems?.first
        #expect(item?.translatedName == "Whole milk 1L")
        let product = item?.product
        #expect(product?.canonicalName == "Vollmilch 1L")        // identity stays original-language
        #expect(product?.translatedName == "Whole milk 1L")
        #expect(product?.translatedNormalizedKey == "whole milk 1l")
        #expect(product?.sourceLanguage == "de")
    }

    @Test func mergeProductsConsolidatesHistoryAndRecomputesStats() throws {
        let context = try makeContext()
        let editor = TransactionEditor(context: context)
        let matcher = ProductMatcher(context: context)
        let survivor = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)
        let loser = matcher.findOrCreateProduct(canonicalName: "Banana", defaultUnit: .kilogram)

        let t1 = try editor.createManual(kind: .expense, date: Date(), amountMinor: 120,
                                         payee: "Lidl", account: nil, category: nil, notes: "", paymentMethod: .card)
        let l1 = LineItem(rawName: "BANAANI", displayName: "Banaani", quantity: 1, unit: .kilogram, lineTotalMinor: 120)
        l1.transaction = t1; l1.product = survivor; context.insert(l1)
        try editor.didEdit(t1)

        let t2 = try editor.createManual(kind: .expense, date: Date(), amountMinor: 130,
                                         payee: "Prisma", account: nil, category: nil, notes: "", paymentMethod: .card)
        let l2 = LineItem(rawName: "BANANA", displayName: "Banana", quantity: 1, unit: .kilogram, lineTotalMinor: 130)
        l2.transaction = t2; l2.product = loser; context.insert(l2)
        try editor.didEdit(t2)

        #expect(survivor.purchaseCount == 1)
        #expect(loser.purchaseCount == 1)

        try editor.mergeProducts(loser: loser, into: survivor)

        // Loser gone; its history is now under the survivor with recomputed stats.
        #expect(try context.fetch(FetchDescriptor<Product>()).count == 1)
        #expect(survivor.purchaseCount == 2)
        #expect((survivor.lineItems ?? []).count == 2)
    }

    @Test func deleteRecomputesProductStats() throws {
        let context = try makeContext()
        let editor = TransactionEditor(context: context)
        let matcher = ProductMatcher(context: context)
        let product = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)

        let transaction = try editor.createManual(
            kind: .expense, date: Date(), amountMinor: 120,
            payee: "Lidl", account: nil, category: nil, notes: "", paymentMethod: .card
        )
        let item = LineItem(rawName: "BANAANI", displayName: "Banaani", quantity: 1, unit: .kilogram, lineTotalMinor: 120)
        item.transaction = transaction
        item.product = product
        context.insert(item)
        try editor.didEdit(transaction)
        #expect(product.purchaseCount == 1)

        try editor.delete(transaction)
        #expect(product.purchaseCount == 0)
        #expect(product.lastPurchasedAt == nil)
        // Cascade removed the line item; the product survives (history-less).
        #expect(try context.fetch(FetchDescriptor<LineItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Product>()).count == 1)
    }
}
