import SwiftData
import SwiftUI
import UIKit

/// The review-and-correct screen between Gemini's parse and the actual save. All edits
/// land in flow.draft (pure values); the ModelContext is only touched on Save, which
/// runs through TransactionEditor.saveReceipt via flow.save.
struct ReceiptReviewView: View {
    @Bindable var flow: ReceiptImportFlow

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var selectedAccount: Account?
    @State private var showingViewer = false
    @State private var saveErrorMessage: String?
    @State private var confirmingCancel = false

    var body: some View {
        if let draft = Binding($flow.draft) {
            form(draft: draft)
        } else {
            ContentUnavailableView("Nothing to review", systemImage: "doc.text.magnifyingglass")
        }
    }

    // MARK: - Form

    private func form(draft: Binding<ReceiptDraft>) -> some View {
        Form {
            headerSection(draft: draft)
            lineItemsSection(draft: draft)
            totalsSection(draft: draft)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { saveBar }
        .task {
            if selectedAccount == nil {
                selectedAccount = accounts.first(where: \.isDefault) ?? accounts.first
            }
        }
        .sheet(isPresented: $showingViewer) {
            if let data = flow.draft?.pages.first {
                ReceiptImageViewer(imageData: data)
            }
        }
        .alert("Couldn't save", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .confirmationDialog("Discard this receipt?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private func headerSection(draft: Binding<ReceiptDraft>) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Store", text: draft.storeNormalizedName)
                        .font(.headline)
                    let raw = draft.wrappedValue.storeRawName
                    if !raw.isEmpty && raw != draft.wrappedValue.storeNormalizedName {
                        Text(raw)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                thumbnail
            }
            DatePicker("Date", selection: draft.date, displayedComponents: [.date, .hourAndMinute])
            Picker("Payment", selection: draft.paymentMethod) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    Text(Self.paymentLabel(method)).tag(method)
                }
            }
            Picker("Account", selection: $selectedAccount) {
                ForEach(accounts) { account in
                    Text(account.name).tag(account as Account?)
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = flow.draft?.pages.first, let image = UIImage(data: data) {
            Button {
                showingViewer = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)
        }
    }

    private func lineItemsSection(draft: Binding<ReceiptDraft>) -> some View {
        Section("Items") {
            ForEach(draft.lines) { $line in
                LineItemEditRow(line: $line)
            }
            .onDelete { offsets in
                flow.draft?.lines.remove(atOffsets: offsets)
            }
            Button {
                addLine()
            } label: {
                Label("Add line", systemImage: "plus")
            }
        }
    }

    private func totalsSection(draft: Binding<ReceiptDraft>) -> some View {
        Section("Totals") {
            HStack {
                Text("Subtotal")
                Spacer()
                ReceiptEuroField("—", optionalMinor: draft.subtotalMinor)
                    .frame(width: 110)
            }
            HStack {
                Text("Total")
                Spacer()
                ReceiptEuroField("0.00", optionalMinor: draft.totalMinor)
                    .frame(width: 110)
            }
            ForEach(Array(draft.wrappedValue.vatLines.enumerated()), id: \.offset) { _, vat in
                HStack {
                    Text("VAT \(vat.ratePercent.formatted(.number.precision(.fractionLength(0...2)))) %")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let base = vat.baseMinor {
                        Text(Money.euros(base))
                            .foregroundStyle(.tertiary)
                    }
                    Text(Money.euros(vat.taxMinor))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            HStack {
                Text("Items sum")
                    .foregroundStyle(.secondary)
                Spacer()
                AmountText(minor: draft.wrappedValue.lineSumMinor)
            }
            // Informative only — a mismatch never blocks saving.
            if let mismatch = draft.wrappedValue.totalMismatchMinor,
               let total = draft.wrappedValue.totalMinor {
                warningRow("Items sum to \(Money.euros(draft.wrappedValue.lineSumMinor)), receipt says \(Money.euros(total)) (difference \(Money.euros(mismatch)))")
            }
            ForEach(draft.wrappedValue.warnings, id: \.self) { warning in
                warningRow(warning)
            }
        }
    }

    private func warningRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.footnote)
            Text(text)
                .font(.footnote)
        }
        .listRowBackground(Color.yellow.opacity(0.12))
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                confirmingCancel = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button {
                save()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func save() {
        do {
            try flow.save(account: selectedAccount, modelContext: modelContext)
            dismiss()
        } catch {
            saveErrorMessage = AppError(wrapping: error).userMessage
        }
    }

    private func addLine() {
        let count = flow.draft?.lines.count ?? 0
        flow.draft?.lines.append(LineDraft(
            rawName: "",
            canonicalName: "",
            quantity: 1,
            unit: .piece,
            lineTotalMinor: 0,
            isDiscountOrDeposit: false,
            uncertain: false,
            uncertaintyReason: nil,
            suggestedCategoryUUID: nil,
            chosenCategoryUUID: nil,
            resolution: .newProduct,
            sortOrder: count
        ))
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
    }

    private static func paymentLabel(_ method: PaymentMethod) -> String {
        switch method {
        case .card: "Card"
        case .cash: "Cash"
        case .mobilePay: "MobilePay"
        case .bankTransfer: "Bank transfer"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }
}
