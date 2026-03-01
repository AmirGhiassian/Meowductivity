import SwiftUI
import SwiftData

struct TrainingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var gestures: [GestureTask]
    
    @State private var showingRecordSheet = false
    @State private var isTraining = false
    @State private var trainingMessage = ""
    
    @AppStorage("isRecognitionEnabled") private var isRecognitionEnabled = true
    @AppStorage("showFaintDotsOverlay") private var showFaintDotsOverlay = false
    @AppStorage("recognitionSensitivity") private var recognitionSensitivity = 0.8
    @AppStorage("cropSizeRatio") private var cropSizeRatio = 0.85
    @AppStorage("showNotifications") private var showNotifications = true
    
    var body: some View {
        VStack {
            Form {
                Toggle("Enable Gesture Recognition", isOn: $isRecognitionEnabled)
                    .font(.headline)
                    
                Toggle("Show Faint Camera Dots Overlay", isOn: $showFaintDotsOverlay)
                Text("Displays faint green dots tracking your hand on screen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Show Gesture Notifications", isOn: $showNotifications)
                Text("Receive a notification each time a gesture is recognized.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                VStack(alignment: .leading) {
                    Text("Sensitivity: \(Int(recognitionSensitivity * 100))%")
                    Slider(value: $recognitionSensitivity, in: 0.0...1.0, step: 0.05)
                    Text("Higher sensitivity triggers gestures more easily with less exact hand positioning.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("Detection Box Size: \(Int(cropSizeRatio * 100))%")
                    Slider(value: $cropSizeRatio, in: 0.4...1.0, step: 0.05)
                    Text("Adjust the size of the camera area used for gesture detection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Divider()
            
            if gestures.isEmpty {
                Text("No gestures recorded yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(gestures) { gesture in
                        HStack {
                            Text(gesture.gestureName)
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteGestures)
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    
                    if isTraining {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text(trainingMessage)
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    } else {
                        Button(action: {
                            showingRecordSheet = true
                        }) {
                            Label("Add Gesture", systemImage: "plus")
                        }
                        .padding()
                        .disabled(isRecognitionEnabled)
                        .help("Turn off gesture recognition to add a new gesture")
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingRecordSheet) {
            RecordGestureView { gestureName in
                addGesture(gestureName: gestureName)
            }
        }
    }
    
    private func addGesture(gestureName: String) {
        let newGesture = GestureTask(gestureName: gestureName, actionName: "None")
        modelContext.insert(newGesture)
        isRecognitionEnabled = false
        triggerTraining()
    }
    
    private func deleteGestures(offsets: IndexSet) {
        for index in offsets {
            let gesture = gestures[index]
            DatasetManager.shared.deleteGesture(named: gesture.gestureName)
            modelContext.delete(gesture)
        }
        if !offsets.isEmpty {
            isRecognitionEnabled = false
            triggerTraining()
        }
    }
    
    private func triggerTraining() {
        isTraining = true
        trainingMessage = "Training ML model..."
        
        DatasetManager.shared.trainModel { result in
            switch result {
            case .success(_):
                self.trainingMessage = "Model trained!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.isTraining = false
                }
                GestureRecognizer.shared.loadModel()
            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain == "DatasetManager" && (nsError.code == 2 || nsError.code == 4) {
                    self.trainingMessage = "Requires 2+ gestures"
                } else {
                    self.trainingMessage = "Training failed"
                    print("Training failed: \(error)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.isTraining = false
                }
                GestureRecognizer.shared.loadModel()
            }
        }
    }
}
