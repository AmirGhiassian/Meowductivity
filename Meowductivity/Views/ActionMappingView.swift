import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ActionMappingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var gestures: [GestureTask]
    let allActions = ActionExecutor.shared.allActions
    
    var body: some View {
        VStack {
            if gestures.isEmpty {
                Text("No gestures trained. Go to the Training tab to add a gesture.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(gestures) { gesture in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(gesture.gestureName)
                                .font(.headline)
                            
                            Spacer()
                            
                            Picker("Action", selection: Binding(
                                get: { gesture.actionName },
                                set: { newValue in
                                    gesture.actionName = newValue
                                }
                            )) {
                                ForEach(allActions, id: \.self) { action in
                                    Text(action).tag(action)
                                }
                            }
                            .frame(width: 250)
                            
                            Toggle("", isOn: Binding(
                                get: { gesture.isActive },
                                set: { gesture.isActive = $0 }
                            ))
                            .labelsHidden()
                            .help("Enable or Disable this rule")
                        }
                        
                        if gesture.actionName == "Open Application..." {
                            HStack {
                                Text("App URL: ").font(.caption)
                                TextField("file:///Applications/Safari.app", text: Binding(
                                    get: { gesture.appURL ?? "" },
                                    set: { gesture.appURL = $0 }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 300)
                                
                                Button("Select...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowedContentTypes = [UTType.application]
                                    if panel.runModal() == .OK {
                                        gesture.appURL = panel.url?.absoluteString
                                    }
                                }
                            }
                            .padding(.leading, 20)
                        } else if gesture.actionName == "Custom Key Combo..." {
                            HStack {
                                Text("Keys: ").font(.caption)
                                TextField("e.g. cmd,shift,c", text: Binding(
                                    get: { gesture.keyCombo ?? "" },
                                    set: { gesture.keyCombo = $0 }
                                ))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 200)
                            }
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: gestures) { _ in
                    if let delegate = NSApp.delegate as? AppDelegate {
                        // Debounce might be needed in a real app, but SwiftData onChange works for now
                        delegate.refreshActiveGestures(modelContext: modelContext)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }
}
