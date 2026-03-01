import SwiftUI

struct DotsOverlayView: View {
    @ObservedObject var cameraManager = CameraManager.shared
    @AppStorage("showFaintDotsOverlay") private var showFaintDotsOverlay = false
    
    var body: some View {
        ZStack {
            Color.clear // Transparent background
            
            if showFaintDotsOverlay && (cameraManager.isHandInFrame || !cameraManager.currentHandLandmarks.isEmpty) {
                Canvas { context, size in
                    // First hand - Green
                    for point in cameraManager.currentHandLandmarks {
                        let x = point.x * size.width
                        let y = (1.0 - point.y) * size.height
                        let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: rect), with: .color(.green.opacity(0.4)))
                    }
                    
                    // Second hand - Orange
                    for point in cameraManager.currentSecondHandLandmarks {
                        let x = point.x * size.width
                        let y = (1.0 - point.y) * size.height
                        let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: rect), with: .color(.orange.opacity(0.4)))
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
