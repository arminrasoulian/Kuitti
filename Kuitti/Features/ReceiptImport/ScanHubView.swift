import SwiftData
import SwiftUI

/// Center tab root: entry points for the three capture flows. Only receipt scanning is
/// gated on the Gemini key — barcode lookup and manual entry work without it.
struct ScanHubView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var hasAPIKey = KeychainStore.hasAPIKey
    @State private var showingKeyEntry = false
    @State private var showingReceiptScan = false
    @State private var showingBarcodeScan = false
    @State private var showingManualEntry = false
    @State private var nudge: ProductSimilarity.Candidate?

    var body: some View {
        VStack(spacing: 0) {
            if !hasAPIKey {
                setupBanner
                    .padding(.top, 8)
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    showingReceiptScan = true
                } label: {
                    Label("Scan Receipt", systemImage: "doc.viewfinder")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasAPIKey)

                Button {
                    showingBarcodeScan = true
                } label: {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Button("Add manually") {
                    showingManualEntry = true
                }
                .padding(.top, 4)
            }
            Spacer()
            Text("Scanning needs a connection; everything else works offline.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .navigationTitle("Scan")
        // The key may have been added (or removed) via Settings while this tab was inactive.
        .onAppear { hasAPIKey = KeychainStore.hasAPIKey }
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
