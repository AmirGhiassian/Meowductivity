import SwiftUI
import SwiftData

struct TrainingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var gestures: [GestureTask]
    
    @State private var showingRecordSheet = false
    @StateObject private var trainer = GestureTrainer()
    
    @AppStorage("isRecognitionEnabled") private var isRecognitionEnabled = true
    @AppStorage("recognitionSensitivity") private var recognitionSensitivity = 0.8
    @AppStorage("needsTraining") private var needsTraining = false
    
    var body: some View {
        VStack {
            Form {
                Toggle("Enable Gesture Recognition", isOn: $isRecognitionEnabled)
                    .font(.headline)
                    .disabled(needsTraining || trainer.isTraining)
                    
                if needsTraining {
                    Text("Model requires training before recognition can be enabled.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                VStack(alignment: .leading) {
                    Text("Confidence Threshold: \(Int(recognitionSensitivity * 100))%")
                    Slider(value: $recognitionSensitivity, in: 0.70...0.99, step: 0.01)
                    Text("A higher threshold reduces sensitivity (requires more confidence to trigger).")
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
                if trainer.isTraining {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text(trainer.trainingStatus)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                } else if let error = trainer.lastError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.top, 8)
                } else if trainer.trainingStatus == "Model Trained Successfully!" {
                    Text(trainer.trainingStatus)
                        .foregroundColor(.green)
                        .font(.caption)
                        .padding(.top, 8)
                }
                
                HStack {
                    Button(action: {
                        trainer.trainModel { _ in }
                    }) {
                        Label("Train Model", systemImage: "brain.head.profile")
                    }
                    .disabled(trainer.isTraining || gestures.isEmpty)
                    .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        showingRecordSheet = true
                    }) {
                        Label("Add Gesture", systemImage: "plus")
                    }
                    .padding()
                    .disabled(isRecognitionEnabled || trainer.isTraining)
                    .help("Turn off gesture recognition to add a new gesture")
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
        needsTraining = true
        isRecognitionEnabled = false
    }
    
    private func deleteGestures(offsets: IndexSet) {
        for index in offsets {
            let gesture = gestures[index]
            DatasetManager.shared.deleteGesture(named: gesture.gestureName)
            modelContext.delete(gesture)
        }
        if !offsets.isEmpty {
            needsTraining = true
            isRecognitionEnabled = false
        }
    }
}
