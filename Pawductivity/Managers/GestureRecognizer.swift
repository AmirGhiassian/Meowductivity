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
    
    private var lastModelLoadAttempt: Date = .distantPast
    private let modelLoadRetryInterval: TimeInterval = 5.0

    // MARK: – Recognition state

    /// Rolling window of recent predictions used to decide when to fire.
    /// Each entry is (timestamp, label, probability).
    private var predictionWindow: [(timestamp: Date, label: String, prob: Double)] = []

    /// How long the window spans. We fire when ≥ windowFillRatio of this window
    /// is dominated by one label at high confidence.
    private let windowDuration: TimeInterval = 0.8

    /// Fraction of the window that must be filled before we even consider firing (≈ 75 %).
    private let windowFillRatio: Double = 0.75

    /// Fraction of frames *within* the window that must match the winner label.
    private let dominanceThreshold: Double = 0.75

    /// Minimum average probability of the winner label across its frames.
    private let highConfidenceThreshold: Double = 0.82

    /// After a gesture fires, it is added here.
    /// It stays blocked until the model stops predicting it (hand released / moved away).
    private var awaitingRelease: String? = nil

    /// Hard minimum between ANY two firings (safety net for rapid camera frames)
    private let minimumCooldown: TimeInterval = 1.0
    private var lastFiredTime: Date = .distantPast

    private var recognitionSensitivity: Double {
        let defaultSensitivity = 0.5
        return UserDefaults.standard.object(forKey: "recognitionSensitivity") as? Double ?? defaultSensitivity
    }

    init() {
        loadModel()
    }

    func loadModel() {
        // Throttle loading to avoid excessive disk hits if called rapidly
        let now = Date()
        guard now.timeIntervalSince(lastModelLoadAttempt) > modelLoadRetryInterval else { return }
        lastModelLoadAttempt = now
        
        print("[GestureRecognizer] Attempting to load models...")
        var loaded = false

        let url1H = DatasetManager.shared.model1HUrl
        if let model = try? MLModel(contentsOf: url1H) {
            mlModel1H = model
            loaded = true
            print("[GestureRecognizer] 1-hand model loaded.")
        } else {
            mlModel1H = nil
        }

        let url2H = DatasetManager.shared.model2HUrl
        if let model = try? MLModel(contentsOf: url2H) {
            mlModel2H = model
            loaded = true
            print("[GestureRecognizer] 2-hand model loaded.")
        } else {
            mlModel2H = nil
        }

        // Legacy model fallback → treat as 1-hand
        if mlModel1H == nil {
            let legacyURL = DatasetManager.shared.datasetDirectory
                .appendingPathComponent("GestureClassifier.mlmodelc")
            if let model = try? MLModel(contentsOf: legacyURL) {
                mlModel1H = model
                loaded = true
                print("[GestureRecognizer] Legacy 1-hand model loaded.")
            }
        }

        DispatchQueue.main.async { 
            self.isModelLoaded = loaded 
            if !loaded {
                print("[GestureRecognizer] Failed to load any models.")
            }
        }
    }
    
    func retryLoadModelIfNeeded() {
        if !isModelLoaded {
            loadModel()
        }
    }

    // MARK: – Prediction

    func predict(landmarks: [CGPoint], activeGestures: [String: GestureActionData]) {
        let isEnabled = UserDefaults.standard.object(forKey: "isRecognitionEnabled") as? Bool ?? true
        guard isEnabled, !activeGestures.isEmpty else { return }

        let model: MLModel
        switch landmarks.count {
        case 21:
            guard let m = mlModel1H else {
                retryLoadModelIfNeeded()
                return
            }
            model = m
        case 42:
            guard let m = mlModel2H else {
                retryLoadModelIfNeeded()
                return
            }
            model = m
        default:
            return
        }

        var dict: [String: Double] = [:]
        for (i, pt) in landmarks.enumerated() {
            dict["p\(i)_x"] = Double(pt.x)
            dict["p\(i)_y"] = Double(pt.y)
        }

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: dict)
            let prediction = try model.prediction(from: provider)

            guard let label = prediction.featureValue(for: "label")?.stringValue else { return }
            let prob = (prediction.featureValue(for: "labelProbability")?.dictionaryValue[label] as? Double) ?? 1.0

            // sensitivity 0…1 → minProb 0.7…0.2
            let minProbability = 0.7 - (recognitionSensitivity * 0.5)

            let isAboveThreshold = prob >= minProbability && activeGestures.keys.contains(label)

            let now = Date()

            // ── RELEASE DETECTION ──────────────────────────────────────────
            // If the current high-conf prediction is still the gesture we just fired,
            // keep it blocked (user is still holding the pose). Otherwise clear the lock.
            if let blocked = awaitingRelease {
                if isAboveThreshold && label == blocked {
                    // still holding the fired gesture — do nothing, but allow window to decay
                } else {
                    awaitingRelease = nil   // hand moved away / different gesture
                    predictionWindow.removeAll()
                }
            }

            // Hard minimum cooldown between any two separate firings
            guard now.timeIntervalSince(lastFiredTime) > minimumCooldown else {
                // Still allow window to decay even if cooldown is active
                let cutoff = now.addingTimeInterval(-windowDuration)
                predictionWindow.removeAll { $0.timestamp < cutoff }
                return
            }

            // ── ROLLING WINDOW BOOKKEEPING ─────────────────────────────────
            // Only add frames where the model predicts a known gesture above threshold.
            if isAboveThreshold {
                predictionWindow.append((timestamp: now, label: label, prob: prob))
            } else {
                // If the frame is low confidence or the wrong gesture, we simply skip adding it.
                // The window will naturally decay over 'windowDuration' (0.8s).
                // This allows for significant hand-detection flicker (common in 2-hand mode)
                // without resetting a gesture progress that is 90% complete.
                return
            }

            // Drop frames that have aged out of the window.
            let cutoff = now.addingTimeInterval(-windowDuration)
            predictionWindow.removeAll { $0.timestamp < cutoff }

            // ── WINDOW ANALYSIS ────────────────────────────────────────────
            // Wait until the window has been filling for at least windowFillRatio
            // of windowDuration before even attempting to fire.
            let oldestAllowed = now.addingTimeInterval(-windowDuration * (1.0 - windowFillRatio))
            guard let firstEntry = predictionWindow.first,
                  firstEntry.timestamp <= oldestAllowed else {
                return  // window not filled enough yet (< 75 % elapsed)
            }

            // Find which label dominates the window.
            var labelCounts: [String: (count: Int, totalProb: Double)] = [:]
            for entry in predictionWindow {
                let existing = labelCounts[entry.label] ?? (count: 0, totalProb: 0)
                labelCounts[entry.label] = (count: existing.count + 1,
                                            totalProb: existing.totalProb + entry.prob)
            }

            guard let (winnerLabel, winnerStats) = labelCounts.max(by: { $0.value.count < $1.value.count }) else { return }

            let totalFrames  = predictionWindow.count
            let winnerFrac   = Double(winnerStats.count) / Double(totalFrames)
            let winnerAvgProb = winnerStats.totalProb / Double(winnerStats.count)

            // Require the winner to dominate ≥ 75 % of frames AND be highly confident.
            // Two-hand models are naturally noisier, so we use a slightly lower threshold.
            let requiredConfidence = landmarks.count == 42 ? (highConfidenceThreshold - 0.12) : highConfidenceThreshold
            
            guard winnerFrac >= dominanceThreshold,
                  winnerAvgProb >= requiredConfidence else { return }

            // ── FIRE ───────────────────────────────────────────────────────
            lastFiredTime = now
            awaitingRelease = winnerLabel   // block re-fire until hand releases
            predictionWindow.removeAll()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentGesture = winnerLabel
                if let actionData = activeGestures[winnerLabel] {
                    ActionExecutor.shared.executeAction(
                        named: actionData.actionName,
                        appURL: actionData.appURL,
                        keyCombo: actionData.keyCombo
                    )
                    NSSound(named: "Glass")?.play()
                }
            }

        } catch {
            print("[GestureRecognizer] Prediction error: \(error)")
        }
    }
}
