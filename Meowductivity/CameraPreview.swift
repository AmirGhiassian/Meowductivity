import SwiftUI
import AVFoundation

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    
    class VideoPreviewView: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = AVCaptureVideoPreviewLayer()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
        
        var session: AVCaptureSession? {
            get { videoPreviewLayer.session }
            set {
                videoPreviewLayer.session = newValue
                videoPreviewLayer.videoGravity = .resizeAspectFill
            }
        }
        
        override func layout() {
            super.layout()
            layer?.frame = bounds
        }
    }
    
    func makeNSView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.session = session
        return view
    }
    
    func updateNSView(_ nsView: VideoPreviewView, context: Context) {
        nsView.session = session
    }
}
