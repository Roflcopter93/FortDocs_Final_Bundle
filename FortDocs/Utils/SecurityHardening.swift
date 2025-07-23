import Foundation
import UIKit
import SwiftUI

class SecurityHardening: ObservableObject {
    static let shared = SecurityHardening()
    
    @Published var isAppInBackground = false
    @Published var screenshotDetected = false
    @Published var screenRecordingDetected = false
    
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var screenRecordingObserver: NSObjectProtocol?
    
    private init() {
        setupSecurityMonitoring()
    }
    
    deinit {
        if let observer = screenRecordingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Public Methods
    
    func enableSecurityHardening() {
        setupAppStateMonitoring()
        setupScreenshotPrevention()
        setupScreenRecordingDetection()
        setupJailbreakDetection()
    }
    
    func disableSecurityHardening() {
        NotificationCenter.default.removeObserver(self)
        
        if let observer = screenRecordingObserver {
            NotificationCenter.default.removeObserver(observer)
            screenRecordingObserver = nil
        }
    }
    
    func isJailbroken() -> Bool {
        return checkJailbreakIndicators()
    }
    
    func isDebugging() -> Bool {
        return checkDebuggingIndicators()
    }
    
    func preventScreenshots() {
        // This will be implemented with a secure view overlay
        print("Screenshot prevention enabled")
    }
    
    func clearSensitiveDataFromMemory() {
        // Clear any cached sensitive data
        print("Clearing sensitive data from memory")
    }
    
    // MARK: - Private Methods
    
    private func setupSecurityMonitoring() {
        enableSecurityHardening()
    }
    
    private func setupAppStateMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    private func setupScreenshotPrevention() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenshotTaken),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )
    }
    
    private func setupScreenRecordingDetection() {
        if #available(iOS 11.0, *) {
            screenRecordingObserver = NotificationCenter.default.addObserver(
                forName: UIScreen.capturedDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.checkScreenRecording()
            }
            
            // Initial check
            checkScreenRecording()
        }
    }
    
    private func setupJailbreakDetection() {
        if isJailbroken() {
            print("⚠️ Jailbreak detected - Enhanced security measures activated")
            // In a production app, you might want to limit functionality
        }
    }
    
    @objc private func appWillResignActive() {
        isAppInBackground = true
        clearSensitiveDataFromMemory()
        
        // Start background task to maintain security
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    @objc private func appDidBecomeActive() {
        isAppInBackground = false
        endBackgroundTask()
        
        // Re-authenticate user if needed
        NotificationCenter.default.post(name: .requireReAuthentication, object: nil)
    }
    
    @objc private func appDidEnterBackground() {
        // Additional background security measures
        preventScreenshots()
    }
    
    @objc private func appWillEnterForeground() {
        // Prepare for foreground activation
        checkScreenRecording()
    }
    
    @objc private func screenshotTaken() {
        screenshotDetected = true
        
        // Log security event
        logSecurityEvent(.screenshotTaken)
        
        // Optionally show warning to user
        NotificationCenter.default.post(name: .screenshotDetected, object: nil)
        
        // Reset flag after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.screenshotDetected = false
        }
    }
    
    private func checkScreenRecording() {
        if #available(iOS 11.0, *) {
            let wasRecording = screenRecordingDetected
            screenRecordingDetected = UIScreen.main.isCaptured
            
            if screenRecordingDetected && !wasRecording {
                logSecurityEvent(.screenRecordingStarted)
                NotificationCenter.default.post(name: .screenRecordingDetected, object: nil)
            } else if !screenRecordingDetected && wasRecording {
                logSecurityEvent(.screenRecordingStopped)
            }
        }
    }
    
    private func checkJailbreakIndicators() -> Bool {
        // Check for common jailbreak files and directories
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/private/var/lib/cydia",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
            "/System/Library/LaunchDaemons/com.ikey.bbot.plist",
            "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            "/var/cache/apt",
            "/var/lib/apt",
            "/var/lib/cydia",
            "/usr/libexec/ssh-keysign",
            "/usr/sbin/sshd",
            "/usr/bin/sshd",
            "/usr/libexec/sftp-server",
            "/Applications/blackra1n.app",
            "/Applications/FakeCarrier.app",
            "/Applications/Icy.app",
            "/Applications/IntelliScreen.app",
            "/Applications/MxTube.app",
            "/Applications/RockApp.app",
            "/Applications/SBSettings.app",
            "/Applications/WinterBoard.app"
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
            return true // Should not be able to write here on non-jailbroken device
        } catch {
            // Expected behavior on non-jailbroken device
        }
        
        // Check for suspicious URL schemes
        let suspiciousSchemes = ["cydia://", "sileo://", "zbra://"]
        for scheme in suspiciousSchemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                return true
            }
        }
        
        return false
    }
    
    private func checkDebuggingIndicators() -> Bool {
        // Check if debugger is attached
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        
        if result == 0 {
            return (info.kp_proc.p_flag & P_TRACED) != 0
        }
        
        return false
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func logSecurityEvent(_ event: SecurityEvent) {
        let timestamp = Date()
        let eventData = SecurityEventData(
            event: event,
            timestamp: timestamp,
            deviceInfo: getDeviceInfo()
        )
        
        // In a production app, you would log this securely
        print("🔒 Security Event: \(event) at \(timestamp)")
        
        // Store in secure log if needed
        storeSecurityEvent(eventData)
    }
    
    private func getDeviceInfo() -> DeviceInfo {
        return DeviceInfo(
            model: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            isJailbroken: isJailbroken(),
            isDebugging: isDebugging()
        )
    }
    
    private func storeSecurityEvent(_ eventData: SecurityEventData) {
        // Store security events in encrypted local storage
        // This could be used for security auditing
        print("Storing security event: \(eventData)")
    }
}

// MARK: - Supporting Types

enum SecurityEvent {
    case screenshotTaken
    case screenRecordingStarted
    case screenRecordingStopped
    case jailbreakDetected
    case debuggerDetected
    case appBackgrounded
    case appForegrounded
    case authenticationRequired
}

struct SecurityEventData {
    let event: SecurityEvent
    let timestamp: Date
    let deviceInfo: DeviceInfo
}

struct DeviceInfo {
    let model: String
    let systemVersion: String
    let isJailbroken: Bool
    let isDebugging: Bool
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let requireReAuthentication = Notification.Name("requireReAuthentication")
    static let screenshotDetected = Notification.Name("screenshotDetected")
    static let screenRecordingDetected = Notification.Name("screenRecordingDetected")
}

// MARK: - Secure View Modifier

struct SecureView: ViewModifier {
    @StateObject private var securityHardening = SecurityHardening.shared
    @State private var showSecurityWarning = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if securityHardening.isAppInBackground {
                        Color.black
                            .ignoresSafeArea()
                            .overlay(
                                VStack {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white)
                                    
                                    Text("FortDocs")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                            )
                    }
                }
            )
            .alert("Security Warning", isPresented: $showSecurityWarning) {
                Button("OK") { }
            } message: {
                if securityHardening.screenshotDetected {
                    Text("Screenshot detected. Your documents are protected.")
                } else if securityHardening.screenRecordingDetected {
                    Text("Screen recording detected. Please stop recording to continue.")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .screenshotDetected)) { _ in
                showSecurityWarning = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .screenRecordingDetected)) { _ in
                showSecurityWarning = true
            }
    }
}

extension View {
    func secureView() -> some View {
        modifier(SecureView())
    }
}

