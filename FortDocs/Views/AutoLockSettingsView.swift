import SwiftUI

struct AutoLockSettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
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
        }
        .navigationTitle("Auto-Lock")
    }
}

struct AutoLockSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AutoLockSettingsView()
            .environmentObject(AuthenticationService())
    }
}
