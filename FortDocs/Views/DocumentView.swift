import SwiftUI
import QuickLook
import PDFKit

struct DocumentView: View {
    let document: Document
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingRenameAlert = false
    @State private var newDocumentName = ""
    @State private var documentURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading document...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ErrorView(message: error) {
                        loadDocument()
                    }
                } else if let url = documentURL {
                    DocumentContentView(url: url, document: document)
                } else {
                    EmptyDocumentView()
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: { showingRenameAlert = true }) {
                            Label("Rename", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(action: { showingDeleteAlert = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                        .foregroundColor(.red)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            loadDocument()
            newDocumentName = document.title
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = documentURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Rename Document", isPresented: $showingRenameAlert) {
            TextField("Document Name", text: $newDocumentName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                renameDocument()
            }
        }
        .alert("Delete Document", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteDocument()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private func loadDocument() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let url = try document.getDecryptedFileURL()
                await MainActor.run {
                    self.documentURL = url
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func renameDocument() {
        let trimmedName = newDocumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        document.title = trimmedName
        
        do {
            try document.managedObjectContext?.save()
        } catch {
            errorMessage = "Failed to rename document: \(error.localizedDescription)"
        }
    }
    
    private func deleteDocument() {
        guard let context = document.managedObjectContext else { return }
        
        context.delete(document)
        
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = "Failed to delete document: \(error.localizedDescription)"
        }
    }
}

// MARK: - Document Content View

struct DocumentContentView: View {
    let url: URL
    let document: Document
    
    var body: some View {
        Group {
            switch document.documentType {
            case .pdf:
                PDFDocumentView(url: url)
            case .image:
                ImageDocumentView(url: url)
            case .text:
                TextDocumentView(url: url)
            case .unknown:
                QuickLookView(url: url)
            }
        }
    }
}

// MARK: - PDF Document View

struct PDFDocumentView: View {
    let url: URL
    @State private var pdfDocument: PDFDocument?
    
    var body: some View {
        Group {
            if let pdfDocument = pdfDocument {
                PDFKitView(document: pdfDocument)
            } else {
                ProgressView("Loading PDF...")
                    .onAppear {
                        loadPDF()
                    }
            }
        }
    }
    
    private func loadPDF() {
        pdfDocument = PDFDocument(url: url)
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

// MARK: - Image Document View

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
                                .onChanged { value in
                                    scale = value
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
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
                            
                            Button("Zoom In") {
                                withAnimation {
                                    scale = min(scale * 1.5, 5.0)
                                }
                            }
                            
                            Button("Zoom Out") {
                                withAnimation {
                                    scale = max(scale / 1.5, 0.5)
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView("Loading image...")
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }
    
    private func loadImage() {
        Task {
            do {
                let data = try Data(contentsOf: url)
                let loadedImage = UIImage(data: data)
                
                await MainActor.run {
                    self.image = loadedImage
                }
            } catch {
                print("Failed to load image: \(error)")
            }
        }
    }
}

// MARK: - Text Document View

struct TextDocumentView: View {
    let url: URL
    @State private var content: String = ""
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading text...")
                    .onAppear {
                        loadText()
                    }
            } else {
                ScrollView {
                    Text(content)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    private func loadText() {
        Task {
            do {
                let textContent = try String(contentsOf: url, encoding: .utf8)
                
                await MainActor.run {
                    self.content = textContent
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.content = "Failed to load text content: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Quick Look View

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        
        init(url: URL) {
            self.url = url
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as QLPreviewItem
        }
    }
}

// MARK: - Supporting Views

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Document Detail View

struct DocumentDetailView: View {
    let document: Document
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Document thumbnail and basic info
                    HStack {
                        if let thumbnail = document.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                        } else {
                            Image(systemName: document.documentType.icon)
                                .font(.system(size: 40))
                                .foregroundColor(document.documentType.color)
                                .frame(width: 80, height: 80)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.title)
                                .font(.headline)
                                .lineLimit(2)
                            
                            Text(document.documentType.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(document.formattedFileSize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Document metadata
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Details")
                            .font(.headline)
                        
                        DetailRow(title: "Created", value: document.createdAt.formatted(date: .abbreviated, time: .shortened))
                        DetailRow(title: "Modified", value: document.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        DetailRow(title: "File Name", value: document.fileName)
                        DetailRow(title: "Type", value: document.mimeType)
                        
                        if let folder = document.folder {
                            DetailRow(title: "Folder", value: folder.name)
                        }
                    }
                    
                    // Tags
                    if !document.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.headline)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                                ForEach(Array(document.tags), id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    
                    // OCR text preview
                    if let ocrText = document.ocrText, !ocrText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Text Content")
                                .font(.headline)
                            
                            Text(ocrText)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .lineLimit(10)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Document Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("View") {
                        // This would open the full document view
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.body)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    // Preview would need a sample document
    Text("Document View Preview")
}

