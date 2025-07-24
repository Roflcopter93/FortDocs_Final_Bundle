import Foundation
import CloudKit
import CoreData
import Combine

class CloudKitService: ObservableObject {
    static let shared = CloudKitService()
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var isCloudKitAvailable = false
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let publicDatabase: CKDatabase
    private var cancellables = Set<AnyCancellable>()
    
    // Subscription IDs for push notifications
    private let documentSubscriptionID = "DocumentChanges"
    private let folderSubscriptionID = "FolderChanges"
    
    private init() {
        container = CKContainer(identifier: "iCloud.com.fortdocs.app")
        privateDatabase = container.privateCloudDatabase
        publicDatabase = container.publicCloudDatabase
        
        checkCloudKitAvailability()
        Task { await setupSubscriptions() }
    }
    
    // MARK: - CloudKit Availability
    
    func checkCloudKitAvailability() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.isCloudKitAvailable = true
                    self?.syncStatus = .ready
                case .noAccount:
                    self?.isCloudKitAvailable = false
                    self?.syncStatus = .noAccount
                case .restricted:
                    self?.isCloudKitAvailable = false
                    self?.syncStatus = .restricted
                case .couldNotDetermine:
                    self?.isCloudKitAvailable = false
                    self?.syncStatus = .error("Could not determine iCloud status")
                case .temporarilyUnavailable:
                    self?.isCloudKitAvailable = false
                    self?.syncStatus = .temporarilyUnavailable
                @unknown default:
                    self?.isCloudKitAvailable = false
                    self?.syncStatus = .error("Unknown iCloud status")
                }
            }
        }
    }
    
    // MARK: - Sync Operations
    
    func performFullSync() async throws {
        guard isCloudKitAvailable else {
            throw CloudKitError.notAvailable
        }
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        do {
            // Sync folders first (dependencies)
            try await syncFolders()
            
            // Then sync documents
            try await syncDocuments()
            
            await MainActor.run {
                syncStatus = .completed
                lastSyncDate = Date()
            }
            
        } catch {
            await MainActor.run {
                syncStatus = .error(error.localizedDescription)
            }
            throw error
        }
    }
    
    private func syncFolders() async throws {
        // Fetch remote folders
        let remoteFolders = try await fetchRemoteFolders()
        
        // Get local folders
        let localFolders = try await fetchLocalFolders()
        
        // Resolve conflicts and merge
        try await mergeFolders(remote: remoteFolders, local: localFolders)
    }
    
    private func syncDocuments() async throws {
        // Fetch remote documents
        let remoteDocuments = try await fetchRemoteDocuments()
        
        // Get local documents
        let localDocuments = try await fetchLocalDocuments()
        
        // Resolve conflicts and merge
        try await mergeDocuments(remote: remoteDocuments, local: localDocuments)
    }
    
    // MARK: - Fetch Operations
    
    private func fetchRemoteFolders() async throws -> [CKRecord] {
        let query = CKQuery(recordType: "Folder", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        
        let (matchResults, _) = try await privateDatabase.records(matching: query)
        
        var records: [CKRecord] = []
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                print("Failed to fetch folder record: \(error)")
            }
        }
        
        return records
    }
    
    private func fetchRemoteDocuments() async throws -> [CKRecord] {
        let query = CKQuery(recordType: "Document", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
        
        let (matchResults, _) = try await privateDatabase.records(matching: query)
        
        var records: [CKRecord] = []
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                print("Failed to fetch document record: \(error)")
            }
        }
        
        return records
    }
    
    private func fetchLocalFolders() async throws -> [Folder] {
        return try await withCheckedThrowingContinuation { continuation in
            let context = PersistenceController.shared.container.viewContext
            context.perform {
                do {
                    let request: NSFetchRequest<Folder> = Folder.fetchRequest()
                    let folders = try context.fetch(request)
                    continuation.resume(returning: folders)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func fetchLocalDocuments() async throws -> [Document] {
        return try await withCheckedThrowingContinuation { continuation in
            let context = PersistenceController.shared.container.viewContext
            context.perform {
                do {
                    let request: NSFetchRequest<Document> = Document.fetchRequest()
                    let documents = try context.fetch(request)
                    continuation.resume(returning: documents)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Merge Operations
    
    private func mergeFolders(remote: [CKRecord], local: [Folder]) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        await context.perform {
            // Create lookup dictionaries
            let remoteDict = Dictionary(uniqueKeysWithValues: remote.map { ($0.recordID.recordName, $0) })
            let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.id?.uuidString ?? "", $0) })
            
            // Process remote records
            for (recordName, record) in remoteDict {
                if let localFolder = localDict[recordName] {
                    // Update existing folder if remote is newer
                    if let remoteModified = record["modifiedAt"] as? Date,
                       let localModified = localFolder.modifiedAt,
                       remoteModified > localModified {
                        self.updateFolder(localFolder, from: record, in: context)
                    }
                } else {
                    // Create new folder from remote record
                    self.createFolder(from: record, in: context)
                }
            }
            
            // Upload local folders not in remote
            var uploadTasks: [Task<Void, Error>] = []
            for (localID, localFolder) in localDict {
                if remoteDict[localID] == nil {
                    uploadTasks.append(Task {
                        try await self.uploadFolder(localFolder)
                    })
                }
            }

            for task in uploadTasks {
                do { try await task.value } catch { print("Upload folder failed: \(error)") }
            }
            
            do {
                try context.save()
            } catch {
                print("Failed to save folder merge: \(error)")
            }
        }
    }
    
    private func mergeDocuments(remote: [CKRecord], local: [Document]) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        await context.perform {
            // Create lookup dictionaries
            let remoteDict = Dictionary(uniqueKeysWithValues: remote.map { ($0.recordID.recordName, $0) })
            let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.id?.uuidString ?? "", $0) })
            
            // Process remote records
            for (recordName, record) in remoteDict {
                if let localDocument = localDict[recordName] {
                    // Update existing document if remote is newer
                    if let remoteModified = record["modifiedAt"] as? Date,
                       let localModified = localDocument.modifiedAt,
                       remoteModified > localModified {
                        self.updateDocument(localDocument, from: record, in: context)
                    }
                } else {
                    // Create new document from remote record
                    self.createDocument(from: record, in: context)
                }
            }
            
            // Upload local documents not in remote
            var docTasks: [Task<Void, Error>] = []
            for (localID, localDocument) in localDict {
                if remoteDict[localID] == nil {
                    docTasks.append(Task {
                        try await self.uploadDocument(localDocument)
                    })
                }
            }

            for task in docTasks {
                do { try await task.value } catch { print("Upload document failed: \(error)") }
            }
            
            do {
                try context.save()
            } catch {
                print("Failed to save document merge: \(error)")
            }
        }
    }
    
    // MARK: - Record Conversion
    
    private func createFolder(from record: CKRecord, in context: NSManagedObjectContext) {
        let folder = Folder(context: context)
        updateFolder(folder, from: record, in: context)
    }
    
    private func updateFolder(_ folder: Folder, from record: CKRecord, in context: NSManagedObjectContext) {
        folder.id = UUID(uuidString: record.recordID.recordName)
        folder.name = record["name"] as? String ?? ""
        folder.iconName = record["iconName"] as? String
        folder.colorHex = record["colorHex"] as? String
        folder.sortOrder = record["sortOrder"] as? Int32 ?? 0
        folder.createdAt = record["createdAt"] as? Date ?? Date()
        folder.modifiedAt = record["modifiedAt"] as? Date ?? Date()
        
        // Handle parent folder reference
        if let parentReference = record["parentFolder"] as? CKRecord.Reference {
            let parentID = UUID(uuidString: parentReference.recordID.recordName)
            let parentRequest: NSFetchRequest<Folder> = Folder.fetchRequest()
            parentRequest.predicate = NSPredicate(format: "id == %@", parentID! as CVarArg)
            
            if let parentFolder = try? context.fetch(parentRequest).first {
                folder.parentFolder = parentFolder
            }
        }
    }
    
    private func createDocument(from record: CKRecord, in context: NSManagedObjectContext) {
        let document = Document(context: context)
        updateDocument(document, from: record, in: context)
    }
    
    private func updateDocument(_ document: Document, from record: CKRecord, in context: NSManagedObjectContext) {
        document.id = UUID(uuidString: record.recordID.recordName)
        document.title = record["title"] as? String ?? ""
        document.fileName = record["fileName"] as? String ?? ""
        document.mimeType = record["mimeType"] as? String ?? ""
        document.fileSize = record["fileSize"] as? Int64 ?? 0
        document.ocrText = record["ocrText"] as? String
        document.createdAt = record["createdAt"] as? Date ?? Date()
        document.modifiedAt = record["modifiedAt"] as? Date ?? Date()
        
        // Handle folder reference
        if let folderReference = record["folder"] as? CKRecord.Reference {
            let folderID = UUID(uuidString: folderReference.recordID.recordName)
            let folderRequest: NSFetchRequest<Folder> = Folder.fetchRequest()
            folderRequest.predicate = NSPredicate(format: "id == %@", folderID! as CVarArg)
            
            if let folder = try? context.fetch(folderRequest).first {
                document.folder = folder
            }
        }
        
        // Handle file asset
        if let fileAsset = record["fileAsset"] as? CKAsset {
            Task {
                await self.downloadDocumentFile(from: fileAsset, for: document)
            }
        }
    }
    
    // MARK: - Upload Operations
    
    func uploadFolder(_ folder: Folder) async throws {
        guard let folderID = folder.id else { return }
        
        let record = CKRecord(recordType: "Folder", recordID: CKRecord.ID(recordName: folderID.uuidString))
        
        record["name"] = folder.name
        record["iconName"] = folder.iconName
        record["colorHex"] = folder.colorHex
        record["sortOrder"] = folder.sortOrder
        record["createdAt"] = folder.createdAt
        record["modifiedAt"] = folder.modifiedAt
        
        // Handle parent folder reference
        if let parentFolder = folder.parentFolder,
           let parentID = parentFolder.id {
            let parentReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: parentID.uuidString),
                action: .deleteSelf
            )
            record["parentFolder"] = parentReference
        }
        
        try await privateDatabase.save(record)
    }
    
    func uploadDocument(_ document: Document) async throws {
        guard let documentID = document.id else { return }
        
        let record = CKRecord(recordType: "Document", recordID: CKRecord.ID(recordName: documentID.uuidString))
        
        record["title"] = document.title
        record["fileName"] = document.fileName
        record["mimeType"] = document.mimeType
        record["fileSize"] = document.fileSize
        record["ocrText"] = document.ocrText
        record["createdAt"] = document.createdAt
        record["modifiedAt"] = document.modifiedAt
        
        // Handle folder reference
        if let folder = document.folder,
           let folderID = folder.id {
            let folderReference = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: folderID.uuidString),
                action: .deleteSelf
            )
            record["folder"] = folderReference
        }
        
        // Upload file asset using encrypted file path
        let fileURL = URL(fileURLWithPath: document.encryptedFilePath)
        let asset = CKAsset(fileURL: fileURL)
        record["fileAsset"] = asset
        
        try await privateDatabase.save(record)
    }
    
    // MARK: - File Operations
    
    private func downloadDocumentFile(from asset: CKAsset, for document: Document) async {
        guard let assetURL = asset.fileURL else { return }
        
        do {
            let data = try Data(contentsOf: assetURL)
            
            // Create local file URL
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let localURL = documentsURL.appendingPathComponent(document.fileName)
            
            // Write encrypted file
            try CryptoVault.shared.encryptData(data, to: localURL)
            
            // Update document with local path
            await MainActor.run {
                document.encryptedFilePath = localURL.path
            }
            
        } catch {
            print("Failed to download document file: \(error)")
        }
    }
    
    // MARK: - Subscriptions
    
    private func setupSubscriptions() async {
        do {
            try await createDocumentSubscription()
            try await createFolderSubscription()
        } catch {
            print("Failed to set up subscriptions: \(error)")
        }
    }
    
    private func createDocumentSubscription() async throws {
        let subscription = CKQuerySubscription(
            recordType: "Document",
            predicate: NSPredicate(value: true),
            subscriptionID: documentSubscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        try await privateDatabase.save(subscription)
    }
    
    private func createFolderSubscription() async throws {
        let subscription = CKQuerySubscription(
            recordType: "Folder",
            predicate: NSPredicate(value: true),
            subscriptionID: folderSubscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        try await privateDatabase.save(subscription)
    }
    
    // MARK: - Push Notification Handling
    
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return
        }
        
        switch notification.notificationType {
        case .query:
            if let queryNotification = notification as? CKQueryNotification {
                await handleQueryNotification(queryNotification)
            }
        case .database:
            // Handle database changes
            try? await performFullSync()
        default:
            break
        }
    }
    
    private func handleQueryNotification(_ notification: CKQueryNotification) async {
        guard let recordID = notification.recordID else { return }
        
        switch notification.queryNotificationReason {
        case .recordCreated, .recordUpdated:
            // Fetch and update the specific record
            do {
                let record = try await privateDatabase.record(for: recordID)
                await updateLocalRecord(record)
            } catch {
                print("Failed to fetch updated record: \(error)")
            }
            
        case .recordDeleted:
            // Delete the local record
            await deleteLocalRecord(recordID)
            
        @unknown default:
            break
        }
    }
    
    private func updateLocalRecord(_ record: CKRecord) async {
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        await context.perform {
            switch record.recordType {
            case "Folder":
                if let folder = self.findLocalFolder(recordID: record.recordID, in: context) {
                    self.updateFolder(folder, from: record, in: context)
                } else {
                    self.createFolder(from: record, in: context)
                }
                
            case "Document":
                if let document = self.findLocalDocument(recordID: record.recordID, in: context) {
                    self.updateDocument(document, from: record, in: context)
                } else {
                    self.createDocument(from: record, in: context)
                }
                
            default:
                break
            }
            
            do {
                try context.save()
            } catch {
                print("Failed to save updated record: \(error)")
            }
        }
    }
    
    private func deleteLocalRecord(_ recordID: CKRecord.ID) async {
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        await context.perform {
            let id = UUID(uuidString: recordID.recordName)
            
            // Try to find and delete folder
            let folderRequest: NSFetchRequest<Folder> = Folder.fetchRequest()
            folderRequest.predicate = NSPredicate(format: "id == %@", id! as CVarArg)
            
            if let folder = try? context.fetch(folderRequest).first {
                context.delete(folder)
            }
            
            // Try to find and delete document
            let documentRequest: NSFetchRequest<Document> = Document.fetchRequest()
            documentRequest.predicate = NSPredicate(format: "id == %@", id! as CVarArg)
            
            if let document = try? context.fetch(documentRequest).first {
                context.delete(document)
            }
            
            do {
                try context.save()
            } catch {
                print("Failed to delete record: \(error)")
            }
        }
    }
    
    private func findLocalFolder(recordID: CKRecord.ID, in context: NSManagedObjectContext) -> Folder? {
        let id = UUID(uuidString: recordID.recordName)
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id! as CVarArg)
        
        return try? context.fetch(request).first
    }
    
    private func findLocalDocument(recordID: CKRecord.ID, in context: NSManagedObjectContext) -> Document? {
        let id = UUID(uuidString: recordID.recordName)
        let request: NSFetchRequest<Document> = Document.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id! as CVarArg)
        
        return try? context.fetch(request).first
    }
    
    // MARK: - Conflict Resolution
    
    private func resolveConflict<T: NSManagedObject>(
        local: T,
        remote: CKRecord,
        localModified: Date,
        remoteModified: Date
    ) -> ConflictResolution {
        // Simple last-writer-wins strategy
        if remoteModified > localModified {
            return .useRemote
        } else if localModified > remoteModified {
            return .useLocal
        } else {
            // Same timestamp, prefer remote to maintain consistency
            return .useRemote
        }
    }
}

// MARK: - Supporting Types

enum SyncStatus: Equatable {
    case idle
    case ready
    case syncing
    case completed
    case noAccount
    case restricted
    case temporarilyUnavailable
    case error(String)
    
    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .ready:
            return "Ready to sync"
        case .syncing:
            return "Syncing..."
        case .completed:
            return "Sync completed"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "iCloud restricted"
        case .temporarilyUnavailable:
            return "iCloud temporarily unavailable"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

enum ConflictResolution {
    case useLocal
    case useRemote
    case merge
}

enum CloudKitError: LocalizedError {
    case notAvailable
    case syncFailed
    case uploadFailed
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "iCloud is not available"
        case .syncFailed:
            return "Sync operation failed"
        case .uploadFailed:
            return "Failed to upload to iCloud"
        case .downloadFailed:
            return "Failed to download from iCloud"
        }
    }
}

