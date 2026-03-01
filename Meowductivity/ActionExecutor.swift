import Foundation
import AppKit

class ActionExecutor {
    static let shared = ActionExecutor()
    
    // We prevent firing the same action 50 times a second
    private var lastExecutionTime: Date = Date.distantPast
    private let cooldown: TimeInterval = 2.0
    
    func executeAction(named actionName: String) {
        guard Date().timeIntervalSince(lastExecutionTime) > cooldown else { return }
        
        print("Executing action: \(actionName)")
        lastExecutionTime = Date()
        
        switch actionName {
        case "Switch Application":
            switchApplication()
        case "Switch Screen":
            switchScreen()
        case "Show Mission Control":
            showMissionControl()
        case "Show Desktop":
            showDesktop()
        default:
            print("Unknown action: \(actionName)")
        }
    }
    
    private func switchApplication() {
        // Simulates Cmd+Tab
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        let tabDown = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: true)
        let tabUp = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        tabDown?.flags = .maskCommand
        tabUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        tabDown?.post(tap: .cghidEventTap)
        tabUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
    
    private func switchScreen() {
        // Simulates Ctrl+Right Arrow (Move a space right)
        let src = CGEventSource(stateID: .hidSystemState)
        let ctrlDown = CGEvent(keyboardEventSource: src, virtualKey: 0x3B, keyDown: true)
        let rightDown = CGEvent(keyboardEventSource: src, virtualKey: 0x7C, keyDown: true)
        let rightUp = CGEvent(keyboardEventSource: src, virtualKey: 0x7C, keyDown: false)
        let ctrlUp = CGEvent(keyboardEventSource: src, virtualKey: 0x3B, keyDown: false)
        
        ctrlDown?.flags = .maskControl
        rightDown?.flags = .maskControl
        rightUp?.flags = .maskControl
        
        ctrlDown?.post(tap: .cghidEventTap)
        rightDown?.post(tap: .cghidEventTap)
        rightUp?.post(tap: .cghidEventTap)
        ctrlUp?.post(tap: .cghidEventTap)
    }
    
    private func showMissionControl() {
        // Simulates Ctrl+Up Arrow
        let src = CGEventSource(stateID: .hidSystemState)
        let ctrlDown = CGEvent(keyboardEventSource: src, virtualKey: 0x3B, keyDown: true)
        let upDown = CGEvent(keyboardEventSource: src, virtualKey: 0x7E, keyDown: true)
        let upUp = CGEvent(keyboardEventSource: src, virtualKey: 0x7E, keyDown: false)
        let ctrlUp = CGEvent(keyboardEventSource: src, virtualKey: 0x3B, keyDown: false)
        
        ctrlDown?.flags = .maskControl
        upDown?.flags = .maskControl
        upUp?.flags = .maskControl
        
        ctrlDown?.post(tap: .cghidEventTap)
        upDown?.post(tap: .cghidEventTap)
        upUp?.post(tap: .cghidEventTap)
        ctrlUp?.post(tap: .cghidEventTap)
    }
    
    private func showDesktop() {
        // F11 (or Fn+F11) usually shows desktop
        let src = CGEventSource(stateID: .hidSystemState)
        let f11Down = CGEvent(keyboardEventSource: src, virtualKey: 0x67, keyDown: true)
        let f11Up = CGEvent(keyboardEventSource: src, virtualKey: 0x67, keyDown: false)
        
        f11Down?.post(tap: .cghidEventTap)
        f11Up?.post(tap: .cghidEventTap)
    }
}
