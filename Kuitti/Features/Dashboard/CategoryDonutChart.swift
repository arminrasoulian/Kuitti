import SwiftUI
import SwiftData
import Charts

/// Expense breakdown donut for the selected period's transactions.
///
/// THE REPORTING RULE lives in `SpendingReport`: itemized transactions attribute spend per line
/// item's category; un-itemized transactions attribute the whole amount to the transaction's
/// category; nil categories pool under a gray "Uncategorized" slice (totals ≤ 0 are dropped —
/// SectorMark can't render them).
///
/// Both the legend rows and the pie slices are tappable: they drill into `CategoryDetailView`
/// for the period. (A `NavigationLink` can't live inside a `Chart` builder — it takes
/// `ChartContent`, not `View` — so slice taps go through `chartAngleSelection` → a route, and the
/// legend rows set the same route. One `navigationDestination` serves both.)
struct CategoryDonutChart: View {
    let transactions: [Transaction]
    let interval: DateInterval

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @State private var selectedValue: Int?
    @State private var selectedRoute: CategoryRoute?

    var body: some View {
        let slices = makeSlices()
        let totalMinor = slices.reduce(0) { $0 + $1.totalMinor }
        if slices.isEmpty {
            Text("No expenses in this period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 16) {
                donut(slices: slices, totalMinor: totalMinor)
                legend(slices: slices, totalMinor: totalMinor)
            }
            .navigationDestination(item: $selectedRoute) { route in
                CategoryDetailView(
                    category: route.categoryValue,
                    fallbackTitle: "Uncategorized",
                    interval: interval,
                    transactions: transactions
                )
            }
        }
    }

    private func donut(slices: [Slice], totalMinor: Int) -> some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Amount", slice.totalMinor),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .foregroundStyle(slice.color)
            .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedValue)
        .onChange(of: selectedValue) { _, newValue in
            guard let newValue, let slice = slice(at: newValue, in: slices) else { return }
            selectedRoute = slice.route
            selectedValue = nil   // reset so re-tapping the same slice fires again
        }
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    VStack(spacing: 2) {
                        Text("Total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Money.euros(totalMinor))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(height: 220)
    }

    private func legend(slices: [Slice], totalMinor: Int) -> some View {
        VStack(spacing: 8) {
            ForEach(slices) { slice in
                Button {
                    selectedRoute = slice.route
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 10, height: 10)
                        Text(slice.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(Money.euros(slice.totalMinor))
                            .font(.subheadline)
                            .monospacedDigit()
                        Text(shareText(of: slice, totalMinor: totalMinor))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shareText(of slice: Slice, totalMinor: Int) -> String {
        guard totalMinor > 0 else { return "" }
        return (Double(slice.totalMinor) / Double(totalMinor))
            .formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Slice computation

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let color: Color
        let totalMinor: Int
        let category: Category?

        var route: CategoryRoute {
            category.map { .category($0) } ?? .uncategorized
        }
    }

    private func makeSlices() -> [Slice] {
        let totals = SpendingReport.expenseTotals(transactions)
        let byUUID = Dictionary(uniqueKeysWithValues: categories.map { ($0.uuid, $0) })
        return totals
            .compactMap { key, total -> Slice? in
                // A discount-heavy category can net <= 0; SectorMark can't render it.
                guard total > 0 else { return nil }
                if let key, let category = byUUID[key] {
                    return Slice(id: key.uuidString, name: category.name,
                                 color: Color(hex: category.colorHex), totalMinor: total, category: category)
                }
                return Slice(id: "uncategorized", name: "Uncategorized",
                             color: Color(.systemGray), totalMinor: total, category: nil)
            }
            .sorted { $0.totalMinor > $1.totalMinor }
    }

    /// Map a chart angle selection (a cumulative value along the angular axis) back to the slice
    /// it falls in — walking the slices in plot order, the same order the chart draws them.
    private func slice(at value: Int, in slices: [Slice]) -> Slice? {
        var cumulative = 0
        for slice in slices {
            cumulative += slice.totalMinor
            if value < cumulative { return slice }
        }
        return slices.last
    }
}

/// A drill-down target: a concrete category, or the Uncategorized pool. `Hashable` so it can
/// drive `navigationDestination(item:)` (Category is a `PersistentModel`, hence Hashable).
enum CategoryRoute: Hashable {
    case category(Category)
    case uncategorized

    var categoryValue: Category? {
        if case .category(let category) = self { return category }
        return nil
    }
}
