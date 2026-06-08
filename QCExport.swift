import Foundation
import SwiftUI
import AppKit

@MainActor
public class QCExporter {
    
    public static func exportToPDF(report: QCReport, destinationURL: URL) {
        // Create a printable view that avoids ScrollView and sidebars
        let exportView = QCPrintableView(report: report)
            .background(Color.white)
            .frame(width: 800) // Fixed width, flexible height
            // We use a white background explicitly in case the user's Mac is in dark mode,
            // to ensure the PDF is printable and clean.
            .environment(\.colorScheme, .light)
        
        let renderer = ImageRenderer(content: exportView)
        // Set a tall proposed size. If it's shorter, ImageRenderer might trim it or use the proposed size.
        renderer.proposedSize = .init(width: 800, height: 2500)
        
        renderer.render { size, context in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let pdfContext = CGContext(destinationURL as CFURL, mediaBox: &mediaBox, nil) else {
                print("Failed to create PDF context")
                return
            }
            
            pdfContext.beginPDFPage(nil)
            context(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }
    }
    
    public static func promptForPDFExport(report: QCReport) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "QCReport_\(report.fileName).pdf"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                exportToPDF(report: report, destinationURL: url)
            }
        }
    }
}

struct QCPrintableView: View {
    let report: QCReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("QC Report: \(report.fileName)")
                    .font(.system(size: 32, weight: .bold))
                Text("Generated on \(Date().formatted())")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // All sections sequentially
            VStack(alignment: .leading, spacing: 40) {
                FindingsView(report: report)
                Divider()
                SummaryView(report: report)
                Divider()
                TextHeaderView(report: report, isPrintable: true)
                Divider()
                AmplitudeStatsView(report: report, isPrintable: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(width: 800)
    }
}
