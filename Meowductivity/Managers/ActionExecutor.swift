import Foundation
import AppKit
import UserNotifications

class ActionExecutor {
    static let shared = ActionExecutor()
    
    // We prevent firing the same action rapidly
    private var lastExecutionTime: Date = Date.distantPast
    private let cooldown: TimeInterval = 2.0
    
    struct ActionGroup {
        let title: String
        let actions: [String]
    }
    
    let actionGroups: [ActionGroup] = [
        ActionGroup(title: "General", actions: [
            "None",
            "Open Application...",
            "Custom Key Combo...",
            "Enable Dictation"
        ]),
        ActionGroup(title: "Window & Space", actions: [
            "Switch Application (Forward)",
            "Switch Application (Backward)",
            "Switch Screen (Left)",
            "Switch Screen (Right)",
            "Show Mission Control",
            "Show Desktop",
            "Toggle Fullscreen",
            "Minimize Window",
            "Quit Application"
        ]),
        ActionGroup(title: "Media Control", actions: [
            "Play/Pause Media",
            "Next Song",
            "Previous Song"
        ]),
        ActionGroup(title: "Volume", actions: [
            "Increase Volume",
            "Decrease Volume",
            "Mute Volume"
        ]),
        ActionGroup(title: "Brightness", actions: [
            "Increase Brightness",
            "Decrease Brightness"
        ])
    ]
    
    var allActions: [String] {
        actionGroups.flatMap { $0.actions }
    }
    
    func executeAction(named actionName: String, appURL: String? = nil, keyCombo: String? = nil) {
        // Prevent rapid re-execution
        guard Date().timeIntervalSince(lastExecutionTime) > cooldown else { return }
        
        // "None" or unassigned gestures shouldn't execute
        guard actionName != "None" else { return }
        
        print("Executing action: \(actionName)")
        lastExecutionTime = Date()
        
        switch actionName {
        case "Switch Application (Forward)": switchApplication(forward: true)
        case "Switch Application (Backward)": switchApplication(forward: false)
        case "Switch Screen (Left)": switchScreen(right: false)
        case "Switch Screen (Right)": switchScreen(right: true)
        case "Show Mission Control": showMissionControl()
        case "Show Desktop": showDesktop()
        case "Toggle Fullscreen": toggleFullscreen()
        case "Minimize Window": minimizeWindow()
        case "Quit Application": quitApplication()
        case "Open Application...": openApplication(url: appURL)
        case "Increase Volume": increaseVolume()
        case "Decrease Volume": decreaseVolume()
        case "Mute Volume": muteVolume()
        case "Next Song": nextSong()
        case "Previous Song": previousSong()
        case "Play/Pause Media": playPauseMedia()
        case "Enable Dictation": enableDictation()
        case "Increase Brightness": increaseBrightness()
        case "Decrease Brightness": decreaseBrightness()
        case "Custom Key Combo...": executeCustomKeyCombo(combo: keyCombo)
        default:
            // Fallback for previous saved rules
            if actionName == "Switch Application" { switchApplication(forward: true) }
            else if actionName == "Switch Screen" { switchScreen(right: true) }
            else { print("Unknown action: \(actionName)") }
        }
        
        // Post Notification if enabled
        let showNotifications = UserDefaults.standard.object(forKey: "showNotifications") as? Bool ?? true
        if showNotifications {
            postNotification(title: "Gesture Detected", body: "Triggered: \(actionName)")
        }
    }
    
    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func switchApplication(forward: Bool) {
        // App Switcher logic: Cmd + Tab (immediately release)
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        var tabFlags: CGEventFlags = .maskCommand
        if !forward {
            tabFlags.insert(.maskShift)
            let shiftDown = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: true)
            shiftDown?.flags = tabFlags
            shiftDown?.post(tap: .cghidEventTap)
        }
        
