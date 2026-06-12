import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var searchText = ""
    @State private var filter = TransactionFilter()
    @State private var showingFilter = false
    @State private var showingNew = false
    @State private var pendingDelete: Transaction?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if transactions.isEmpty {
                EmptyStateView(
                    systemImage: "list.bullet.rectangle",
                    title: "No Transactions",
                    message: "Add one with the + button or scan a receipt from the Scan tab."
                )
            } else if daySections.isEmpty {
                if searchText.isEmpty {
                    EmptyStateView(
                        systemImage: "line.3.horizontal.decrease.circle",
                        title: "No Matches",
                        message: "No transactions match the current filters."
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                transactionList
            }
        }
        .navigationTitle("Transactions")
        .searchable(text: $searchText, prompt: "Payee, notes, or item")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingFilter = true
                } label: {
                    TransactionFilterButtonLabel(activeCount: filter.activeCount)
                }
                Button {
                    showingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add transaction")
            }
        }
        .sheet(isPresented: $showingFilter) {
            TransactionFilterSheet(filter: $filter)
        }
        .sheet(isPresented: $showingNew) {
            TransactionEditView(existing: nil)
        }
        .confirmationDialog(
            "Delete transaction?",
            isPresented: deleteDialogPresented,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { transaction in
            Button("Delete", role: .destructive) { delete(transaction) }
        } message: { transaction in
            Text("\(transaction.payee.isEmpty ? "This transaction" : transaction.payee), \(Money.euros(transaction.amountMinor)). This can't be undone.")
        }
        .alert("Something went wrong", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var transactionList: some View {
        List {
            ForEach(daySections, id: \.day) { section in
                Section(headerTitle(for: section.day)) {
                    ForEach(section.transactions) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                        .swipeActions(edge: .trailing) {
                            // No .destructive role: that removes the row optimistically
                            // before the confirmation dialog has run.
                            Button {
                                pendingDelete = transaction
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Filtering & grouping (in memory — data set is small)

    private var visibleTransactions: [Transaction] {
        transactions.filter { filter.matches($0) && matchesSearch($0) }
    }

    private var daySections: [(day: Date, transactions: [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleTransactions) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.date > $1.date })
        }
    }

    private func matchesSearch(_ transaction: Transaction) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        if transaction.payee.localizedCaseInsensitiveContains(query) { return true }
        if transaction.notes.localizedCaseInsensitiveContains(query) { return true }
        return (transaction.lineItems ?? []).contains {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.rawName.localizedCaseInsensitiveContains(query)
        }
    }

    private func headerTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Delete

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func delete(_ transaction: Transaction) {
        do {
            try TransactionEditor(context: modelContext).delete(transaction)
        } catch {
            errorMessage = AppError(wrapping: error).userMessage
        }
    }
}

// MARK: - Row

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(transaction.payee.isEmpty ? "—" : transaction.payee)
                        .lineLimit(1)
                    if let glyph = transaction.source.glyphName {
                        Image(systemName: glyph)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(transaction.source == .recurring ? "Recurring" : "Receipt scan")
                    }
                }
                if !categoryLine.isEmpty {
                    Text(categoryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            AmountText(minor: transaction.signedAmountMinor, kind: transaction.kind)
        }
    }

    private var categoryLine: String {
        if let category = transaction.category { return category.name }
        let items = (transaction.lineItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
        var seen = Set<String>()
        let names = items.compactMap(\.category?.name).filter { seen.insert($0).inserted }
        return names.joined(separator: ", ")
    }
}

private extension TransactionSource {
    var glyphName: String? {
        switch self {
        case .manual: nil
        case .receiptScan: "doc.text.viewfinder"
        case .recurring: "repeat"
        }
    }
}
