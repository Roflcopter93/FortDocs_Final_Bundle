import SwiftUI
import PDFKit

/// Displays a PDF document using PDFKit.  Loading occurs asynchronously
/// on appearance and the PDF is rendered once available.
struct PDFDocumentView: View {
    let url: URL
    @State private var pdfDocument: PDFDocument?
    var body: some View {
        Group {
            if let pdfDocument = pdfDocument {
                PDFKitView(document: pdfDocument)
            } else {
                ProgressView("Loading PDF...")
                    .onAppear { loadPDF() }
            }
        }
    }
    private func loadPDF() {
        pdfDocument = PDFDocument(url: url)
    }
}

/// A simple wrapper to embed PDFKit's PDFView in SwiftUI.
private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}