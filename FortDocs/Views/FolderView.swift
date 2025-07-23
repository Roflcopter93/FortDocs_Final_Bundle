import SwiftUI
import CoreData

struct FolderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var folderStore: FolderStore
    @StateObject private var viewModel = FolderViewModel()
    
    @State private var selectedFolder: Folder?
    @State private var showingAddFolder = false
    @State private var showingDocumentPicker = false
    @State private var showingScanner = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with folder hierarchy
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
            // Main content area
            if let folder = selectedFolder {
                FolderContentView(folder: folder)
            } else {
                // Default view when no folder is selected
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
            selectDefaultFolder()
        }
    }
    
    private func selectDefaultFolder() {
        if selectedFolder == nil {
            selectedFolder = folderStore.getDefaultFolder(named: "Documents")
        }
    }
}

// MARK: - Folder Sidebar View

struct FolderSidebarView: View {
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
    
    private func deleteFolders(offsets: IndexSet) {
        withAnimation {
            offsets.map { rootFolders[$0] }.forEach { folder in
                if !folder.isDefault {
                    viewContext.delete(folder)
                }
            }
            
            do {
                try viewContext.save()
            } catch {
                print("Failed to delete folder: \(error)")
            }
        }
    }
}

// MARK: - Folder Row View

struct FolderRowView: View {
    let folder: Folder
    @Binding var selectedFolder: Folder?
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { 
                    if !folder.subfolders.isEmpty {
                        isExpanded.toggle()
                    }
                }) {
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
            .onTapGesture {
                selectedFolder = folder
            }
            
            if isExpanded {
                ForEach(folder.sortedSubfolders(), id: \.id) { subfolder in
                    FolderRowView(folder: subfolder, selectedFolder: $selectedFolder)
                        .padding(.leading, 20)
                }
            }
        }
    }
}

// MARK: - Folder Content View

struct FolderContentView: View {
    let folder: Folder
    @Environment(\.managedObjectContext) private var viewContext
    @State private var documents: [Document] = []
    @State private var showingDocumentPicker = false
    @State private var showingScanner = false
    @State private var selectedDocument: Document?
    @State private var searchText = ""
    
    var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return documents
        } else {
            return documents.filter { document in
                document.searchableContent().localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with folder info and actions
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
                
                HStack(spacing: 12) {
                    Button(action: { showingDocumentPicker = true }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { showingScanner = true }) {
                        Label("Scan", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            
            // Search bar
            SearchBar(text: $searchText)
                .padding(.horizontal)
                .padding(.bottom)
            
            // Document grid
            if filteredDocuments.isEmpty {
                EmptyFolderView(folder: folder, hasSearchFilter: !searchText.isEmpty)
            } else {
                DocumentGridView(documents: filteredDocuments, selectedDocument: $selectedDocument)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadDocuments()
        }
        .onChange(of: folder) { _ in
            loadDocuments()
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPickerView(folder: folder)
        }
        .sheet(isPresented: $showingScanner) {
            ScannerView(folder: folder)
        }
        .sheet(item: $selectedDocument) { document in
            DocumentDetailView(document: document)
        }
    }
    
    private func loadDocuments() {
        documents = folder.sortedDocuments()
    }
}

// MARK: - Document Grid View

struct DocumentGridView: View {
    let documents: [Document]
    @Binding var selectedDocument: Document?
    
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(documents, id: \.id) { document in
                    DocumentCardView(document: document)
                        .onTapGesture {
                            selectedDocument = document
                        }
                }
            }
            .padding()
        }
    }
}

// MARK: - Document Card View

struct DocumentCardView: View {
    let document: Document
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail or icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(height: 120)
                
                if let thumbnail = document.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: document.documentType.icon)
                        .font(.system(size: 40))
                        .foregroundColor(document.documentType.color)
                }
            }
            
            // Document info
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(document.formattedFileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(document.modifiedAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Empty Folder View

struct EmptyFolderView: View {
    let folder: Folder
    let hasSearchFilter: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: hasSearchFilter ? "magnifyingglass" : "folder")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text(hasSearchFilter ? "No matching documents" : "This folder is empty")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text(hasSearchFilter ? 
                 "Try adjusting your search terms" : 
                 "Add documents by scanning or importing files")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search documents...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Add Folder View

struct AddFolderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let parentFolder: Folder?
    @State private var folderName = ""
    @State private var selectedColor = Color.blue
    @State private var selectedIcon = "folder.fill"
    
    private let availableIcons = [
        "folder.fill", "doc.fill", "photo.fill", "receipt.fill",
        "person.crop.rectangle.fill", "bag.fill", "rosette",
        "heart.fill", "star.fill", "bookmark.fill"
    ]
    
    private let availableColors: [Color] = [
        .blue, .green, .orange, .red, .purple, .pink, .yellow, .gray
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Folder Details") {
                    TextField("Folder Name", text: $folderName)
                    
                    HStack {
                        Text("Color")
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(availableColors, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                                    )
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                        }
                    }
                    
                    HStack {
                        Text("Icon")
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(availableIcons, id: \.self) { icon in
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(selectedIcon == icon ? selectedColor : .secondary)
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedIcon == icon ? selectedColor.opacity(0.2) : Color.clear)
                                    )
                                    .onTapGesture {
                                        selectedIcon = icon
                                    }
                            }
                        }
                    }
                }
                
                if let parent = parentFolder {
                    Section("Location") {
                        HStack {
                            Image(systemName: parent.icon)
                                .foregroundColor(parent.color)
                            Text("Inside \(parent.name)")
                        }
                    }
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createFolder()
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func createFolder() {
        let folder = Folder(context: viewContext, name: folderName.trimmingCharacters(in: .whitespacesAndNewlines))
        folder.colorHex = selectedColor.toHex()
        folder.iconName = selectedIcon
        folder.parentFolder = parentFolder
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Failed to create folder: \(error)")
        }
    }
}

#Preview {
    FolderView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .environmentObject(FolderStore())
}

