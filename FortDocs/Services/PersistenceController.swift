import CoreData
import CloudKit
import Foundation

class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    
    @Published var isCloudKitEnabled = true
    @Published var syncStatus: CloudKitSyncStatus = .notStarted
    
    lazy var container: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "FortDocs")
        
        // Configure CloudKit
        if isCloudKitEnabled {
            setupCloudKitContainer(container)
        } else {
            setupLocalContainer(container)
        }
        
        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error as NSError? {
                print("Core Data error: \(error), \(error.userInfo)")
                self?.syncStatus = .error(error.localizedDescription)
            } else {
                print("Core Data store loaded: \(storeDescription)")
                self?.syncStatus = .available
                
                if self?.isCloudKitEnabled == true {
                    self?.setupCloudKitNotifications()
                }
            }
        }
        
        // Configure context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Enable persistent history tracking
        container.viewContext.transactionAuthor = "FortDocs-Main"
        
        return container
    }()
    
    private init() {
        // Check CloudKit availability on init
        checkCloudKitAvailability()
    }
    
    // MARK: - CloudKit Configuration
    
    private func setupCloudKitContainer(_ container: NSPersistentCloudKitContainer) {
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        // Configure CloudKit
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Set CloudKit container identifier
        description.setOption("iCloud.com.fortdocs.app" as NSString, forKey: NSPersistentCloudKitContainerOptionsKey)
        
        // Configure sync options
        let cloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.fortdocs.app")
        description.cloudKitContainerOptions = cloudKitOptions
        
        // Set up URL for local store
        let storeURL = getStoreURL()
        description.url = storeURL
        
        print("CloudKit container configured with identifier: iCloud.com.fortdocs.app")
    }
    
    private func setupLocalContainer(_ container: NSPersistentCloudKitContainer) {
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        // Disable CloudKit for local-only mode
        description.cloudKitContainerOptions = nil
        
        // Still enable history tracking for potential future CloudKit sync
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Set up URL for local store
        let storeURL = getStoreURL()
        description.url = storeURL
        
        print("Local-only Core Data container configured")
    }
    
    private func getStoreURL() -> URL {
        let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FortDocs.sqlite")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        return storeURL
    }
    
    // MARK: - CloudKit Availability
    
    private func checkCloudKitAvailability() {
        let container = CKContainer(identifier: "iCloud.com.fortdocs.app")
        
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.syncStatus = .available
                case .noAccount:
                    self?.syncStatus = .noAccount
                case .restricted:
                    self?.syncStatus = .restricted
                case .couldNotDetermine:
                    self?.syncStatus = .error("Could not determine iCloud status")
                case .temporarilyUnavailable:
                    self?.syncStatus = .temporarilyUnavailable
                @unknown default:
                    self?.syncStatus = .error("Unknown iCloud status")
                }
            }
        }
    }
    
    // MARK: - CloudKit Notifications
    
    private func setupCloudKitNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteStoreChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudKitImport),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container
        )
    }
    
    @objc private func handleRemoteStoreChange(_ notification: Notification) {
        print("Remote store change detected")
        
        DispatchQueue.main.async {
            self.syncStatus = .syncing
        }
        
        // Merge changes into view context
        container.viewContext.perform {
            self.container.viewContext.refreshAllObjects()
            
            DispatchQueue.main.async {
                self.syncStatus = .available
            }
        }
    }
    
    @objc private func handleCloudKitImport(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }
        
        print("CloudKit event: \(event.type.rawValue)")
        
        DispatchQueue.main.async {
            switch event.type {
            case .setup:
                self.syncStatus = .available
            case .import:
                self.syncStatus = .syncing
            case .export:
                self.syncStatus = .syncing
            @unknown default:
                break
            }
            
            if event.endDate != nil {
                self.syncStatus = .available
            }
            
            if let error = event.error {
                self.syncStatus = .error(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Context Management
    
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = "FortDocs-Background"
        return context
    }
    
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            context.transactionAuthor = "FortDocs-Task"
            block(context)
        }
    }
    
    // MARK: - Save Operations
    
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
                print("Core Data context saved successfully")
            } catch {
                print("Failed to save Core Data context: \(error)")
                
                // Handle save errors
                if let nsError = error as NSError? {
                    handleSaveError(nsError)
                }
            }
        }
    }
    
    func saveContext(_ context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
                print("Background context saved successfully")
            } catch {
                print("Failed to save background context: \(error)")
                
                if let nsError = error as NSError? {
                    handleSaveError(nsError)
                }
            }
        }
    }
    
    private func handleSaveError(_ error: NSError) {
        // Handle different types of Core Data errors
        switch error.code {
        case NSValidationMissingMandatoryPropertyError:
            print("Validation error: Missing mandatory property")
        case NSValidationRelationshipLacksMinimumCountError:
            print("Validation error: Relationship lacks minimum count")
        case NSValidationRelationshipExceedsMaximumCountError:
            print("Validation error: Relationship exceeds maximum count")
        case NSManagedObjectValidationError:
            print("Managed object validation error")
        case NSPersistentStoreInvalidTypeError:
            print("Persistent store invalid type error")
        default:
            print("Unhandled Core Data error: \(error.localizedDescription)")
        }
        
        DispatchQueue.main.async {
            self.syncStatus = .error(error.localizedDescription)
        }
    }
    
    // MARK: - CloudKit Sync Control
    
    func enableCloudKitSync() {
        guard !isCloudKitEnabled else { return }
        
        isCloudKitEnabled = true
        
        // Recreate container with CloudKit enabled
        // Note: This would require app restart in a real implementation
        print("CloudKit sync enabled - app restart required")
    }
    
    func disableCloudKitSync() {
        guard isCloudKitEnabled else { return }
        
        isCloudKitEnabled = false
        
        // Recreate container without CloudKit
        // Note: This would require app restart in a real implementation
        print("CloudKit sync disabled - app restart required")
    }
    
    // MARK: - Data Migration
    
    func migrateToCloudKit() async throws {
        guard !isCloudKitEnabled else { return }
        
        syncStatus = .migrating
        
        // This would implement migration from local to CloudKit
        // For now, just enable CloudKit
        enableCloudKitSync()
        
        syncStatus = .available
    }
    
    func migrateFromCloudKit() async throws {
        guard isCloudKitEnabled else { return }
        
        syncStatus = .migrating
        
        // This would implement migration from CloudKit to local
        // For now, just disable CloudKit
        disableCloudKitSync()
        
        syncStatus = .available
    }
    
    // MARK: - Cleanup
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Preview Support

