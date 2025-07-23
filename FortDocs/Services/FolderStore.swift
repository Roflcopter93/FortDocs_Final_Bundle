import Foundation
import CoreData
import SwiftUI
import Combine

@MainActor
class FolderStore: ObservableObject {
    @Published var rootFolders: [Folder] = []
    @Published var isInitialized = false
    
    private var managedObjectContext: NSManagedObjectContext?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupNotifications()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    
    func initialize(with context: NSManagedObjectContext) {
        self.managedObjectContext = context
        loadRootFolders()
        
        if !isInitialized {
            initializeDefaultFolders()
        }
    }
    
    func initializeDefaultFolders() {
        guard let context = managedObjectContext else { return }
        
        // Check if default folders already exist
        let request = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "isDefault == YES")
        
        do {
            let existingDefaultFolders = try context.fetch(request)
            if !existingDefaultFolders.isEmpty {
                isInitialized = true
                return
            }
        } catch {
            print("Failed to check for existing default folders: \(error)")
        }
        
        // Create default folders
        let defaultFolders = [
            DefaultFolderConfig(name: "Documents", color: .blue, icon: "doc.fill", sortOrder: 0),
            DefaultFolderConfig(name: "Invoices", color: .green, icon: "receipt.fill", sortOrder: 1),
            DefaultFolderConfig(name: "IDs", color: .orange, icon: "person.crop.rectangle.fill", sortOrder: 2),
            DefaultFolderConfig(name: "Receipts", color: .purple, icon: "bag.fill", sortOrder: 3),
            DefaultFolderConfig(name: "Certificates", color: .red, icon: "rosette", sortOrder: 4)
        ]
        
        for config in defaultFolders {
            let folder = Folder(context: context)
            folder.name = config.name
            folder.colorHex = config.color.toHex()
            folder.iconName = config.icon
            folder.sortOrder = Int32(config.sortOrder)
            folder.isDefault = true
        }
        
