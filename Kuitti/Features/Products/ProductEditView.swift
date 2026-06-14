import SwiftData
import SwiftUI

/// Full editor for a product's details. The AI parse is sometimes slightly off, so the user
/// can fix the name (the size lives inside the name), the English translation, brand, barcode,
/// and unit. Persists through `TransactionEditor.updateProduct` — the mutation choke point that
/// recomputes the matching keys — then refreshes the duplicate scanner (a rename can create or
/// resolve a duplicate).
struct ProductEditView: View {
    let product: Product

    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var translatedName: String
    @State private var brand: String
    @State private var ean: String
    @State private var unit: UnitKind
    @State private var errorMessage: String?

    init(product: Product) {
        self.product = product
        _name = State(initialValue: product.canonicalName)
        _translatedName = State(initialValue: product.translatedName)
        _brand = State(initialValue: product.brand ?? "")
        _ean = State(initialValue: product.ean ?? "")
        _unit = State(initialValue: product.defaultUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Include the size in the name (e.g. “Pepsi Max 0,5 L”) — Kuitti reads the size from here to tell pack sizes apart.")
                }
                Section {
                    TextField("English name (optional)", text: $translatedName)
                } header: {
                    Text("English name")
                } footer: {
                    Text("Shown when it differs from the name above. Leave empty if the name is already in English.")
                }
                Section("Details") {
                    TextField("Brand (optional)", text: $brand)
                    TextField("Barcode (optional)", text: $ean)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    Picker("Unit", selection: $unit) {
                        Text("Piece").tag(UnitKind.piece)
                        Text("Kilogram").tag(UnitKind.kilogram)
                        Text("Litre").tag(UnitKind.litre)
                        Text("Other").tag(UnitKind.other)
                    }
                }
                if let conflictName = barcodeConflictName {
                    Section {
                        Label("Another product, “\(conflictName)”, already has this barcode. You can merge them from either product's menu.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Couldn't Save", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// Display name of another product that already carries the entered barcode (advisory
    /// only — `ean` is intentionally non-unique; the duplicate scanner funnels the merge).
    private var barcodeConflictName: String? {
        let code = ean.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        let selfID = product.uuid
        let fetch = FetchDescriptor<Product>(predicate: #Predicate { $0.ean == code && $0.uuid != selfID })
        return (try? context.fetch(fetch))?.first?.nameDisplay.primary
    }

    private func save() {
        do {
            try TransactionEditor(context: context).updateProduct(
                product,
                canonicalName: name,
                translatedName: translatedName,
                brand: brand,
                ean: ean,
                defaultUnit: unit
            )
            env.duplicates.refresh(context: context)
            dismiss()
        } catch {
            errorMessage = AppError(wrapping: error).userMessage
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
