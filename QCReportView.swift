import SwiftUI
import Charts

public struct HistogramBin: Identifiable {
    public let id = UUID()
    public let edge: Float
    public let count: Int
}

public struct TraceCoord: Identifiable {
    public let id = UUID()
    public let x: Double
    public let y: Double
}

public struct QCReportView: View {
    public var report: QCReport
    
    @State private var selectedTab = 0
    
    public init(report: QCReport) {
        self.report = report
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("QC Report: \(report.fileName)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Generated on \(Date().formatted())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: exportPDF) {
                    Label("Export PDF", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 10) {
                    TabButton(title: "Findings", icon: "exclamationmark.triangle", isSelected: selectedTab == 0) { selectedTab = 0 }
                    TabButton(title: "Dataset Summary", icon: "doc.text.magnifyingglass", isSelected: selectedTab == 1) { selectedTab = 1 }
                    TabButton(title: "EBCDIC Header", icon: "text.alignleft", isSelected: selectedTab == 3) { selectedTab = 3 }
                    TabButton(title: "Amplitude Stats", icon: "chart.bar", isSelected: selectedTab == 2) { selectedTab = 2 }
                    Spacer()
                }
                .padding()
                .frame(width: 200)
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider()
                
                // Main Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if selectedTab == 0 {
                            FindingsView(report: report)
                        } else if selectedTab == 1 {
                            SummaryView(report: report)
                        } else if selectedTab == 2 {
                            AmplitudeStatsView(report: report)
                        } else if selectedTab == 3 {
                            TextHeaderView(report: report)
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    private func exportPDF() {
        QCExporter.promptForPDFExport(report: report)
    }
}

// MARK: - Subviews

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct TextHeaderView: View {
    let report: QCReport
    var isPrintable: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("EBCDIC/ASCII Text Header")
                .font(.headline)
            
            if isPrintable {
                Text(report.textHeader)
                    .font(.system(size: 9, design: .monospaced))
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            } else {
                ScrollView(.horizontal) {
                    Text(report.textHeader)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(8)
                }
            }
        }
    }
}

struct FindingsView: View {
    let report: QCReport
    
    var findings: [QCFinding] { report.findings }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quality Findings")
                .font(.headline)
            
