import SwiftUI

/// Displays a plain text or markdown document by loading its contents from disk.
struct TextDocumentView: View {
    let url: URL
    @State private var text: String = ""
    var body: some View {
        ScrollView {
            Text(text)
                .font(.body)
                .padding()
        }
        .onAppear { loadText() }
    }
    private func loadText() {
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            text = "Unable to load text." + "\n" + error.localizedDescription
        }
    }
}