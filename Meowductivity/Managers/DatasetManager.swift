import Foundation
import AppKit
import CoreImage

class DatasetManager {
    static let shared = DatasetManager()
    
    // Directory structure: ~/Documents/Meowductivity/Dataset/
    var datasetDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Meowductivity/Dataset")
    }
    
    func saveFrames(_ frames: [CGImage], forGesture gestureName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trainingDir = datasetDirectory.appendingPathComponent("Training/\(gestureName)")
        let testingDir = datasetDirectory.appendingPathComponent("Testing/\(gestureName)")
        
        do {
            try FileManager.default.createDirectory(at: trainingDir, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: testingDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            completion(.failure(error))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Shuffle and split 80/20
            var shuffledFrames = frames.shuffled()
            let testCount = max(1, Int(Double(frames.count) * 0.2)) // 20% for testing
            let testFrames = Array(shuffledFrames.prefix(testCount))
            let trainFrames = Array(shuffledFrames.dropFirst(testCount))
            
            let timestamp = Int(Date().timeIntervalSince1970)
            
            do {
                for (index, frame) in trainFrames.enumerated() {
                    let fileURL = trainingDir.appendingPathComponent("\(timestamp)_train_\(index).jpg")
                    try self.saveImage(frame, to: fileURL)
                }
                for (index, frame) in testFrames.enumerated() {
                    let fileURL = testingDir.appendingPathComponent("\(timestamp)_test_\(index).jpg")
                    try self.saveImage(frame, to: fileURL)
                }
                
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func saveImage(_ cgImage: CGImage, to url: URL) throws {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw NSError(domain: "DatasetManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
        }
        try data.write(to: url)
    }
    
    private var backgroundIndex = 0
    func saveBackgroundFrame(_ frame: CGImage) {
        let isTest = backgroundIndex % 5 == 0 // 20% to testing
        let dir = datasetDirectory.appendingPathComponent(isTest ? "Testing/Background" : "Training/Background")
        
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        
        let fileURL = dir.appendingPathComponent("bg_\(backgroundIndex).jpg")
        try? saveImage(frame, to: fileURL)
        
        backgroundIndex = (backgroundIndex + 1) % 60
    }
    
    func deleteGesture(named gestureName: String) {
        let trainingDir = datasetDirectory.appendingPathComponent("Training/\(gestureName)")
        let testingDir = datasetDirectory.appendingPathComponent("Testing/\(gestureName)")
        
        do {
            if FileManager.default.fileExists(atPath: trainingDir.path) {
                try FileManager.default.removeItem(at: trainingDir)
            }
            if FileManager.default.fileExists(atPath: testingDir.path) {
                try FileManager.default.removeItem(at: testingDir)
            }
            print("Successfully deleted dataset for gesture: \(gestureName)")
        } catch {
            print("Failed to delete dataset for gesture \(gestureName): \(error)")
        }
    }
}
