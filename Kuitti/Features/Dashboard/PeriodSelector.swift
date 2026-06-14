import SwiftUI

/// Scope control for the Dashboard: Month / Year / Custom. Month & Year use the familiar chevron
/// stepper (clamped so it never advances past the current period); Custom uses two date pickers.
struct PeriodSelector: View {
    @Binding var period: ReportPeriod

    var body: some View {
        VStack(spacing: 12) {
            Picker("Scope", selection: kindBinding) {
                ForEach(ReportPeriod.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch period.kind {
            case .month, .year: stepperRow
            case .custom: customRange
            }
        }
        .padding(.top, 4)
    }

    // Switching kind preserves the anchor; the first switch to Custom seeds the range to the
    // anchor's month (start … min(today, month end)).
    private var kindBinding: Binding<ReportPeriod.Kind> {
        Binding(
            get: { period.kind },
            set: { newKind in
                var copy = period
                copy.kind = newKind
                if newKind == .custom {
                    let calendar = Calendar.current
                    if let monthInterval = calendar.dateInterval(of: .month, for: period.anchor) {
                        let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.start
                        copy.customStart = monthInterval.start
                        copy.customEnd = min(Date(), lastDay)
                    }
                }
                period = copy
            }
        )
    }

    private var stepperRow: some View {
        HStack {
            Button { period = period.stepped(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("Previous period")

            Spacer()

            Text(period.displayLabel)
                .font(.title3.weight(.semibold))

            Spacer()

            Button { period = period.stepped(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .disabled(period.isCurrent())
            .accessibilityLabel("Next period")
        }
    }

    private var customRange: some View {
        VStack(spacing: 8) {
            DatePicker("From", selection: customStartBinding, in: ...period.customEnd, displayedComponents: .date)
            DatePicker("To", selection: customEndBinding, in: period.customStart...Date(), displayedComponents: .date)
        }
        .font(.subheadline)
    }

    private var customStartBinding: Binding<Date> {
        Binding(get: { period.customStart }, set: { var copy = period; copy.customStart = $0; period = copy })
    }

    private var customEndBinding: Binding<Date> {
        Binding(get: { period.customEnd }, set: { var copy = period; copy.customEnd = $0; period = copy })
    }
}
