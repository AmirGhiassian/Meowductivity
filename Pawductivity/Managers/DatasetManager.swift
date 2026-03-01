import Foundation
import AppKit
import CreateML
import TabularData
import CoreML

struct GestureFrame: Codable {
    let landmarks: [CGPoint]
}

struct GestureData: Codable {
    let name: String
    let frames: [GestureFrame]
    /// Number of landmark points per frame. 21 = single hand, 42 = two hands.
    let pointCount: Int

    // Backward-compatible decoding (old files lack pointCount → default to 21)
    init(name: String, frames: [GestureFrame], pointCount: Int) {
        self.name = name
        self.frames = frames
        self.pointCount = pointCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        frames = try container.decode([GestureFrame].self, forKey: .frames)
        pointCount = try container.decodeIfPresent(Int.self, forKey: .pointCount) ?? 21
    }

    enum CodingKeys: String, CodingKey {
        case name, frames, pointCount
    }
}

class DatasetManager {
    static let shared = DatasetManager()

    // Directory structure: ~/Documents/Pawductivity/Dataset/
    var datasetDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Pawductivity/Meowductivity/Dataset")
    }

    var gesturesDirectory: URL {
        return datasetDirectory.appendingPathComponent("Gestures")
    }

    /// Compiled model for single-hand gestures (21 points = 42 features).
    var model1HUrl: URL { datasetDirectory.appendingPathComponent("GestureClassifier1H.mlmodelc") }
    /// Compiled model for two-hand gestures (42 points = 84 features).
    var model2HUrl: URL { datasetDirectory.appendingPathComponent("GestureClassifier2H.mlmodelc") }

    init() {
        try? FileManager.default.createDirectory(at: gesturesDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    // MARK: – Save

    func saveLandmarks(_ frames: [[CGPoint]], forGesture gestureName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard !frames.isEmpty else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "DatasetManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No frames provided"]))) }
                return
            }

            let pointCount = frames[0].count
            var augmented: [GestureFrame] = []
            
            // Aim for roughly 100-150 frames total. 
            // If we have many frames, we augment each one less.
            let augmentPerFrame = max(1, 120 / frames.count)

            for seedFrame in frames where seedFrame.count == pointCount {
                // Add the original frame
                augmented.append(GestureFrame(landmarks: seedFrame))
                
                // Add augmented versions
                for _ in 0..<augmentPerFrame {
                    let scale = CGFloat.random(in: 0.92...1.08)
                    let angle = CGFloat.random(in: -0.15...0.15)
                    let jitter: CGFloat = 0.015
                    let cosA = cos(angle), sinA = sin(angle)

                    var newPoints = [CGPoint]()
                    let handsCount = pointCount / 21
                    
                    let relDistJitterX = handsCount > 1 ? CGFloat.random(in: -0.1...0.1) : 0
                    let relDistJitterY = handsCount > 1 ? CGFloat.random(in: -0.1...0.1) : 0

                    for h in 0..<handsCount {
                        let base = h * 21
                        let wrist = seedFrame[base]
                        for pt in seedFrame[base..<base+21] {
                            let jx = CGFloat.random(in: -jitter...jitter)
                            let jy = CGFloat.random(in: -jitter...jitter)
                            
                            let tx = pt.x - wrist.x, ty = pt.y - wrist.y
                            var rx = (tx * cosA - ty * sinA) * scale + wrist.x + jx
                            var ry = (tx * sinA + ty * cosA) * scale + wrist.y + jy
                            
                            if h > 0 {
                                rx += relDistJitterX
                                ry += relDistJitterY
                            }
                            
                            newPoints.append(CGPoint(x: rx, y: ry))
                        }
                    }
                    augmented.append(GestureFrame(landmarks: newPoints))
                }
            }

            let gestureData = GestureData(name: gestureName, frames: augmented, pointCount: pointCount)
            let fileURL = self.gesturesDirectory.appendingPathComponent("\(gestureName).json")

            do {
                let data = try JSONEncoder().encode(gestureData)
                try data.write(to: fileURL)
                self.cleanupOldData(forGesture: gestureName)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: – Load

    func loadLandmarks(forGesture gestureName: String) -> [[CGPoint]]? {
        let fileURL = gesturesDirectory.appendingPathComponent("\(gestureName).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let gestureData = try JSONDecoder().decode(GestureData.self, from: data)
            return gestureData.frames.map { $0.landmarks }
        } catch {
            print("Failed to load landmarks for gesture \(gestureName): \(error)")
            return nil
        }
    }

    /// Loads all gestures, grouping by point count.
    func loadAllGestures() -> [String: [[CGPoint]]] {
        var all: [String: [[CGPoint]]] = [:]
        guard let files = try? FileManager.default.contentsOfDirectory(at: gesturesDirectory, includingPropertiesForKeys: nil) else { return all }
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            if let landmarks = loadLandmarks(forGesture: name) { all[name] = landmarks }
        }
        return all
    }

    /// Loads all gesture metadata (name + pointCount) without loading full frame data.
    func loadAllGestureMetadata() -> [(name: String, pointCount: Int)] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: gesturesDirectory, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { file -> (String, Int)? in
            guard file.pathExtension == "json",
                  let data = try? Data(contentsOf: file),
                  let gd = try? JSONDecoder().decode(GestureData.self, from: data) else { return nil }
            return (gd.name, gd.pointCount)
        }
    }

    // MARK: – Train

    /// Trains one or two CoreML classifiers:
    ///  - `GestureClassifier1H.mlmodelc` for single-hand gestures (pointCount == 21)
    ///  - `GestureClassifier2H.mlmodelc` for two-hand gestures   (pointCount == 42)
    func trainModel(completion: @escaping (Result<[URL], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let metadata = self.loadAllGestureMetadata()
            guard !metadata.isEmpty else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "DatasetManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No gesture data found"]))) }
                return
            }

            // Group gesture names by point count
            var byPointCount: [Int: [String]] = [:]
            for m in metadata {
                byPointCount[m.pointCount, default: []].append(m.name)
            }

            var trainedURLs: [URL] = []
            var trainingError: Error? = nil

            for (pointCount, gestureNames) in byPointCount {
                // We can train if we have at least 1 actual gesture (we'll synthesize a Rest class if needed)
                guard !gestureNames.isEmpty else { continue }

                // Build DataFrame columns
                var labels = [String]()
                var px: [[Double]] = Array(repeating: [], count: pointCount)
                var py: [[Double]] = Array(repeating: [], count: pointCount)

                for name in gestureNames {
                    guard let frames = self.loadLandmarks(forGesture: name) else { continue }
                    for frame in frames {
                        guard frame.count == pointCount else { continue }
                        labels.append(name)
                        for (i, pt) in frame.enumerated() {
                            px[i].append(Double(pt.x))
                            py[i].append(Double(pt.y))
                        }
                    }
                }

                // If we only have ONE gesture for this hand-count, we MUST add a second class 
                // for the MLClassifier to even train (classification requires ≥2 classes).
                // We'll synthesize a "Rest" class with noise around the origin.
                if gestureNames.count == 1 {
                    for _ in 0..<100 {
                        labels.append("Rest")
                        for i in 0..<pointCount {
                            // Points at origin with some jitter
                            px[i].append(Double.random(in: -0.05...0.05))
                            py[i].append(Double.random(in: -0.05...0.05))
                        }
                    }
                }

                guard labels.count >= 2 else { continue }

                var df = DataFrame()
                df.append(column: Column<String>(name: "label", contents: labels))
                for i in 0..<pointCount {
                    df.append(column: Column<Double>(name: "p\(i)_x", contents: px[i]))
                    df.append(column: Column<Double>(name: "p\(i)_y", contents: py[i]))
                }

                let isTwoHand = pointCount == 42
                let modelName = isTwoHand ? "GestureClassifier2H" : "GestureClassifier1H"
                let modelURL = self.datasetDirectory.appendingPathComponent("\(modelName).mlmodel")
                let compiledDest = isTwoHand ? self.model2HUrl : self.model1HUrl

                do {
                    let classifier = try MLClassifier(trainingData: df, targetColumn: "label")

                    if FileManager.default.fileExists(atPath: modelURL.path) {
                        try FileManager.default.removeItem(at: modelURL)
                    }

                    let meta = MLModelMetadata(
                        author: "Pawductivity",
                        shortDescription: "Custom CoreML Landmark Hand Gesture Model (\(isTwoHand ? "2-hand" : "1-hand"))",
                        version: "2.0"
                    )
                    try classifier.write(to: modelURL, metadata: meta)

                    let compiledTemp = try MLModel.compileModel(at: modelURL)
                    if FileManager.default.fileExists(atPath: compiledDest.path) {
                        try FileManager.default.removeItem(at: compiledDest)
                    }
                    try FileManager.default.moveItem(at: compiledTemp, to: compiledDest)
                    trainedURLs.append(compiledDest)
                } catch {
                    trainingError = error
                    print("Training error for \(modelName): \(error)")
                }
            }

            DispatchQueue.main.async {
                if trainedURLs.isEmpty {
                    completion(.failure(trainingError ?? NSError(domain: "DatasetManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "No models trained (need ≥2 gestures per hand type)"])))
                } else {
                    completion(.success(trainedURLs))
                }
            }
        }
    }

    // MARK: – Delete / Cleanup

    func deleteGesture(named gestureName: String) {
        let fileURL = gesturesDirectory.appendingPathComponent("\(gestureName).json")
        try? FileManager.default.removeItem(at: fileURL)
        cleanupOldData(forGesture: gestureName)
        print("Successfully deleted dataset for gesture: \(gestureName)")
    }

    private func cleanupOldData(forGesture gestureName: String) {
        let dirs = [
            datasetDirectory.appendingPathComponent("Training/\(gestureName)"),
            datasetDirectory.appendingPathComponent("Testing/\(gestureName)"),
            datasetDirectory.appendingPathComponent("Training/Background"),
            datasetDirectory.appendingPathComponent("Testing/Background")
        ]
        dirs.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
