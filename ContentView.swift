import SwiftUI
import MetalKit
import UniformTypeIdentifiers

public struct ContentView: View {
    @StateObject private var model = SEGYModel()
    @StateObject private var rendererWrapper = MetalRendererWrapper()
    
    @State private var isTargeted = false
    
    // View state
    @State private var viewMode: Int = 1 // 1: Inline Section, 2: Crossline Section, 3: Z-Slice (Time/Depth)
    @State private var activeZIndex: Int = 0
    
    // Text input states for slider sync
    @State private var inlineInput: String = ""
    @State private var crosslineInput: String = ""
    @State private var zIndexInput: String = ""
    
    // Interaction state
    @State private var hoveredTraceIndex: Int? = nil
    @State private var hoveredSampleIndex: Int? = nil
    
    // Hover details
    @State private var hoveredInline: Int = 0
    @State private var hoveredCrossline: Int = 0
    @State private var hoveredOffset: Int = 0
    @State private var hoveredValue: Float = 0.0
    @State private var hoveredTimeMs: Double = 0.0
    
    // Z-slice background state
    @State private var isZSliceLoading = false
    @State private var zSliceProgress = 0.0
    @State private var activeZSlice: [Float] = []
    @State private var zSliceTask: Task<Void, Never>? = nil
    
    // 3D Slices loading state
    @State private var is3DZSliceLoading = false
    @State private var z3DSliceProgress = 0.0
    @State private var z3DSliceTask: Task<Void, Never>? = nil
    
    // QC State
    @State private var isShowingQCReport = false
    @State private var isQCRunning = false
    @State private var qcProgress: Double = 0.0
    @State private var qcReport: QCReport? = nil
    
    // Rendering State
    @State private var isFileLoading = false
    @State private var fileLoadingProgress = 0.0
    
    // QC Plot State
    @State private var plotWord: PlotHeaderWord = .offset
    
    // UI layout state
    @State private var bottomPanelHeight: CGFloat = 220
    @State private var rightSidebarWidth: CGFloat = 220
    @State private var sidebarWidth: CGFloat = 280
    @State private var bottomTab: Int = 2 // 0: Text, 1: Binary, 2: Trace Headers
    
    // Canvas sizing for coordinate mapping
    @State private var canvasSize: CGSize = .zero
    
    // Traces loaded in active view (used for tables, plots, etc.)
    @State private var activeTraces: [TraceHeader] = []
    @State private var activeSamples: [[Float]] = []
    
    // File status message
    @State private var statusMessage: String = "No file loaded"
    @State private var isError: Bool = false
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // 1. Left Sidebar
            SidebarView
                .frame(width: sidebarWidth)
                .background(Color(nsColor: .windowBackgroundColor))
            
