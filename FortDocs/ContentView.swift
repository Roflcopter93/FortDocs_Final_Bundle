import SwiftUI
import LocalAuthentication

struct ContentView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showingOnboarding = false
    
    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView()
                    .transition(.opacity)
            } else {
                AuthenticationView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
        .onAppear {
            checkFirstLaunch()
        }
    }
    
    private func checkFirstLaunch() {
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            showingOnboarding = true
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }
}

// MARK: - Authentication View
struct AuthenticationView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showingPINEntry = false
    @State private var authError: String?
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // App logo and title
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                    
                    Text("FortDocs")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Your secure document vault")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // Authentication buttons
                VStack(spacing: 20) {
                    if authService.biometricType != .none {
                        Button(action: authenticateWithBiometrics) {
                            HStack {
                                Image(systemName: authService.biometricType == .faceID ? "faceid" : "touchid")
                                    .font(.title2)
                                Text(authService.biometricType == .faceID ? "Unlock with Face ID" : "Unlock with Touch ID")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                        }
                    }
                    
                    Button(action: { showingPINEntry = true }) {
                        HStack {
                            Image(systemName: "number.circle.fill")
                                .font(.title2)
                            Text("Enter PIN")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 40)
                
                if let error = authError {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(8)
                        .padding(.horizontal, 40)
                }
            }
        }
        .sheet(isPresented: $showingPINEntry) {
            PINEntryView()
                .environmentObject(authService)
        }
    }
    
    private func authenticateWithBiometrics() {
        Task {
            do {
                try await authService.authenticateWithBiometrics()
                authError = nil
            } catch {
                authError = error.localizedDescription
            }
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FolderView()
                .tabItem {
                    Image(systemName: "folder.fill")
                    Text("Documents")
                }
                .tag(0)
            
            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .tag(1)
            
            ScannerView()
                .tabItem {
                    Image(systemName: "camera.fill")
                    Text("Scan")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
        }
        .accentColor(.blue)
    }
}

// MARK: - PIN Entry View
struct PINEntryView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @State private var enteredPIN = ""
    @State private var isSettingUpPIN = false
    @State private var confirmPIN = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text(isSettingUpPIN ? "Set up your PIN" : "Enter your PIN")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // PIN dots display
                HStack(spacing: 20) {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill(index < enteredPIN.count ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 20, height: 20)
                    }
                }
                
                // Number pad
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
                    ForEach(1...9, id: \.self) { number in
                        Button(action: { addDigit(String(number)) }) {
                            Text(String(number))
                                .font(.title)
                                .fontWeight(.medium)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(30)
                        }
                    }
                    
                    // Empty space
                    Color.clear
                        .frame(width: 60, height: 60)
                    
                    // Zero button
                    Button(action: { addDigit("0") }) {
                        Text("0")
                            .font(.title)
                            .fontWeight(.medium)
                            .frame(width: 60, height: 60)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(30)
                    }
                    
                    // Delete button
                    Button(action: deleteDigit) {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .frame(width: 60, height: 60)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(30)
                    }
                }
                .padding(.horizontal, 40)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            checkPINSetup()
        }
    }
    
    private func checkPINSetup() {
        isSettingUpPIN = !authService.hasPINSet
    }
    
    private func addDigit(_ digit: String) {
        if enteredPIN.count < 5 {
            enteredPIN += digit
            
            if enteredPIN.count == 5 {
                if isSettingUpPIN {
                    if confirmPIN.isEmpty {
                        confirmPIN = enteredPIN
                        enteredPIN = ""
                        // Show confirmation message
                    } else {
                        // Verify PINs match
                        if enteredPIN == confirmPIN {
                            Task {
                                do {
                                    try await authService.setPIN(enteredPIN)
                                    dismiss()
                                } catch {
                                    errorMessage = error.localizedDescription
                                    enteredPIN = ""
                                    confirmPIN = ""
                                }
                            }
                        } else {
                            errorMessage = "PINs don't match. Please try again."
                            enteredPIN = ""
                            confirmPIN = ""
                        }
                    }
                } else {
                    // Verify PIN
                    Task {
                        do {
                            try await authService.authenticateWithPIN(enteredPIN)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            enteredPIN = ""
                        }
                    }
                }
            }
        }
    }
    
    private func deleteDigit() {
        if !enteredPIN.isEmpty {
            enteredPIN.removeLast()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService())
        .environmentObject(FolderStore())
        .environmentObject(SearchIndex())
}

