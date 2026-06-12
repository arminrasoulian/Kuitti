import SwiftUI
import SwiftData

struct AccountListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var editingAccount: Account?
    @State private var isCreating = false
    @State private var archiveCandidate: Account?
    @State private var showArchivePrompt = false

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { accounts.filter(\.isArchived) }

    var body: some View {
        List {
            Section {
                ForEach(activeAccounts) { account in
                    row(for: account)
                }
            }
            if !archivedAccounts.isEmpty {
                Section {
                    DisclosureGroup("Archived (\(archivedAccounts.count))") {
                        ForEach(archivedAccounts) { account in
                            row(for: account)
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Account", systemImage: "plus") { isCreating = true }
            }
        }
        .overlay {
            if accounts.isEmpty {
                EmptyStateView(
                    systemImage: "creditcard",
                    title: "No Accounts",
                    message: "Add a bank, cash, or credit account to track balances."
                )
            }
        }
        .sheet(isPresented: $isCreating) {
            AccountFormSheet(account: nil, nextSortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1)
        }
        .sheet(item: $editingAccount) { account in
            AccountFormSheet(account: account, nextSortOrder: 0)
        }
        .alert("Account Has Transactions", isPresented: $showArchivePrompt, presenting: archiveCandidate) { account in
            Button("Archive") {
                account.isArchived = true
                account.updatedAt = Date()
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text("\(account.name) has \(account.transactions?.count ?? 0) transactions, so it can't be deleted. Archiving hides it from pickers while keeping the history.")
        }
    }

    private func row(for account: Account) -> some View {
        NavigationLink {
            AccountDetailView(account: account)
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(iconName: account.iconName, colorHex: account.colorHex)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                    if account.isDefault {
                        Text("Default")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                AmountText(minor: balance(of: account))
            }
        }
        .swipeActions(edge: .leading) {
            Button("Edit", systemImage: "pencil") { editingAccount = account }
                .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash") { attemptDelete(account) }
                .tint(.red)
            if account.isArchived {
                Button("Unarchive", systemImage: "tray.and.arrow.up") {
                    account.isArchived = false
                    account.updatedAt = Date()
                    try? context.save()
                }
            }
        }
    }

    private func balance(of account: Account) -> Int {
        account.initialBalanceMinor + (account.transactions ?? []).reduce(0) { $0 + $1.signedAmountMinor }
    }

    private func attemptDelete(_ account: Account) {
        guard (account.transactions ?? []).isEmpty else {
            archiveCandidate = account
            showArchivePrompt = true
            return
        }
        if let seedID = account.seedIdentifier {
            SeedDataService.recordDismissed(seedIdentifier: seedID)
        }
        context.delete(account)
        try? context.save()
    }
}

// MARK: - Create/edit sheet

private struct AccountFormSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let account: Account?
    let nextSortOrder: Int

    @State private var name: String
    @State private var type: AccountType
    @State private var initialBalanceMinor: Int?
    @State private var iconName: String
    @State private var colorHex: String

    private static let icons = ["creditcard.fill", "banknote.fill", "wallet.pass.fill", "building.columns.fill"]
    private static let palette = ["#4A90D9", "#34C759", "#FF9500", "#FF3B30", "#AF52DE", "#5856D6", "#30B0C7", "#A2845E"]

    init(account: Account?, nextSortOrder: Int) {
        self.account = account
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .bank)
        _initialBalanceMinor = State(initialValue: account?.initialBalanceMinor)
        _iconName = State(initialValue: account?.iconName ?? "creditcard.fill")
        _colorHex = State(initialValue: account?.colorHex ?? "#4A90D9")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Text(type.displayLabel).tag(type)
                        }
                    }
                    HStack {
                        Text("Initial balance")
                        Spacer()
                        HouseholdEuroField("0,00", minor: $initialBalanceMinor, allowsNegative: true)
                    }
                }
                Section("Icon") {
                    HStack(spacing: 16) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(iconName == icon ? Color.white : Color.secondary)
                                    .frame(width: 44, height: 44)
                                    .background(iconName == icon ? Color(hex: colorHex) : Color(.systemFill), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(Self.palette, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if colorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let account {
            account.name = trimmed
            account.type = type
            account.initialBalanceMinor = initialBalanceMinor ?? 0
            account.iconName = iconName
            account.colorHex = colorHex
            account.updatedAt = Date()
        } else {
            let new = Account(name: trimmed, type: type, initialBalanceMinor: initialBalanceMinor ?? 0)
            new.iconName = iconName
            new.colorHex = colorHex
            new.sortOrder = nextSortOrder
            context.insert(new)
        }
        try? context.save()
        dismiss()
    }
}

private extension AccountType {
    var displayLabel: String {
        switch self {
        case .bank: "Bank"
        case .cash: "Cash"
        case .credit: "Credit card"
        }
    }
}

// MARK: - Shared euro entry

/// Comma/dot-tolerant euro entry shared by the management screens. Edits cents (Int?)
/// live on every keystroke (so a sheet's Save button never reads a stale binding) and
/// snaps the text to canonical "12,34" form on focus loss / submit, when onCommit fires.
/// Parsing goes through Decimal via Money.minorUnits — never Double.
struct HouseholdEuroField: View {
    private let title: String
    @Binding private var minor: Int?
    private let allowsNegative: Bool
    private let onCommit: (() -> Void)?

    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(_ title: String, minor: Binding<Int?>, allowsNegative: Bool = false, onCommit: (() -> Void)? = nil) {
        self.title = title
        self._minor = minor
        self.allowsNegative = allowsNegative
        self.onCommit = onCommit
    }

    /// Non-optional convenience: cleared input maps to 0.
    init(_ title: String, minorValue: Binding<Int>, allowsNegative: Bool = false, onCommit: (() -> Void)? = nil) {
        self.init(
            title,
            minor: Binding<Int?>(
                get: { minorValue.wrappedValue },
                set: { minorValue.wrappedValue = $0 ?? 0 }
            ),
            allowsNegative: allowsNegative,
            onCommit: onCommit
        )
    }

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($isFocused)
            .onAppear {
                if !isFocused { text = Self.display(minor) }
            }
            .onChange(of: text) { _, newValue in
                if let parsed = Self.parse(newValue, allowsNegative: allowsNegative) {
                    minor = parsed
                } else if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    minor = nil
                }
            }
            .onChange(of: minor) { _, newValue in
                if !isFocused { text = Self.display(newValue) }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        text = Self.display(minor)
        onCommit?()
    }

    private static func parse(_ raw: String, allowsNegative: Bool) -> Int? {
        let normalized = raw
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty,
              let cents = Money.minorUnits(fromDecimalString: normalized) else { return nil }
        if cents < 0 && !allowsNegative { return nil }
        return cents
    }

    private static func display(_ minor: Int?) -> String {
        guard let minor else { return "" }
        return Money.plainDecimalString(minor).replacingOccurrences(of: ".", with: ",")
    }
}
