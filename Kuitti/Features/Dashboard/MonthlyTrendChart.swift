import SwiftUI
import Charts

/// Income vs expense bars for each month across `interval`.
struct MonthlyTrendChart: View {
    let transactions: [Transaction]
    let interval: DateInterval

    var body: some View {
        let points = SpendingReport.incomeExpenseSeries(transactions, interval: interval)
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Month", point.monthStart, unit: .month),
                    y: .value("Amount", Double(point.incomeMinor) / 100)
                )
                .position(by: .value("Kind", "Income"))
                .foregroundStyle(by: .value("Kind", "Income"))
                .cornerRadius(2)

                BarMark(
                    x: .value("Month", point.monthStart, unit: .month),
                    y: .value("Amount", Double(point.expenseMinor) / 100)
                )
                .position(by: .value("Kind", "Expenses"))
                .foregroundStyle(by: .value("Kind", "Expenses"))
                .cornerRadius(2)
            }
        }
        .chartForegroundStyleScale([
            "Income": Color.accentColor,
            "Expenses": Color(.systemGray),
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: monthAxisStride(forBucketCount: points.count))) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .euroChartYAxis()
        .frame(height: 200)
    }
}
