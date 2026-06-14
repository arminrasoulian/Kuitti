import SwiftData
import SwiftUI

/// A barcode scanned but not yet linked, handed to `ProductDetailView` so the user can inspect
/// a candidate product's full history before deciding to link the barcode to it (or go back and
/// create a new product). While it's set, the edit/merge/delete menu is hidden — the only
/// action offered is the link decision.
struct PendingBarcodeLink: Hashable {
    let ean: String
    let brand: String?
    let sizeMismatch: Bool
    let offName: String?
    let offSize: String?
}

/// The in-store "is this a good price?" screen: stats, price trend per chain, and the
/// full purchase timeline for one product.
struct ProductDetailView: View {
    let product: Product
    /// When set, the screen is confirming whether to link a freshly scanned barcode to this
    /// product (the inspect-before-link step). Default nil = ordinary product detail.
    var pendingBarcode: PendingBarcodeLink? = nil

    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showMergeSheet = false
    // Set the instant a merge/delete commits so the body stops reading `product` (which may be
    // the merged-away loser or the just-deleted product) for the frame before this view pops.
    @State private var isMerging = false
    @State private var isDeleting = false
    @State private var deleteBlockedCount: Int?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        if isMerging || isDeleting {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            if let pendingBarcode {
                linkSection(pendingBarcode)
            }
            if product.brand != nil || product.ean != nil || product.nameDisplay.secondary != nil {
                Section {
                    if let original = product.nameDisplay.secondary {
                        LabeledContent("Original name", value: original)
                    }
                    if let brand = product.brand {
                        LabeledContent("Brand", value: brand)
                    }
                    if let ean = product.ean {
                        LabeledContent("Barcode", value: ean)
                    }
                }
            }
            Section {
                HStack(alignment: .top) {
                    StatCell(value: "\(product.purchaseCount)×", label: "Purchases")
                    StatCell(
                        value: product.lastUnitPrice.map { unitPriceText($0, unit: product.defaultUnit) } ?? "—",
                        label: "Last Price"
                    )
                    StatCell(value: product.lastStoreName ?? "—", label: "Last Store")
                }
            }
            Section("Price History") {
                PriceHistoryChart(lineItems: purchases)
            }
            Section("Purchases") {
                if purchases.isEmpty {
                    Text("No purchases recorded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(purchases) { item in
                        PurchaseRow(item: item)
                    }
                }
            }
        }
        .navigationTitle(product.nameDisplay.primary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pendingBarcode == nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit…", systemImage: "pencil") {
                            showEditSheet = true
                        }
                        Button("Merge into another product…", systemImage: "arrow.triangle.merge") {
                            showMergeSheet = true
                        }
                        Divider()
                        Button("Delete Product", systemImage: "trash", role: .destructive) {
                            attemptDelete()
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ProductEditView(product: product)
        }
        .sheet(isPresented: $showMergeSheet) {
            MergeTargetPicker(current: product) {
                // Merge committed inside the picker's preview step — tear everything down.
                showMergeSheet = false
                isMerging = true
                dismiss()
            }
        }
        .alert("Can't Delete Product", isPresented: deleteBlockedBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            let count = deleteBlockedCount ?? 0
            Text("\(count) purchase\(count == 1 ? "" : "s") reference this product. Remove or reassign those line items first.")
        }
        .confirmationDialog("Delete this product?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes “\(product.nameDisplay.primary)” and its barcode and learned aliases. This can't be undone.")
        }
        .alert("Something Went Wrong", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var purchases: [LineItem] {
        (product.lineItems ?? []).sorted { $0.purchaseDate > $1.purchaseDate }
    }

    // MARK: - Barcode link (inspect-before-link)

    @ViewBuilder
    private func linkSection(_ pending: PendingBarcodeLink) -> some View {
        Section {
            if product.ean == pending.ean {
                Label("Barcode linked", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                if pending.sizeMismatch {
                    Label(sizeWarning(pending), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let offName = pending.offName {
                    LabeledContent("Scanned", value: offName)
                }
                LabeledContent("Barcode", value: pending.ean)
                if let existing = product.ean {
                    Text("This product already has barcode \(existing). Linking will replace it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    linkBarcode(pending)
                } label: {
                    Label(product.ean == nil ? "Link Barcode to This Product" : "Replace Barcode",
                          systemImage: "barcode.viewfinder")
                }
            }
        } header: {
            Text("Scanned Barcode")
        } footer: {
            if product.ean != pending.ean {
                Text("Check the purchase history below — make sure this is the same item (brand and size) you scanned.")
            }
        }
    }

    private func sizeWarning(_ pending: PendingBarcodeLink) -> String {
        if let offSize = pending.offSize {
            return "The scanned size (\(offSize)) looks different from this product's size. Check the history below before linking."
        }
        return "The scanned size looks different from this product's size. Check the history below before linking."
    }

    private func linkBarcode(_ pending: PendingBarcodeLink) {
        do {
            try TransactionEditor(context: context).linkBarcode(pending.ean, brand: pending.brand, to: product)
            env.duplicates.refresh(context: context)
        } catch {
            errorMessage = AppError(wrapping: error).userMessage
        }
    }

    // MARK: - Delete

    private func attemptDelete() {
        let count = (product.lineItems ?? []).count
        if count > 0 {
            deleteBlockedCount = count
        } else {
            showDeleteConfirm = true
        }
    }

    private func performDelete() {
        // Stop the body from dereferencing the product in the frame before this view pops.
        isDeleting = true
        do {
            if try TransactionEditor(context: context).deleteProduct(product) {
                env.duplicates.refresh(context: context)
                dismiss()
            } else {
                // Became referenced between the check and now (shouldn't happen) — recover.
                isDeleting = false
                deleteBlockedCount = (product.lineItems ?? []).count
            }
        } catch {
            isDeleting = false
            errorMessage = AppError(wrapping: error).userMessage
        }
    }

    private var deleteBlockedBinding: Binding<Bool> {
        Binding(get: { deleteBlockedCount != nil }, set: { if !$0 { deleteBlockedCount = nil } })
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PurchaseRow: View {
    let item: LineItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.purchaseDate, format: .dateTime.day().month().year())
                    if item.quantityIsUncertain {
                        UncertaintyBadge()
                    }
                }
                Text(storeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(minor: item.lineTotalMinor)
                Text("\(quantityText) · \(unitPriceText(item.unitPrice, unit: item.unit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storeName: String {
        let name = item.transaction?.store?.name ?? item.transaction?.payee ?? ""
        return name.isEmpty ? "Unknown store" : name
    }

    private var quantityText: String {
        "\(item.quantity.formatted(.number.precision(.fractionLength(0...3)))) \(unitAbbreviation(item.unit))"
    }
}

private struct MergeTargetPicker: View {
    let current: Product
    let onMerged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var products: [Product]
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Other Products",
                        systemImage: "basket",
                        description: Text("There's nothing to merge into yet.")
                    )
                } else {
                    List(candidates) { candidate in
                        NavigationLink {
                            // current is the loser by default ("merge THIS into another");
                            // the preview still lets the user flip which one survives.
                            MergePreviewView(productA: current, productB: candidate,
                                             defaultSurvivor: candidate, onMerged: onMerged)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.nameDisplay.primary)
                                    .foregroundStyle(.primary)
                                if candidate.purchaseCount > 0 {
                                    Text("\(candidate.purchaseCount)× purchased")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Merge Into")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search products")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var candidates: [Product] {
        let others = products
            .filter { $0.persistentModelID != current.persistentModelID }
            .sorted { $0.canonicalName.localizedStandardCompare($1.canonicalName) == .orderedAscending }
        let key = TextNormalizer.key(searchText)
        guard !key.isEmpty else { return others }
        return others.filter {
            TextNormalizer.key($0.canonicalName).contains(key)
                || TextNormalizer.key($0.translatedName).contains(key)
        }
    }
}

fileprivate func unitPriceText(_ eurosPerUnit: Double, unit: UnitKind) -> String {
    let amount = Decimal(eurosPerUnit).formatted(.currency(code: "EUR").precision(.fractionLength(2...3)))
    return "\(amount)/\(unitAbbreviation(unit))"
}

fileprivate func unitAbbreviation(_ unit: UnitKind) -> String {
    switch unit {
    case .piece: "pc"
    case .kilogram: "kg"
    case .litre: "l"
    case .other: "unit"
    }
}
