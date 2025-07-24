import SwiftUI

/// Displays an image document and supports basic pinch and drag gestures to zoom
/// and pan the image.  The image is loaded lazily on appearance.
struct ImageDocumentView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    var body: some View {
        Group {
            if let image = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = value }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in offset = value.translation }
                        )
                }
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Button("Reset") {
                                withAnimation {
                                    scale = 1.0
                                    offset = .zero
                                }
                            }
                            Spacer()
                            Button("Fit") {
                                withAnimation { scale = 1.0; offset = .zero }
                            }
                        }
                    }
                }
            } else {
                ProgressView("Loading Image...")
                    .onAppear { loadImage() }
            }
        }
    }
    private func loadImage() {
        if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
            self.image = uiImage
        }
    }
}