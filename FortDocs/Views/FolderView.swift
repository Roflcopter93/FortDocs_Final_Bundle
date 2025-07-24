import SwiftUI
import CoreData

/// High level view displaying the folder hierarchy on the left and the contents of the
/// selected folder on the right.  This implementation fixes a UI glitch where
/// deleted folders would remain visible after rapid creation/deletion by
/// performing deletions on the context queue and immediately processing
/// pending changes.  It also introduces a simple multi‑selection mode for
/// documents allowing batch deletion and export.
struct FolderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var folderStore: FolderStore
    @StateObject private var viewModel = FolderViewModel()
    @State private var selectedFolder: Folder?
    @State private var showingAddFolder = false

    var body: some View {
        NavigationSplitView {
            FolderSidebarView(selectedFolder: $selectedFolder)
                .navigationTitle("Folders")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingAddFolder = true }) {
                            Image(systemName: "folder.badge.plus")
                        }
                    }
                }
        } detail: {
            if let folder = selectedFolder {
                FolderContentView(folder: folder)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("Select a folder to view documents")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Choose a folder from the sidebar to see its contents")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
        .sheet(isPresented: $showingAddFolder) {
            AddFolderView(parentFolder: selectedFolder)
        }
        .onAppear {
            viewModel.loadRootFolders(context: viewContext)
            if selectedFolder == nil {
                selectedFolder = folderStore.getDefaultFolder(named: "Documents")
            }
        }
    }
}

// MARK: - Folder Sidebar

/// Displays the root folder hierarchy in a list.  Deletions are performed on
/// the context's queue without animation to avoid visual glitches.  After
/// deleting, pending changes are processed to refresh the fetch request.
private struct FolderSidebarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: Folder.fetchRootFolders()) private var rootFolders: FetchedResults<Folder>
    @Binding var selectedFolder: Folder?

    var body: some View {
        List(selection: $selectedFolder) {
            ForEach(rootFolders, id: \.id) { folder in
                FolderRowView(folder: folder, selectedFolder: $selectedFolder)
            }
            .onDelete(perform: deleteFolders)
        }
        .listStyle(SidebarListStyle())
    }

    /// Delete folders at the given offsets.  This implementation avoids using
    /// `withAnimation` and instead performs deletion on the managed object
    /// context's queue, saving and processing pending changes immediately.
    private func deleteFolders(at offsets: IndexSet) {
        let foldersToDelete = offsets.map { rootFolders[$0] }
        viewContext.perform {
            for folder in foldersToDelete where !folder.isDefault {
                viewContext.delete(folder)
            }
            do {
                try viewContext.save()
                // Immediately process pending changes so the fetch request updates
                viewContext.processPendingChanges()
            } catch {
                print("Failed to delete folder: \(error)")
            }
        }
    }
}

// MARK: - Folder Row

/// A single row in the folder hierarchy.  Expands to display subfolders and
/// updates the selection when tapped.
private struct FolderRowView: View {
    let folder: Folder
    @Binding var selectedFolder: Folder?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { if !folder.subfolders.isEmpty { isExpanded.toggle() } }) {
                    Image(systemName: folder.subfolders.isEmpty ? "circle" : (isExpanded ? "chevron.down" : "chevron.right"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(PlainButtonStyle())
                Image(systemName: folder.icon)
                    .foregroundColor(folder.color)
                    .frame(width: 20)
                Text(folder.name)
                    .font(.body)
                Spacer()
                if folder.documentCount > 0 {
                    Text("\(folder.documentCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedFolder = folder }
            if isExpanded {
                ForEach(folder.sortedSubfolders(), id: \.id) { subfolder in
                    FolderRowView(folder: subfolder, selectedFolder: $selectedFolder)
                        .padding(.leading, 20)
                }
            }
        }
    }
}

// MARK: - Folder Content

/// Displays the contents of a folder.  Users can toggle into a selection mode
/// which allows multiple documents to be selected and batch deleted or exported.
private struct FolderContentView: View {
    let folder: Folder
    @Environment(\.managedObjectContext) private var viewContext
    @State private var documents: [Document] = []
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedDocumentIDs: Set<UUID> = []

    private var filteredDocuments: [Document] {
        if searchText.isEmpty { return documents } else {
            return documents.filter { $0.searchableContent().localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(folder.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("\(folder.documentCount) documents")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Toggle selection mode
                Button(action: { isSelecting.toggle(); if !isSelecting { selectedDocumentIDs.removeAll() } }) {
                    Text(isSelecting ? "Cancel" : "Select")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search documents...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            // Document grid
            if filteredDocuments.isEmpty {
                EmptyFolderView(folder: folder, hasSearchFilter: !searchText.isEmpty)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                        ForEach(filteredDocuments, id: \.id) { document in
                            DocumentCardView(document: document)
                                .overlay(
                                    Group {
                                        if isSelecting {
                                            // Show a selection indicator when in select mode
                                            Image(systemName: selectedDocumentIDs.contains(document.id ?? UUID()) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(.blue)
                                                .padding(6)
                                                .background(Color.white.opacity(0.8))
                                                .clipShape(Circle())
                                                .offset(x: 6, y: -6)
                                        }
                                    }, alignment: .topTrailing
                                )
                                .onTapGesture {
                                    if isSelecting {
                                        // Toggle selection
                                        if let id = document.id {
                                            if selectedDocumentIDs.contains(id) {
                                                selectedDocumentIDs.remove(id)
                                            } else {
                                                selectedDocumentIDs.insert(id)
                                            }
                                        }
                                    } else {
                                        // Open document detail
                                        openDocument(document)
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { loadDocuments() }
        .onChange(of: folder) { _ in loadDocuments() }
        .toolbar(isSelecting ? .visible : .hidden, for: .navigationBar) {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: deleteSelected) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedDocumentIDs.isEmpty)
                Spacer()
                Button(action: exportSelected) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(selectedDocumentIDs.isEmpty)
            }
        }
    }

    /// Refresh the list of documents from the folder.
    private func loadDocuments() {
        documents = folder.sortedDocuments()
    }

    /// Open a document by presenting its detail view.  In a full application this
    /// would push a new view onto the navigation stack.
    private func openDocument(_ document: Document) {
        // Implementation would navigate to DocumentView
        // For this simplified example we do nothing
    }

    /// Delete all selected documents using the managed object context.  After
    /// deletion the context is saved and the local list refreshed.
    private func deleteSelected() {
        guard !selectedDocumentIDs.isEmpty else { return }
        viewContext.perform {
            for doc in documents where selectedDocumentIDs.contains(doc.id ?? UUID()) {
                viewContext.delete(doc)
            }
            do {
                try viewContext.save()
                viewContext.processPendingChanges()
                selectedDocumentIDs.removeAll()
                loadDocuments()
            } catch {
                print("Failed to delete documents: \(error)")
            }
        }
    }

    /// Export selected documents.  A real implementation would present a share sheet.
    private func exportSelected() {
        // In a production app this would create a zip or share individual files
        selectedDocumentIDs.removeAll()
    }
}