            ForEach(findings) { finding in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconForSeverity(finding.severity))
                        .foregroundColor(colorForSeverity(finding.severity))
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.category)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Text(finding.message)
                            .font(.body)
                        
                        if let examples = finding.examples, !examples.isEmpty {
                            Text("Examples: " + examples.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(colorForSeverity(finding.severity).opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    func colorForSeverity(_ sev: QCSeverity) -> Color {
        switch sev {
        case .pass: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    func iconForSeverity(_ sev: QCSeverity) -> String {
        switch sev {
        case .pass: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

struct SummaryView: View {
    let report: QCReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dataset Summary")
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Text("File Information").font(.subheadline).bold()
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow(label: "File Name:", value: report.fileName)
                    summaryRow(label: "File Size:", value: formatBytes(report.fileSize))
                    summaryRow(label: "SEG-Y Revision:", value: "\(report.segyRevision)")
                    summaryRow(label: "Data Format:", value: formatDataFormat(report.dataFormat))
                }
                .padding(.leading, 10)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Survey Geometry").font(.subheadline).bold()
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow(label: "Trace Count:", value: "\(report.traceCount)")
                    summaryRow(label: "Samples per Trace:", value: "\(report.samplesPerTrace)")
                    summaryRow(label: "Sample Interval:", value: "\(report.sampleInterval) µs")
                    summaryRow(label: "Inline Range:", value: "\(report.minInline) - \(report.maxInline)")
                    summaryRow(label: "Crossline Range:", value: "\(report.minCrossline) - \(report.maxCrossline)")
                    summaryRow(label: "X Coordinates:", value: "\(String(format: "%.1f", report.minX)) - \(String(format: "%.1f", report.maxX))")
                    summaryRow(label: "Y Coordinates:", value: "\(String(format: "%.1f", report.minY)) - \(String(format: "%.1f", report.maxY))")
                }
                .padding(.leading, 10)
            }
            
            if !report.missingTraceCoordinates.isEmpty {
                let hasPhysical = (report.maxX - report.minX > 1.0) && (report.maxY - report.minY > 1.0)
                let xLabel = hasPhysical ? "Easting / X" : "Inline"
                let yLabel = hasPhysical ? "Northing / Y" : "Crossline"
                VStack(alignment: .leading, spacing: 10) {
                    Text("Missing Traces Map").font(.subheadline).bold()
                    let coords = report.missingTraceCoordinates.map { TraceCoord(x: $0.x, y: $0.y) }.filter { !($0.x == 0 && $0.y == 0) }
                    Chart(coords) { coord in
                        PointMark(
                            x: .value(xLabel, coord.x),
                            y: .value(yLabel, coord.y)
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(10)
                    }
                    .chartXScale(domain: .automatic(includesZero: false))
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxisLabel(xLabel)
                    .chartYAxisLabel(yLabel)
                    .frame(height: 300)
                    .padding()
                    .padding()
                }
            }
        }
    }
    
    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .bold()
        }
    }
    
    func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func formatDataFormat(_ code: Int) -> String {
        switch code {
        case 1: return "1 (IBM 4-byte Float)"
        case 2: return "2 (4-byte Integer)"
        case 3: return "3 (2-byte Integer)"
        case 4: return "4 (32-bit fixed point)"
        case 5: return "5 (IEEE 4-byte Float)"
        case 8: return "8 (1-byte Integer)"
        default: return "\(code) (Unknown)"
        }
    }
}

struct AmplitudeStatsView: View {
    let report: QCReport
    var isPrintable: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Amplitude Statistics")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatCard(title: "Min", value: String(format: "%.4f", report.minAmplitude))
                StatCard(title: "Max", value: String(format: "%.4f", report.maxAmplitude))
                StatCard(title: "Mean", value: String(format: "%.4f", report.meanAmplitude))
                StatCard(title: "RMS", value: String(format: "%.4f", report.rmsAmplitude))
                StatCard(title: "Std Dev", value: String(format: "%.4f", report.stdDevAmplitude))
            }
            
            if !report.histogramBins.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Amplitude Distribution (Sampled)").font(.subheadline).bold()
                    let bins = zip(report.histogramBins, report.histogramCounts).map {
                        HistogramBin(edge: $0.0, count: $0.1)
                    }
                    
                    let binWidth = report.histogramBins.count > 1 ? (report.histogramBins[1] - report.histogramBins[0]) : 1.0
                    
                    if isPrintable {
                        Chart(bins) { bin in
                            RectangleMark(
                                xStart: .value("Min", bin.edge),
                                xEnd: .value("Max", bin.edge + binWidth),
                                yStart: .value("Zero", 0),
                                yEnd: .value("Count", bin.count)
                            )
                            .foregroundStyle(Color.blue) // Gradients sometimes fail in CGContext PDF exports
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5))
                        }
                        .frame(width: 700, height: 300)
                        .drawingGroup() // Force rasterization/drawing synchronously
                        .padding()
                    } else {
                        Chart(bins) { bin in
                            RectangleMark(
                                xStart: .value("Min", bin.edge),
                                xEnd: .value("Max", bin.edge + binWidth),
                                yStart: .value("Zero", 0),
                                yEnd: .value("Count", bin.count)
                            )
                            .foregroundStyle(Color.blue.gradient)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5))
                        }
                        .frame(height: 300)
                        .padding()
                    }
                }
            }
            
            if !report.spectrumFrequencies.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Frequency Spectrum (dB)").font(.subheadline).bold()
                    let spec = zip(report.spectrumFrequencies, report.spectrumAmplitudes).map {
                        SpectrumPoint(freq: $0.0, amp: $0.1)
                    }
                    
                    if isPrintable {
                        Chart(spec) { point in
                            LineMark(
                                x: .value("Frequency", point.freq),
                                y: .value("Amplitude", point.amp)
                            )
                            .foregroundStyle(Color.purple)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 10))
                        }
                        .chartYAxisLabel("Power (dB)")
                        .chartXAxisLabel("Frequency (Hz)")
                        .frame(width: 700, height: 300)
                        .drawingGroup()
                        .padding()
                    } else {
                        Chart(spec) { point in
                            LineMark(
                                x: .value("Frequency", point.freq),
                                y: .value("Amplitude", point.amp)
                            )
                            .foregroundStyle(Color.purple.gradient)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 10))
                        }
                        .chartYAxisLabel("Power (dB)")
                        .chartXAxisLabel("Frequency (Hz)")
                        .frame(height: 300)
                        .padding()
                    }
                }
            }
        }
    }
}

public struct SpectrumPoint: Identifiable {
    public let id = UUID()
    public let freq: Float
    public let amp: Float
}

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
