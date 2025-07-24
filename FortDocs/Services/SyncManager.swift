import Foundation
import CoreData
import CloudKit
import Combine
import Network

class SyncManager: ObservableObject {
    static let shared = SyncManager()
    
    @Published var syncState: SyncState = .idle
    @Published var isOnline = true
    @Published var pendingChanges = 0
    @Published var lastSyncDate: Date?
    @Published var conflicts: [SyncConflict] = []
    @Published var syncProgress: Double = 0.0
    
    private let persistenceController = PersistenceController.shared
    private let cloudKitService = CloudKitService.shared
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var syncTask: Task<Void, Never>?
    
    // Sync configuration
    private let syncInterval: TimeInterval = 300 // 5 minutes
    private let maxRetryAttempts = 3
    private let retryDelay: TimeInterval = 30
    
    private init() {
        setupNetworkMonitoring()
        setupAutoSync()
        setupNotificationObservers()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOnline = self?.isOnline ?? false
                self?.isOnline = path.status == .satisfied
                
                // If we just came back online, trigger sync
                if !wasOnline && self?.isOnline == true {
                    self?.syncWhenOnline()
                }
            }
        }
        
        networkMonitor.start(queue: networkQueue)
    }
    
    // MARK: - Auto Sync
    
    private func setupAutoSync() {
        // Start periodic sync timer
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            self?.performAutoSync()
        }
        
        // Sync when app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.performAutoSync()
            }
            .store(in: &cancellables)
        
        // Sync when app goes to background
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.performBackgroundSync()
            }
            .store(in: &cancellables)
    }
    
    private func setupNotificationObservers() {
        // Listen for Core Data changes
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] notification in
                self?.handleCoreDataChange(notification)
            }
            .store(in: &cancellables)
        
        // Listen for CloudKit notifications
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .sink { [weak self] notification in
                self?.handleCloudKitEvent(notification)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Sync Operations
    
    func performManualSync() async {
        guard isOnline else {
            syncState = .offline
            return
        }
        
        await performSync(isManual: true)
    }
    
    private func performAutoSync() {
        guard isOnline && syncState != .syncing else { return }
        
        syncTask?.cancel()
        syncTask = Task {
            await performSync(isManual: false)
        }
    }
    
    private func performBackgroundSync() {
        guard isOnline else { return }
        
        // Request background time
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        
        syncTask?.cancel()
        syncTask = Task {
            await performSync(isManual: false)
            endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    private func performSync(isManual: Bool) async {
        await MainActor.run {
            syncState = .syncing
            syncProgress = 0.0
        }

        do {
            // Step 1: Upload pending local changes
            try await uploadPendingChanges()
            await MainActor.run { syncProgress = 0.33 }

            // Step 2: Download remote changes
            try await downloadRemoteChanges()
            await MainActor.run { syncProgress = 0.66 }

            // Step 3: Resolve conflicts
            try await resolveConflicts()

            await MainActor.run { syncProgress = 0.9 }

            // Step 4: Update sync metadata
            updateSyncMetadata()

            await MainActor.run {
                syncState = .completed
                syncProgress = 1.0
                lastSyncDate = Date()
                
                if isManual {
                    // Show success feedback for manual sync
                    NotificationCenter.default.post(name: .syncCompleted, object: nil)
                }
            }
            
        } catch {
            await MainActor.run {
                syncState = .error(error.localizedDescription)
                syncProgress = 0.0
            }
            
            print("Sync failed: \(error)")
            
            // Schedule retry for non-manual syncs
            if !isManual {
                scheduleRetry()
            }
        }
    }
    
    private func syncWhenOnline() {
        guard isOnline && pendingChanges > 0 else { return }
        
        syncTask?.cancel()
        syncTask = Task {
            await performSync(isManual: false)
        }
    }
    
    // MARK: - Upload Operations
    
    private func uploadPendingChanges() async throws {
        let context = persistenceController.newBackgroundContext()
        
        try await context.perform {
            // Upload pending folders
            let pendingFolders = try self.fetchPendingFolders(in: context)
            for folder in pendingFolders {
                try await self.uploadFolder(folder)
                folder.needsSync = false
                folder.lastSyncDate = Date()
            }
            
            // Upload pending documents
            let pendingDocuments = try self.fetchPendingDocuments(in: context)
            for document in pendingDocuments {
                try await self.uploadDocument(document)
                document.needsSync = false
                document.lastSyncDate = Date()
            }
            
            try context.save()
            
            await MainActor.run {
                self.pendingChanges = 0
            }
        }
    }
    
    private func fetchPendingFolders(in context: NSManagedObjectContext) throws -> [Folder] {
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "needsSync == YES")
        return try context.fetch(request)
    }
    
    private func fetchPendingDocuments(in context: NSManagedObjectContext) throws -> [Document] {
        let request: NSFetchRequest<Document> = Document.fetchRequest()
        request.predicate = NSPredicate(format: "needsSync == YES")
        return try context.fetch(request)
    }
    
    private func uploadFolder(_ folder: Folder) async throws {
        try await cloudKitService.uploadFolder(folder)
    }
    
    private func uploadDocument(_ document: Document) async throws {
        try await cloudKitService.uploadDocument(document)
    }
    
    // MARK: - Download Operations
    
    private func downloadRemoteChanges() async throws {
        try await cloudKitService.performFullSync()
    }
    
    // MARK: - Conflict Resolution
    
    private func resolveConflicts() async throws {
        let context = persistenceController.newBackgroundContext()
        
        try await context.perform {
            let conflictedFolders = try self.fetchConflictedFolders(in: context)
            for folder in conflictedFolders {
                try self.resolveFolder(folder, in: context)
            }
            
            let conflictedDocuments = try self.fetchConflictedDocuments(in: context)
            for document in conflictedDocuments {
                try self.resolveDocument(document, in: context)
            }
            
            try context.save()
        }
    }
    
    private func fetchConflictedFolders(in context: NSManagedObjectContext) throws -> [Folder] {
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "conflictData != nil")
        return try context.fetch(request)
    }
    
    private func fetchConflictedDocuments(in context: NSManagedObjectContext) throws -> [Document] {
        let request: NSFetchRequest<Document> = Document.fetchRequest()
        request.predicate = NSPredicate(format: "conflictData != nil")
        return try context.fetch(request)
    }
    
    private func resolveFolder(_ folder: Folder, in context: NSManagedObjectContext) throws {
        guard let conflictData = folder.conflictData else { return }
        
        // Decode conflict data
        let conflict = try JSONDecoder().decode(FolderConflict.self, from: conflictData)
        
        // Apply resolution strategy
        switch conflict.resolutionStrategy {
        case .useLocal:
            // Keep local version, mark for upload
            folder.needsSync = true
            
        case .useRemote:
            // Apply remote changes
            folder.name = conflict.remoteName
            folder.iconName = conflict.remoteIconName
            folder.colorHex = conflict.remoteColorHex
            folder.modifiedAt = conflict.remoteModifiedAt
            
        case .merge:
            // Custom merge logic
            folder.name = conflict.remoteName // Prefer remote name
            folder.modifiedAt = max(folder.modifiedAt ?? Date(), conflict.remoteModifiedAt)
        }
        
        // Clear conflict data
        folder.conflictData = nil
        
        // Create conflict resolution record
        createConflictResolution(
            entityType: "Folder",
            entityID: folder.id!,
            strategy: conflict.resolutionStrategy,
            in: context
        )
    }
    
    private func resolveDocument(_ document: Document, in context: NSManagedObjectContext) throws {
        guard let conflictData = document.conflictData else { return }
        
        // Decode conflict data
        let conflict = try JSONDecoder().decode(DocumentConflict.self, from: conflictData)
        
        // Apply resolution strategy
        switch conflict.resolutionStrategy {
        case .useLocal:
            // Keep local version, mark for upload
            document.needsSync = true
            
        case .useRemote:
            // Apply remote changes
            document.title = conflict.remoteTitle
            document.ocrText = conflict.remoteOcrText
            document.modifiedAt = conflict.remoteModifiedAt
            
        case .merge:
            // Custom merge logic
            document.title = conflict.remoteTitle // Prefer remote title
            document.modifiedAt = max(document.modifiedAt ?? Date(), conflict.remoteModifiedAt)
        }
        
        // Clear conflict data
        document.conflictData = nil
        
        // Create conflict resolution record
        createConflictResolution(
            entityType: "Document",
            entityID: document.id!,
            strategy: conflict.resolutionStrategy,
            in: context
        )
    }
    
    private func createConflictResolution(
        entityType: String,
        entityID: UUID,
        strategy: ConflictResolutionStrategy,
        in context: NSManagedObjectContext
    ) {
        let resolution = ConflictResolution(context: context)
        resolution.id = UUID()
        resolution.entityType = entityType
        resolution.entityID = entityID
        resolution.conflictDate = Date()
        resolution.resolutionStrategy = strategy.rawValue
        resolution.isResolved = true
    }
    
    // MARK: - Sync Metadata
    
    private func updateSyncMetadata() {
        let context = persistenceController.newBackgroundContext()
        
        context.perform {
            // Update folder sync metadata
            self.updateEntitySyncMetadata(entityName: "Folder", in: context)
            
            // Update document sync metadata
            self.updateEntitySyncMetadata(entityName: "Document", in: context)
            
            do {
                try context.save()
            } catch {
                print("Failed to update sync metadata: \(error)")
            }
        }
    }
    
    private func updateEntitySyncMetadata(entityName: String, in context: NSManagedObjectContext) {
        let request: NSFetchRequest<SyncMetadata> = SyncMetadata.fetchRequest()
        request.predicate = NSPredicate(format: "entityName == %@", entityName)
        
        let metadata: SyncMetadata
        if let existing = try? context.fetch(request).first {
            metadata = existing
        } else {
            metadata = SyncMetadata(context: context)
            metadata.id = UUID()
            metadata.entityName = entityName
        }
        
        metadata.lastFullSync = Date()
        metadata.lastIncrementalSync = Date()
        metadata.errorCount = 0
    }
    
    // MARK: - Event Handlers
    
    private func handleCoreDataChange(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        
        // Count pending changes
        var changeCount = 0
        
        if let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for object in insertedObjects {
                if object is Folder || object is Document {
                    markForSync(object)
                    changeCount += 1
                }
            }
        }
        
        if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            for object in updatedObjects {
                if object is Folder || object is Document {
                    markForSync(object)
                    changeCount += 1
                }
            }
        }
        
        if changeCount > 0 {
            DispatchQueue.main.async {
                self.pendingChanges += changeCount
            }
        }
    }
    
    private func markForSync(_ object: NSManagedObject) {
        if let folder = object as? Folder {
            folder.needsSync = true
        } else if let document = object as? Document {
            document.needsSync = true
        }
    }
    
    private func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }
        
        DispatchQueue.main.async {
            switch event.type {
            case .setup:
                self.syncState = .ready
            case .import:
                self.syncState = .downloading
            case .export:
                self.syncState = .uploading
            @unknown default:
                break
            }
            
            if let error = event.error {
                self.syncState = .error(error.localizedDescription)
            } else if event.endDate != nil {
                self.syncState = .completed
            }
        }
    }
    
    // MARK: - Retry Logic
    
    private func scheduleRetry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            self?.performAutoSync()
        }
    }
    
    // MARK: - Public Interface
    
    func enableSync() {
        persistenceController.enableCloudKitSync()
        setupAutoSync()
    }
    
    func disableSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        persistenceController.disableCloudKitSync()
    }
    
    func clearSyncData() async {
        let context = persistenceController.newBackgroundContext()
        
        await context.perform {
            // Clear sync metadata
            let metadataRequest: NSFetchRequest<SyncMetadata> = SyncMetadata.fetchRequest()
            let metadataObjects = try? context.fetch(metadataRequest)
            metadataObjects?.forEach { context.delete($0) }
            
            // Clear conflict resolutions
            let conflictRequest: NSFetchRequest<ConflictResolution> = ConflictResolution.fetchRequest()
            let conflictObjects = try? context.fetch(conflictRequest)
            conflictObjects?.forEach { context.delete($0) }
            
            // Reset sync flags
            let folderRequest: NSFetchRequest<Folder> = Folder.fetchRequest()
            let folders = try? context.fetch(folderRequest)
            folders?.forEach { folder in
                folder.needsSync = false
                folder.lastSyncDate = nil
                folder.conflictData = nil
            }
            
            let documentRequest: NSFetchRequest<Document> = Document.fetchRequest()
            let documents = try? context.fetch(documentRequest)
            documents?.forEach { document in
                document.needsSync = false
                document.lastSyncDate = nil
                document.conflictData = nil
            }
            
            try? context.save()
        }
        
        await MainActor.run {
            pendingChanges = 0
            lastSyncDate = nil
            conflicts.removeAll()
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        syncTimer?.invalidate()
        networkMonitor.cancel()
        endBackgroundTask()
    }
}

