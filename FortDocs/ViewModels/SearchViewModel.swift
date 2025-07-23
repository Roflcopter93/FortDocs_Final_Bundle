import Foundation
import CoreData
import SwiftUI
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var selectedDocumentTypes: Set<DocumentType> = Set(DocumentType.allCases)
    @Published var dateRange = DateRange()
    @Published var sizeRange = SizeRange()
    @Published var includeOCRText = true
    @Published var caseSensitive = false
    @Published var wholeWordsOnly = false
    
    private var managedObjectContext: NSManagedObjectContext?
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        resetFilters()
    }
    
    deinit {
        searchTask?.cancel()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    
    func initialize(context: NSManagedObjectContext) {
        self.managedObjectContext = context
    }
    
    func search(query: String, filter: SearchFilter = .all) {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        searchTask = Task {
            do {
                let results = try await performSearch(query: query, filter: filter)
                
                if !Task.isCancelled {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    print("Search failed: \(error)")
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }
    
    func resetFilters() {
        selectedDocumentTypes = Set(DocumentType.allCases)
        dateRange = DateRange()
        sizeRange = SizeRange()
        includeOCRText = true
        caseSensitive = false
        wholeWordsOnly = false
    }
    
    func toggleDocumentType(_ type: DocumentType) {
        if selectedDocumentTypes.contains(type) {
            selectedDocumentTypes.remove(type)
        } else {
            selectedDocumentTypes.insert(type)
        }
    }
    
    // MARK: - Private Methods
    
    private func performSearch(query: String, filter: SearchFilter) async throws -> [SearchResult] {
        guard let context = managedObjectContext else { return [] }
        
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    var results: [SearchResult] = []
                    
                    // Search documents
                    if filter == .all || filter == .documents {
                        let documentResults = try self.searchDocuments(query: query, in: context)
                        results.append(contentsOf: documentResults)
                    }
                    
                    // Search folders
                    if filter == .all || filter == .folders {
                        let folderResults = try self.searchFolders(query: query, in: context)
                        results.append(contentsOf: folderResults)
                    }
                    
                    // Sort by relevance
                    results.sort { $0.relevanceScore > $1.relevanceScore }
                    
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func searchDocuments(query: String, in context: NSManagedObjectContext) throws -> [SearchResult] {
        let request = Document.fetchRequest()
        
        // Build predicate based on filters
        var predicates: [NSPredicate] = []
        
        // Text search predicate
        let searchPredicate = buildTextSearchPredicate(query: query)
        predicates.append(searchPredicate)
        
        // Document type filter
        if selectedDocumentTypes.count < DocumentType.allCases.count {
            let typeStrings = selectedDocumentTypes.map { $0.rawValue }
            let typePredicate = NSPredicate(format: "mimeType IN %@", typeStrings)
            predicates.append(typePredicate)
        }
        
        // Date range filter
        if let startDate = dateRange.start {
            let datePredicate = NSPredicate(format: "createdAt >= %@", startDate as NSDate)
            predicates.append(datePredicate)
        }
        
        if let endDate = dateRange.end {
            let datePredicate = NSPredicate(format: "createdAt <= %@", endDate as NSDate)
            predicates.append(datePredicate)
        }
        
        // Size range filter
        if sizeRange.min > 0 {
            let sizePredicate = NSPredicate(format: "fileSize >= %d", sizeRange.min)
            predicates.append(sizePredicate)
        }
        
        if sizeRange.max != Int.max {
            let sizePredicate = NSPredicate(format: "fileSize <= %d", sizeRange.max)
            predicates.append(sizePredicate)
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Document.modifiedAt, ascending: false)]
        
        let documents = try context.fetch(request)
        
        return documents.map { document in
            let relevanceScore = calculateRelevanceScore(for: document, query: query)
            let snippet = generateSnippet(for: document, query: query)
            
            return SearchResult(
                id: document.id,
                item: .document(document),
                title: document.title,
                subtitle: document.folder?.name,
                snippet: snippet,
                relevanceScore: relevanceScore,
                lastModified: document.modifiedAt,
                icon: document.documentType.icon,
                iconColor: document.documentType.color
            )
        }
    }
    
    private func searchFolders(query: String, in context: NSManagedObjectContext) throws -> [SearchResult] {
        let request = Folder.searchFolders(query: query)
        let folders = try context.fetch(request)
        
        return folders.map { folder in
            let relevanceScore = calculateRelevanceScore(for: folder, query: query)
            
            return SearchResult(
                id: folder.id,
                item: .folder(folder),
                title: folder.name,
                subtitle: "\(folder.documentCount) documents",
                snippet: folder.path,
                relevanceScore: relevanceScore,
                lastModified: folder.modifiedAt,
                icon: folder.icon,
                iconColor: folder.color
            )
        }
    }
    
    private func buildTextSearchPredicate(query: String) -> NSPredicate {
        let searchTerms = query.components(separatedBy: .whitespacesAndPunctuationMarks)
            .filter { !$0.isEmpty }
        
        var predicates: [NSPredicate] = []
        
        for term in searchTerms {
            var termPredicates: [NSPredicate] = []
            
            let options: NSComparisonPredicate.Options = caseSensitive ? [] : [.caseInsensitive]
            let format = wholeWordsOnly ? "MATCHES" : "CONTAINS"
            let pattern = wholeWordsOnly ? ".*\\b\(term)\\b.*" : term
            
            // Search in title
            termPredicates.append(NSPredicate(format: "title \(format)[\(options.rawValue)] %@", pattern))
            
            // Search in filename
            termPredicates.append(NSPredicate(format: "fileName \(format)[\(options.rawValue)] %@", pattern))
            
            // Search in OCR text if enabled
            if includeOCRText {
                termPredicates.append(NSPredicate(format: "ocrText \(format)[\(options.rawValue)] %@", pattern))
            }
            
            // Search in tags
            termPredicates.append(NSPredicate(format: "ANY tags \(format)[\(options.rawValue)] %@", pattern))
            
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: termPredicates))
        }
        
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
    
    private func calculateRelevanceScore(for document: Document, query: String) -> Double {
        let queryLower = query.lowercased()
        var score: Double = 0
        
        // Title match (highest weight)
        if document.title.lowercased().contains(queryLower) {
            score += 1.0
            
            // Exact match bonus
            if document.title.lowercased() == queryLower {
                score += 0.5
            }
            
            // Starts with bonus
            if document.title.lowercased().hasPrefix(queryLower) {
                score += 0.3
            }
        }
        
        // Filename match
        if document.fileName.lowercased().contains(queryLower) {
            score += 0.7
        }
        
        // OCR text match
        if let ocrText = document.ocrText, ocrText.lowercased().contains(queryLower) {
            score += 0.5
            
            // Multiple occurrences bonus
            let occurrences = ocrText.lowercased().components(separatedBy: queryLower).count - 1
            score += Double(occurrences - 1) * 0.1
        }
        
        // Tags match
        for tag in document.tags {
            if tag.lowercased().contains(queryLower) {
                score += 0.6
                
                if tag.lowercased() == queryLower {
                    score += 0.2
                }
            }
        }
        
        // Recency bonus
        let daysSinceModified = Date().timeIntervalSince(document.modifiedAt) / (24 * 60 * 60)
        let recencyBonus = max(0, 0.2 - (daysSinceModified / 365) * 0.2)
        score += recencyBonus
        
        return min(score, 2.0) // Cap at 2.0
    }
    
    private func calculateRelevanceScore(for folder: Folder, query: String) -> Double {
        let queryLower = query.lowercased()
        var score: Double = 0
        
        // Name match
        if folder.name.lowercased().contains(queryLower) {
            score += 1.0
            
            if folder.name.lowercased() == queryLower {
                score += 0.5
            }
        }
        
        // Document count bonus
        score += Double(folder.documentCount) * 0.01
        
        return min(score, 2.0)
    }
    
    private func generateSnippet(for document: Document, query: String) -> String? {
        let queryLower = query.lowercased()
        
        // Try OCR text first
        if let ocrText = document.ocrText, !ocrText.isEmpty {
            if let snippet = extractSnippet(from: ocrText, query: queryLower) {
                return snippet
            }
        }
        
        // Fallback to title and filename
        let combinedText = "\(document.title) \(document.fileName)"
        return extractSnippet(from: combinedText, query: queryLower)
    }
    
    private func extractSnippet(from text: String, query: String) -> String? {
        let textLower = text.lowercased()
        
        guard let range = textLower.range(of: query) else {
            return String(text.prefix(100))
        }
        
        let snippetLength = 150
        let queryStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let contextStart = max(0, queryStart - snippetLength / 2)
        let contextEnd = min(text.count, contextStart + snippetLength)
        
        let startIndex = text.index(text.startIndex, offsetBy: contextStart)
        let endIndex = text.index(text.startIndex, offsetBy: contextEnd)
        
        var snippet = String(text[startIndex..<endIndex])
        
        if contextStart > 0 {
            snippet = "..." + snippet
        }
        
        if contextEnd < text.count {
            snippet = snippet + "..."
        }
        
        return snippet
    }
}

// MARK: - Supporting Types

enum SearchFilter: String, CaseIterable {
    case all = "All"
    case documents = "Documents"
    case folders = "Folders"
    case images = "Images"
    case pdfs = "PDFs"
    case recent = "Recent"
    
    var displayName: String {
        return rawValue
    }
    
    var icon: String {
        switch self {
        case .all:
            return "magnifyingglass"
        case .documents:
            return "doc.fill"
        case .folders:
            return "folder.fill"
        case .images:
            return "photo.fill"
        case .pdfs:
            return "doc.richtext.fill"
        case .recent:
            return "clock.fill"
        }
    }
}

struct SearchResult {
    let id: UUID
    let item: SearchResultItem
    let title: String
    let subtitle: String?
    let snippet: String?
    let relevanceScore: Double
    let lastModified: Date?
    let icon: String
    let iconColor: Color
}

enum SearchResultItem {
    case document(Document)
    case folder(Folder)
}

struct DateRange {
    var start: Date?
    var end: Date?
    
    init() {
        self.start = nil
        self.end = nil
    }
}

struct SizeRange {
    var min: Int
    var max: Int
    
    init() {
        self.min = 0
        self.max = Int.max
    }
}

