import Foundation
import Vision
import AppKit

class HandTracker {
    static let shared = HandTracker()
    
    var isActive = false
    
    // Configurable multiplier to map hand movement to screen
    private let sensitivityY: CGFloat = 2.0
    
    // We lock X coordinate to where the mouse currently is when the switcher opens
    private var lockedX: CGFloat? = nil
    
    // Baseline Y for tracking relative movement
    private var initialHandY: CGFloat? = nil
    private var initialMouseY: CGFloat? = nil
    
    // Moving average filter for Y coordinate to reduce jitter
    private var yHistory: [CGFloat] = []
    private let maxHistoryFrames = 5
    
    var onFistOpened: (() -> Void)?
    
    func startTracking() {
        isActive = true
        lockedX = NSEvent.mouseLocation.x
        initialMouseY = NSEvent.mouseLocation.y
        initialHandY = nil
        yHistory.removeAll()
        print("Hand Tracking Started - X coordinate locked at \(lockedX!)")
    }
    
    func stopTracking() {
        isActive = false
        lockedX = nil
        initialHandY = nil
        initialMouseY = nil
        yHistory.removeAll()
        print("Hand Tracking Stopped")
    }
    
    func processFrame(_ image: CGImage) {
        guard isActive else { return }
        
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        let request = VNDetectHumanHandPoseRequest { [weak self] request, error in
            guard let self = self,
                  let results = request.results as? [VNHumanHandPoseObservation],
                  let hand = results.first else {
                return
            }
            
            self.analyzeHand(hand)
        }
        
        request.maximumHandCount = 1
        
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform hand pose request: \(error)")
        }
    }
    
    private func analyzeHand(_ observation: VNHumanHandPoseObservation) {
        // Get wrist and fingertips
        guard let wrist = try? observation.recognizedPoint(.wrist),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let ringTip = try? observation.recognizedPoint(.ringTip),
              let littleTip = try? observation.recognizedPoint(.littleTip) else {
            return
        }
        
        // Vision coordinates are normalized (0.0 to 1.0) with origin at bottom-left
        let wristPoint = CGPoint(x: wrist.location.x, y: wrist.location.y)
        let tips = [
            CGPoint(x: indexTip.location.x, y: indexTip.location.y),
            CGPoint(x: middleTip.location.x, y: middleTip.location.y),
            CGPoint(x: ringTip.location.x, y: ringTip.location.y),
            CGPoint(x: littleTip.location.x, y: littleTip.location.y)
        ]
        
        // Calculate average distance from wrist to tips
        let averageDistance = tips.map { distance(from: wristPoint, to: $0) }.reduce(0, +) / CGFloat(tips.count)
        
        // Thresholds for open vs closed hand
        // In normalized coordinates, distance typically < 0.2 indicates a closed fist, > 0.3 indicates an open hand
        let isClosedFist = averageDistance < 0.25
        
        DispatchQueue.main.async {
            if isClosedFist {
                self.updateCursorPosition(normalizedY: wristPoint.y)
            } else {
                // Hand opened! Trigger selection and stop.
                print("Hand opened - finalizing selection.")
                self.onFistOpened?()
                self.stopTracking()
            }
        }
    }
    
    private func updateCursorPosition(normalizedY: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        
        if initialHandY == nil {
            initialHandY = normalizedY
            // We use the locked mouse Y if tracking started mid-action, else center it
            initialMouseY = initialMouseY ?? (screenHeight / 2)
        }
        
        guard let baselineY = initialHandY, let baseMouseY = initialMouseY, let fixedX = lockedX else { return }
        
        // Calculate delta (Vision Y goes up, Screen Y goes down from top-left, so we need to map accordingly)
        // Actually, Vision origin is bottom-left, NSEvent.mouseLocation origin is bottom-left
        // CGEvent origin is top-left! So we need to be careful with global display coordinates.
        
        let deltaY = (normalizedY - baselineY) * screenHeight * sensitivityY
        
        // NSEvent space is bottom-left. We want the hand moving UP (Vision +Y) to move the mouse UP (NSEvent +Y)
        var targetMouseY = baseMouseY + deltaY
        
        // Clamp to screen bounds
        targetMouseY = max(0, min(screenHeight, targetMouseY))
        
        // Apply moving average for smooth cursor
        yHistory.append(targetMouseY)
        if yHistory.count > maxHistoryFrames {
            yHistory.removeFirst()
        }
        let smoothedY = yHistory.reduce(0, +) / CGFloat(yHistory.count)
        
        // Move the cursor
        moveMouse(x: fixedX, y: smoothedY, screenHeight: screenHeight)
    }
    
    private func moveMouse(x: CGFloat, y: CGFloat, screenHeight: CGFloat) {
        // CGEvent uses top-left origin! Need to flip Y.
        let cgPoint = CGPoint(x: x, y: screenHeight - y)
        
        guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left) else {
            return
        }
        
        moveEvent.post(tap: .cghidEventTap)
    }
    
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        return hypot(p2.x - p1.x, p2.y - p1.y)
    }
}
