import SwiftUI

/// Center tab root: entry points for the three capture flows. Only receipt scanning is
/// gated on the Gemini key — barcode lookup and manual entry work without it.
struct ScanHubView: View {
    @State private var hasAPIKey = KeychainStore.hasAPIKey
    @State private var showingKeyEntry = false
    @State private var showingReceiptScan = false
    @State private var showingBarcodeScan = false
    @State private var showingManualEntry = false

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