        // Tap Tab
        let tabDown = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: true)
        tabDown?.flags = tabFlags
        tabDown?.post(tap: .cghidEventTap)
        
        let tabUp = CGEvent(keyboardEventSource: src, virtualKey: 0x30, keyDown: false)
        tabUp?.flags = tabFlags
        tabUp?.post(tap: .cghidEventTap)
        
        if !forward {
            let shiftUp = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: false)
            shiftUp?.flags = .maskCommand
            shiftUp?.post(tap: .cghidEventTap)
        }
        
        // Release Cmd immediately
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }
    
    private func switchScreen(right: Bool) {
        // Simulates Ctrl+Right Arrow / Left Arrow (Move a space right/left)
        let key: CGKeyCode = right ? 0x7C : 0x7B // 0x7C = Right Arrow, 0x7B = Left Arrow
        postKeyCombo(virtualKeys: [key], flags: .maskControl) // 0x3B = Ctrl
    }
    
    private func showMissionControl() {
        // Simulates Ctrl+Up Arrow
        postKeyCombo(virtualKeys: [0x7E], flags: .maskControl) // 0x7E = Up Arrow
    }
    
    private func showDesktop() {
        // F11 (or Fn+F11) usually shows desktop
        postKeyCombo(virtualKeys: [0x67], flags: []) // 0x67 = F11
    }
    
    private func toggleFullscreen() {
        // Simulates Cmd+Ctrl+F
        postKeyCombo(virtualKeys: [0x03], flags: [.maskCommand, .maskControl]) // 0x03 = F
    }
    
    private func minimizeWindow() {
        // Simulates Cmd+M
        postKeyCombo(virtualKeys: [0x2E], flags: .maskCommand) // 0x2E = M
    }
    
    private func quitApplication() {
        // Simulates Cmd+Q
        postKeyCombo(virtualKeys: [0x0C], flags: .maskCommand) // 0x0C = Q
    }
    
    private func openApplication(url: String?) {
        guard let urlStr = url, let appUrl = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(appUrl)
    }
    
    private func increaseVolume() {
        let script = "set volume output volume (output volume of (get volume settings) + 10)"
        runAppleScript(script)
    }
    
    private func decreaseVolume() {
        let script = "set volume output volume (output volume of (get volume settings) - 10)"
        runAppleScript(script)
    }
    
    private func muteVolume() {
        // Toggle mute
        let script = "set volume with output muted"
        runAppleScript(script)
    }
    
    private func nextSong() {
        runAppleScript("tell application \"Music\" to next track")
    }
    
    private func previousSong() {
        runAppleScript("tell application \"Music\" to previous track")
    }
    
    private func playPauseMedia() {
        runAppleScript("tell application \"Music\" to playpause")
    }
    
    private func enableDictation() {
        // Simulates double-tap Fn
        postKeyCombo(virtualKeys: [0x3F], flags: [])
        postKeyCombo(virtualKeys: [0x3F], flags: [])
    }
    
    private func increaseBrightness() {
        runAppleScript("tell application \"System Events\" to key code 113")
    }
    
    private func decreaseBrightness() {
        runAppleScript("tell application \"System Events\" to key code 107")
    }
    
    private func executeCustomKeyCombo(combo: String?) {
        guard let combo = combo, !combo.isEmpty else { return }
        // Format: "cmd,shift,c"
        let parts = combo.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
        guard let keyString = parts.last else { return }
        
        var flags: CGEventFlags = []
        if parts.contains("cmd") || parts.contains("command") { flags.insert(.maskCommand) }
        if parts.contains("shift") { flags.insert(.maskShift) }
        if parts.contains("ctrl") || parts.contains("control") { flags.insert(.maskControl) }
        if parts.contains("opt") || parts.contains("option") || parts.contains("alt") { flags.insert(.maskAlternate) }
        
        let vk = virtualKey(for: keyString)
        postKeyCombo(virtualKeys: [vk], flags: flags)
    }
    
    // Helpers
    private func postKeyCombo(virtualKeys: [CGKeyCode], flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for key in virtualKeys {
            let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
            down?.flags = flags
            down?.post(tap: .cghidEventTap)
        }
        for key in virtualKeys.reversed() {
            let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
            up?.flags = flags
            up?.post(tap: .cghidEventTap)
        }
    }
    
    private func runAppleScript(_ source: String) {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
            }
        }
    }
    
    private func virtualKey(for string: String) -> CGKeyCode {
        let map: [String: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
            "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
            "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F,
            "tab": 0x30, "space": 0x31, "delete": 0x33, "esc": 0x35, "cmd": 0x37, "shift": 0x38, "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C, "enter": 0x24, "return": 0x24
        ]
        return map[string] ?? 0x00
    }
}
