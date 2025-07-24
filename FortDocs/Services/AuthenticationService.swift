import Foundation
import LocalAuthentication
import SwiftUI
import UIKit
import CryptoKit
import Security

/// Service responsible for handling all user authentication logic.  This includes
/// biometric authentication, PIN based authentication, and associated state
/// management such as lockouts and failed attempt counters.  The API closely
/// mirrors the original implementation from the upstream project, but has
/// been updated to provide more descriptive error handling and to centralise
/// common behaviours.
@MainActor
final class AuthenticationService: ObservableObject {
    /// Shared singleton instance used throughout the application.
    static let shared = AuthenticationService()

    // Published properties to drive SwiftUI views
    @Published var isAuthenticated = false
    @Published var biometricType: LABiometryType = .none
    @Published var authenticationError: String?
    @Published var failedAttempts = 0
    @Published var isLocked = false
    @Published var lockoutEndTime: Date?
    @Published var autoLockTimeout: TimeInterval = 0

    private let keychain = KeychainService()
    private let maxFailedAttempts = 5
    private let lockoutDurations: [TimeInterval] = [30, 300, 1800, 3600, 86400]
    private let autoLockKey = "AutoLockTimeout"
    private var lastInactiveDate: Date?

    // MARK: - Initialization

    init() {
        checkBiometricAvailability()
        checkLockoutStatus()
        autoLockTimeout = UserDefaults.standard.double(forKey: autoLockKey)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - Computed properties

    /// Indicates whether a PIN has been set in the keychain.
    var hasPINSet: Bool { keychain.hasPIN() }

    /// Returns `true` if the device supports biometrics and the user has opted in.
    var canUseBiometrics: Bool { biometricType != .none && keychain.isBiometricsEnabled() }

    /// Indicates whether the account is currently locked out.
    var isLockedOut: Bool {
        guard let lockoutEndTime = lockoutEndTime else { return false }
        return Date() < lockoutEndTime
    }

    /// The remaining time (in seconds) before a lockout is lifted.
    var remainingLockoutTime: TimeInterval {
        guard let lockoutEndTime = lockoutEndTime else { return 0 }
        return max(0, lockoutEndTime.timeIntervalSinceNow)
    }

    // MARK: - Authentication

    /// Perform biometric authentication using Face ID or Touch ID.  Throws an
    /// `AuthenticationError` when the device does not support biometrics or
    /// when the account is locked.  Any errors propagated from the LAContext
    /// evaluation will also be rethrown to the caller.
    func authenticateWithBiometrics() async throws {
        guard canUseBiometrics else { throw AuthenticationError.biometricsNotAvailable }
        guard !isLockedOut else { throw AuthenticationError.accountLocked(remainingTime: remainingLockoutTime) }

        let context = LAContext()
        context.localizedFallbackTitle = "Use PIN"

        do {
            let reason = "Authenticate to access your secure documents"
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if success { await handleSuccessfulAuthentication() }
        } catch {
            await handleFailedAttempt()
            throw error
        }
    }

    /// Authenticate with a 5‑digit PIN.  Invalid or incorrect PINs throw
    /// descriptive `AuthenticationError`s.  On failure the failed attempt
    /// counter is incremented which may eventually trigger a lockout.
    func authenticateWithPIN(_ pin: String) async throws {
        guard !isLockedOut else { throw AuthenticationError.accountLocked(remainingTime: remainingLockoutTime) }
        guard pin.count == 5 && pin.allSatisfy({ $0.isNumber }) else { throw AuthenticationError.invalidPIN }

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
            // Surface a keychain specific error when encountered
            if case AuthenticationError.keychainError = error {
                throw error
            }
            throw AuthenticationError.keychainError((error as NSError).code == 0 ? errSecInternalComponent : OSStatus((error as NSError).code))
        }
    }

