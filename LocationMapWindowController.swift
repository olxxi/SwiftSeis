import Cocoa
import SwiftUI

public class LocationMapWindowController: NSObject, NSWindowDelegate {
    public static let shared = LocationMapWindowController()
    
    private var window: NSWindow?
    
    public func show(with model: SEGYModel) {
        if let existingWindow = window {
            // Bring existing window to front
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // Create new window
        let view = LocationMapView(model: model)
        let hostingView = NSHostingView(rootView: view)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "3D Location Map"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        // Set minimum size
        newWindow.minSize = NSSize(width: 400, height: 400)
        
        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Clear reference so it can be re-created later
        self.window = nil
    }
}
