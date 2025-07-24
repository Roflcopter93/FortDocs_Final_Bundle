import XCTest
import CoreData
import CoreSpotlight
@testable import FortDocs

final class SearchIndexTests: XCTestCase {
    
    var searchIndex: SearchIndex!
    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!
    var testDocuments: [Document] = []
    var testFolders: [Folder] = []
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Use in-memory store for testing
        persistenceController = createInMemoryPersistenceController()
        context = persistenceController.container.viewContext
        searchIndex = SearchIndex.shared
        
        // Create test data
        try createTestData()
    }
    
    override func tearDownWithError() throws {
        // Clean up test data
        testDocuments.removeAll()
        testFolders.removeAll()
        
        // Clear search index
        await searchIndex.clearIndex()
        
        searchIndex = nil
        persistenceController = nil
        context = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Test Data Creation
    
    func createInMemoryPersistenceController() -> PersistenceController {
        let controller = PersistenceController()
        
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        
        controller.container.persistentStoreDescriptions = [description]
        
        controller.container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load in-memory store: \(error)")
            }
        }
        
        return controller
    }
    
    func createTestData() throws {
        // Create test folders
        let documentsFolder = Folder(context: context)
        documentsFolder.id = UUID()
        documentsFolder.name = "Documents"
        documentsFolder.iconName = "folder.fill"
        documentsFolder.colorHex = "#007AFF"
        documentsFolder.createdAt = Date()
        documentsFolder.modifiedAt = Date()
        documentsFolder.sortOrder = 0
        testFolders.append(documentsFolder)
        
        let invoicesFolder = Folder(context: context)
        invoicesFolder.id = UUID()
        invoicesFolder.name = "Invoices"
        invoicesFolder.iconName = "doc.text.fill"
        invoicesFolder.colorHex = "#FF9500"
        invoicesFolder.createdAt = Date()
        invoicesFolder.modifiedAt = Date()
        invoicesFolder.sortOrder = 1
        testFolders.append(invoicesFolder)
        
        // Create test documents
        let testCases = [
            ("Meeting Notes", "meeting_notes.txt", "text/plain", "Team meeting notes from January 15th. Discussed project timeline and budget allocation.", documentsFolder),
            ("Invoice 2024-001", "invoice_001.pdf", "application/pdf", "Invoice from ABC Company for consulting services. Amount: $2,500. Due date: February 1st, 2024.", invoicesFolder),
            ("Project Proposal", "proposal.pdf", "application/pdf", "Comprehensive project proposal for mobile app development. Includes timeline, budget, and technical specifications.", documentsFolder),
            ("Receipt Starbucks", "receipt_starbucks.jpg", "image/jpeg", "Coffee purchase receipt from Starbucks. Date: January 20th, 2024. Amount: $4.75.", invoicesFolder),
            ("Contract Agreement", "contract.pdf", "application/pdf", "Service agreement between FortDocs Inc. and client. Effective date: January 1st, 2024.", documentsFolder)
        ]
        
        for (title, fileName, mimeType, ocrText, folder) in testCases {
            let document = Document(context: context)
            document.id = UUID()
            document.title = title
            document.fileName = fileName
            document.mimeType = mimeType
            document.ocrText = ocrText
            document.folder = folder
            document.createdAt = Date()
            document.modifiedAt = Date()
            document.fileSize = Int64.random(in: 1024...1048576) // 1KB to 1MB
            document.isEncrypted = true
            document.encryptedFilePath = "/encrypted/\(fileName)"
            testDocuments.append(document)
        }
        
        try context.save()
    }
    
    // MARK: - Document Indexing Tests
    
    func testIndexDocument() async throws {
        let document = testDocuments.first!
        
        await searchIndex.indexDocument(document)
        
        // Verify document was indexed
        let stats = await searchIndex.getIndexStatistics()
        XCTAssertGreaterThan(stats.indexedDocuments, 0)
    }
    
    func testIndexMultipleDocuments() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let stats = await searchIndex.getIndexStatistics()
        XCTAssertEqual(stats.indexedDocuments, testDocuments.count)
    }
    
    func testUpdateDocumentIndex() async throws {
        let document = testDocuments.first!
        
        // Index document initially
        await searchIndex.indexDocument(document)
        
        // Update document
        document.title = "Updated Meeting Notes"
        document.ocrText = "Updated content with new information about project status."
        try context.save()
        
        // Update index
        await searchIndex.updateDocumentIndex(document)
        
        // Search for updated content
        let results = await searchIndex.search("Updated")
        XCTAssertGreaterThan(results.documents.count, 0)
        XCTAssertEqual(results.documents.first?.title, "Updated Meeting Notes")
    }
    
    func testRemoveDocumentFromIndex() async throws {
        let document = testDocuments.first!
        let documentID = document.id!
        
        // Index document
        await searchIndex.indexDocument(document)
        
        // Verify it's indexed
        let initialResults = await searchIndex.search(document.title!)
        XCTAssertGreaterThan(initialResults.documents.count, 0)
        
        // Remove from index
        await searchIndex.removeDocumentFromIndex(documentID)
        
        // Verify it's no longer found
        let finalResults = await searchIndex.search(document.title!)
        XCTAssertEqual(finalResults.documents.count, 0)
    }
    
    // MARK: - Search Tests
    
    func testBasicSearch() async throws {
        // Index all test documents
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        // Search for "meeting"
        let results = await searchIndex.search("meeting")
        
        XCTAssertGreaterThan(results.documents.count, 0)
        XCTAssertTrue(results.documents.contains { $0.title?.lowercased().contains("meeting") == true })
    }

    func testIndexedContentEncrypted() async throws {
        let document = testDocuments.first!
        await searchIndex.indexDocument(document)

        let request: NSFetchRequest<SearchIndexEntry> = SearchIndexEntry.fetchRequest()
        request.predicate = NSPredicate(format: "documentID == %@", document.id! as CVarArg)

        let entries = try context.fetch(request)
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            XCTAssertFalse(entry.content.contains(document.title!.lowercased()))
        }
    }
    
    func testSearchInTitle() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let results = await searchIndex.search("Invoice")
        
        XCTAssertGreaterThan(results.documents.count, 0)
        XCTAssertTrue(results.documents.contains { $0.title?.contains("Invoice") == true })
    }
    
    func testSearchInOCRText() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let results = await searchIndex.search("consulting services")
        
        XCTAssertGreaterThan(results.documents.count, 0)
        XCTAssertTrue(results.documents.contains { $0.ocrText?.contains("consulting services") == true })
    }
    
    func testSearchInFileName() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let results = await searchIndex.search("proposal.pdf")
        
        XCTAssertGreaterThan(results.documents.count, 0)
        XCTAssertTrue(results.documents.contains { $0.fileName.contains("proposal.pdf") })
    }
    
    func testMultiTermSearch() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let results = await searchIndex.search("project timeline")
        
        XCTAssertGreaterThan(results.documents.count, 0)
        // Should find documents containing both "project" and "timeline"
    }
    
    func testCaseInsensitiveSearch() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let upperResults = await searchIndex.search("INVOICE")
        let lowerResults = await searchIndex.search("invoice")
        let mixedResults = await searchIndex.search("Invoice")
        
        XCTAssertEqual(upperResults.documents.count, lowerResults.documents.count)
        XCTAssertEqual(lowerResults.documents.count, mixedResults.documents.count)
    }
    
    func testEmptySearch() async throws {
        let results = await searchIndex.search("")
        XCTAssertEqual(results.documents.count, 0)
        
        let whitespaceResults = await searchIndex.search("   ")
        XCTAssertEqual(whitespaceResults.documents.count, 0)
    }
    
    // MARK: - Search Filters Tests
    
    func testSearchWithFolderFilter() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let invoicesFolder = testFolders.first { $0.name == "Invoices" }!
        var filters = SearchFilters()
        filters.folder = invoicesFolder
        
        let results = await searchIndex.search("2024", filters: filters)
        
        XCTAssertGreaterThan(results.documents.count, 0)
        XCTAssertTrue(results.documents.allSatisfy { $0.folder == invoicesFolder })
    }
    
    func testSearchWithDateRangeFilter() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let endDate = Date()
        
        var filters = SearchFilters()
        filters.dateRange = SearchFilters.DateRange(start: startDate, end: endDate)
        
        let results = await searchIndex.search("document", filters: filters)
        
        // All results should be within the date range
        XCTAssertTrue(results.documents.allSatisfy { document in
            guard let createdAt = document.createdAt else { return false }
            return createdAt >= startDate && createdAt <= endDate
        })
    }
    
    func testSearchWithDocumentTypeFilter() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        var filters = SearchFilters()
        filters.documentTypes = ["application/pdf"]
        
        let results = await searchIndex.search("document", filters: filters)
        
        XCTAssertGreaterThan(results.documents.count, 0)
        XCTAssertTrue(results.documents.allSatisfy { $0.mimeType == "application/pdf" })
    }
    
    // MARK: - Search Suggestions Tests
    
    func testSearchSuggestions() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let suggestions = await searchIndex.getSearchSuggestions(for: "meet")
        
        XCTAssertGreaterThan(suggestions.count, 0)
        XCTAssertTrue(suggestions.contains { $0.hasPrefix("meet") })
    }
    
    func testSearchSuggestionsMinLength() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let shortSuggestions = await searchIndex.getSearchSuggestions(for: "m")
        XCTAssertEqual(shortSuggestions.count, 0)
        
        let validSuggestions = await searchIndex.getSearchSuggestions(for: "me")
        // Should return suggestions for 2+ character queries
    }
    
    func testSearchSuggestionsLimit() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let suggestions = await searchIndex.getSearchSuggestions(for: "a", limit: 3)
        XCTAssertLessThanOrEqual(suggestions.count, 3)
    }
    
    // MARK: - Relevance Scoring Tests
    
    func testRelevanceScoring() async throws {
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let results = await searchIndex.search("invoice")
        
        XCTAssertGreaterThan(results.documents.count, 0)
        
        // Document with "Invoice" in title should rank higher than one with "invoice" only in OCR text
        let titleMatch = results.documents.first { $0.title?.contains("Invoice") == true }
        let ocrMatch = results.documents.first { $0.title?.contains("Invoice") != true && $0.ocrText?.contains("invoice") == true }
        
        if let titleMatch = titleMatch, let ocrMatch = ocrMatch {
            let titleIndex = results.documents.firstIndex(of: titleMatch)!
            let ocrIndex = results.documents.firstIndex(of: ocrMatch)!
            XCTAssertLessThan(titleIndex, ocrIndex, "Title matches should rank higher than OCR matches")
        }
    }
    
    func testRecentDocumentBoost() async throws {
        // Create an older document
        let oldDocument = Document(context: context)
        oldDocument.id = UUID()
        oldDocument.title = "Old Meeting Notes"
        oldDocument.fileName = "old_meeting.txt"
        oldDocument.mimeType = "text/plain"
        oldDocument.ocrText = "Old meeting discussion"
        oldDocument.folder = testFolders.first
        oldDocument.createdAt = Calendar.current.date(byAdding: .month, value: -6, to: Date())
        oldDocument.modifiedAt = Calendar.current.date(byAdding: .month, value: -6, to: Date())
        oldDocument.fileSize = 1024
        oldDocument.isEncrypted = true
        oldDocument.encryptedFilePath = "/encrypted/old_meeting.txt"
        
        // Create a recent document
        let recentDocument = Document(context: context)
        recentDocument.id = UUID()
        recentDocument.title = "Recent Meeting Notes"
        recentDocument.fileName = "recent_meeting.txt"
        recentDocument.mimeType = "text/plain"
        recentDocument.ocrText = "Recent meeting discussion"
        recentDocument.folder = testFolders.first
        recentDocument.createdAt = Date()
        recentDocument.modifiedAt = Date()
        recentDocument.fileSize = 1024
        recentDocument.isEncrypted = true
        recentDocument.encryptedFilePath = "/encrypted/recent_meeting.txt"
        
        try context.save()
        
        await searchIndex.indexDocument(oldDocument)
        await searchIndex.indexDocument(recentDocument)
        
        let results = await searchIndex.search("meeting")
        
        XCTAssertGreaterThan(results.documents.count, 1)
        
        // Recent document should rank higher
        let recentIndex = results.documents.firstIndex { $0.title == "Recent Meeting Notes" }
        let oldIndex = results.documents.firstIndex { $0.title == "Old Meeting Notes" }
        
        if let recentIndex = recentIndex, let oldIndex = oldIndex {
            XCTAssertLessThan(recentIndex, oldIndex, "Recent documents should rank higher")
        }
    }
    
    // MARK: - Index Management Tests
    
    func testRebuildIndex() async throws {
        // Index some documents
        for document in testDocuments.prefix(2) {
            await searchIndex.indexDocument(document)
        }
        
        let initialStats = await searchIndex.getIndexStatistics()
        XCTAssertEqual(initialStats.indexedDocuments, 2)
        
        // Add more documents to Core Data but don't index them
        let newDocument = Document(context: context)
        newDocument.id = UUID()
        newDocument.title = "New Document"
        newDocument.fileName = "new.txt"
        newDocument.mimeType = "text/plain"
        newDocument.ocrText = "New document content"
        newDocument.folder = testFolders.first
        newDocument.createdAt = Date()
        newDocument.modifiedAt = Date()
        newDocument.fileSize = 1024
        newDocument.isEncrypted = true
        newDocument.encryptedFilePath = "/encrypted/new.txt"
        
        try context.save()
        
        // Rebuild index
        await searchIndex.rebuildIndex()
        
        let finalStats = await searchIndex.getIndexStatistics()
        XCTAssertEqual(finalStats.indexedDocuments, testDocuments.count + 1) // Original + new document
    }
    
    func testClearIndex() async throws {
        // Index documents
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        let initialStats = await searchIndex.getIndexStatistics()
        XCTAssertGreaterThan(initialStats.indexedDocuments, 0)
        
        // Clear index
        await searchIndex.clearIndex()
        
        let finalStats = await searchIndex.getIndexStatistics()
        XCTAssertEqual(finalStats.indexedDocuments, 0)
        
        // Search should return no results
        let results = await searchIndex.search("meeting")
        XCTAssertEqual(results.documents.count, 0)
    }
    
    func testIndexStatistics() async throws {
        let initialStats = await searchIndex.getIndexStatistics()
        XCTAssertEqual(initialStats.indexedDocuments, 0)
        
        // Index some documents
        for document in testDocuments.prefix(3) {
            await searchIndex.indexDocument(document)
        }
        
        let finalStats = await searchIndex.getIndexStatistics()
        XCTAssertEqual(finalStats.indexedDocuments, 3)
        XCTAssertGreaterThan(finalStats.totalIndexEntries, 0)
        XCTAssertNotNil(finalStats.lastUpdate)
    }
    
    // MARK: - Performance Tests
    
    func testSearchPerformance() async throws {
        // Index all documents
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        measure {
            Task {
                _ = await searchIndex.search("document")
            }
        }
    }
    
    func testIndexingPerformance() async throws {
        let documents = Array(testDocuments.prefix(3))
        
        measure {
            Task {
                for document in documents {
                    await searchIndex.indexDocument(document)
                }
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testSearchWithCorruptedIndex() async throws {
        // This test would simulate corrupted index data
        // For now, we'll test that search handles empty results gracefully
        let results = await searchIndex.search("nonexistent")
        XCTAssertEqual(results.documents.count, 0)
        XCTAssertEqual(results.totalCount, 0)
    }
    
    // MARK: - Integration Tests
    
    func testFullSearchWorkflow() async throws {
        // Index documents
        for document in testDocuments {
            await searchIndex.indexDocument(document)
        }
        
        // Perform various searches
        let titleSearch = await searchIndex.search("Meeting")
        XCTAssertGreaterThan(titleSearch.documents.count, 0)
        
        let contentSearch = await searchIndex.search("consulting")
        XCTAssertGreaterThan(contentSearch.documents.count, 0)
        
        let fileSearch = await searchIndex.search("invoice_001.pdf")
        XCTAssertGreaterThan(fileSearch.documents.count, 0)
        
        // Test suggestions
        let suggestions = await searchIndex.getSearchSuggestions(for: "meet")
        XCTAssertGreaterThan(suggestions.count, 0)
        
        // Test filtered search
        var filters = SearchFilters()
        filters.documentTypes = ["application/pdf"]
        let filteredSearch = await searchIndex.search("document", filters: filters)
        XCTAssertTrue(filteredSearch.documents.allSatisfy { $0.mimeType == "application/pdf" })
        
        // Test index management
        let stats = await searchIndex.getIndexStatistics()
        XCTAssertEqual(stats.indexedDocuments, testDocuments.count)
    }
}

// MARK: - Test Utilities

extension SearchIndexTests {
    
    func createLargeTestDocument() -> Document {
        let document = Document(context: context)
        document.id = UUID()
        document.title = "Large Test Document"
        document.fileName = "large_test.txt"
        document.mimeType = "text/plain"
        document.folder = testFolders.first
        document.createdAt = Date()
        document.modifiedAt = Date()
        document.fileSize = 1048576 // 1MB
        document.isEncrypted = true
        document.encryptedFilePath = "/encrypted/large_test.txt"
        
        // Generate large OCR text
        var ocrText = ""
        for i in 0..<1000 {
            ocrText += "This is line \(i) of the large test document. It contains various keywords like project, meeting, invoice, contract, and proposal. "
        }
        document.ocrText = ocrText
        
        return document
    }
    
    func waitForIndexing() async {
        // Wait a bit for async indexing operations to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
}

