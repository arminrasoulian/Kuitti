import SwiftUI
import SwiftData

/// In-memory filter applied by TransactionListView. Date bounds are whole-day inclusive;
/// amounts compare the unsigned total.
struct TransactionFilter: Equatable {
    var fromDate: Date?
    var toDate: Date?
    var kind: TransactionKind?
    var account: Account?
    var category: Category?
    var paymentMethod: PaymentMethod?
    var minAmountMinor: Int?
    var maxAmountMinor: Int?

    /// Date range and amount range each count as one filter for the toolbar badge.
    var activeCount: Int {
        var count = 0
        if fromDate != nil || toDate != nil { count += 1 }
        if kind != nil { count += 1 }
        if account != nil { count += 1 }
        if category != nil { count += 1 }
        if paymentMethod != nil { count += 1 }
        if minAmountMinor != nil || maxAmountMinor != nil { count += 1 }
        return count
    }

    var isActive: Bool { activeCount > 0 }

    func matches(_ transaction: Transaction) -> Bool {
        let calendar = Calendar.current
        if let fromDate, transaction.date < calendar.startOfDay(for: fromDate) { return false }
        if let toDate {
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: toDate)) ?? toDate
            if transaction.date >= endExclusive { return false }
        }
        if let kind, transaction.kind != kind { return false }
        if let account, transaction.account !== account { return false }
        if let category {
            let inLines = (transaction.lineItems ?? []).contains { $0.category === category }
            if transaction.category !== category && !inLines { return false }
        }
        if let paymentMethod, transaction.paymentMethod != paymentMethod { return false }
        if let minAmountMinor, transaction.amountMinor < minAmountMinor { return false }
        if let maxAmountMinor, transaction.amountMinor > maxAmountMinor { return false }
        return true
    }
}

/// Toolbar label for the filter button — fills and badges when filters are active.
struct TransactionFilterButtonLabel: View {
    let activeCount: Int

    var body: some View {
        Image(systemName: activeCount > 0
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle")
            .overlay(alignment: .topTrailing) {
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 8, y: -8)
                }
            }
            .accessibilityLabel(activeCount > 0 ? "Filters, \(activeCount) active" : "Filters")
    }
}

struct TransactionFilterSheet: View {
    @Binding var filter: TransactionFilter
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var draft: TransactionFilter
    @State private var minAmountText: String
    @State private var maxAmountText: String

    init(filter: Binding<TransactionFilter>) {
        _filter = filter
        let value = filter.wrappedValue
        _draft = State(initialValue: value)
        _minAmountText = State(initialValue: value.minAmountMinor.map(Money.plainDecimalString) ?? "")
        _maxAmountText = State(initialValue: value.maxAmountMinor.map(Money.plainDecimalString) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Toggle("From", isOn: dateToggle(\.fromDate))
                    if draft.fromDate != nil {
                        DatePicker("From date", selection: dateValue(\.fromDate), displayedComponents: .date)
                    }
                    Toggle("To", isOn: dateToggle(\.toDate))
                    if draft.toDate != nil {
                        DatePicker("To date", selection: dateValue(\.toDate), displayedComponents: .date)
                    }
                }
                Section {
                    Picker("Kind", selection: $draft.kind) {
                        Text("Any").tag(nil as TransactionKind?)
                        Text("Expense").tag(TransactionKind.expense as TransactionKind?)
                        Text("Income").tag(TransactionKind.income as TransactionKind?)
                    }
                    Picker("Account", selection: $draft.account) {
                        Text("Any").tag(nil as Account?)
                        ForEach(accounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                    Picker("Category", selection: $draft.category) {
                        Text("Any").tag(nil as Category?)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.iconName).tag(category as Category?)
                        }
                    }
                    Picker("Payment method", selection: $draft.paymentMethod) {
                        Text("Any").tag(nil as PaymentMethod?)
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(method.label).tag(method as PaymentMethod?)
                        }
                    }
                }
                Section("Amount") {
                    amountRow(label: "Min", text: $minAmountText)
                    amountRow(label: "Max", text: $maxAmountText)
                }
                Section {
                    Button("Reset filters") {
                        draft = TransactionFilter()
                        minAmountText = ""
                        maxAmountText = ""
                    }
                    .disabled(!draft.isActive && minAmountText.isEmpty && maxAmountText.isEmpty)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(!amountTextsValid)
                }
            }
        }
    }

    private func amountRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text("€")
                .foregroundStyle(.secondary)
        }
    }

    private var amountTextsValid: Bool {
        isValidOrEmpty(minAmountText) && isValidOrEmpty(maxAmountText)
    }

    private func isValidOrEmpty(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty || parseEuroText(text) != nil
    }

    private func apply() {
        draft.minAmountMinor = parseEuroText(minAmountText).map { abs($0) }
        draft.maxAmountMinor = parseEuroText(maxAmountText).map { abs($0) }
        filter = draft
        dismiss()
    }

    private func dateToggle(_ keyPath: WritableKeyPath<TransactionFilter, Date?>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] != nil },
            set: { draft[keyPath: keyPath] = $0 ? Calendar.current.startOfDay(for: Date()) : nil }
        )
    }

    private func dateValue(_ keyPath: WritableKeyPath<TransactionFilter, Date?>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: keyPath] ?? Date() },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }
}

/// Comma decimals (fi_FI keyboards) are normalized to dots before the Decimal parse.
private func parseEuroText(_ text: String) -> Int? {
    let normalized = text
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: ",", with: ".")
        .replacingOccurrences(of: "€", with: "")
        .trimmingCharacters(in: .whitespaces)
    guard !normalized.isEmpty else { return nil }
    return Money.minorUnits(fromDecimalString: normalized)
}

private extension PaymentMethod {
    var label: String {
        switch self {
        case .card: "Card"
        case .cash: "Cash"
        case .mobilePay: "MobilePay"
        case .bankTransfer: "Bank transfer"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }
}
