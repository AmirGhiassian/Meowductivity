import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("showNotifications") private var showNotifications = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch on Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    if SMAppService.mainApp.status == .enabled { return }
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("Failed to update SMAppService: \(error)")
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                    Text("Automatically start Pawductivity in the background when you log in.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Startup")
                    .font(.headline)
            }
            .padding(.bottom)
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Show Notifications", isOn: $showNotifications)
                    Text("Display a macOS notification when a gesture is recognized and an action is triggered.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Notifications")
                    .font(.headline)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    GeneralSettingsView()
}
