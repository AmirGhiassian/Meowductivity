import Foundation
import Vision
import Combine
import AppKit
import UserNotifications
import CoreML

class GestureRecognizer: ObservableObject {
    static let shared = GestureRecognizer()

    @Published var currentGesture: String? = nil
    @Published var isModelLoaded = false

    /// Single-hand model (42 features: 21 pts × x+y)
    private var mlModel1H: MLModel?
    /// Two-hand model (84 features: 42 pts × x+y)
    private var mlModel2H: MLModel?

    private var currentConsecutiveMatches = 0
    private var lastMatchedGesture: String? = nil
    private let requiredConsecutiveMatches = 5

    private var recognitionSensitivity: Double {
        let defaultSensitivity = 0.8
        return UserDefaults.standard.object(forKey: "recognitionSensitivity") as? Double ?? defaultSensitivity
    }

    init() {
        loadModel()
    }

    func loadModel() {
        var loaded = false

        // Load 1-hand model
        let url1H = DatasetManager.shared.model1HUrl
        if let model = try? MLModel(contentsOf: url1H) {
            mlModel1H = model
            loaded = true
            print("Loaded 1-hand CoreML model.")
        } else {
            mlModel1H = nil
        }

        // Load 2-hand model
        let url2H = DatasetManager.shared.model2HUrl
        if let model = try? MLModel(contentsOf: url2H) {
            mlModel2H = model
            loaded = true
            print("Loaded 2-hand CoreML model.")
        } else {
            mlModel2H = nil
        }

        // Also try legacy path (GestureClassifier.mlmodelc → treat as 1H)
        if mlModel1H == nil {
            let legacyURL = DatasetManager.shared.datasetDirectory.appendingPathComponent("GestureClassifier.mlmodelc")
            if let model = try? MLModel(contentsOf: legacyURL) {
                mlModel1H = model
                loaded = true
                print("Loaded legacy CoreML model as 1-hand model.")
            }
        }

        DispatchQueue.main.async {
            self.isModelLoaded = loaded
        }
    }

    // MARK: – Prediction

    /// Routes prediction to the appropriate model based on landmark count.
    /// - 21 pts → 1-hand model
    /// - 42 pts → 2-hand model
    func predict(landmarks: [CGPoint], activeGestures: [String: GestureActionData]) {
        let isEnabled = UserDefaults.standard.object(forKey: "isRecognitionEnabled") as? Bool ?? true
        guard isEnabled else { return }

        let model: MLModel?
        switch landmarks.count {
        case 21: model = mlModel1H
        case 42: model = mlModel2H
        default:  return  // unsupported landmark count
        }
        guard let model else { return }

        var dict: [String: Double] = [:]
        for (index, point) in landmarks.enumerated() {
            dict["p\(index)_x"] = Double(point.x)
            dict["p\(index)_y"] = Double(point.y)
        }

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: dict)
            let prediction = try model.prediction(from: provider)

            guard let label = prediction.featureValue(for: "label")?.stringValue else { return }

            let probabilityDict = prediction.featureValue(for: "labelProbability")?.dictionaryValue
            let prob = (probabilityDict?[label] as? Double) ?? 1.0

            // Map sensitivity (0…1) → min probability (0.9…0.4)
            let minProbability = 0.9 - (recognitionSensitivity * 0.5)

            if prob >= minProbability, activeGestures.keys.contains(label) {
                if label == lastMatchedGesture {
                    currentConsecutiveMatches += 1
                } else {
                    lastMatchedGesture = label
                    currentConsecutiveMatches = 1
                }

                if currentConsecutiveMatches >= requiredConsecutiveMatches {
                    DispatchQueue.main.async {
                        self.currentGesture = label

                        if let actionData = activeGestures[label] {
                            ActionExecutor.shared.executeAction(named: actionData.actionName, appURL: actionData.appURL, keyCombo: actionData.keyCombo)

                            if let sound = NSSound(named: "Glass") ?? NSSound(named: "Tink") {
                                sound.play()
                            }

                            let showNotifications = UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true
                            if showNotifications {
                                self.sendNotification(title: "Gesture Recognized", body: "Executed action: \(actionData.actionName)")
                            }
                        }
                    }
                    currentConsecutiveMatches = 0
                }
            } else {
                currentConsecutiveMatches = 0
                lastMatchedGesture = nil
            }
        } catch {
            print("Prediction error: \(error)")
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }
}
