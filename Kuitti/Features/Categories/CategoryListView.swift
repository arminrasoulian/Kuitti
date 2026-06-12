import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Environment(\.modelContext) private var context
    @State private var editing: Category?
    @State private var showAdd = false
    @State private var pendingDelete: Category?

    var body: some View {
        List {
            section(title: "Expenses", kind: .expense)
            section(title: "Income", kind: .income)
        }
        .navigationTitle("Categories")
        .toolbar {
            Button("Add", systemImage: "plus") { showAdd = true }
        }
        .sheet(isPresented: $showAdd) { CategoryEditView(existing: nil) }
        .sheet(item: $editing) { CategoryEditView(existing: $0) }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deletePending() }
        } message: {
            Text("Transactions and line items in it become uncategorized.")
        }
    }

    @ViewBuilder
    private func section(title: String, kind: CategoryKind) -> some View {
        let items = categories.filter { $0.kind == kind }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { category in
                    Button {
                        editing = category
                    } label: {
                        row(category)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if category.seedIdentifier != SeedCatalog.fallbackCategorySeedID {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDelete = category
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ category: Category) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(iconName: category.iconName, colorHex: category.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                Text(usageText(category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let budget = category.monthlyBudgetMinor {
                Text(Money.euros(budget) + "/kk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usageText(_ category: Category) -> String {
        let count = (category.transactions?.count ?? 0) + (category.lineItems?.count ?? 0)
        return count == 1 ? "1 use" : "\(count) uses"
    }

    private func deletePending() {
        guard let category = pendingDelete else { return }
        // The fallback category must always exist — Gemini decode and deletions rely on it.
        guard category.seedIdentifier != SeedCatalog.fallbackCategorySeedID else { return }
        if let seedID = category.seedIdentifier {
            SeedDataService.recordDismissed(seedIdentifier: seedID)
        }
        context.delete(category)  // .nullify rules leave transactions uncategorized
        try? context.save()
        pendingDelete = nil
    }
}
