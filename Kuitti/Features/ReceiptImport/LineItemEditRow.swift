import SwiftData
import SwiftUI

/// One editable receipt line. Resolution chips: green ✓ = confirmed alias, yellow ≈ =
/// fuzzy suggestion, blue "new" = product created on save; discount/deposit lines get a
/// gray capsule instead and never become products.
struct LineItemEditRow: View {
    @Binding var line: LineDraft

    // Literal must match CategoryKind.expense.rawValue — predicate stays on a scalar field.
    @Query(filter: #Predicate<Category> { $0.kindRaw == "expense" }, sort: \Category.sortOrder)
    private var expenseCategories: [Category]

    @State private var quantityText = ""
    @State private var showingUncertainty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                resolutionChip
                VStack(alignment: .leading, spacing: 2) {
                    // Edits the original-language canonical name; the translation is shown below.
                    TextField("Item name", text: $line.canonicalName)
                        .font(.body.weight(.semibold))
                    if let translated = line.translatedName, !translated.isEmpty, translated != line.canonicalName {
                        Text(translated)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !line.rawName.isEmpty && line.rawName != line.canonicalName {
                        Text(line.rawName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if line.uncertain {
                    Button {
                        showingUncertainty = true
                    } label: {
                        UncertaintyBadge()
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                TextField("Qty", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 52)
                Picker("Unit", selection: $line.unit) {
                    ForEach(UnitKind.allCases, id: \.self) { unit in
                        Text(Self.unitLabel(unit)).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                ReceiptEuroField("0.00", minor: $line.lineTotalMinor)
                    .frame(width: 84)
                AmountText(minor: line.lineTotalMinor)
            }
            categoryChip
        }
        .padding(.vertical, 2)
        .onAppear {
            quantityText = line.quantity.formatted(
                .number.precision(.fractionLength(0...3))
                    .locale(Locale(identifier: "en_US_POSIX"))
                    .grouping(.never)
            )
        }
        .onChange(of: quantityText) { _, newValue in
            let cleaned = newValue
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespaces)
            // Quantity is a measurement, not money — Decimal parse for separator tolerance only.
            guard let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return }
            line.quantity = NSDecimalNumber(decimal: decimal).doubleValue
        }
        .alert("Check this line", isPresented: $showingUncertainty) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uncertaintyMessage)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var resolutionChip: some View {
        if line.isDiscountOrDeposit {
            chipLabel("discount/deposit", color: .gray)
        } else {
            switch line.resolution {
            case .confirmedAlias:
                chipLabel("✓", color: .green)
            case .fuzzySuggested:
                chipLabel("≈", color: .yellow)
            case .newProduct:
                chipLabel("new", color: .blue)
            case .notAProduct:
                EmptyView()
            }
        }
    }

    private func chipLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var categoryChip: some View {
        Menu {
            ForEach(expenseCategories) { category in
                Button {
                    line.chosenCategoryUUID = category.uuid
                } label: {
                    Label(category.name, systemImage: category.iconName)
                }
            }
        } label: {
            if let category = effectiveCategory {
                CategoryChipLabel(name: category.name, iconName: category.iconName, colorHex: category.colorHex)
            } else {
                CategoryChipLabel(name: "Category", iconName: "tag", colorHex: "#8E8E93")
            }
        }
        .buttonStyle(.borderless)
    }

    private var effectiveCategory: Category? {
        guard let id = line.chosenCategoryUUID ?? line.suggestedCategoryUUID else { return nil }
        return expenseCategories.first { $0.uuid == id }
    }

    private var uncertaintyMessage: String {
        let reason = line.uncertaintyReason ?? "The parser wasn't confident about this line."
        return reason + "\n\nTip: tap the quantity to fix pcs ↔ kg mix-ups."
    }

    private static func unitLabel(_ unit: UnitKind) -> String {
        switch unit {
        case .piece: "pcs"
        case .kilogram: "kg"
        case .litre: "l"
        case .other: "other"
        }
    }
}

/// String-state ↔ Int-cents euro field; accepts both comma and dot decimal separators.
/// Internal (not private) so ReceiptReviewView reuses it for subtotal/total —
/// receipt-prefixed to avoid colliding with other features' euro-field helpers.
struct ReceiptEuroField: View {
    private let title: String
    @Binding private var minor: Int?

    @State private var text = ""
    @FocusState private var focused: Bool

    /// Optional-cents binding: empty field ↔ nil.
    init(_ title: String, optionalMinor: Binding<Int?>) {
        self.title = title
        self._minor = optionalMinor
    }

    /// Non-optional convenience: empty field parses as 0.
    init(_ title: String, minor: Binding<Int>) {
        self.title = title
        self._minor = Binding(
            get: { minor.wrappedValue },
            set: { minor.wrappedValue = $0 ?? 0 }
        )
    }

    var body: some View {
        // numbersAndPunctuation instead of decimalPad: discount/deposit lines need the
        // minus sign, which the decimal pad lacks.
        TextField(title, text: $text)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($focused)
            .onAppear { text = Self.display(minor) }
            .onChange(of: text) { _, newValue in
                let cleaned = newValue
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)
                if cleaned.isEmpty {
                    minor = nil
                } else if let cents = Money.minorUnits(fromDecimalString: cleaned) {
                    minor = cents
                }
                // Partial input ("-", "3.") keeps the last good value until it parses.
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = Self.display(minor) }
            }
    }

    private static func display(_ minor: Int?) -> String {
        guard let minor else { return "" }
        return Money.plainDecimalString(minor)
    }
}
