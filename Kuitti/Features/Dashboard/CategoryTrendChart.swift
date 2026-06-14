import SwiftUI
import Charts

/// One category's monthly expense across the selected interval — a single-series line so the
/// up/down trend reads clearly (bars are reserved for the income-vs-expense comparison).
struct CategoryTrendChart: View {
    let categoryID: UUID?
    let colorHex: String
    let transactions: [Transaction]
    let interval: DateInterval

    var body: some View {
        let points = SpendingReport.monthlySeries(for: categoryID, in: transactions, interval: interval)
        if points.isEmpty {
            Text("No data for this period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Chart(points) { point in
                LineMark(
                    x: .value("Month", point.monthStart, unit: .month),
                    y: .value("Amount", Double(point.totalMinor) / 100)
                )
                .foregroundStyle(Color(hex: colorHex))

                PointMark(
                    x: .value("Month", point.monthStart, unit: .month),
                    y: .value("Amount", Double(point.totalMinor) / 100)
                )
                .foregroundStyle(Color(hex: colorHex))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: monthAxisStride(forBucketCount: points.count))) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .euroChartYAxis()
            .frame(height: 200)
        }
    }
}
