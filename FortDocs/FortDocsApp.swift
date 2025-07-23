import SwiftUI
import CoreData

@main
struct FortDocsApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var authenticationService = AuthenticationService()
    @StateObject private var folderStore = FolderStore()
    @StateObject private var searchIndex = SearchIndex()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(authenticationService)
                .environmentObject(folderStore)
                .environmentObject(searchIndex)
                .onAppear {
                    setupApplication()
                }
        }
    }
    
    private func setupApplication() {
        // Initialize default folders if needed
        folderStore.initializeDefaultFolders()
        
        // Setup search indexing
        searchIndex.setupCoreSpotlight()
        
        // Configure app security settings
        configureAppSecurity()
    }
    
    private func configureAppSecurity() {
        // Enable file protection
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        do {
            try FileManager.default.setAttributes([
                .protectionKey: FileProtectionType.complete
            ], ofItemAtPath: documentsPath.path)
        } catch {
            print("Failed to set file protection: \(error)")
        }
        
        // Configure app for security
        #if !DEBUG
        // Enable jailbreak detection in release builds
        SecurityUtils.enableJailbreakDetection()
        #endif
    }
}

// MARK: - Core Data Stack
class PersistenceController {
    static let shared = PersistenceController()
    
    lazy var container: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "FortDocs")
        
        // Configure for CloudKit
        let storeDescription = container.persistentStoreDescriptions.first!
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Core Data error: \(error), \(error.userInfo)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Core Data save error: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// MARK: - Security Utilities
struct SecurityUtils {
    static func enableJailbreakDetection() {
        // Implement jailbreak detection
        if isJailbroken() {
            // Handle jailbroken device
            fatalError("Security violation detected")
        }
    }
    
    private static func isJailbroken() -> Bool {
        // Check for common jailbreak indicators
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check if we can write to system directories
        let testPath = "/private/test_jailbreak"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            // Normal behavior - we shouldn't be able to write here
        }
        
        return false
    }
}

