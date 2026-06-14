import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Center tab root: receipt-input methods grouped together ("Add a receipt") and the other
/// actions below ("More"), so each entry point is self-explanatory. Receipt inputs are gated
/// on the Gemini key; barcode lookup and manual entry work without it.
struct ScanHubView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var hasAPIKey = KeychainStore.hasAPIKey
    @State private var showingKeyEntry = false
    @State private var showingReceiptScan = false
    @State private var showingBarcodeScan = false
    @State private var showingManualEntry = false
    @State private var nudge: ProductSimilarity.Candidate?

    // "Choose from Library" source selection.
    @State private var showingLibrarySource = false
    @State private var showingPhotosPicker = false
    @State private var showingFileImporter = false
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var loadingLibrary = false

    var body: some View {
        List {
            if !hasAPIKey {
                Section {
                    setupBanner
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            Section("Add a receipt") {
                actionRow(title: "Scan Receipt", subtitle: "Use the camera",
                          systemImage: "doc.viewfinder", tint: .accentColor, enabled: hasAPIKey) {
                    showingReceiptScan = true
                }
                actionRow(title: "Choose from Library", subtitle: "Import a photo or PDF",
                          systemImage: "photo.on.rectangle", tint: .accentColor, enabled: hasAPIKey) {
                    showingLibrarySource = true
                }
            }
            Section("More") {
                actionRow(title: "Scan Barcode", subtitle: "Check a product's price history",
                          systemImage: "barcode.viewfinder", tint: .primary) {
                    showingBarcodeScan = true
                }
                actionRow(title: "Add Manually", subtitle: "Enter a transaction by hand",
                          systemImage: "square.and.pencil", tint: .primary) {
                    showingManualEntry = true
                }
            }
            Section {
                if loadingLibrary {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Scanning needs a connection; everything else works offline.")
            }
        }
        .navigationTitle("Scan")
        // The key may have been added (or removed) via Settings while this tab was inactive.
        .onAppear { hasAPIKey = KeychainStore.hasAPIKey }
        .confirmationDialog("Import receipt from", isPresented: $showingLibrarySource, titleVisibility: .visible) {
            Button("Photos") { showingPhotosPicker = true }
            Button("Files") { showingFileImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingPhotosPicker, selection: $pickedItems, maxSelectionCount: 5, matching: .images)
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image, .pdf], allowsMultipleSelection: true) { result in
            handleFiles(result)
        }
        .onChange(of: pickedItems) { _, items in loadPhotos(items) }
        .sheet(isPresented: $showingKeyEntry, onDismiss: { hasAPIKey = KeychainStore.hasAPIKey }) {
            APIKeyEntryView()
        }
        .fullScreenCover(isPresented: $showingReceiptScan) {
            ReceiptImportNavigator()
        }
        .fullScreenCover(isPresented: $showingBarcodeScan) {
            BarcodeScanScreen()
        }
        .sheet(isPresented: $showingManualEntry) {
            TransactionEditView(existing: nil)
        }
        // A receipt save sets pendingNudge once the off-main scan finishes (by which point
        // the capture flow has closed) — surface it as a gentle merge prompt.
        .onChange(of: env.duplicates.pendingNudge?.id) { _, id in
            guard id != nil else { return }
            nudge = env.duplicates.pendingNudge
            env.duplicates.pendingNudge = nil
        }
        .sheet(item: $nudge) { candidate in
            PostScanNudgeView(candidate: candidate)
        }
    }

    private func actionRow(title: LocalizedStringKey, subtitle: LocalizedStringKey,
                           systemImage: String, tint: Color, enabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    /// Photos → images → the shared import coordinator (no confirm; the user chose them).
    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        loadingLibrary = true
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            loadingLibrary = false
            pickedItems = []
            env.receiptImport.request(images: images, needsConfirmation: false)
        }
    }

    /// Files (images or PDFs) → page images → the shared import coordinator. fileImporter
    /// hands back security-scoped URLs, so access must be opened around the read.
    private func handleFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        loadingLibrary = true
        var images: [UIImage] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            images.append(contentsOf: ReceiptFileLoader.images(from: url))
        }
        loadingLibrary = false
        env.receiptImport.request(images: images, needsConfirmation: false)
    }

    private var setupBanner: some View {
        Button {
            showingKeyEntry = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your Gemini API key to scan receipts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Takes a minute — tap to set it up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Shown right after a receipt save when the new product looks like one you already have.
/// Offers an immediate merge (with preview), keep-separate, or dismiss.
private struct PostScanNudgeView: View {
    let candidate: ProductSimilarity.Candidate

    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let a = product(candidate.a), let b = product(candidate.b) {
                content(a: a, b: b)
            } else {
                // A product vanished (e.g. already merged) — nothing to offer.
                Color.clear.task { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }

    private func content(a: Product, b: Product) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("This looks like a product you already have")
                .font(.headline)
                .multilineTextAlignment(.center)
            VStack(spacing: 2) {
                Text(a.nameDisplay.primary).font(.body.weight(.semibold))
                Text("and").font(.caption).foregroundStyle(.secondary)
                Text(b.nameDisplay.primary).font(.body.weight(.semibold))
            }
            Text(candidate.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 12) {
                NavigationLink {
                    MergePreviewView(productA: a, productB: b) { dismiss() }
                } label: {
                    Text("Merge…").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Button("Keep separate") {
                    context.insert(DismissedDuplicatePair(productA: a.uuid, productB: b.uuid))
                    try? context.save()
                    env.duplicates.refresh(context: context)
                    dismiss()
                }
                .buttonStyle(.bordered)
                Button("Not now") { dismiss() }
            }
        }
        .padding()
        .navigationTitle("Possible Duplicate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func product(_ id: UUID) -> Product? {
        let fetch = FetchDescriptor<Product>(predicate: #Predicate { $0.uuid == id })
        return (try? context.fetch(fetch))?.first
    }
}
