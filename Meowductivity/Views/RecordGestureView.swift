import SwiftUI

// MARK: – Skeleton connections (pairs of joint indices within a single hand's 21 pts)
private let handConnections: [(Int, Int)] = [
    (0,1),(1,2),(2,3),(3,4),           // thumb
    (0,5),(5,6),(6,7),(7,8),           // index
    (0,9),(9,10),(10,11),(11,12),      // middle
    (0,13),(13,14),(14,15),(15,16),    // ring
    (0,17),(17,18),(18,19),(19,20),    // pinky
    (5,9),(9,13),(13,17)               // palm
]

// MARK: – Landmark preview canvas (supports 1 or 2 hands)
private struct LandmarkPreviewCanvas: View {
    /// All points: 21 = single hand, 42 = two hands (first 21 = hand A, next 21 = hand B)
    let points: [CGPoint]

    var body: some View {
        Canvas { ctx, size in
            guard !points.isEmpty else { return }

            let hands: [[CGPoint]]
            if points.count == 42 {
                hands = [Array(points[0..<21]), Array(points[21..<42])]
            } else {
                hands = [points]
            }

            // Compute a shared bounding box across all points so both hands scale together
            let padding: CGFloat = 24
            let xs = points.map { $0.x }
            let ys = points.map { $0.y }
            let minX = xs.min()!, maxX = xs.max()!
            let minY = ys.min()!, maxY = ys.max()!
            let rangeX = max(maxX - minX, 0.001)
            let rangeY = max(maxY - minY, 0.001)
            let availW = size.width  - padding * 2
            let availH = size.height - padding * 2
            let scale  = min(availW / rangeX, availH / rangeY)
            let drawW  = rangeX * scale
            let drawH  = rangeY * scale
            let originX = (size.width  - drawW) / 2
            let originY = (size.height - drawH) / 2

            func mapped(_ p: CGPoint) -> CGPoint {
                // Vision Y is bottom-up; Canvas Y is top-down → flip Y
                CGPoint(
                    x: originX + (p.x - minX) * scale,
                    y: originY + (maxY - p.y) * scale
                )
            }

            // Accent colors: hand A = system accent, hand B = orange
            let colors: [Color] = [.accentColor, .orange]

            for (handIdx, handPts) in hands.enumerated() {
                let color = colors[handIdx % colors.count]

                // Connections
                for (a, b) in handConnections {
                    guard a < handPts.count, b < handPts.count else { continue }
                    var path = Path()
                    path.move(to: mapped(handPts[a]))
                    path.addLine(to: mapped(handPts[b]))
                    ctx.stroke(path, with: .color(color.opacity(0.5)), lineWidth: 1.5)
                }
                // Joints
                for pt in handPts {
                    let c = mapped(pt)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x-4, y: c.y-4, width: 8, height: 8)),
                             with: .color(color))
                }
            }
        }
    }
}

