import SwiftUI
import UIKit

/// Confirmation shown when a receipt is shared in from another app (or Files), before it's
/// parsed. The user explicitly opted to import, so this is a light "is this the right file?"
/// check with a thumbnail — not a full editor.
struct ImportConfirmView: View {
    let images: [UIImage]
    var onImport: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let first = images.first {
                    Image(uiImage: first)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 4)
                }
                Text(images.count > 1 ? "Import these \(images.count) pages as a receipt?" : "Import this as a receipt?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Spacer()
                VStack(spacing: 12) {
                    Button {
                        onImport()
                    } label: {
                        Text("Import Receipt").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Shared Receipt")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
