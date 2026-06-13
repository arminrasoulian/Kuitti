import SwiftData
import SwiftUI

/// The in-store "is this a good price?" screen: stats, price trend per chain, and the
/// full purchase timeline for one product.
struct ProductDetailView: View {
    let product: Product

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showMergeSheet = false
    @State private var errorMessage: String?

    var body: some View {
        List {
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename…", systemImage: "pencil") {
                        renameText = product.canonicalName
                        showRenameAlert = true
                    }
                    Button("Merge into another product…", systemImage: "arrow.triangle.merge") {
                        showMergeSheet = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Product", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showMergeSheet) {
            MergeTargetPicker(current: product) { survivor in
                merge(into: survivor)
            }
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

    private func rename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != product.canonicalName else { return }
        product.canonicalName = trimmed
        product.normalizedKey = TextNormalizer.key(trimmed)
        product.updatedAt = Date()
        do {
            try context.save()
        } catch {
            errorMessage = AppError(wrapping: error).userMessage
        }
    }

    private func merge(into survivor: Product) {
        ProductMatcher(context: context).merge(loser: product, into: survivor)
        // merge repoints line items, so the survivor's denormalized stats are stale.
        TransactionEditor(context: context).recomputeStats(for: survivor)
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = AppError(wrapping: error).userMessage
        }
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
    let onPick: (Product) -> Void

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
                        Button {
                            dismiss()
                            onPick(candidate)
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
