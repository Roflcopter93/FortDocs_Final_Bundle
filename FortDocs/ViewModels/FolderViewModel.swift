import Foundation
import CoreData
import SwiftUI
import Combine

/// View model responsible for managing the folder hierarchy and performing
/// operations on folders and documents.  This version adds support for batch
/// document operations and reuses existing CRUD operations from the upstream
/// implementation.  All methods that mutate Core Data are executed on the
/// provided managed object context.
@MainActor
final class FolderViewModel: ObservableObject {
    @Published var rootFolders: [Folder] = []
    @Published var selectedFolder: Folder?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var managedObjectContext: NSManagedObjectContext?

    init() {
        setupNotifications()
    }
    deinit { cancellables.forEach { $0.cancel() } }

    // MARK: - Folder loading
    func loadRootFolders(context: NSManagedObjectContext) {
        managedObjectContext = context
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

    // MARK: - Folder CRUD
    func createFolder(name: String, color: Color, icon: String, parent: Folder? = nil) {
        guard let context = managedObjectContext else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Folder name cannot be empty"
            return
        }
        // Prevent duplicates
        let existingNames: [String]
        if let parent = parent {
            existingNames = parent.subfolders.map { $0.name.lowercased() }
        } else {
            existingNames = rootFolders.map { $0.name.lowercased() }
        }
        if existingNames.contains(trimmed.lowercased()) {
            errorMessage = "A folder with this name already exists"
            return
        }
        let folder = Folder(context: context, name: trimmed, color: color, icon: icon)
        folder.parentFolder = parent
        do {
            try context.save()
            loadRootFolders(context: context)
            // Trigger a reindex asynchronously; the new folder does not correspond to a document
            Task { await SearchIndex.shared.rebuildIndex() }
            errorMessage = nil
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
        }
    }
    func deleteFolder(_ folder: Folder) {
        guard let context = managedObjectContext, !folder.isDefault else {
            errorMessage = "Cannot delete default folders"
            return
        }
        context.delete(folder)
        do {
            try context.save()
            loadRootFolders(context: context)
            if selectedFolder == folder { selectedFolder = nil }
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
            Task { await SearchIndex.shared.rebuildIndex() }
            errorMessage = nil
        } catch {
            errorMessage = "Failed to move folder: \(error.localizedDescription)"
        }
    }
    func renameFolder(_ folder: Folder, to newName: String) {
        guard let context = managedObjectContext else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Folder name cannot be empty"
            return
        }
        guard folder.validateName(trimmed) else {
            errorMessage = "A folder with this name already exists"
            return
        }
        folder.name = trimmed
        do {
            try context.save()
            loadRootFolders(context: context)
            Task { await SearchIndex.shared.rebuildIndex() }
            errorMessage = nil
        } catch {
            errorMessage = "Failed to rename folder: \(error.localizedDescription)"
        }
    }

    // MARK: - Document batch operations
    /// Delete multiple documents at once.  Each document is removed from its context
    /// and the context is saved once at the end.
    func deleteDocuments(_ documents: [Document]) {
        guard let context = managedObjectContext else { return }
        context.perform {
            for doc in documents { context.delete(doc) }
            do {
                try context.save()
                // Refresh index to remove deleted documents
                Task { await SearchIndex.shared.removeDocumentFromIndex(documents.first?.id ?? UUID()) }
            } catch {
                DispatchQueue.main.async { self.errorMessage = "Failed to delete documents: \(error.localizedDescription)" }
            }
        }
    }
    /// Placeholder for moving multiple documents.  In a full implementation this would update the
    /// `folder` relationship on each document and save the context.
    func moveDocuments(_ documents: [Document], to folder: Folder) {
        guard let context = managedObjectContext else { return }
        context.perform {
            for doc in documents { doc.folder = folder }
            do { try context.save() } catch {
                DispatchQueue.main.async { self.errorMessage = "Failed to move documents: \(error.localizedDescription)" }
            }
        }
    }
    /// Placeholder for exporting multiple documents.  In a production app this might compress
    /// the files into a zip archive and present a share sheet.
    func exportDocuments(_ documents: [Document]) {
        // Implementation intentionally left as an exercise.
    }

    // MARK: - Notifications
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                Task { @MainActor in self?.handleContextDidSave() }
            }
            .store(in: &cancellables)
    }
    private func handleContextDidSave() {
        guard let context = managedObjectContext else { return }
        loadRootFolders(context: context)
    }
}