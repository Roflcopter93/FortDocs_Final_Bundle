import Foundation
import CryptoKit
import Security
import LocalAuthentication

/// CryptoVault is responsible for generating and managing encryption keys,
/// performing symmetric encryption/decryption and providing convenience
/// methods for securely storing document data.  The implementation here
/// mirrors the upstream project but includes additional hardening around
/// temporary file protection and support for encrypted search tokens.
class CryptoVault: ObservableObject {
    static let shared = CryptoVault()

    private let keychain = KeychainManager()
    private var masterKey: SymmetricKey?
    private let fileManager = FileManager.default

    // Constants
    private let masterKeyTag = "com.fortdocs.masterkey"
    private let keySize = 32 // 256 bits
    private let nonceSize = 12 // 96 bits for AES‑GCM
    private let tagSize = 16  // 128 bits for authentication tag

    private init() {
        setupMasterKey()
    }

    // MARK: - Public Methods

    func encryptDocument(at sourceURL: URL, to destinationURL: URL) throws {
        guard let masterKey = masterKey else {
            throw CryptoVaultError.masterKeyNotAvailable
        }

        // Read source file
        let plainData = try Data(contentsOf: sourceURL)

        // Generate document‑specific key
        let documentKey = try deriveDocumentKey(from: masterKey, documentID: destinationURL.lastPathComponent)

        // Encrypt data
        let encryptedData = try encryptData(plainData, with: documentKey)

        // Write encrypted data
        try encryptedData.write(to: destinationURL)

        // Set file protection
        try setFileProtection(for: destinationURL)
    }

    func decryptDocument(at sourceURL: URL, to destinationURL: URL) throws {
        guard let masterKey = masterKey else {
            throw CryptoVaultError.masterKeyNotAvailable
        }

        // Read encrypted file
        let encryptedData = try Data(contentsOf: sourceURL)

        // Generate document‑specific key
        let documentKey = try deriveDocumentKey(from: masterKey, documentID: sourceURL.lastPathComponent)

        // Decrypt data
        let plainData = try decryptData(encryptedData, with: documentKey)

        // Write decrypted data
        try plainData.write(to: destinationURL)
    }

    /// Decrypts an encrypted file into a secure temporary location and returns the resulting URL.
    ///
    /// The returned file resides in the system temporary directory and is immediately marked
    /// with complete file protection.  Without explicitly setting this attribute the file
    /// would remain unprotected on disk until removal.  Complete protection ensures
    /// the file is inaccessible on disk while the device is locked.
    func getDecryptedFileURL(for encryptedURL: URL) throws -> URL {
        guard masterKey != nil else {
            throw CryptoVaultError.masterKeyNotAvailable
        }
        let tempDirectory = fileManager.temporaryDirectory
        let tempFileName = UUID().uuidString + "_decrypted"
        let tempURL = tempDirectory.appendingPathComponent(tempFileName)
        // Decrypt to temporary location
        try decryptDocument(at: encryptedURL, to: tempURL)
        // Apply file protection to the decrypted temporary file
        try? setFileProtection(for: tempURL)
        return tempURL
    }

    func encryptInPlace(fileURL: URL) throws -> String {
        let tempURL = fileURL.appendingPathExtension("tmp")
        try encryptDocument(at: fileURL, to: tempURL)
        // Replace original with encrypted version
        _ = try fileManager.replaceItem(at: fileURL, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
        try setFileProtection(for: fileURL)
        return fileURL.lastPathComponent
    }

    func verifyIntegrity(of encryptedURL: URL) throws -> Bool {
        guard let masterKey = masterKey else {
            throw CryptoVaultError.masterKeyNotAvailable
        }
        let encryptedData = try Data(contentsOf: encryptedURL)
        let documentKey = try deriveDocumentKey(from: masterKey, documentID: encryptedURL.lastPathComponent)
        do {
            _ = try decryptData(encryptedData, with: documentKey)
            return true
        } catch {
            return false
        }
    }

    func rotateMasterKey() throws {
        let newMasterKey = SymmetricKey(size: .bits256)
        try keychain.storeMasterKey(newMasterKey, tag: masterKeyTag)
        self.masterKey = newMasterKey
        // Re‑encrypting existing data is omitted for brevity
    }

    // MARK: - Private Methods

    private func setupMasterKey() {
        do {
            if let existingKey = try keychain.retrieveMasterKey(tag: masterKeyTag) {
                self.masterKey = existingKey
                return
            }
            let newMasterKey = SymmetricKey(size: .bits256)
            try keychain.storeMasterKey(newMasterKey, tag: masterKeyTag)
            self.masterKey = newMasterKey
        } catch {
            print("Failed to setup master key: \(error)")
        }
    }

    private func deriveDocumentKey(from masterKey: SymmetricKey, documentID: String) throws -> SymmetricKey {
        let info = documentID.data(using: .utf8) ?? Data()
        let salt = Data("FortDocs.DocumentKey".utf8)
        return HKDF.deriveKey(
            inputKeyMaterial: masterKey,
            salt: salt,
            info: info,
            outputByteCount: keySize
        )
    }

    private func encryptData(_ data: Data, with key: SymmetricKey) throws -> Data {
        var nonce = Data(count: nonceSize)
        let result = nonce.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, nonceSize, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        guard result == errSecSuccess else {
            throw CryptoVaultError.randomGenerationFailed
        }
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: AES.GCM.Nonce(data: nonce))
        var encryptedData = Data()
        encryptedData.append(nonce)
        encryptedData.append(sealedBox.ciphertext)
        encryptedData.append(sealedBox.tag)
        return encryptedData
    }

