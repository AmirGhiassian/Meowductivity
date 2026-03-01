import Foundation
import AVFoundation
import CoreImage
import AppKit
import Combine
import Vision

struct GestureActionData {
    let actionName: String
    let appURL: String?
    let keyCombo: String?
    let isTwoHand: Bool
}

enum CameraMode {
    case inference
    case recording
}

class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    @Published var permissionGranted = false
    let captureSession = AVCaptureSession()

    @Published var isRecording = false
    @Published var isWaitingToRecord = false  // waiting for hand(s) to enter frame
    @Published var capturedFramesCount = 0
    var maxFrames = 300 // Safety cap (~10 s at 30 fps); recording stops when hand leaves frame

    @Published var isHandInFrame = false
    @Published var currentHandLandmarks: [CGPoint] = []       // first hand raw points (for overlay)
    @Published var currentSecondHandLandmarks: [CGPoint] = [] // second hand raw points (two-hand mode)

    /// When true, waits for both hands before recording and concatenates their landmarks (42 pts).
    @Published var twoHandMode: Bool = false

    // Maintain a dict of gesture names to their action data for inference
    var activeGestures: [String: GestureActionData] = [:]

    private var capturedLandmarks: [[CGPoint]] = []
    private var videoOutput = AVCaptureVideoDataOutput()
    private let context = CIContext()
    private var isSessionSetup = false
    
    @Published var mode: CameraMode = .inference
    
    // Dedicated serial queue for all AVCaptureSession operations to avoid concurrent access/crashes
    private let sessionQueue = DispatchQueue(label: "com.cat-corp.pawductivity.sessionQueue")
    private let videoProcessingQueue = DispatchQueue(label: "com.cat-corp.pawductivity.videoProcessingQueue")
    private let frameProcessingSemaphore = DispatchSemaphore(value: 1)

    var onRecordingFinished: (([[CGPoint]]) -> Void)?


    private override init() {
        super.init()
        checkPermission()
        UserDefaults.standard.addObserver(self, forKeyPath: "isRecognitionEnabled", options: [.new, .initial], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "isRecognitionEnabled" {
            updateSessionState()
        }
    }

    func updateSessionState() {
        // Capture state on main thread to avoid races in the sessionQueue
        let isEnabled = UserDefaults.standard.bool(forKey: "isRecognitionEnabled")
        let currentMode = self.mode
        let isPermissionGranted = self.permissionGranted
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if (isEnabled || currentMode == .recording) && isPermissionGranted {
                if !self.captureSession.isRunning {
                    print("[CameraManager] Starting capture session...")
                    self.captureSession.startRunning()
                }
            } else {
                if self.captureSession.isRunning && !self.isRecording {
                    print("[CameraManager] Stopping capture session...")
                    self.captureSession.stopRunning()
                }
            }
        }
    }

    deinit {
        let session = self.captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
        UserDefaults.standard.removeObserver(self, forKeyPath: "isRecognitionEnabled")
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.permissionGranted = true
                self.setupCaptureSession()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.permissionGranted = granted
                    if granted {
                        self.setupCaptureSession()
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.permissionGranted = false
            }
        }
    }

    func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.isSessionSetup { return }
            
            print("[CameraManager] Setting up capture session...")
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .vga640x480

            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                print("[CameraManager] Error: Could not find video device.")
                self.captureSession.commitConfiguration()
                return
            }
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(videoInput) {
                    self.captureSession.addInput(videoInput)
                }
            } catch {
                print("[CameraManager] Error: Could not create video input: \(error)")
                self.captureSession.commitConfiguration()
                return
            }

            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            // Fix mirroring for natural gesture recording
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }

            self.captureSession.commitConfiguration()
            self.isSessionSetup = true
            print("[CameraManager] Capture session setup complete.")

            // Delay starting the session slightly to avoid races with view initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.updateSessionState()
            }
        }
    }

    func startRecording() {
        DispatchQueue.main.async {
            self.capturedLandmarks.removeAll()
            self.capturedFramesCount = 0
            self.isRecording = false
            self.isWaitingToRecord = true  // will auto-start when hand(s) enter frame
        }
    }

    func cancelRecording() {
        DispatchQueue.main.async {
            self.isRecording = false
            self.isWaitingToRecord = false
            self.capturedLandmarks.removeAll()
            self.capturedFramesCount = 0
        }
    }

    // MARK: – Landmark extraction (single or dual hand)

    /// Extracts normalized+scale-normalized landmarks for up to `maxHands` hands.
    /// Returns (normalizedPoints, rawPoints) arrays, one entry per detected hand.
    private func extractLandmarks(from image: CGImage, maxHands: Int, completion: @escaping ([[CGPoint]], [[CGPoint]]) -> Void) {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        // Minimum confidence per joint — keep this low so partial hand visibility still works
        let jointConfidenceThreshold: Float = 0.2

        let request = VNDetectHumanHandPoseRequest { request, error in
            if let error = error {
                print("[CameraManager] VNDetectHumanHandPoseRequest error: \(error)")
                completion([], [])
                return
            }
            guard let results = request.results as? [VNHumanHandPoseObservation], !results.isEmpty else {
                completion([], [])
                return
            }

            // Sort hands by X-coordinate (e.g. Left-to-Right in the mirrored view)
            // for deterministic vector generation and stable UI overlays.
            let sortedResults = results.sorted { (h1, h2) -> Bool in
                let w1 = (try? h1.recognizedPoint(.wrist))?.location.x ?? 0
                let w2 = (try? h2.recognizedPoint(.wrist))?.location.x ?? 0
                return w1 < w2
            }

            var normalizedAll: [[CGPoint]] = []
            var rawAll: [[CGPoint]] = []
            
            // ... (process sortedResults below)

            let allJoints: [VNHumanHandPoseObservation.JointName] = [
                .wrist,
                .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
                .indexMCP, .indexPIP, .indexDIP, .indexTip,
                .middleMCP, .middlePIP, .middleDIP, .middleTip,
                .ringMCP, .ringPIP, .ringDIP, .ringTip,
                .littleMCP, .littlePIP, .littleDIP, .littleTip
            ]

            for hand in sortedResults.prefix(maxHands) {
                do {
                    var points: [CGPoint] = []
                    for joint in allJoints {
                        let point = try hand.recognizedPoint(joint)
                        points.append(CGPoint(x: point.location.x, y: point.location.y))
                    }
                    rawAll.append(points)
                } catch {
                    print("[CameraManager] Failed to extract joints for a hand: \(error)")
                }
            }

            // Normalize all detected hands relative to the PRIMARY hand's wrist and size.
            // This ensures that for two-handed gestures, the relative distance between 
            // hands and their relative scaling is preserved for the ML model.
            if let firstHandRaw = rawAll.first {
                let wrist = firstHandRaw[0]
                let middleMCP = firstHandRaw[9]
                // Scale normalized by the primary hand's size (wrist to middle knuckle)
                let refDist = max(hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y), 0.01)
                
                for handPoints in rawAll {
                    let normalized = handPoints.map { pt in
                        CGPoint(
                            x: (pt.x - wrist.x) / refDist,
                            y: (pt.y - wrist.y) / refDist
                        )
                    }
                    normalizedAll.append(normalized)
                }
            }

            print("[CameraManager] Returning \(normalizedAll.count) normalized hand(s)")
            completion(normalizedAll, rawAll)
        }
        request.maximumHandCount = maxHands
        do {
            try handler.perform([request])
        } catch {
            print("[CameraManager] Failed to perform hand pose request: \(error)")
            completion([], [])
        }
    }
}

