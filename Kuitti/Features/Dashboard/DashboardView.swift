import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var period = ReportPeriod.current()
    @State private var trendSelection: TrendSelection?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PeriodSelector(period: $period)
                summaryCards
                sectionCard("Spending by Category") {
                    CategoryDonutChart(transactions: periodTransactions, interval: periodInterval)
                }
                if period.isMultiMonth {
                    sectionCard("Category trend") {
                        categoryTrendContent
                    }
                }
                sectionCard("Income vs Expenses") {
                    MonthlyTrendChart(transactions: transactions, interval: trendInterval)
                }
                sectionCard("Budgets") {
                    BudgetProgressSection(monthTransactions: periodTransactions, interval: periodInterval)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                statCard {
                    Text("Income")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(minor: incomeMinor, kind: .income)
                }
                statCard {
                    Text("Expenses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AmountText(minor: expensesMinor, kind: .expense)
                    expenseComparisonLine
                }
            }
            statCard {
                HStack {
                    Text("Net")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    AmountText(minor: netMinor, kind: netMinor >= 0 ? .income : .expense)
                }
            }
        }
    }

    @ViewBuilder
    private var expenseComparisonLine: some View {
        if let percent = expenseChangePercent, let label = period.comparisonLabel {
            Text("\(percent > 0 ? "+" : "")\(percent)% \(label)")
                .font(.caption2)
                .foregroundStyle(percent > 0 ? Color.red : (percent < 0 ? Color.green : Color.secondary))
        }
    }

    // MARK: - Category trend (multi-month only)

    @ViewBuilder
    private var categoryTrendContent: some View {
        let options = trendOptions
        if options.isEmpty {
            Text("No expenses in this period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            let selection = resolvedTrendSelection(options: options)
            VStack(alignment: .leading, spacing: 12) {
                Picker("Category", selection: trendBinding(default: selection)) {
                    ForEach(options) { option in
                        Text(option.name).tag(option.selection)
                    }
                }
                .pickerStyle(.menu)
                CategoryTrendChart(
                    categoryID: selection.categoryID,
                    colorHex: options.first { $0.selection == selection }?.colorHex ?? "#999999",
                    transactions: periodTransactions,
                    interval: periodInterval
                )
            }
        }
    }

    private struct TrendOption: Identifiable {
        let selection: TrendSelection
        let name: String
        let colorHex: String
        let totalMinor: Int
        var id: TrendSelection { selection }
    }

    /// Categories with positive spend this period, largest first, plus an "Uncategorized" entry
    /// when there's uncategorized spend.
    private var trendOptions: [TrendOption] {
        let totals = SpendingReport.expenseTotals(periodTransactions)
        let byUUID = Dictionary(uniqueKeysWithValues: categories.map { ($0.uuid, $0) })
        return totals
            .compactMap { key, total -> TrendOption? in
                guard total > 0 else { return nil }
                if let key, let category = byUUID[key] {
                    return TrendOption(selection: .category(key), name: category.name,
                                       colorHex: category.colorHex, totalMinor: total)
                }
                if key == nil {
                    return TrendOption(selection: .uncategorized, name: "Uncategorized",
                                       colorHex: "#999999", totalMinor: total)
                }
                return nil
            }
            .sorted { $0.totalMinor > $1.totalMinor }
    }

    /// The user's pick if it still has spend this period; otherwise the largest spender.
    private func resolvedTrendSelection(options: [TrendOption]) -> TrendSelection {
        if let current = trendSelection, options.contains(where: { $0.selection == current }) {
            return current
        }
        return options.first?.selection ?? .uncategorized
    }

    private func trendBinding(default selection: TrendSelection) -> Binding<TrendSelection> {
        Binding(get: { selection }, set: { trendSelection = $0 })
    }

    // MARK: - Cards

    private func statCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Period math

    private var calendar: Calendar { Calendar.current }

    private var periodInterval: DateInterval { period.dateInterval }

    private var periodTransactions: [Transaction] {
        transactions.filter { periodInterval.contains($0.date) }
    }

    /// The income-vs-expense trend keeps the familiar trailing-6-month context for a single
    /// month (one bar pair is a poor "trend"); for year/custom it spans the period's months.
    private var trendInterval: DateInterval {
        switch period.kind {
        case .month:
            let end = periodInterval.end
            let monthStart = calendar.dateInterval(of: .month, for: period.anchor)?.start ?? periodInterval.start
            let start = calendar.date(byAdding: .month, value: -5, to: monthStart) ?? monthStart
            return DateInterval(start: start, end: end)
        case .year, .custom:
            return periodInterval
        }
    }

    private var incomeMinor: Int {
        periodTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountMinor }
    }

    private var expensesMinor: Int {
        periodTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountMinor }
    }

    private var netMinor: Int { incomeMinor - expensesMinor }

    private var previousExpensesMinor: Int {
        guard let previous = period.previousInterval() else { return 0 }
        return transactions
            .filter { previous.contains($0.date) && $0.kind == .expense }
            .reduce(0) { $0 + $1.amountMinor }
    }

    /// Rounded percent change vs the previous comparable period; nil when there's nothing to
    /// compare against (no prior data, or a custom range with no natural predecessor).
    private var expenseChangePercent: Int? {
        guard previousExpensesMinor > 0 else { return nil }
        let delta = Double(expensesMinor - previousExpensesMinor) / Double(previousExpensesMinor)
        return Int((delta * 100).rounded())
    }
}

/// Which series the multi-month "Category trend" card is showing.
enum TrendSelection: Hashable {
    case category(UUID)
    case uncategorized

    var categoryID: UUID? {
        switch self {
        case .category(let id): id
        case .uncategorized: nil
        }
    }
}
