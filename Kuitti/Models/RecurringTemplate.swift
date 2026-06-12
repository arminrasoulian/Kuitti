import Foundation
import SwiftData

@Model
final class RecurringTemplate {
    var uuid: UUID = UUID()
    // "Vuokra", "Netflix", "Palkka" — becomes the materialized transaction's payee.
    var name: String = ""
    var kindRaw: String = TransactionKind.expense.rawValue
    var amountMinor: Int = 0
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    // Every N periods (e.g. every 3 months).
    var interval: Int = 1
    var nextDueDate: Date = Date()
    var endDate: Date?
    var isActive: Bool = true
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var account: Account?
    var category: Category?

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    init(name: String, kind: TransactionKind, amountMinor: Int, frequency: RecurrenceFrequency, nextDueDate: Date) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.amountMinor = amountMinor
        self.frequencyRaw = frequency.rawValue
        self.nextDueDate = nextDueDate
    }
}
