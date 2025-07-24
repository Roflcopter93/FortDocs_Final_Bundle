import SwiftUI
import PDFKit
import QuickLook

/// Presents a single document to the user.  This version extracts the various
/// content renderers into separate files and adds a dedicated share button in
/// the toolbar for one‑tap access.  The original overflow menu still
/// contains the share action for discoverability.
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
                    ErrorView(message: error) { loadDocument() }
                } else if let url = documentURL {
                    DocumentContentView(url: url, document: document)
                } else {
                    EmptyDocumentView()
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Leading close button
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                // Direct share button
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(documentURL == nil)
                }
                // Overflow menu with additional actions
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button(action: { showingRenameAlert = true }) {
                            Label("Rename", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive, action: { showingDeleteAlert = true }) {
                            Label("Delete", systemImage: "trash")
                        }
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
            Button("Rename") { renameDocument() }
        }
        .alert("Delete Document", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteDocument() }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    /// Load and decrypt the document, updating state on the main thread.
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

    /// Rename the current document and persist the change.
    private func renameDocument() {
        let trimmed = newDocumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.title = trimmed
        do {
            try document.managedObjectContext?.save()
        } catch {
            errorMessage = "Failed to rename document: \(error.localizedDescription)"
        }
    }

    /// Permanently delete the document from Core Data.
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

// MARK: - Document Content

/// Delegates to the appropriate view based on the document's type.
private struct DocumentContentView: View {
    let url: URL
    let document: Document
    var body: some View {
        switch document.documentType {
        case .pdf: PDFDocumentView(url: url)
        case .image: ImageDocumentView(url: url)
        case .text: TextDocumentView(url: url)
        case .unknown: QuickLookView(url: url)
        }
    }
}
