import Foundation

/// THE single implementation of THE REPORTING RULE.
///
/// Itemized expense transactions attribute spend per line item's category (`lineTotalMinor`,
/// discounts included as negatives); un-itemized expense transactions attribute the whole
/// `amountMinor` to the transaction's category. A `nil` category maps to the `nil` key (shown
/// as "Uncategorized"). Income is ignored by every `expense…` function here.
///
/// MainActor because it reads `@Model` stored properties (`lineItems`, `category`) under the
/// project's Swift 6 MainActor-default isolation. Do NOT mark it `nonisolated` — only the pure
/// date math (`monthStarts` / `elapsedMonthCount`) is nonisolated.
enum SpendingReport {

    /// Per-category expense totals, keyed by category UUID (`nil` = uncategorized). Totals may be
    /// ≤ 0 for discount-heavy categories; rendering callers drop non-positive values themselves.
    static func expenseTotals(_ transactions: [Transaction]) -> [UUID?: Int] {
        var totals: [UUID?: Int] = [:]
        for transaction in transactions where transaction.kind == .expense {
            let items = transaction.lineItems ?? []
            if items.isEmpty {
                totals[transaction.category?.uuid, default: 0] += transaction.amountMinor
            } else {
                for item in items {
                    totals[item.category?.uuid, default: 0] += item.lineTotalMinor
                }
            }
        }
        return totals
    }

    /// Total expense attributed to one category id (`nil` = uncategorized) under the rule.
    static func expenseTotal(for categoryID: UUID?, in transactions: [Transaction]) -> Int {
        var total = 0
        for transaction in transactions where transaction.kind == .expense {
            let items = transaction.lineItems ?? []
            if items.isEmpty {
                if transaction.category?.uuid == categoryID { total += transaction.amountMinor }
            } else {
                for item in items where item.category?.uuid == categoryID {
                    total += item.lineTotalMinor
                }
            }
        }
        return total
    }

    /// Per-month expense series for one category id across `interval`. One entry per calendar
    /// month the interval touches, chronological; months with no spend yield 0 (so the chart
    /// axis renders a continuous line).
    static func monthlySeries(for categoryID: UUID?,
                              in transactions: [Transaction],
                              interval: DateInterval) -> [MonthlyPoint] {
        let calendar = Calendar.current
        let starts = monthStarts(in: interval)
        guard !starts.isEmpty else { return [] }
        var byMonth: [Date: Int] = [:]
        for transaction in transactions where transaction.kind == .expense
            && interval.contains(transaction.date) {
            guard let monthStart = calendar.dateInterval(of: .month, for: transaction.date)?.start else { continue }
            let items = transaction.lineItems ?? []
            if items.isEmpty {
                if transaction.category?.uuid == categoryID {
                    byMonth[monthStart, default: 0] += transaction.amountMinor
                }
            } else {
                for item in items where item.category?.uuid == categoryID {
                    byMonth[monthStart, default: 0] += item.lineTotalMinor
                }
            }
        }
        return starts.map { MonthlyPoint(monthStart: $0, totalMinor: byMonth[$0] ?? 0) }
    }

    /// Income vs expense per month across `interval` — generalizes the old fixed 6-month bucketing.
    static func incomeExpenseSeries(_ transactions: [Transaction],
                                    interval: DateInterval) -> [IncomeExpensePoint] {
        let calendar = Calendar.current
        let starts = monthStarts(in: interval)
        guard !starts.isEmpty else { return [] }
        var income: [Date: Int] = [:]
        var expense: [Date: Int] = [:]
        for transaction in transactions where interval.contains(transaction.date) {
            guard let monthStart = calendar.dateInterval(of: .month, for: transaction.date)?.start else { continue }
            switch transaction.kind {
            case .income: income[monthStart, default: 0] += transaction.amountMinor
            case .expense: expense[monthStart, default: 0] += transaction.amountMinor
            }
        }
        return starts.map {
            IncomeExpensePoint(monthStart: $0, incomeMinor: income[$0] ?? 0, expenseMinor: expense[$0] ?? 0)
        }
    }

    // MARK: - Pure date math (no @Model — safe off the main actor)

