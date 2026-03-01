import Foundation
import AppKit
import UserNotifications
import ApplicationServices

// MARK: – Private CGS Space-switching API (Dynamic Linker)
private typealias _CGSConnectionID = UInt32

// RTLD_DEFAULT is -2 on macOS. This searches all loaded libraries.
private let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

private func getCGSSymbol<T>(_ name: String) -> T? {
    let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    let variants = [
        name, "_" + name,
        name.replacingOccurrences(of: "CGS", with: "SLS"),
        "_" + name.replacingOccurrences(of: "CGS", with: "SLS"),
        name.replacingOccurrences(of: "Workspace", with: "CurrentSpace"),
        "_" + name.replacingOccurrences(of: "Workspace", with: "CurrentSpace")
    ]
    
    for variant in variants {
        if let sym = dlsym(handle ?? RTLD_DEFAULT, variant) {
            return unsafeBitCast(sym, to: T.self)
        }
    }

    if let error = dlerror() {
        print("CGS Debug: Failed to resolve symbol '\(name)' after trying variants \(variants). Error: \(String(cString: error))")
    }
    return nil
}







private typealias CGSMainConnectionIDFunc = @convention(c) () -> _CGSConnectionID
private typealias CGSGetWorkspaceFunc = @convention(c) (_CGSConnectionID, UnsafeMutablePointer<Int32>) -> Int32
private typealias CGSSetWorkspaceFunc = @convention(c) (_CGSConnectionID, Int32) -> Int32
private typealias CGSGetWorkspaceWindowCountFunc = @convention(c) (_CGSConnectionID, Int32, UnsafeMutablePointer<Int32>) -> Int32


class ActionExecutor {
    static let shared = ActionExecutor()
    
    private init() {
        // Proactively request Automation permission on start
        requestAutomationPermission()
    }
    
    // We prevent firing the same action rapidly
    private var lastExecutionTime: Date = Date.distantPast

    /// Returns true if Accessibility permission is currently granted.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Checks if Automation permission (System Events) is granted by attempting a trivial script.
    var hasAutomationPermission: Bool {
        let script = "tell application \"System Events\" to get name"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }

    /// Forces a system prompt for Automation permission by running a trivial script.
    func requestAutomationPermission() {
        DispatchQueue.global(qos: .background).async {
            let script = "tell application \"System Events\" to get name"
            if let scriptObject = NSAppleScript(source: script) {
                var error: NSDictionary?
                scriptObject.executeAndReturnError(&error)
                if let error = error {
                    print("Automation Request status: \(error)")
                } else {
                    print("Automation Permission granted.")
                }
            }
        }
    }

    /// Shows a native alert directing the user to grant Accessibility permission.
    private func showAccessibilityAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Pawductivity needs Accessibility access to control system shortcuts (e.g. Switch Space). Please enable it in System Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    struct ActionGroup {
        let title: String
        let actions: [String]
    }
    
