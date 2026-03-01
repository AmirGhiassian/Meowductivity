import Foundation
import AppKit
import SwiftUI
import Combine

class DotsOverlayWindowManager {
    static let shared = DotsOverlayWindowManager()
    
    private var overlayWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    init() {}
    
    func setup() {
        guard overlayWindow == nil else { return }
        
        let screenRect = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        
        let window = NSWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        // Float above everything so we can see it on top of other apps
        window.level = .screenSaver
        // Pass through all clicks
        window.ignoresMouseEvents = true
        window.hasShadow = false
        // Show on all spaces/desktops
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        
        let overlayView = DotsOverlayView()
        window.contentView = NSHostingView(rootView: overlayView)
        
        window.makeKeyAndOrderFront(nil)
        self.overlayWindow = window
        
        // Listen to screen changes to resize window if resolution changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self = self, let screenRect = NSScreen.main?.frame else { return }
                self.overlayWindow?.setFrame(screenRect, display: true)
            }
            .store(in: &cancellables)
    }
}
