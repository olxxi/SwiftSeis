import Foundation
import Accelerate

public class QCAnalyzer {
    
    public static func runQC(model: SEGYModel, progressCallback: @escaping (Double) -> Void) async -> QCReport {
        var report = QCReport()
        report.textHeader = model.textHeader
        report.fileName = model.fileName ?? "Unknown"
        report.fileSize = model.fileSize
        report.segyRevision = model.format == .ibmFloat ? 0 : 1
        report.dataFormat = model.format.rawValue
        
        report.traceCount = model.numTraces
        report.samplesPerTrace = model.ns
        report.sampleInterval = model.dt
        report.minInline = model.minInline
        report.maxInline = model.maxInline
        report.minCrossline = model.minCrossline
        report.maxCrossline = model.maxCrossline
        
        var minX: Double = .greatestFiniteMagnitude
        var maxX: Double = -.greatestFiniteMagnitude
        var minY: Double = .greatestFiniteMagnitude
        var maxY: Double = -.greatestFiniteMagnitude
        
        var deadTracesCount = 0
        var zeroCoordsCount = 0
        
        var minAmp: Float = .greatestFiniteMagnitude
        var maxAmp: Float = -.greatestFiniteMagnitude
        var sumAmp: Double = 0.0
        var sumSqAmp: Double = 0.0
        var totalSamples: Int = 0
        
        // Phase 1: Headers Geometry & Duplicates
        // Trace length/sample rate sanity check
        if let firstTrace = model.traceHeaders.first {
            if firstTrace.ns != 0 && Int(firstTrace.ns) != model.ns {
                report.findings.append(QCFinding(category: "Consistency", severity: .error, message: "Sample count mismatch: Binary header declares \(model.ns), but trace 1 declares \(firstTrace.ns)."))
            }
            if firstTrace.dt != 0 && Int(firstTrace.dt) != model.dt {
                report.findings.append(QCFinding(category: "Consistency", severity: .error, message: "Sample interval mismatch: Binary header declares \(model.dt) µs, but trace 1 declares \(firstTrace.dt) µs."))
            }
        }
        
        var grid = Set<String>()
        var duplicateCount = 0
        
        var expectedGridCount = (model.maxInline - model.minInline + 1) * (model.maxCrossline - model.minCrossline + 1)
        if expectedGridCount < 0 { expectedGridCount = 0 }
        
        for trace in model.traceHeaders {
            let x = Double(trace.srcX)
            let y = Double(trace.srcY)
            if x != 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            if y != 0 {
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
            if x == 0 && y == 0 {
                zeroCoordsCount += 1
            }
            
            let gridKey = "\(trace.inline)_\(trace.crossline)"
            if grid.contains(gridKey) {
                duplicateCount += 1
            } else {
                grid.insert(gridKey)
            }
        }
        
        report.minX = minX == .greatestFiniteMagnitude ? 0 : minX
        report.maxX = maxX == -.greatestFiniteMagnitude ? 0 : maxX
        report.minY = minY == .greatestFiniteMagnitude ? 0 : minY
        report.maxY = maxY == -.greatestFiniteMagnitude ? 0 : maxY
        report.zeroCoordinateTracesCount = zeroCoordsCount
        report.duplicateTracesCount = duplicateCount
        
        let is3D = model.inlines.count > 0 && model.crosslines.count > 0
        let hasPhysicalCoords = (maxX - minX > 1.0) && (maxY - minY > 1.0)
        
        // Estimate affine transform for interpolating missing traces
        var A = 0.0, B = 0.0, D = 0.0, E = 0.0
        var originIL = 0.0, originXL = 0.0, originX = 0.0, originY = 0.0
        var validAffine = false
        
        if is3D && hasPhysicalCoords {
            // Find 3 non-collinear valid traces
            let validTraces = model.traceHeaders.filter { $0.srcX != 0 || $0.srcY != 0 }
            if validTraces.count >= 3 {
                let t0 = validTraces[0]
                var t1: TraceHeader? = nil
                var t2: TraceHeader? = nil
                
                for i in 1..<validTraces.count {
                    if validTraces[i].inline != t0.inline || validTraces[i].crossline != t0.crossline {
                        if t1 == nil {
                            t1 = validTraces[i]
                        } else {
                            // Check determinant for collinearity
                            let dil1 = Double(t1!.inline - t0.inline)
                            let dxl1 = Double(t1!.crossline - t0.crossline)
                            let dil2 = Double(validTraces[i].inline - t0.inline)
                            let dxl2 = Double(validTraces[i].crossline - t0.crossline)
                            
                            let det = dil1 * dxl2 - dxl1 * dil2
                            if abs(det) > 0.001 {
                                t2 = validTraces[i]
                                
                                // Solve linear system
                                let dX1 = Double(t1!.srcX - t0.srcX)
                                let dY1 = Double(t1!.srcY - t0.srcY)
                                let dX2 = Double(t2!.srcX - t0.srcX)
                                let dY2 = Double(t2!.srcY - t0.srcY)
                                
                                A = (dX1 * dxl2 - dX2 * dxl1) / det
                                B = (dil1 * dX2 - dil2 * dX1) / det
                                D = (dY1 * dxl2 - dY2 * dxl1) / det
                                E = (dil1 * dY2 - dil2 * dY1) / det
                                
                                originIL = Double(t0.inline)
                                originXL = Double(t0.crossline)
                                originX = Double(t0.srcX)
                                originY = Double(t0.srcY)
                                validAffine = true
                                break
                            }
                        }
                    }
                }
            }
        }
        
        if is3D {
            var missingCoords = [SIMD2<Double>]()
            for il in model.minInline...model.maxInline {
                for xl in model.minCrossline...model.maxCrossline {
                    if !grid.contains("\(il)_\(xl)") {
                        if missingCoords.count < 10000 { // limit for UI performance
                            var cx = Double(il)
                            var cy = Double(xl)
                            if validAffine {
                                let dil = Double(il) - originIL
                                let dxl = Double(xl) - originXL
                                cx = originX + A * dil + B * dxl
                                cy = originY + D * dil + E * dxl
                            }
                            missingCoords.append(SIMD2<Double>(cx, cy))
                        }
                    }
                }
            }
            report.missingTraceCoordinates = missingCoords
            let missing = expectedGridCount - grid.count
            report.missingTracesCount = max(0, missing)
        } else {
            report.missingTracesCount = 0
        }
        
        // Generate Findings from Phase 1
        if duplicateCount > 0 {
            report.findings.append(QCFinding(category: "Geometry", severity: .warning, message: "\(duplicateCount) duplicate traces detected based on Inline/Crossline keys."))
        }
        if report.missingTracesCount > 0 {
            let pct = (Double(report.missingTracesCount) / Double(expectedGridCount)) * 100.0
            let sev: QCSeverity = pct > 10.0 ? .error : .warning
            report.findings.append(QCFinding(category: "Geometry", severity: sev, message: "\(report.missingTracesCount) traces missing from expected survey grid (\(String(format: "%.2f", pct))%)."))
        }
        if zeroCoordsCount > 0 {
            report.findings.append(QCFinding(category: "Coordinates", severity: .warning, message: "\(zeroCoordsCount) traces contain zero for X/Y coordinates."))
        }
        
        // Phase 2: Samples & Amplitudes
        let numTraces = model.numTraces
        var deadTraceExamples = [String]()
        
        for i in 0..<numTraces {
            if i % 500 == 0 {
                let pct = Double(i) / Double(numTraces)
                await MainActor.run { progressCallback(pct) }
            }
            
            let samples = model.readTraceSamples(traceIndex: i)
            var traceMin: Float = .greatestFiniteMagnitude
            var traceMax: Float = -.greatestFiniteMagnitude
            
            for s in samples {
                if s < minAmp { minAmp = s }
                if s > maxAmp { maxAmp = s }
                if s < traceMin { traceMin = s }
                if s > traceMax { traceMax = s }
                
                sumAmp += Double(s)
                sumSqAmp += Double(s) * Double(s)
            }
            totalSamples += samples.count
            
            if traceMin == 0.0 && traceMax == 0.0 && samples.count > 0 {
                deadTracesCount += 1
                let hdr = model.traceHeaders[i]
                if report.deadTraceCoordinates.count < 10000 {
                    let cx = hasPhysicalCoords ? Double(hdr.srcX) : Double(hdr.inline)
                    let cy = hasPhysicalCoords ? Double(hdr.srcY) : Double(hdr.crossline)
                    report.deadTraceCoordinates.append(SIMD2<Double>(cx, cy))
                }
                if deadTraceExamples.count < 5 {
                    deadTraceExamples.append("IL \(hdr.inline) XL \(hdr.crossline)")
                }
            }
        }
        
        report.deadTracesCount = deadTracesCount
        report.minAmplitude = minAmp == .greatestFiniteMagnitude ? 0 : minAmp
        report.maxAmplitude = maxAmp == -.greatestFiniteMagnitude ? 0 : maxAmp
        
        if totalSamples > 0 {
            report.meanAmplitude = Float(sumAmp / Double(totalSamples))
            let meanSq = sumSqAmp / Double(totalSamples)
            report.rmsAmplitude = Float(sqrt(meanSq))
            
            let variance = meanSq - (Double(report.meanAmplitude) * Double(report.meanAmplitude))
            report.stdDevAmplitude = Float(sqrt(max(0, variance)))
        }
        
        if deadTracesCount > 0 {
            let pct = (Double(deadTracesCount) / Double(numTraces)) * 100.0
            let sev: QCSeverity = pct > 5.0 ? .error : .warning
            report.findings.append(QCFinding(category: "Signal Quality", severity: sev, message: "\(deadTracesCount) dead traces detected (\(String(format: "%.2f", pct))%).", examples: deadTraceExamples))
        }
        
        // Pass 3: Histogram & Frequency Spectrum
        let histTraces = min(1000, numTraces)
        let step = max(1, numTraces / histTraces)
        let binCount = 50
        var bins = [Int](repeating: 0, count: binCount)
        var binEdges = [Float]()
        
        let range = report.maxAmplitude - report.minAmplitude
        if range > 0 {
            for i in 0..<binCount {
                binEdges.append(report.minAmplitude + Float(i) * (range / Float(binCount)))
            }
        }
        
        // Setup FFT
        let n = model.ns
        var spectrumFrequencies = [Float]()
        var spectrumAmplitudes = [Float]()
        var sumSpectrum = [Float]()
        var fftSetup: FFTSetup? = nil
        var log2n: vDSP_Length = 0
        var fftN: Int = 0
        
        if n > 1 {
            log2n = vDSP_Length(log2(Float(n)).rounded(.up))
            fftN = Int(1 << log2n)
            fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
            sumSpectrum = [Float](repeating: 0, count: fftN / 2)
        }
        var processedTracesForFFT = 0
        
        for i in stride(from: 0, to: numTraces, by: step) {
            var samples = model.readTraceSamples(traceIndex: i)
            
            // Histogram
            if range > 0 {
                for s in samples {
                    let normalized = (s - report.minAmplitude) / range
                    var binIdx = Int(normalized * Float(binCount))
                    if binIdx >= binCount { binIdx = binCount - 1 }
                    if binIdx < 0 { binIdx = 0 }
                    bins[binIdx] += 1
                }
            }
            
            // FFT
            if let setup = fftSetup, samples.count > 0 {
                if samples.count < fftN {
                    samples.append(contentsOf: [Float](repeating: 0, count: fftN - samples.count))
                }
                
                var realp = [Float](repeating: 0, count: fftN / 2)
                var imagp = [Float](repeating: 0, count: fftN / 2)
                
                realp.withUnsafeMutableBufferPointer { realPtr in
                    imagp.withUnsafeMutableBufferPointer { imagPtr in
                        var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                        
                        samples.withUnsafeBytes { ptr in
                            let f32Ptr = ptr.bindMemory(to: Float.self).baseAddress!
                            vDSP_ctoz(UnsafePointer<DSPComplex>(OpaquePointer(f32Ptr)), 2, &splitComplex, 1, vDSP_Length(fftN / 2))
                        }
                        
                        vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                        
                        var magnitudes = [Float](repeating: 0, count: fftN / 2)
                        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftN / 2))
                        
                        for j in 0..<(fftN / 2) {
                            sumSpectrum[j] += magnitudes[j]
                        }
                    }
                }
                processedTracesForFFT += 1
            }
        }
        
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
            let dtSeconds = Double(model.dt) / 1_000_000.0
            let nyquist = dtSeconds > 0 ? (1.0 / (2.0 * dtSeconds)) : 125.0
            
            for j in 0..<(fftN / 2) {
                let freq = Float(nyquist) * Float(j) / Float(fftN / 2)
                spectrumFrequencies.append(freq)
                
                let avgMag = sumSpectrum[j] / Float(processedTracesForFFT)
                let db = 10.0 * log10(avgMag + 1e-10)
                spectrumAmplitudes.append(Float(db))
            }
        }
        
        report.histogramBins = binEdges
        report.histogramCounts = bins
        report.spectrumFrequencies = spectrumFrequencies
        report.spectrumAmplitudes = spectrumAmplitudes
        
        // Sort findings by severity (ERROR first)
        report.findings.sort { $0.severity.rawValue > $1.severity.rawValue }
        
        if report.findings.isEmpty {
            report.findings.append(QCFinding(category: "Summary", severity: .pass, message: "No significant issues detected in geometry or signal quality."))
        }
        
        await MainActor.run { progressCallback(1.0) }
        return report
    }
}
