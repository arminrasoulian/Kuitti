import Charts
import SwiftUI

/// Unit price over time, one colored series per store chain — the heart of the
/// "is this a good price?" answer.
struct PriceHistoryChart: View {
    let lineItems: [LineItem]

    var body: some View {
        if points.count >= 2 {
            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("€/unit", point.price)
                )
                .foregroundStyle(by: .value("Store", point.store))
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("€/unit", point.price)
                )
                .foregroundStyle(by: .value("Store", point.store))
            }
            .chartYAxisLabel("€/unit")
            .frame(height: 220)
            .padding(.vertical, 4)
        } else {
            Text("Not enough data for a trend yet")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var points: [PricePoint] {
        lineItems
            .filter { !$0.isDiscountOrDeposit && $0.quantity != 0 }
            .sorted { $0.purchaseDate < $1.purchaseDate }
            .map { item in
                let store = item.transaction?.store?.name ?? item.transaction?.payee
                return PricePoint(
                    date: item.purchaseDate,
                    price: item.unitPrice,
                    store: store?.isEmpty == false ? store! : "Unknown store"
                )
            }
    }
}

private struct PricePoint: Identifiable {
    let id = UUID()
    let date: Date
    let price: Double
    let store: String
}
