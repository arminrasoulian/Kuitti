import SwiftUI
import SwiftData

/// Per-category budget bars for the selected month. Spending follows the same reporting
/// rule as the donut: itemized transactions count per line item's category, un-itemized
/// ones count whole against the transaction's category.
struct BudgetProgressSection: View {
    let monthTransactions: [Transaction]

    @Query(sort: \Category.sortOrder) private var categories: [Category]

    var body: some View {
        let budgeted = categories.filter { $0.kind == .expense && $0.monthlyBudgetMinor != nil }
        if budgeted.isEmpty {
            Text("Set monthly budgets on categories in Settings to track them here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            let spending = expenseTotalsByCategory()
            VStack(spacing: 14) {
                ForEach(budgeted) { category in
                    BudgetRow(category: category, spentMinor: spending[category.uuid] ?? 0)
                }
            }
        }
    }

    private func expenseTotalsByCategory() -> [UUID: Int] {
        var totals: [UUID: Int] = [:]
        for transaction in monthTransactions where transaction.kind == .expense {
            let items = transaction.lineItems ?? []
            if items.isEmpty {
                if let uuid = transaction.category?.uuid {
                    totals[uuid, default: 0] += transaction.amountMinor
                }
            } else {
                for item in items {
                    if let uuid = item.category?.uuid {
                        totals[uuid, default: 0] += item.lineTotalMinor
                    }
                }
            }
        }
        return totals
    }
}

private struct BudgetRow: View {
    let category: Category
    let spentMinor: Int

    var body: some View {
        let budgetMinor = category.monthlyBudgetMinor ?? 0
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
        }
    }

    private func progressFraction(spent: Int, budget: Int) -> Double {
        guard budget > 0 else { return 0 }
        return min(max(Double(spent) / Double(budget), 0), 1)
    }
}
