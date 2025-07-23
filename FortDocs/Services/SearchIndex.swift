import Foundation
import CoreSpotlight
import MobileCoreServices
import CoreData
import Combine

class SearchIndex: ObservableObject {
    static let shared = SearchIndex()
    
    @Published var isIndexing = false
    @Published var indexingProgress: Double = 0.0
    @Published var lastIndexUpdate: Date?
    @Published var indexedDocumentCount = 0
    
    private let persistenceController = PersistenceController.shared
    private let cryptoVault = CryptoVault.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Search configuration
    private let maxSearchResults = 100
    private let searchTimeout: TimeInterval = 5.0
    private let indexBatchSize = 50
    
    private init() {
        setupCoreDataObservers()
        setupInitialIndex()
    }
    
    // MARK: - Core Data Observers
    
    private func setupCoreDataObservers() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] notification in
                self?.handleCoreDataChange(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleCoreDataChange(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        
        // Handle inserted documents
        if let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for object in insertedObjects {
                if let document = object as? Document {
                    Task {
                        await indexDocument(document)
                    }
                }
            }
        }
        
        // Handle updated documents
        if let updatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            for object in updatedObjects {
                if let document = object as? Document {
                    Task {
                        await updateDocumentIndex(document)
                    }
                }
            }
        }
        
        // Handle deleted documents
        if let deletedObjects = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> {
            for object in deletedObjects {
                if let document = object as? Document,
                   let documentID = document.id {
                    Task {
                        await removeDocumentFromIndex(documentID)
                    }
                }
            }
        }
    }
    
    // MARK: - Initial Index Setup
    
    private func setupInitialIndex() {
        Task {
            await buildInitialIndex()
        }
    }
    
    private func buildInitialIndex() async {
        await MainActor.run {
            isIndexing = true
            indexingProgress = 0.0
        }
        
        let context = persistenceController.newBackgroundContext()
        
        await context.perform {
            do {
                let request: NSFetchRequest<Document> = Document.fetchRequest()
                let documents = try context.fetch(request)
                let totalDocuments = documents.count
                
                for (index, document) in documents.enumerated() {
                    await self.indexDocument(document)
                    
                    let progress = Double(index + 1) / Double(totalDocuments)
                    await MainActor.run {
                        self.indexingProgress = progress
                    }
                }
                
                await MainActor.run {
                    self.isIndexing = false
                    self.indexingProgress = 1.0
                    self.lastIndexUpdate = Date()
                    self.indexedDocumentCount = totalDocuments
                }
                
            } catch {
                print("Failed to build initial index: \(error)")
                await MainActor.run {
                    self.isIndexing = false
                }
            }
        }
    }
    
    // MARK: - Document Indexing
    
    func indexDocument(_ document: Document) async {
        guard let documentID = document.id else { return }
        
        // Create Core Spotlight item
        let searchableItem = createSearchableItem(for: document)
        
        // Index in Core Spotlight
        await indexInCoreSpotlight([searchableItem])
        
        // Index in local search database
        await indexInLocalDatabase(document)
        
        print("Indexed document: \(document.title ?? "Untitled")")
    }
    
    func updateDocumentIndex(_ document: Document) async {
        // Remove old index entry
        if let documentID = document.id {
            await removeDocumentFromIndex(documentID)
        }
        
        // Add updated index entry
        await indexDocument(document)
    }
    
    func removeDocumentFromIndex(_ documentID: UUID) async {
        // Remove from Core Spotlight
        let identifier = "document-\(documentID.uuidString)"
        await removeFromCoreSpotlight([identifier])
        
        // Remove from local database
        await removeFromLocalDatabase(documentID)
        
        print("Removed document from index: \(documentID)")
    }
    
    // MARK: - Core Spotlight Integration
    
    private func createSearchableItem(for document: Document) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(itemContentType: kUTTypeItem as String)
        
        // Basic attributes
        attributeSet.title = document.title
        attributeSet.displayName = document.title
        attributeSet.contentDescription = generateContentDescription(for: document)
        
        // Content
        if let ocrText = document.ocrText, !ocrText.isEmpty {
            attributeSet.textContent = ocrText
        }
        
        // Metadata
        attributeSet.contentCreationDate = document.createdAt
        attributeSet.contentModificationDate = document.modifiedAt
        attributeSet.fileSize = NSNumber(value: document.fileSize)
        
        // Document type
        attributeSet.contentType = document.mimeType
        attributeSet.kind = getDocumentKind(from: document.mimeType)
        
        // Folder information
        if let folder = document.folder {
            attributeSet.path = folder.name
            attributeSet.containerTitle = folder.name
            attributeSet.containerDisplayName = folder.name
        }
        
        // Keywords from OCR and metadata
        attributeSet.keywords = extractKeywords(from: document)
        
        // Thumbnail
        if let thumbnailData = document.thumbnailData {
            attributeSet.thumbnailData = thumbnailData
        }
        
        // Custom attributes for filtering
        attributeSet.setValue(document.folder?.name, forCustomKey: CSCustomAttributeKey(keyName: "folderName")!)
        attributeSet.setValue(document.mimeType, forCustomKey: CSCustomAttributeKey(keyName: "documentType")!)
        
        // Security - mark as encrypted
        attributeSet.setValue(document.isEncrypted, forCustomKey: CSCustomAttributeKey(keyName: "isEncrypted")!)
        
        let identifier = "document-\(document.id!.uuidString)"
        let searchableItem = CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: "com.fortdocs.documents",
            attributeSet: attributeSet
        )
        
        return searchableItem
    }
    
    private func generateContentDescription(for document: Document) -> String {
        var description = ""
        
        if let folder = document.folder {
            description += "In \(folder.name)"
        }
        
        if let ocrText = document.ocrText, !ocrText.isEmpty {
            let preview = String(ocrText.prefix(200))
            if !description.isEmpty {
                description += " • "
            }
            description += preview
            if ocrText.count > 200 {
                description += "..."
            }
        }
        
        return description
    }
    
    private func getDocumentKind(from mimeType: String) -> String {
        switch mimeType.lowercased() {
        case let type where type.hasPrefix("image/"):
            return "Image"
        case "application/pdf":
            return "PDF Document"
        case let type where type.hasPrefix("text/"):
            return "Text Document"
        default:
            return "Document"
        }
    }
    
    private func extractKeywords(from document: Document) -> [String] {
        var keywords: [String] = []
        
        // Add document title words
        if let title = document.title {
            keywords.append(contentsOf: title.components(separatedBy: .whitespacesAndPunctuationMarks))
        }
        
        // Add folder name
        if let folderName = document.folder?.name {
            keywords.append(folderName)
        }
        
        // Add OCR text keywords (most frequent words)
        if let ocrText = document.ocrText {
            let ocrKeywords = extractFrequentWords(from: ocrText, limit: 20)
            keywords.append(contentsOf: ocrKeywords)
        }
        
        // Add file type
        keywords.append(getDocumentKind(from: document.mimeType))
        
        // Clean and deduplicate
        return keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndPunctuationMarks) }
            .filter { !$0.isEmpty && $0.count > 2 }
            .removingDuplicates()
    }
    
    private func extractFrequentWords(from text: String, limit: Int) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndPunctuationMarks)
            .filter { $0.count > 3 } // Only words longer than 3 characters
        
        let wordCounts = Dictionary(grouping: words, by: { $0 })
            .mapValues { $0.count }
        
        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
    
    private func indexInCoreSpotlight(_ items: [CSSearchableItem]) async {
        do {
            try await CSSearchableIndex.default().indexSearchableItems(items)
        } catch {
            print("Failed to index in Core Spotlight: \(error)")
        }
    }
    
    private func removeFromCoreSpotlight(_ identifiers: [String]) async {
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers)
        } catch {
            print("Failed to remove from Core Spotlight: \(error)")
        }
    }
    
    // MARK: - Local Database Indexing
    
    private func indexInLocalDatabase(_ document: Document) async {
        let context = persistenceController.newBackgroundContext()
        
        await context.perform {
            // Remove existing entries for this document
            let deleteRequest: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
            deleteRequest.predicate = NSPredicate(format: "documentID == %@", document.id! as CVarArg)
            
            if let existingEntries = try? context.fetch(deleteRequest) {
                existingEntries.forEach { context.delete($0) }
            }
            
            // Create new index entries
            self.createIndexEntries(for: document, in: context)
            
            do {
                try context.save()
            } catch {
                print("Failed to save search index: \(error)")
            }
        }
    }
    
    private func createIndexEntries(for document: Document, in context: NSManagedObjectContext) {
        guard let documentID = document.id else { return }
        
        // Title index entry
        if let title = document.title, !title.isEmpty {
            let titleEntry = SearchIndexEntry(context: context)
            titleEntry.id = UUID()
            titleEntry.documentID = documentID
            titleEntry.indexType = "title"
            titleEntry.content = title.lowercased()
            titleEntry.createdAt = Date()
            titleEntry.modifiedAt = Date()
        }
        
        // OCR text index entry
        if let ocrText = document.ocrText, !ocrText.isEmpty {
            let ocrEntry = SearchIndexEntry(context: context)
            ocrEntry.id = UUID()
            ocrEntry.documentID = documentID
            ocrEntry.indexType = "ocr"
            ocrEntry.content = ocrText.lowercased()
            ocrEntry.createdAt = Date()
            ocrEntry.modifiedAt = Date()
        }
        
        // Folder index entry
        if let folderName = document.folder?.name, !folderName.isEmpty {
            let folderEntry = SearchIndexEntry(context: context)
            folderEntry.id = UUID()
            folderEntry.documentID = documentID
            folderEntry.indexType = "folder"
            folderEntry.content = folderName.lowercased()
            folderEntry.createdAt = Date()
            folderEntry.modifiedAt = Date()
        }
        
        // File name index entry
        if !document.fileName.isEmpty {
            let fileNameEntry = SearchIndexEntry(context: context)
            fileNameEntry.id = UUID()
            fileNameEntry.documentID = documentID
            fileNameEntry.indexType = "filename"
            fileNameEntry.content = document.fileName.lowercased()
            fileNameEntry.createdAt = Date()
            fileNameEntry.modifiedAt = Date()
        }
    }
    
    private func removeFromLocalDatabase(_ documentID: UUID) async {
        let context = persistenceController.newBackgroundContext()
        
        await context.perform {
            let request: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
            request.predicate = NSPredicate(format: "documentID == %@", documentID as CVarArg)
            
            if let entries = try? context.fetch(request) {
                entries.forEach { context.delete($0) }
                
                do {
                    try context.save()
                } catch {
                    print("Failed to remove from local search index: \(error)")
                }
            }
        }
    }
    
    // MARK: - Search Operations
    
    func search(_ query: String, filters: SearchFilters = SearchFilters()) async -> SearchResults {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return SearchResults(documents: [], totalCount: 0, query: query)
        }
        
        // Perform local database search
        let localResults = await searchLocalDatabase(trimmedQuery, filters: filters)
        
        // Combine and rank results
        let rankedResults = rankSearchResults(localResults, query: trimmedQuery)
        
        return SearchResults(
            documents: rankedResults,
            totalCount: rankedResults.count,
            query: query
        )
    }
    
    private func searchLocalDatabase(_ query: String, filters: SearchFilters) async -> [Document] {
        return await withCheckedContinuation { continuation in
            let context = persistenceController.newBackgroundContext()
            
            context.perform {
                do {
                    let searchTerms = query.lowercased().components(separatedBy: .whitespacesAndPunctuationMarks)
                        .filter { !$0.isEmpty }
                    
                    var predicates: [NSPredicate] = []
                    
                    // Build search predicates for each term
                    for term in searchTerms {
                        let termPredicates = [
                            NSPredicate(format: "content CONTAINS[cd] %@", term)
                        ]
                        
                        let termPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: termPredicates)
                        predicates.append(termPredicate)
                    }
                    
                    let searchPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                    
                    // Search index entries
                    let indexRequest: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
                    indexRequest.predicate = searchPredicate
                    
                    let indexEntries = try context.fetch(indexRequest)
                    let documentIDs = Set(indexEntries.map { $0.documentID })
                    
                    // Fetch matching documents
                    let documentRequest: NSFetchRequest<Document> = Document.fetchRequest()
                    documentRequest.predicate = NSPredicate(format: "id IN %@", documentIDs)
                    
                    // Apply filters
                    var filterPredicates: [NSPredicate] = []
                    
                    if let folderFilter = filters.folder {
                        filterPredicates.append(NSPredicate(format: "folder == %@", folderFilter))
                    }
                    
                    if let dateRange = filters.dateRange {
                        filterPredicates.append(NSPredicate(format: "createdAt >= %@ AND createdAt <= %@", dateRange.start as CVarArg, dateRange.end as CVarArg))
                    }
                    
                    if !filters.documentTypes.isEmpty {
                        let typePredicates = filters.documentTypes.map { type in
                            NSPredicate(format: "mimeType BEGINSWITH %@", type)
                        }
                        filterPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates))
                    }
                    
                    if !filterPredicates.isEmpty {
                        let combinedFilters = NSCompoundPredicate(andPredicateWithSubpredicates: filterPredicates)
                        documentRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [documentRequest.predicate!, combinedFilters])
                    }
                    
                    // Sort by relevance (will be re-ranked later)
                    documentRequest.sortDescriptors = [
                        NSSortDescriptor(keyPath: \Document.modifiedAt, ascending: false)
                    ]
                    
                    documentRequest.fetchLimit = maxSearchResults
                    
                    let documents = try context.fetch(documentRequest)
                    continuation.resume(returning: documents)
                    
                } catch {
                    print("Search failed: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func rankSearchResults(_ documents: [Document], query: String) -> [Document] {
        let queryTerms = query.lowercased().components(separatedBy: .whitespacesAndPunctuationMarks)
            .filter { !$0.isEmpty }
        
        let scoredDocuments = documents.map { document in
            let score = calculateRelevanceScore(document, queryTerms: queryTerms)
            return (document, score)
        }
        
        return scoredDocuments
            .sorted { $0.1 > $1.1 } // Sort by score descending
            .map { $0.0 } // Extract documents
    }
    
    private func calculateRelevanceScore(_ document: Document, queryTerms: [String]) -> Double {
        var score: Double = 0
        
        let title = document.title?.lowercased() ?? ""
        let ocrText = document.ocrText?.lowercased() ?? ""
        let fileName = document.fileName.lowercased()
        
        for term in queryTerms {
            // Title matches get highest score
            if title.contains(term) {
                score += 10
                if title.hasPrefix(term) {
                    score += 5 // Bonus for prefix match
                }
            }
            
            // File name matches get high score
            if fileName.contains(term) {
                score += 8
                if fileName.hasPrefix(term) {
                    score += 3
                }
            }
            
            // OCR text matches get medium score
            let ocrMatches = ocrText.components(separatedBy: term).count - 1
            score += Double(ocrMatches) * 2
            
            // Folder name matches get low score
            if let folderName = document.folder?.name?.lowercased(), folderName.contains(term) {
                score += 1
            }
        }
        
        // Boost recent documents
        if let modifiedAt = document.modifiedAt {
            let daysSinceModified = Date().timeIntervalSince(modifiedAt) / (24 * 60 * 60)
            if daysSinceModified < 7 {
                score += 2 // Recent documents get bonus
            }
        }
        
        return score
    }
    
    // MARK: - Search Suggestions
    
    func getSearchSuggestions(for query: String, limit: Int = 10) async -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedQuery.count >= 2 else { return [] }
        
        return await withCheckedContinuation { continuation in
            let context = persistenceController.newBackgroundContext()
            
            context.perform {
                do {
                    let request: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
                    request.predicate = NSPredicate(format: "content BEGINSWITH %@", trimmedQuery)
                    request.fetchLimit = limit * 2 // Fetch more to account for duplicates
                    
                    let entries = try context.fetch(request)
                    
                    let suggestions = entries
                        .compactMap { entry in
                            // Extract the word that starts with the query
                            let words = entry.content.components(separatedBy: .whitespacesAndPunctuationMarks)
                            return words.first { $0.hasPrefix(trimmedQuery) && $0.count > trimmedQuery.count }
                        }
                        .removingDuplicates()
                        .prefix(limit)
                        .map { String($0) }
                    
                    continuation.resume(returning: Array(suggestions))
                    
                } catch {
                    print("Failed to get search suggestions: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    // MARK: - Index Management
    
    func rebuildIndex() async {
        await clearIndex()
        await buildInitialIndex()
    }
    
    func clearIndex() async {
        // Clear Core Spotlight index
        do {
            try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["com.fortdocs.documents"])
        } catch {
            print("Failed to clear Core Spotlight index: \(error)")
        }
        
        // Clear local database index
        let context = persistenceController.newBackgroundContext()
        await context.perform {
            let request: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
            
            if let entries = try? context.fetch(request) {
                entries.forEach { context.delete($0) }
                
                do {
                    try context.save()
                } catch {
                    print("Failed to clear local search index: \(error)")
                }
            }
        }
        
        await MainActor.run {
            indexedDocumentCount = 0
            lastIndexUpdate = nil
        }
    }
    
    func getIndexStatistics() async -> IndexStatistics {
        return await withCheckedContinuation { continuation in
            let context = persistenceController.newBackgroundContext()
            
            context.perform {
                do {
                    let documentRequest: NSFetchRequest<Document> = Document.fetchRequest()
                    let totalDocuments = try context.count(for: documentRequest)
                    
                    let indexRequest: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
                    let totalIndexEntries = try context.count(for: indexRequest)
                    
                    let stats = IndexStatistics(
                        totalDocuments: totalDocuments,
                        indexedDocuments: self.indexedDocumentCount,
                        totalIndexEntries: totalIndexEntries,
                        lastUpdate: self.lastIndexUpdate
                    )
                    
                    continuation.resume(returning: stats)
                    
                } catch {
                    print("Failed to get index statistics: \(error)")
                    continuation.resume(returning: IndexStatistics(totalDocuments: 0, indexedDocuments: 0, totalIndexEntries: 0, lastUpdate: nil))
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct SearchFilters {
    var folder: Folder?
    var dateRange: DateRange?
    var documentTypes: [String] = []
    var sortBy: SearchSortOption = .relevance
    
    struct DateRange {
        let start: Date
        let end: Date
    }
}

enum SearchSortOption {
    case relevance
    case dateCreated
    case dateModified
    case title
    case fileSize
}

struct SearchResults {
    let documents: [Document]
    let totalCount: Int
    let query: String
}

struct IndexStatistics {
    let totalDocuments: Int
    let indexedDocuments: Int
    let totalIndexEntries: Int
    let lastUpdate: Date?
}moveDocumentFromIndex(document)
        indexDocument(document)
    }
    
    func clearAllIndexes() {
        // This will be fully implemented in phase 6
        print("Clearing all search indexes")
        
        CSSearchableIndex.default().deleteAllSearchableItems { error in
            if let error = error {
                print("Failed to clear search indexes: \(error)")
            }
        }
    }
    
    func reindexAllDocuments(context: NSManagedObjectContext) {
        // This will be fully implemented in phase 6
        print("Reindexing all documents")
        
        let request = Document.fetchAll()
        
        do {
            let documents = try context.fetch(request)
            
            for document in documents {
                indexDocument(document)
            }
        } catch {
            print("Failed to reindex documents: \(error)")
        }
    }
}

