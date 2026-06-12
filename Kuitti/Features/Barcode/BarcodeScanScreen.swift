import SwiftData
import SwiftUI

/// Scan (or type) an EAN → local product history if the barcode is known, otherwise an
/// Open Food Facts lookup feeding BarcodeResultView. Cross-feature contract: presentable
/// with no parameters from anywhere in the app.
struct BarcodeScanScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var env

    @State private var phase: Phase = .scan
    @State private var manualEAN = ""
    @State private var lookupTask: Task<Void, Never>?

    private enum Phase {
        case scan
        case lookingUp(ean: String)
        case localProduct(Product)
        case offResult(ean: String, off: OFFProduct?, note: String?)
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if showsScanAgain {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Scan Again", systemImage: "barcode.viewfinder") { reset() }
                        }
                    }
                }
        }
        .onDisappear { lookupTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scan:
            scanContent
                .navigationTitle("Scan Barcode")
                .navigationBarTitleDisplayMode(.inline)
        case .lookingUp(let ean):
            VStack(spacing: 12) {
                ProgressView()
                Text("Looking up \(ean)…")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
        case .localProduct(let product):
            ProductDetailView(product: product)
        case .offResult(let ean, let off, let note):
            BarcodeResultView(ean: ean, offProduct: off, lookupNote: note)
        }
    }

    @ViewBuilder
    private var scanContent: some View {
        if BarcodeScannerView.isSupported {
            ZStack(alignment: .bottom) {
                BarcodeScannerView { code in
                    handle(code)
                }
                .ignoresSafeArea(edges: .bottom)
                Text("Point the camera at an EAN barcode")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        } else {
            // Simulator / unsupported hardware: type the digits instead.
            Form {
                Section {
                    TextField("EAN-8 or EAN-13", text: $manualEAN)
                        .keyboardType(.numberPad)
                    Button("Look Up") { handle(manualEAN) }
                        .disabled(!isValidEAN(manualEAN.trimmingCharacters(in: .whitespacesAndNewlines)))
                } footer: {
                    Text("Live scanning isn't available on this device. Type the digits printed under the barcode.")
                }
            }
        }
    }

    private var showsScanAgain: Bool {
        if case .scan = phase { return false }
        return true
    }

    private func reset() {
        lookupTask?.cancel()
        manualEAN = ""
        phase = .scan
    }

    private func handle(_ rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEAN(code) else { return }

        let fetch = FetchDescriptor<Product>(predicate: #Predicate { $0.ean == code })
        if let existing = (try? context.fetch(fetch))?.first {
            phase = .localProduct(existing)
            return
        }

        phase = .lookingUp(ean: code)
        lookupTask?.cancel()
        lookupTask = Task {
            do {
                let off = try await env.off.product(forBarcode: code)
                guard !Task.isCancelled else { return }
                phase = .offResult(ean: code, off: off, note: nil)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                // Lookup errors land in the same not-found flow, with the reason attached.
                phase = .offResult(ean: code, off: nil, note: AppError(wrapping: error).userMessage)
            }
        }
    }

    private func isValidEAN(_ code: String) -> Bool {
        (code.count == 8 || code.count == 13) && code.allSatisfy(\.isNumber)
    }
}
