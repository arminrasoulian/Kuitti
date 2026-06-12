import SwiftUI
import UIKit

struct TransactionDetailView: View {
    let transaction: Transaction

    @State private var showingEdit = false
    @State private var viewerImage: ViewerImage?

    var body: some View {
        List {
            headerSection
            detailsSection
            if !transaction.notes.isEmpty {
                Section("Notes") {
                    Text(transaction.notes)
                }
            }
            if !transaction.importWarnings.isEmpty {
                warningsSection
            }
            if !transaction.vatLines.isEmpty {
                vatSection
            }
            if !sortedLineItems.isEmpty {
                lineItemsSection
            }
            if !sortedImages.isEmpty {
                receiptSection
            }
        }
        .navigationTitle(transaction.payee.isEmpty ? "Transaction" : transaction.payee)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            TransactionEditView(existing: transaction)
        }
        .fullScreenCover(item: $viewerImage) { image in
            ReceiptImageViewer(imageData: image.data)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: 4) {
                Text(Money.euros(transaction.signedAmountMinor))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(transaction.kind == .income ? Color.accentColor : .primary)
                Text(transaction.date.formatted(date: .long, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private var detailsSection: some View {
        Section {
            LabeledContent("Payee", value: transaction.payee.isEmpty ? "—" : transaction.payee)
            if let store = transaction.store, store.name != transaction.payee {
                LabeledContent("Store", value: store.name)
            }
            LabeledContent("Account", value: transaction.account?.name ?? "—")
            LabeledContent("Payment", value: transaction.paymentMethod.label)
            LabeledContent("Source", value: transaction.source.label)
            if let category = transaction.category {
                LabeledContent("Category") {
                    CategoryChipLabel(name: category.name, iconName: category.iconName, colorHex: category.colorHex)
                }
            }
        }
    }

    private var warningsSection: some View {
        Section("Warnings") {
            ForEach(transaction.importWarnings, id: \.self) { warning in
                Label {
                    Text(warning)
                        .font(.callout)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                .listRowBackground(Color.yellow.opacity(0.12))
            }
        }
    }

    private var vatSection: some View {
        Section("VAT") {
            ForEach(transaction.vatLines, id: \.self) { line in
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Money.euros(line.taxMinor))
                            .monospacedDigit()
                        if let base = line.baseMinor {
                            Text("Base \(Money.euros(base))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Text("\(line.ratePercent.formatted(.number.precision(.fractionLength(0...2)))) %")
                }
            }
            if let subtotal = transaction.subtotalMinor {
                LabeledContent("Subtotal") {
                    Text(Money.euros(subtotal))
                        .monospacedDigit()
                }
            }
        }
    }

    private var lineItemsSection: some View {
        Section("Line items") {
            ForEach(sortedLineItems) { item in
                LineItemRow(item: item)
            }
        }
    }

    private var receiptSection: some View {
        Section("Receipt") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sortedImages) { image in
                        if let data = image.imageData, let uiImage = UIImage(data: data) {
                            Button {
                                viewerImage = ViewerImage(data: data)
                            } label: {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Receipt page \(image.pageIndex + 1)")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var sortedLineItems: [LineItem] {
        (transaction.lineItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sortedImages: [ReceiptImage] {
        (transaction.receiptImages ?? []).sorted { $0.pageIndex < $1.pageIndex }
    }
}

// MARK: - Line item row

private struct LineItemRow: View {
    let item: LineItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(item.displayName.isEmpty ? item.rawName : item.displayName)
                    if item.quantityIsUncertain {
                        UncertaintyBadge()
                            .font(.caption)
                    }
                }
                if !item.rawName.isEmpty && item.rawName != item.displayName {
                    Text(item.rawName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(metricsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let category = item.category {
                    CategoryChipLabel(name: category.name, iconName: category.iconName, colorHex: category.colorHex)
                }
            }
            Spacer()
            AmountText(minor: item.lineTotalMinor)
        }
    }

    private var metricsLine: String {
        let quantity = item.quantity.formatted(.number.precision(.fractionLength(0...3)))
        let unitPrice = item.unitPrice.formatted(.currency(code: "EUR"))
        switch item.unit {
        case .piece: return "\(quantity) pcs · \(unitPrice) each"
        case .kilogram: return "\(quantity) kg · \(unitPrice)/kg"
        case .litre: return "\(quantity) l · \(unitPrice)/l"
        case .other: return "\(quantity) · \(unitPrice)"
        }
    }
}

private struct ViewerImage: Identifiable {
    let id = UUID()
    let data: Data
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

private extension TransactionSource {
    var label: String {
        switch self {
        case .manual: "Manual"
        case .receiptScan: "Receipt scan"
        case .recurring: "Recurring"
        }
    }
}