extension PersistenceController {
    static var preview: PersistenceController = {
        let controller = PersistenceController()
        let context = controller.container.viewContext
        
        // Create sample data for previews
        let sampleFolder = Folder(context: context)
        sampleFolder.id = UUID()
        sampleFolder.name = "Sample Folder"
        sampleFolder.iconName = "folder.fill"
        sampleFolder.colorHex = "007AFF"
        sampleFolder.createdAt = Date()
        sampleFolder.modifiedAt = Date()
        sampleFolder.sortOrder = 0
        
        let sampleDocument = Document(context: context)
        sampleDocument.id = UUID()
        sampleDocument.title = "Sample Document"
        sampleDocument.fileName = "sample.pdf"
        sampleDocument.mimeType = "application/pdf"
        sampleDocument.fileSize = 1024
        sampleDocument.createdAt = Date()
        sampleDocument.modifiedAt = Date()
        sampleDocument.folder = sampleFolder
        sampleDocument.ocrText = "This is sample OCR text from the document."
        
        do {
            try context.save()
        } catch {
            print("Failed to save preview data: \(error)")
        }
        
        return controller
    }()
}

// MARK: - Supporting Types

enum CloudKitSyncStatus: Equatable {
    case notStarted
    case available
    case syncing
    case migrating
    case noAccount
    case restricted
    case temporarilyUnavailable
    case error(String)
    
    var description: String {
        switch self {
        case .notStarted:
            return "Not started"
        case .available:
            return "Available"
        case .syncing:
            return "Syncing..."
        case .migrating:
            return "Migrating..."
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "iCloud restricted"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
    
    var isAvailable: Bool {
        return self == .available
    }
}

// MARK: - Core Data Extensions

extension NSManagedObjectContext {
    func saveIfNeeded() throws {
        if hasChanges {
            try save()
        }
    }
    
    func performAndWait<T>(_ block: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        
        performAndWait {
            do {
                result = .success(try block())
            } catch {
                result = .failure(error)
            }
        }
        
        return try result.get()
    }
}

extension NSPersistentContainer {
    func saveViewContext() {
        if viewContext.hasChanges {
            do {
                try viewContext.save()
            } catch {
                print("Failed to save view context: \(error)")
            }
        }
    }
}

