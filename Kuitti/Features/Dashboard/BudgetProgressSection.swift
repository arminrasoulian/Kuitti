import SwiftUI
import SwiftData

/// Per-category budget bars for the selected period. Spending follows THE REPORTING RULE
/// (`SpendingReport`). Budgets are monthly, so for multi-month periods the target is scaled by
/// the number of months *elapsed* so far (a still-running year counts only Jan…current month).
/// Each bar drills into `CategoryDetailView`.
struct BudgetProgressSection: View {
    let monthTransactions: [Transaction]
    let interval: DateInterval

    @Query(sort: \Category.sortOrder) private var categories: [Category]

    var body: some View {
        let budgeted = categories.filter { $0.kind == .expense && $0.monthlyBudgetMinor != nil }
        if budgeted.isEmpty {
            Text("Set monthly budgets on categories in Settings to track them here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            let totals = SpendingReport.expenseTotals(monthTransactions)
            let monthCount = SpendingReport.elapsedMonthCount(in: interval)
            VStack(spacing: 14) {
                if monthCount > 1 {
                    Text("Budgets scaled ×\(monthCount) for this period.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(budgeted) { category in
                    NavigationLink {
                        CategoryDetailView(
                            category: category,
                            fallbackTitle: category.name,
                            interval: interval,
                            transactions: monthTransactions
                        )
                    } label: {
                        BudgetRow(
                            category: category,
                            spentMinor: max(totals[category.uuid] ?? 0, 0),
                            budgetMinor: (category.monthlyBudgetMinor ?? 0) * monthCount
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BudgetRow: View {
    let category: Category
    let spentMinor: Int
    let budgetMinor: Int

    var body: some View {
        let isOver = budgetMinor > 0 && spentMinor > budgetMinor
        HStack(spacing: 12) {
            CategoryIcon(iconName: category.iconName, colorHex: category.colorHex)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Money.euros(spentMinor)) / \(Money.euros(budgetMinor))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isOver ? Color.red : Color.secondary)
                }
                ProgressView(value: progressFraction(spent: spentMinor, budget: budgetMinor))
                    .tint(isOver ? Color.red : Color(hex: category.colorHex))
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func progressFraction(spent: Int, budget: Int) -> Double {
        guard budget > 0 else { return 0 }
        return min(max(Double(spent) / Double(budget), 0), 1)
    }
}
