import SwiftData
import SwiftUI

/// The confirm-with-preview step shared by every merge path (manual "Merge into…", the
/// duplicate review screen, and the post-scan nudge). Lets the user pick which product to
/// keep, edit the surviving name, and see what the result will be before committing. Has no
/// NavigationStack of its own — push it or wrap it in one. On success it performs the merge
/// (through TransactionEditor.mergeProducts) and calls `onMerged`; the owner tears down.
struct MergePreviewView: View {
    let productA: Product
    let productB: Product
    var defaultSurvivor: Product? = nil
    var onMerged: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var survivorIsA: Bool
    @State private var nameText: String
    @State private var errorMessage: String?

    init(productA: Product, productB: Product, defaultSurvivor: Product? = nil, onMerged: @escaping () -> Void = {}) {
        self.productA = productA
        self.productB = productB
        self.defaultSurvivor = defaultSurvivor
        self.onMerged = onMerged
        let aWins = defaultSurvivor.map { $0 === productA } ?? (productA.purchaseCount >= productB.purchaseCount)
        _survivorIsA = State(initialValue: aWins)
        _nameText = State(initialValue: (aWins ? productA : productB).canonicalName)
    }

    private var survivor: Product { survivorIsA ? productA : productB }
    private var loser: Product { survivorIsA ? productB : productA }

    var body: some View {
        Form {
            Section("Keep") {
                Picker("Keep", selection: $survivorIsA) {
                    productLabel(productA).tag(true)
                    productLabel(productB).tag(false)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: survivorIsA) { _, isA in
                    nameText = (isA ? productA : productB).canonicalName
                }
            }
            Section("Surviving name") {
                TextField("Name", text: $nameText)
            }
            Section {
                LabeledContent("Combined purchases", value: "\(productA.purchaseCount + productB.purchaseCount)")
                if let brand = survivor.brand ?? loser.brand {
                    LabeledContent("Brand", value: brand)
                }
                if let ean = survivor.ean ?? loser.ean {
                    LabeledContent("Barcode", value: ean)
                }
            } header: {
                Text("Result")
            } footer: {
                Text("All purchases and price history from “\(loser.nameDisplay.primary)” move under the product you keep. This can't be undone.")
            }
        }
        .navigationTitle("Merge Products")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge", role: .destructive) { merge() }
                    .disabled(nameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert("Couldn't merge", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func productLabel(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(product.nameDisplay.primary)
            Text("\(product.purchaseCount)× purchased")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func merge() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Capture the survivor before merge; renaming keeps both keys in lockstep.
        if !trimmed.isEmpty, trimmed != survivor.canonicalName {
            survivor.canonicalName = trimmed
            survivor.normalizedKey = TextNormalizer.key(trimmed)
        }
        do {
            try TransactionEditor(context: context).mergeProducts(loser: loser, into: survivor)
            env.duplicates.refresh(context: context)
            onMerged()
        } catch {
            errorMessage = AppError(wrapping: error).userMessage
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
