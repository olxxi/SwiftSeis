import Foundation

// A minimal script to test memory-mapped reading speed
let path = "seismic/USGS_EN555_line01.sgy"
let fd = open(path, O_RDONLY)
let fileSize = lseek(fd, 0, SEEK_END)
lseek(fd, 0, SEEK_SET)

let mappedPointer = mmap(nil, Int(fileSize), PROT_READ, MAP_PRIVATE, fd, 0)

var dtVal: UInt16 = 0
var nsVal: UInt16 = 0
var formatVal: UInt16 = 0
memcpy(&dtVal, mappedPointer!.advanced(by: 3216), 2)
memcpy(&nsVal, mappedPointer!.advanced(by: 3220), 2)
memcpy(&formatVal, mappedPointer!.advanced(by: 3224), 2)

let isBigEndian = true // assumed
let ns = Int(UInt16(bigEndian: nsVal))
let format = Int(UInt16(bigEndian: formatVal))

let traceSize = 240 + ns * 4
let numTraces = (Int(fileSize) - 3600) / traceSize

print("ns: \(ns), format: \(format), numTraces: \(numTraces)")

let start = Date()
var inlines = Set<Int>()
var crosslines = Set<Int>()
for i in 0..<numTraces {
    let offset = 3600 + i * traceSize
    var inline: Int32 = 0
    memcpy(&inline, mappedPointer!.advanced(by: offset + 188), 4)
    inlines.insert(Int(Int32(bigEndian: inline)))
}
print("Header scan: \(-start.timeIntervalSinceNow) s")

let start2 = Date()
var samples = [[Float]]()
for i in 0..<numTraces {
    let offset = 3600 + i * traceSize + 240
    var trace = [Float](repeating: 0.0, count: ns)
    for j in 0..<ns {
        var val: UInt32 = 0
        memcpy(&val, mappedPointer!.advanced(by: offset + j * 4), 4)
        trace[j] = Float(bitPattern: UInt32(bigEndian: val))
    }
    samples.append(trace)
}
print("Read samples: \(-start2.timeIntervalSinceNow) s")

let start3 = Date()
let width = samples.count
let height = ns
var pixels = [Float](repeating: 0.0, count: width * height)
for i in 0..<width {
    let trace = samples[i]
    for j in 0..<min(height, trace.count) {
        pixels[j * width + i] = trace[j]
    }
}
print("Flatten pixels: \(-start3.timeIntervalSinceNow) s")

