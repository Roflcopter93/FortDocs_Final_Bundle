import Foundation
import CoreData
import SwiftUI

@objc(Folder)
public class Folder: NSManagedObject {
    
}

extension Folder {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Folder> {
        return NSFetchRequest<Folder>(entityName: "Folder")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var colorHex: String
    @NSManaged public var iconName: String
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var isDefault: Bool
    @NSManaged public var parentFolder: Folder?
    @NSManaged public var subfolders: Set<Folder>
    @NSManaged public var documents: Set<Document>
    
    // Computed properties
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
    
    var icon: String {
        iconName.isEmpty ? "folder.fill" : iconName
    }
    
    var documentCount: Int {
        documents.count + subfolders.reduce(0) { $0 + $1.documentCount }
    }
    
    var directDocumentCount: Int {
        documents.count
    }
    
    var isRootFolder: Bool {
        parentFolder == nil
    }
    
    var depth: Int {
        var currentFolder = self
        var depth = 0
        
        while let parent = currentFolder.parentFolder {
            depth += 1
            currentFolder = parent
        }
        
        return depth
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
    
    // MARK: - Core Data Lifecycle
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        id = UUID()
        createdAt = Date()
        modifiedAt = Date()
        colorHex = Color.blue.toHex()
        iconName = "folder.fill"
        sortOrder = 0
        isDefault = false
        subfolders = Set<Folder>()
        documents = Set<Document>()
    }
    
    public override func willSave() {
        super.willSave()
        
        if isUpdated && !isDeleted {
            modifiedAt = Date()
        }
    }
}

// MARK: - Folder Management

extension Folder {
    
    // MARK: - Convenience Initializers
    
    convenience init(context: NSManagedObjectContext, name: String, parent: Folder? = nil) {
        self.init(context: context)
        self.name = name
        self.parentFolder = parent
        
        if let parent = parent {
            parent.addToSubfolders(self)
        }
    }
    
    convenience init(context: NSManagedObjectContext, name: String, color: Color, icon: String, isDefault: Bool = false) {
        self.init(context: context)
        self.name = name
        self.colorHex = color.toHex()
        self.iconName = icon
        self.isDefault = isDefault
    }
    
    // MARK: - Hierarchy Management
    
    func addSubfolder(_ folder: Folder) {
        folder.parentFolder = self
        addToSubfolders(folder)
    }
    
    func removeSubfolder(_ folder: Folder) {
        folder.parentFolder = nil
        removeFromSubfolders(folder)
    }
    
    func moveToFolder(_ newParent: Folder?) {
        parentFolder?.removeFromSubfolders(self)
        parentFolder = newParent
        newParent?.addToSubfolders(self)
    }
    
    func canMoveTo(_ targetFolder: Folder) -> Bool {
        // Prevent moving a folder into itself or its descendants
        var currentFolder: Folder? = targetFolder
        
        while let folder = currentFolder {
            if folder == self {
                return false
            }
            currentFolder = folder.parentFolder
        }
        
        return true
    }
    
    // MARK: - Document Management
    
    func addDocument(_ document: Document) {
        document.folder = self
        addToDocuments(document)
    }
    
    func removeDocument(_ document: Document) {
        document.folder = nil
        removeFromDocuments(document)
    }
    
    func moveDocument(_ document: Document, to targetFolder: Folder) {
        removeDocument(document)
        targetFolder.addDocument(document)
    }
    
    // MARK: - Sorting and Organization
    
    func sortedSubfolders() -> [Folder] {
        subfolders.sorted { folder1, folder2 in
            if folder1.sortOrder != folder2.sortOrder {
                return folder1.sortOrder < folder2.sortOrder
            }
            return folder1.name.localizedCaseInsensitiveCompare(folder2.name) == .orderedAscending
        }
    }
    
    func sortedDocuments() -> [Document] {
        documents.sorted { doc1, doc2 in
            doc1.modifiedAt > doc2.modifiedAt
        }
    }
    
    // MARK: - Search Support
    
    func searchDocuments(query: String) -> [Document] {
        var results: [Document] = []
        
        // Search documents in this folder
        for document in documents {
            if document.searchableContent().localizedCaseInsensitiveContains(query) {
                results.append(document)
            }
        }
        
        // Search documents in subfolders
        for subfolder in subfolders {
            results.append(contentsOf: subfolder.searchDocuments(query: query))
        }
        
        return results.sorted { $0.modifiedAt > $1.modifiedAt }
    }
    
    // MARK: - Validation
    
    func validateName(_ name: String) -> Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        // Check for duplicate names in the same parent folder
        let siblings = parentFolder?.subfolders ?? Set<Folder>()
        return !siblings.contains { $0 != self && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}

// MARK: - Default Folders

extension Folder {
    
    static func createDefaultFolders(in context: NSManagedObjectContext) {
        let defaultFolders = [
            ("Documents", Color.blue, "doc.fill"),
            ("Invoices", Color.green, "receipt.fill"),
            ("IDs", Color.orange, "person.crop.rectangle.fill"),
            ("Receipts", Color.purple, "bag.fill"),
            ("Certificates", Color.red, "rosette")
        ]
        
        for (index, (name, color, icon)) in defaultFolders.enumerated() {
            let folder = Folder(context: context, name: name, color: color, icon: icon, isDefault: true)
            folder.sortOrder = Int32(index)
        }
        
        do {
            try context.save()
        } catch {
            print("Failed to create default folders: \(error)")
        }
    }
    
    static func getDefaultFolder(named name: String, in context: NSManagedObjectContext) -> Folder? {
        let request = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@ AND isDefault == YES", name)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Failed to fetch default folder: \(error)")
            return nil
        }
    }
}

// MARK: - Identifiable Conformance

extension Folder: Identifiable {
    // Uses the existing `id` property
}

// MARK: - Fetch Request Extensions

extension Folder {
    
    static func fetchRootFolders() -> NSFetchRequest<Folder> {
        let request = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "parentFolder == nil")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ]
        return request
    }
    
    static func fetchSubfolders(of parent: Folder) -> NSFetchRequest<Folder> {
        let request = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "parentFolder == %@", parent)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ]
        return request
    }
    
    static func fetchAll() -> NSFetchRequest<Folder> {
        let request = Folder.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ]
        return request
    }
    
    static func searchFolders(query: String) -> NSFetchRequest<Folder> {
        let request = Folder.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Folder.name, ascending: true)
        ]
        return request
    }
}

// MARK: - Core Data Relationships

extension Folder {
    
    @objc(addSubfoldersObject:)
    @NSManaged public func addToSubfolders(_ value: Folder)
    
    @objc(removeSubfoldersObject:)
    @NSManaged public func removeFromSubfolders(_ value: Folder)
    
    @objc(addSubfolders:)
    @NSManaged public func addToSubfolders(_ values: NSSet)
    
    @objc(removeSubfolders:)
    @NSManaged public func removeFromSubfolders(_ values: NSSet)
    
    @objc(addDocumentsObject:)
    @NSManaged public func addToDocuments(_ value: Document)
    
    @objc(removeDocumentsObject:)
    @NSManaged public func removeFromDocuments(_ value: Document)
    
    @objc(addDocuments:)
    @NSManaged public func addToDocuments(_ values: NSSet)
    
    @objc(removeDocuments:)
    @NSManaged public func removeFromDocuments(_ values: NSSet)
}

// MARK: - Color Extension

extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return String(format: "#%02X%02X%02X",
                     Int(red * 255),
                     Int(green * 255),
                     Int(blue * 255))
    }
    
    init?(hex: String) {
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
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

