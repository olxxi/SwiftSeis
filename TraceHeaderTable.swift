import SwiftUI
import AppKit

public struct TraceHeaderTable: View {
    public var headers: [TraceHeader]
    @Binding public var selectedTraceIndices: Set<Int>
    
    public init(headers: [TraceHeader], selectedTraceIndices: Binding<Set<Int>>) {
        self.headers = headers
        self._selectedTraceIndices = selectedTraceIndices
    }
    
    public var body: some View {
        if headers.isEmpty {
            VStack {
                Spacer()
                Text("No trace header data loaded")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TraceHeaderNSTableRepresentable(headers: headers, selectedTraceIndices: $selectedTraceIndices)
        }
    }
}

// Subclass NSTableView to handle keyboard Cmd+C command
class CopyableTableView: NSTableView {
    var onCopy: (() -> Void)?
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            onCopy?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct TraceHeaderNSTableRepresentable: NSViewRepresentable {
    var headers: [TraceHeader]
    @Binding var selectedTraceIndices: Set<Int>
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        let tableView = CopyableTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = 20
        tableView.usesAlternatingRowBackgroundColors = true
        
        // Show solid grid lines
        tableView.gridColor = NSColor.gridColor
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        
        let columnsConfig = [
            ("Seq Line", "seqLine", 70),
            ("Seq File", "seqFile", 70),
            ("Record", "fieldRecord", 75),
            ("Trace", "fieldTrace", 70),
            ("Offset", "offset", 75),
            ("Elevation", "elevation", 75),
            ("Source (X, Y)", "srcXY", 170),
            ("Receiver (X, Y)", "recXY", 170),
            ("Inline", "inline", 70),
            ("Crossline", "crossline", 70)
        ]
        
        for (title, identifier, width) in columnsConfig {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            col.title = title
            col.width = CGFloat(width)
            col.minWidth = 50
            col.maxWidth = 400
            tableView.addTableColumn(col)
        }
        
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        
        // Copy callback for Cmd+C
        tableView.onCopy = { [weak coordinator = context.coordinator] in
            coordinator?.copySelectedRows()
        }
        
        // Add context menu
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy Selected Rows Info", action: #selector(Coordinator.copySelectedRows), keyEquivalent: "c")
        copyItem.target = context.coordinator
        menu.addItem(copyItem)
        tableView.menu = menu
        
        scrollView.documentView = tableView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        
        context.coordinator.parent = self
        
        // Check if headers count changed to decide reload
        context.coordinator.lastHeadersCount = headers.count
        
        tableView.reloadData()
        
        // Map selectedTraceIndices to NSTableView index set
        var indexSet = IndexSet()
        for id in selectedTraceIndices {
            if let index = headers.firstIndex(where: { $0.id == id }) {
                indexSet.insert(index)
            }
        }
        
        context.coordinator.isUpdatingFromBinding = true
        tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
        context.coordinator.isUpdatingFromBinding = false
        
        // Scroll to visible ONLY if selection is updated programmatically from outside
        // (i.e. table view is not the first responder / focused)
        let isFocused = tableView.window?.firstResponder == tableView
        if !isFocused, let firstSelectedRow = indexSet.first {
            tableView.scrollRowToVisible(firstSelectedRow)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func getCopyString(for headersList: [TraceHeader]) -> String {
        var result = "Seq Line\tSeq File\tRecord\tTrace\tOffset\tElevation\tSource X\tSource Y\tReceiver X\tReceiver Y\tInline\tCrossline\n"
        for header in headersList {
            result += "\(header.seqLine)\t\(header.seqFile)\t\(header.fieldRecord)\t\(header.fieldTrace)\t\(header.offset)\t\(header.elevation)\t\(header.srcX)\t\(header.srcY)\t\(header.recX)\t\(header.recY)\t\(header.inline)\t\(header.crossline)\n"
        }
        return result
    }
    
    public class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuItemValidation {
        var parent: TraceHeaderNSTableRepresentable
        var lastHeadersCount = 0
        var isUpdatingFromBinding = false
        
        init(_ parent: TraceHeaderNSTableRepresentable) {
            self.parent = parent
        }
        
        // NSTableViewDataSource methods
        public func numberOfRows(in tableView: NSTableView) -> Int {
            return parent.headers.count
        }
        
        // NSTableViewDelegate methods
        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.headers.count, let column = tableColumn else { return nil }
            let header = parent.headers[row]
            let identifier = column.identifier.rawValue
            
            let text: String
            switch identifier {
            case "seqLine": text = "\(header.seqLine)"
            case "seqFile": text = "\(header.seqFile)"
            case "fieldRecord": text = "\(header.fieldRecord)"
            case "fieldTrace": text = "\(header.fieldTrace)"
            case "offset": text = "\(header.offset)"
            case "elevation": text = "\(header.elevation)"
            case "srcXY": text = "(\(header.srcX), \(header.srcY))"
            case "recXY": text = "(\(header.recX), \(header.recY))"
            case "inline": text = "\(header.inline)"
            case "crossline": text = "\(header.crossline)"
            default: text = ""
            }
            
            let cellIdentifier = NSUserInterfaceItemIdentifier("TextCell")
            var textField = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField
            if textField == nil {
                textField = NSTextField(labelWithString: "")
                textField?.identifier = cellIdentifier
                textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                textField?.isBordered = false
                textField?.drawsBackground = false
                textField?.isEditable = false
                textField?.isSelectable = false
            }
            
            textField?.stringValue = text
            
            // Adjust cell fonts and colors based on row selection and focus state
            let isSelected = tableView.selectedRowIndexes.contains(row)
            let isFocused = tableView.window?.firstResponder == tableView
            
            if isSelected {
                textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
                if isFocused {
                    textField?.textColor = NSColor.selectedControlTextColor // white against blue focused selection
                } else {
                    textField?.textColor = NSColor.controlAccentColor // accent color against light grey unfocused selection
                }
            } else {
                textField?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                textField?.textColor = NSColor.labelColor
            }
            
            return textField
        }
        
        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView, !isUpdatingFromBinding else { return }
            
            // Force reload of visible rows so text color/font updates dynamically
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            if visibleRows.length > 0 {
                let rowRange = IndexSet(integersIn: visibleRows.lowerBound..<visibleRows.upperBound)
                let colRange = IndexSet(integersIn: 0..<tableView.numberOfColumns)
                tableView.reloadData(forRowIndexes: rowRange, columnIndexes: colRange)
            }
            
            let selectedRows = tableView.selectedRowIndexes
            var newSelection = Set<Int>()
            for row in selectedRows {
                if row < parent.headers.count {
                    newSelection.insert(parent.headers[row].id)
                }
            }
            
            DispatchQueue.main.async {
                if self.parent.selectedTraceIndices != newSelection {
                    self.parent.selectedTraceIndices = newSelection
                }
            }
        }
        
        @objc func copySelectedRows() {
            let selectedRows = parent.headers.filter { parent.selectedTraceIndices.contains($0.id) }
            guard !selectedRows.isEmpty else { return }
            
            let copyString = parent.getCopyString(for: selectedRows)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(copyString, forType: .string)
            print("SwiftSeis [Debug] Copied \(selectedRows.count) rows to clipboard.")
        }
        
        public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            if menuItem.action == #selector(copySelectedRows) {
                return !parent.selectedTraceIndices.isEmpty
            }
            return true
        }
    }
}
