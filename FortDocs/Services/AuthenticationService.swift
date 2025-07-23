import Foundation
import LocalAuthentication
import SwiftUI
import CryptoKit
import Security

@MainActor
class AuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var biometricType: LABiometryType = .none
    @Published var authenticationError: String?
    @Published var failedAttempts = 0
    @Published var isLocked = false
    @Published var lockoutEndTime: Date?
    
    private let keychain = KeychainService()
    private let maxFailedAttempts = 5
    private let lockoutDurations: [TimeInterval] = [30, 300, 1800, 3600, 86400] // 30s, 5m, 30m, 1h, 24h
    
    // MARK: - Initialization
    
    init() {
        checkBiometricAvailability()
        checkLockoutStatus()
    }
    
    // MARK: - Public Properties
    
    var hasPINSet: Bool {
        keychain.hasPIN()
    }
    
    var canUseBiometrics: Bool {
        biometricType != .none && keychain.isBiometricsEnabled()
    }
    
    var isLockedOut: Bool {
        guard let lockoutEndTime = lockoutEndTime else { return false }
        return Date() < lockoutEndTime
    }
    
    var remainingLockoutTime: TimeInterval {
        guard let lockoutEndTime = lockoutEndTime else { return 0 }
        return max(0, lockoutEndTime.timeIntervalSinceNow)
    }
    
    // MARK: - Authentication Methods
    
    func authenticateWithBiometrics() async throws {
        guard canUseBiometrics else {
            throw AuthenticationError.biometricsNotAvailable
        }
        
        guard !isLockedOut else {
            throw AuthenticationError.accountLocked(remainingTime: remainingLockoutTime)
        }
        
        let context = LAContext()
        context.localizedFallbackTitle = "Use PIN"
        
        do {
            let reason = "Authenticate to access your secure documents"
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            
            if success {
                await handleSuccessfulAuthentication()
            }
        } catch {
            await handleAuthenticationFailure(error)
            throw error
        }
    }
    
    func authenticateWithPIN(_ pin: String) async throws {
        guard !isLockedOut else {
            throw AuthenticationError.accountLocked(remainingTime: remainingLockoutTime)
        }
        
        guard pin.count == 5 && pin.allSatisfy({ $0.isNumber }) else {
            throw AuthenticationError.invalidPIN
        }
        
        do {
            let isValid = try keychain.validatePIN(pin)
            
            if isValid {
                await handleSuccessfulAuthentication()
            } else {
                await handleFailedAttempt()
                throw AuthenticationError.incorrectPIN
            }
        } catch {
            await handleFailedAttempt()
            throw error
        }
    }
    
    func setPIN(_ pin: String) async throws {
        guard pin.count == 5 && pin.allSatisfy({ $0.isNumber }) else {
            throw AuthenticationError.invalidPIN
        }
        
        do {
            try keychain.storePIN(pin)
            await handleSuccessfulAuthentication()
        } catch {
            throw AuthenticationError.pinStorageFailed
        }
    }
    
    func changePIN(currentPIN: String, newPIN: String) async throws {
        guard !isLockedOut else {
            throw AuthenticationError.accountLocked(remainingTime: remainingLockoutTime)
        }
        
        // Validate current PIN
        try await authenticateWithPIN(currentPIN)
        
        // Set new PIN
        try await setPIN(newPIN)
    }
    
    func enableBiometrics() async throws {
        guard biometricType != .none else {
            throw AuthenticationError.biometricsNotAvailable
        }
        
        let context = LAContext()
        let reason = "Enable biometric authentication for FortDocs"
        
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            
            if success {
                keychain.setBiometricsEnabled(true)
            }
        } catch {
            throw AuthenticationError.biometricsEnableFailed
        }
    }
    
    func disableBiometrics() {
        keychain.setBiometricsEnabled(false)
    }
    
    func logout() {
        isAuthenticated = false
        authenticationError = nil
    }
    
    // MARK: - Private Methods
    
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }
    
    private func checkLockoutStatus() {
        failedAttempts = keychain.getFailedAttempts()
        
        if let lockoutEndTimeStamp = keychain.getLockoutEndTime(), lockoutEndTimeStamp > Date().timeIntervalSince1970 {
            lockoutEndTime = Date(timeIntervalSince1970: lockoutEndTimeStamp)
            isLocked = true
            
            // Set up timer to unlock when lockout period ends
            setupUnlockTimer()
        }
    }
    
    private func handleSuccessfulAuthentication() async {
        isAuthenticated = true
        authenticationError = nil
        failedAttempts = 0
        isLocked = false
        lockoutEndTime = nil
        
        // Clear failed attempts and lockout data
        keychain.clearFailedAttempts()
        keychain.clearLockoutEndTime()
    }
    
    private func handleFailedAttempt() async {
        failedAttempts += 1
        keychain.setFailedAttempts(failedAttempts)
        
        if failedAttempts >= maxFailedAttempts {
            await lockAccount()
        }
    }
    
    private func handleAuthenticationFailure(_ error: Error) async {
        if let laError = error as? LAError {
            switch laError.code {
            case .userCancel, .userFallback:
                authenticationError = nil
            case .biometryNotAvailable:
                authenticationError = "Biometric authentication is not available"
            case .biometryNotEnrolled:
                authenticationError = "No biometric data is enrolled"
            case .biometryLockout:
                authenticationError = "Biometric authentication is locked. Use your device passcode."
            default:
                authenticationError = "Authentication failed: \(laError.localizedDescription)"
            }
        } else {
            authenticationError = error.localizedDescription
        }
        
        await handleFailedAttempt()
    }
    
    private func lockAccount() async {
        let lockoutIndex = min(failedAttempts - maxFailedAttempts, lockoutDurations.count - 1)
        let lockoutDuration = lockoutDurations[lockoutIndex]
        
        lockoutEndTime = Date().addingTimeInterval(lockoutDuration)
        isLocked = true
        
        keychain.setLockoutEndTime(lockoutEndTime!.timeIntervalSince1970)
        
        setupUnlockTimer()
    }
    
    private func setupUnlockTimer() {
        guard let lockoutEndTime = lockoutEndTime else { return }
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                if Date() >= lockoutEndTime {
                    self.isLocked = false
                    self.lockoutEndTime = nil
                    self.keychain.clearLockoutEndTime()
                    timer.invalidate()
                }
            }
        }
    }
}

