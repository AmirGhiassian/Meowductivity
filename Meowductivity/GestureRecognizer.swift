import Foundation
import CoreML
import Vision
import CoreImage
import Combine

class GestureRecognizer: ObservableObject {
    static let shared = GestureRecognizer()
    
    @Published var currentGesture: String? = nil
    @Published var isModelLoaded = false
    
    private var visionModel: VNCoreMLModel?
    
    private var currentConsecutiveMatches = 0
    private var lastMatchedGesture: String? = nil
    private let requiredConsecutiveMatches = 20 // requires ~0.6s to trigger
    
    private var confidenceThreshold: Float {
        if let val = UserDefaults.standard.object(forKey: "recognitionSensitivity") as? Double {
            return Float(val)
        }
        return 0.8
    }
    
    init() {
        loadModel()
    }
    
    func loadModel() {
        let datasetDir = DatasetManager.shared.datasetDirectory
        let modelURL = datasetDir.appendingPathComponent("GestureClassifier.mlmodel")
        
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            print("No compiled model found yet.")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Compile the model first
                let compiledURL = try MLModel.compileModel(at: modelURL)
                let mlModel = try MLModel(contentsOf: compiledURL)
                
                let vnModel = try VNCoreMLModel(for: mlModel)
                
                DispatchQueue.main.async {
                    self.visionModel = vnModel
                    self.isModelLoaded = true
                    print("Model compiled and loaded successfully!")
                }
            } catch {
                print("Failed to load model: \(error)")
            }
        }
    }
    
    func predict(image: CGImage, activeGestures: [String: String]) {
        guard let visionModel = visionModel else { return }
        
        // Ensure recognition is globally enabled
        let isEnabled = UserDefaults.standard.object(forKey: "isRecognitionEnabled") as? Bool ?? true
        guard isEnabled else { return }
        
        let request = VNCoreMLRequest(model: visionModel) { request, error in
            if let results = request.results as? [VNClassificationObservation],
               let topResult = results.first {
                
                // Only act if confidence is high and it's not a generic "Background" class
                if topResult.confidence >= self.confidenceThreshold {
                    let gestureName = topResult.identifier
                    
                    if gestureName == self.lastMatchedGesture {
                        self.currentConsecutiveMatches += 1
                    } else {
                        self.lastMatchedGesture = gestureName
                        self.currentConsecutiveMatches = 1
                    }
                    
                    if self.currentConsecutiveMatches >= self.requiredConsecutiveMatches {
                        DispatchQueue.main.async {
                            self.currentGesture = gestureName
                            
                            // Pass execution to ActionExecutor if we have a match
                            if let actionStr = activeGestures[gestureName] {
                                ActionExecutor.shared.executeAction(named: actionStr)
                            }
                        }
                        self.currentConsecutiveMatches = 0 // reset after firing
                    }
                } else {
                    self.currentConsecutiveMatches = 0
                    self.lastMatchedGesture = nil
                }
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform prediction: \(error)")
        }
    }
}
