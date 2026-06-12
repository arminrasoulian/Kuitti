import Foundation
import SwiftData

@Model
final class Transaction {
    var uuid: UUID = UUID()
    var kindRaw: String = TransactionKind.expense.rawValue
    var date: Date = Date()
    // Grand total in EUR cents, always >= 0; sign is derived from kind.
    var amountMinor: Int = 0
    var currencyCode: String = "EUR"
    // Denormalized display name (store chain or free text) — what the list and keyword search show.
    var payee: String = ""
    var notes: String = ""
    var paymentMethodRaw: String = PaymentMethod.unknown.rawValue
    var sourceRaw: String = TransactionSource.manual.rawValue
    var subtotalMinor: Int?
    // JSON-encoded [VatLine]. Display-only data, kept out of SwiftData's composite-attribute
    // machinery (Codable struct arrays have a crash history) and trivially CloudKit-safe.
    var vatLinesData: Data = Data()
    var importWarnings: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var account: Account?
    var category: Category?
    var store: Store?

    @Relationship(deleteRule: .cascade, inverse: \LineItem.transaction)
    var lineItems: [LineItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \ReceiptImage.transaction)
    var receiptImages: [ReceiptImage]? = []

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .unknown }
        set { paymentMethodRaw = newValue.rawValue }
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var vatLines: [VatLine] {
        get { (try? JSONDecoder().decode([VatLine].self, from: vatLinesData)) ?? [] }
        set { vatLinesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Signed amount in cents: negative for expenses, positive for income.
    var signedAmountMinor: Int {
        kind == .expense ? -amountMinor : amountMinor
    }

    init(kind: TransactionKind, date: Date, amountMinor: Int, payee: String = "", source: TransactionSource = .manual) {
        self.kindRaw = kind.rawValue
        self.date = date
        self.amountMinor = amountMinor
        self.payee = payee
        self.sourceRaw = source.rawValue
    }
}

nonisolated struct VatLine: Codable, Hashable {
    var ratePercent: Double
    var baseMinor: Int?   // not all receipts print the taxable base (Veroton)
    var taxMinor: Int
}