// MARK: – AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        // If we're already processing a frame, drop this one to prevent the queue from filling up
        if frameProcessingSemaphore.wait(timeout: .now()) == .timedOut {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            frameProcessingSemaphore.signal()
            return
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            frameProcessingSemaphore.signal()
            return
        }

        videoProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            var cropRatio = UserDefaults.standard.double(forKey: "cropSizeRatio")
            if cropRatio == 0 { cropRatio = 0.85 }

            // Capture published values to local variables to avoid data races
            var localTwoHandMode = false
            var localMode: CameraMode = .inference
            
            DispatchQueue.main.sync {
                localTwoHandMode = self.twoHandMode
                localMode = self.mode
            }

            let maxHands = (localTwoHandMode || localMode == .inference) ? 2 : 1

        // Always detect on the full frame so live dots follow the hand everywhere.
        // The crop box only controls the start/stop trigger, checked mathematically below.

        // Pre-compute crop box bounds as normalized [0…1] fractions of the full frame.
        // Used to test whether the wrist is "inside the box" without actually cropping.
        let minDim = min(cgImage.width, cgImage.height)
        let cropPx   = Double(minDim) * cropRatio
        let xOffNorm = (Double(cgImage.width)  - cropPx) / 2.0 / Double(cgImage.width)
        let yOffNorm = (Double(cgImage.height) - cropPx) / 2.0 / Double(cgImage.height)
        let cropWNorm = cropPx / Double(cgImage.width)
        let cropHNorm = cropPx / Double(cgImage.height)

        /// Returns true when the wrist of the first detected point set lies inside the crop box.
        func wristInCropBox(_ rawPts: [CGPoint]) -> Bool {
            guard let wrist = rawPts.first else { return false }
            return wrist.x >= xOffNorm && wrist.x <= xOffNorm + cropWNorm
                && wrist.y >= yOffNorm && wrist.y <= yOffNorm + cropHNorm
        }


        self.extractLandmarks(from: cgImage, maxHands: maxHands) { [weak self] normalizedHands, rawHands in
            guard let self = self else { return }
            
            defer {
                self.frameProcessingSemaphore.signal()
            }

            DispatchQueue.main.async {
                // Update live overlay landmarks
                self.currentHandLandmarks = rawHands.first ?? []
                self.currentSecondHandLandmarks = rawHands.count > 1 ? rawHands[1] : []

                // For the start/stop trigger:
                //   • two-hand mode: both hands detected anywhere = trigger
                //   • single-hand mode: wrist must be inside the crop box
                let requiredHandCount = self.twoHandMode ? 2 : 1
                let handsDetected = normalizedHands.count >= requiredHandCount
                let triggerActive: Bool
                if self.twoHandMode {
                    triggerActive = handsDetected
                } else {
                    // Wrist (raw point 0) must lie within the crop box bounds
                    triggerActive = handsDetected && wristInCropBox(rawHands.first ?? [])
                }
                self.isHandInFrame = triggerActive
                
                // Concatenate landmarks for prediction/recording
                let combinedNormalized: [CGPoint]?
                if self.mode == .inference {
                    // During inference, we take what we can get (1 or 2 hands)
                    if normalizedHands.count >= 2 {
                        combinedNormalized = normalizedHands[0] + normalizedHands[1]
                    } else if normalizedHands.count == 1 {
                        combinedNormalized = normalizedHands[0]
                    } else {
                        combinedNormalized = nil
                    }
                } else {
                    // During recording, we strictly follow the required count
                    combinedNormalized = handsDetected
                        ? normalizedHands.prefix(requiredHandCount).flatMap { $0 }
                        : nil
                }

                if self.isWaitingToRecord {
                    if triggerActive {
                        self.isWaitingToRecord = false
                        self.isRecording = true
                    }
                } else if self.isRecording {
                    if handsDetected, let pts = combinedNormalized {
                        self.capturedLandmarks.append(pts)
                        self.capturedFramesCount += 1

                        if self.capturedFramesCount >= self.maxFrames {
                            self.isRecording = false
                            self.onRecordingFinished?(self.capturedLandmarks)
                        }
                    } else if !triggerActive && !handsDetected {
                        // Hand(s) left frame entirely – stop and deliver
                        self.isRecording = false
                        self.onRecordingFinished?(self.capturedLandmarks)
                    }
                } else {
                    // Inference mode
                    if let pts = combinedNormalized {
                        GestureRecognizer.shared.predict(landmarks: pts, activeGestures: self.activeGestures)
                        
                        if !GestureRecognizer.shared.isModelLoaded {
                            print("[CameraManager] Hand detected but model not loaded yet. Retry triggered.")
                        }
                    } else {
                        // No hand in frame during inference — do nothing (expected)
                    }
                }
            }
        }
        }
    }
}
