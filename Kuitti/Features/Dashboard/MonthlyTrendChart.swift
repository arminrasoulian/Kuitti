import SwiftUI
import Charts

/// Income vs expense bars for the six months ending at `endingMonth`.
struct MonthlyTrendChart: View {
    let transactions: [Transaction]
    let endingMonth: Date

    var body: some View {
        let buckets = makeBuckets()
        Chart {
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Month", bucket.monthStart, unit: .month),
                    y: .value("Amount", Double(bucket.incomeMinor) / 100)
                )
                .position(by: .value("Kind", "Income"))
                .foregroundStyle(by: .value("Kind", "Income"))
                .cornerRadius(2)

                BarMark(
                    x: .value("Month", bucket.monthStart, unit: .month),
                    y: .value("Amount", Double(bucket.expenseMinor) / 100)
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
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let euros = value.as(Double.self) {
                        // .notation(.compactName) on currency is iOS 18+; hand-roll "1,2 t. €".
                        if abs(euros) >= 1000 {
                            Text("\((euros / 1000).formatted(.number.precision(.fractionLength(0...1)))) t. €")
                        } else {
                            Text(Decimal(euros), format: .currency(code: "EUR").precision(.fractionLength(0)))
                        }
                    }
                }
            }
        }
        .frame(height: 200)
    }

    // MARK: - Bucketing

    private struct MonthBucket: Identifiable {
        let monthStart: Date
        let incomeMinor: Int
        let expenseMinor: Int
        var id: Date { monthStart }
    }

    private func makeBuckets() -> [MonthBucket] {
        let calendar = Calendar.current
        guard let endStart = calendar.dateInterval(of: .month, for: endingMonth)?.start else { return [] }
        return (0..<6).reversed().compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: endStart),
                  let interval = calendar.dateInterval(of: .month, for: monthDate) else { return nil }
            var income = 0
            var expense = 0
            for transaction in transactions where interval.contains(transaction.date) {
                switch transaction.kind {
                case .income: income += transaction.amountMinor
                case .expense: expense += transaction.amountMinor
                }
            }
            return MonthBucket(monthStart: interval.start, incomeMinor: income, expenseMinor: expense)
        }
    }
}
