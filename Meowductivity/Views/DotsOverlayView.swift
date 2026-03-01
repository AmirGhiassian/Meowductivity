import SwiftUI

struct DotsOverlayView: View {
    @ObservedObject var cameraManager = CameraManager.shared
    @AppStorage("showFaintDotsOverlay") private var showFaintDotsOverlay = false
    
    var body: some View {
        ZStack {
            Color.clear // Transparent background
            
            if showFaintDotsOverlay && cameraManager.isHandInFrame {
                Canvas { context, size in
                    for point in cameraManager.currentHandLandmarks {
                        let x = (1.0 - point.x) * size.width
                        let y = (1.0 - point.y) * size.height
                        // Use a faint green color
                        let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: rect), with: .color(.green.opacity(0.4)))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    DotsOverlayView()
}