// MARK: - Supporting Types

enum SyncState: Equatable {
    case idle
    case ready
    case syncing
    case uploading
    case downloading
    case completed
    case offline
    case error(String)
    
    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .ready:
            return "Ready"
        case .syncing:
            return "Syncing..."
        case .uploading:
            return "Uploading..."
        case .downloading:
            return "Downloading..."
        case .completed:
            return "Completed"
        case .offline:
            return "Offline"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

struct SyncConflict {
    let id: UUID
    let entityType: String
    let entityID: UUID
    let localData: Data
    let remoteData: Data
    let conflictDate: Date
}

enum ConflictResolutionStrategy: String, CaseIterable {
    case useLocal = "local"
    case useRemote = "remote"
    case merge = "merge"
}

struct FolderConflict: Codable {
    let localName: String
    let remoteName: String
    let localIconName: String?
    let remoteIconName: String?
    let localColorHex: String?
    let remoteColorHex: String?
    let localModifiedAt: Date
    let remoteModifiedAt: Date
    let resolutionStrategy: ConflictResolutionStrategy
}

struct DocumentConflict: Codable {
    let localTitle: String
    let remoteTitle: String
    let localOcrText: String?
    let remoteOcrText: String?
    let localModifiedAt: Date
    let remoteModifiedAt: Date
    let resolutionStrategy: ConflictResolutionStrategy
}

// MARK: - Notifications

extension Notification.Name {
    static let syncCompleted = Notification.Name("SyncCompleted")
    static let syncFailed = Notification.Name("SyncFailed")
    static let conflictDetected = Notification.Name("ConflictDetected")
}

