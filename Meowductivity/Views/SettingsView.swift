import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            TrainingSettingsView()
                .tabItem {
                    Label("Training", systemImage: "brain.head.profile")
                }
                
            ActionMappingView()
                .tabItem {
                    Label("Actions", systemImage: "switch.2")
                }
        }
        .frame(width: 550, height: 450)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: GestureTask.self, inMemory: true)
}
