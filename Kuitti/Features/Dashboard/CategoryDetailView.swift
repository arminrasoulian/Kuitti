import SwiftUI

/// Drill-down for one spending category (or the Uncategorized pool) over the selected period:
/// the total, an optional month-by-month trend, and the individual purchases — each tapping
/// through to the full transaction.
///
/// Pure presentation over the parent's already-filtered transactions, so the totals match the
/// chart slice / budget bar the user tapped. (The reporting rule branches on `lineItems.isEmpty`
/// and pools nil categories, so it can't be a SwiftData predicate — it must run in Swift, exactly
/// as the donut and budget section do.)
struct CategoryDetailView: View {
    /// The tapped category, or `nil` for the Uncategorized pool.
    let category: Category?
    /// Title shown when `category` is nil. Callers pass "Uncategorized".
    let fallbackTitle: String
    /// The period the dashboard is scoped to — defines totals and the trend window.
    let interval: DateInterval
    /// The SAME filtered set the donut/budget computed against (the dashboard's period transactions).
    let transactions: [Transaction]

    private var categoryID: UUID? { category?.uuid }
    private var title: String { category?.name ?? fallbackTitle }

    private var entries: [SpendingEntry] {
        SpendingEntry.entries(in: transactions, forCategory: categoryID)
    }
    private var totalMinor: Int {
        entries.reduce(0) { $0 + $1.amountMinor }
    }
    private var spansMultipleMonths: Bool {
        SpendingReport.monthStarts(in: interval).count > 1
    }

    var body: some View {
        List {
            headerSection
            if spansMultipleMonths {
                Section("Trend") {
                    CategoryTrendChart(
                        categoryID: categoryID,
                        colorHex: category?.colorHex ?? "#999999",
                        transactions: transactions,
                        interval: interval
                    )
                }
            }
            entriesSection
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text("\(entries.count) \(entries.count == 1 ? "item" : "items")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AmountText(minor: totalMinor)
                }
                budgetLine
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var icon: some View {
        if let category {
            CategoryIcon(iconName: category.iconName, colorHex: category.colorHex)
        } else {
            Image(systemName: "tag.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color(.systemGray), in: Circle())
        }
    }

    @ViewBuilder private var budgetLine: some View {
        if let category, let monthly = category.monthlyBudgetMinor {
            let budget = monthly * SpendingReport.elapsedMonthCount(in: interval)
            let spent = max(totalMinor, 0)
            let isOver = budget > 0 && spent > budget
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Money.euros(spent)) / \(Money.euros(budget))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isOver ? Color.red : Color.secondary)
                }
                ProgressView(value: budget > 0 ? min(max(Double(spent) / Double(budget), 0), 1) : 0)
                    .tint(isOver ? Color.red : Color(hex: category.colorHex))
            }
        }
    }

    // MARK: - Items

    @ViewBuilder private var entriesSection: some View {
        if entries.isEmpty {
            Section {
                Text("No spending in this category for this period.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(daySections, id: \.day) { section in
                Section(headerTitle(for: section.day)) {
                    ForEach(section.entries) { entry in
                        NavigationLink {
                            TransactionDetailView(transaction: entry.transaction)
                        } label: {
                            SpendingEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    private var daySections: [(day: Date, entries: [SpendingEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.date > $1.date })
        }
    }

    private func headerTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Row

private struct SpendingEntryRow: View {
    let entry: SpendingEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.displayName)
                        .lineLimit(1)
                    if entry.quantityIsUncertain {
                        UncertaintyBadge()
                            .font(.caption)
                    }
                }
                if let secondary = entry.secondaryName {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let store = entry.storeContext {
                    Text(store)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            AmountText(minor: entry.amountMinor)
        }
    }
}
