import Foundation
import SwiftData
import Testing
@testable import Kuitti

struct RecurringServiceTests {
    @Test func materializesAndAdvances() throws {
        let context = try makeContext()
        let template = RecurringTemplate(
            name: "Vuokra", kind: .expense, amountMinor: 95000,
            frequency: .monthly,
            nextDueDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        )
        context.insert(template)
        try context.save()

        try RecurringService.materializeDue(context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 1)
        #expect(transactions.first?.payee == "Vuokra")
        #expect(transactions.first?.source == .recurring)
        #expect(transactions.first?.amountMinor == 95000)
        #expect(template.nextDueDate > Date())
    }

    @Test func catchesUpAcrossMissedPeriods() throws {
        let context = try makeContext()
        let template = RecurringTemplate(
            name: "Netflix", kind: .expense, amountMinor: 1499,
            frequency: .monthly,
            nextDueDate: Calendar.current.date(byAdding: .month, value: -3, to: .now)!
        )
        context.insert(template)
        try context.save()

        try RecurringService.materializeDue(context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        // 3 months ago + today-ish boundary: 3 or 4 catch-up posts, never 0 or runaway.
        #expect((3...4).contains(transactions.count))
        #expect(template.nextDueDate > Date())
    }

    @Test func endDateDeactivates() throws {
        let context = try makeContext()
        let template = RecurringTemplate(
            name: "Old gym", kind: .expense, amountMinor: 3000,
            frequency: .monthly,
            nextDueDate: Calendar.current.date(byAdding: .month, value: -2, to: .now)!
        )
        template.endDate = Calendar.current.date(byAdding: .month, value: -3, to: .now)!
        context.insert(template)
        try context.save()

        try RecurringService.materializeDue(context: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.isEmpty)
        #expect(!template.isActive)
    }

    @Test func weeklyIntervalAdvance() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let next = RecurringService.advance(start, frequency: .weekly, interval: 2)
        #expect(next == Calendar.current.date(byAdding: .weekOfYear, value: 2, to: start))
    }
}
