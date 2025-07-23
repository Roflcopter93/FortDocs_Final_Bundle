import Foundation
import CoreData
import SwiftUI
import Combine

@MainActor
class FolderViewModel: ObservableObject {
    @Published var rootFolders: [Folder] = []
    @Published var selectedFolder: Folder?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private var managedObjectContext: NSManagedObjectContext?
    
    // MARK: - Initialization
    
    init() {
        setupNotifications()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    
    func loadRootFolders(context: NSManagedObjectContext) {
        self.managedObjectContext = context
        isLoading = true
        errorMessage = nil
        
        do {
            let request = Folder.fetchRootFolders()
            rootFolders = try context.fetch(request)
            isLoading = false
        } catch {
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func createFolder(name: String, color: Color, icon: String, parent: Folder? = nil) {
        guard let context = managedObjectContext else { return }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Folder name cannot be empty"
            return
        }
        
        // Check for duplicate names
        if let parent = parent {
            let existingNames = parent.subfolders.map { $0.name.lowercased() }
            if existingNames.contains(trimmedName.lowercased()) {
                errorMessage = "A folder with this name already exists"
                return
            }
        } else {
            let existingNames = rootFolders.map { $0.name.lowercased() }
            if existingNames.contains(trimmedName.lowercased()) {
                errorMessage = "A folder with this name already exists"
                return
            }
        }
        
        let folder = Folder(context: context, name: trimmedName, color: color, icon: icon)
        folder.parentFolder = parent
        
        do {
            try context.save()
            loadRootFolders(context: context)
            SearchIndex.shared.reindexAllDocuments(context: context)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
        }
    }
    
    func deleteFolder(_ folder: Folder) {
        guard let context = managedObjectContext else { return }
        guard !folder.isDefault else {
            errorMessage = "Cannot delete default folders"
            return
        }
        
        context.delete(folder)
        
        do {
            try context.save()
            loadRootFolders(context: context)
            
            // Clear selection if deleted folder was selected
            if selectedFolder == folder {
                selectedFolder = nil
            }
            
            errorMessage = nil
        } catch {
            errorMessage = "Failed to delete folder: \(error.localizedDescription)"
        }
    }
    
    func moveFolder(_ folder: Folder, to newParent: Folder?) {
        guard let context = managedObjectContext else { return }
        guard folder.canMoveTo(newParent ?? folder) else {
            errorMessage = "Cannot move folder to this location"
            return
        }
        
        folder.moveToFolder(newParent)
        
        do {
            try context.save()
            loadRootFolders(context: context)
            SearchIndex.shared.reindexAllDocuments(context: context)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to move folder: \(error.localizedDescription)"
        }
    }
    
    func renameFolder(_ folder: Folder, to newName: String) {
        guard let context = managedObjectContext else { return }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Folder name cannot be empty"
            return
        }
        
        guard folder.validateName(trimmedName) else {
            errorMessage = "A folder with this name already exists"
            return
        }
        
        folder.name = trimmedName
        
        do {
            try context.save()
            loadRootFolders(context: context)
            SearchIndex.shared.reindexAllDocuments(context: context)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to rename folder: \(error.localizedDescription)"
        }
    }
    
    func updateFolderAppearance(_ folder: Folder, color: Color, icon: String) {
        guard let context = managedObjectContext else { return }
        
        folder.colorHex = color.toHex()
        folder.iconName = icon
        
        do {
            try context.save()
            loadRootFolders(context: context)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to update folder: \(error.localizedDescription)"
        }
    }
    
    func searchFolders(query: String) -> [Folder] {
        guard let context = managedObjectContext else { return [] }
        
        do {
            let request = Folder.searchFolders(query: query)
            return try context.fetch(request)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            return []
        }
    }
    
    func getFolderHierarchy(for folder: Folder) -> [Folder] {
        var hierarchy: [Folder] = []
        var currentFolder: Folder? = folder
        
        while let folder = currentFolder {
            hierarchy.insert(folder, at: 0)
            currentFolder = folder.parentFolder
        }
        
        return hierarchy
    }
    
    func getSubfolders(of folder: Folder) -> [Folder] {
        return folder.sortedSubfolders()
    }
    
    func getDocuments(in folder: Folder) -> [Document] {
        return folder.sortedDocuments()
    }
    
    func getTotalDocumentCount(in folder: Folder) -> Int {
        return folder.documentCount
    }
    
    func getDirectDocumentCount(in folder: Folder) -> Int {
        return folder.directDocumentCount
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleContextDidSave()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleContextDidSave() {
        guard let context = managedObjectContext else { return }
        loadRootFolders(context: context)
    }
}

// MARK: - Folder Organization

extension FolderViewModel {
    
    func organizeFoldersByType() {
        guard let context = managedObjectContext else { return }
        
        // Create type-based folders if they don't exist
        let folderTypes = [
            ("Documents", Color.blue, "doc.fill"),
            ("Images", Color.green, "photo.fill"),
            ("PDFs", Color.red, "doc.fill"),
            ("Receipts", Color.orange, "receipt.fill")
        ]
        
        for (name, color, icon) in folderTypes {
            if !rootFolders.contains(where: { $0.name == name }) {
                createFolder(name: name, color: color, icon: icon)
            }
        }
    }
    
    func sortFolders(by sortType: FolderSortType) {
        switch sortType {
        case .name:
            rootFolders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateCreated:
            rootFolders.sort { $0.createdAt < $1.createdAt }
        case .dateModified:
            rootFolders.sort { $0.modifiedAt > $1.modifiedAt }
        case .documentCount:
            rootFolders.sort { $0.documentCount > $1.documentCount }
        case .custom:
            rootFolders.sort { $0.sortOrder < $1.sortOrder }
        }
    }
    
    func updateSortOrder(for folders: [Folder]) {
        guard let context = managedObjectContext else { return }
        
        for (index, folder) in folders.enumerated() {
            folder.sortOrder = Int32(index)
        }
        
        do {
            try context.save()
            loadRootFolders(context: context)
        } catch {
            errorMessage = "Failed to update sort order: \(error.localizedDescription)"
        }
    }
}

// MARK: - Folder Statistics

extension FolderViewModel {
    
    func getFolderStatistics() -> FolderStatistics {
        let totalFolders = rootFolders.count + rootFolders.reduce(0) { $0 + countSubfolders($1) }
        let totalDocuments = rootFolders.reduce(0) { $0 + $1.documentCount }
        let totalSize = calculateTotalSize()
        
        return FolderStatistics(
            totalFolders: totalFolders,
            totalDocuments: totalDocuments,
            totalSize: totalSize,
            lastModified: rootFolders.map { $0.modifiedAt }.max() ?? Date()
        )
    }
    
    private func countSubfolders(_ folder: Folder) -> Int {
        return folder.subfolders.count + folder.subfolders.reduce(0) { $0 + countSubfolders($1) }
    }
    
    private func calculateTotalSize() -> Int64 {
        return rootFolders.reduce(0) { total, folder in
            total + folder.documents.reduce(0) { $0 + $1.fileSize }
        }
    }
}

// MARK: - Supporting Types

enum FolderSortType: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
    case dateModified = "Date Modified"
    case documentCount = "Document Count"
    case custom = "Custom Order"
    
    var systemImage: String {
        switch self {
        case .name:
            return "textformat.abc"
        case .dateCreated:
            return "calendar.badge.plus"
        case .dateModified:
            return "calendar.badge.clock"
        case .documentCount:
            return "number.circle"
        case .custom:
            return "line.3.horizontal"
        }
    }
}

struct FolderStatistics {
    let totalFolders: Int
    let totalDocuments: Int
    let totalSize: Int64
    let lastModified: Date
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

// MARK: - Error Handling

extension FolderViewModel {
    
    func clearError() {
        errorMessage = nil
    }
    
    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