// MARK: - Authentication Errors

enum AuthenticationError: LocalizedError {
    case biometricsNotAvailable
    case biometricsEnableFailed
    case invalidPIN
    case incorrectPIN
    case pinStorageFailed
    case accountLocked(remainingTime: TimeInterval)
    case keychainError(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .biometricsNotAvailable:
            return "Biometric authentication is not available on this device"
        case .biometricsEnableFailed:
            return "Failed to enable biometric authentication"
        case .invalidPIN:
            return "PIN must be exactly 5 digits"
        case .incorrectPIN:
            return "Incorrect PIN entered"
        case .pinStorageFailed:
            return "Failed to store PIN securely"
        case .accountLocked(let remainingTime):
            let minutes = Int(remainingTime / 60)
            let seconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))
            if minutes > 0 {
                return "Account locked for \(minutes)m \(seconds)s"
            } else {
                return "Account locked for \(seconds) seconds"
            }
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}

// MARK: - Keychain Service

private class KeychainService {
    private let pinKey = "com.fortdocs.pin"
    private let biometricsEnabledKey = "com.fortdocs.biometrics.enabled"
    private let failedAttemptsKey = "com.fortdocs.failed.attempts"
    private let lockoutEndTimeKey = "com.fortdocs.lockout.endtime"
    
    // MARK: - PIN Management
    
    func storePIN(_ pin: String) throws {
        let pinData = pin.data(using: .utf8)!
        let hashedPIN = SHA256.hash(data: pinData)
        let hashedData = Data(hashedPIN)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKey,
            kSecValueData as String: hashedData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing PIN first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthenticationError.keychainError(status)
        }
    }
    
    func validatePIN(_ pin: String) throws -> Bool {
        let pinData = pin.data(using: .utf8)!
        let hashedPIN = SHA256.hash(data: pinData)
        let hashedData = Data(hashedPIN)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let storedData = result as? Data else {
            if status == errSecItemNotFound {
                return false
            }
            throw AuthenticationError.keychainError(status)
        }
        
        return storedData == hashedData
    }
    
    func hasPIN() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKey,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Biometrics Settings
    
    func setBiometricsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: biometricsEnabledKey)
    }
    
    func isBiometricsEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: biometricsEnabledKey)
    }
    
    // MARK: - Failed Attempts Tracking
    
    func setFailedAttempts(_ count: Int) {
        UserDefaults.standard.set(count, forKey: failedAttemptsKey)
    }
    
    func getFailedAttempts() -> Int {
        return UserDefaults.standard.integer(forKey: failedAttemptsKey)
    }
    
    func clearFailedAttempts() {
        UserDefaults.standard.removeObject(forKey: failedAttemptsKey)
    }
    
    // MARK: - Lockout Management
    
    func setLockoutEndTime(_ timestamp: TimeInterval) {
        UserDefaults.standard.set(timestamp, forKey: lockoutEndTimeKey)
    }
    
    func getLockoutEndTime() -> TimeInterval? {
        let timestamp = UserDefaults.standard.double(forKey: lockoutEndTimeKey)
        return timestamp > 0 ? timestamp : nil
    }
    
    func clearLockoutEndTime() {
        UserDefaults.standard.removeObject(forKey: lockoutEndTimeKey)
    }
}

