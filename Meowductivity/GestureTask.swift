import Foundation
import SwiftData

@Model
final class GestureTask {
    var id: UUID
    var gestureName: String
    var actionName: String
    var isActive: Bool
    
    init(id: UUID = UUID(), gestureName: String, actionName: String, isActive: Bool = true) {
        self.id = id
        self.gestureName = gestureName
        self.actionName = actionName
        self.isActive = isActive
    }
}
