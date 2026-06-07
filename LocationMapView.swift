import SwiftUI

public struct LocationMapView: View {
    @ObservedObject var model: SEGYModel
    
    // Extracted physical bounds
    @State private var minX: Double = 0
    @State private var maxX: Double = 1
    @State private var minY: Double = 0
    @State private var maxY: Double = 1
    @State private var hasPhysicalCoords: Bool = false
    @State private var isCalculated: Bool = false
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Map Overview")
                    .font(.headline)
                Spacer()
                Text("Inline: \(model.activeInline)")
                    .foregroundColor(.red)
                    .bold()
                Text(" | ")
                Text("Crossline: \(model.activeCrossline)")
                    .foregroundColor(.green)
                    .bold()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            GeometryReader { geometry in
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    
                    if isCalculated {
                        Canvas { context, size in
                            let rangeX = maxX - minX
                            let rangeY = maxY - minY
                            
                            guard rangeX > 0 && rangeY > 0 else { return }
                            
                            let padding: CGFloat = 20
                            let availableWidth = size.width - padding * 2
                            let availableHeight = size.height - padding * 2
                            
                            let scaleX = availableWidth / CGFloat(rangeX)
                            let scaleY = availableHeight / CGFloat(rangeY)
                            let scale = min(scaleX, scaleY) // Preserve 1:1 physical aspect ratio
                            
                            let drawWidth = CGFloat(rangeX) * scale
                            let drawHeight = CGFloat(rangeY) * scale
                            
                            // Center in available space
                            let offsetX = padding + (availableWidth - drawWidth) / 2
                            let offsetY = padding + (availableHeight - drawHeight) / 2
                            
                            // Map physical coordinates to canvas
                            func mapPoint(x: Double, y: Double) -> CGPoint {
                                // Invert Y axis so north is up
                                let normX = CGFloat(x - minX) / CGFloat(rangeX)
                                let normY = 1.0 - (CGFloat(y - minY) / CGFloat(rangeY))
                                
                                return CGPoint(
                                    x: offsetX + normX * drawWidth,
                                    y: offsetY + normY * drawHeight
                                )
                            }
                            
                            // Draw Inline Grid Lines
                            var inlinePath = Path()
                            for inline in model.inlines {
                                guard let traceIndices = model.inlineMap[inline], !traceIndices.isEmpty else { continue }
                                
                                var moved = false
                                for idx in traceIndices {
                                    let t = model.traceHeaders[idx]
                                    if hasPhysicalCoords && t.srcX == 0 && t.srcY == 0 { continue }
                                    
                                    let pt = mapPoint(x: getX(t), y: getY(t))
                                    if !moved {
                                        inlinePath.move(to: pt)
                                        moved = true
                                    } else {
                                        inlinePath.addLine(to: pt)
                                    }
                                }
                            }
                            context.stroke(inlinePath, with: .color(.blue), lineWidth: 0.5)
                            
                            // Draw Crossline Grid Lines
                            var crosslinePath = Path()
                            for crossline in model.crosslines {
                                guard let traceIndices = model.crosslineMap[crossline], !traceIndices.isEmpty else { continue }
                                
                                var moved = false
                                for idx in traceIndices {
                                    let t = model.traceHeaders[idx]
                                    if hasPhysicalCoords && t.srcX == 0 && t.srcY == 0 { continue }
                                    
                                    let pt = mapPoint(x: getX(t), y: getY(t))
                                    if !moved {
                                        crosslinePath.move(to: pt)
                                        moved = true
                                    } else {
                                        crosslinePath.addLine(to: pt)
                                    }
                                }
                            }
                            context.stroke(crosslinePath, with: .color(.blue), lineWidth: 0.5)
                            
                            // Draw Active Inline (Red)
                            if let traceIndices = model.inlineMap[model.activeInline], !traceIndices.isEmpty {
                                var activeIlPath = Path()
                                var moved = false
                                for idx in traceIndices {
                                    let t = model.traceHeaders[idx]
                                    if hasPhysicalCoords && t.srcX == 0 && t.srcY == 0 { continue }
                                    
                                    let pt = mapPoint(x: getX(t), y: getY(t))
                                    if !moved {
                                        activeIlPath.move(to: pt)
                                        moved = true
                                    } else {
                                        activeIlPath.addLine(to: pt)
                                    }
                                }
                                context.stroke(activeIlPath, with: .color(.red), lineWidth: 4)
                            }
                            
                            // Draw Active Crossline (Green)
                            if let traceIndices = model.crosslineMap[model.activeCrossline], !traceIndices.isEmpty {
                                var activeXlPath = Path()
                                var moved = false
                                for idx in traceIndices {
                                    let t = model.traceHeaders[idx]
                                    if hasPhysicalCoords && t.srcX == 0 && t.srcY == 0 { continue }
                                    
                                    let pt = mapPoint(x: getX(t), y: getY(t))
                                    if !moved {
                                        activeXlPath.move(to: pt)
                                        moved = true
                                    } else {
                                        activeXlPath.addLine(to: pt)
                                    }
                                }
                                context.stroke(activeXlPath, with: .color(.green), lineWidth: 4)
                            }
                            
                            // Draw Active Trace Intersection (Green Circle)
                            if let traceIndices = model.inlineMap[model.activeInline] {
                                for idx in traceIndices {
                                    let t = model.traceHeaders[idx]
                                    if t.crossline == model.activeCrossline {
                                        if hasPhysicalCoords && t.srcX == 0 && t.srcY == 0 { continue }
                                        let pt = mapPoint(x: getX(t), y: getY(t))
                                        let circleRect = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                                        context.fill(Path(ellipseIn: circleRect), with: .color(.green))
                                        context.stroke(Path(ellipseIn: circleRect), with: .color(.white), lineWidth: 1)
                                        break
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Calculating Geometry...")
                            .foregroundColor(.secondary)
                    }
                }
                .cornerRadius(8)
                .shadow(radius: 2)
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 400)
        .onAppear {
            calculateBounds()
        }
    }
    
    private func getX(_ t: TraceHeader) -> Double {
        return hasPhysicalCoords ? Double(t.srcX) : Double(t.crossline)
    }
    
    private func getY(_ t: TraceHeader) -> Double {
        return hasPhysicalCoords ? Double(t.srcY) : Double(t.inline)
    }
    
    private func calculateBounds() {
        guard !model.traceHeaders.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var tMinX: Double = .greatestFiniteMagnitude
            var tMaxX: Double = -.greatestFiniteMagnitude
            var tMinY: Double = .greatestFiniteMagnitude
            var tMaxY: Double = -.greatestFiniteMagnitude
            
            // Check if physical coordinates are present in the first few traces
            var foundPhysical = false
            for idx in 0..<min(100, model.traceHeaders.count) {
                let t = model.traceHeaders[idx]
                if t.srcX != 0 || t.srcY != 0 {
                    foundPhysical = true
                    break
                }
            }
            
            let localHasPhysical = foundPhysical
            
            for t in model.traceHeaders {
                if localHasPhysical && t.srcX == 0 && t.srcY == 0 {
                    continue // Ignore dead traces
                }
                
                let x = localHasPhysical ? Double(t.srcX) : Double(t.crossline)
                let y = localHasPhysical ? Double(t.srcY) : Double(t.inline)
                
                if x < tMinX { tMinX = x }
                if x > tMaxX { tMaxX = x }
                if y < tMinY { tMinY = y }
                if y > tMaxY { tMaxY = y }
            }
            
            // Pad identical ranges
            if tMaxX == tMinX {
                tMaxX += 1; tMinX -= 1
            }
            if tMaxY == tMinY {
                tMaxY += 1; tMinY -= 1
            }
            
            DispatchQueue.main.async {
                self.hasPhysicalCoords = localHasPhysical
                self.minX = tMinX
                self.maxX = tMaxX
                self.minY = tMinY
                self.maxY = tMaxY
                self.isCalculated = true
            }
        }
    }
}
