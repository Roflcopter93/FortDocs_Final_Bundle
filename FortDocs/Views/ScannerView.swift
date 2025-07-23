import SwiftUI
import VisionKit

struct ScannerView: View {
    let folder: Folder?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var documentScanner = DocumentScanner.shared
    @StateObject private var cryptoVault = CryptoVault.shared
    @EnvironmentObject private var folderStore: FolderStore
    
    @State private var showingDocumentScanner = false
    @State private var showingImagePicker = false
    @State private var showingFilePicker = false
    @State private var showingProcessingResults = false
    @State private var processedDocuments: [ProcessedDocument] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    
    init(folder: Folder? = nil) {
        self.folder = folder
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if documentScanner.isProcessing {
                    ProcessingView(progress: documentScanner.processingProgress)
                } else {
                    ScannerContentView(
                        folder: folder,
                        onScanWithCamera: { showingDocumentScanner = true },
                        onImportFromPhotos: { showingImagePicker = true },
                        onImportFiles: { showingFilePicker = true }
                    )
                }
            }
            .navigationTitle("Scan Documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(documentScanner.isProcessing)
                }
            }
        }
        .sheet(isPresented: $showingDocumentScanner) {
            DocumentScannerView { images in
                processImages(images)
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerView { images in
                processImages(images)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .image, .text],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingProcessingResults) {
            ProcessingResultsView(
                processedDocuments: processedDocuments,
                targetFolder: folder
            ) { savedDocuments in
                handleDocumentsSaved(savedDocuments)
            }
        }
        .alert("Processing Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func processImages(_ images: [UIImage]) {
        documentScanner.processScannedImages(images) { result in
            switch result {
            case .success(let processed):
                processedDocuments = processed
                showingProcessingResults = true
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await importFiles(urls)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func importFiles(_ urls: [URL]) async {
        var images: [UIImage] = []
        
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                
                if let image = UIImage(data: data) {
                    images.append(image)
                } else if url.pathExtension.lowercased() == "pdf" {
                    // Convert PDF to images
                    if let pdfImages = await convertPDFToImages(data) {
                        images.append(contentsOf: pdfImages)
                    }
                }
            } catch {
                print("Failed to import file: \(error)")
            }
        }
        
        if !images.isEmpty {
            await MainActor.run {
                processImages(images)
            }
        }
    }
    
    private func convertPDFToImages(_ pdfData: Data) async -> [UIImage]? {
        // This would implement PDF to image conversion
        // For now, return nil as placeholder
        return nil
    }
    
    private func handleDocumentsSaved(_ documents: [Document]) {
        dismiss()
    }
}

// MARK: - Scanner Content View

struct ScannerContentView: View {
    let folder: Folder?
    let onScanWithCamera: () -> Void
    let onImportFromPhotos: () -> Void
    let onImportFiles: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Scan Documents")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Capture documents with your camera or import existing files")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Scan options
                VStack(spacing: 16) {
                    ScanOptionButton(
                        title: "Scan with Camera",
                        subtitle: "Use document scanner with OCR",
                        icon: "camera.fill",
                        color: .blue,
                        action: onScanWithCamera
                    )
                    
                    ScanOptionButton(
                        title: "Import from Photos",
                        subtitle: "Choose existing images",
                        icon: "photo.fill",
                        color: .green,
                        action: onImportFromPhotos
                    )
                    
                    ScanOptionButton(
                        title: "Import Files",
                        subtitle: "PDF, images, and documents",
                        icon: "doc.badge.plus",
                        color: .orange,
                        action: onImportFiles
                    )
                }
                .padding(.horizontal)
                
                // Target folder info
                if let folder = folder {
                    VStack(spacing: 8) {
                        Text("Saving to:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Image(systemName: folder.icon)
                                .foregroundColor(folder.color)
                            Text(folder.name)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(folder.color.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                // Features info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Features")
                        .font(.headline)
                    
                    FeatureRow(
                        icon: "text.viewfinder",
                        title: "OCR Text Recognition",
                        description: "Extract text from documents automatically"
                    )
                    
                    FeatureRow(
                        icon: "doc.text.magnifyingglass",
                        title: "Smart Classification",
                        description: "Automatically detect document types"
                    )
                    
                    FeatureRow(
                        icon: "wand.and.rays",
                        title: "Image Enhancement",
                        description: "Improve quality with perspective correction"
                    )
                    
                    FeatureRow(
                        icon: "lock.shield",
                        title: "Secure Storage",
                        description: "Military-grade encryption protection"
                    )
                }
                .padding(.horizontal)
                
                Spacer(minLength: 50)
            }
            .padding()
        }
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                // Animated processing icon
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 8)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)
                    
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                }
                
                VStack(spacing: 8) {
                    Text("Processing Documents")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Enhancing images and extracting text...")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("\(Int(progress * 100))% Complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Processing Results View

struct ProcessingResultsView: View {
    let processedDocuments: [ProcessedDocument]
    let targetFolder: Folder?
    let onSave: ([Document]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var folderStore: FolderStore
    @StateObject private var cryptoVault = CryptoVault.shared
    
    @State private var editableDocuments: [EditableDocument] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isSaving {
                    SavingView()
                } else {
                    DocumentResultsList(
                        documents: $editableDocuments,
                        folderStore: folderStore
                    )
                }
            }
            .navigationTitle("Review Documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save All") {
                        saveDocuments()
                    }
                    .disabled(isSaving || editableDocuments.isEmpty)
                }
            }
        }
        .onAppear {
            setupEditableDocuments()
        }
        .alert("Save Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Failed to save documents")
        }
    }
    
    private func setupEditableDocuments() {
        editableDocuments = processedDocuments.map { processed in
            EditableDocument(
                id: processed.id,
                title: processed.classification.suggestedTitle,
                selectedFolder: targetFolder ?? folderStore.getDefaultFolder(named: processed.classification.suggestedFolder),
                processedDocument: processed
            )
        }
    }
    
    private func saveDocuments() {
        isSaving = true
        
        Task {
            do {
                var savedDocuments: [Document] = []
                
                for editableDoc in editableDocuments {
                    let document = try await saveDocument(editableDoc)
                    savedDocuments.append(document)
                }
                
                await MainActor.run {
                    isSaving = false
                    onSave(savedDocuments)
                    dismiss()
                }
                
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func saveDocument(_ editableDoc: EditableDocument) async throws -> Document {
        let processed = editableDoc.processedDocument
        
        // Create document entity
        let document = Document(context: viewContext)
        document.id = processed.id
        document.title = editableDoc.title
        document.fileName = "\(processed.id.uuidString).jpg"
        document.mimeType = "image/jpeg"
        document.createdAt = Date()
        document.modifiedAt = Date()
        document.ocrText = processed.ocrResult.text
        document.folder = editableDoc.selectedFolder
        
        // Save image to secure storage
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsURL.appendingPathComponent(document.fileName)
        
        // Convert image to JPEG data
        guard let imageData = processed.enhancedImage.jpegData(compressionQuality: 0.8) else {
            throw DocumentSaveError.imageConversionFailed
        }
        
        // Write to temporary location first
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try imageData.write(to: tempURL)
        
        // Encrypt and move to final location
        try cryptoVault.encryptDocument(at: tempURL, to: imageURL)
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)
        
        // Set file size
        document.fileSize = Int64(imageData.count)
        document.fileURL = imageURL
        
        // Save context
        try viewContext.save()
        
        return document
    }
}

// MARK: - Supporting Views and Types

struct EditableDocument {
    let id: UUID
    var title: String
    var selectedFolder: Folder?
    let processedDocument: ProcessedDocument
}

struct DocumentResultsList: View {
    @Binding var documents: [EditableDocument]
    let folderStore: FolderStore
    
    var body: some View {
        List {
            ForEach(documents.indices, id: \.self) { index in
                DocumentResultRow(
                    document: $documents[index],
                    availableFolders: folderStore.getAllFolders()
                )
            }
        }
    }
}

struct DocumentResultRow: View {
    @Binding var document: EditableDocument
    let availableFolders: [Folder]
    
    @State private var showingTitleEditor = false
    @State private var showingFolderPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Document preview
            HStack(spacing: 12) {
                if let thumbnail = document.processedDocument.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "doc.fill")
                                .foregroundColor(.gray)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Button(document.title) {
                        showingTitleEditor = true
                    }
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    
                    Text("Confidence: \(Int(document.processedDocument.ocrResult.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(document.processedDocument.classification.type.defaultFolderName)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
            }
            
            // Folder selection
            Button(action: { showingFolderPicker = true }) {
                HStack {
                    Image(systemName: document.selectedFolder?.icon ?? "folder.fill")
                        .foregroundColor(document.selectedFolder?.color ?? .blue)
                    
                    Text(document.selectedFolder?.name ?? "Select Folder")
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            // OCR text preview
            if !document.processedDocument.ocrResult.text.isEmpty {
                Text(document.processedDocument.ocrResult.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .alert("Edit Title", isPresented: $showingTitleEditor) {
            TextField("Document Title", text: $document.title)
            Button("Cancel", role: .cancel) { }
            Button("Save") { }
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView(
                selectedFolder: $document.selectedFolder,
                availableFolders: availableFolders
            )
        }
    }
}

struct FolderPickerView: View {
    @Binding var selectedFolder: Folder?
    let availableFolders: [Folder]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(availableFolders, id: \.id) { folder in
                    Button(action: {
                        selectedFolder = folder
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: folder.icon)
                                .foregroundColor(folder.color)
                            
                            Text(folder.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SavingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Saving Documents...")
                .font(.headline)
            
            Text("Encrypting and storing securely")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

enum DocumentSaveError: LocalizedError {
    case imageConversionFailed
    case encryptionFailed
    case contextSaveFailed
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to JPEG format"
        case .encryptionFailed:
            return "Failed to encrypt document"
        case .contextSaveFailed:
            return "Failed to save document to database"
        }
    }
}

// MARK: - Document Scanner View (Updated)

struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: ([UIImage]) -> Void
        
        init(completion: @escaping ([UIImage]) -> Void) {
            self.completion = completion
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            
            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                images.append(image)
            }
            
            completion(images)
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }
        
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("Document scanner failed: \(error)")
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Image Picker View (Updated)

struct ImagePickerView: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: ([UIImage]) -> Void
        
        init(completion: @escaping ([UIImage]) -> Void) {
            self.completion = completion
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                completion([image])
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    ScannerView()
        .environmentObject(FolderStore())
}

