import Foundation
import AVFoundation
import CoreImage
import AppKit
import Combine

struct GestureActionData {
    let actionName: String
    let appURL: String?
    let keyCombo: String?
}

class CameraManager: NSObject, ObservableObject {
    @Published var permissionGranted = false
    let captureSession = AVCaptureSession()
    
    @Published var isRecording = false
    @Published var capturedFramesCount = 0
    var maxFrames = 120 // ≈4 seconds at 30fps
    
    // Maintain a dict of gesture names to their action data for inference
    var activeGestures: [String: GestureActionData] = [:]
    
    private var capturedBuffers: [CGImage] = []
    private var videoOutput = AVCaptureVideoDataOutput()
    private let context = CIContext()
    
    var onRecordingFinished: (([CGImage]) -> Void)?
    
    override init() {
        super.init()
        checkPermission()
    }
    
    deinit {
        if captureSession.isRunning {
            captureSession.stopRunning()
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
            self.capturedBuffers.removeAll()
            self.capturedFramesCount = 0
            self.isRecording = true
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Crop picture to center 60% of shortest side (matches the 150x150 UI overlay)
        let minDim = min(cgImage.width, cgImage.height)
        let cropSize = Int(Double(minDim) * 0.6)
        let xOff = (cgImage.width - cropSize) / 2
        let yOff = (cgImage.height - cropSize) / 2
        let rect = CGRect(x: xOff, y: yOff, width: cropSize, height: cropSize)
        
        guard let croppedImage = cgImage.cropping(to: rect) else { return }
        
        if isRecording {
            DispatchQueue.main.async {
                self.capturedBuffers.append(croppedImage)
                self.capturedFramesCount = self.capturedBuffers.count
                
                if self.capturedFramesCount >= self.maxFrames {
                    self.isRecording = false
                    self.onRecordingFinished?(self.capturedBuffers)
                }
            }
        } else {
            // Forward live frames for real-time inference
            // Note: In a production app, we would drop frames here (e.g., process 1 out of 5 frames) to save CPU
            if HandTracker.shared.isActive {
                HandTracker.shared.processFrame(croppedImage)
            } else if GestureRecognizer.shared.isModelLoaded {
                GestureRecognizer.shared.predict(image: croppedImage, activeGestures: self.activeGestures)
            }
        }
    }
}