        do {
            try context.save()
            loadRootFolders()
            isInitialized = true
        } catch {
            print("Failed to create default folders: \(error)")
        }
    }
    
    func getDefaultFolder(named name: String) -> Folder? {
        guard let context = managedObjectContext else { return nil }
        
        let request = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@ AND isDefault == YES", name)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Failed to fetch default folder: \(error)")
            return nil
        }
    }
    
    func createFolder(name: String, color: Color = .blue, icon: String = "folder.fill", parent: Folder? = nil) -> Folder? {
        guard let context = managedObjectContext else { return nil }
        
        let folder = Folder(context: context)
        folder.name = name
        folder.colorHex = color.toHex()
        folder.iconName = icon
        folder.parentFolder = parent
        
        if let parent = parent {
            folder.sortOrder = Int32(parent.subfolders.count)
        } else {
            folder.sortOrder = Int32(rootFolders.count)
        }
        
        do {
            try context.save()
            loadRootFolders()
            return folder
        } catch {
            print("Failed to create folder: \(error)")
            return nil
        }
    }
    
    func deleteFolder(_ folder: Folder) -> Bool {
        guard let context = managedObjectContext else { return false }
        guard !folder.isDefault else { return false }
        
        context.delete(folder)
        
        do {
            try context.save()
            loadRootFolders()
            return true
        } catch {
            print("Failed to delete folder: \(error)")
            return false
        }
    }
    
    func moveFolder(_ folder: Folder, to newParent: Folder?) -> Bool {
        guard let context = managedObjectContext else { return false }
        guard folder.canMoveTo(newParent ?? folder) else { return false }
        
        folder.moveToFolder(newParent)
        
        do {
            try context.save()
            loadRootFolders()
            return true
        } catch {
            print("Failed to move folder: \(error)")
            return false
        }
    }
    
    func renameFolder(_ folder: Folder, to newName: String) -> Bool {
        guard let context = managedObjectContext else { return false }
        guard folder.validateName(newName) else { return false }
        
        folder.name = newName
        
        do {
            try context.save()
            loadRootFolders()
            return true
        } catch {
            print("Failed to rename folder: \(error)")
            return false
        }
    }
    
    func updateFolderAppearance(_ folder: Folder, color: Color, icon: String) -> Bool {
        guard let context = managedObjectContext else { return false }
        
        folder.colorHex = color.toHex()
        folder.iconName = icon
        
        do {
            try context.save()
            loadRootFolders()
            return true
        } catch {
            print("Failed to update folder appearance: \(error)")
            return false
        }
    }
    
    func reorderFolders(_ folders: [Folder]) -> Bool {
        guard let context = managedObjectContext else { return false }
        
        for (index, folder) in folders.enumerated() {
            folder.sortOrder = Int32(index)
        }
        
        do {
            try context.save()
            loadRootFolders()
            return true
        } catch {
            print("Failed to reorder folders: \(error)")
            return false
        }
    }
    
    // MARK: - Search and Query Methods
    
    func searchFolders(query: String) -> [Folder] {
        guard let context = managedObjectContext else { return [] }
        
        let request = Folder.searchFolders(query: query)
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to search folders: \(error)")
            return []
        }
    }
    
    func getAllFolders() -> [Folder] {
        guard let context = managedObjectContext else { return [] }
        
        let request = Folder.fetchAll()
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch all folders: \(error)")
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
    
    func getFolderPath(for folder: Folder) -> String {
        let hierarchy = getFolderHierarchy(for: folder)
        return hierarchy.map { $0.name }.joined(separator: " > ")
    }
    
    // MARK: - Statistics and Analytics
    
    func getFolderStatistics() -> FolderStatistics {
        let allFolders = getAllFolders()
        let totalDocuments = allFolders.reduce(0) { $0 + $1.directDocumentCount }
        let totalSize = allFolders.reduce(Int64(0)) { total, folder in
            total + folder.documents.reduce(Int64(0)) { $0 + $1.fileSize }
        }
        
        return FolderStatistics(
            totalFolders: allFolders.count,
            totalDocuments: totalDocuments,
            totalSize: totalSize,
            lastModified: allFolders.compactMap { $0.modifiedAt }.max() ?? Date()
        )
    }
    
    func getRecentlyModifiedFolders(limit: Int = 10) -> [Folder] {
        let allFolders = getAllFolders()
        return Array(allFolders.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit))
    }
    
    func getMostUsedFolders(limit: Int = 10) -> [Folder] {
        let allFolders = getAllFolders()
        return Array(allFolders.sorted { $0.documentCount > $1.documentCount }.prefix(limit))
    }
    
    // MARK: - Document Management
    
    func addDocument(_ document: Document, to folder: Folder) -> Bool {
        guard let context = managedObjectContext else { return false }
        
        folder.addDocument(document)
        
        do {
            try context.save()
            return true
        } catch {
            print("Failed to add document to folder: \(error)")
            return false
        }
    }
    
    func moveDocument(_ document: Document, from sourceFolder: Folder, to targetFolder: Folder) -> Bool {
        guard let context = managedObjectContext else { return false }
        
        sourceFolder.removeDocument(document)
        targetFolder.addDocument(document)
        
        do {
            try context.save()
            return true
        } catch {
            print("Failed to move document: \(error)")
            return false
        }
    }
    
    func removeDocument(_ document: Document, from folder: Folder) -> Bool {
        guard let context = managedObjectContext else { return false }
        
        folder.removeDocument(document)
        
        do {
            try context.save()
            return true
        } catch {
            print("Failed to remove document from folder: \(error)")
            return false
        }
    }
    
    // MARK: - Smart Folder Suggestions
    
    func suggestFolderForDocument(_ document: Document) -> Folder? {
        let documentTitle = document.title.lowercased()
        let ocrText = document.ocrText?.lowercased() ?? ""
        let content = "\(documentTitle) \(ocrText)"
        
        // Define keyword patterns for different folder types
        let folderSuggestions: [(keywords: [String], folderName: String)] = [
            (["invoice", "bill", "payment", "due", "amount"], "Invoices"),
            (["receipt", "purchase", "bought", "paid", "transaction"], "Receipts"),
            (["id", "passport", "license", "identification", "card"], "IDs"),
            (["certificate", "diploma", "award", "achievement", "completion"], "Certificates"),
            (["contract", "agreement", "legal", "terms", "conditions"], "Documents")
        ]
        
        for suggestion in folderSuggestions {
            if suggestion.keywords.contains(where: { content.contains($0) }) {
                return getDefaultFolder(named: suggestion.folderName)
            }
        }
        
        // Default to Documents folder
        return getDefaultFolder(named: "Documents")
    }
    
    func generateSmartFolderName(for documents: [Document]) -> String {
        let commonWords = extractCommonWords(from: documents)
        
        if let mostCommon = commonWords.first {
            return mostCommon.capitalized
        }
        
        // Fallback to date-based naming
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Documents - \(formatter.string(from: Date()))"
    }
    
    // MARK: - Private Methods
    
    private func loadRootFolders() {
        guard let context = managedObjectContext else { return }
        
        let request = Folder.fetchRootFolders()
        
        do {
            rootFolders = try context.fetch(request)
        } catch {
            print("Failed to load root folders: \(error)")
            rootFolders = []
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadRootFolders()
                }
            }
            .store(in: &cancellables)
    }
    
    private func extractCommonWords(from documents: [Document]) -> [String] {
        var wordCounts: [String: Int] = [:]
        
        for document in documents {
            let words = document.title.components(separatedBy: .whitespacesAndPunctuationMarks)
                .filter { $0.count > 2 }
                .map { $0.lowercased() }
            
            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }
        
        return wordCounts.sorted { $0.value > $1.value }.map { $0.key }
    }
}

// MARK: - Supporting Types

struct DefaultFolderConfig {
    let name: String
    let color: Color
    let icon: String
    let sortOrder: Int
}

// MARK: - Folder Organization Extensions

extension FolderStore {
    
    func organizeFoldersByType() {
        guard let context = managedObjectContext else { return }
        
        // Get all documents without folders
        let request = Document.fetchRequest()
        request.predicate = NSPredicate(format: "folder == nil")
        
        do {
            let unorganizedDocuments = try context.fetch(request)
            
            for document in unorganizedDocuments {
                if let suggestedFolder = suggestFolderForDocument(document) {
                    _ = addDocument(document, to: suggestedFolder)
                }
            }
        } catch {
            print("Failed to organize folders by type: \(error)")
        }
    }
    
    func createSmartFolder(name: String, predicate: NSPredicate) -> Folder? {
        guard let context = managedObjectContext else { return nil }
        
        let folder = Folder(context: context)
        folder.name = name
        folder.colorHex = Color.purple.toHex()
        folder.iconName = "sparkles"
        
        // Note: Smart folders would require additional implementation
        // to store and evaluate predicates dynamically
        
        do {
            try context.save()
            loadRootFolders()
            return folder
        } catch {
            print("Failed to create smart folder: \(error)")
            return nil
        }
    }
    
    func cleanupEmptyFolders() {
        let allFolders = getAllFolders()
        let emptyFolders = allFolders.filter { !$0.isDefault && $0.documents.isEmpty && $0.subfolders.isEmpty }
        
        for folder in emptyFolders {
            _ = deleteFolder(folder)
        }
    }
}