// MARK: – Main view
struct RecordGestureView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cameraManager = CameraManager(isBackground: false)
    @AppStorage("cropSizeRatio") private var cropSizeRatio = 0.85

    @State private var gestureName: String = ""
    @State private var isSaving: Bool = false
    @State private var hasRecorded: Bool = false
    @State private var savedBadgeVisible: Bool = false

    /// Two-hand mode toggle – lives in preview panel, disabled once recording has started
    @State private var twoHandMode: Bool = false

    // Captured frames stored in memory until the user confirms Save
    @State private var capturedLandmarks: [[CGPoint]] = []

    // Preview animation
    @State private var previewFrameIndex: Int = 0
    @State private var previewTimer: Timer? = nil

    var onSave: (String) -> Void

    private var previewPoints: [CGPoint] {
        guard !capturedLandmarks.isEmpty else { return [] }
        return capturedLandmarks[previewFrameIndex % capturedLandmarks.count]
    }

    private var isTwoHand: Bool { capturedLandmarks.first?.count == 42 }

    var body: some View {
        VStack(spacing: 20) {
            Text("Record a Gesture")
                .font(.headline)

            Form {
                TextField("Gesture Name:", text: $gestureName)
            }
            .padding(.horizontal)
            .disabled(cameraManager.isRecording || hasRecorded)

            // ── Camera / Preview area ────────────────────────────────────
            ZStack {
                if hasRecorded {
                    previewPanel
                } else {
                    liveCameraView
                }
            }
            .padding(.horizontal)

            // ── Two-hand toggle (shown on camera page, before recording) ─
            if !hasRecorded {
                Toggle(isOn: $twoHandMode) {
                    HStack(spacing: 6) {
                        Image(systemName: "hands.sparkles")
                        Text("Two-hand gesture")
                            .font(.callout)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(cameraManager.isRecording || cameraManager.isWaitingToRecord)
                .padding(.horizontal)
            }

            // ── Buttons ──────────────────────────────────────────────────
            HStack {
                Button(cameraManager.isRecording
                       ? "Recording…"
                       : cameraManager.isWaitingToRecord
                       ? (twoHandMode ? "Waiting for both hands…" : "Waiting for hand…")
                       : (hasRecorded ? "Re-Record" : "Start Recording")) {
                    resetPreview()
                    cameraManager.twoHandMode = twoHandMode
                    cameraManager.startRecording()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !cameraManager.permissionGranted ||
                    cameraManager.isRecording ||
                    cameraManager.isWaitingToRecord ||
                    gestureName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    isSaving
                )

                Spacer()

                Button("Cancel") {
                    stopPreviewTimer()
                    cameraManager.cancelRecording()
                    dismiss()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveAndDismiss()
                }
                .disabled(!hasRecorded || isSaving || capturedLandmarks.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 450, height: 540)
        .onAppear {
            cameraManager.onRecordingFinished = { frames in
                self.capturedLandmarks = frames
                self.previewFrameIndex = 0
                self.hasRecorded = true
                self.startPreviewTimer()
            }
        }
        .onDisappear {
            stopPreviewTimer()
        }
    }

    // MARK: – Sub-views

    private var liveCameraView: some View {
        ZStack {
            if cameraManager.permissionGranted {
                CameraPreview(session: cameraManager.captureSession)
                    .frame(height: 260)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                    .overlay(
                        ZStack {
                            Rectangle()
                                .stroke(Color.blue.opacity(0.8), lineWidth: 3)
                            // First-hand dots (green)
                            Canvas { context, size in
                                for point in cameraManager.currentHandLandmarks {
                                    let x = (1.0 - point.x) * size.width
                                    let y = (1.0 - point.y) * size.height
                                    let rect = CGRect(x: x-3, y: y-3, width: 6, height: 6)
                                    context.fill(Path(ellipseIn: rect), with: .color(.green))
                                }
                                // Second-hand dots (orange) when in two-hand mode
                                for point in cameraManager.currentSecondHandLandmarks {
                                    let x = (1.0 - point.x) * size.width
                                    let y = (1.0 - point.y) * size.height
                                    let rect = CGRect(x: x-3, y: y-3, width: 6, height: 6)
                                    context.fill(Path(ellipseIn: rect), with: .color(.orange))
                                }
                            }
                        }
                        .frame(width: 260 * cropSizeRatio, height: 260 * cropSizeRatio)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 260)
                    .overlay(Text("Camera Access Required").foregroundColor(.secondary))
            }

            if cameraManager.isWaitingToRecord {
                overlayBadge {
                    let icon = twoHandMode ? "hands.sparkles" : "hand.raised"
                    let text = twoHandMode ? "Waiting for both hands…" : "Waiting for hand to enter frame…"
                    Label(text, systemImage: icon).foregroundColor(.yellow)
                }
            } else if cameraManager.isRecording {
                overlayBadge {
                    Label("Recording… \(cameraManager.capturedFramesCount) frames", systemImage: "circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                    )

                LandmarkPreviewCanvas(points: previewPoints)
                    .padding(12)

                // Frame counter + hand type badge
                HStack(spacing: 6) {
                    Image(systemName: isTwoHand ? "hands.sparkles.fill" : "hand.raised.fill")
                        .font(.caption2)
                    Text("Frame \(previewFrameIndex + 1) / \(capturedLandmarks.count)")
                        .font(.caption).bold()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                .padding(.bottom, 10)
            }
            .frame(height: 200)

            // Navigation row
            HStack(spacing: 16) {
                Button { stepFrame(by: -1) } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(capturedLandmarks.count <= 1)

                Text("Preview – \(capturedLandmarks.count) frame\(capturedLandmarks.count == 1 ? "" : "s") captured")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button { stepFrame(by: 1) } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(capturedLandmarks.count <= 1)
            }

            if savedBadgeVisible {
                Label("Saved!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption).bold()
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    // Floating status badge
    private func overlayBadge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            Spacer()
            HStack {
                ProgressView().controlSize(.small).padding(.trailing, 4)
                content().font(.caption).bold()
            }
            .padding(8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
            .padding(.bottom, 8)
        }
    }

    // MARK: – Helpers

    private func startPreviewTimer() {
        stopPreviewTimer()
        guard capturedLandmarks.count > 1 else { return }
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { _ in
            previewFrameIndex = (previewFrameIndex + 1) % capturedLandmarks.count
        }
    }

    private func stopPreviewTimer() {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    private func stepFrame(by delta: Int) {
        guard !capturedLandmarks.isEmpty else { return }
        stopPreviewTimer()
        previewFrameIndex = (previewFrameIndex + delta + capturedLandmarks.count) % capturedLandmarks.count
    }

    private func resetPreview() {
        stopPreviewTimer()
        capturedLandmarks = []
        previewFrameIndex = 0
        hasRecorded = false
        savedBadgeVisible = false
    }

    private func saveAndDismiss() {
        isSaving = true
        stopPreviewTimer()
        DatasetManager.shared.saveLandmarks(capturedLandmarks, forGesture: gestureName) { result in
            self.isSaving = false
            switch result {
            case .success:
                withAnimation { self.savedBadgeVisible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.onSave(self.gestureName)
                    self.dismiss()
                }
            case .failure(let error):
                print("Failed to save frames: \(error)")
            }
        }
    }
}

#Preview {
    RecordGestureView { gesture in
        print("Saved \(gesture)")
    }
}
