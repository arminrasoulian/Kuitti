import SwiftUI
import Charts

extension View {
    /// The dashboard's shared euro Y-axis: grid lines + labels that render thousands as
    /// "1,2 t. €" (`.notation(.compactName)` on currency is iOS 18+, so it's hand-rolled).
    /// Used by both the income/expense and the category-trend charts.
    func euroChartYAxis() -> some View {
        chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let euros = value.as(Double.self) {
                        if abs(euros) >= 1000 {
                            Text("\((euros / 1000).formatted(.number.precision(.fractionLength(0...1)))) t. €")
                        } else {
                            Text(Decimal(euros), format: .currency(code: "EUR").precision(.fractionLength(0)))
                        }
                    }
                }
            }
        }
    }
}

/// X-axis month-label stride that thins out as the bucket count grows, so a long custom range
/// (e.g. several years) doesn't crowd the axis.
nonisolated func monthAxisStride(forBucketCount count: Int) -> Int {
    if count > 18 { return 3 }
    if count > 12 { return 2 }
    return 1
}
