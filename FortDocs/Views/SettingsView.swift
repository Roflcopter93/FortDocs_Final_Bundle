import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var folderStore: FolderStore
    @ObservedObject private var syncManager = SyncManager.shared
    @State private var showingChangePIN = false
    @State private var showingAbout = false
    @State private var showingExportData = false
    @State private var showingDeleteAllData = false
    @State private var showingSyncComplete = false
    @State private var biometricsEnabled = false

    private var autoLockDescription: String {
        switch authService.autoLockTimeout {
        case 0: return "Immediately"
        case 60: return "After 1 Minute"
        case 300: return "After 5 Minutes"
        case 1800: return "After 30 Minutes"
        case 3600: return "After 1 Hour"
        default: return "Custom"
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Security Section
                Section("Security") {
                    HStack {
                        Image(systemName: "faceid")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading) {
                            Text("Biometric Authentication")
                                .font(.body)
                            
                            Text(authService.biometricType == .faceID ? "Face ID" : "Touch ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $biometricsEnabled)
                            .disabled(authService.biometricType == .none)
                    }
                    
                    Button(action: { showingChangePIN = true }) {
                        HStack {
                            Image(systemName: "number.circle")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("Change PIN")
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                    
                    NavigationLink(destination: AutoLockSettingsView()) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.green)
                                .frame(width: 24)

                            VStack(alignment: .leading) {
                                Text("Auto-Lock")
                                    .font(.body)

                                Text(autoLockDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Storage Section
                Section("Storage") {
                    StorageInfoRow()
                    
                    Button(action: { showingExportData = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("Export Data")
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                    
                    Button(action: cleanupStorage) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            
                            Text("Clean Up Storage")
                            
                            Spacer()
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                // Sync Section
                Section("Sync") {
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading) {
                            Text("iCloud Sync")
                                .font(.body)
                            
                            Text("Enabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    Button("Sync Now") {
                        syncNow()
                    }
                    if syncManager.syncState == .syncing {
                        ProgressView(value: syncManager.syncProgress)
                    }
                }
                
                // App Section
                Section("App") {
                    Button(action: { showingAbout = true }) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("About FortDocs")
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                    
                    Link(destination: URL(string: "https://fortdocs.app/privacy")!) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("Privacy Policy")
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://fortdocs.app/support")!) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("Support")
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Danger Zone
                Section("Danger Zone") {
                    Button(action: { showingDeleteAllData = true }) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .frame(width: 24)
                            
                            Text("Delete All Data")
                            
                            Spacer()
                        }
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            biometricsEnabled = authService.canUseBiometrics
        }
        .onChange(of: biometricsEnabled) { enabled in
            toggleBiometrics(enabled)
        }
        .sheet(isPresented: $showingChangePIN) {
            ChangePINView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingExportData) {
            ExportDataView()
        }
        .alert("Delete All Data", isPresented: $showingDeleteAllData) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete all your documents and folders. This action cannot be undone.")
        }
        .alert("Sync Completed", isPresented: $showingSyncComplete) {
            Button("OK", role: .cancel) { }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncCompleted)) { _ in
            showingSyncComplete = true
        }
    }
    
    private func toggleBiometrics(_ enabled: Bool) {
        if enabled {
            Task {
                do {
                    try await authService.enableBiometrics()
                } catch {
                    biometricsEnabled = false
                }
            }
        } else {
            authService.disableBiometrics()
        }
    }
    
    private func cleanupStorage() {
        folderStore.cleanupEmptyFolders()
        // Additional cleanup logic would go here
    }
    
    private func syncNow() {
        Task {
            await SyncManager.shared.performManualSync()
            showingSyncComplete = true
        }
    }
    
    private func deleteAllData() {
        // This would delete all user data
        print("Delete all data triggered")
    }
}

// MARK: - Storage Info Row

struct StorageInfoRow: View {
    @EnvironmentObject private var folderStore: FolderStore
    @State private var storageInfo: StorageInfo?
    
    var body: some View {
        HStack {
            Image(systemName: "internaldrive")
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text("Storage Used")
                    .font(.body)
                
                if let info = storageInfo {
                    Text("\(info.usedSpace) of \(info.totalSpace)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Calculating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let info = storageInfo {
                CircularProgressView(progress: info.usagePercentage)
                    .frame(width: 30, height: 30)
            }
        }
        .onAppear {
            calculateStorageInfo()
        }
    }
    
    private func calculateStorageInfo() {
        Task {
            let stats = folderStore.getFolderStatistics()
            let totalSpace = "Available" // Would calculate actual device storage
            let usedSpace = stats.formattedSize
            let percentage = 0.25 // Would calculate actual percentage
            
            await MainActor.run {
                self.storageInfo = StorageInfo(
                    usedSpace: usedSpace,
                    totalSpace: totalSpace,
                    usagePercentage: percentage
                )
            }
        }
    }
}

struct StorageInfo {
    let usedSpace: String
    let totalSpace: String
    let usagePercentage: Double
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}

// MARK: - Change PIN View

struct ChangePINView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var step = 1
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text(stepTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // PIN dots display
                HStack(spacing: 20) {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill(index < currentPINEntry.count ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 20, height: 20)
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var stepTitle: String {
        switch step {
        case 1:
            return "Enter current PIN"
        case 2:
            return "Enter new PIN"
        case 3:
            return "Confirm new PIN"
        default:
            return ""
        }
    }
    
    private var currentPINEntry: String {
        switch step {
        case 1:
            return currentPIN
        case 2:
            return newPIN
        case 3:
            return confirmPIN
        default:
            return ""
        }
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // App icon and info
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        Text("FortDocs")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Version 1.0.0")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text("Privacy-first document vault")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Features")
                            .font(.headline)
                        
                        FeatureRow(icon: "lock.shield", title: "Military-grade encryption", description: "AES-256 encryption with Secure Enclave")
                        FeatureRow(icon: "faceid", title: "Biometric security", description: "Face ID and Touch ID support")
                        FeatureRow(icon: "icloud", title: "Seamless sync", description: "Secure synchronization across devices")
                        FeatureRow(icon: "magnifyingglass", title: "Smart search", description: "Full-text search with OCR")
                        FeatureRow(icon: "camera.viewfinder", title: "Document scanning", description: "Advanced document capture")
                    }
                    
                    // Credits
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Credits")
                            .font(.headline)
                        
                        Text("Developed by Manus AI")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text("Built with SwiftUI and modern iOS frameworks")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Export Data View

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exportFormat: ExportFormat = .pdf
    @State private var includeMetadata = true
    @State private var isExporting = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Export Format") {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Options") {
                    Toggle("Include metadata", isOn: $includeMetadata)
                }
                
                Section {
                    Button(action: startExport) {
                        if isExporting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Exporting...")
                            }
                        } else {
                            Text("Export Data")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func startExport() {
        isExporting = true
        
        Task {
            // Simulate export process
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
            await MainActor.run {
                isExporting = false
                dismiss()
            }
        }
    }
}

enum ExportFormat: String, CaseIterable {
    case pdf = "PDF"
    case zip = "ZIP"
    case json = "JSON"
    
    var displayName: String {
        return rawValue
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationService())
        .environmentObject(FolderStore())
}

