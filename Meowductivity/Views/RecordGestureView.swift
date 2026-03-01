import SwiftUI

struct RecordGestureView: View {
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var cameraManager = CameraManager()
    
    @State private var gestureName: String = ""
    @State private var recordingDuration: Int = 4 // Default to 4 seconds
    @State private var isSaving: Bool = false
    @State private var recordedFramesCount: Int = 0
    @State private var hasRecorded: Bool = false
    
    var onSave: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Record a Gesture")
                .font(.headline)
            
            Form {
                TextField("Gesture Name:", text: $gestureName)
                LabeledContent("Recording Duration:") {
                    HStack(spacing: 4) {
                        TextField("", value: $recordingDuration, format: .number)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                        Stepper("", value: $recordingDuration, in: 1...300)
                            .labelsHidden()
                        Text("seconds")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }
                .disabled(cameraManager.isRecording || hasRecorded)
            }
            .padding(.horizontal)
            
            ZStack {
                if cameraManager.permissionGranted {
                    CameraPreview(session: cameraManager.captureSession)
                        .frame(height: 250)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                        )
                        .overlay(
                            Rectangle()
                                .stroke(Color.blue.opacity(0.8), lineWidth: 3)
                                .frame(width: 150, height: 150)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 250)
                        .overlay(Text("Camera Access Required").foregroundColor(.secondary))
                }
                
                if cameraManager.isRecording {
                    VStack {
                        Spacer()
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text("Recording... \(cameraManager.capturedFramesCount)/\(cameraManager.maxFrames)")
                                .foregroundColor(.white)
                                .font(.caption).bold()
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.bottom, 8)
                    }
                } else if isSaving {
                    VStack {
                        Spacer()
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text("Saving...")
                                .foregroundColor(.white)
                                .font(.caption).bold()
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.bottom, 8)
                    }
                } else if hasRecorded {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Captured \(recordedFramesCount) frames")
                                .foregroundColor(.white)
                                .font(.caption).bold()
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.horizontal)
            
            HStack {
                Button(cameraManager.isRecording ? "Recording..." : (hasRecorded ? "Re-Record" : "Start Recording")) {
                    hasRecorded = false
                    cameraManager.maxFrames = recordingDuration * 30
                    cameraManager.startRecording()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!cameraManager.permissionGranted || cameraManager.isRecording || gestureName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    onSave(gestureName)
                    dismiss()
                }
                .disabled(!hasRecorded || isSaving)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 450, height: 500)
        .onAppear {
            cameraManager.onRecordingFinished = { frames in
                self.isSaving = true
                DatasetManager.shared.saveFrames(frames, forGesture: self.gestureName) { result in
                    switch result {
                    case .success:
                        self.recordedFramesCount = frames.count
                        self.hasRecorded = true
                    case .failure(let error):
                        print("Failed to save frames: \(error)")
                    }
                    self.isSaving = false
                }
            }
        }
    }
}

#Preview {
    RecordGestureView { gesture in
        print("Saved \(gesture)")
    }
}
