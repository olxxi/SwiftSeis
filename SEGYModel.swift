import Foundation
import Combine

public enum SEGYFormat: Int, Sendable {
    case ibmFloat = 1
    case int32 = 2
    case int16 = 3
    case fixedPoint = 4
    case ieeeFloat = 5
    case int8 = 8
    case uint8 = 9
    
    public var sampleSize: Int {
        switch self {
        case .ibmFloat, .int32, .fixedPoint, .ieeeFloat:
            return 4
        case .int16:
            return 2
        case .int8, .uint8:
            return 1
        }
    }
    
    public var description: String {
        switch self {
        case .ibmFloat: return "4-byte IBM Float"
        case .int32: return "4-byte Two's Complement Int"
        case .int16: return "2-byte Two's Complement Int"
        case .fixedPoint: return "4-byte Fixed Point"
        case .ieeeFloat: return "4-byte IEEE Float"
        case .int8: return "1-byte Two's Complement Int"
        case .uint8: return "1-byte Unsigned Int"
        }
    }
}

public struct TraceHeader: Identifiable, Hashable {
    public var id: Int // Trace index (0-based)
    public var seqLine: Int32
    public var seqFile: Int32
    public var fieldRecord: Int32
    public var fieldTrace: Int32
    public var offset: Int32
    public var elevation: Int32
    public var srcX: Int32
    public var srcY: Int32
    public var recX: Int32
    public var recY: Int32
    public var inline: Int32
    public var crossline: Int32
}

public class SEGYModel: ObservableObject {
    @Published public var filePath: String? = nil
    @Published public var fileName: String? = nil
    @Published public var fileSize: Int = 0
    
    @Published public var textHeader: String = ""
    @Published public var binaryHeader: [String: String] = [:]
    
    @Published public var isBigEndian: Bool = true
    @Published public var isEbcdic: Bool = true
    @Published public var ns: Int = 0
    @Published public var dt: Int = 0
    @Published public var format: SEGYFormat = .ibmFloat
    
    @Published public var numTraces: Int = 0
    @Published public var traceHeaders: [TraceHeader] = []
    @Published public var inlines: [Int] = []
    @Published public var crosslines: [Int] = []
    
    @Published public var minInline: Int = 0
    @Published public var maxInline: Int = 0
    @Published public var minCrossline: Int = 0
    @Published public var maxCrossline: Int = 0
    
    @Published public var activeInline: Int = 1
    @Published public var activeCrossline: Int = 1
    
    @Published public var inlineByteOffset: Int = 188 // 0-based offset (Byte 189)
    @Published public var crosslineByteOffset: Int = 192 // 0-based offset (Byte 193)
    
    // Navigation index mappings
    public var inlineMap: [Int: [Int]] = [:] // inline -> trace indices
    public var crosslineMap: [Int: [Int]] = [:] // crossline -> trace indices
    public var gridMap: [Int64: Int] = [:] // (inline << 32 | crossline) -> trace index
    
    // Memory mapping variables
    private var fd: Int32 = -1
    private var mappedPointer: UnsafeMutableRawPointer? = nil
    private var firstTraceOffset: Int = 3600
    private var traceSize: Int = 0
    
    // EBCDIC to ASCII conversion table (CP037)
    private static let ebcdicToAsciiTable: [UInt8] = [
        0x00, 0x01, 0x02, 0x03, 0x1A, 0x09, 0x1A, 0x7F, 0x1A, 0x1A, 0x1A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        0x10, 0x11, 0x12, 0x13, 0x1A, 0x1A, 0x08, 0x1A, 0x18, 0x19, 0x1A, 0x1A, 0x1C, 0x1D, 0x1E, 0x1F,
        0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x0A, 0x17, 0x1B, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x05, 0x06, 0x07,
        0x1A, 0x1A, 0x16, 0x1A, 0x1A, 0x1A, 0x1A, 0x04, 0x1A, 0x1A, 0x1A, 0x1A, 0x14, 0x15, 0x1A, 0x1A,
        0x20, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x5B, 0x2E, 0x3C, 0x28, 0x2B, 0x21,
        0x50, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x5D, 0x24, 0x2A, 0x29, 0x3B, 0x5E,
        0x2D, 0x2F, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x7C, 0x2C, 0x25, 0x5F, 0x3E, 0x3F,
        0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x60, 0x3A, 0x23, 0x40, 0x27, 0x3D, 0x22,
        0x1A, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A,
        0x1A, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x71, 0x72, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A,
        0x1A, 0x7E, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A,
        0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A,
        0x7B, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A,
        0x7D, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A,
        0x5C, 0x1A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A,
        0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A, 0x1A
    ]
    
