import PhotosUI
import SwiftUI
import UIKit

/// The camera step of the scan flow. When the document camera is available it fills the
/// screen with no overlaid controls (overlaying SwiftUI on VisionKit's own chrome collided
/// with its shutter/filter row) — the "Choose from Library" entry now lives on the Scan hub.
/// The photo picker only appears in the camera-unavailable fallback (simulator / old iPad),
/// where there's no camera to overlap.
struct ReceiptCaptureView: View {
    let flow: ReceiptImportFlow

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var loadingPicked = false

    var body: some View {
        Group {
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
                } actions: {
                    PhotosPicker(selection: $pickedItems, maxSelectionCount: 5, matching: .images) {
                        if loadingPicked {
                            ProgressView()
                        } else {
                            Text("Choose from Library")
                        }
                    }
                    .disabled(loadingPicked)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
