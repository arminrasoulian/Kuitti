import SwiftUI

struct ReceiptImageViewer: View {
    let imageData: Data
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = UIImage(data: imageData) {
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .containerRelativeFrame(.horizontal)
                        .scaleEffect(scale, anchor: .center)
                }
                .defaultScrollAnchor(.center)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(steadyScale * value.magnification, 1), 6)
                        }
                        .onEnded { _ in steadyScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation { scale = 1; steadyScale = 1 }
                }
            } else {
                EmptyStateView(systemImage: "photo", title: "No image", message: "The receipt image couldn't be loaded.")
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
    }
}
