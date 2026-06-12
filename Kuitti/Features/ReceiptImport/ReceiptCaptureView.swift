import PhotosUI
import SwiftUI
import UIKit

/// Document camera with a photo-library fallback (the camera is unavailable on the
/// simulator and older iPads). Both paths feed the same setCaptured → parse pipeline.
struct ReceiptCaptureView: View {
    let flow: ReceiptImportFlow

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var loadingPicked = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if DocumentCameraView.isSupported {
                DocumentCameraView(
                    onScan: { images in capture(images) },
                    onCancel: { dismiss() }
                )
                .ignoresSafeArea()
            } else {
                ContentUnavailableView {
                    Label("Camera Unavailable", systemImage: "camera.fill")
                } description: {
                    Text("Pick receipt photos from your library instead.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            PhotosPicker(selection: $pickedItems, maxSelectionCount: 5, matching: .images) {
                Group {
                    if loadingPicked {
                        ProgressView()
                    } else {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                            .font(.callout.weight(.medium))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .disabled(loadingPicked)
            // Sits above the document camera's own shutter controls.
            .padding(.bottom, DocumentCameraView.isSupported ? 96 : 24)
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            loadingPicked = true
            Task {
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
                loadingPicked = false
                pickedItems = []
                if !images.isEmpty {
                    capture(images)
                }
            }
        }
    }

    private func capture(_ images: [UIImage]) {
        flow.setCaptured(images: images)
        guard !flow.pages.isEmpty else { return }
        Task { await flow.parse(modelContext: modelContext) }
    }
}
