import Foundation
import SwiftData
import Testing
@testable import Kuitti

/// THE REPORTING RULE and the drill-down entry factory. MainActor — these read @Model props.
@MainActor
struct SpendingReportTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func itemizedAttributesPerLineItemCategory() throws {
        let context = try makeContext(seeded: false)
        let food = Kuitti.Category(name: "Food"); context.insert(food)
        let home = Kuitti.Category(name: "Home"); context.insert(home)
        let tx = Transaction(kind: .expense, date: date(2026, 6, 10), amountMinor: 500); context.insert(tx)
        let milk = LineItem(rawName: "Milk", displayName: "Milk", quantity: 1, unit: .piece, lineTotalMinor: 200)
        milk.transaction = tx; milk.category = food; context.insert(milk)
        let soap = LineItem(rawName: "Soap", displayName: "Soap", quantity: 1, unit: .piece, lineTotalMinor: 300)
        soap.transaction = tx; soap.category = home; context.insert(soap)
        tx.lineItems = [milk, soap]
        try context.save()

        let totals = SpendingReport.expenseTotals([tx])
        #expect(totals[food.uuid] == 200)
        #expect(totals[home.uuid] == 300)
        #expect(SpendingReport.expenseTotal(for: food.uuid, in: [tx]) == 200)
    }

    @Test func unitemizedAttributesWholeToTransactionCategory() throws {
        let context = try makeContext(seeded: false)
        let food = Kuitti.Category(name: "Food"); context.insert(food)
        let tx = Transaction(kind: .expense, date: date(2026, 6, 10), amountMinor: 1500); context.insert(tx)
        tx.category = food; tx.lineItems = []
        try context.save()
        #expect(SpendingReport.expenseTotals([tx])[food.uuid] == 1500)
    }

    @Test func nilCategoryPoolsUnderNilKey() throws {
        let context = try makeContext(seeded: false)
        let tx = Transaction(kind: .expense, date: date(2026, 6, 10), amountMinor: 700); context.insert(tx)
        tx.lineItems = []
        try context.save()
        let nilKey: UUID? = nil
        #expect(SpendingReport.expenseTotals([tx])[nilKey] == 700)
    }

    @Test func incomeExcludedFromExpenseTotals() throws {
        let context = try makeContext(seeded: false)
        let salary = Kuitti.Category(name: "Salary", kind: .income); context.insert(salary)
        let tx = Transaction(kind: .income, date: date(2026, 6, 10), amountMinor: 100000); context.insert(tx)
        tx.category = salary; tx.lineItems = []
        try context.save()
        #expect(SpendingReport.expenseTotals([tx]).isEmpty)
    }

    @Test func discountNetsNegativeForCategory() throws {
        let context = try makeContext(seeded: false)
        let food = Kuitti.Category(name: "Food"); context.insert(food)
        let tx = Transaction(kind: .expense, date: date(2026, 6, 10), amountMinor: 0); context.insert(tx)
        let apple = LineItem(rawName: "Apple", displayName: "Apple", quantity: 1, unit: .piece, lineTotalMinor: 300)
        apple.transaction = tx; apple.category = food
        let coupon = LineItem(rawName: "Coupon", displayName: "Coupon", quantity: 1, unit: .piece, lineTotalMinor: -400)
        coupon.transaction = tx; coupon.category = food
        context.insert(apple); context.insert(coupon)
        tx.lineItems = [apple, coupon]
        try context.save()
        #expect(SpendingReport.expenseTotals([tx])[food.uuid] == -100)
    }

    @Test func monthlySeriesZeroFillsAndOrdersChronologically() throws {
        let context = try makeContext(seeded: false)
        let food = Kuitti.Category(name: "Food"); context.insert(food)
        let december = Transaction(kind: .expense, date: date(2025, 12, 20), amountMinor: 1000)
        december.category = food; december.lineItems = []
        let february = Transaction(kind: .expense, date: date(2026, 2, 5), amountMinor: 2000)
        february.category = food; february.lineItems = []
        context.insert(december); context.insert(february)
        try context.save()

        // Clean month boundaries: [Dec 1 00:00, Mar 1 00:00) → Dec, Jan, Feb.
        let calendar = Calendar.current
        let interval = DateInterval(
            start: calendar.dateInterval(of: .month, for: date(2025, 12, 10))!.start,
            end: calendar.dateInterval(of: .month, for: date(2026, 2, 10))!.end
        )
        let series = SpendingReport.monthlySeries(for: food.uuid, in: [december, february], interval: interval)
        #expect(series.count == 3)              // Dec, Jan, Feb
        #expect(series[0].totalMinor == 1000)   // Dec
        #expect(series[1].totalMinor == 0)      // Jan — zero-filled
        #expect(series[2].totalMinor == 2000)   // Feb
    }

    @Test func incomeExpenseSeriesSplitsByKind() throws {
        let context = try makeContext(seeded: false)
        let income = Transaction(kind: .income, date: date(2026, 6, 5), amountMinor: 5000); income.lineItems = []
        let expense = Transaction(kind: .expense, date: date(2026, 6, 9), amountMinor: 1200); expense.lineItems = []
        context.insert(income); context.insert(expense)
        try context.save()
        let interval = Calendar.current.dateInterval(of: .month, for: date(2026, 6, 1))!
        let series = SpendingReport.incomeExpenseSeries([income, expense], interval: interval)
        #expect(series.count == 1)
        #expect(series[0].incomeMinor == 5000)
        #expect(series[0].expenseMinor == 1200)
    }

    @Test func entriesEmitOneRowPerMatchingLine() throws {
        let context = try makeContext(seeded: false)
        let food = Kuitti.Category(name: "Food"); context.insert(food)
        let tx = Transaction(kind: .expense, date: date(2026, 6, 10), amountMinor: 500); context.insert(tx)
        let milk = LineItem(rawName: "Milk", displayName: "Milk", quantity: 1, unit: .piece, lineTotalMinor: 200)
        milk.transaction = tx; milk.category = food
        let bread = LineItem(rawName: "Bread", displayName: "Bread", quantity: 1, unit: .piece, lineTotalMinor: 300)
        bread.transaction = tx; bread.category = food
        context.insert(milk); context.insert(bread)
        tx.lineItems = [milk, bread]
        try context.save()

        let entries = SpendingEntry.entries(in: [tx], forCategory: food.uuid)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.transaction.uuid == tx.uuid })
        #expect(entries.map(\.amountMinor).sorted() == [200, 300])
    }

    @Test func entriesForUncategorizedWholeTransaction() throws {
        let context = try makeContext(seeded: false)
        let tx = Transaction(kind: .expense, date: date(2026, 6, 10), amountMinor: 800); context.insert(tx)
        tx.payee = "Kiosk"; tx.lineItems = []
        try context.save()

        let entries = SpendingEntry.entries(in: [tx], forCategory: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.amountMinor == 800)
        #expect(entries.first?.displayName == "Kiosk")
    }

    @Test func elapsedMonthCountMatchesMonthStarts() {
        // Clean month boundaries: [Jan 1 00:00, Apr 1 00:00) → Jan, Feb, Mar.
        let calendar = Calendar.current
        let interval = DateInterval(
            start: calendar.dateInterval(of: .month, for: date(2026, 1, 15))!.start,
            end: calendar.dateInterval(of: .month, for: date(2026, 3, 15))!.end
        )
        #expect(SpendingReport.monthStarts(in: interval).count == 3)
        // All three months are in the past relative to mid-2026.
        #expect(SpendingReport.elapsedMonthCount(in: interval, now: date(2026, 6, 14)) == 3)
        // Only Jan + Feb have started as of mid-Feb.
        #expect(SpendingReport.elapsedMonthCount(in: interval, now: date(2026, 2, 14)) == 2)
    }
}
