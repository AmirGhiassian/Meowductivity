import Foundation
import SwiftData

@Model
final class GestureTask {
    var id: UUID
    var gestureName: String
    var actionName: String
    var isActive: Bool
    var appURL: String?
    var keyCombo: String?
    
    init(id: UUID = UUID(), gestureName: String, actionName: String = "None", isActive: Bool = true, appURL: String? = nil, keyCombo: String? = nil) {
        self.id = id
        self.gestureName = gestureName
        self.actionName = actionName
        self.isActive = isActive
        self.appURL = appURL
        self.keyCombo = keyCombo
    }
}
