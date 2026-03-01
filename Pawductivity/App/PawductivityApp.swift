//
//  PawductivityApp.swift
//  Pawductivity
//
//  Created by Amirreza Ghiassian on 2026-02-28.
//

import SwiftUI
import SwiftData
import AppKit
import UserNotifications
import AVFoundation
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Global camera manager to run in the background
    let cameraManager = CameraManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApp.setActivationPolicy(.accessory)
        DotsOverlayWindowManager.shared.setup()

        // Load active gestures for the background camera manager
        let schema = Schema([GestureTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            refreshActiveGestures(modelContext: container.mainContext)
        }

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Delay permission prompts slightly so the menu bar is visible first.
        // Both checks run on EVERY launch — the OS shows the dialog each time
        // a required permission is still missing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkPermissions()
        }
    }

    private func checkPermissions() {
        // ── Camera ────────────────────────────────────────────────────────
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        case .denied, .restricted:
            showPermissionAlert(
                title: "Camera Access Required",
                message: "Pawductivity needs camera access to detect hand gestures. Enable it in System Settings → Privacy → Camera.",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
            )
        default: break
        }

        // ── Accessibility ─────────────────────────────────────────────────
        // AXIsProcessTrustedWithOptions with prompt:true opens the Accessibility
        // pane in System Settings and highlights this app every launch it's missing.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            print("[Permissions] Accessibility not granted — system prompt shown.")
        }
    }

    private func showPermissionAlert(title: String, message: String, settingsURL: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: settingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    
    func refreshActiveGestures(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<GestureTask>()
        do {
            let gestures = try modelContext.fetch(descriptor)
            
            // Get metadata to know which gestures are 2-hand
            let metadata = DatasetManager.shared.loadAllGestureMetadata()
            let twoHandGestures = Set(metadata.filter { $0.pointCount == 42 }.map { $0.name })

            var activeDict: [String: GestureActionData] = [:]
            for gesture in gestures where gesture.isActive {
                if gesture.actionName != "None" {
                    let isTwoHand = twoHandGestures.contains(gesture.gestureName)
                    activeDict[gesture.gestureName] = GestureActionData(
                        actionName: gesture.actionName, 
                        appURL: gesture.appURL, 
                        keyCombo: gesture.keyCombo,
                        isTwoHand: isTwoHand
                    )
                }
            }
            cameraManager.activeGestures = activeDict
            
            // Automatically enable two-hand mode if any active gesture requires it
            let needsTwoHands = activeDict.values.contains { $0.isTwoHand }
            cameraManager.twoHandMode = needsTwoHands
            
            // Ensure model is loaded/reloaded to match active gestures
            GestureRecognizer.shared.loadModel()
            
            print("Loaded \(activeDict.count) active gestures for inference. Two-hand mode: \(needsTwoHands)")
        } catch {
            print("Failed to fetch gestures: \(error)")
        }
    }
    

    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is active/foreground
        completionHandler([.banner, .sound])
    }
}

@main
struct PawductivityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @ObservedObject private var cameraManager = CameraManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            GestureTask.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra(
            "Pawductivity",
            systemImage: cameraManager.isHandInFrame ? "hand.raised.fill" : "camera.viewfinder"
        ) {
            QuickSettingsView()
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .modelContainer(sharedModelContainer)
                .onAppear {
                    appDelegate.refreshActiveGestures(modelContext: sharedModelContainer.mainContext)
                }
        }
    }
}

