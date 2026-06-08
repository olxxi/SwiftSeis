import Cocoa
import SwiftUI

public class QCReportWindowController: NSObject, NSWindowDelegate {
    public static let shared = QCReportWindowController()
    
    private var window: NSWindow?
    
    public func show(with report: QCReport) {
        if let existingWindow = window {
            // Update report and bring to front
            // Since we pass a static report struct, we might need to recreate the view or use a StateObject.
            // For simplicity, we just close and recreate, or we can just bring to front if it's the same.
            existingWindow.makeKeyAndOrderFront(nil)
            
            // To update the content dynamically, we'd need an ObservableObject.
            // But since runQC generates a new report, let's just update the contentView:
            let view = QCReportView(report: report)
            existingWindow.contentView = NSHostingView(rootView: view)
            return
        }
        
        // Create new window
        let view = QCReportView(report: report)
        let hostingView = NSHostingView(rootView: view)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "QC Report: \(report.fileName)"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        
        // Set minimum size
        newWindow.minSize = NSSize(width: 800, height: 500)
        
        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Clear reference so it can be re-created later
        self.window = nil
    }
}
