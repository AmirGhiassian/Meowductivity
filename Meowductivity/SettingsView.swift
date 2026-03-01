import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        TabView {
            // General Settings stub
            Form {
                Text("General settings description...")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            GesturesSettingsView()
                .tabItem {
                    Label("Gestures", systemImage: "hand.point.up.left")
                }
        }
        .frame(width: 500, height: 400)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: GestureTask.self, inMemory: true)
}
