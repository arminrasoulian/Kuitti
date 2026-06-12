import SwiftUI
import SwiftData

struct BudgetSetupView: View {
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var transactions: [Transaction]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                ForEach(categories.filter { $0.kind == .expense }) { category in
                    BudgetRow(
                        category: category,
                        spentMinor: spentThisMonth(in: category),
                        onChange: { try? context.save() }
                    )
                }
            } footer: {
                Text("Budgets are monthly. Progress counts the current calendar month.")
            }
        }
        .navigationTitle("Budgets")
    }

    /// Same reporting rule as the dashboard: itemized transactions count per line-item
    /// category; itemless ones count transaction.category.
    private func spentThisMonth(in category: Category) -> Int {
        let calendar = Calendar.current
        let now = Date()
        var total = 0
        for transaction in transactions where transaction.kind == .expense
            && calendar.isDate(transaction.date, equalTo: now, toGranularity: .month) {
            let items = transaction.lineItems ?? []
            if items.isEmpty {
                if transaction.category?.uuid == category.uuid { total += transaction.amountMinor }
            } else {
                total += items.filter { $0.category?.uuid == category.uuid }
                    .reduce(0) { $0 + $1.lineTotalMinor }
            }
        }
        return max(total, 0)
    }
}

private struct BudgetRow: View {
    let category: Category
    let spentMinor: Int
    let onChange: () -> Void
    @State private var enabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                CategoryIcon(iconName: category.iconName, colorHex: category.colorHex)
                Text(category.name)
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
            }
            if enabled {
                HStack {
                    Text("Monthly limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    EuroAmountField("0,00", optionalMinor: Binding(
                        get: { category.monthlyBudgetMinor },
                        set: { category.monthlyBudgetMinor = $0; onChange() }
                    ))
                }
                if let budget = category.monthlyBudgetMinor, budget > 0 {
                    let fraction = Double(spentMinor) / Double(budget)
                    ProgressView(value: min(fraction, 1))
                        .tint(fraction > 1 ? .red : Color(hex: category.colorHex))
                    Text("\(Money.euros(spentMinor)) / \(Money.euros(budget))")
                        .font(.caption2)
                        .foregroundStyle(fraction > 1 ? .red : .secondary)
                }
            }
        }
        .onAppear { enabled = category.monthlyBudgetMinor != nil }
        .onChange(of: enabled) { _, isOn in
            if isOn && category.monthlyBudgetMinor == nil {
                category.monthlyBudgetMinor = 10000  // 100 € starting point
                onChange()
            } else if !isOn && category.monthlyBudgetMinor != nil {
                category.monthlyBudgetMinor = nil
                onChange()
            }
        }
    }
}
