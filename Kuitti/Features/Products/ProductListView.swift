import SwiftData
import SwiftUI

struct ProductListView: View {
    @Query private var products: [Product]
    @State private var searchText = ""
    @State private var showScanner = false

    var body: some View {
        Group {
            if products.isEmpty {
                EmptyStateView(
                    systemImage: "basket",
                    title: "No Products Yet",
                    message: "Products build up automatically as you save scanned receipts."
                )
            } else if visibleProducts.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(visibleProducts) { product in
                    NavigationLink {
                        ProductDetailView(product: product)
                    } label: {
                        ProductRow(product: product)
                    }
                }
            }
        }
        .navigationTitle("Products")
        .searchable(text: $searchText, prompt: "Search products")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            BarcodeScanScreen()
        }
    }

    // Sorted in memory: SQL ordering of optional dates can't guarantee nil-last, and the
    // search filter is in-memory anyway (~1-2k rows max).
    private var visibleProducts: [Product] {
        let sorted = products.sorted { a, b in
            switch (a.lastPurchasedAt, b.lastPurchasedAt) {
            case let (l?, r?): l > r
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.canonicalName.localizedStandardCompare(b.canonicalName) == .orderedAscending
            }
        }
        let key = TextNormalizer.key(searchText)
        guard !key.isEmpty else { return sorted }
        return sorted.filter { TextNormalizer.key($0.canonicalName).contains(key) }
    }
}

private struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.canonicalName)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let trend {
                Image(systemName: trend.systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(trend.color)
                    .accessibilityLabel(trend.label)
            }
        }
    }

    private var subtitle: String {
        guard let price = product.lastUnitPrice else { return "No purchases yet" }
        var text = "last " + unitPriceText(price, unit: product.defaultUnit)
        if let store = product.lastStoreName, !store.isEmpty {
            text += " at \(store)"
        }
        text += " · \(product.purchaseCount)×"
        return text
    }

    // Red/green here is data semantics (paying more vs. less), not a warning state.
    private var trend: (systemImage: String, color: Color, label: String)? {
        let prices = (product.lineItems ?? [])
            .filter { !$0.isDiscountOrDeposit && $0.unitPrice > 0 }
            .sorted { $0.purchaseDate > $1.purchaseDate }
            .prefix(2)
            .map(\.unitPrice)
        guard prices.count == 2 else { return nil }
        let delta = prices[0] - prices[1]
        if abs(delta) < 0.005 {
            return ("arrow.right", Color.secondary, "Price unchanged")
        }
        return delta > 0
            ? ("arrow.up.right", Color.red, "Price went up")
            : ("arrow.down.right", Color.green, "Price went down")
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
