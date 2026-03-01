import SwiftUI

struct QuickSettingsView: View {
    @AppStorage("isCameraManagerEnabled") private var isCameraManagerEnabled = true
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meowductivity")
                .font(.headline)
            
            Toggle("Enable Camera Manager", isOn: $isCameraManagerEnabled)
            
            Divider()
            
            Button("Preferences...") {
                openSettings()
                // Ensure application comes to front when settings open
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 250)
    }
}

#Preview {
    QuickSettingsView()
}