    /// Month-start dates the interval touches, chronological. Shared by the series builders, by
    /// `ReportPeriod.isMultiMonth`, and by `elapsedMonthCount`, so month-counting stays consistent.
    nonisolated static func monthStarts(in interval: DateInterval) -> [Date] {
        let calendar = Calendar.current
        guard interval.duration > 0,
              var cursor = calendar.dateInterval(of: .month, for: interval.start)?.start else { return [] }
        // End is exclusive; step from the last instant strictly inside the interval.
        let lastInstant = interval.end.addingTimeInterval(-1)
        guard let lastStart = calendar.dateInterval(of: .month, for: lastInstant)?.start else { return [] }
        var result: [Date] = []
        while cursor <= lastStart {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Months in the interval that have already started as of `now` (≥ 1). The budget-scaling factor.
    nonisolated static func elapsedMonthCount(in interval: DateInterval, now: Date = Date()) -> Int {
        max(1, monthStarts(in: interval).filter { $0 <= now }.count)
    }
}

nonisolated struct MonthlyPoint: Identifiable {
    let monthStart: Date
    let totalMinor: Int
    var id: Date { monthStart }
}

nonisolated struct IncomeExpensePoint: Identifiable {
    let monthStart: Date
    let incomeMinor: Int
    let expenseMinor: Int
    var id: Date { monthStart }
}

/// One drillable purchase in a category drill-down: wraps EITHER a single line item (itemized
/// transaction) OR a whole un-itemized transaction, normalized to the fields a row + navigation
/// need. Holds `@Model` references, so MainActor-only (not `nonisolated`).
struct SpendingEntry: Identifiable {
    enum Source {
        case lineItem(LineItem)
        case wholeTransaction(Transaction)
    }

    let source: Source
    /// Parent transaction for navigation to `TransactionDetailView`. Always set — entries are
    /// built from the parent's own transactions.
    let transaction: Transaction

    /// Stable identity. A `LineItem.uuid` is unique even across a multi-line transaction, so
    /// several rows pointing at the same transaction never collide.
    var id: UUID {
        switch source {
        case .lineItem(let item): item.uuid
        case .wholeTransaction(let txn): txn.uuid
        }
    }

    /// Line items carry a denormalized `purchaseDate` kept in lockstep with the transaction date.
    var date: Date {
        switch source {
        case .lineItem(let item): item.purchaseDate
        case .wholeTransaction(let txn): txn.date
        }
    }

    var displayName: String {
        switch source {
        case .lineItem(let item):
            return item.nameDisplay.primary
        case .wholeTransaction(let txn):
            let name = txn.payee.isEmpty ? (txn.store?.name ?? "") : txn.payee
            return name.isEmpty ? "Transaction" : name
        }
    }

    /// Original-language name for a translated line item; `nil` for whole-transaction rows.
    var secondaryName: String? {
        switch source {
        case .lineItem(let item): item.nameDisplay.secondary
        case .wholeTransaction: nil
        }
    }

    /// The shop/payee context for a line item (the section header already shows the day);
    /// `nil` for whole-transaction rows, whose `displayName` is already the payee.
    var storeContext: String? {
        switch source {
        case .lineItem:
            let name = transaction.store?.name ?? transaction.payee
            return name.isEmpty ? nil : name
        case .wholeTransaction:
            return nil
        }
    }

    /// AUTHORITATIVE amount in EUR cents. Negative for discount/deposit line items.
    var amountMinor: Int {
        switch source {
        case .lineItem(let item): item.lineTotalMinor
        case .wholeTransaction(let txn): txn.amountMinor
        }
    }

    var quantityIsUncertain: Bool {
        if case .lineItem(let item) = source { return item.quantityIsUncertain }
        return false
    }

    /// All purchases attributed to `categoryID` (`nil` = Uncategorized), newest first, following
    /// THE REPORTING RULE. Expense kind only. Emits ONE row per matching line item, so a
    /// multi-line same-category transaction yields multiple rows (each linking to that transaction).
    static func entries(in transactions: [Transaction], forCategory categoryID: UUID?) -> [SpendingEntry] {
        var result: [SpendingEntry] = []
        for transaction in transactions where transaction.kind == .expense {
            let items = transaction.lineItems ?? []
            if items.isEmpty {
                if transaction.category?.uuid == categoryID {
                    result.append(SpendingEntry(source: .wholeTransaction(transaction), transaction: transaction))
                }
            } else {
                for item in items where item.category?.uuid == categoryID {
                    result.append(SpendingEntry(source: .lineItem(item), transaction: transaction))
                }
            }
        }
        return result.sorted { $0.date > $1.date }
    }
}
