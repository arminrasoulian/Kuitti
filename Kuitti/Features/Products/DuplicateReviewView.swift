import SwiftData
import SwiftUI

/// Lists the duplicate-product suggestions from `DuplicateScanner`, split into confident
/// "Duplicates" and "Possible duplicates". Tap a pair to merge (with preview); swipe to
/// "Keep separate", which is remembered so the pair never reappears.
struct DuplicateReviewView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var products: [Product]

    @State private var selection: PairSelection?

    var body: some View {
        Group {
            if resolved.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "No Duplicates",
                    message: "Kuitti didn't find any products that look like the same thing."
                )
            } else {
                List {
                    section("Duplicates", items: resolved.filter { $0.candidate.confidence == .high })
                    section("Possible duplicates", items: resolved.filter { $0.candidate.confidence == .medium })
                }
            }
        }
        .navigationTitle("Review Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selection) { pair in
            NavigationStack {
                MergePreviewView(productA: pair.a, productB: pair.b) { selection = nil }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [PairSelection]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    Button { selection = item } label: { row(item) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Keep separate") { keepSeparate(item) }
                                .tint(.gray)
                        }
                }
            }
        }
    }

    private func row(_ item: PairSelection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.candidate.confidence == .high ? "doc.on.doc.fill" : "doc.on.doc")
                .foregroundStyle(item.candidate.confidence == .high ? Color.accentColor : .yellow)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                productLine(item.a)
                productLine(item.b)
                Text(item.candidate.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func productLine(_ product: Product) -> some View {
        HStack(spacing: 6) {
            Text(product.nameDisplay.primary)
                .font(.subheadline)
                .lineLimit(1)
            if let original = product.nameDisplay.secondary {
                Text(original)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(product.purchaseCount)×")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Data

    /// Candidates resolved to live products (dropping any whose product was since deleted).
    private var resolved: [PairSelection] {
        let byID = Dictionary(products.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        return env.duplicates.candidates.compactMap { candidate in
            guard let a = byID[candidate.a], let b = byID[candidate.b] else { return nil }
            return PairSelection(candidate: candidate, a: a, b: b)
        }
    }

    private func keepSeparate(_ item: PairSelection) {
        context.insert(DismissedDuplicatePair(productA: item.a.uuid, productB: item.b.uuid))
        try? context.save()
        env.duplicates.refresh(context: context)
    }
}

private struct PairSelection: Identifiable {
    let candidate: ProductSimilarity.Candidate
    let a: Product
    let b: Product
    var id: String { candidate.id }
}
