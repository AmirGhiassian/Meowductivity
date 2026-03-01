import Foundation
import CreateML
import Combine

class GestureTrainer: ObservableObject {
    @Published var isTraining = false
    @Published var trainingStatus = "Idle"
    @Published var lastError: String? = nil
    
    func trainModel(completion: @escaping (Result<URL, Error>) -> Void) {
        let datasetDir = DatasetManager.shared.datasetDirectory
        let trainingDir = datasetDir.appendingPathComponent("Training")
        let testingDir = datasetDir.appendingPathComponent("Testing")
        
        guard FileManager.default.fileExists(atPath: trainingDir.path) else {
            DispatchQueue.main.async {
                self.lastError = "No training data found."
                completion(.failure(NSError(domain: "GestureTrainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No training data found."])))
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isTraining = true
            self.trainingStatus = "Loading Dataset..."
            self.lastError = nil
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let trainingDataSource = MLImageClassifier.DataSource.labeledDirectories(at: trainingDir)
                let testingDataSource = MLImageClassifier.DataSource.labeledDirectories(at: testingDir)
                
                DispatchQueue.main.async {
                    self.trainingStatus = "Training Model (this may take a while)..."
                }
                
                let parameters = MLImageClassifier.ModelParameters(
                    featureExtractor: .scenePrint(revision: 2),
                    validationData: nil,
                    maxIterations: 20,
                    augmentationOptions: [.crop, .blur, .exposure, .flip]
                )
                
                let classifier = try MLImageClassifier(trainingData: trainingDataSource, parameters: parameters)
                
                DispatchQueue.main.async {
                    self.trainingStatus = "Evaluating Model..."
                }
                
                let evaluation = classifier.evaluation(on: testingDataSource)
                print("Evaluation accuracy error: \(evaluation.classificationError)")
                
                let saveURL = datasetDir.appendingPathComponent("GestureClassifier.mlmodel")
                if FileManager.default.fileExists(atPath: saveURL.path) {
                    try FileManager.default.removeItem(at: saveURL)
                }
                
                let metadata = MLModelMetadata(
                    author: "Meowductivity",
                    shortDescription: "Custom Hand Gesture Model",
                    version: "1.0"
                )
                
                try classifier.write(to: saveURL, metadata: metadata)
                
                DispatchQueue.main.async {
                    self.trainingStatus = "Model Trained Successfully!"
                    self.isTraining = false
                    UserDefaults.standard.set(false, forKey: "needsTraining")
                    GestureRecognizer.shared.loadModel() // Reload new model in memory
                    completion(.success(saveURL))
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.trainingStatus = "Training Failed"
                    self.lastError = error.localizedDescription
                    self.isTraining = false
                    completion(.failure(error))
                }
            }
        }
    }
}
