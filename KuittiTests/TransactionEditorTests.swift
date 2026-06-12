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
