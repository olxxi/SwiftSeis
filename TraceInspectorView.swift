import SwiftUI

public struct TraceInspectorView: View {
    public var samples: [Float]
    public var traceIndex: Int
    public var ns: Int
    public var dt: Int
    public var isHovered: Bool
    public var onClearSelection: (() -> Void)? = nil
    
    public init(samples: [Float], traceIndex: Int, ns: Int, dt: Int, isHovered: Bool, onClearSelection: (() -> Void)? = nil) {
        self.samples = samples
        self.traceIndex = traceIndex
        self.ns = ns
        self.dt = dt
        self.isHovered = isHovered
        self.onClearSelection = onClearSelection
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("1D Trace Inspector")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !isHovered && onClearSelection != nil {
                    Spacer()
                    Button(action: { onClearSelection?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear trace selection")
                }
            }
            
            if samples.isEmpty {
                VStack {
                    Spacer()
                    Text("Hover or click a trace\nto inspect")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Trace Index: \(traceIndex)")
                        Spacer()
                        Text("Samples: \(ns)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Interval: \(Double(dt) / 1000.0) ms")
                        Spacer()
                        Text("Length: \(Double(ns * dt) / 1000.0) ms")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
                
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let midX = width / 2.0
                    
                    ZStack {
                        // Background Grid
                        Path { path in
                            // Center zero-line
                            path.move(to: CGPoint(x: midX, y: 0))
                            path.addLine(to: CGPoint(x: midX, y: height))
                            
                            // Time tick marks (every 100 samples)
                            let tickStep = max(10, ns / 10)
                            for i in stride(from: 0, to: ns, by: tickStep) {
                                let y = CGFloat(i) / CGFloat(ns) * height
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: width, y: y))
                            }
                        }
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        
                        // Time labels
                        let tickStep = max(10, ns / 10)
                        ForEach(Array(stride(from: 0, to: ns, by: tickStep)), id: \.self) { i in
                            let y = CGFloat(i) / CGFloat(ns) * height
                            let timeMs = Double(i * dt) / 1000.0
                            Text("\(Int(timeMs)) ms")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                                .position(x: 24, y: y + 4)
                        }
                        
                        // Positive Area Fill Path
                        WiggleFillShape(samples: samples, midX: midX, width: width)
                            .fill(Color.red.opacity(0.3))
                        
                        // Wiggle Line Path
                        WiggleLineShape(samples: samples, midX: midX, width: width)
                            .stroke(Color.primary, lineWidth: 1.5)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(8)
        .frame(minWidth: 180, maxWidth: 300)
    }
}

// Custom shape for drawing the wiggle trace line
struct WiggleLineShape: Shape {
    var samples: [Float]
    var midX: CGFloat
    var width: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty else { return path }
        
        let count = samples.count
        let height = rect.height
        let stepY = height / CGFloat(count)
        
        // Find max amplitude to scale values
        let maxVal = samples.map { abs($0) }.max() ?? 1.0
        let scale = (width / 2.0 - 10) / CGFloat(maxVal > 0 ? maxVal : 1.0)
        
        path.move(to: CGPoint(x: midX + CGFloat(samples[0]) * scale, y: 0))
        
        for i in 1..<count {
            let x = midX + CGFloat(samples[i]) * scale
            let y = CGFloat(i) * stepY
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

// Custom shape for filling the positive lobes
struct WiggleFillShape: Shape {
    var samples: [Float]
    var midX: CGFloat
    var width: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty else { return path }
        
        let count = samples.count
        let height = rect.height
        let stepY = height / CGFloat(count)
        
        let maxVal = samples.map { abs($0) }.max() ?? 1.0
        let scale = (width / 2.0 - 10) / CGFloat(maxVal > 0 ? maxVal : 1.0)
        
        var inPositiveLobe = false
        var lobeStartIdx = 0
        
        for i in 0..<count {
            let val = samples[i]
            
            if val > 0 {
                if !inPositiveLobe {
                    inPositiveLobe = true
                    lobeStartIdx = i
                    path.move(to: CGPoint(x: midX, y: CGFloat(i) * stepY))
                }
                let x = midX + CGFloat(val) * scale
                let y = CGFloat(i) * stepY
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                if inPositiveLobe {
                    inPositiveLobe = false
                    // Close the path to the zero line at the crossing point
                    path.addLine(to: CGPoint(x: midX, y: CGFloat(i) * stepY))
                    path.addLine(to: CGPoint(x: midX, y: CGFloat(lobeStartIdx) * stepY))
                    path.closeSubpath()
                }
            }
        }
        
        // Close trailing positive lobe if any
        if inPositiveLobe {
            path.addLine(to: CGPoint(x: midX, y: height))
            path.addLine(to: CGPoint(x: midX, y: CGFloat(lobeStartIdx) * stepY))
            path.closeSubpath()
        }
        
        return path
    }
}
