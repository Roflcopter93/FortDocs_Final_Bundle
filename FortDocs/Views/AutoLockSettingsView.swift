import SwiftUI

/// Presents the auto‑lock timeout options to the user.  A footer at the bottom
/// of the list explains the behaviour of the setting to avoid confusion.
struct AutoLockSettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService

    /// A list of human friendly labels paired with their corresponding time interval.
    private let options: [(label: String, value: TimeInterval)] = [
        ("Immediately", 0),
        ("After 1 Minute", 60),
        ("After 5 Minutes", 300),
        ("After 30 Minutes", 1800),
        ("After 1 Hour", 3600)
    ]

    var body: some View {
        List {
            ForEach(options, id: \.value) { option in
                HStack {
                    Text(option.label)
                    Spacer()
                    if authService.autoLockTimeout == option.value {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    authService.updateAutoLockTimeout(option.value)
                }
            }

            // Add a descriptive footer to clarify the purpose of the auto‑lock setting
            Section {
                EmptyView()
            } footer: {
                Text("FortDocs will automatically lock and require authentication after the selected period of inactivity. Selecting \"Immediately\" means the app locks as soon as it is backgrounded.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .navigationTitle("Auto‑Lock")
    }
}

// MARK: - Preview
struct AutoLockSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AutoLockSettingsView()
            .environmentObject(AuthenticationService())
    }
}