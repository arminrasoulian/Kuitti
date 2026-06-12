import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var selectedMonth = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthStepper
                summaryCards
                sectionCard("Spending by Category") {
                    CategoryDonutChart(transactions: monthTransactions)
                }
                sectionCard("Income vs Expenses") {
                    MonthlyTrendChart(transactions: transactions, endingMonth: selectedMonth)
                }
                sectionCard("Budgets") {
                    BudgetProgressSection(monthTransactions: monthTransactions)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
    }

    // MARK: - Month stepper

    private var monthStepper: some View {
        HStack {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(Self.monthLabelFormatter.string(from: selectedMonth))
                .font(.title3.weight(.semibold))

            Spacer()

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
        .padding(.top, 4)
    }

    private func step(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: selectedMonth) else { return }
        let nextMonthStart = calendar.dateInterval(of: .month, for: next)?.start ?? next
        guard nextMonthStart <= Date() else { return }
        selectedMonth = next
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    // Standalone month name (LLLL) — in Finnish the nominative form, not the partitive MMMM.
    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

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
        if let percent = expenseChangePercent {
            Text("\(percent > 0 ? "+" : "")\(percent)% vs last month")
                .font(.caption2)
                .foregroundStyle(percent > 0 ? Color.red : (percent < 0 ? Color.green : Color.secondary))
        }
    }

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

    // MARK: - Month math

    private var calendar: Calendar { Calendar.current }

    private var monthTransactions: [Transaction] {
        guard let interval = calendar.dateInterval(of: .month, for: selectedMonth) else { return [] }
        return transactions.filter { interval.contains($0.date) }
    }

    private var incomeMinor: Int {
        monthTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amountMinor }
    }

    private var expensesMinor: Int {
        monthTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amountMinor }
    }

    private var netMinor: Int { incomeMinor - expensesMinor }

    private var previousMonthExpensesMinor: Int {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: selectedMonth),
              let interval = calendar.dateInterval(of: .month, for: previous) else { return 0 }
        return transactions
            .filter { interval.contains($0.date) && $0.kind == .expense }
            .reduce(0) { $0 + $1.amountMinor }
    }

    /// Rounded percent change vs the previous month; nil when there is nothing to compare against.
    private var expenseChangePercent: Int? {
        guard previousMonthExpensesMinor > 0 else { return nil }
        let delta = Double(expensesMinor - previousMonthExpensesMinor) / Double(previousMonthExpensesMinor)
        return Int((delta * 100).rounded())
    }
}
