import Foundation

public enum QCSeverity: Int, Comparable {
    case pass = 0
    case info = 1
    case warning = 2
    case error = 3
    
    public static func < (lhs: QCSeverity, rhs: QCSeverity) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    public var stringValue: String {
        switch self {
        case .pass: return "PASS"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}

public struct QCFinding: Identifiable {
    public let id = UUID()
    public let category: String
    public let severity: QCSeverity
    public let message: String
    public let examples: [String]?
    
    public init(category: String, severity: QCSeverity, message: String, examples: [String]? = nil) {
        self.category = category
        self.severity = severity
        self.message = message
        self.examples = examples
    }
}

public struct QCReport {
    // Summary
    public var fileName: String = ""
    public var fileSize: Int = 0
    public var segyRevision: Int = 0
    public var dataFormat: Int = 0
    public var textHeader: String = ""
    
    // Geometry
    public var traceCount: Int = 0
    public var samplesPerTrace: Int = 0
    public var sampleInterval: Int = 0 // in microseconds
    public var minInline: Int = 0
    public var maxInline: Int = 0
    public var minCrossline: Int = 0
    public var maxCrossline: Int = 0
    public var minX: Double = .greatestFiniteMagnitude
    public var maxX: Double = -.greatestFiniteMagnitude
    public var minY: Double = .greatestFiniteMagnitude
    public var maxY: Double = -.greatestFiniteMagnitude
    
    // Stats
    public var minAmplitude: Float = .greatestFiniteMagnitude
    public var maxAmplitude: Float = -.greatestFiniteMagnitude
    public var meanAmplitude: Float = 0.0
    public var rmsAmplitude: Float = 0.0
    public var stdDevAmplitude: Float = 0.0
    
    // Trace Issues
    public var deadTracesCount: Int = 0
    public var duplicateTracesCount: Int = 0
    public var missingTracesCount: Int = 0
    public var zeroCoordinateTracesCount: Int = 0
    
    public var deadTraceCoordinates: [SIMD2<Double>] = []
    public var missingTraceCoordinates: [SIMD2<Double>] = []
    
    // Histogram data (100 bins)
    public var histogramBins: [Float] = []
    public var histogramCounts: [Int] = []
    
    // Frequency Spectrum data
    public var spectrumFrequencies: [Float] = []
    public var spectrumAmplitudes: [Float] = []
    
    // Findings
    public var findings: [QCFinding] = []
    
    public init() {}
}
