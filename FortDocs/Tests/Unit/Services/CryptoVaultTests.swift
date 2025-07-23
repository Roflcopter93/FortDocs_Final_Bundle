import XCTest
import CryptoKit
@testable import FortDocs

final class CryptoVaultTests: XCTestCase {
    
    var cryptoVault: CryptoVault!
    var testData: Data!
    var testString: String!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        cryptoVault = CryptoVault.shared
        testString = "This is a test document content for encryption testing."
        testData = testString.data(using: .utf8)!
    }
    
    override func tearDownWithError() throws {
        cryptoVault = nil
        testData = nil
        testString = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Key Generation Tests
    
    func testGenerateEncryptionKey() throws {
        let key = try cryptoVault.generateEncryptionKey()
        
        XCTAssertNotNil(key)
        XCTAssertEqual(key.bitCount, 256) // AES-256
    }
    
    func testGenerateMultipleKeysAreUnique() throws {
        let key1 = try cryptoVault.generateEncryptionKey()
        let key2 = try cryptoVault.generateEncryptionKey()
        
        XCTAssertNotEqual(key1.withUnsafeBytes { Data($0) }, 
                         key2.withUnsafeBytes { Data($0) })
    }
    
    // MARK: - Encryption/Decryption Tests
    
    func testEncryptDecryptData() throws {
        let key = try cryptoVault.generateEncryptionKey()
        
        let encryptedData = try cryptoVault.encrypt(data: testData, with: key)
        XCTAssertNotNil(encryptedData)
        XCTAssertNotEqual(encryptedData, testData)
        
        let decryptedData = try cryptoVault.decrypt(data: encryptedData, with: key)
        XCTAssertEqual(decryptedData, testData)
        
        let decryptedString = String(data: decryptedData, encoding: .utf8)
        XCTAssertEqual(decryptedString, testString)
    }
    
    func testEncryptDecryptString() throws {
        let key = try cryptoVault.generateEncryptionKey()
        
        let encryptedData = try cryptoVault.encrypt(string: testString, with: key)
        XCTAssertNotNil(encryptedData)
        
        let decryptedString = try cryptoVault.decrypt(data: encryptedData, with: key, as: String.self)
        XCTAssertEqual(decryptedString, testString)
    }
    
    func testEncryptionWithDifferentKeys() throws {
        let key1 = try cryptoVault.generateEncryptionKey()
        let key2 = try cryptoVault.generateEncryptionKey()
        
        let encryptedData = try cryptoVault.encrypt(data: testData, with: key1)
        
        // Decryption with wrong key should fail
        XCTAssertThrowsError(try cryptoVault.decrypt(data: encryptedData, with: key2))
    }
    
    func testEncryptionProducesUniqueResults() throws {
        let key = try cryptoVault.generateEncryptionKey()
        
        let encrypted1 = try cryptoVault.encrypt(data: testData, with: key)
        let encrypted2 = try cryptoVault.encrypt(data: testData, with: key)
        
        // Same data encrypted twice should produce different results (due to random nonce)
        XCTAssertNotEqual(encrypted1, encrypted2)
        
        // But both should decrypt to the same original data
        let decrypted1 = try cryptoVault.decrypt(data: encrypted1, with: key)
        let decrypted2 = try cryptoVault.decrypt(data: encrypted2, with: key)
        
        XCTAssertEqual(decrypted1, testData)
        XCTAssertEqual(decrypted2, testData)
    }
    
    // MARK: - File Encryption Tests
    
    func testEncryptDecryptFile() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let tempDir = FileManager.default.temporaryDirectory
        
        // Create test file
        let sourceURL = tempDir.appendingPathComponent("test_source.txt")
        try testData.write(to: sourceURL)
        
        // Encrypt file
        let encryptedURL = tempDir.appendingPathComponent("test_encrypted.dat")
        try cryptoVault.encryptFile(at: sourceURL, to: encryptedURL, with: key)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: encryptedURL.path))
        
        // Verify encrypted file is different from original
        let encryptedData = try Data(contentsOf: encryptedURL)
        XCTAssertNotEqual(encryptedData, testData)
        
        // Decrypt file
        let decryptedURL = tempDir.appendingPathComponent("test_decrypted.txt")
        try cryptoVault.decryptFile(at: encryptedURL, to: decryptedURL, with: key)
        
        let decryptedData = try Data(contentsOf: decryptedURL)
        XCTAssertEqual(decryptedData, testData)
        
        // Cleanup
        try? FileManager.default.removeItem(at: sourceURL)
        try? FileManager.default.removeItem(at: encryptedURL)
        try? FileManager.default.removeItem(at: decryptedURL)
    }
    
    // MARK: - Key Storage Tests
    
    func testStoreAndRetrieveKey() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let keyID = "test-key-\(UUID().uuidString)"
        
        // Store key
        try cryptoVault.storeKey(key, withIdentifier: keyID)
        
        // Retrieve key
        let retrievedKey = try cryptoVault.retrieveKey(withIdentifier: keyID)
        
        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, 
                      retrievedKey.withUnsafeBytes { Data($0) })
        
        // Cleanup
        try? cryptoVault.deleteKey(withIdentifier: keyID)
    }
    
    func testDeleteKey() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let keyID = "test-key-delete-\(UUID().uuidString)"
        
        // Store key
        try cryptoVault.storeKey(key, withIdentifier: keyID)
        
        // Verify key exists
        XCTAssertNoThrow(try cryptoVault.retrieveKey(withIdentifier: keyID))
        
        // Delete key
        try cryptoVault.deleteKey(withIdentifier: keyID)
        
        // Verify key no longer exists
        XCTAssertThrowsError(try cryptoVault.retrieveKey(withIdentifier: keyID))
    }
    
    func testKeyExistence() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let keyID = "test-key-exists-\(UUID().uuidString)"
        
        // Key should not exist initially
        XCTAssertFalse(cryptoVault.keyExists(withIdentifier: keyID))
        
        // Store key
        try cryptoVault.storeKey(key, withIdentifier: keyID)
        
        // Key should now exist
        XCTAssertTrue(cryptoVault.keyExists(withIdentifier: keyID))
        
        // Cleanup
        try? cryptoVault.deleteKey(withIdentifier: keyID)
        
        // Key should no longer exist
        XCTAssertFalse(cryptoVault.keyExists(withIdentifier: keyID))
    }
    
    // MARK: - Master Key Tests
    
    func testGenerateMasterKey() throws {
        let masterKey = try cryptoVault.generateMasterKey()
        
        XCTAssertNotNil(masterKey)
        XCTAssertEqual(masterKey.bitCount, 256)
    }
    
    func testMasterKeyDerivation() throws {
        let password = "test-password-123"
        let salt = try cryptoVault.generateSalt()
        
        let derivedKey1 = try cryptoVault.deriveKey(from: password, salt: salt)
        let derivedKey2 = try cryptoVault.deriveKey(from: password, salt: salt)
        
        // Same password and salt should produce same key
        XCTAssertEqual(derivedKey1.withUnsafeBytes { Data($0) },
                      derivedKey2.withUnsafeBytes { Data($0) })
        
        // Different salt should produce different key
        let differentSalt = try cryptoVault.generateSalt()
        let derivedKey3 = try cryptoVault.deriveKey(from: password, salt: differentSalt)
        
        XCTAssertNotEqual(derivedKey1.withUnsafeBytes { Data($0) },
                         derivedKey3.withUnsafeBytes { Data($0) })
    }
    
    // MARK: - Performance Tests
    
    func testEncryptionPerformance() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let largeData = Data(repeating: 0x42, count: 1024 * 1024) // 1MB
        
        measure {
            do {
                _ = try cryptoVault.encrypt(data: largeData, with: key)
            } catch {
                XCTFail("Encryption failed: \(error)")
            }
        }
    }
    
    func testDecryptionPerformance() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let largeData = Data(repeating: 0x42, count: 1024 * 1024) // 1MB
        let encryptedData = try cryptoVault.encrypt(data: largeData, with: key)
        
        measure {
            do {
                _ = try cryptoVault.decrypt(data: encryptedData, with: key)
            } catch {
                XCTFail("Decryption failed: \(error)")
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testDecryptionWithCorruptedData() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let encryptedData = try cryptoVault.encrypt(data: testData, with: key)
        
        // Corrupt the encrypted data
        var corruptedData = encryptedData
        corruptedData[0] = corruptedData[0] ^ 0xFF
        
        XCTAssertThrowsError(try cryptoVault.decrypt(data: corruptedData, with: key))
    }
    
    func testDecryptionWithInvalidData() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let invalidData = Data([0x00, 0x01, 0x02, 0x03]) // Too short to be valid encrypted data
        
        XCTAssertThrowsError(try cryptoVault.decrypt(data: invalidData, with: key))
    }
    
    func testKeyStorageWithInvalidIdentifier() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let emptyIdentifier = ""
        
        XCTAssertThrowsError(try cryptoVault.storeKey(key, withIdentifier: emptyIdentifier))
    }
    
    // MARK: - Security Tests
    
    func testKeyWiping() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let keyData = key.withUnsafeBytes { Data($0) }
        
        // Use the key for encryption
        let encryptedData = try cryptoVault.encrypt(data: testData, with: key)
        
        // Verify encryption worked
        XCTAssertNotEqual(encryptedData, testData)
        
        // The key should still be valid for decryption
        let decryptedData = try cryptoVault.decrypt(data: encryptedData, with: key)
        XCTAssertEqual(decryptedData, testData)
    }
    
    func testSecureRandomGeneration() throws {
        let random1 = try cryptoVault.generateSecureRandom(length: 32)
        let random2 = try cryptoVault.generateSecureRandom(length: 32)
        
        XCTAssertEqual(random1.count, 32)
        XCTAssertEqual(random2.count, 32)
        XCTAssertNotEqual(random1, random2)
    }
    
    // MARK: - Integration Tests
    
    func testFullDocumentEncryptionWorkflow() throws {
        let key = try cryptoVault.generateEncryptionKey()
        let keyID = "document-key-\(UUID().uuidString)"
        
        // Store the key
        try cryptoVault.storeKey(key, withIdentifier: keyID)
        
        // Encrypt document data
        let encryptedData = try cryptoVault.encrypt(data: testData, with: key)
        
        // Simulate storing encrypted data and key ID
        let storedKeyID = keyID
        let storedEncryptedData = encryptedData
        
        // Simulate retrieving and decrypting
        let retrievedKey = try cryptoVault.retrieveKey(withIdentifier: storedKeyID)
        let decryptedData = try cryptoVault.decrypt(data: storedEncryptedData, with: retrievedKey)
        
        XCTAssertEqual(decryptedData, testData)
        
        // Cleanup
        try cryptoVault.deleteKey(withIdentifier: keyID)
    }
}

// MARK: - Test Helpers

extension CryptoVaultTests {
    
    func createTestDocument() -> Data {
        let testContent = """
        This is a test document with multiple lines.
        It contains various types of content including:
        - Numbers: 123, 456, 789
        - Special characters: !@#$%^&*()
        - Unicode: 🔒🔑📄
        
        This document is used for testing encryption and decryption functionality.
        """
        return testContent.data(using: .utf8)!
    }
    
    func measureMemoryUsage<T>(operation: () throws -> T) rethrows -> T {
        let startMemory = mach_task_basic_info()
        let result = try operation()
        let endMemory = mach_task_basic_info()
        
        let memoryUsed = endMemory.resident_size - startMemory.resident_size
        print("Memory used: \(memoryUsed) bytes")
        
        return result
    }
}

// MARK: - Memory Info Helper

func mach_task_basic_info() -> mach_task_basic_info_data_t {
    var info = mach_task_basic_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
    
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_,
                     task_flavor_t(MACH_TASK_BASIC_INFO),
                     $0,
                     &count)
        }
    }
    
    if kerr == KERN_SUCCESS {
        return info
    } else {
        return mach_task_basic_info_data_t()
    }
}

