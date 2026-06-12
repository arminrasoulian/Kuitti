import SwiftUI
import SwiftData

/// Create (existing == nil) or edit a transaction. Line items are edited as value drafts
/// and only applied to the model on Save, so Cancel never leaves half-applied changes.
/// All persistence runs through TransactionEditor.
struct TransactionEditView: View {
    let existing: Transaction?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var date = Date()
    @State private var payee = ""
    @State private var account: Account?
    @State private var category: Category?
    @State private var paymentMethod: PaymentMethod = .card
    @State private var notes = ""
    @State private var lineDrafts: [ManualLineDraft] = []
    @State private var editingLine: ManualLineDraft?
    // True once the user types the total while line items exist — stops the auto-sync
    // from lines and saves with amountOverridden: true.
    @State private var amountTypedManually = false
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool

    init(existing: Transaction?) {
        self.existing = existing
        guard let existing else { return }
        _kind = State(initialValue: existing.kind)
        _amountText = State(initialValue: Money.plainDecimalString(existing.amountMinor))
        _date = State(initialValue: existing.date)
        _payee = State(initialValue: existing.payee)
        _account = State(initialValue: existing.account)
        _category = State(initialValue: existing.category)
        _paymentMethod = State(initialValue: existing.paymentMethod)
        _notes = State(initialValue: existing.notes)
        let items = (existing.lineItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
        _lineDrafts = State(initialValue: items.map(ManualLineDraft.init(item:)))
        // A stored total that differs from the line sum was overridden by the user
        // at some point — keep treating it as overridden unless they retype it.
        if !items.isEmpty {
            let sum = items.reduce(0) { $0 + $1.lineTotalMinor }
            _amountTypedManually = State(initialValue: existing.amountMinor != max(sum, 0))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Income").tag(TransactionKind.income)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                            .frame(maxWidth: 140)
                        Text("€")
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $date)
                }
                Section {
                    TextField("Payee", text: $payee)
                    Picker("Account", selection: $account) {
                        Text("None").tag(nil as Account?)
                        ForEach(availableAccounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                    Picker("Category", selection: $category) {
                        Text("None").tag(nil as Category?)
                        ForEach(availableCategories) { category in
                            Label(category.name, systemImage: category.iconName).tag(category as Category?)
                        }
                    }
                    Picker("Payment method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Line items") {
                    ForEach(lineDrafts) { draft in
                        Button {
                            editingLine = draft
                        } label: {
                            ManualLineDraftRow(draft: draft)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { lineDrafts.remove(atOffsets: $0) }
                    Button("Add line item", systemImage: "plus") {
                        editingLine = ManualLineDraft.empty()
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(item: $editingLine) { draft in
                LineItemEditorSheet(draft: draft) { updated in
                    upsert(updated)
                }
            }
            .onChange(of: kind) { _, newKind in
                if let category, category.kind.rawValue != newKind.rawValue {
                    self.category = nil
                }
            }
            .onChange(of: lineDrafts) {
                syncAmountFromLines()
            }
            .onChange(of: amountText) {
                // Programmatic syncs happen while the field isn't focused.
                if amountFocused { amountTypedManually = true }
            }
            .onAppear {
                if existing == nil && account == nil {
                    account = accounts.first(where: \.isDefault) ?? accounts.first
                }
            }
            .alert("Couldn't save", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Derived state

    private var availableAccounts: [Account] {
        accounts.filter { !$0.isArchived || $0 === account }
    }

    private var availableCategories: [Category] {
        categories.filter { $0.kind.rawValue == kind.rawValue }
    }

    private var parsedAmountMinor: Int? {
        parseEuroText(amountText).map { abs($0) }
    }

    private var lineSumMinor: Int? {
        guard !lineDrafts.isEmpty else { return nil }
        return lineDrafts.reduce(0) { $0 + $1.totalMinor }
    }

    private var canSave: Bool {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && parsedAmountMinor == nil { return false }
        return parsedAmountMinor != nil || lineSumMinor != nil
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Line drafts

    private func upsert(_ draft: ManualLineDraft) {
        if let index = lineDrafts.firstIndex(where: { $0.id == draft.id }) {
            lineDrafts[index] = draft
        } else {
            lineDrafts.append(draft)
        }
    }

    private func syncAmountFromLines() {
        guard !amountTypedManually, let sum = lineSumMinor else { return }
        amountText = Money.plainDecimalString(max(sum, 0))
    }

    private func applyManualLineDrafts(to transaction: Transaction) {
        let keptIDs = Set(lineDrafts.compactMap { $0.item?.uuid })
        for item in transaction.lineItems ?? [] where !keptIDs.contains(item.uuid) {
            modelContext.delete(item)
        }
        for (index, draft) in lineDrafts.enumerated() {
            if let item = draft.item {
                item.displayName = draft.name
                item.quantity = draft.quantity
                item.unit = draft.unit
                item.lineTotalMinor = draft.totalMinor
                item.sortOrder = index
            } else {
                let item = LineItem(
                    rawName: draft.name,
                    displayName: draft.name,
                    quantity: draft.quantity,
                    unit: draft.unit,
                    lineTotalMinor: draft.totalMinor,
                    sortOrder: index
                )
                item.purchaseDate = transaction.date
                item.transaction = transaction
                modelContext.insert(item)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let editor = TransactionEditor(context: modelContext)
        let trimmedPayee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let existing {
                existing.kind = kind
                existing.date = date
                existing.payee = trimmedPayee
                existing.notes = notes
                existing.paymentMethod = paymentMethod
                existing.account = account
                existing.category = category
                applyManualLineDrafts(to: existing)
                let hasLines = !(existing.lineItems ?? []).isEmpty
                if let amount = parsedAmountMinor, !hasLines || amountTypedManually {
                    existing.amountMinor = amount
                }
                try editor.didEdit(existing, amountOverridden: amountTypedManually)
            } else {
                let amount = parsedAmountMinor ?? lineSumMinor.map { max($0, 0) } ?? 0
                let transaction = try editor.createManual(
                    kind: kind,
                    date: date,
                    amountMinor: amount,
                    payee: trimmedPayee,
                    account: account,
                    category: category,
                    notes: notes,
                    paymentMethod: paymentMethod
                )
                if !lineDrafts.isEmpty {
                    applyManualLineDrafts(to: transaction)
                    try editor.didEdit(transaction, amountOverridden: amountTypedManually)
                }
            }
            dismiss()
        } catch {
            errorMessage = AppError(wrapping: error).userMessage
        }
    }
}

// MARK: - Line draft model

private struct ManualLineDraft: Identifiable, Equatable {
    let id: UUID
    var item: LineItem?
    var name: String
    var rawName: String
    var quantity: Double
    var unit: UnitKind
    var totalMinor: Int

    init(item: LineItem) {
        self.id = item.uuid
        self.item = item
        self.name = item.displayName
        self.rawName = item.rawName
        self.quantity = item.quantity
        self.unit = item.unit
        self.totalMinor = item.lineTotalMinor
    }

    private init(id: UUID) {
        self.id = id
        self.item = nil
        self.name = ""
        self.rawName = ""
        self.quantity = 1
        self.unit = .piece
        self.totalMinor = 0
    }

    static func empty() -> ManualLineDraft {
        ManualLineDraft(id: UUID())
    }
}

private struct ManualLineDraftRow: View {
    let draft: ManualLineDraft

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name.isEmpty ? "Unnamed item" : draft.name)
                Text("\(draft.quantity.formatted(.number.precision(.fractionLength(0...3)))) \(draft.unit.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(minor: draft.totalMinor)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Line item editor

private struct LineItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantityText: String
    @State private var unit: UnitKind
    @State private var totalText: String

    private let draft: ManualLineDraft
    private let onSave: (ManualLineDraft) -> Void

    init(draft: ManualLineDraft, onSave: @escaping (ManualLineDraft) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _quantityText = State(initialValue: draft.quantity.formatted(.number.precision(.fractionLength(0...3)).grouping(.never)))
        _unit = State(initialValue: draft.unit)
        _totalText = State(initialValue: Money.plainDecimalString(draft.totalMinor))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if !draft.rawName.isEmpty && draft.rawName != draft.name {
                    LabeledContent("On receipt", value: draft.rawName)
                }
                HStack {
                    Text("Quantity")
                    Spacer()
                    TextField("1", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                Picker("Unit", selection: $unit) {
                    ForEach(UnitKind.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                HStack {
                    Text("Total")
                    Spacer()
                    // Negative totals are valid (discount/deposit-return lines).
                    TextField("0.00", text: $totalText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                    Text("€")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(draft.item == nil && draft.name.isEmpty ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var parsedQuantity: Double? {
        let normalized = quantityText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var parsedTotalMinor: Int? {
        parseEuroText(totalText)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedQuantity != nil
            && parsedTotalMinor != nil
    }

    private func save() {
        guard let quantity = parsedQuantity, let total = parsedTotalMinor else { return }
        var updated = draft
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.quantity = quantity
        updated.unit = unit
        updated.totalMinor = total
        onSave(updated)
        dismiss()
    }
}

// MARK: - Helpers

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

private extension UnitKind {
    var label: String {
        switch self {
        case .piece: "pcs"
        case .kilogram: "kg"
        case .litre: "l"
        case .other: "other"
        }
    }
}
