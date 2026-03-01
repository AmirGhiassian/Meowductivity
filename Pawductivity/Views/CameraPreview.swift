import SwiftUI
import AVFoundation

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    
    class VideoPreviewView: NSView {
        override func makeBackingLayer() -> CALayer {
            return AVCaptureVideoPreviewLayer()
        }
        
        override init(frame: NSRect) {
            super.init(frame: frame)
            self.wantsLayer = true
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            self.wantsLayer = true
        }
        
        private var videoPreviewLayer: AVCaptureVideoPreviewLayer? {
            return layer as? AVCaptureVideoPreviewLayer
        }
        
        var session: AVCaptureSession? {
            get { videoPreviewLayer?.session }
            set {
                let newSession = newValue
                DispatchQueue.main.async {
                    if let layer = self.videoPreviewLayer {
                        if layer.session !== newSession {
                            layer.session = newSession
                            layer.videoGravity = .resizeAspectFill
                            if let connection = layer.connection, connection.isVideoMirroringSupported {
                                connection.automaticallyAdjustsVideoMirroring = false
                                connection.isVideoMirrored = true
                            }
                        }
                    }
                }
            }
        }
        
        override func layout() {
            super.layout()
            videoPreviewLayer?.frame = bounds
        }
    }
    
    func makeNSView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        // No session assignment here, wait for first update or layout
        return view
    }
    
    func updateNSView(_ nsView: VideoPreviewView, context: Context) {
        if nsView.session !== session {
            nsView.session = session
        }
    }
}