            // Left Resizable Divider (thin split line)
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 1)
                .contentShape(Rectangle())
                .frame(width: 6)
                .onHover { inside in
                    if inside {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let newWidth = sidebarWidth + gesture.translation.width
                            sidebarWidth = max(260, min(400, newWidth))
                        }
                )
            
            // 2. Main content area
            VStack(spacing: 0) {
                // Top Toolbar QC Plot
                if viewMode != 3 && viewMode != 4 && !activeTraces.isEmpty {
                    HeaderPlotView(headers: activeTraces, activeWord: plotWord, hoveredTraceIndex: $hoveredTraceIndex)
                        .frame(height: 75)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .windowBackgroundColor))
                    Divider()
                }
                
                // Main split: Center Canvas and Right 1D Inspector
                HStack(spacing: 0) {
                    // Center Canvas (Metal View)
                    ZStack {
                        if model.filePath == nil {
                            LandingScreen
                        } else {
                            MetalCanvasView
                            
                            // Highlight crosshair
                            CrosshairOverlay
                                .allowsHitTesting(false)
                            
                            // Z-slice loading progress bar
                            if isZSliceLoading || is3DZSliceLoading {
                                ProgressOverlay
                                    .allowsHitTesting(false)
                            }
                        }
                        
                        if isFileLoading {
                            FileLoadingOverlay
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Right Sidebar (1D Inspector)
                    if viewMode != 3 && viewMode != 4 {
                        // Right Resizable Divider
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 1)
                            .contentShape(Rectangle())
                            .frame(width: 6)
                            .onHover { inside in
                                if inside {
                                    NSCursor.resizeLeftRight.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        let newWidth = rightSidebarWidth - gesture.translation.width
                                        rightSidebarWidth = max(200, min(350, newWidth))
                                    }
                            )
                        
                        let firstSelectedId = rendererWrapper.selectedTraceIndices.first
                        let firstSelectedLocalIndex = firstSelectedId.flatMap { selId in
                            activeTraces.firstIndex(where: { $0.id == selId })
                        }
                        
                        TraceInspectorView(
                            samples: (hoveredTraceIndex != nil && hoveredTraceIndex! < activeSamples.count) ? activeSamples[hoveredTraceIndex!] : (firstSelectedLocalIndex != nil && firstSelectedLocalIndex! < activeSamples.count ? activeSamples[firstSelectedLocalIndex!] : []),
                            traceIndex: hoveredTraceIndex ?? firstSelectedLocalIndex ?? 0,
                            ns: model.ns,
                            dt: model.dt,
                            isHovered: hoveredTraceIndex != nil,
                            onClearSelection: {
                                rendererWrapper.selectedTraceIndices.removeAll()
                            }
                        )
                        .frame(width: rightSidebarWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if viewMode != 3 && viewMode != 4 {
                    // Bottom Resizable Divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 1)
                        .contentShape(Rectangle())
                        .frame(height: 6)
                        .onHover { inside in
                            if inside {
                                NSCursor.resizeUpDown.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let newHeight = bottomPanelHeight - gesture.translation.height
                                    bottomPanelHeight = max(150, min(500, newHeight))
                                }
                        )
                    
                    // Bottom Panel (Headers)
                    BottomPanel
                        .frame(height: bottomPanelHeight)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 600)
        .navigationTitle(model.fileName ?? "SwiftSeis Viewer")
        .toolbar {
            ToolbarItems
        }
        .onAppear {
            rendererWrapper.onScreenshotReady = { image in
                saveScreenshot(image: image)
            }
            
            // Check for command line argument to load file (useful for automated testing)
            let args = CommandLine.arguments
            if args.count > 1 {
                let filePath = args[1]
                if FileManager.default.fileExists(atPath: filePath) {
                    loadSEGY(at: filePath)
                    return
                }
            }
            
            // Load a default test file if present
            let cwd = FileManager.default.currentDirectoryPath
            let defaultPath = URL(fileURLWithPath: cwd).appendingPathComponent("synthetic_ibm_big.segy").path
            if FileManager.default.fileExists(atPath: defaultPath) {
                loadSEGY(at: defaultPath)
            }
        }
        .onChange(of: model.activeInline) {
            inlineInput = "\(model.activeInline)"
        }
        .onChange(of: model.activeCrossline) {
            crosslineInput = "\(model.activeCrossline)"
        }
        .onChange(of: activeZIndex) {
            zIndexInput = "\(activeZIndex)"
        }
    }
    
    private func runQC() {
        guard !isQCRunning else { return }
        isQCRunning = true
        qcProgress = 0.0
        
        Task {
            let report = await QCAnalyzer.runQC(model: model) { progress in
                self.qcProgress = progress
            }
            
            await MainActor.run {
                self.qcReport = report
                self.isQCRunning = false
                QCReportWindowController.shared.show(with: report)
            }
        }
    }
    
    // --- Subviews ---
    
    // Landing Screen when no file is loaded
    private var LandingScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon with glowing effect if targeted
            ZStack {
                Circle()
                    .fill(isTargeted ? Color.blue.opacity(0.15) : Color.blue.opacity(0.08))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isTargeted ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isTargeted)
                
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .scaleEffect(isTargeted ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isTargeted)
            }
            
            VStack(spacing: 8) {
                Text("Welcome to SwiftSeis")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                
                Text(isTargeted ? "Drop your SEGY file here" : "Drag and drop a SEGY file, or choose from your computer")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 450)
            
            Button(action: selectFile) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Select SEGY File...")
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.blue : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.blue.opacity(0.03) : Color.clear)
                )
        )
        .padding(30)
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            if let provider = providers.first {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        DispatchQueue.main.async {
                            loadSEGY(at: url.path)
                        }
                    } else {
                        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                            if let data = data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                DispatchQueue.main.async {
                                    loadSEGY(at: url.path)
                                }
                            }
                        }
                    }
                }
                return true
            }
            return false
        }
    }
    
    // Sidebar Controls View
    private var SidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // File Metadata summary
                GroupBox(label: Label("File Details", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledMetadata(label: "File Size", value: String(format: "%.2f MB", Double(model.fileSize) / 1024.0 / 1024.0))
                        LabeledMetadata(label: "Traces Count", value: "\(model.numTraces)")
                        LabeledMetadata(label: "Samples per Trace", value: "\(model.ns)")
                        LabeledMetadata(label: "Sample Interval", value: "\(Double(model.dt)/1000.0) ms")
                        LabeledMetadata(label: "Format Detected", value: model.format.description)
                        LabeledMetadata(label: "Byte Order", value: model.isBigEndian ? "Big-Endian" : "Little-Endian")
                        LabeledMetadata(label: "Encoding", value: model.isEbcdic ? "EBCDIC" : "ASCII")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                
                // Format Overrides (in case auto-detect fails)
                GroupBox(label: Label("Overrides", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("EBCDIC Text Encoding", isOn: Binding(
                            get: { model.isEbcdic },
                            set: { newValue in
                                model.isEbcdic = newValue
                                // Trigger reparse
                                reloadSEGYFile()
                            }
                        ))
                        
                        Toggle("Big Endian Byte Order", isOn: Binding(
                            get: { model.isBigEndian },
                            set: { newValue in
                                model.isBigEndian = newValue
                                reloadSEGYFile()
                            }
                        ))
                        
                        Picker("Format", selection: Binding(
                            get: { model.format },
                            set: { newValue in
                                model.format = newValue
                                model.binaryHeader["Format Code"] = "\(newValue.rawValue)"
                                refreshActiveSlice()
                            }
                        )) {
                            Text("IBM Float").tag(SEGYFormat.ibmFloat)
                            Text("IEEE Float").tag(SEGYFormat.ieeeFloat)
                            Text("Int16 (2-byte)").tag(SEGYFormat.int16)
                            Text("Int32 (4-byte)").tag(SEGYFormat.int32)
                            Text("Int8 (1-byte)").tag(SEGYFormat.int8)
                        }
                        .pickerStyle(.menu)
                        
                        Picker("Inline Byte", selection: Binding(
                            get: { model.inlineByteOffset },
                            set: { updateCoordinateOffsets(inlineOffset: $0, crosslineOffset: nil) }
                        )) {
                            Text("Byte 189 (Std)").tag(188)
                            Text("Byte 181").tag(180)
                            Text("Byte 9").tag(8)
                            Text("Byte 17").tag(16)
                        }
                        .pickerStyle(.menu)
                        
                        Picker("Crossline Byte", selection: Binding(
                            get: { model.crosslineByteOffset },
                            set: { updateCoordinateOffsets(inlineOffset: nil, crosslineOffset: $0) }
                        )) {
                            Text("Byte 193 (Std)").tag(192)
                            Text("Byte 185").tag(184)
                            Text("Byte 21").tag(20)
                            Text("Byte 13").tag(12)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.top, 4)
                }
                
                // Navigation (Slices / Dimensions)
                if model.filePath != nil {
                    GroupBox(label: Label("Navigation & Slices", systemImage: "square.3d.layers.3d")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("View Mode", selection: $viewMode) {
                                Text("Inline Section").tag(1)
                                if model.maxCrossline > model.minCrossline {
                                    Text("Crossline Section").tag(2)
                                }
                                if model.maxInline > model.minInline && model.maxCrossline > model.minCrossline {
                                    Text("Z-Slice (Time)").tag(3)
                                    Text("3D View").tag(4)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("viewModePicker")
                            .onChange(of: viewMode) {
                                rendererWrapper.is3DMode = (viewMode == 4)
                                rendererWrapper.selectedTraceIndices.removeAll()
                                hoveredTraceIndex = nil
                                refreshActiveSlice()
                                inlineInput = "\(model.activeInline)"
                                crosslineInput = "\(model.activeCrossline)"
                                zIndexInput = "\(activeZIndex)"
                            }
                            
                            if viewMode == 1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Inline: \(model.activeInline)")
                                            .font(.caption)
                                        Spacer()
                                        Text("Range: \(model.minInline) - \(model.maxInline)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    if model.maxInline > model.minInline {
                                        Slider(value: Binding(
                                            get: { Double(model.activeInline) },
                                            set: { model.activeInline = Int($0); refreshActiveSlice() }
                                        ), in: Double(model.minInline)...Double(model.maxInline), step: 1)
                                        .accessibilityIdentifier("inlineSlider")
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Button(action: {
                                            if model.activeInline > model.minInline {
                                                model.activeInline -= 1
                                                refreshActiveSlice()
                                            }
                                        }) {
                                            Image(systemName: "chevron.left")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(model.activeInline <= model.minInline)
                                        
                                        TextField("", text: $inlineInput, onCommit: {
                                            if let val = Int(inlineInput), val >= model.minInline && val <= model.maxInline {
                                                model.activeInline = val
                                                refreshActiveSlice()
                                            } else {
                                                inlineInput = "\(model.activeInline)"
                                            }
                                        })
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityIdentifier("inlineTextField")
                                        .frame(width: 70)
                                        .multilineTextAlignment(.center)
                                        
                                        Button(action: {
                                            if model.activeInline < model.maxInline {
                                                model.activeInline += 1
                                                refreshActiveSlice()
                                            }
                                        }) {
                                            Image(systemName: "chevron.right")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(model.activeInline >= model.maxInline)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            } else if viewMode == 2 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Crossline: \(model.activeCrossline)")
                                            .font(.caption)
                                        Spacer()
                                        Text("Range: \(model.minCrossline) - \(model.maxCrossline)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    if model.maxCrossline > model.minCrossline {
                                        Slider(value: Binding(
                                            get: { Double(model.activeCrossline) },
                                            set: { model.activeCrossline = Int($0); refreshActiveSlice() }
                                        ), in: Double(model.minCrossline)...Double(model.maxCrossline), step: 1)
                                        .accessibilityIdentifier("crosslineSlider")
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Button(action: {
                                            if model.activeCrossline > model.minCrossline {
                                                model.activeCrossline -= 1
                                                refreshActiveSlice()
                                            }
                                        }) {
                                            Image(systemName: "chevron.left")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(model.activeCrossline <= model.minCrossline)
                                        
                                        TextField("", text: $crosslineInput, onCommit: {
                                            if let val = Int(crosslineInput), val >= model.minCrossline && val <= model.maxCrossline {
                                                model.activeCrossline = val
                                                refreshActiveSlice()
                                            } else {
                                                crosslineInput = "\(model.activeCrossline)"
                                            }
                                        })
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityIdentifier("crosslineTextField")
                                        .frame(width: 70)
                                        .multilineTextAlignment(.center)
                                        
                                        Button(action: {
                                            if model.activeCrossline < model.maxCrossline {
                                                model.activeCrossline += 1
                                                refreshActiveSlice()
                                            }
                                        }) {
                                            Image(systemName: "chevron.right")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(model.activeCrossline >= model.maxCrossline)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            } else if viewMode == 3 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Z-Slice Time: \(Int(Double(activeZIndex * model.dt) / 1000.0)) ms")
                                            .font(.caption)
                                        Spacer()
                                        Text("Sample Index: \(activeZIndex)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    if model.ns > 1 {
                                        Slider(value: Binding(
                                            get: { Double(activeZIndex) },
                                            set: {
                                                let val = Int($0)
                                                if val != activeZIndex {
                                                    activeZIndex = val
                                                    triggerZSliceExtraction()
                                                }
                                            }
                                        ), in: 0...Double(model.ns - 1), step: 1)
                                        .accessibilityIdentifier("zSliceSlider")
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Button(action: {
                                            if activeZIndex > 0 {
                                                activeZIndex -= 1
                                                triggerZSliceExtraction()
                                            }
                                        }) {
                                            Image(systemName: "chevron.left")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(activeZIndex <= 0)
                                        
                                        TextField("", text: $zIndexInput, onCommit: {
                                            if let val = Int(zIndexInput), val >= 0 && val < model.ns {
                                                activeZIndex = val
                                                triggerZSliceExtraction()
                                            } else {
                                                zIndexInput = "\(activeZIndex)"
                                            }
                                        })
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityIdentifier("zSliceTextField")
                                        .frame(width: 70)
                                        .multilineTextAlignment(.center)
                                        
                                        Button(action: {
                                            if activeZIndex < model.ns - 1 {
                                                activeZIndex += 1
                                                triggerZSliceExtraction()
                                            }
                                        }) {
                                            Image(systemName: "chevron.right")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(activeZIndex >= model.ns - 1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            } else if viewMode == 4 {
                                VStack(alignment: .leading, spacing: 16) {
                                    // Inline slider
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Inline: \(model.activeInline)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text("Range: \(model.minInline) - \(model.maxInline)")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        if model.maxInline > model.minInline {
                                            Slider(value: Binding(
                                                get: { Double(model.activeInline) },
                                                set: { model.activeInline = Int($0); update3DInlineSlice() }
                                            ), in: Double(model.minInline)...Double(model.maxInline), step: 1)
                                            .accessibilityIdentifier("inlineSlider3D")
                                        }
                                        HStack(spacing: 8) {
                                            Button(action: {
                                                if model.activeInline > model.minInline {
                                                    model.activeInline -= 1
                                                    update3DInlineSlice()
                                                }
                                            }) {
                                                Image(systemName: "chevron.left")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(model.activeInline <= model.minInline)
                                            
                                            TextField("", text: $inlineInput, onCommit: {
                                                if let val = Int(inlineInput), val >= model.minInline && val <= model.maxInline {
                                                    model.activeInline = val
                                                    update3DInlineSlice()
                                                } else {
                                                    inlineInput = "\(model.activeInline)"
                                                }
                                            })
                                            .textFieldStyle(.roundedBorder)
                                            .accessibilityIdentifier("inlineTextField3D")
                                            .frame(width: 70)
                                            .multilineTextAlignment(.center)
                                            
                                            Button(action: {
                                                if model.activeInline < model.maxInline {
                                                    model.activeInline += 1
                                                    update3DInlineSlice()
                                                }
                                            }) {
                                                Image(systemName: "chevron.right")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(model.activeInline >= model.maxInline)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    
                                    Divider()
                                    
                                    // Crossline slider
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Crossline: \(model.activeCrossline)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text("Range: \(model.minCrossline) - \(model.maxCrossline)")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        if model.maxCrossline > model.minCrossline {
                                            Slider(value: Binding(
                                                get: { Double(model.activeCrossline) },
                                                set: { model.activeCrossline = Int($0); update3DCrosslineSlice() }
                                            ), in: Double(model.minCrossline)...Double(model.maxCrossline), step: 1)
                                            .accessibilityIdentifier("crosslineSlider3D")
                                        }
                                        HStack(spacing: 8) {
                                            Button(action: {
                                                if model.activeCrossline > model.minCrossline {
                                                    model.activeCrossline -= 1
                                                    update3DCrosslineSlice()
                                                }
                                            }) {
                                                Image(systemName: "chevron.left")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(model.activeCrossline <= model.minCrossline)
                                            
                                            TextField("", text: $crosslineInput, onCommit: {
                                                if let val = Int(crosslineInput), val >= model.minCrossline && val <= model.maxCrossline {
                                                    model.activeCrossline = val
                                                    update3DCrosslineSlice()
                                                } else {
                                                    crosslineInput = "\(model.activeCrossline)"
                                                }
                                            })
                                            .textFieldStyle(.roundedBorder)
                                            .accessibilityIdentifier("crosslineTextField3D")
                                            .frame(width: 70)
                                            .multilineTextAlignment(.center)
                                            
                                            Button(action: {
                                                if model.activeCrossline < model.maxCrossline {
                                                    model.activeCrossline += 1
                                                    update3DCrosslineSlice()
                                                }
                                            }) {
                                                Image(systemName: "chevron.right")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(model.activeCrossline >= model.maxCrossline)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    
                                    Divider()
                                    
                                    // Z-slice slider
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Z-Slice Time: \(Int(Double(activeZIndex * model.dt) / 1000.0)) ms")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text("Sample Index: \(activeZIndex)")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        if model.ns > 1 {
                                            Slider(value: Binding(
                                                get: { Double(activeZIndex) },
                                                set: {
                                                    let val = Int($0)
                                                    if val != activeZIndex {
                                                        activeZIndex = val
                                                        trigger3DVolumeZSliceExtraction()
                                                    }
                                                }
                                            ), in: 0...Double(model.ns - 1), step: 1)
                                            .accessibilityIdentifier("zSliceSlider3D")
                                        }
                                        HStack(spacing: 8) {
                                            Button(action: {
                                                if activeZIndex > 0 {
                                                    activeZIndex -= 1
                                                    trigger3DVolumeZSliceExtraction()
                                                }
                                            }) {
                                                Image(systemName: "chevron.left")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(activeZIndex <= 0)
                                            
                                            TextField("", text: $zIndexInput, onCommit: {
                                                if let val = Int(zIndexInput), val >= 0 && val < model.ns {
                                                    activeZIndex = val
                                                    trigger3DVolumeZSliceExtraction()
                                                } else {
                                                    zIndexInput = "\(activeZIndex)"
                                                }
                                            })
                                            .textFieldStyle(.roundedBorder)
                                            .accessibilityIdentifier("zSliceTextField3D")
                                            .frame(width: 70)
                                            .multilineTextAlignment(.center)
                                            
                                            Button(action: {
                                                if activeZIndex < model.ns - 1 {
                                                    activeZIndex += 1
                                                    trigger3DVolumeZSliceExtraction()
                                                }
                                            }) {
                                                Image(systemName: "chevron.right")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(activeZIndex >= model.ns - 1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    
                                    Divider()
                                    
                                    // Z-Scale slider for 3D
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Vertical Stretch (Z-Axis)")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text(String(format: "%.1fx", rendererWrapper.zScale3D))
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        Slider(value: $rendererWrapper.zScale3D, in: 0.1...10.0, step: 0.1)
                                            .onChange(of: rendererWrapper.zScale3D) { _ in
                                                rendererWrapper.triggerRedraw()
                                            }
                                            .accessibilityIdentifier("zScaleSlider3D")
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                
                // Gain and Palette Controls
                GroupBox(label: Label("Display & Gain", systemImage: "paintbrush")) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Gain: \(String(format: "%.1f", rendererWrapper.gain))x")
                                    .font(.caption)
                                Spacer()
                            }
                            Slider(value: $rendererWrapper.gain, in: 0.1...10.0, step: 0.1)
                                .onChange(of: rendererWrapper.gain) { rendererWrapper.triggerRedraw() }
                        }
                        
                        if rendererWrapper.displayMode != 1 {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Wiggle Scale: \(String(format: "%.1f", rendererWrapper.wiggleScale))")
                                        .font(.caption)
                                    Spacer()
                                }
                                Slider(value: $rendererWrapper.wiggleScale, in: 0.5...8.0, step: 0.1)
                                    .onChange(of: rendererWrapper.wiggleScale) {
                                        rendererWrapper.instance.updateWiggleGeometry(samples: activeSamples, ns: model.ns)
                                    }
                            }
                        }
                        
                        if rendererWrapper.displayMode != 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Colormap")
                                        .font(.caption)
                                    Spacer()
                                }
                                Picker("Colormap", selection: $rendererWrapper.colormap) {
                                    Text("Seismic (Blue-White-Red)").tag(1)
                                    Text("Grayscale").tag(0)
                                    Text("Rainbow").tag(2)
                                    Text("High Contrast").tag(3)
                                }
                                .pickerStyle(.menu)
                                .onChange(of: rendererWrapper.colormap) { rendererWrapper.triggerRedraw() }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Contrast Clip: \(Int(rendererWrapper.clipPercentile * 100))%")
                                        .font(.caption)
                                }
                                Slider(value: $rendererWrapper.clipPercentile, in: 0.05...3.0, step: 0.05)
                                    .onChange(of: rendererWrapper.clipPercentile) { rendererWrapper.triggerRedraw() }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                GroupBox(label: Label("Aspect Scales", systemImage: "arrow.up.left.and.arrow.down.right")) {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Horizontal (X)").font(.caption)
                            Spacer()
                            ControlGroup {
                                Button(action: { rendererWrapper.zoomX = max(0.1, rendererWrapper.zoomX / 1.2) }) { Image(systemName: "minus") }
                                Button(action: { rendererWrapper.zoomX = min(200.0, rendererWrapper.zoomX * 1.2) }) { Image(systemName: "plus") }
                            }
                            .frame(width: 70)
                        }
                        
                        HStack {
                            Text("Vertical (Z)").font(.caption)
                            Spacer()
                            ControlGroup {
                                Button(action: { rendererWrapper.zoomY = max(0.1, rendererWrapper.zoomY / 1.2) }) { Image(systemName: "minus") }
                                Button(action: { rendererWrapper.zoomY = min(200.0, rendererWrapper.zoomY * 1.2) }) { Image(systemName: "plus") }
                            }
                            .frame(width: 70)
                        }
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
                
                // Load Status at bottom of sidebar
                HStack(spacing: 6) {
                    Circle()
                        .fill(isError ? Color.red : (model.filePath == nil ? Color.gray : Color.green))
                        .frame(width: 8, height: 8)
                    Text(statusMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("statusLabel")
                }
                .padding(.horizontal, 4)
            }
            .frame(width: sidebarWidth - 24, alignment: .leading)
            .padding(12)
        }
    }
    
    private func LabeledMetadata(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
    }
    
    // Center Canvas wrapping the Metal View
    private var MetalCanvasView: some View {
        GeometryReader { geom in
            MetalView(renderer: rendererWrapper)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        canvasSize = geom.size
                        updateHoverDetails(at: location)
                    case .ended:
                        hoveredTraceIndex = nil
                        hoveredSampleIndex = nil
                    }
                }
                .overlay(
                    // Zoom controls embedded directly in Canvas bottom right
                    HStack(spacing: 6) {
                        Button(action: zoomIn) {
                            Image(systemName: "plus.magnifyingglass")
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Zoom In (Cmd + =)")
                        
                        Button(action: zoomOut) {
                            Image(systemName: "minus.magnifyingglass")
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Zoom Out (Cmd + -)")
                        
                        Button(action: resetZoom) {
                            Image(systemName: "arrow.counterclockwise")
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Reset Zoom (Cmd + 0)")
                    }
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
                    .padding(12),
                    alignment: .bottomTrailing
                )
                .overlay(alignment: .center) {
                    if isFileLoading {
                        ProgressView("Loading File...", value: fileLoadingProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding()
                            .frame(width: 250)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                            .cornerRadius(8)
                    } else if isQCRunning {
                        ProgressView("Running QC Analysis...", value: qcProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding()
                            .frame(width: 250)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                            .cornerRadius(8)
                    }
                }
        }
    }
    
    // Crosshair and value display overlayed on mouse hover
    private var CrosshairOverlay: some View {
        Group {
            if let trIdx = hoveredTraceIndex, let smIdx = hoveredSampleIndex, canvasSize.width > 0 {
                // Texture mapped space coordinates:
                // u = (relativeX - 0.5) / zoomX + 0.5 + panX / numTraces
                // Solve for relativeX: relativeX = (u - 0.5 - panX/numTraces) * zoomX + 0.5
                let zoomX = rendererWrapper.zoomX
                let zoomY = rendererWrapper.zoomY
                let panX = rendererWrapper.panX
                let panY = rendererWrapper.panY
                let nTraces = Float(rendererWrapper.instance.instance_numTraces())
                let nS = Float(rendererWrapper.instance.instance_ns())
                
                let u = (Float(trIdx) + 0.5) / nTraces
                let v = (Float(smIdx) + 0.5) / nS
                
                let screenU = CGFloat((u - 0.5 - panX/nTraces) * zoomX + 0.5)
                let screenV = CGFloat((v - 0.5 - panY/nS) * zoomY + 0.5)
                
                let screenX = screenU * canvasSize.width
                let screenY = screenV * canvasSize.height
                
                if screenX >= 0 && screenX <= canvasSize.width && screenY >= 0 && screenY <= canvasSize.height {
                    ZStack(alignment: .topLeading) {
                        // Vertical line
                        Path { path in
                            path.move(to: CGPoint(x: screenX, y: 0))
                            path.addLine(to: CGPoint(x: screenX, y: canvasSize.height))
                        }
                        .stroke(Color.blue.opacity(0.35), lineWidth: 0.8)
                        
                        // Horizontal line
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: screenY))
                            path.addLine(to: CGPoint(x: canvasSize.width, y: screenY))
                        }
                        .stroke(Color.blue.opacity(0.35), lineWidth: 0.8)
                        
                        // Hover Details Tag
                        VStack(alignment: .leading, spacing: 4) {
                            if viewMode == 3 {
                                Text("Inline: \(hoveredInline)")
                                Text("Crossline: \(hoveredCrossline)")
                            } else {
                                Text("Trace: #\(trIdx + 1)")
                                Text("Inline: \(hoveredInline)  |  Xline: \(hoveredCrossline)")
                                Text("Time: \(String(format: "%.1f", hoveredTimeMs)) ms")
                                Text("Offset: \(hoveredOffset) m")
                            }
                            Text("Value: \(String(format: "%.4f", hoveredValue))")
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .padding(6)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                        .cornerRadius(4)
                        .shadow(radius: 2)
                        .position(x: screenX + 70, y: screenY - 50)
                    }
                }
            }
        }
    }
    
    // Z-slice loading progress Overlay
    private var ProgressOverlay: some View {
        VStack(spacing: 12) {
            ProgressView(value: zSliceProgress) {
                Text("Extracting Time Slice...")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .progressViewStyle(.linear)
            .frame(width: 200)
            
            Text("\(Int(zSliceProgress * 100))% Complete")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
    
    // File loading progress Overlay
    private var FileLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
            
            VStack(spacing: 16) {
                ProgressView(value: fileLoadingProgress) {
                    Text("Scanning Trace Headers...")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .progressViewStyle(.linear)
                .frame(width: 280)
                
                Text(String(format: "%.0f%% Complete (%d traces)", fileLoadingProgress * 100, model.numTraces))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 10)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Bottom panel containing text, binary and trace header grids
    private var BottomPanel: some View {
        VStack(spacing: 0) {
            Picker("Bottom panel views", selection: $bottomTab) {
                Text("Text Header (3200 bytes)").tag(0)
                Text("Binary Header (400 bytes)").tag(1)
                Text("Trace Headers").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(6)
            
            Divider()
            
            switch bottomTab {
            case 0:
                ScrollView {
                    Text(model.textHeader)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            case 1:
                List {
                    ForEach(model.binaryHeader.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key)
                                .fontWeight(.medium)
                                .frame(width: 250, alignment: .leading)
                            Divider()
                            Text(value)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(.vertical, 2)
                    }
                }
            default:
                TraceHeaderTable(headers: activeTraces, selectedTraceIndices: $rendererWrapper.selectedTraceIndices)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // Toolbar buttons
    @ToolbarContentBuilder
    private var ToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: selectFile) {
                Label("Open SEGY", systemImage: "doc.badge.plus")
            }
            .help("Open a seismic SEGY file")
        }
        
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                Button(action: {
                    LocationMapWindowController.shared.show(with: model)
                }) {
                    Label("Location Map", systemImage: "map")
                }
                .help("Open 2D Location Map")
                
                Button(action: runQC) {
                    Label("Run QC", systemImage: "checkmark.seal")
                }
                .help("Run Quality Control Analysis")
                .disabled(model.filePath == nil || isFileLoading || isQCRunning)
                
                Button(action: {
                    rendererWrapper.exportFullSeismicImage { image in
                        if let image = image {
                            saveScreenshot(image: image)
                        }
                    }
                }) {
                    Label("Screenshot", systemImage: "camera")
                }
                .help("Take a high-quality PNG snapshot")
            }
        }
        
        ToolbarItem(placement: .navigation) {
            Picker("Display Mode", selection: $rendererWrapper.displayMode) {
                Label("Variable Density", systemImage: "circle.grid.2x2")
                    .tag(1)
                    .help("Show Variable Density seismic data only")
                Label("Wiggle Trace", systemImage: "waveform")
                    .tag(0)
                    .help("Show wiggle traces only")
                Label("Overlap Overlay", systemImage: "waveform.path.ecg")
                    .tag(2)
                    .help("Overlay wiggle traces on top of Variable Density data")
            }
            .pickerStyle(.segmented)
            .help("Toggle rendering: Color, Wiggle or Overlap")
        }
        
        if viewMode != 3 && viewMode != 4 && !activeTraces.isEmpty {
            ToolbarItem(placement: .automatic) {
                Picker("QC Plot Word", selection: $plotWord) {
                    Text("Offset").tag(PlotHeaderWord.offset)
                    Text("Elevation").tag(PlotHeaderWord.elevation)
                    Text("Source X").tag(PlotHeaderWord.srcX)
                    Text("Receiver X").tag(PlotHeaderWord.recX)
                    Text("Seq Line").tag(PlotHeaderWord.seqLine)
                }
                .pickerStyle(.menu)
                .help("Select header word to plot for QC")
            }
        }
        
        ToolbarItem(placement: .status) {
            if model.filePath != nil {
                Text(model.fileName ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // --- File & Data Logic ---
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            loadSEGY(at: url.path)
        }
    }
    
    private func loadSEGY(at path: String) {
        statusMessage = "Loading..."
        isError = false
        isFileLoading = true
        fileLoadingProgress = 0.0
        
        do {
            try model.openSEGY(at: path)
            model.scanTraceHeaders(progress: { pct in
                self.fileLoadingProgress = pct
            }, completion: {
                self.statusMessage = "File loaded successfully: \(self.model.fileName!)"
                self.isError = false
                self.isFileLoading = false
                
                // Adjust navigation modes depending on dimensions
                self.viewMode = 1 // default to Inline Section
                self.model.activeInline = self.model.minInline
                self.model.activeCrossline = self.model.minCrossline
                self.activeZIndex = 0
                self.rendererWrapper.selectedTraceIndices.removeAll()
                self.hoveredTraceIndex = nil
                
                self.inlineInput = "\(self.model.minInline)"
                self.crosslineInput = "\(self.model.minCrossline)"
                self.zIndexInput = "0"
                
                self.refreshActiveSlice()
            })
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isError = true
            model.closeFile()
            isFileLoading = false
        }
    }
    
    private func reloadSEGYFile() {
        guard let path = model.filePath else { return }
        statusMessage = "Reloading..."
        isError = false
        isFileLoading = true
        fileLoadingProgress = 0.0
        
        do {
            try model.openSEGY(at: path)
            model.scanTraceHeaders(progress: { pct in
                self.fileLoadingProgress = pct
            }, completion: {
                self.isFileLoading = false
                self.refreshActiveSlice()
            })
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isError = true
            model.closeFile()
            isFileLoading = false
        }
    }
    
    private func refreshActiveSlice() {
        guard model.filePath != nil else { return }
        
        // Cancel in-flight Z-slice extractions
        zSliceTask?.cancel()
        isZSliceLoading = false
        
        switch viewMode {
        case 1:
            // 3D Inline section: load traces for model.activeInline
            let traceIndices = model.inlineMap[model.activeInline] ?? []
            activeTraces = traceIndices.map { model.traceHeaders[$0] }
            activeSamples = traceIndices.map { model.readTraceSamples(traceIndex: $0) }
            
            rendererWrapper.loadData(samples: activeSamples, traces: activeTraces, ns: model.ns, selectedTraceIndices: rendererWrapper.selectedTraceIndices)
            resetZoom()
            
        case 2:
            // 3D Crossline section: load traces for model.activeCrossline
            let traceIndices = model.crosslineMap[model.activeCrossline] ?? []
            activeTraces = traceIndices.map { model.traceHeaders[$0] }
            activeSamples = traceIndices.map { model.readTraceSamples(traceIndex: $0) }
            
            rendererWrapper.loadData(samples: activeSamples, traces: activeTraces, ns: model.ns, selectedTraceIndices: rendererWrapper.selectedTraceIndices)
            resetZoom()
            
        case 3:
            // Z-Slice time slice
            triggerZSliceExtraction()
            
        case 4:
            // 3D View mode
            refresh3DSlices()
            
        default:
            break
        }
    }
    
    private func triggerZSliceExtraction() {
        guard model.filePath != nil else { return }
        
        zSliceTask?.cancel()
        isZSliceLoading = true
        zSliceProgress = 0.0
        
        zSliceTask = Task {
            do {
                let slice = try await model.extractZSlice(sampleIndex: activeZIndex) { prog in
                    // Update progress on main thread
                    DispatchQueue.main.async {
                        self.zSliceProgress = prog
                    }
                }
                
                guard !Task.isCancelled else { return }
                
                // Format the Z-slice into a 2D plane: numInlines x numCrosslines
                // X-axis: crosslines, Y-axis: inlines
                let nCols = model.crosslines.count
                let nRows = model.inlines.count
                
                var gridSamples = [[Float]](repeating: [Float](repeating: 0.0, count: nRows), count: nCols)
                
                for c in 0..<nCols {
                    let xl = model.crosslines[c]
                    for r in 0..<nRows {
                        let il = model.inlines[r]
                        let key = (Int64(il) << 32) | Int64(xl)
                        if let traceIdx = model.gridMap[key] {
                            gridSamples[c][r] = slice[traceIdx]
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.activeZSlice = slice
                    self.activeSamples = gridSamples
                    // In Z-Slice mode, the "samples per trace" (vertical axis) is numInlines (nRows),
                    // and the horizontal axis width is numCrosslines (nCols)
                    self.rendererWrapper.loadData(samples: gridSamples, traces: [], ns: nRows, selectedTraceIndices: [])
                    self.isZSliceLoading = false
                }
                
            } catch {
                if !Task.isCancelled {
                    DispatchQueue.main.async {
                        self.isZSliceLoading = false
                    }
                }
            }
        }
    }
    
    private func update3DInlineSlice() {
        guard model.filePath != nil else { return }
        let localModel = model
        let localInline = model.activeInline
        let ns = model.ns
        
        Task.detached(priority: .userInitiated) {
            var inlineSamples = [[Float]]()
            for xl in localModel.crosslines {
                let key = (Int64(localInline) << 32) | Int64(xl)
                if let traceIdx = localModel.gridMap[key] {
                    inlineSamples.append(localModel.readTraceSamples(traceIndex: traceIdx))
                } else {
                    inlineSamples.append([Float](repeating: 0.0, count: ns))
                }
            }
            let inlineIdx = localModel.inlines.firstIndex(of: localInline) ?? 0
            
            await MainActor.run {
                guard self.model.activeInline == localInline else { return }
                self.rendererWrapper.updateInlineTexture(with: inlineSamples, ns: ns)
                self.rendererWrapper.activeInlineIndex = inlineIdx
            }
        }
    }
    
    private func update3DCrosslineSlice() {
        guard model.filePath != nil else { return }
        let localModel = model
        let localCrossline = model.activeCrossline
        let ns = model.ns
        
        Task.detached(priority: .userInitiated) {
            var crosslineSamples = [[Float]]()
            for il in localModel.inlines {
                let key = (Int64(il) << 32) | Int64(localCrossline)
                if let traceIdx = localModel.gridMap[key] {
                    crosslineSamples.append(localModel.readTraceSamples(traceIndex: traceIdx))
                } else {
                    crosslineSamples.append([Float](repeating: 0.0, count: ns))
                }
            }
            let crosslineIdx = localModel.crosslines.firstIndex(of: localCrossline) ?? 0
            
            await MainActor.run {
                guard self.model.activeCrossline == localCrossline else { return }
                self.rendererWrapper.updateCrosslineTexture(with: crosslineSamples, ns: ns)
                self.rendererWrapper.activeCrosslineIndex = crosslineIdx
            }
        }
    }
    
    private func trigger3DVolumeZSliceExtraction() {
        guard model.filePath != nil else { return }
        
        z3DSliceTask?.cancel()
        is3DZSliceLoading = true
        z3DSliceProgress = 0.0
        
        z3DSliceTask = Task {
            do {
                let slice = try await model.extractZSlice(sampleIndex: activeZIndex) { prog in
                    DispatchQueue.main.async {
                        self.z3DSliceProgress = prog
                    }
                }
                guard !Task.isCancelled else { return }
                
                let nCols = model.crosslines.count
                let nRows = model.inlines.count
                
                var gridSamples = [[Float]](repeating: [Float](repeating: 0.0, count: nRows), count: nCols)
                
                for c in 0..<nCols {
                    let xl = model.crosslines[c]
                    for r in 0..<nRows {
                        let il = model.inlines[r]
                        let key = (Int64(il) << 32) | Int64(xl)
                        if let traceIdx = model.gridMap[key] {
                            gridSamples[c][r] = slice[traceIdx]
                        }
                    }
                }
                
                guard !Task.isCancelled else { return }
                
                DispatchQueue.main.async {
                    self.rendererWrapper.updateZSliceTexture(with: gridSamples, ns: nRows)
                    self.rendererWrapper.activeZIndex = self.activeZIndex
                    self.is3DZSliceLoading = false
                }
            } catch {
                if !Task.isCancelled {
                    DispatchQueue.main.async {
                        self.is3DZSliceLoading = false
                    }
                }
            }
        }
    }
    
    private func refresh3DSlices() {
        guard model.filePath != nil else { return }
        let localModel = model
        let localInline = model.activeInline
        let localCrossline = model.activeCrossline
        let ns = model.ns
        
        Task.detached(priority: .userInitiated) {
            let inlineTraceIndices = localModel.inlineMap[localInline] ?? []
            let inlineSamples = inlineTraceIndices.map { localModel.readTraceSamples(traceIndex: $0) }
            let traces = inlineTraceIndices.map { localModel.traceHeaders[$0] }
            let inlineIdx = localModel.inlines.firstIndex(of: localInline) ?? 0
            let numInlines = localModel.inlines.count
            
            let crosslineTraceIndices = localModel.crosslineMap[localCrossline] ?? []
            let crosslineSamples = crosslineTraceIndices.map { localModel.readTraceSamples(traceIndex: $0) }
            let crosslineIdx = localModel.crosslines.firstIndex(of: localCrossline) ?? 0
            let numCrosslines = localModel.crosslines.count
            
            await MainActor.run {
                guard self.model.activeInline == localInline && self.model.activeCrossline == localCrossline else { return }
                
                self.rendererWrapper.ns = ns
                self.rendererWrapper.updateInlineTexture(with: inlineSamples, ns: ns)
                self.rendererWrapper.activeInlineIndex = inlineIdx
                self.rendererWrapper.numInlines = numInlines
                
                self.rendererWrapper.updateCrosslineTexture(with: crosslineSamples, ns: ns)
                self.rendererWrapper.activeCrosslineIndex = crosslineIdx
                self.rendererWrapper.numCrosslines = numCrosslines
                
                self.trigger3DVolumeZSliceExtraction()
            }
        }
    }
    
    // --- Camera & Zoom Zoom functions ---
    
    private func zoomIn() {
        rendererWrapper.zoomX *= 1.4
        rendererWrapper.zoomY *= 1.4
        rendererWrapper.triggerRedraw()
    }
    
    private func zoomOut() {
        rendererWrapper.zoomX = max(0.5, rendererWrapper.zoomX / 1.4)
        rendererWrapper.zoomY = max(0.5, rendererWrapper.zoomY / 1.4)
        rendererWrapper.triggerRedraw()
    }
    
    private func resetZoom() {
        rendererWrapper.zoomX = 1.0
        rendererWrapper.zoomY = 1.0
        rendererWrapper.panX = 0.0
        rendererWrapper.panY = 0.0
        rendererWrapper.triggerRedraw()
    }
    

    
    // Map screen mouse hover coordinates to trace and sample indexes
    private func updateHoverDetails(at screenPos: CGPoint) {
        guard canvasSize.width > 0 && canvasSize.height > 0 else { return }
        
        let relativeX = Float(screenPos.x / canvasSize.width)
        let relativeY = Float(screenPos.y / canvasSize.height)
        
        let zoomX = rendererWrapper.zoomX
        let zoomY = rendererWrapper.zoomY
        let panX = rendererWrapper.panX
        let panY = rendererWrapper.panY
        
        let nTraces = Float(rendererWrapper.instance.instance_numTraces())
        let nS = Float(rendererWrapper.instance.instance_ns())
        
        // Map back to texture coordinates
        let u = (relativeX - 0.5) / zoomX + 0.5 + (panX / nTraces)
        let v = (relativeY - 0.5) / zoomY + 0.5 + (panY / nS)
        
        guard u >= 0 && u <= 1 && v >= 0 && v <= 1 else {
            hoveredTraceIndex = nil
            hoveredSampleIndex = nil
            return
        }
        
        let trIdx = Int(u * nTraces)
        let smIdx = Int(v * nS)
        
        guard trIdx >= 0 && trIdx < activeSamples.count else { return }
        let traceSamples = activeSamples[trIdx]
        
        guard smIdx >= 0 && smIdx < traceSamples.count else { return }
        
        self.hoveredTraceIndex = trIdx
        self.hoveredSampleIndex = smIdx
        self.hoveredValue = traceSamples[smIdx]
        
        if viewMode == 3 {
            // Z-slice mode: gridSamples[crossline][inline]
            // X-axis: crosslines (trIdx), Y-axis: inlines (smIdx)
            if trIdx < model.crosslines.count && smIdx < model.inlines.count {
                self.hoveredCrossline = model.crosslines[trIdx]
                self.hoveredInline = model.inlines[smIdx]
            }
        } else {
            // 2D/3D profile mode: activeTraces[trIdx]
            if trIdx < activeTraces.count {
                let header = activeTraces[trIdx]
                self.hoveredInline = Int(header.inline)
                self.hoveredCrossline = Int(header.crossline)
                self.hoveredOffset = Int(header.offset)
                self.hoveredTimeMs = Double(smIdx * model.dt) / 1000.0
            }
        }
    }
    
    private func updateCoordinateOffsets(inlineOffset: Int?, crosslineOffset: Int?) {
        if let il = inlineOffset {
            model.inlineByteOffset = il
        }
        if let xl = crosslineOffset {
            model.crosslineByteOffset = xl
        }
        
        isFileLoading = true
        fileLoadingProgress = 0.0
        
        model.scanTraceHeaders(progress: { pct in
            self.fileLoadingProgress = pct
        }, completion: {
            self.isFileLoading = false
            
            // Safely reset navigation parameters to the new coordinate system
            self.model.activeInline = self.model.minInline
            self.model.activeCrossline = self.model.minCrossline
            self.inlineInput = "\(self.model.minInline)"
            self.crosslineInput = "\(self.model.minCrossline)"
            self.rendererWrapper.selectedTraceIndices.removeAll()
            self.hoveredTraceIndex = nil
            
            self.refreshActiveSlice()
        })
    }
    
    private func saveScreenshot(image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Seismic Snapshot"
        savePanel.message = "Choose a location to save the high-quality snapshot."
        
        var filename = "Seismic_Snapshot"
        if let fileName = model.fileName {
            let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            filename = baseName
        }
        
        let is3D = model.inlines.count > 0 && model.crosslines.count > 0
        if is3D {
            if viewMode == 1 {
                filename += "_Inline_\(model.activeInline)"
            } else if viewMode == 2 {
                filename += "_Crossline_\(model.activeCrossline)"
            } else if viewMode == 3 {
                filename += "_ZSlice_\(activeZIndex)"
            } else if viewMode == 4 {
                filename += "_3DView"
            }
        } else {
            filename += "_2DLine"
        }
        
        savePanel.nameFieldStringValue = "\(filename)_\(Int(Date().timeIntervalSince1970)).png"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: url)
                }
            }
        }
    }
}

// Extension to bridge variables into helper functions safely
extension MetalRendererWrapper {
    func instance_numTraces() -> Int {
        return self.instance.instance_numTraces()
    }
    func instance_ns() -> Int {
        return self.instance.instance_ns()
    }
}

// Add simple getters to MetalRenderer to avoid unsafe instance bindings
extension MetalRenderer {
    func instance_numTraces() -> Int {
        return self.numTraces
    }
    func instance_ns() -> Int {
        return self.ns
    }
}
