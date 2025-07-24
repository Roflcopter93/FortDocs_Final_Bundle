import SwiftUI
import CoreData

struct SearchView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var searchIndex = SearchIndex.shared
    @State private var searchText = ""
    @State private var selectedDocument: Document?
    @State private var showingFilters = false
    @State private var selectedFilter: SearchFilter = .all
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                SearchBarView(text: $searchText, onSearchChanged: performSearch)
                    .padding()
                
                // Filter chips
                FilterChipsView(selectedFilter: $selectedFilter, onFilterChanged: applyFilter)
                    .padding(.horizontal)
                
                // Search results
                if viewModel.isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchText.isEmpty {
                    EmptySearchView()
                } else if viewModel.searchResults.isEmpty {
                    NoResultsView(searchText: searchText)
                } else {
                    SearchResultsView(
                        results: viewModel.searchResults,
                        searchText: searchText,
                        selectedDocument: $selectedDocument
                    )
                }
                if searchIndex.isIndexing {
                    ProgressView("Indexing...", value: searchIndex.indexingProgress)
                        .padding()
                }
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingFilters = true }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(item: $selectedDocument) { document in
            DocumentView(document: document)
        }
        .sheet(isPresented: $showingFilters) {
            SearchFiltersView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.initialize(context: viewContext)
        }
    }
    
    private func performSearch(_ query: String) {
        viewModel.search(query: query, filter: selectedFilter)
    }
    
    private func applyFilter(_ filter: SearchFilter) {
        selectedFilter = filter
        if !searchText.isEmpty {
            performSearch(searchText)
        }
    }
}

// MARK: - Search Bar View

struct SearchBarView: View {
    @Binding var text: String
    let onSearchChanged: (String) -> Void
    @State private var isEditing = false
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search documents, folders, and content...", text: $text)
                    .onEditingChanged { editing in
                        isEditing = editing
                    }
                    .onChange(of: text) { newValue in
                        onSearchChanged(newValue)
                    }
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                        onSearchChanged("")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            if isEditing {
                Button("Cancel") {
                    text = ""
                    isEditing = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}

// MARK: - Filter Chips View

struct FilterChipsView: View {
    @Binding var selectedFilter: SearchFilter
    let onFilterChanged: (SearchFilter) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SearchFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.displayName,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                        onFilterChanged(filter)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Search Results View

struct SearchResultsView: View {
    let results: [SearchResult]
    let searchText: String
    @Binding var selectedDocument: Document?
    
    var body: some View {
        List {
            ForEach(results, id: \.id) { result in
                SearchResultRow(result: result, searchText: searchText) {
                    if case .document(let document) = result.item {
                        selectedDocument = document
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let searchText: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: result.icon)
                    .font(.title2)
                    .foregroundColor(result.iconColor)
                    .frame(width: 40, height: 40)
                    .background(result.iconColor.opacity(0.1))
                    .cornerRadius(8)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let subtitle = result.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let snippet = result.snippet {
                        Text(highlightedText(snippet, searchText: searchText))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                // Metadata
                VStack(alignment: .trailing, spacing: 4) {
                    Text(result.relevanceScore, format: .percent)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let date = result.lastModified {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func highlightedText(_ text: String, searchText: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        if !searchText.isEmpty {
            let range = text.range(of: searchText, options: .caseInsensitive)
            if let range = range {
                let nsRange = NSRange(range, in: text)
                if let attributedRange = Range(nsRange, in: attributedString) {
                    attributedString[attributedRange].backgroundColor = .yellow.opacity(0.3)
                }
            }
        }
        
        return attributedString
    }
}

// MARK: - Empty States

struct EmptySearchView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Search Your Documents")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                Text("Find documents by:")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Document title or filename")
                    Text("• Text content (OCR)")
                    Text("• Tags and metadata")
                    Text("• Folder names")
                }
                .font(.body)
                .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct NoResultsView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Results Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("No documents match '\(searchText)'")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Try:")
                    .font(.body)
                    .fontWeight(.medium)
                
                Text("• Different keywords")
                Text("• Checking spelling")
                Text("• Using fewer words")
                Text("• Searching in all content types")
            }
            .font(.body)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Search Filters View

struct SearchFiltersView: View {
    @ObservedObject var viewModel: SearchViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Content Type") {
                    ForEach(DocumentType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(type.color)
                            Text(type.rawValue)
                            Spacer()
                            if viewModel.selectedDocumentTypes.contains(type) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toggleDocumentType(type)
                        }
                    }
                }
                
                Section("Date Range") {
                    DatePicker("From", selection: Binding(
                        get: { viewModel.dateRange.start ?? Date().addingTimeInterval(-30*24*60*60) },
                        set: { viewModel.dateRange.start = $0 }
                    ), displayedComponents: .date)
                    
                    DatePicker("To", selection: Binding(
                        get: { viewModel.dateRange.end ?? Date() },
                        set: { viewModel.dateRange.end = $0 }
                    ), displayedComponents: .date)
                }
                
                Section("File Size") {
                    HStack {
                        Text("Min Size")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(viewModel.sizeRange.min), countStyle: .file))
                    }
                    
                    Slider(value: Binding(
                        get: { Double(viewModel.sizeRange.min) },
                        set: { viewModel.sizeRange.min = Int($0) }
                    ), in: 0...10_000_000, step: 100_000)
                    
                    HStack {
                        Text("Max Size")
                        Spacer()
                        Text(viewModel.sizeRange.max == Int.max ? "No limit" : 
                             ByteCountFormatter.string(fromByteCount: Int64(viewModel.sizeRange.max), countStyle: .file))
                    }
                    
                    if viewModel.sizeRange.max != Int.max {
                        Slider(value: Binding(
                            get: { Double(viewModel.sizeRange.max) },
                            set: { viewModel.sizeRange.max = Int($0) }
                        ), in: Double(viewModel.sizeRange.min)...50_000_000, step: 100_000)
                    }
                    
                    Toggle("No size limit", isOn: Binding(
                        get: { viewModel.sizeRange.max == Int.max },
                        set: { viewModel.sizeRange.max = $0 ? Int.max : 10_000_000 }
                    ))
                }
                
                Section("Options") {
                    Toggle("Include OCR text", isOn: $viewModel.includeOCRText)
                    Toggle("Case sensitive", isOn: $viewModel.caseSensitive)
                    Toggle("Whole words only", isOn: $viewModel.wholeWordsOnly)
                }
            }
            .navigationTitle("Search Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        viewModel.resetFilters()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SearchView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}