    let actionGroups: [ActionGroup] = [
        ActionGroup(title: "General", actions: [
            "None",
            "Open Application...",
            "Custom Key Combo...",
            "Enable Dictation",
            "Lock Mac"
        ]),
        ActionGroup(title: "Window & Space", actions: [
            "Application Switcher (Forward)",
            "Application Switcher (Backward)",
            "Cycle Windows (Forward)",
            "Cycle Windows (Backward)",
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
        let cooldown = UserDefaults.standard.object(forKey: "cooldown") as? TimeInterval ?? 3.0

        guard Date().timeIntervalSince(lastExecutionTime) > cooldown else { return }
        
        // "None" or unassigned gestures shouldn't execute
        guard actionName != "None" else { return }
        
        print("Executing action: \(actionName)")
        lastExecutionTime = Date()
        
        switch actionName {
        case "Application Switcher (Forward)": switchApplication(forward: true)
        case "Application Switcher (Backward)": switchApplication(forward: false)
        case "Cycle Windows (Forward)": cycleWindows(forward: true)
        case "Cycle Windows (Backward)": cycleWindows(forward: false)
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
        case "Lock Mac": lockMac()
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
    
    private func cycleWindows(forward: Bool) {
        // Window cycling logic: Cmd + ` (the key below Esc)
        // Virtual key for ` (Backtick) is 0x32
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        var flags: CGEventFlags = .maskCommand
        if !forward {
            flags.insert(.maskShift)
            let shiftDown = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: true)
            shiftDown?.flags = flags
            shiftDown?.post(tap: .cghidEventTap)
        }
        
        // Tap Backtick (0x32)
        let backtickDown = CGEvent(keyboardEventSource: src, virtualKey: 0x32, keyDown: true)
        backtickDown?.flags = flags
        backtickDown?.post(tap: .cghidEventTap)
        
        let backtickUp = CGEvent(keyboardEventSource: src, virtualKey: 0x32, keyDown: false)
        backtickUp?.flags = flags
        backtickUp?.post(tap: .cghidEventTap)
        
        if !forward {
            let shiftUp = CGEvent(keyboardEventSource: src, virtualKey: 0x38, keyDown: false)
            shiftUp?.flags = .maskCommand
            shiftUp?.post(tap: .cghidEventTap)
        }
        
        // Release Cmd
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }
    
    private func switchScreen(right: Bool) {
        // --- Tier 1: Private CGS API (No permissions required) ---
        let getMainConn: CGSMainConnectionIDFunc? = getCGSSymbol("CGSMainConnectionID")
        let getWS: CGSGetWorkspaceFunc? = getCGSSymbol("CGSGetWorkspace")
        let setWS: CGSSetWorkspaceFunc? = getCGSSymbol("CGSSetWorkspace")
        let getWSCount: CGSGetWorkspaceWindowCountFunc? = getCGSSymbol("CGSGetWorkspaceWindowCount")

        if let getMainConn = getMainConn, let getWS = getWS, let setWS = setWS, let getWSCount = getWSCount {
            let cid = getMainConn()
            var current: Int32 = 0
            getWS(cid, &current)

            var maxSpace: Int32 = 1
            for ws in 1...32 {
                var cnt: Int32 = 0
                if getWSCount(cid, Int32(ws), &cnt) == 0 {
                    maxSpace = Int32(ws)
                } else if ws > 1 { break }
            }

            let next: Int32 = right ? (current < maxSpace ? current + 1 : current) : (current > 1 ? current - 1 : current)
            if next != current {
                print("switchScreen (CGS): \(current) → \(next)")
                setWS(cid, next)
                return // Success!
            } else {
                print("switchScreen (CGS): already at edge")
                return
            }
        }

        // --- Tier 2: AppleScript (Most reliable now that Sandbox is OFF) ---
        print("switchScreen: CGS failed. falling back to AppleScript (Control+Arrow)")
        let appleScriptCode = right ? 124 : 123
        runAppleScript("tell application \"System Events\" to key code \(appleScriptCode) using {control down}")
        print("switchScreen: AppleScript command sent.")
        
        // --- Tier 3: CGEvent (Secondary fallback) ---
        if hasAccessibilityPermission {
            let keyCode: CGKeyCode = right ? 0x7C : 0x7B
            postKeyCombo(virtualKeys: [keyCode], flags: .maskControl)
            print("switchScreen: CGEvent backup sent.")
        }
    }
    
    private func showMissionControl() {
        guard hasAccessibilityPermission else { showAccessibilityAlert(); return }
        postKeyCombo(virtualKeys: [0x7E], flags: .maskControl)
    }
    
    private func showDesktop() {
        guard hasAccessibilityPermission else { showAccessibilityAlert(); return }
        postKeyCombo(virtualKeys: [0x67], flags: [])
    }
    
    private func toggleFullscreen() {
        guard hasAccessibilityPermission else { showAccessibilityAlert(); return }
        postKeyCombo(virtualKeys: [0x03], flags: [.maskCommand, .maskControl])
    }
    
    private func minimizeWindow() {
        guard hasAccessibilityPermission else { showAccessibilityAlert(); return }
        postKeyCombo(virtualKeys: [0x2E], flags: .maskCommand)
    }
    
    private func quitApplication() {
        guard hasAccessibilityPermission else { showAccessibilityAlert(); return }
        postKeyCombo(virtualKeys: [0x0C], flags: .maskCommand)
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
        sendMediaKey(keyType: 17) // NX_KEYTYPE_NEXT
    }
    
    private func previousSong() {
        sendMediaKey(keyType: 18) // NX_KEYTYPE_PREVIOUS
    }
    
    private func playPauseMedia() {
        sendMediaKey(keyType: 16) // NX_KEYTYPE_PLAY
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
    
    private func lockMac() {
        // Standard macOS lock shortcut: Cmd + Ctrl + Q
        runAppleScript("tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
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
    
    // MARK: – Media key simulation
    /// Sends a hardware media key event (works for any playing app, no AppleScript needed)
    private func sendMediaKey(keyType: Int) {
        // Key-down event
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (keyType << 16) | 0x0a00,
            data2: -1
        )
        // Key-up event
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (keyType << 16) | 0x0b00,
            data2: -1
        )
        keyDown?.cgEvent?.post(tap: .cghidEventTap)
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
    }
    
    // Helpers
    private func postKeyCombo(virtualKeys: [CGKeyCode], flags: CGEventFlags) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        
        for key in virtualKeys {
            let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
            down?.flags = flags
            down?.post(tap: .cghidEventTap)
            
            usleep(50000) // 50ms hold
            
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
