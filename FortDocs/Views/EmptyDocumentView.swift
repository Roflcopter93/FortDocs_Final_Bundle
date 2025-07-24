import SwiftUI

/// Shown when a document cannot be loaded or is missing.  Presents a simple
/// placeholder graphic and explanation.
struct EmptyDocumentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Document Not Available")
                .font(.title2)
                .fontWeight(.semibold)
            Text("The document could not be loaded.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}