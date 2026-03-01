import SwiftUI

struct QuickSettingsView: View {
    @AppStorage("isRecognitionEnabled") private var isRecognitionEnabled = true
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pawductivity")
                .font(.headline)
            
            Toggle("Enable Gesture Recognition", isOn: $isRecognitionEnabled)
            
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
