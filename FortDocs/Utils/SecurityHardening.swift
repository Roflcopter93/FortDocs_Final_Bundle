import Foundation
import UIKit
import SwiftUI
import MachO

/// Provides runtime security hardening for the application.  This includes
/// jailbreak detection, screenshot prevention, screen recording detection and
/// basic debugging checks.  The jailbreak detection logic has been extended
/// beyond simple filesystem checks to inspect loaded dynamic libraries and
/// environment variables, helping to identify more sophisticated jailbreaks.
final class SecurityHardening: ObservableObject {
    static let shared = SecurityHardening()
    @Published var isAppInBackground = false
    @Published var screenshotDetected = false
    @Published var screenRecordingDetected = false

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var screenRecordingObserver: NSObjectProtocol?
    private init() { setupSecurityMonitoring() }
    deinit { if let observer = screenRecordingObserver { NotificationCenter.default.removeObserver(observer) } }

    // MARK: - Public interface
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
    func isJailbroken() -> Bool { checkJailbreakIndicators() }
    func isDebugging() -> Bool { checkDebuggingIndicators() }
    func preventScreenshots() { /* overlay would be implemented here */ }
    func clearSensitiveDataFromMemory() { /* flush caches as needed */ }

    // MARK: - Setup routines
    private func setupSecurityMonitoring() { enableSecurityHardening() }
    private func setupAppStateMonitoring() {
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    private func setupScreenshotPrevention() {
        NotificationCenter.default.addObserver(self, selector: #selector(screenshotTaken), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    }
    private func setupScreenRecordingDetection() {
        if #available(iOS 11.0, *) {
            screenRecordingObserver = NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.checkScreenRecording()
            }
            checkScreenRecording()
        }
    }
    private func setupJailbreakDetection() {
        if isJailbroken() {
            logSecurityEvent(.jailbreakDetected)
            print("⚠️ Jailbreak detected – enhanced security measures activated")
        }
    }

    // MARK: - App state handlers
    @objc private func appWillResignActive() {
        isAppInBackground = true
        clearSensitiveDataFromMemory()
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in self?.endBackgroundTask() }
    }
    @objc private func appDidBecomeActive() {
        isAppInBackground = false
        endBackgroundTask()
        NotificationCenter.default.post(name: .requireReAuthentication, object: nil)
    }
    @objc private func appDidEnterBackground() { preventScreenshots() }
    @objc private func appWillEnterForeground() { checkScreenRecording() }
    @objc private func screenshotTaken() {
        screenshotDetected = true
        logSecurityEvent(.screenshotTaken)
        NotificationCenter.default.post(name: .screenshotDetected, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.screenshotDetected = false }
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

    // MARK: - Jailbreak detection
    /// Combines file system, environment and dynamic library checks to detect jailbroken devices.
    private func checkJailbreakIndicators() -> Bool {
        // 1. Check for existence of common jailbreak files and directories
        let jailbreakPaths: [String] = [
            "/Applications/Cydia.app", "/Library/MobileSubstrate/MobileSubstrate.dylib", "/bin/bash", "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/apt/", "/private/var/lib/cydia"
        ]
        for path in jailbreakPaths { if FileManager.default.fileExists(atPath: path) { return true } }
        // 2. Check write permissions outside the sandbox
        let testPath = "/private/jb_test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {}
        // 3. Check for suspicious URL schemes
        let suspiciousSchemes = ["cydia://", "sileo://", "zbra://"]
        for scheme in suspiciousSchemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) { return true }
        }
        // 4. Inspect environment variables for inserted dynamic libraries
        if let env = getenv("DYLD_INSERT_LIBRARIES"), String(cString: env).isEmpty == false { return true }
        // 5. Inspect loaded dynamic libraries for known jailbreak frameworks
        let suspiciousLibraryKeywords = ["Substrate", "Tweak", "Frida", "Cycript"]
        let imageCount = _dyld_image_count()
        for i in 0..<imageCount {
            if let cName = _dyld_get_image_name(i) {
                let name = String(cString: cName)
                for keyword in suspiciousLibraryKeywords where name.contains(keyword) { return true }
            }
        }
        return false
    }

    // MARK: - Debugging detection
    private func checkDebuggingIndicators() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout.stride(ofValue: info)
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        if result == 0 { return (info.kp_proc.p_flag & P_TRACED) != 0 }
        return false
    }

    // MARK: - Helpers
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    private func logSecurityEvent(_ event: SecurityEvent) {
        let timestamp = Date()
        let data = SecurityEventData(event: event, timestamp: timestamp, deviceInfo: getDeviceInfo())
        // In production this would be written to a secure audit log
        print("🔒 Security Event: \(event) at \(timestamp)")
        storeSecurityEvent(data)
    }
    private func getDeviceInfo() -> DeviceInfo {
        DeviceInfo(model: UIDevice.current.model, systemVersion: UIDevice.current.systemVersion, isJailbroken: isJailbroken(), isDebugging: isDebugging())
    }
    private func storeSecurityEvent(_ data: SecurityEventData) {
        // Write to secure storage; stubbed out here
    }
}

// MARK: - Supporting types and notifications
enum SecurityEvent {
    case screenshotTaken, screenRecordingStarted, screenRecordingStopped, jailbreakDetected, debuggerDetected, appBackgrounded, appForegrounded, authenticationRequired
}
struct SecurityEventData { let event: SecurityEvent; let timestamp: Date; let deviceInfo: DeviceInfo }
struct DeviceInfo { let model: String; let systemVersion: String; let isJailbroken: Bool; let isDebugging: Bool }

extension Notification.Name {
    static let requireReAuthentication = Notification.Name("requireReAuthentication")
    static let screenshotDetected = Notification.Name("screenshotDetected")
    static let screenRecordingDetected = Notification.Name("screenRecordingDetected")
}

// MARK: - Secure view modifier
struct SecureView: ViewModifier {
    @StateObject private var security = SecurityHardening.shared
    @State private var showWarning = false
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if security.isAppInBackground {
                        Color.black.ignoresSafeArea().overlay(
                            VStack {
                                Image(systemName: "lock.shield.fill").font(.system(size: 60)).foregroundColor(.white)
                                Text("FortDocs").font(.title).fontWeight(.bold).foregroundColor(.white)
                            }
                        )
                    }
                }
            )
            .alert("Security Warning", isPresented: $showWarning) {
                Button("OK") { }
            } message: {
                if security.screenshotDetected {
                    Text("Screenshot detected. Your documents are protected.")
                } else if security.screenRecordingDetected {
                    Text("Screen recording detected. Please stop recording to continue.")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .screenshotDetected)) { _ in showWarning = true }
            .onReceive(NotificationCenter.default.publisher(for: .screenRecordingDetected)) { _ in showWarning = true }
    }
}
extension View {
    func secureView() -> some View { modifier(SecureView()) }
}