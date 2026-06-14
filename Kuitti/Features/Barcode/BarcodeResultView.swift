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
    @State private var candidates: [ProductMatcher.OFFCandidate] = []
    @State private var missChoice: MissChoice?
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
            } else if let missChoice {
                missChooserForm(missChoice)
            } else if let off = offProduct, let offName = off.bestName {
                hitForm(off: off, offName: offName)
            } else {
                notFoundForm
            }
        }
        .sheet(item: $proposal) { proposed in
            ProposalConfirmSheet(proposal: proposed) { name, brand in
                proposal = nil
                attemptCreate(name: name, brand: brand,
                              translatedName: proposed.translatedName, sourceLanguage: proposed.sourceLanguage)
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
            candidateSection(candidates, brand: primaryBrand(off.brands), offName: offName, offSize: off.quantity)
            Section {
                Button("Create New Product", systemImage: "plus") {
                    // OFF names are already in the app language (we request that variant).
                    let product = ProductMatcher(context: context)
                        .findOrCreateProduct(canonicalName: offName, defaultUnit: .piece, sourceLanguage: AppLanguage.current)
                    adopt(product, brand: primaryBrand(off.brands))
                }
            } footer: {
                Text("Tap a product above to inspect it before linking, or create a new one. Linking saves the barcode so the next scan opens its price history instantly.")
            }
        }
        .navigationTitle("Product Found")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            candidates = ProductMatcher(context: context)
                .candidates(forOFFName: offName, brand: primaryBrand(off.brands), offSize: off.quantity)
        }
    }

    /// Shared candidate list (OFF-hit and OFF-miss): each row pushes the product's full detail
    /// with a pending barcode-link decision, so the user inspects price history before linking
    /// instead of committing on tap.
    @ViewBuilder
    private func candidateSection(_ candidates: [ProductMatcher.OFFCandidate],
                                  brand: String?, offName: String?, offSize: String?) -> some View {
        if !candidates.isEmpty {
            Section("Is this one of your products?") {
                ForEach(candidates, id: \.product.uuid) { candidate in
                    NavigationLink {
                        ProductDetailView(
                            product: candidate.product,
                            pendingBarcode: PendingBarcodeLink(
                                ean: ean, brand: brand,
                                sizeMismatch: candidate.sizeMismatch,
                                offName: offName, offSize: offSize
                            )
                        )
                    } label: {
                        CandidateRow(candidate: candidate)
                    }
                }
            }
        }
    }

    // MARK: - OFF miss / lookup error

    private var notFoundForm: some View {
        Form {
            Section {
                Text("Open Food Facts doesn't know this barcode (\(ean)). Its coverage of some products — especially store brands — is limited, so this happens sometimes.")
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
                    attemptCreate(name: manualName, brand: nil)
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
                    translatedName: result.translatedName ?? "",
                    sourceLanguage: result.sourceLanguage ?? "",
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

    // MARK: - OFF miss / manual: similar-products chooser

    /// OFF-miss / manual / photo path: the user supplied a name and we found similar existing
    /// products. Inspect-then-link each (via the pushed detail), or create the new product anyway.
    private func missChooserForm(_ choice: MissChoice) -> some View {
        Form {
            Section {
                Text("Before creating “\(choice.name)”, check whether it's one of these products you already have.")
                    .font(.callout)
            }
            candidateSection(choice.candidates, brand: choice.brand, offName: choice.name, offSize: nil)
            Section {
                Button("Create New Product Anyway", systemImage: "plus") {
                    createProduct(named: choice.name, brand: choice.brand,
                                  translatedName: choice.translatedName, sourceLanguage: choice.sourceLanguage)
                }
            } footer: {
                Text("This saves the barcode on a brand-new product.")
            }
        }
        .navigationTitle("Similar Products")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Persisting

    /// Stamps the scanned EAN (and brand, if missing) onto the chosen product via the
    /// TransactionEditor choke point, then shows its detail. Used by the create-new paths;
    /// candidate links happen inside the pushed ProductDetailView itself.
    private func adopt(_ product: Product, brand: String?) {
        do {
            try TransactionEditor(context: context).linkBarcode(ean, brand: brand, to: product)
            env.duplicates.refresh(context: context)
            resolvedProduct = product
        } catch {
            saveError = AppError(wrapping: error).userMessage
        }
    }

    /// Before creating, check whether a similarly-named product already exists (the AI/OFF name
    /// can collide with one the user already has). If so, let the user inspect-then-link or
    /// create anyway, instead of silently reusing/clobbering an existing product.
    private func attemptCreate(name: String, brand: String?, translatedName: String = "", sourceLanguage: String = "") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let found = ProductMatcher(context: context).candidates(forOFFName: trimmed, brand: brand, offSize: nil)
        if found.isEmpty {
            createProduct(named: trimmed, brand: brand, translatedName: translatedName, sourceLanguage: sourceLanguage)
        } else {
            missChoice = MissChoice(name: trimmed, brand: brand,
                                    translatedName: translatedName, sourceLanguage: sourceLanguage,
                                    candidates: found)
        }
    }

    private func createProduct(named name: String, brand: String?, translatedName: String = "", sourceLanguage: String = "") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let product = ProductMatcher(context: context)
            .findOrCreateProduct(canonicalName: trimmed, defaultUnit: .piece,
                                 translatedName: translatedName, sourceLanguage: sourceLanguage)
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

/// OFF-miss / manual state: a name the user supplied plus the similar existing products found,
/// so the chooser can offer inspect-then-link or create-anyway.
private struct MissChoice {
    var name: String
    var brand: String?
    var translatedName: String
    var sourceLanguage: String
    var candidates: [ProductMatcher.OFFCandidate]
}

/// One existing-product row in the barcode candidate list: name, brand, purchase summary, and
/// a "different size" flag so a multipack is obvious before the user drills in to inspect it.
private struct CandidateRow: View {
    let candidate: ProductMatcher.OFFCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.product.nameDisplay.primary)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if candidate.sizeMismatch {
                Label("Different size", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var subtitle: String? {
        let product = candidate.product
        var parts: [String] = []
        if let brand = product.brand, !brand.isEmpty { parts.append(brand) }
        if product.purchaseCount > 0 {
            var stat = "\(product.purchaseCount)×"
            if let price = product.lastUnitPrice {
                let amount = Decimal(price).formatted(.currency(code: "EUR").precision(.fractionLength(2...3)))
                stat += " · last \(amount)"
            }
            parts.append(stat)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct ProductProposal: Identifiable {
    let id = UUID()
    var name: String
    var brand: String
    var translatedName: String
    var sourceLanguage: String
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
