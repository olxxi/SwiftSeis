import SwiftUI

public enum PlotHeaderWord: String, CaseIterable, Identifiable {
    case offset = "Source-Receiver Offset"
    case elevation = "Receiver Elevation"
    case srcX = "Source X coordinate"
    case srcY = "Source Y coordinate"
    case recX = "Receiver X coordinate"
    case recY = "Receiver Y coordinate"
    case seqLine = "Sequence Number (Line)"
    
    public var id: String { self.rawValue }
}

public struct HeaderPlotView: View {
    public var headers: [TraceHeader]
    public var activeWord: PlotHeaderWord
    @Binding public var hoveredTraceIndex: Int?
    
    public init(headers: [TraceHeader], activeWord: PlotHeaderWord, hoveredTraceIndex: Binding<Int?>) {
        self.headers = headers
        self.activeWord = activeWord
        self._hoveredTraceIndex = hoveredTraceIndex
    }
    
    // Extract numerical value from trace header based on active selection
    private func value(for header: TraceHeader) -> Double {
        switch activeWord {
        case .offset: return Double(header.offset)
        case .elevation: return Double(header.elevation)
        case .srcX: return Double(header.srcX)
        case .srcY: return Double(header.srcY)
        case .recX: return Double(header.recX)
        case .recY: return Double(header.recY)
        case .seqLine: return Double(header.seqLine)
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Trace Header QC Plot: \(activeWord.rawValue)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                if let idx = hoveredTraceIndex, idx >= 0 && idx < headers.count {
                    Text("Trace #\(idx + 1): \(Int(value(for: headers[idx])))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 8)
            
            if headers.isEmpty {
                VStack {
                    Text("No trace data to plot")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 60)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            } else {
                let values = headers.map { value(for: $0) }
                let minVal = values.min() ?? 0.0
                let maxVal = values.max() ?? 1.0
                let valRange = maxVal - minVal > 0 ? maxVal - minVal : 1.0
                
                GeometryReader { geometry in
                    let w = geometry.size.width
                    let h = geometry.size.height
                    let stepX = w / CGFloat(headers.count > 1 ? headers.count - 1 : 1)
                    
                    ZStack(alignment: .leading) {
                        // Plot Background grid line for min/max
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: w, y: 0))
                            path.move(to: CGPoint(x: 0, y: h))
                            path.addLine(to: CGPoint(x: w, y: h))
                        }
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        
                        // Labels
                        VStack(alignment: .leading) {
                            Text("\(Int(maxVal))")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(minVal))")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 4)
                        
                        // Hover Trace marker vertical line
                        if let hoverIdx = hoveredTraceIndex, hoverIdx >= 0 && hoverIdx < headers.count {
                            let hoverX = CGFloat(hoverIdx) * stepX
                            Path { path in
                                path.move(to: CGPoint(x: hoverX, y: 0))
                                path.addLine(to: CGPoint(x: hoverX, y: h))
                            }
                            .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                        }
                        
                        // The QC Plot Line
                        Path { path in
                            guard headers.count > 0 else { return }
                            
                            // Map values to screen: Y goes from h (min) to 0 (max)
                            let startY = h - CGFloat((values[0] - minVal) / valRange) * h
                            path.move(to: CGPoint(x: 0, y: startY))
                            
                            for i in 1..<headers.count {
                                let x = CGFloat(i) * stepX
                                let y = h - CGFloat((values[i] - minVal) / valRange) * h
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        .stroke(Color.blue, lineWidth: 1.5)
                    }
                }
                .frame(height: 50)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 4)
    }
}
