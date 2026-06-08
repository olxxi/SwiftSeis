import Foundation

let path = "ContentView.swift"
var content = try! String(contentsOfFile: path)

// Add onAppear
if !content.contains("onAppear { print(\"App appeared\") }") {
    let target = ".frame(minWidth: 1000, minHeight: 700)"
    let replacement = """
    .frame(minWidth: 1000, minHeight: 700)
            .onAppear {
                print("App appeared")
                let defaultPath = "/Users/oleksii/Desktop/MacSEGY/seismic/USGS_EN555_line01.sgy"
                if FileManager.default.fileExists(atPath: defaultPath) {
                    print("Auto-loading SEGY: \\(defaultPath)")
                    loadSEGY(at: defaultPath)
                }
            }
    """
    content = content.replacingOccurrences(of: target, with: replacement)
}

// Add prints to loadSEGY
content = content.replacingOccurrences(of: "try model.openSEGY(at: path)", with: "print(\"Calling openSEGY...\"); try model.openSEGY(at: path); print(\"openSEGY finished.\")")
content = content.replacingOccurrences(of: "model.scanTraceHeaders(progress: { pct in", with: "print(\"Calling scanTraceHeaders...\"); model.scanTraceHeaders(progress: { pct in")
content = content.replacingOccurrences(of: "self.refreshActiveSlice()", with: "print(\"Calling refreshActiveSlice...\"); self.refreshActiveSlice(); print(\"refreshActiveSlice returned.\")")

try! content.write(toFile: path, atomically: true, encoding: .utf8)
