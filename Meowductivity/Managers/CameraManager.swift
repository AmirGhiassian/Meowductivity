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

    var onRecordingFinished: (([[CGPoint]]) -> Void)?

    let isBackground: Bool

    init(isBackground: Bool = true) {
        self.isBackground = isBackground
        super.init()
        checkPermission()

        if isBackground {
            UserDefaults.standard.addObserver(self, forKeyPath: "isRecognitionEnabled", options: [.new, .initial], context: nil)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard isBackground else { return }

        if keyPath == "isRecognitionEnabled" {
            let isEnabled = UserDefaults.standard.bool(forKey: "isRecognitionEnabled")
            DispatchQueue.global(qos: .background).async {
                if isEnabled && self.permissionGranted {
                    if !self.captureSession.isRunning {
                        self.captureSession.startRunning()
                    }
                } else {
                    if self.captureSession.isRunning && !self.isRecording {
                        self.captureSession.stopRunning()
                    }
                }
            }
        }
    }

    deinit {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        if isBackground {
            UserDefaults.standard.removeObserver(self, forKeyPath: "isRecognitionEnabled")
        }
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
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480

        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Fix mirroring for natural gesture recording
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        captureSession.commitConfiguration()

        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
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
        let request = VNDetectHumanHandPoseRequest { request, _ in
            guard let results = request.results as? [VNHumanHandPoseObservation], !results.isEmpty else {
                completion([], [])
                return
            }

            var normalizedAll: [[CGPoint]] = []
            var rawAll: [[CGPoint]] = []

            let allJoints: [VNHumanHandPoseObservation.JointName] = [
                .wrist,
                .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
                .indexMCP, .indexPIP, .indexDIP, .indexTip,
                .middleMCP, .middlePIP, .middleDIP, .middleTip,
                .ringMCP, .ringPIP, .ringDIP, .ringTip,
                .littleMCP, .littlePIP, .littleDIP, .littleTip
            ]

            for hand in results.prefix(maxHands) {
                do {
                    var points: [CGPoint] = []
                    for joint in allJoints {
                        let point = try hand.recognizedPoint(joint)
                        points.append(CGPoint(x: point.location.x, y: point.location.y))
                    }
                    rawAll.append(points)

                    // Normalize: wrist-relative then scale by wrist→middleMCP distance
                    let wrist = points[0]
                    var normalized = points.map { CGPoint(x: $0.x - wrist.x, y: $0.y - wrist.y) }
                    let middleMCP = normalized[9]
                    let refDist = max(hypot(middleMCP.x, middleMCP.y), 0.01)
                    normalized = normalized.map { CGPoint(x: $0.x / refDist, y: $0.y / refDist) }
                    normalizedAll.append(normalized)
                } catch {
                    // skip this hand if joint extraction fails
                }
            }
            completion(normalizedAll, rawAll)
        }
        request.maximumHandCount = maxHands
        try? handler.perform([request])
    }
}

// MARK: – AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        var cropRatio = UserDefaults.standard.double(forKey: "cropSizeRatio")
        if cropRatio == 0 { cropRatio = 0.85 }

        let minDim = min(cgImage.width, cgImage.height)
        let cropSize = Int(Double(minDim) * cropRatio)
        let xOff = (cgImage.width - cropSize) / 2
        let yOff = (cgImage.height - cropSize) / 2
        let rect = CGRect(x: xOff, y: yOff, width: cropSize, height: cropSize)

        guard let croppedImage = cgImage.cropping(to: rect) else { return }

        let maxHands = twoHandMode ? 2 : 1

        extractLandmarks(from: croppedImage, maxHands: maxHands) { [weak self] normalizedHands, rawHands in
            guard let self = self else { return }

            DispatchQueue.main.async {
                // Update live overlay landmarks
                self.currentHandLandmarks = rawHands.first ?? []
                self.currentSecondHandLandmarks = rawHands.count > 1 ? rawHands[1] : []

                let requiredHandCount = self.twoHandMode ? 2 : 1
                let handsPresent = normalizedHands.count >= requiredHandCount
                self.isHandInFrame = handsPresent

                // Concatenate both hand landmark arrays for two-hand mode
                let combinedNormalized: [CGPoint]? = handsPresent
                    ? normalizedHands.prefix(requiredHandCount).flatMap { $0 }
                    : nil

                if self.isWaitingToRecord {
                    if handsPresent {
                        self.isWaitingToRecord = false
                        self.isRecording = true
                    }
                } else if self.isRecording {
                    if handsPresent, let pts = combinedNormalized {
                        self.capturedLandmarks.append(pts)
                        self.capturedFramesCount += 1

                        if self.capturedFramesCount >= self.maxFrames {
                            self.isRecording = false
                            self.onRecordingFinished?(self.capturedLandmarks)
                        }
                    } else if !handsPresent {
                        // Hand(s) left frame – stop and deliver
                        self.isRecording = false
                        self.onRecordingFinished?(self.capturedLandmarks)
                    }
                } else {
                    // Inference mode
                    if let pts = combinedNormalized {
                        if GestureRecognizer.shared.isModelLoaded {
                            GestureRecognizer.shared.predict(landmarks: pts, activeGestures: self.activeGestures)
                        }
                    }
                }
            }
        }
    }
}
