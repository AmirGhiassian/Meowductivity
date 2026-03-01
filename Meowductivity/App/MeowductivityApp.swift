//
//  MeowductivityApp.swift
//  Meowductivity
//
//  Created by Amirreza Ghiassian on 2026-02-28.
//

import SwiftUI
import SwiftData
import AppKit
import UserNotifications
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Global camera manager to run in the background
    let cameraManager = CameraManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // Hide the app from the Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Setup transparent dots overlay
        DotsOverlayWindowManager.shared.setup()
        
        // Request camera permissions on launch if not determined
        checkCameraPermissions()
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
        
        // Load active gestures for the background camera manager
        let schema = Schema([GestureTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            refreshActiveGestures(modelContext: container.mainContext)
        }
    }
    
    func refreshActiveGestures(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<GestureTask>()
        do {
            let gestures = try modelContext.fetch(descriptor)
            var activeDict: [String: GestureActionData] = [:]
            for gesture in gestures where gesture.isActive {
                if gesture.actionName != "None" {
                    activeDict[gesture.gestureName] = GestureActionData(actionName: gesture.actionName, appURL: gesture.appURL, keyCombo: gesture.keyCombo)
                }
            }
            cameraManager.activeGestures = activeDict
            print("Loaded \(activeDict.count) active gestures for inference.")
        } catch {
            print("Failed to fetch gestures: \(error)")
        }
    }
    
    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("Camera permission granted on launch: \(granted)")
            }
        case .denied, .restricted:
            print("Camera permission was denied or restricted.")
            // Ideally, show an alert directing the user to System Settings > Privacy & Security > Camera
        case .authorized:
            print("Camera permission already authorized.")
        @unknown default:
            break
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is active/foreground
        completionHandler([.banner, .sound])
    }
}

@main
struct MeowductivityApp: App {
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
            "Meowductivity",
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

