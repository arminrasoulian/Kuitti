import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var account: Account

    private var balanceMinor: Int {
        account.initialBalanceMinor + (account.transactions ?? []).reduce(0) { $0 + $1.signedAmountMinor }
    }

    private var sortedTransactions: [Transaction] {
        (account.transactions ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 2) {
                    Text("Balance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.euros(balanceMinor))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            Section {
                HStack {
                    Text("Initial balance")
                    Spacer()
                    HouseholdEuroField("0,00", minorValue: $account.initialBalanceMinor, allowsNegative: true) {
                        account.updatedAt = Date()
                        try? context.save()
                    }
                }
            } footer: {
                Text("The balance above is this starting amount plus every transaction on the account.")
            }
            Section("Transactions") {
                if sortedTransactions.isEmpty {
                    Text("No transactions on this account yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTransactions) { transaction in
                        AccountTransactionRow(transaction: transaction)
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountTransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.payee.isEmpty ? "—" : transaction.payee)
                Text(transaction.date.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(minor: transaction.signedAmountMinor, kind: transaction.kind)
        }
    }
}