    /// Persist a new 5‑digit PIN in the Keychain.  After setting the PIN the
    /// user is considered authenticated.  Throws on invalid input or storage
    /// failures.
    func setPIN(_ pin: String) async throws {
        guard pin.count == 5 && pin.allSatisfy({ $0.isNumber }) else { throw AuthenticationError.invalidPIN }
        do {
            try keychain.storePIN(pin)
            await handleSuccessfulAuthentication()
        } catch {
            throw AuthenticationError.pinStorageFailed
        }
    }

    /// Change the current PIN by verifying the existing PIN and setting a new one.
    func changePIN(currentPIN: String, newPIN: String) async throws {
        guard !isLockedOut else { throw AuthenticationError.accountLocked(remainingTime: remainingLockoutTime) }
        // Validate current PIN
        try await authenticateWithPIN(currentPIN)
        // Set the new PIN
        try await setPIN(newPIN)
    }

    /// Enable biometric authentication.  If the device does not support
    /// biometrics an error is thrown.  Any errors returned by LAContext
    /// evaluation are propagated.
    func enableBiometrics() async throws {
        guard biometricType != .none else { throw AuthenticationError.biometricsNotAvailable }
        let context = LAContext()
        let reason = "Enable biometric authentication for FortDocs"
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if success { keychain.setBiometricsEnabled(true) }
        } catch {
            throw AuthenticationError.biometricsEnableFailed
        }
    }

    /// Disable biometric authentication.
    func disableBiometrics() { keychain.setBiometricsEnabled(false) }

    /// Logs the user out by resetting authentication state.
    func logout() {
        isAuthenticated = false
        authenticationError = nil
    }

    /// Update the auto‑lock timeout and persist it to UserDefaults.
    func updateAutoLockTimeout(_ timeout: TimeInterval) {
        autoLockTimeout = timeout
        UserDefaults.standard.set(timeout, forKey: autoLockKey)
    }

    // MARK: - App Lifecycle Handlers

    @objc private func appWillResignActive() {
        lastInactiveDate = Date()
    }

    @objc private func appDidBecomeActive() {
        // If the app was inactive longer than the auto‑lock timeout, require re‑authentication
        if let last = lastInactiveDate, autoLockTimeout > 0 {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed >= autoLockTimeout {
                isAuthenticated = false
                NotificationCenter.default.post(name: .requireReAuthentication, object: nil)
            }
        }
        lastInactiveDate = nil
    }

    // MARK: - Private helpers

    /// Check the type of biometric available on the device.
    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }

    /// Check persisted lockout status at startup.
    private func checkLockoutStatus() {
        failedAttempts = keychain.getFailedAttempts()
        if let lockoutEndTimeStamp = keychain.getLockoutEndTime(), lockoutEndTimeStamp > Date().timeIntervalSince1970 {
            lockoutEndTime = Date(timeIntervalSince1970: lockoutEndTimeStamp)
            isLocked = true
            setupUnlockTimer()
        }
    }

    /// Handle a successful authentication by resetting state and clearing lockout data.
    private func handleSuccessfulAuthentication() async {
        isAuthenticated = true
        authenticationError = nil
        failedAttempts = 0
        isLocked = false
        lockoutEndTime = nil
        keychain.clearFailedAttempts()
        keychain.clearLockoutEndTime()
    }

    /// Increment the failed attempt counter and trigger a lockout if necessary.
    private func handleFailedAttempt() async {
        failedAttempts += 1
        keychain.setFailedAttempts(failedAttempts)
        if failedAttempts >= maxFailedAttempts {
            await lockAccount()
        }
    }

    /// Lock the account for a duration that grows exponentially based on the number of failed attempts.
    private func lockAccount() async {
        isLocked = true
        let attemptIndex = min(failedAttempts - maxFailedAttempts, lockoutDurations.count - 1)
        let lockoutDuration = lockoutDurations[max(0, attemptIndex)]
        let endTime = Date().addingTimeInterval(lockoutDuration)
        lockoutEndTime = endTime
        keychain.setLockoutEndTime(endTime.timeIntervalSince1970)
        // Schedule unlock
        setupUnlockTimer()
    }

    /// Set up a timer to unlock the account when the lockout period expires.
    private func setupUnlockTimer() {
        guard let lockoutEndTime = lockoutEndTime else { return }
        let delay = max(0, lockoutEndTime.timeIntervalSinceNow)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.isLocked = false
            self.failedAttempts = 0
            self.lockoutEndTime = nil
            keychain.clearFailedAttempts()
            keychain.clearLockoutEndTime()
        }
    }

    // MARK: - Nested Types

    /// Custom error type for all authentication operations.  Each case maps to
    /// a user friendly description via `errorDescription`.
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
                return "Biometric authentication is not available on this device."
            case .biometricsEnableFailed:
                return "Failed to enable biometric authentication."
            case .invalidPIN:
                return "PIN must be exactly 5 digits."
            case .incorrectPIN:
                return "Incorrect PIN entered."
            case .pinStorageFailed:
                return "Failed to store PIN securely."
            case .accountLocked(let remainingTime):
                let minutes = Int(remainingTime / 60)
                let seconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))
                if minutes > 0 {
                    return "Account locked for \(minutes)m \(seconds)s."
                } else {
                    return "Account locked for \(seconds) seconds."
                }
            case .keychainError(let status):
                // Use the OSStatus extension to produce a friendly message
                return status.keychainErrorMessage
            }
        }
    }

    /// Private helper encapsulating all keychain interactions.  Throws
    /// `AuthenticationError.keychainError` when a low level failure occurs.
    private class KeychainService {
        private let pinKey = "com.fortdocs.pin"
        private let biometricsEnabledKey = "com.fortdocs.biometrics.enabled"
        private let failedAttemptsKey = "com.fortdocs.failed.attempts"
        private let lockoutEndTimeKey = "com.fortdocs.lockout.endtime"

        // MARK: PIN Management

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
            // Remove any existing entry before adding
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
                if status == errSecItemNotFound { return false }
                throw AuthenticationError.keychainError(status)
            }
            return timingSafeEqual(storedData, hashedData)
        }

        /// Perform a timing safe comparison to avoid side channel attacks.
        private func timingSafeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
            guard lhs.count == rhs.count else { return false }
            var difference: UInt8 = 0
            for i in 0..<lhs.count {
                difference |= lhs[i] ^ rhs[i]
            }
            return difference == 0
        }

        /// Check if a PIN currently exists in the keychain.
        func hasPIN() -> Bool {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: pinKey,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            let status = SecItemCopyMatching(query as CFDictionary, nil)
            return status == errSecSuccess
        }

        // MARK: Biometrics settings
        func setBiometricsEnabled(_ enabled: Bool) {
            UserDefaults.standard.set(enabled, forKey: biometricsEnabledKey)
        }
        func isBiometricsEnabled() -> Bool { UserDefaults.standard.bool(forKey: biometricsEnabledKey) }

        // MARK: Failed attempts tracking
        func setFailedAttempts(_ count: Int) { UserDefaults.standard.set(count, forKey: failedAttemptsKey) }
        func getFailedAttempts() -> Int { UserDefaults.standard.integer(forKey: failedAttemptsKey) }
        func clearFailedAttempts() { UserDefaults.standard.removeObject(forKey: failedAttemptsKey) }

        // MARK: Lockout management
        func setLockoutEndTime(_ timestamp: TimeInterval) { UserDefaults.standard.set(timestamp, forKey: lockoutEndTimeKey) }
        func getLockoutEndTime() -> TimeInterval? {
            let timestamp = UserDefaults.standard.double(forKey: lockoutEndTimeKey)
            return timestamp > 0 ? timestamp : nil
        }
        func clearLockoutEndTime() { UserDefaults.standard.removeObject(forKey: lockoutEndTimeKey) }
    }
}
