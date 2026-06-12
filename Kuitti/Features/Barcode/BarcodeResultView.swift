import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Post-lookup screen. OFF hit: link the barcode to a local product (receipt-born
/// products have no EAN, so the first scan needs this bridge) or create one. OFF miss:
/// create the product manually or via a Gemini package-photo identification.
struct BarcodeResultView: View {
    let ean: String
    var offProduct: OFFProduct?
    var lookupNote: String?

    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env

    @State private var resolvedProduct: Product?
    @State private var candidates: [Product] = []
    @State private var manualName = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var identifyTask: Task<Void, Never>?
    @State private var isIdentifying = false
    @State private var identifyError: String?
    @State private var proposal: ProductProposal?
    @State private var saveError: String?

    var body: some View {
        Group {
            if let resolvedProduct {
                ProductDetailView(product: resolvedProduct)
            } else if let off = offProduct, let offName = off.bestName {
                hitForm(off: off, offName: offName)
            } else {
                notFoundForm
            }
        }
        .sheet(item: $proposal) { proposed in
            ProposalConfirmSheet(proposal: proposed) { name, brand in
                createProduct(named: name, brand: brand)
                proposal = nil
            }
        }
        .alert("Couldn't Save", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .onDisappear { identifyTask?.cancel() }
    }

    // MARK: - OFF hit

    private func hitForm(off: OFFProduct, offName: String) -> some View {
        Form {
            Section("Open Food Facts") {
                LabeledContent("Name", value: offName)
                if let brands = off.brands, !brands.isEmpty {
                    LabeledContent("Brand", value: brands)
                }
                if let quantity = off.quantity, !quantity.isEmpty {
                    LabeledContent("Size", value: quantity)
                }
                LabeledContent("Barcode", value: ean)
            }
            if !candidates.isEmpty {
                Section("Is this one of your products?") {
                    ForEach(candidates) { candidate in
                        Button {
                            adopt(candidate, brand: primaryBrand(off.brands))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.canonicalName)
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
            Section {
                Button("Create New Product", systemImage: "plus") {
                    let product = ProductMatcher(context: context)
                        .findOrCreateProduct(canonicalName: offName, defaultUnit: .piece)
                    adopt(product, brand: primaryBrand(off.brands))
                }
            } footer: {
                Text("Linking saves the barcode, so the next scan opens the price history instantly.")
            }
        }
        .navigationTitle("Product Found")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            candidates = ProductMatcher(context: context)
                .candidates(forOFFName: offName, brand: primaryBrand(off.brands))
                .map(\.product)
        }
    }

    // MARK: - OFF miss / lookup error

    private var notFoundForm: some View {
        Form {
            Section {
                Text("Open Food Facts doesn't know this barcode (\(ean)). Its coverage of Finnish products — especially store brands like Pirkka or Rainbow — is patchy, so this happens a lot.")
                    .font(.callout)
                if let lookupNote {
                    Text(lookupNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Name it yourself") {
                TextField("Product name", text: $manualName)
                Button("Create Product") {
                    createProduct(named: manualName, brand: nil)
                }
                .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Photograph the package", systemImage: "photo.on.rectangle")
                }
                .disabled(isIdentifying)
                if isIdentifying {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Asking Gemini what this is…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let identifyError {
                    Label(identifyError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Pick a clear photo of the package front and Gemini proposes a name.")
            }
        }
        .navigationTitle("Unknown Barcode")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            identify(newItem)
        }
    }

    private func identify(_ item: PhotosPickerItem) {
        identifyTask?.cancel()
        identifyError = nil
        isIdentifying = true
        photoItem = nil // allow re-picking the same photo
        identifyTask = Task {
            defer { isIdentifying = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = ImageProcessor.processProductPhoto(image) else {
                    identifyError = "Couldn't read that photo. Try another one."
                    return
                }
                guard !Task.isCancelled else { return }
                let result = try await env.gemini.identifyProduct(imageData: jpeg, knownProducts: topProductNames())
                guard !Task.isCancelled else { return }
                proposal = ProductProposal(
                    name: result.productName,
                    brand: result.brand ?? "",
                    uncertain: result.confidence == "low"
                )
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                identifyError = AppError(wrapping: error).userMessage
            }
        }
    }

    /// Top-50 known product names give Gemini the chance to reuse an existing canonical name.
    private func topProductNames() -> [String] {
        var fetch = FetchDescriptor<Product>(sortBy: [SortDescriptor(\.purchaseCount, order: .reverse)])
        fetch.fetchLimit = 50
        return ((try? context.fetch(fetch)) ?? []).map(\.canonicalName)
    }

    // MARK: - Persisting

    /// Stamps the scanned EAN (and brand, if missing) onto the chosen product.
    private func adopt(_ product: Product, brand: String?) {
        product.ean = ean
        if product.brand == nil, let brand, !brand.isEmpty {
            product.brand = brand
        }
        product.updatedAt = Date()
        do {
            try context.save()
            resolvedProduct = product
        } catch {
            saveError = AppError(wrapping: error).userMessage
        }
    }

    private func createProduct(named name: String, brand: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let product = ProductMatcher(context: context)
            .findOrCreateProduct(canonicalName: trimmed, defaultUnit: .piece)
        adopt(product, brand: brand)
    }

    /// OFF "brands" is a comma list; the first entry is the actual brand.
    private func primaryBrand(_ brands: String?) -> String? {
        brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    }
}

private struct ProductProposal: Identifiable {
    let id = UUID()
    var name: String
    var brand: String
    var uncertain: Bool
}

private struct ProposalConfirmSheet: View {
    @State private var name: String
    @State private var brand: String
    private let uncertain: Bool
    private let onCreate: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(proposal: ProductProposal, onCreate: @escaping (String, String?) -> Void) {
        _name = State(initialValue: proposal.name)
        _brand = State(initialValue: proposal.brand)
        self.uncertain = proposal.uncertain
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            Form {
                if uncertain {
                    HStack(spacing: 8) {
                        UncertaintyBadge()
                        Text("Gemini wasn't confident — double-check the name.")
                            .font(.footnote)
                    }
                }
                Section("Product") {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }
            }
            .navigationTitle("New Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, brand.isEmpty ? nil : brand)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