    // MARK: - Async Wrappers
    func encryptDataAsync(_ data: Data, with key: SymmetricKey, completion: @escaping (Result<Data, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try self.encryptData(data, with: key)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func decryptData(_ encryptedData: Data, with key: SymmetricKey) throws -> Data {
        guard encryptedData.count >= nonceSize + tagSize else {
            throw CryptoVaultError.invalidEncryptedData
        }
        let nonce = encryptedData.prefix(nonceSize)
        let ciphertext = encryptedData.dropFirst(nonceSize).dropLast(tagSize)
        let tag = encryptedData.suffix(tagSize)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(sealedBox, using: key)
    }

    func decryptDataAsync(_ encryptedData: Data, with key: SymmetricKey, completion: @escaping (Result<Data, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try self.decryptData(encryptedData, with: key)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - String Helpers
    func encryptString(_ string: String, documentID: String) throws -> String {
        guard let masterKey = masterKey else { throw CryptoVaultError.masterKeyNotAvailable }
        let key = try deriveDocumentKey(from: masterKey, documentID: documentID)
        let data = Data(string.utf8)
        let encrypted = try encryptData(data, with: key)
        return encrypted.base64EncodedString()
    }

    func decryptString(_ base64: String, documentID: String) throws -> String {
        guard let masterKey = masterKey else { throw CryptoVaultError.masterKeyNotAvailable }
        let key = try deriveDocumentKey(from: masterKey, documentID: documentID)
        guard let data = Data(base64Encoded: base64) else { throw CryptoVaultError.invalidEncryptedData }
        let decrypted = try decryptData(data, with: key)
        return String(decoding: decrypted, as: UTF8.self)
    }

    // MARK: - Encrypted Search Helpers
    /// Derives a deterministic search key from the master key using HKDF.  The derived key
    /// is used to compute HMACs for search tokens without revealing the master key itself.
    private func deriveSearchKey() throws -> SymmetricKey {
        guard let masterKey = masterKey else { throw CryptoVaultError.masterKeyNotAvailable }
        let info = Data("FortDocs.SearchKey".utf8)
        let salt = Data("FortDocs.SearchKeySalt".utf8)
        return HKDF.deriveKey(
            inputKeyMaterial: masterKey,
            salt: salt,
            info: info,
            outputByteCount: keySize
        )
    }

    /// Computes a keyed hash of a search token using HMAC‑SHA256 and the derived search key.
    /// The returned data can be safely stored alongside index entries and compared
    /// against hashed user queries without decrypting document content.
    func hashedToken(_ token: String) throws -> Data {
        let searchKey = try deriveSearchKey()
        let data = Data(token.lowercased().utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: searchKey)
        return Data(hmac)
    }

    private func setFileProtection(for url: URL) throws {
        try fileManager.setAttributes([
            .protectionKey: FileProtectionType.complete
        ], ofItemAtPath: url.path)
    }
}

// MARK: - Keychain Manager
private class KeychainManager {
    func storeMasterKey(_ key: SymmetricKey, tag: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrAccessControl as String: try createAccessControl()
        ]
        // Delete existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        // Add new key
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CryptoVaultError.keychainError(status)
        }
    }

    func retrieveMasterKey(tag: String) throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw CryptoVaultError.keychainError(status)
        }
        guard let keyData = result as? Data else {
            throw CryptoVaultError.invalidKeyData
        }
        return SymmetricKey(data: keyData)
    }

    private func createAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.biometryAny, .or, .devicePasscode],
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                throw CryptoVaultError.accessControlCreationFailed(error)
            }
            throw CryptoVaultError.accessControlCreationFailed(nil)
        }
        return accessControl
    }
}

// MARK: - Crypto Vault Errors
enum CryptoVaultError: LocalizedError {
    case masterKeyNotAvailable
    case randomGenerationFailed
    case invalidEncryptedData
    case invalidKeyData
    case keychainError(OSStatus)
    case accessControlCreationFailed(CFError?)

    var errorDescription: String? {
        switch self {
        case .masterKeyNotAvailable:
            return "Master encryption key is not available"
        case .randomGenerationFailed:
            return "Failed to generate random data"
        case .invalidEncryptedData:
            return "Invalid encrypted data format"
        case .invalidKeyData:
            return "Invalid key data retrieved from keychain"
        case .keychainError(let status):
            return status.keychainErrorMessage
        case .accessControlCreationFailed(let error):
            return "Failed to create access control: \(error?.localizedDescription ?? \"Unknown error\")"
        }
    }
}