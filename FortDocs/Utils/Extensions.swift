import Foundation
import SwiftUI
import CoreData

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return "000000"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}

// MARK: - Date Extensions

extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }
    
    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    var isThisMonth: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .month)
    }
    
    var isThisYear: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year)
    }
    
    func relativeDateString() -> String {
        if isToday {
            return "Today"
        } else if isYesterday {
            return "Yesterday"
        } else if isThisWeek {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: self)
        } else if isThisYear {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: self)
        }
    }
}

// MARK: - String Extensions

extension String {
    var isValidEmail: Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: self)
    }
    
    var isValidPIN: Bool {
        return count == 5 && allSatisfy { $0.isNumber }
    }
    
    func truncated(to length: Int, trailing: String = "...") -> String {
        return count > length ? String(prefix(length)) + trailing : self
    }
    
    func sanitizedFilename() -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}

// MARK: - Data Extensions

extension Data {
    var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
    
    func hexString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

// MARK: - URL Extensions

extension URL {
    var mimeType: String {
        if let mimeType = UTType(filenameExtension: pathExtension)?.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }
    
    var fileSize: Int64 {
        do {
            let resourceValues = try resourceValues(forKeys: [.fileSizeKey])
            return Int64(resourceValues.fileSize ?? 0)
        } catch {
            return 0
        }
    }
    
    var creationDate: Date? {
        do {
            let resourceValues = try resourceValues(forKeys: [.creationDateKey])
            return resourceValues.creationDate
        } catch {
            return nil
        }
    }
    
    var modificationDate: Date? {
        do {
            let resourceValues = try resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            return nil
        }
    }
}

// MARK: - Array Extensions

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var addedDict = [Element: Bool]()
        return filter {
            addedDict.updateValue(true, forKey: $0) == nil
        }
    }
    
    mutating func removeDuplicates() {
        self = self.removingDuplicates()
    }
}

// MARK: - View Extensions

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Custom Shapes

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Document Type Extensions

extension DocumentType {
    var icon: String {
        switch self {
        case .pdf:
            return "doc.richtext.fill"
        case .image:
            return "photo.fill"
        case .text:
            return "doc.text.fill"
        case .unknown:
            return "doc.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pdf:
            return .red
        case .image:
            return .blue
        case .text:
            return .green
        case .unknown:
            return .gray
        }
    }
    
    static func from(mimeType: String) -> DocumentType {
        switch mimeType.lowercased() {
        case let type where type.hasPrefix("image/"):
            return .image
        case "application/pdf":
            return .pdf
        case let type where type.hasPrefix("text/"):
            return .text
        default:
            return .unknown
        }
    }
}

enum DocumentType: String, CaseIterable {
    case pdf = "PDF"
    case image = "Image"
    case text = "Text"
    case unknown = "Unknown"
}

// MARK: - Core Data Extensions

extension NSManagedObjectContext {
    func saveIfNeeded() throws {
        if hasChanges {
            try save()
        }
    }
}

extension NSFetchRequest {
    func with(predicate: NSPredicate) -> Self {
        self.predicate = predicate
        return self
    }
    
    func with(sortDescriptors: [NSSortDescriptor]) -> Self {
        self.sortDescriptors = sortDescriptors
        return self
    }
    
    func with(limit: Int) -> Self {
        self.fetchLimit = limit
        return self
    }
}

// MARK: - Folder Statistics

extension FolderStore {
    struct FolderStatistics {
        let totalFolders: Int
        let totalDocuments: Int
        let totalSize: Int64
        let lastModified: Date
        
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        }
    }
}

// MARK: - Document Extensions

extension Document {
    var documentType: DocumentType {
        return DocumentType.from(mimeType: mimeType)
    }
    
    var formattedFileSize: String {
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var thumbnail: UIImage? {
        // This would generate or retrieve a thumbnail
        return nil
    }
    
    func getDecryptedFileURL() throws -> URL {
        let encryptedURL = URL(fileURLWithPath: encryptedFilePath)
        return try CryptoVault.shared.getDecryptedFileURL(for: encryptedURL)
    }
}

// MARK: - Folder Extensions

extension Folder {
    var icon: String {
        return iconName ?? "folder.fill"
    }
    
    var color: Color {
        if let colorHex = colorHex {
            return Color(hex: colorHex)
        }
        return .blue
    }
    
    var path: String {
        var components: [String] = []
        var currentFolder: Folder? = self
        
        while let folder = currentFolder {
            components.insert(folder.name, at: 0)
            currentFolder = folder.parentFolder
        }
        
        return components.joined(separator: " > ")
    }
    
    var documentCount: Int {
        return documents.count + subfolders.reduce(0) { $0 + $1.documentCount }
    }
    
    var directDocumentCount: Int {
        return documents.count
    }
    
    func canMoveTo(_ destination: Folder) -> Bool {
        // Prevent moving to self or descendant
        var current: Folder? = destination
        while let folder = current {
            if folder == self {
                return false
            }
            current = folder.parentFolder
        }
        return true
    }
    
    func moveToFolder(_ newParent: Folder?) {
        parentFolder = newParent
        modifiedAt = Date()
    }
    
    func addDocument(_ document: Document) {
        document.folder = self
        modifiedAt = Date()
    }
    
    func removeDocument(_ document: Document) {
        document.folder = nil
        modifiedAt = Date()
    }
    
    func validateName(_ name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && trimmedName.count <= 100
    }
}

// MARK: - Fetch Request Extensions

extension Document {
    static func fetchAll() -> NSFetchRequest<Document> {
        let request = Document.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Document.modifiedAt, ascending: false)]
        return request
    }
    
    static func fetchRecent(limit: Int = 10) -> NSFetchRequest<Document> {
        let request = fetchAll()
        request.fetchLimit = limit
        return request
    }
    
    static func searchDocuments(query: String) -> NSFetchRequest<Document> {
        let request = Document.fetchRequest()
        
        let titlePredicate = NSPredicate(format: "title CONTAINS[cd] %@", query)
        let fileNamePredicate = NSPredicate(format: "fileName CONTAINS[cd] %@", query)
        let ocrPredicate = NSPredicate(format: "ocrText CONTAINS[cd] %@", query)
        
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            titlePredicate, fileNamePredicate, ocrPredicate
        ])
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Document.modifiedAt, ascending: false)]
        
        return request
    }
}

extension Folder {
    static func fetchAll() -> NSFetchRequest<Folder> {
        let request = Folder.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true)]
        return request
    }
    
    static func fetchRootFolders() -> NSFetchRequest<Folder> {
        let request = fetchAll()
        request.predicate = NSPredicate(format: "parentFolder == nil")
        return request
    }
    
    static func searchFolders(query: String) -> NSFetchRequest<Folder> {
        let request = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Folder.name, ascending: true)]
        return request
    }
}

// MARK: - Import/Export Extensions

extension UTType {
    static let fortDocsDocument = UTType(exportedAs: "com.fortdocs.document")
    static let fortDocsFolder = UTType(exportedAs: "com.fortdocs.folder")
}



// MARK: - Array Extensions for Search

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

