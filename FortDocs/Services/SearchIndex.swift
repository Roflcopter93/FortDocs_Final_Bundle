import Foundation
import CoreData
import Combine

/// A lightweight search index for FortDocs documents.  This implementation
/// replaces the original eager decryption approach with a privacy preserving
/// encrypted search.  Instead of decrypting every index entry into memory
/// when performing a search, we derive a per‑document search key from the
/// master key and compute deterministic hashes of each search term.  These
/// token hashes are stored in the index and used for lookups, dramatically
/// reducing memory overhead and improving scalability.
final class SearchIndex: ObservableObject {
    static let shared = SearchIndex()

    // Published properties for progress monitoring
    @Published var isIndexing = false
    @Published var indexingProgress: Double = 0.0
    @Published var lastIndexUpdate: Date?
    @Published var indexedDocumentCount = 0

    private let persistenceController = PersistenceController.shared
    private let cryptoVault = CryptoVault.shared
    private var cancellables = Set<AnyCancellable>()

    /// Maximum number of results returned by a search.
    private let maxSearchResults = 100

    private init() {
        // Observe Core Data saves to keep the index up to date
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] notification in
                self?.handleCoreDataChange(notification)
            }
            .store(in: &cancellables)
    }

    // MARK: - Core Data Change Handling

    /// Handles inserts, updates and deletes of Document objects by updating the search index accordingly.
    private func handleCoreDataChange(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        var tasks: [Task<Void, Never>] = []
        if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for object in inserted where object is Document {
                tasks.append(Task { await indexDocument(object as! Document) })
            }
        }
        if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            for object in updated where object is Document {
                tasks.append(Task { await updateDocumentIndex(object as! Document) })
            }
        }
        if let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> {
            for object in deleted where object is Document {
                if let id = (object as! Document).id {
                    tasks.append(Task { await removeDocumentFromIndex(id) })
                }
            }
        }
        Task { await Task.whenAllComplete(tasks) }
    }

    // MARK: - Indexing API

    /// Index a single document by creating hashed token entries for its searchable fields.
    func indexDocument(_ document: Document) async {
        guard let documentID = document.id else { return }
        let context = persistenceController.newBackgroundContext()
        await context.perform {
            // Remove existing entries
            let request: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
            request.predicate = NSPredicate(format: "documentID == %@", documentID as CVarArg)
            if let entries = try? context.fetch(request) {
                entries.forEach { context.delete($0) }
            }
            // Create new entries with hashed tokens
            self.createIndexEntries(for: document, in: context)
            try? context.save()
        }
    }

    /// Update the index for a modified document by removing the old entries and indexing again.
    func updateDocumentIndex(_ document: Document) async {
        await indexDocument(document)
    }

    /// Remove all index entries for a given document identifier.
    func removeDocumentFromIndex(_ documentID: UUID) async {
        let context = persistenceController.newBackgroundContext()
        await context.perform {
            let request: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
            request.predicate = NSPredicate(format: "documentID == %@", documentID as CVarArg)
            if let entries = try? context.fetch(request) {
                entries.forEach { context.delete($0) }
                try? context.save()
            }
        }
    }

    // MARK: - Search API

    /// Perform a search against the local index using encrypted search tokens.  The query is split into
    /// individual terms which are hashed using a derived search key.  Only documents whose index
    /// entries contain all token hashes will be returned.
    func search(_ query: String, filters: SearchFilters = SearchFilters()) async -> SearchResults {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return SearchResults(documents: [], totalCount: 0, query: query)
        }
        let localResults = await searchLocalDatabase(trimmedQuery, filters: filters)
        // Ranking and further filtering could happen here, but for simplicity we preserve the ordering
        return SearchResults(documents: localResults, totalCount: localResults.count, query: query)
    }

    /// Search the local Core Data index for documents matching the provided query.
    private func searchLocalDatabase(_ query: String, filters: SearchFilters) async -> [Document] {
        await withCheckedContinuation { continuation in
            let context = persistenceController.newBackgroundContext()
            context.perform {
                do {
                    // Tokenise the query
                    let searchTerms = query.lowercased().components(separatedBy: CharacterSet.whitespacesAndPunctuationMarks).filter { !$0.isEmpty }
                    // Fetch all index entries
                    let indexRequest: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
                    let indexEntries = try context.fetch(indexRequest)
                    // Determine which documents match all search terms
                    var matchingIDs = Set<UUID>()
                    for entry in indexEntries {
                        // The content now stores hashed tokens separated by spaces
                        let storedTokens = entry.content.components(separatedBy: " ")
                        var matchesAll = true
                        for term in searchTerms {
                            // Derive the same hash for the current term using the document ID as salt
                            guard let hash = try? self.cryptoVault.hashedToken(term, documentID: entry.documentID.uuidString) else {
                                matchesAll = false
                                break
                            }
                            if !storedTokens.contains(hash) {
                                matchesAll = false
                                break
                            }
                        }
                        if matchesAll { matchingIDs.insert(entry.documentID) }
                    }
                    guard !matchingIDs.isEmpty else {
                        continuation.resume(returning: [])
                        return
                    }
                    // Fetch matching Document objects
                    let documentRequest: NSFetchRequest<Document> = Document.fetchRequest()
                    documentRequest.predicate = NSPredicate(format: "id IN %@", matchingIDs as CVarArg)
                    // Apply optional filters
                    var predicates: [NSPredicate] = []
                    if let folder = filters.folder {
                        predicates.append(NSPredicate(format: "folder == %@", folder))
                    }
                    if let range = filters.dateRange {
                        predicates.append(NSPredicate(format: "createdAt >= %@ AND createdAt <= %@", range.start as CVarArg, range.end as CVarArg))
                    }
                    if !filters.documentTypes.isEmpty {
                        let typePreds = filters.documentTypes.map { NSPredicate(format: "mimeType BEGINSWITH %@", $0) }
                        predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: typePreds))
                    }
                    if !predicates.isEmpty {
                        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [documentRequest.predicate!, NSCompoundPredicate(andPredicateWithSubpredicates: predicates)])
                        documentRequest.predicate = combined
                    }
                    documentRequest.fetchLimit = self.maxSearchResults
                    let documents = try context.fetch(documentRequest)
                    continuation.resume(returning: documents)
                } catch {
                    print("Search failed: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Index entry creation

    /// Create index entries for each searchable field of a document.  Each entry stores a space separated
    /// list of hashed tokens rather than an encrypted blob.  The hash is deterministic for a given term
    /// and document ID, enabling efficient matching without revealing the plaintext.
    private func createIndexEntries(for document: Document, in context: NSManagedObjectContext) {
        guard let documentID = document.id else { return }
        // Helper to process a single field
        func addEntry(type: String, text: String) {
            let tokens = text.lowercased().components(separatedBy: CharacterSet.whitespacesAndPunctuationMarks).filter { !$0.isEmpty }
            let hashes = tokens.compactMap { try? cryptoVault.hashedToken($0, documentID: documentID.uuidString) }
            let entry = SearchIndexEntry(context: context)
            entry.id = UUID()
            entry.documentID = documentID
            entry.indexType = type
            entry.content = hashes.joined(separator: " ")
            entry.createdAt = Date()
            entry.modifiedAt = Date()
        }
        if let title = document.title, !title.isEmpty { addEntry(type: "title", text: title) }
        if let ocr = document.ocrText, !ocr.isEmpty { addEntry(type: "ocr", text: ocr) }
        if let folderName = document.folder?.name, !folderName.isEmpty { addEntry(type: "folder", text: folderName) }
        let fileName = document.fileName
        if !fileName.isEmpty { addEntry(type: "filename", text: fileName) }
    }
}

// MARK: - Supporting Types

/// Simple container for search filters.  Additional filter criteria can be added as needed.
struct SearchFilters {
    var folder: Folder? = nil
    var dateRange: (start: Date, end: Date)? = nil
    var documentTypes: [String] = []
}

/// Simple wrapper around search results including total count and original query.
struct SearchResults {
    let documents: [Document]
    let totalCount: Int
    let query: String
}