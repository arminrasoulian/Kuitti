import SwiftUI
import Charts

/// Expense breakdown donut for one month's transactions.
///
/// THE REPORTING RULE: itemized transactions attribute spend per line item's category
/// (lineTotalMinor summed as-is, discounts included); un-itemized transactions attribute
/// the whole amountMinor to the transaction's category. Nil categories pool under a gray
/// "Uncategorized" slice.
struct CategoryDonutChart: View {
    let transactions: [Transaction]

    var body: some View {
        let slices = makeSlices()
        let totalMinor = slices.reduce(0) { $0 + $1.totalMinor }
        if slices.isEmpty {
            Text("No expenses this month.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 16) {
                donut(slices: slices, totalMinor: totalMinor)
                legend(slices: slices, totalMinor: totalMinor)
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
                }
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
    }

    private func makeSlices() -> [Slice] {
        var totals: [UUID?: Int] = [:]
        var categoriesByUUID: [UUID: Category] = [:]

        for transaction in transactions where transaction.kind == .expense {
            let items = transaction.lineItems ?? []
            if items.isEmpty {
                totals[transaction.category?.uuid, default: 0] += transaction.amountMinor
                if let category = transaction.category { categoriesByUUID[category.uuid] = category }
            } else {
                for item in items {
                    totals[item.category?.uuid, default: 0] += item.lineTotalMinor
                    if let category = item.category { categoriesByUUID[category.uuid] = category }
                }
            }
        }

        return totals
            .compactMap { key, total -> Slice? in
                // A discount-heavy category can net <= 0; SectorMark can't render it.
                guard total > 0 else { return nil }
                if let key, let category = categoriesByUUID[key] {
                    return Slice(id: key.uuidString, name: category.name,
                                 color: Color(hex: category.colorHex), totalMinor: total)
                }
                return Slice(id: "uncategorized", name: "Uncategorized",
                             color: Color(.systemGray), totalMinor: total)
            }
            .sorted { $0.totalMinor > $1.totalMinor }
    }
}
