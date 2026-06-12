import SwiftUI

/// Euro text field bound to Int cents — comma/dot tolerant (Finnish keyboards type ","),
/// parsed through Decimal, never Double.
struct EuroAmountField: View {
    private let title: String
    @Binding private var optionalMinor: Int?
    private let allowsNil: Bool
    @State private var text = ""

    /// Empty field ↔ nil.
    init(_ title: String, optionalMinor: Binding<Int?>) {
        self.title = title
        self._optionalMinor = optionalMinor
        self.allowsNil = true
    }

    /// Empty field → 0.
    init(_ title: String, minor: Binding<Int>) {
        self.title = title
        self._optionalMinor = Binding(
            get: { minor.wrappedValue },
            set: { minor.wrappedValue = $0 ?? 0 }
        )
        self.allowsNil = false
    }

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.numbersAndPunctuation)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .onAppear { syncFromBinding() }
            .onChange(of: text) { _, newValue in
                let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)
                if normalized.isEmpty {
                    optionalMinor = allowsNil ? nil : 0
                } else if let minor = Money.minorUnits(fromDecimalString: normalized) {
                    optionalMinor = minor
                }
            }
            .onChange(of: optionalMinor) { _, _ in
                // External change (e.g. recompute from line items) — refresh unless typing.
                if parsedText != optionalMinor { syncFromBinding() }
            }
    }

    private var parsedText: Int? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return normalized.isEmpty ? nil : Money.minorUnits(fromDecimalString: normalized)
    }

    private func syncFromBinding() {
        if let minor = optionalMinor {
            text = Money.plainDecimalString(minor).replacingOccurrences(of: ".", with: ",")
        } else {
            text = ""
        }
    }
}
