import Foundation
import CoreData
import SwiftUI

@objc(Document)
public class Document: NSManagedObject {
    
}

extension Document {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Document> {
        return NSFetchRequest<Document>(entityName: "Document")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var fileName: String
    @NSManaged public var encryptedFilePath: String
    @NSManaged public var fileSize: Int64
    @NSManaged public var mimeType: String
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date
    @NSManaged public var ocrText: String?
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var tags: Set<String>
    @NSManaged public var isEncrypted: Bool
    @NSManaged public var encryptionKeyID: String?
    @NSManaged public var folder: Folder?
    
    // Computed properties
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var fileExtension: String {
        URL(fileURLWithPath: fileName).pathExtension.lowercased()
    }
    
    var documentType: DocumentType {
        DocumentType.from(mimeType: mimeType)
    }
    
    var thumbnail: UIImage? {
        guard let data = thumbnailData else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Core Data Lifecycle
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        id = UUID()
        createdAt = Date()
        modifiedAt = Date()
        isEncrypted = true
        tags = Set<String>()
    }
    
    public override func willSave() {
        super.willSave()
        
        if isUpdated && !isDeleted {
            modifiedAt = Date()
        }
    }
}

// MARK: - Document Extensions

extension Document {
    
    // MARK: - Convenience Initializers
    
    convenience init(context: NSManagedObjectContext, title: String, fileName: String, mimeType: String) {
        self.init(context: context)
        self.title = title
        self.fileName = fileName
        self.mimeType = mimeType
    }
    
    // MARK: - File Management
    
    func getDecryptedFileURL() throws -> URL {
        guard let cryptoVault = CryptoVault.shared else {
            throw DocumentError.cryptoVaultNotAvailable
        }
        
        let encryptedURL = URL(fileURLWithPath: encryptedFilePath)
        return try cryptoVault.getDecryptedFileURL(for: encryptedURL)
    }
    
    func updateThumbnail(from image: UIImage) {
        let thumbnailSize = CGSize(width: 200, height: 200)
        let thumbnail = image.preparingThumbnail(of: thumbnailSize)
        self.thumbnailData = thumbnail?.jpegData(compressionQuality: 0.8)
    }
    
    func addTag(_ tag: String) {
        var currentTags = tags
        currentTags.insert(tag.lowercased())
        tags = currentTags
    }
    
    func removeTag(_ tag: String) {
        var currentTags = tags
        currentTags.remove(tag.lowercased())
        tags = currentTags
    }
    
    // MARK: - Search Support
    
    func searchableContent() -> String {
        var content = [title, fileName]
        
        if let ocrText = ocrText, !ocrText.isEmpty {
            content.append(ocrText)
        }
        
        content.append(contentsOf: tags)
        
        return content.joined(separator: " ")
    }
}

// MARK: - Document Errors

enum DocumentError: LocalizedError {
    case cryptoVaultNotAvailable
    case fileNotFound
    case decryptionFailed
    case invalidFileFormat
    
    var errorDescription: String? {
        switch self {
        case .cryptoVaultNotAvailable:
            return "Crypto vault is not available"
        case .fileNotFound:
            return "Document file not found"
        case .decryptionFailed:
            return "Failed to decrypt document"
        case .invalidFileFormat:
            return "Invalid file format"
        }
    }
}

// MARK: - Identifiable Conformance

extension Document: Identifiable {
    // Uses the existing `id` property
}

// MARK: - Fetch Request Extensions

extension Document {
    
    static func fetchAll() -> NSFetchRequest<Document> {
        let request = Document.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Document.modifiedAt, ascending: false)
        ]
        return request
    }
    
    static func fetchByFolder(_ folder: Folder) -> NSFetchRequest<Document> {
        let request = Document.fetchRequest()
        request.predicate = NSPredicate(format: "folder == %@", folder)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Document.modifiedAt, ascending: false)
        ]
        return request
    }
    
    static func fetchByTag(_ tag: String) -> NSFetchRequest<Document> {
        let request = Document.fetchRequest()
        request.predicate = NSPredicate(format: "ANY tags CONTAINS[cd] %@", tag)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Document.modifiedAt, ascending: false)
        ]
        return request
    }
    
    static func searchDocuments(query: String) -> NSFetchRequest<Document> {
        let request = Document.fetchRequest()
        
        let titlePredicate = NSPredicate(format: "title CONTAINS[cd] %@", query)
        let fileNamePredicate = NSPredicate(format: "fileName CONTAINS[cd] %@", query)
        let ocrPredicate = NSPredicate(format: "ocrText CONTAINS[cd] %@", query)
        let tagsPredicate = NSPredicate(format: "ANY tags CONTAINS[cd] %@", query)
        
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            titlePredicate, fileNamePredicate, ocrPredicate, tagsPredicate
        ])
        
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Document.modifiedAt, ascending: false)
        ]
        
        return request
    }
}

