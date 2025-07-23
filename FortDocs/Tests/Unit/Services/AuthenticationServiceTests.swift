import XCTest
import LocalAuthentication
@testable import FortDocs

final class AuthenticationServiceTests: XCTestCase {
    
    var authService: AuthenticationService!
    var mockContext: MockLAContext!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        authService = AuthenticationService.shared
        mockContext = MockLAContext()
    }
    
    override func tearDownWithError() throws {
        authService = nil
        mockContext = nil
        
        // Clean up any stored test data
        UserDefaults.standard.removeObject(forKey: "HasSetupPIN")
        UserDefaults.standard.removeObject(forKey: "PINHash")
        UserDefaults.standard.removeObject(forKey: "PINSalt")
        UserDefaults.standard.removeObject(forKey: "FailedAttempts")
        UserDefaults.standard.removeObject(forKey: "LastFailedAttempt")
        UserDefaults.standard.removeObject(forKey: "LockoutUntil")
        
        try super.tearDownWithError()
    }
    
    // MARK: - Biometric Authentication Tests
    
    func testBiometricAvailability() {
        // Test when biometrics are available
        mockContext.canEvaluatePolicyResult = true
        mockContext.biometryType = .faceID
        
        let availability = authService.biometricAvailability(context: mockContext)
        
        XCTAssertEqual(availability, .faceID)
    }
    
    func testBiometricAvailabilityTouchID() {
        mockContext.canEvaluatePolicyResult = true
        mockContext.biometryType = .touchID
        
        let availability = authService.biometricAvailability(context: mockContext)
        
        XCTAssertEqual(availability, .touchID)
    }
    
    func testBiometricAvailabilityNone() {
        mockContext.canEvaluatePolicyResult = false
        mockContext.biometryType = .none
        
        let availability = authService.biometricAvailability(context: mockContext)
        
        XCTAssertEqual(availability, .none)
    }
    
    func testBiometricAuthenticationSuccess() async {
        mockContext.evaluatePolicyResult = .success(true)
        
        do {
            let result = try await authService.authenticateWithBiometrics(context: mockContext)
            XCTAssertTrue(result)
        } catch {
            XCTFail("Biometric authentication should have succeeded: \(error)")
        }
    }
    
    func testBiometricAuthenticationFailure() async {
        let authError = LAError(.authenticationFailed)
        mockContext.evaluatePolicyResult = .failure(authError)
        
        do {
            _ = try await authService.authenticateWithBiometrics(context: mockContext)
            XCTFail("Biometric authentication should have failed")
        } catch {
            XCTAssertTrue(error is LAError)
        }
    }
    
    func testBiometricAuthenticationUserCancel() async {
        let cancelError = LAError(.userCancel)
        mockContext.evaluatePolicyResult = .failure(cancelError)
        
        do {
            _ = try await authService.authenticateWithBiometrics(context: mockContext)
            XCTFail("Biometric authentication should have been cancelled")
        } catch {
            if let laError = error as? LAError {
                XCTAssertEqual(laError.code, .userCancel)
            } else {
                XCTFail("Expected LAError with userCancel code")
            }
        }
    }
    
    // MARK: - PIN Authentication Tests
    
    func testPINSetup() {
        let testPIN = "12345"
        
        XCTAssertFalse(authService.hasPINSetup())
        
        authService.setupPIN(testPIN)
        
        XCTAssertTrue(authService.hasPINSetup())
    }
    
    func testPINValidation() {
        let testPIN = "12345"
        let wrongPIN = "54321"
        
        authService.setupPIN(testPIN)
        
        XCTAssertTrue(authService.validatePIN(testPIN))
        XCTAssertFalse(authService.validatePIN(wrongPIN))
    }
    
    func testPINValidationWithEmptyPIN() {
        let testPIN = "12345"
        
        authService.setupPIN(testPIN)
        
        XCTAssertFalse(authService.validatePIN(""))
        XCTAssertFalse(authService.validatePIN("    "))
    }
    
    func testPINChange() {
        let oldPIN = "12345"
        let newPIN = "54321"
        
        authService.setupPIN(oldPIN)
        XCTAssertTrue(authService.validatePIN(oldPIN))
        
        let changeResult = authService.changePIN(currentPIN: oldPIN, newPIN: newPIN)
        XCTAssertTrue(changeResult)
        
        XCTAssertFalse(authService.validatePIN(oldPIN))
        XCTAssertTrue(authService.validatePIN(newPIN))
    }
    
    func testPINChangeWithWrongCurrentPIN() {
        let oldPIN = "12345"
        let wrongPIN = "11111"
        let newPIN = "54321"
        
        authService.setupPIN(oldPIN)
        
        let changeResult = authService.changePIN(currentPIN: wrongPIN, newPIN: newPIN)
        XCTAssertFalse(changeResult)
        
        // Original PIN should still work
        XCTAssertTrue(authService.validatePIN(oldPIN))
        XCTAssertFalse(authService.validatePIN(newPIN))
    }
    
    func testPINRemoval() {
        let testPIN = "12345"
        
        authService.setupPIN(testPIN)
        XCTAssertTrue(authService.hasPINSetup())
        
        authService.removePIN()
        XCTAssertFalse(authService.hasPINSetup())
        XCTAssertFalse(authService.validatePIN(testPIN))
    }
    
    // MARK: - Failed Attempts and Lockout Tests
    
    func testFailedAttemptsTracking() {
        let testPIN = "12345"
        let wrongPIN = "54321"
        
        authService.setupPIN(testPIN)
        
        XCTAssertEqual(authService.getFailedAttempts(), 0)
        
        // First failed attempt
        XCTAssertFalse(authService.validatePIN(wrongPIN))
        XCTAssertEqual(authService.getFailedAttempts(), 1)
        
        // Second failed attempt
        XCTAssertFalse(authService.validatePIN(wrongPIN))
        XCTAssertEqual(authService.getFailedAttempts(), 2)
        
        // Successful attempt should reset counter
        XCTAssertTrue(authService.validatePIN(testPIN))
        XCTAssertEqual(authService.getFailedAttempts(), 0)
    }
    
    func testLockoutAfterMaxFailedAttempts() {
        let testPIN = "12345"
        let wrongPIN = "54321"
        
        authService.setupPIN(testPIN)
        
        // Simulate max failed attempts
        for _ in 0..<5 {
            XCTAssertFalse(authService.validatePIN(wrongPIN))
        }
        
        XCTAssertTrue(authService.isLockedOut())
        
        // Even correct PIN should fail during lockout
        XCTAssertFalse(authService.validatePIN(testPIN))
    }
    
    func testLockoutDuration() {
        let testPIN = "12345"
        let wrongPIN = "54321"
        
        authService.setupPIN(testPIN)
        
        // Trigger lockout
        for _ in 0..<5 {
            XCTAssertFalse(authService.validatePIN(wrongPIN))
        }
        
        XCTAssertTrue(authService.isLockedOut())
        
        let lockoutDuration = authService.getLockoutDuration()
        XCTAssertGreaterThan(lockoutDuration, 0)
        XCTAssertLessThanOrEqual(lockoutDuration, 300) // Should be 5 minutes or less
    }
    
    func testResetFailedAttempts() {
        let testPIN = "12345"
        let wrongPIN = "54321"
        
        authService.setupPIN(testPIN)
        
        // Generate some failed attempts
        for _ in 0..<3 {
            XCTAssertFalse(authService.validatePIN(wrongPIN))
        }
        
        XCTAssertEqual(authService.getFailedAttempts(), 3)
        
        authService.resetFailedAttempts()
        XCTAssertEqual(authService.getFailedAttempts(), 0)
        XCTAssertFalse(authService.isLockedOut())
    }
    
    // MARK: - Security Tests
    
    func testPINHashingConsistency() {
        let testPIN = "12345"
        
        authService.setupPIN(testPIN)
        
        // Validate multiple times to ensure hash is consistent
        for _ in 0..<10 {
            XCTAssertTrue(authService.validatePIN(testPIN))
        }
    }
    
    func testPINSaltUniqueness() {
        let testPIN = "12345"
        
        // Setup PIN first time
        authService.setupPIN(testPIN)
        let firstSalt = UserDefaults.standard.data(forKey: "PINSalt")
        
        // Remove and setup again
        authService.removePIN()
        authService.setupPIN(testPIN)
        let secondSalt = UserDefaults.standard.data(forKey: "PINSalt")
        
        XCTAssertNotEqual(firstSalt, secondSalt)
    }
    
    func testPINHashDifferentWithDifferentSalts() {
        let testPIN = "12345"
        
        // Setup PIN first time
        authService.setupPIN(testPIN)
        let firstHash = UserDefaults.standard.data(forKey: "PINHash")
        
        // Remove and setup again with same PIN
        authService.removePIN()
        authService.setupPIN(testPIN)
        let secondHash = UserDefaults.standard.data(forKey: "PINHash")
        
        // Hashes should be different due to different salts
        XCTAssertNotEqual(firstHash, secondHash)
        
        // But both should validate the same PIN
        XCTAssertTrue(authService.validatePIN(testPIN))
    }
    
    // MARK: - Edge Cases Tests
    
    func testPINValidationWithoutSetup() {
        XCTAssertFalse(authService.hasPINSetup())
        XCTAssertFalse(authService.validatePIN("12345"))
    }
    
    func testPINSetupWithEmptyPIN() {
        authService.setupPIN("")
        XCTAssertFalse(authService.hasPINSetup())
    }
    
    func testPINSetupWithWhitespacePIN() {
        authService.setupPIN("   ")
        XCTAssertFalse(authService.hasPINSetup())
    }
    
    func testPINValidationCaseSensitivity() {
        // PINs should be case-sensitive if they contain letters
        let testPIN = "1a2B3"
        
        authService.setupPIN(testPIN)
        
        XCTAssertTrue(authService.validatePIN("1a2B3"))
        XCTAssertFalse(authService.validatePIN("1A2b3"))
    }
    
    // MARK: - Performance Tests
    
    func testPINValidationPerformance() {
        let testPIN = "12345"
        authService.setupPIN(testPIN)
        
        measure {
            for _ in 0..<100 {
                _ = authService.validatePIN(testPIN)
            }
        }
    }
    
    func testPINHashingPerformance() {
        let testPIN = "12345"
        
        measure {
            for _ in 0..<10 {
                authService.setupPIN(testPIN)
                authService.removePIN()
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testFullAuthenticationFlow() async {
        let testPIN = "12345"
        
        // Setup PIN
        authService.setupPIN(testPIN)
        XCTAssertTrue(authService.hasPINSetup())
        
        // Test biometric availability
        mockContext.canEvaluatePolicyResult = true
        mockContext.biometryType = .faceID
        let availability = authService.biometricAvailability(context: mockContext)
        XCTAssertEqual(availability, .faceID)
        
        // Test successful biometric authentication
        mockContext.evaluatePolicyResult = .success(true)
        do {
            let biometricResult = try await authService.authenticateWithBiometrics(context: mockContext)
            XCTAssertTrue(biometricResult)
        } catch {
            XCTFail("Biometric authentication failed: \(error)")
        }
        
        // Test PIN fallback
        XCTAssertTrue(authService.validatePIN(testPIN))
        
        // Test failed attempts and recovery
        XCTAssertFalse(authService.validatePIN("wrong"))
        XCTAssertEqual(authService.getFailedAttempts(), 1)
        
        XCTAssertTrue(authService.validatePIN(testPIN))
        XCTAssertEqual(authService.getFailedAttempts(), 0)
    }
}

// MARK: - Mock Classes

class MockLAContext: LAContext {
    var canEvaluatePolicyResult = false
    var evaluatePolicyResult: Result<Bool, Error> = .success(true)
    
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        return canEvaluatePolicyResult
    }
    
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        switch evaluatePolicyResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

// MARK: - Test Utilities

extension AuthenticationServiceTests {
    
    func simulateAppBackgrounding() {
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    func simulateAppForegrounding() {
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    func waitForLockoutToExpire() {
        let expectation = XCTestExpectation(description: "Lockout expires")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

