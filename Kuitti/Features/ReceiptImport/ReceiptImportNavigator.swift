import SwiftUI
import UIKit

/// Hosts the scan → parse → review → save flow inside its own NavigationStack.
/// The flow object is created lazily in .task because @Environment isn't available in init.
struct ReceiptImportNavigator: View {
    /// When set, the flow starts from these images (shared in / picked) and skips the camera.
    var initialImages: [UIImage]? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var flow: ReceiptImportFlow?
    @State private var confirmingCancel = false

    var body: some View {
        NavigationStack {
            Group {
                if let flow {
                    stepView(flow)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(flow?.step == .review ? "Review Receipt" : "Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if flow?.draft != nil {
                            confirmingCancel = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog("Discard this receipt?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .task {
            if flow == nil {
                let flow = ReceiptImportFlow(gemini: env.gemini)
                self.flow = flow
                if let initialImages {
                    await flow.beginImport(images: initialImages, modelContext: modelContext)
                }
            }
        }
    }

    @ViewBuilder
    private func stepView(_ flow: ReceiptImportFlow) -> some View {
        switch flow.step {
        case .capture:
            ReceiptCaptureView(flow: flow)
        case .parsing:
            parsingView(flow)
        case .review:
            ReceiptReviewView(flow: flow)
        case .saving:
            ProgressView("Saving…")
        case .failed(let message, let retryable):
            failurePanel(flow: flow, message: message, retryable: retryable)
        }
    }

    private func parsingView(_ flow: ReceiptImportFlow) -> some View {
        VStack(spacing: 24) {
            ProgressView("Reading receipt…")
            if let data = flow.pages.first, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
            }
        }
        .padding()
    }

    private func failurePanel(flow: ReceiptImportFlow, message: String, retryable: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(message)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                if retryable {
                    Button {
                        Task { await flow.retry(modelContext: modelContext) }
                    } label: {
                        Text("Retry")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    flow.reset()
                } label: {
                    Text("Retake photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                // No special manual-entry routing: dismiss back to the hub, where
                // "Add manually" lives.
                Button {
                    dismiss()
                } label: {
                    Text("Enter manually")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
            .frame(maxWidth: 320)
        }
        .padding()
    }
}