    public init() {}
    
    deinit {
        closeFile()
    }
    
    public func closeFile() {
        if let mapped = mappedPointer, fileSize > 0 {
            munmap(mapped, fileSize)
        }
        if fd >= 0 {
            close(fd)
        }
        fd = -1
        mappedPointer = nil
        fileSize = 0
        filePath = nil
        fileName = nil
        traceHeaders = []
        inlineMap = [:]
        crosslineMap = [:]
        gridMap = [:]
        inlineByteOffset = 188
        crosslineByteOffset = 192
    }
    
    public func openSEGY(at path: String) throws {
        closeFile()
        
        fd = open(path, O_RDONLY)
        guard fd >= 0 else {
            throw NSError(domain: "SwiftSeis", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open file at path: \(path)"])
        }
        
        let size = lseek(fd, 0, SEEK_END)
        guard size > 3600 else {
            close(fd)
            fd = -1
            throw NSError(domain: "SwiftSeis", code: 2, userInfo: [NSLocalizedDescriptionKey: "File is too small to be a valid SEGY file (must be > 3600 bytes)"])
        }
        self.fileSize = Int(size)
        lseek(fd, 0, SEEK_SET)
        
        mappedPointer = mmap(nil, fileSize, PROT_READ, MAP_PRIVATE, fd, 0)
        guard mappedPointer != MAP_FAILED else {
            close(fd)
            fd = -1
            throw NSError(domain: "SwiftSeis", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to memory map file"])
        }
        
        self.filePath = path
        self.fileName = URL(fileURLWithPath: path).lastPathComponent
        
        // 1. Textual Header parsing
        parseTextHeader()
        
        // 2. Binary Header parsing & Endianness detection
        detectEndiannessAndFormat()
        
        // 3. Compute Traces
        let formatCode = Int(binaryHeader["Format Code"] ?? "1") ?? 1
        self.format = SEGYFormat(rawValue: formatCode) ?? .ibmFloat
        self.ns = Int(binaryHeader["Samples per Trace"] ?? "0") ?? 0
        self.dt = Int(binaryHeader["Sample Interval (µs)"] ?? "0") ?? 0
        
        guard ns > 0 else {
            throw NSError(domain: "SwiftSeis", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid sample count (ns) in binary header"])
        }
        
        let extHeaderCount = Int(binaryHeader["Extended Textual Headers"] ?? "0") ?? 0
        self.firstTraceOffset = 3600 + extHeaderCount * 3200
        self.traceSize = 240 + ns * format.sampleSize
        
        guard traceSize > 240 else {
            throw NSError(domain: "SwiftSeis", code: 5, userInfo: [NSLocalizedDescriptionKey: "Trace size calculation error"])
        }
        
        self.numTraces = (fileSize - firstTraceOffset) / traceSize
        
        // 4. Auto-detect coordinate offsets
        autoDetectCoordinateOffsets()
    }
    
    private func parseTextHeader() {
        guard let ptr = mappedPointer else { return }
        
        // Copy first 3200 bytes
        var buffer = [UInt8](repeating: 0, count: 3200)
        memcpy(&buffer, ptr, 3200)
        
        // Detect ASCII vs EBCDIC
        // Standard EBCDIC space is 0x40. ASCII space is 0x20.
        let space40 = buffer.filter { $0 == 0x40 }.count
        let space20 = buffer.filter { $0 == 0x20 }.count
        
        self.isEbcdic = space40 > space20
        
        var converted = ""
        if isEbcdic {
            let convertedBytes = buffer.map { SEGYModel.ebcdicToAsciiTable[Int($0)] }
            converted = String(bytes: convertedBytes, encoding: .ascii) ?? "Decoding failed"
        } else {
            converted = String(bytes: buffer, encoding: .ascii) ?? String(bytes: buffer, encoding: .utf8) ?? "Decoding failed"
        }
        
        // Format to 80 characters per line
        var formatted = ""
        for i in 0..<40 {
            let start = i * 80
            let end = min(start + 80, converted.count)
            if start < converted.count {
                let indexStart = converted.index(converted.startIndex, offsetBy: start)
                let indexEnd = converted.index(converted.startIndex, offsetBy: end)
                formatted += String(converted[indexStart..<indexEnd]) + "\n"
            }
        }
        self.textHeader = formatted
    }
    
    private func detectEndiannessAndFormat() {
        // Read format code from binary header (bytes 3225-3226, i.e., offset 24 in binary header starting at 3200)
        let codeBE = readUInt16(at: 3224, bigEndian: true)
        let codeLE = readUInt16(at: 3224, bigEndian: false)
        
        if codeBE >= 1 && codeBE <= 12 {
            self.isBigEndian = true
        } else if codeLE >= 1 && codeLE <= 12 {
            self.isBigEndian = false
        } else {
            // Check sample interval dt (bytes 3217-3218, offset 16)
            let dtBE = readUInt16(at: 3216, bigEndian: true)
            let dtLE = readUInt16(at: 3216, bigEndian: false)
            if dtBE > 0 && dtBE < 50000 {
                self.isBigEndian = true
            } else if dtLE > 0 && dtLE < 50000 {
                self.isBigEndian = false
            } else {
                self.isBigEndian = true // default
            }
        }
        
        // Read all binary header values
        let job = readUInt32(at: 3200, bigEndian: isBigEndian)
        let line = readUInt32(at: 3204, bigEndian: isBigEndian)
        let tracesPerRec = readUInt16(at: 3212, bigEndian: isBigEndian)
        let dtVal = readUInt16(at: 3216, bigEndian: isBigEndian)
        let nsVal = readUInt16(at: 3220, bigEndian: isBigEndian)
        let formatVal = readUInt16(at: 3224, bigEndian: isBigEndian)
        let extHeaderVal = readUInt16(at: 3504, bigEndian: isBigEndian)
        
        self.binaryHeader = [
            "Job ID": "\(job)",
            "Line Number": "\(line)",
            "Traces per Record": "\(tracesPerRec)",
            "Sample Interval (µs)": "\(dtVal)",
            "Samples per Trace": "\(nsVal)",
            "Format Code": "\(formatVal)",
            "Extended Textual Headers": "\(extHeaderVal)"
        ]
    }
    
    public func scanTraceHeaders(progress: ((Double) -> Void)? = nil, completion: (() -> Void)? = nil) {
        guard numTraces > 0 else {
            completion?()
            return
        }
        
        let localNumTraces = numTraces
        let localFirstTraceOffset = firstTraceOffset
        let localTraceSize = traceSize
        let localIsBigEndian = isBigEndian
        let localInlineByteOffset = inlineByteOffset
        let localCrosslineByteOffset = crosslineByteOffset
        let localMappedPointer = SendablePointer(pointer: mappedPointer)
        let localFileSize = fileSize
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var tempHeaders = [TraceHeader]()
            tempHeaders.reserveCapacity(localNumTraces)
            
            var inlines = Set<Int>()
            var crosslines = Set<Int>()
            
            var inlineMap = [Int: [Int]]()
            var crosslineMap = [Int: [Int]]()
            var gridMap = [Int64: Int]()
            
            let progressInterval = max(1, localNumTraces / 100)
            
            func readInt32Background(at off: Int) -> Int32 {
                guard let ptr = localMappedPointer.pointer, off + 4 <= localFileSize else { return 0 }
                var val: Int32 = 0
                memcpy(&val, ptr.advanced(by: off), 4)
                return localIsBigEndian ? Int32(bigEndian: val) : Int32(littleEndian: val)
            }
            
            for i in 0..<localNumTraces {
                let offset = localFirstTraceOffset + i * localTraceSize
                
                let seqLine = readInt32Background(at: offset + 0)
                let seqFile = readInt32Background(at: offset + 4)
                let fieldRecord = readInt32Background(at: offset + 8)
                let fieldTrace = readInt32Background(at: offset + 12)
                let trOffset = readInt32Background(at: offset + 36)
                let elev = readInt32Background(at: offset + 40)
                let srcX = readInt32Background(at: offset + 72)
                let srcY = readInt32Background(at: offset + 76)
                let recX = readInt32Background(at: offset + 80)
                let recY = readInt32Background(at: offset + 84)
                
                let inline = readInt32Background(at: offset + localInlineByteOffset)
                let crossline = readInt32Background(at: offset + localCrosslineByteOffset)
                
                let header = TraceHeader(
                    id: i,
                    seqLine: seqLine,
                    seqFile: seqFile,
                    fieldRecord: fieldRecord,
                    fieldTrace: fieldTrace,
                    offset: trOffset,
                    elevation: elev,
                    srcX: srcX,
                    srcY: srcY,
                    recX: recX,
                    recY: recY,
                    inline: inline,
                    crossline: crossline
                )
                tempHeaders.append(header)
                
                let il = Int(inline)
                let xl = Int(crossline)
                
                inlines.insert(il)
                crosslines.insert(xl)
                
                inlineMap[il, default: []].append(i)
                crosslineMap[xl, default: []].append(i)
                
                let key = (Int64(il) << 32) | Int64(xl)
                gridMap[key] = i
                
                if progress != nil && (i % progressInterval == 0 || i == localNumTraces - 1) {
                    let pct = Double(i + 1) / Double(localNumTraces)
                    DispatchQueue.main.async {
                        progress?(pct)
                    }
                }
            }
            
            let sortedInlines = inlines.sorted()
            let sortedCrosslines = crosslines.sorted()
            let minIl = inlines.min() ?? 0
            let maxIl = inlines.max() ?? 0
            let minXl = crosslines.min() ?? 0
            let maxXl = crosslines.max() ?? 0
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.traceHeaders = tempHeaders
                self.minInline = minIl
                self.maxInline = maxIl
                self.minCrossline = minXl
                self.maxCrossline = maxXl
                self.inlines = sortedInlines
                self.crosslines = sortedCrosslines
                self.inlineMap = inlineMap
                self.crosslineMap = crosslineMap
                self.gridMap = gridMap
                completion?()
            }
        }
    }
    
    private func autoDetectCoordinateOffsets() {
        guard numTraces > 0 else { return }
        
        let candidates = [
            (188, 192), // Byte 189, 193 (Standard)
            (180, 184), // Byte 181, 185 (Landmark/Petrel)
            (8, 20),    // Byte 9, 21 (EGL/Matlab/Land)
            (16, 12)    // Byte 17, 13 (Alt)
        ]
        
        let sampleCount = min(500, numTraces)
        let step = max(1, numTraces / sampleCount)
        
        var bestIlOffset = 188
        var bestXlOffset = 192
        var bestScore = -1.0
        
        for (ilOff, xlOff) in candidates {
            var uniqueIl = Set<Int32>()
            var uniqueXl = Set<Int32>()
            
            for i in 0..<sampleCount {
                let idx = i * step
                guard idx < numTraces else { break }
                let offset = firstTraceOffset + idx * traceSize
                
                let il = readInt32(at: offset + ilOff, bigEndian: isBigEndian)
                let xl = readInt32(at: offset + xlOff, bigEndian: isBigEndian)
                
                uniqueIl.insert(il)
                uniqueXl.insert(xl)
            }
            
            let uIl = uniqueIl.count
            let uXl = uniqueXl.count
            
            if uniqueIl.contains(0) && uniqueXl.contains(0) && uIl == 1 && uXl == 1 {
                continue
            }
            
            var score = 0.0
            if uIl > 1 { score += 10.0 }
            if uXl > 1 { score += 10.0 }
            
            if uIl > 1 && uXl > 1 {
                let gridRatio = Double(uIl * uXl) / Double(sampleCount)
                if gridRatio >= 0.1 && gridRatio <= 10.0 {
                    score += 50.0
                }
            }
            
            let maxValIl = uniqueIl.map({ abs($0) }).max() ?? 0
            let maxValXl = uniqueXl.map({ abs($0) }).max() ?? 0
            
            if maxValIl < 100000 && maxValXl < 100000 {
                score += 30.0
            }
            
            if score > bestScore {
                bestScore = score
                bestIlOffset = ilOff
                bestXlOffset = xlOff
            }
        }
        
        self.inlineByteOffset = bestIlOffset
        self.crosslineByteOffset = bestXlOffset
        print("SwiftSeis [Debug] Auto-detected Coordinate Offsets: Inline=\(bestIlOffset+1), Crossline=\(bestXlOffset+1)")
    }
    
    // Safely reads raw bytes using memcpy to prevent unaligned accesses
    private func readUInt32(at offset: Int, bigEndian: Bool) -> UInt32 {
        guard let ptr = mappedPointer, offset + 4 <= fileSize else { return 0 }
        var val: UInt32 = 0
        memcpy(&val, ptr.advanced(by: offset), 4)
        return bigEndian ? UInt32(bigEndian: val) : UInt32(littleEndian: val)
    }
    
    private func readInt32(at offset: Int, bigEndian: Bool) -> Int32 {
        guard let ptr = mappedPointer, offset + 4 <= fileSize else { return 0 }
        var val: Int32 = 0
        memcpy(&val, ptr.advanced(by: offset), 4)
        return bigEndian ? Int32(bigEndian: val) : Int32(littleEndian: val)
    }
    
    private func readUInt16(at offset: Int, bigEndian: Bool) -> UInt16 {
        guard let ptr = mappedPointer, offset + 2 <= fileSize else { return 0 }
        var val: UInt16 = 0
        memcpy(&val, ptr.advanced(by: offset), 2)
        return bigEndian ? UInt16(bigEndian: val) : UInt16(littleEndian: val)
    }
    
    private func readInt16(at offset: Int, bigEndian: Bool) -> Int16 {
        guard let ptr = mappedPointer, offset + 2 <= fileSize else { return 0 }
        var val: Int16 = 0
        memcpy(&val, ptr.advanced(by: offset), 2)
        return bigEndian ? Int16(bigEndian: val) : Int16(littleEndian: val)
    }
    
    private func readUInt8(at offset: Int) -> UInt8 {
        guard let ptr = mappedPointer, offset < fileSize else { return 0 }
        return ptr.load(fromByteOffset: offset, as: UInt8.self)
    }
    
    private func readInt8(at offset: Int) -> Int8 {
        guard let ptr = mappedPointer, offset < fileSize else { return 0 }
        return ptr.load(fromByteOffset: offset, as: Int8.self)
    }
    
    // Decodes IBM Floating Point to IEEE 754 float
    private func ibmToIeee(_ ibm: UInt32) -> Float {
        return SEGYModel.ibmToIeeeStatic(ibm)
    }
    
    private static func ibmToIeeeStatic(_ ibm: UInt32) -> Float {
        if ibm == 0 { return 0.0 }
        
        let sign = ibm & 0x80000000
        let exp = Int32((ibm >> 24) & 0x7F) - 64
        var fraction = ibm & 0x00FFFFFF
        
        if fraction == 0 { return 0.0 }
        
        var shift = 0
        while (fraction & 0x00800000) == 0 {
            fraction <<= 1
            shift += 1
        }
        
        let ieeeExp = 4 * exp - Int32(shift) + 126
        if ieeeExp <= 0 {
            return 0.0 // Underflow
        } else if ieeeExp >= 255 {
            return Float(bitPattern: sign | 0x7F800000) // Overflow
        }
        
        let ieeeFraction = fraction & 0x007FFFFF
        let ieeeBits = sign | (UInt32(ieeeExp) << 23) | ieeeFraction
        return Float(bitPattern: ieeeBits)
    }
    
    // Reads a single sample value for trace and sample index
    public func readSingleSample(traceIndex: Int, sampleIndex: Int) -> Float {
        return SEGYModel.readSingleSampleStatic(
            traceIndex: traceIndex,
            sampleIndex: sampleIndex,
            numTraces: numTraces,
            ns: ns,
            firstTraceOffset: firstTraceOffset,
            traceSize: traceSize,
            format: format,
            isBigEndian: isBigEndian,
            fileSize: fileSize,
            mappedPointer: mappedPointer
        )
    }
    
    private static func readSingleSampleStatic(
        traceIndex: Int,
        sampleIndex: Int,
        numTraces: Int,
        ns: Int,
        firstTraceOffset: Int,
        traceSize: Int,
        format: SEGYFormat,
        isBigEndian: Bool,
        fileSize: Int,
        mappedPointer: UnsafeMutableRawPointer?
    ) -> Float {
        guard traceIndex >= 0 && traceIndex < numTraces else { return 0.0 }
        guard sampleIndex >= 0 && sampleIndex < ns else { return 0.0 }
        guard let ptr = mappedPointer else { return 0.0 }
        
        let offset = firstTraceOffset + traceIndex * traceSize + 240 + sampleIndex * format.sampleSize
        guard offset + format.sampleSize <= fileSize else { return 0.0 }
        
        switch format {
        case .ibmFloat:
            var val: UInt32 = 0
            memcpy(&val, ptr.advanced(by: offset), 4)
            let raw = isBigEndian ? UInt32(bigEndian: val) : UInt32(littleEndian: val)
            return ibmToIeeeStatic(raw)
        case .ieeeFloat:
            var val: UInt32 = 0
            memcpy(&val, ptr.advanced(by: offset), 4)
            let raw = isBigEndian ? UInt32(bigEndian: val) : UInt32(littleEndian: val)
            return Float(bitPattern: raw)
        case .int32:
            var val: Int32 = 0
            memcpy(&val, ptr.advanced(by: offset), 4)
            let raw = isBigEndian ? Int32(bigEndian: val) : Int32(littleEndian: val)
            return Float(raw)
        case .int16:
            var val: Int16 = 0
            memcpy(&val, ptr.advanced(by: offset), 2)
            let raw = isBigEndian ? Int16(bigEndian: val) : Int16(littleEndian: val)
            return Float(raw)
        case .int8:
            let val = ptr.load(fromByteOffset: offset, as: Int8.self)
            return Float(val)
        case .uint8:
            let val = ptr.load(fromByteOffset: offset, as: UInt8.self)
            return Float(val)
        case .fixedPoint:
            var val: Int32 = 0
            memcpy(&val, ptr.advanced(by: offset), 4)
            let raw = isBigEndian ? Int32(bigEndian: val) : Int32(littleEndian: val)
            return Float(raw)
        }
    }
    
    // Reads trace samples for a given trace index
    public func readTraceSamples(traceIndex: Int) -> [Float] {
        guard traceIndex >= 0 && traceIndex < numTraces else { return [] }
        
        var samples = [Float](repeating: 0.0, count: ns)
        let sampleSize = format.sampleSize
        let baseOffset = firstTraceOffset + traceIndex * traceSize + 240
        guard let p = mappedPointer else { return samples }
        let endOffset = fileSize - sampleSize
        let isBE = isBigEndian
        
        switch format {
        case .ibmFloat:
            for i in 0..<ns {
                let offset = baseOffset + i * 4
                if offset > endOffset { break }
                let raw = p.load(fromByteOffset: offset, as: UInt32.self)
                let swapped = isBE ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
                samples[i] = SEGYModel.ibmToIeeeStatic(swapped)
            }
        case .ieeeFloat:
            for i in 0..<ns {
                let offset = baseOffset + i * 4
                if offset > endOffset { break }
                let raw = p.load(fromByteOffset: offset, as: UInt32.self)
                let swapped = isBE ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
                samples[i] = Float(bitPattern: swapped)
            }
        case .int32, .fixedPoint:
            for i in 0..<ns {
                let offset = baseOffset + i * 4
                if offset > endOffset { break }
                let raw = p.load(fromByteOffset: offset, as: Int32.self)
                let swapped = isBE ? Int32(bigEndian: raw) : Int32(littleEndian: raw)
                samples[i] = Float(swapped)
            }
        case .int16:
            for i in 0..<ns {
                let offset = baseOffset + i * 2
                if offset > endOffset { break }
                let raw = p.load(fromByteOffset: offset, as: Int16.self)
                let swapped = isBE ? Int16(bigEndian: raw) : Int16(littleEndian: raw)
                samples[i] = Float(swapped)
            }
        case .int8:
            for i in 0..<ns {
                let offset = baseOffset + i
                if offset > endOffset { break }
                samples[i] = Float(p.load(fromByteOffset: offset, as: Int8.self))
            }
        case .uint8:
            for i in 0..<ns {
                let offset = baseOffset + i
                if offset > endOffset { break }
                samples[i] = Float(p.load(fromByteOffset: offset, as: UInt8.self))
            }
        }
        
        return samples
    }
    
    // Extracts a Z-slice across all traces concurrently
    public func extractZSlice(sampleIndex: Int, progress: @escaping (Double) -> Void) async throws -> [Float] {
        guard numTraces > 0 else { return [] }
        
        let localNumTraces = self.numTraces
        let localNs = self.ns
        let localFirstTraceOffset = self.firstTraceOffset
        let localTraceSize = self.traceSize
        let localFormat = self.format
        let localIsBigEndian = self.isBigEndian
        let localFileSize = self.fileSize
        let localMappedPointer = SendablePointer(pointer: self.mappedPointer)
        
        return try await Task.detached(priority: .userInitiated) {
            let n = localNumTraces
            var slice = [Float](repeating: 0.0, count: n)
            
            // Chunk size for progress updates & cancellation checks
            let chunkSize = max(1000, n / 100)
            let numChunks = (n + chunkSize - 1) / chunkSize
            
            for chunkIdx in 0..<numChunks {
                try Task.checkCancellation()
                
                let startTrace = chunkIdx * chunkSize
                let endTrace = min(n, startTrace + chunkSize)
                let count = endTrace - startTrace
                
                // Concurrently read trace values within this chunk
                DispatchQueue.concurrentPerform(iterations: count) { i in
                    let traceIdx = startTrace + i
                    slice[traceIdx] = SEGYModel.readSingleSampleStatic(
                        traceIndex: traceIdx,
                        sampleIndex: sampleIndex,
                        numTraces: localNumTraces,
                        ns: localNs,
                        firstTraceOffset: localFirstTraceOffset,
                        traceSize: localTraceSize,
                        format: localFormat,
                        isBigEndian: localIsBigEndian,
                        fileSize: localFileSize,
                        mappedPointer: localMappedPointer.pointer
                    )
                }
                
                // Report progress
                let prog = Double(endTrace) / Double(n)
                progress(prog)
            }
            
            return slice
        }.value
    }
}

// Wrapper for raw memory pointer to conform to Sendable
struct SendablePointer: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer?
}
