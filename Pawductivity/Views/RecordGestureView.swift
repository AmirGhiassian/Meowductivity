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

    @ObservedObject private var cameraManager = CameraManager.shared
    @AppStorage("cropSizeRatio") private var cropSizeRatio = 0.85

    @State private var gestureName: String = ""
    @State private var isSaving: Bool = false
    @State private var hasRecorded: Bool = false
    @State private var savedBadgeVisible: Bool = false

    /// Two-hand mode toggle – lives in preview panel, disabled once recording has started
    @State private var twoHandMode: Bool = false

    // Captured frames stored in memory until the user confirms Save
    @State private var capturedLandmarks: [[CGPoint]] = []

    // Preview and Edit state
    @State private var previewFrameIndex: Int = 0
    @State private var previewTimer: Timer? = nil
    @State private var isEditMode: Bool = false
    @State private var draggingPointIndex: Int? = nil
    @State private var stableEditBounds: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? = nil

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
            VStack {
                if hasRecorded {
                    previewPanel
                } else {
                    liveCameraView
                }
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity)

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
        .frame(width: 600, height: 750)
        .onAppear {
            cameraManager.mode = .recording
            cameraManager.updateSessionState()
            
            cameraManager.onRecordingFinished = { frames in
                self.capturedLandmarks = frames
                self.previewFrameIndex = 0
                self.hasRecorded = true
                self.startPreviewTimer()
            }
        }
        .onChange(of: previewFrameIndex) { _ in
            if isEditMode {
                let pts = capturedLandmarks[previewFrameIndex]
                if !pts.isEmpty {
                    let xs = pts.map { $0.x }, ys = pts.map { $0.y }
                    stableEditBounds = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
                }
            }
        }
        .onDisappear {
            cameraManager.mode = .inference
            cameraManager.updateSessionState()
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
                        // Single canvas covering the full preview.
                        // Vision detects on the full 640×480 frame; map to display using
                        // the same resizeAspectFill math that AVCaptureVideoPreviewLayer uses.
                        Canvas { context, size in
                            let camW: CGFloat = 640
                            let camH: CGFloat = 480

                            // resizeAspectFill: scale to fill, clip the excess
                            let scale = max(size.width / camW, size.height / camH)
                            let scaledW = camW * scale
                            let scaledH = camH * scale
                            let xClip = (scaledW - size.width)  / 2
                            let yClip = (scaledH - size.height) / 2

                            // Map a Vision point (x ∈ [0,1] left→right MIRRORED, y ∈ [0,1] bottom→top)
                            // to canvas coords. X is already mirrored in the pixel data.
                            func mapped(_ p: CGPoint) -> CGPoint {
                                CGPoint(
                                    x: p.x * scaledW - xClip,
                                    y: (1.0 - p.y) * scaledH - yClip
                                )
                            }

                            // ── Crop box ──────────────────────────────────────────────
                            if !self.twoHandMode {
                                let cr = UserDefaults.standard.double(forKey: "cropSizeRatio").isZero
                                         ? 0.85
                                         : UserDefaults.standard.double(forKey: "cropSizeRatio")
                                let minDim = min(camW, camH)
                                let cropPx = minDim * cr
                                // Crop box in Vision full-frame coords (x: centered, y: centered)
                                let boxLeft   = (camW - cropPx) / 2 / camW
                                let boxRight  = boxLeft + cropPx / camW
                                let boxBottom = (camH - cropPx) / 2 / camH  // Vision y-bottom
                                let boxTop    = boxBottom + cropPx / camH   // Vision y-top

                                let tl = mapped(CGPoint(x: boxLeft,  y: boxTop))
                                let br = mapped(CGPoint(x: boxRight, y: boxBottom))
                                let boxRect = CGRect(x: tl.x, y: tl.y,
                                                     width: br.x - tl.x, height: br.y - tl.y)
                                let boxPath = Path(boxRect)
                                context.stroke(boxPath, with: .color(.blue.opacity(0.8)), lineWidth: 3)
                            }

                            // ── Hand dots ─────────────────────────────────────────────
                            for pt in cameraManager.currentHandLandmarks {
                                let c = mapped(pt)
                                context.fill(Path(ellipseIn: CGRect(x: c.x-4, y: c.y-4, width: 8, height: 8)),
                                             with: .color(.green))
                            }
                            for pt in cameraManager.currentSecondHandLandmarks {
                                let c = mapped(pt)
                                context.fill(Path(ellipseIn: CGRect(x: c.x-4, y: c.y-4, width: 8, height: 8)),
                                             with: .color(.orange))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
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
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                    )

                if isEditMode {
                    GeometryReader { geo in
                        landmarkEditorView(size: geo.size)
                    }
                } else {
                    LandmarkPreviewCanvas(points: previewPoints)
                        .padding(12)
                }

                // Header tools
                VStack {
                    HStack {
                        Button(isEditMode ? "Done Editing" : "Edit Landmarks") {
                            if !isEditMode {
                                // Capture stable bounds before editing
                                let pts = capturedLandmarks[previewFrameIndex]
                                if !pts.isEmpty {
                                    let xs = pts.map { $0.x }, ys = pts.map { $0.y }
                                    stableEditBounds = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
                                }
                                stopPreviewTimer()
                            }
                            isEditMode.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(isEditMode ? .green : .blue)
                        
                        Spacer()
                        
                        // Hand type badge
                        HStack(spacing: 6) {
                            Image(systemName: isTwoHand ? "hands.sparkles.fill" : "hand.raised.fill")
                                .font(.caption2)
                            Text("Frame \(previewFrameIndex + 1) / \(capturedLandmarks.count)")
                                .font(.caption).bold()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                    }
                    .padding(10)
                    Spacer()
                }
            }
            .frame(height: 300)

            // Timeline area
            VStack(alignment: .leading, spacing: 4) {
                Text("Gesture Timeline")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 12) {
                            insertButton(at: 0)
                            
                            ForEach(capturedLandmarks.indices, id: \.self) { i in
                                timelineItem(at: i)
                                    .id(i)
                                insertButton(at: i + 1)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                    }
                    .onChange(of: previewFrameIndex) { newIdx in
                        withAnimation { proxy.scrollTo(newIdx, anchor: .center) }
                    }
                }
            }
            .background(Color.black.opacity(0.05))
            .cornerRadius(12)

            // Playback controls
            HStack(spacing: 20) {
                Button { stepFrame(by: -1) } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(capturedLandmarks.count <= 1 || isEditMode)

                Button {
                    if previewTimer == nil { startPreviewTimer() }
                    else { stopPreviewTimer() }
                } label: {
                    Image(systemName: previewTimer == nil ? "play.circle.fill" : "pause.circle.fill").font(.largeTitle)
                }
                .buttonStyle(.plain)
                .disabled(capturedLandmarks.count <= 1 || isEditMode)

                Button { stepFrame(by: 1) } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(capturedLandmarks.count <= 1 || isEditMode)
            }

            if savedBadgeVisible {
                Label("Saved!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption).bold()
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private func timelineItem(at index: Int) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                LandmarkPreviewCanvas(points: capturedLandmarks[index])
                    .frame(width: 80, height: 60)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(previewFrameIndex == index ? Color.accentColor : Color.secondary.opacity(0.3), 
                                    lineWidth: previewFrameIndex == index ? 3 : 1)
                    )
                    .onTapGesture {
                        previewFrameIndex = index
                        stopPreviewTimer()
                    }
                
                Button(action: { deleteFrame(at: index) }) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
            }
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(previewFrameIndex == index ? .accentColor : .secondary)
        }
    }

    private func insertButton(at index: Int) -> some View {
        Button(action: { insertCurrentFrame(at: index) }) {
            VStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                Text("Snap")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
            }
        }
        .buttonStyle(.plain)
        .help("Insert current camera frame here")
    }

    private func landmarkEditorView(size: CGSize) -> some View {
        let points = capturedLandmarks[previewFrameIndex]
        let padding: CGFloat = 30
        
        // Use stable bounds if available, otherwise fallback to current
        let bounds = stableEditBounds ?? {
            let xs = points.map { $0.x }, ys = points.map { $0.y }
            return (xs.min() ?? 0, xs.max() ?? 1, ys.min() ?? 0, ys.max() ?? 1)
        }()
        
        let minX = bounds.minX, maxX = bounds.maxX
        let minY = bounds.minY, maxY = bounds.maxY
        
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
            CGPoint(
                x: originX + (p.x - minX) * scale,
                y: originY + (maxY - p.y) * scale
            )
        }
        
        func unmapped(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: minX + (p.x - originX) / scale,
                y: maxY - (p.y - originY) / scale
            )
        }

        return ZStack {
            // Background Connections (static overlay)
            // We use the same mapping logic to draw lines
            Path { path in
                for (a, b) in handConnections {
                    let hands: [[CGPoint]]
                    if points.count == 42 {
                        hands = [Array(points[0..<21]), Array(points[21..<42])]
                    } else {
                        hands = [points]
                    }
                    
                    for (handIdx, handPts) in hands.enumerated() {
                        let offset = handIdx * 21
                        guard a < handPts.count, b < handPts.count else { continue }
                        path.move(to: mapped(handPts[a + offset]))
                        path.addLine(to: mapped(handPts[b + offset]))
                    }
                }
            }
            .stroke(Color.gray.opacity(0.3), lineWidth: 1.5)
            
            // Interactive Dots
            ForEach(points.indices, id: \.self) { i in
                let pos = mapped(points[i])
                Circle()
                    .fill(i < 21 ? Color.accentColor : Color.orange)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(radius: draggingPointIndex == i ? 4 : 0)
                    .position(pos)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                draggingPointIndex = i
                                var updatedPoints = points
                                let newPt = unmapped(value.location)
                                updatedPoints[i] = CGPoint(
                                    x: max(0, min(1, newPt.x)),
                                    y: max(0, min(1, newPt.y))
                                )
                                capturedLandmarks[previewFrameIndex] = updatedPoints
                            }
                            .onEnded { _ in
                                draggingPointIndex = nil
                            }
                    )
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

    private func deleteFrame(at index: Int) {
        withAnimation {
            capturedLandmarks.remove(at: index)
            if previewFrameIndex >= capturedLandmarks.count && !capturedLandmarks.isEmpty {
                previewFrameIndex = capturedLandmarks.count - 1
            }
            if capturedLandmarks.isEmpty {
                hasRecorded = false
            }
        }
    }

    private func insertCurrentFrame(at index: Int) {
        var newFrame: [CGPoint] = []
        if twoHandMode {
            guard cameraManager.currentHandLandmarks.count == 21,
                  cameraManager.currentSecondHandLandmarks.count == 21 else { return }
            newFrame = cameraManager.currentHandLandmarks + cameraManager.currentSecondHandLandmarks
        } else {
            guard cameraManager.currentHandLandmarks.count == 21 else { return }
            newFrame = cameraManager.currentHandLandmarks
        }
        
        withAnimation {
            capturedLandmarks.insert(newFrame, at: index)
            previewFrameIndex = index
            hasRecorded = true
            stopPreviewTimer()
        }
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
