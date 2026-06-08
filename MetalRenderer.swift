import Foundation
import Metal
import MetalKit
import SwiftUI
import CoreImage
import simd

import AppKit

// Vertex structure for Metal rendering
struct MetalVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

struct Vertex3D {
    var position: SIMD3<Float>
    var uv: SIMD2<Float>
}

public class MetalRenderer: NSObject, MTKViewDelegate {
    public var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    
    // Pipeline states
    private var vdPipeline: MTLRenderPipelineState?
    private var wigglePipeline: MTLRenderPipelineState?
    private var vd3DPipeline: MTLRenderPipelineState?
    private var line3DPipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    
    // Textures & Buffers
    private var seismicTexture: MTLTexture?
    private var wiggleVertexBuffer: MTLBuffer?
    private var wiggleFillBuffer: MTLBuffer?
    private var wiggleVertexCount = 0
    private var wiggleFillCount = 0
    
    // 3D Slices Textures
    private var inlineTexture: MTLTexture?
    private var crosslineTexture: MTLTexture?
    private var zSliceTexture: MTLTexture?
    private var textures3DMutex = NSLock()
    
    // 3D positioning
    public var activeInlineIndex = 0
    public var activeCrosslineIndex = 0
    public var activeZIndex = 0
    public var numInlines = 1
    public var numCrosslines = 1
    
    // 3D Mode & Camera parameters
    public var is3DMode = false
    public var cameraYaw: Float = -0.5
    public var cameraPitch: Float = 0.5
    public var cameraDistance: Float = 3.0
    public var zScale3D: Float = 1.0
    public var lastViewSize: CGSize = CGSize(width: 800, height: 600)
    
    public var pan3D: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    // Render State Parameters
    public var gain: Float = 1.0
    public var colormap: Int = 1 // 1: Blue-White-Red, 0: Grayscale, 2: Rainbow, 3: High Contrast
    public var clipPercentile: Float = 0.5 // range 0.05 to 5.0
    
    // Navigation / Display modes
    public var displayMode: Int = 1 // 0: Wiggle only, 1: VD only, 2: Overlap
    public var wiggleScale: Float = 2.5
    public var wiggleColor: SIMD4<Float> = SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
    public var fillColor: SIMD4<Float> = SIMD4<Float>(0.9, 0.1, 0.1, 0.35) // semi-transparent red
    
    // Camera Zoom & Pan
    public var zoomX: Float = 1.0
    public var zoomY: Float = 1.0
    public var panX: Float = 0.0
    public var panY: Float = 0.0
    
    public var numTraces = 1
    public var ns = 1
    private var traceWidth: Float = 1.0
    private var sampleHeight: Float = 1.0
    
    private var textureMutex = NSLock()
    private var wiggleMutex = NSLock()
    
    public override init() {
        super.init()
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        setupPipelines()
    }
    
    private func setupPipelines() {
        guard let device = device else { return }
        
        let shaderSource = getFallbackShaders()
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            
            // 1. Variable Density Pipeline
            let vdDesc = MTLRenderPipelineDescriptor()
            vdDesc.vertexFunction = library.makeFunction(name: "vd_vertex")
            vdDesc.fragmentFunction = library.makeFunction(name: "vd_fragment")
            vdDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            // Enable blending for overlapping wiggle later
            vdDesc.colorAttachments[0].isBlendingEnabled = true
            vdDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            vdDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            
            vdPipeline = try device.makeRenderPipelineState(descriptor: vdDesc)
            
            // 2. Wiggle Trace Pipeline
            let wiggleDesc = MTLRenderPipelineDescriptor()
            wiggleDesc.vertexFunction = library.makeFunction(name: "wiggle_vertex")
            wiggleDesc.fragmentFunction = library.makeFunction(name: "wiggle_fragment")
            wiggleDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            // Enable blending for semi-transparent wiggle fills
            wiggleDesc.colorAttachments[0].isBlendingEnabled = true
            wiggleDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            wiggleDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            
            // Vertex layout
            let vertexDesc = MTLVertexDescriptor()
            vertexDesc.attributes[0].format = .float2 // position
            vertexDesc.attributes[0].offset = 0
            vertexDesc.attributes[0].bufferIndex = 0
            
            vertexDesc.attributes[1].format = .float4 // color
            vertexDesc.attributes[1].offset = MemoryLayout<MetalVertex>.offset(of: \.color)!
            vertexDesc.attributes[1].bufferIndex = 0
            
            vertexDesc.layouts[0].stride = MemoryLayout<MetalVertex>.stride
            wiggleDesc.vertexDescriptor = vertexDesc
            
            wigglePipeline = try device.makeRenderPipelineState(descriptor: wiggleDesc)
            
            // 3. 3D Volume Slices Pipeline
            let vd3DDesc = MTLRenderPipelineDescriptor()
            vd3DDesc.vertexFunction = library.makeFunction(name: "vertex_3d")
            vd3DDesc.fragmentFunction = library.makeFunction(name: "fragment_3d")
            vd3DDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            vd3DDesc.depthAttachmentPixelFormat = .depth32Float
            
            vd3DDesc.colorAttachments[0].isBlendingEnabled = true
            vd3DDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            vd3DDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            
            let vertex3DDesc = MTLVertexDescriptor()
            vertex3DDesc.attributes[0].format = .float3 // position
            vertex3DDesc.attributes[0].offset = 0
            vertex3DDesc.attributes[0].bufferIndex = 0
            vertex3DDesc.attributes[1].format = .float2 // uv
            vertex3DDesc.attributes[1].offset = 16 // aligned to 16 bytes due to SIMD3 layout
            vertex3DDesc.attributes[1].bufferIndex = 0
            vertex3DDesc.layouts[0].stride = 32 // aligned to 32 bytes due to SIMD3 layout
            
            vd3DDesc.vertexDescriptor = vertex3DDesc
            vd3DPipeline = try device.makeRenderPipelineState(descriptor: vd3DDesc)
            
            // 4. 3D Bounding Box Pipeline
            let line3DDesc = MTLRenderPipelineDescriptor()
            line3DDesc.vertexFunction = library.makeFunction(name: "vertex_line3d")
            line3DDesc.fragmentFunction = library.makeFunction(name: "fragment_line3d")
            line3DDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            line3DDesc.depthAttachmentPixelFormat = .depth32Float
            line3DDesc.colorAttachments[0].isBlendingEnabled = true
            line3DDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            line3DDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            
            line3DPipeline = try device.makeRenderPipelineState(descriptor: line3DDesc)
            
            // Depth State
            let depthDesc = MTLDepthStencilDescriptor()
            depthDesc.depthCompareFunction = .lessEqual
            depthDesc.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depthDesc)
            
        } catch {
            print("Metal Pipeline Compilation Error: \(error)")
        }
    }
    
    // Updates the VD Texture from trace data
    public func updateTexture(with samples: [[Float]], ns: Int) {
        guard let device = device, samples.count > 0, ns > 0 else { return }
        
        let width = samples.count
        let height = ns
        
        self.numTraces = width
        self.ns = height
        
        // Compute max amplitude for normalization
        var maxAmplitude: Float = 0.0
        for t in 0..<width {
            let trace = samples[t]
            let count = min(height, trace.count)
            for s in 0..<count {
                let absVal = abs(trace[s])
                if absVal > maxAmplitude {
                    maxAmplitude = absVal
                }
            }
        }
        if maxAmplitude == 0.0 { maxAmplitude = 1.0 }
        
        // Flatten samples array and normalize
        var flatData = [Float](repeating: 0.0, count: width * height)
        for t in 0..<width {
            let trace = samples[t]
            let count = min(height, trace.count)
            for s in 0..<count {
                flatData[t + s * width] = trace[s] / maxAmplitude
            }
        }
        
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead]
        
        textureMutex.lock()
        let tex = device.makeTexture(descriptor: texDesc)
        tex?.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: flatData,
            bytesPerRow: width * MemoryLayout<Float>.stride
        )
        self.seismicTexture = tex
        textureMutex.unlock()
    }
    
    public func updateInlineTexture(with samples: [[Float]], ns: Int, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let tex = self.createTexture(from: samples, height: ns)
            self.textures3DMutex.lock()
            self.inlineTexture = tex
            self.textures3DMutex.unlock()
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    public func updateCrosslineTexture(with samples: [[Float]], ns: Int, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let tex = self.createTexture(from: samples, height: ns)
            self.textures3DMutex.lock()
            self.crosslineTexture = tex
            self.textures3DMutex.unlock()
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    public func updateZSliceTexture(with samples: [[Float]], ns: Int, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let height = samples.first?.count ?? 1
            let tex = self.createTexture(from: samples, height: height)
            self.textures3DMutex.lock()
            self.zSliceTexture = tex
            self.textures3DMutex.unlock()
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    private func createTexture(from samples: [[Float]], height: Int) -> MTLTexture? {
        guard let device = device, samples.count > 0, height > 0 else { return nil }
        
        let width = samples.count
        
        var maxAmplitude: Float = 0.0
        for t in 0..<width {
            let trace = samples[t]
            let count = min(height, trace.count)
            for s in 0..<count {
                let absVal = abs(trace[s])
                if absVal > maxAmplitude {
                    maxAmplitude = absVal
                }
            }
        }
        if maxAmplitude == 0.0 { maxAmplitude = 1.0 }
        
        var flatData = [Float](repeating: 0.0, count: width * height)
        for t in 0..<width {
            let trace = samples[t]
            let count = min(height, trace.count)
            for s in 0..<count {
                flatData[t + s * width] = trace[s] / maxAmplitude
            }
        }
        
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead]
        
        let tex = device.makeTexture(descriptor: texDesc)
        tex?.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: flatData,
            bytesPerRow: width * MemoryLayout<Float>.stride
        )
        return tex
    }
    
    // Updates the Wiggle Geometry (Lines & Fills)
    public func updateWiggleGeometry(samples: [[Float]], ns: Int, selectedTraceIndices: Set<Int> = []) {
        guard let device = device, samples.count > 0, ns > 0 else { return }
        
        // Prevent massive memory allocations for wiggle traces on very large lines
        // A full 2D line (e.g. 8000 traces * 11000 samples = ~90M points) would require > 10GB of GPU buffers.
        let totalSamples = samples.count * ns
        if totalSamples > 2_500_000 {
            wiggleMutex.lock()
            self.wiggleVertexCount = 0
            self.wiggleFillCount = 0
            self.wiggleVertexBuffer = nil
            self.wiggleFillBuffer = nil
            wiggleMutex.unlock()
            return
        }
        
        // Compute max amplitude of current active samples
        var maxAmplitude: Float = 0.0
        for t in 0..<samples.count {
            let trace = samples[t]
            let count = min(ns, trace.count)
            for s in 0..<count {
                let absVal = abs(trace[s])
                if absVal > maxAmplitude {
                    maxAmplitude = absVal
                }
            }
        }
        if maxAmplitude == 0.0 { maxAmplitude = 1.0 }
        
        var lineVertices = [MetalVertex]()
        var fillVertices = [MetalVertex]()
        
        let count = samples.count
        let scale = wiggleScale
        
        // Reserve memory roughly
        lineVertices.reserveCapacity(count * ns * 2)
        fillVertices.reserveCapacity(count * ns * 6)
        
        for i in 0..<count {
            let trace = samples[i]
            let tX = Float(i)
            let isSelected = selectedTraceIndices.contains(i)
            let color = isSelected ? SIMD4<Float>(0.0, 0.55, 1.0, 1.0) : wiggleColor
            
            // 1. Generate Line Segments
            for j in 0..<(ns - 1) {
                guard j < trace.count, j + 1 < trace.count else { continue }
                let val1 = trace[j] / maxAmplitude
                let val2 = trace[j + 1] / maxAmplitude
                
                let p1 = SIMD2<Float>(tX + val1 * scale, Float(j))
                let p2 = SIMD2<Float>(tX + val2 * scale, Float(j + 1))
                
                lineVertices.append(MetalVertex(position: p1, color: color))
                lineVertices.append(MetalVertex(position: p2, color: color))
            }
            
            // 2. Generate Fill Triangles for Positive Areas
            for j in 0..<(ns - 1) {
                guard j < trace.count, j + 1 < trace.count else { continue }
                let val1 = trace[j] / maxAmplitude
                let val2 = trace[j + 1] / maxAmplitude
                
                let y1 = Float(j)
                let y2 = Float(j + 1)
                
                // If both samples are positive, draw a filled quad (2 triangles)
                if val1 > 0 && val2 > 0 {
                    let vZero1 = SIMD2<Float>(tX, y1)
                    let vPeak1 = SIMD2<Float>(tX + val1 * scale, y1)
                    let vZero2 = SIMD2<Float>(tX, y2)
                    let vPeak2 = SIMD2<Float>(tX + val2 * scale, y2)
                    
                    // Triangle 1: Zero1 -> Peak1 -> Peak2
                    fillVertices.append(MetalVertex(position: vZero1, color: fillColor))
                    fillVertices.append(MetalVertex(position: vPeak1, color: fillColor))
                    fillVertices.append(MetalVertex(position: vPeak2, color: fillColor))
                    
                    // Triangle 2: Zero1 -> Peak2 -> Zero2
                    fillVertices.append(MetalVertex(position: vZero1, color: fillColor))
                    fillVertices.append(MetalVertex(position: vPeak2, color: fillColor))
                    fillVertices.append(MetalVertex(position: vZero2, color: fillColor))
                }
                // Handle zero crossings: if one is positive and the other negative
                else if val1 > 0 && val2 <= 0 {
                    // Interpolate crossing point
                    let t = val1 / (val1 - val2)
                    let yCross = y1 + t * (y2 - y1)
                    
                    let vZero1 = SIMD2<Float>(tX, y1)
                    let vPeak1 = SIMD2<Float>(tX + val1 * scale, y1)
                    let vCross = SIMD2<Float>(tX, yCross)
                    
                    fillVertices.append(MetalVertex(position: vZero1, color: fillColor))
                    fillVertices.append(MetalVertex(position: vPeak1, color: fillColor))
                    fillVertices.append(MetalVertex(position: vCross, color: fillColor))
                }
                else if val1 <= 0 && val2 > 0 {
                    // Interpolate crossing point
                    let t = -val1 / (val2 - val1)
                    let yCross = y1 + t * (y2 - y1)
                    
                    let vCross = SIMD2<Float>(tX, yCross)
                    let vPeak2 = SIMD2<Float>(tX + val2 * scale, y2)
                    let vZero2 = SIMD2<Float>(tX, y2)
                    
                    fillVertices.append(MetalVertex(position: vCross, color: fillColor))
                    fillVertices.append(MetalVertex(position: vPeak2, color: fillColor))
                    fillVertices.append(MetalVertex(position: vZero2, color: fillColor))
                }
            }
        }
        
        wiggleMutex.lock()
        self.wiggleVertexCount = lineVertices.count
        self.wiggleFillCount = fillVertices.count
        
        if lineVertices.count > 0 {
            self.wiggleVertexBuffer = device.makeBuffer(
                bytes: lineVertices,
                length: lineVertices.count * MemoryLayout<MetalVertex>.stride,
                options: .storageModeShared
            )
        } else {
            self.wiggleVertexBuffer = nil
        }
        
        if fillVertices.count > 0 {
            self.wiggleFillBuffer = device.makeBuffer(
                bytes: fillVertices,
                length: fillVertices.count * MemoryLayout<MetalVertex>.stride,
                options: .storageModeShared
            )
        } else {
            self.wiggleFillBuffer = nil
        }
        wiggleMutex.unlock()
    }
    
    // MTKView Delegate Methods
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    public func draw(in view: MTKView) {
        self.lastViewSize = view.bounds.size
        
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandQueue = commandQueue else { return }
        
        if is3DMode {
            renderPassDesc.depthAttachment.clearDepth = 1.0
            renderPassDesc.depthAttachment.loadAction = .clear
            renderPassDesc.depthAttachment.storeAction = .dontCare
        }
        
        // Use a clear dark background color
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.1, alpha: 1.0)
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            commandBuffer.commit()
            return
        }
        
        if is3DMode {
            guard let vd3DPipeline = vd3DPipeline, let line3DPipeline = line3DPipeline, let depthState = depthState else {
                renderEncoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }
            
            renderEncoder.setDepthStencilState(depthState)
            
            // 1. Calculate MVP matrix
            let aspect = Float(view.bounds.width / view.bounds.height)
            let projectionMatrix = MatrixMath.perspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: aspect, near: 0.1, far: 20.0)
            
            let cosP = cos(cameraPitch)
            let sinP = sin(cameraPitch)
            let cosY = cos(cameraYaw)
            let sinY = sin(cameraYaw)
            
            let eyeX = cameraDistance * cosP * sinY
            let eyeY = cameraDistance * sinP
            let eyeZ = cameraDistance * cosP * cosY
            
            let eye = SIMD3<Float>(eyeX, eyeY, eyeZ) + pan3D
            let center = pan3D
            let up = SIMD3<Float>(0.0, 1.0, 0.0)
            
            let maxDim = Float(max(max(numCrosslines, numInlines), ns))
            let normX = maxDim > 0 ? Float(numCrosslines) / maxDim : 1.0
            let normY = maxDim > 0 ? Float(ns) / maxDim : 1.0
            let normZ = maxDim > 0 ? Float(numInlines) / maxDim : 1.0
            
            let scaleMatrix = MatrixMath.scale(x: normX * zoomX, y: normY * zoomY * zScale3D, z: normZ * zoomX)
            
            let viewMatrix = MatrixMath.lookAt(eye: eye, center: center, up: up)
            let mvpMatrix = projectionMatrix * viewMatrix * scaleMatrix
            
            // 2. Draw 3D Bounding Box (Wireframe)
            renderEncoder.setRenderPipelineState(line3DPipeline)
            
            var lineUniforms = struct_Line3DUniforms(
                mvpMatrix: mvpMatrix,
                color: SIMD4<Float>(0.4, 0.4, 0.4, 1.0)
            )
            renderEncoder.setVertexBytes(&lineUniforms, length: MemoryLayout<struct_Line3DUniforms>.size, index: 0)
            renderEncoder.setFragmentBytes(&lineUniforms, length: MemoryLayout<struct_Line3DUniforms>.size, index: 0)
            
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 24)
            
            // 3. Draw Slices
            renderEncoder.setRenderPipelineState(vd3DPipeline)
            
            var uniforms3D = struct_Uniforms3D(
                mvpMatrix: mvpMatrix,
                gain: gain,
                colormap: Int32(colormap),
                clipVal: clipPercentile,
                padding: 0.0
            )
            
            renderEncoder.setVertexBytes(&uniforms3D, length: MemoryLayout<struct_Uniforms3D>.size, index: 1)
            renderEncoder.setFragmentBytes(&uniforms3D, length: MemoryLayout<struct_Uniforms3D>.size, index: 0)
            
            textures3DMutex.lock()
            
            // Draw Inline Plane (Constant Z)
            if let inlineTex = inlineTexture, numInlines > 0 {
                let zNorm = (Float(activeInlineIndex) / Float(max(1, numInlines - 1))) * 2.0 - 1.0
                var inlineVertices = [
                    Vertex3D(position: SIMD3<Float>(-1.0, -1.0, zNorm), uv: SIMD2<Float>(0.0, 1.0)),
                    Vertex3D(position: SIMD3<Float>(1.0, -1.0, zNorm), uv: SIMD2<Float>(1.0, 1.0)),
                    Vertex3D(position: SIMD3<Float>(-1.0, 1.0, zNorm), uv: SIMD2<Float>(0.0, 0.0)),
                    Vertex3D(position: SIMD3<Float>(1.0, 1.0, zNorm), uv: SIMD2<Float>(1.0, 0.0))
                ]
                renderEncoder.setVertexBytes(&inlineVertices, length: MemoryLayout<Vertex3D>.stride * 4, index: 0)
                renderEncoder.setFragmentTexture(inlineTex, index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            
            // Draw Crossline Plane (Constant X)
            if let crosslineTex = crosslineTexture, numCrosslines > 0 {
                let xNorm = (Float(activeCrosslineIndex) / Float(max(1, numCrosslines - 1))) * 2.0 - 1.0
                var crosslineVertices = [
                    Vertex3D(position: SIMD3<Float>(xNorm, -1.0, -1.0), uv: SIMD2<Float>(0.0, 1.0)),
                    Vertex3D(position: SIMD3<Float>(xNorm, -1.0, 1.0), uv: SIMD2<Float>(1.0, 1.0)),
                    Vertex3D(position: SIMD3<Float>(xNorm, 1.0, -1.0), uv: SIMD2<Float>(0.0, 0.0)),
                    Vertex3D(position: SIMD3<Float>(xNorm, 1.0, 1.0), uv: SIMD2<Float>(1.0, 0.0))
                ]
                renderEncoder.setVertexBytes(&crosslineVertices, length: MemoryLayout<Vertex3D>.stride * 4, index: 0)
                renderEncoder.setFragmentTexture(crosslineTex, index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            
            // Draw Z-Slice Plane (Constant Y)
            if let zTex = zSliceTexture, ns > 0 {
                let yNorm = 1.0 - (Float(activeZIndex) / Float(max(1, ns - 1))) * 2.0
                var zVertices = [
                    Vertex3D(position: SIMD3<Float>(-1.0, yNorm, -1.0), uv: SIMD2<Float>(0.0, 0.0)),
                    Vertex3D(position: SIMD3<Float>(1.0, yNorm, -1.0), uv: SIMD2<Float>(1.0, 0.0)),
                    Vertex3D(position: SIMD3<Float>(-1.0, yNorm, 1.0), uv: SIMD2<Float>(0.0, 1.0)),
                    Vertex3D(position: SIMD3<Float>(1.0, yNorm, 1.0), uv: SIMD2<Float>(1.0, 1.0))
                ]
                renderEncoder.setVertexBytes(&zVertices, length: MemoryLayout<Vertex3D>.stride * 4, index: 0)
                renderEncoder.setFragmentTexture(zTex, index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            
            textures3DMutex.unlock()
            
        } else {
            // 1. Draw Variable Density (Seismic Canvas)
            if (displayMode == 1 || displayMode == 2), let vdPipeline = vdPipeline {
                textureMutex.lock()
                if let tex = seismicTexture {
                    renderEncoder.setRenderPipelineState(vdPipeline)
                    renderEncoder.setFragmentTexture(tex, index: 0)
                    
                    // Calculate scale and translation for panning/zooming in texture coordinates
                    let scaleU = 1.0 / zoomX
                    let translateU = 0.5 * (1.0 - 1.0 / zoomX) + (panX / Float(numTraces))
                    let scaleV = 1.0 / zoomY
                    let translateV = 0.5 * (1.0 - 1.0 / zoomY) + (panY / Float(ns))
                    
                    var vdUniforms = struct_VDUniforms(
                        gain: gain,
                        colormap: Int32(colormap),
                        clipVal: clipPercentile,
                        scale: SIMD2<Float>(scaleU, scaleV),
                        translate: SIMD2<Float>(translateU, translateV)
                    )
                    
                    renderEncoder.setFragmentBytes(&vdUniforms, length: MemoryLayout<struct_VDUniforms>.size, index: 0)
                    renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
                textureMutex.unlock()
            }
            
            // 2. Draw Wiggle Traces (Lines & Fills)
            if (displayMode == 0 || displayMode == 2), let wigglePipeline = wigglePipeline {
                wiggleMutex.lock()
                
                // Coordinate transformations to map data coords to NDC
                // Data space: [0, numTraces] x [0, ns]
                // NDC space: [-1, 1] x [1, -1] (top is 1, bottom is -1)
                let scaleX = 2.0 * zoomX / Float(numTraces)
                let translateX = -zoomX * (1.0 + 2.0 * panX / Float(numTraces))
                let scaleY = -2.0 * zoomY / Float(ns)
                let translateY = zoomY * (1.0 + 2.0 * panY / Float(ns))
                
                var wiggleUniforms = struct_WiggleUniforms(
                    color: wiggleColor,
                    scale: SIMD2<Float>(scaleX, scaleY),
                    translate: SIMD2<Float>(translateX, translateY)
                )
                
                renderEncoder.setRenderPipelineState(wigglePipeline)
                renderEncoder.setVertexBytes(&wiggleUniforms, length: MemoryLayout<struct_WiggleUniforms>.size, index: 1)
                renderEncoder.setFragmentBytes(&wiggleUniforms, length: MemoryLayout<struct_WiggleUniforms>.size, index: 1)
                
                // Draw fills first
                if let fillBuf = wiggleFillBuffer, wiggleFillCount > 0 {
                    renderEncoder.setVertexBuffer(fillBuf, offset: 0, index: 0)
                    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: wiggleFillCount)
                }
                
                // Draw wiggle lines
                if let lineBuf = wiggleVertexBuffer, wiggleVertexCount > 0 {
                    renderEncoder.setVertexBuffer(lineBuf, offset: 0, index: 0)
                    renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: wiggleVertexCount)
                }
                
                wiggleMutex.unlock()
            }
        }
        
        renderEncoder.endEncoding()
        
        let textureToCapture = drawable.texture
        let captureRequested = (view as? InteractiveMTKView)?.renderer?.captureScreenshot ?? false
        let rendererWrapper = (view as? InteractiveMTKView)?.renderer
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        if captureRequested {
            DispatchQueue.main.async {
                rendererWrapper?.captureScreenshot = false
            }
            
            commandBuffer.waitUntilCompleted()
            
            let width = textureToCapture.width
            let height = textureToCapture.height
            let rowBytes = width * 4
            var buffer = [UInt8](repeating: 0, count: rowBytes * height)
            let region = MTLRegionMake2D(0, 0, width, height)
            
            textureToCapture.getBytes(&buffer, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            let data = Data(bytes: &buffer, count: buffer.count)
            
            if let provider = CGDataProvider(data: data as CFData),
               let cgImage = CGImage(width: width,
                                     height: height,
                                     bitsPerComponent: 8,
                                     bitsPerPixel: 32,
                                     bytesPerRow: rowBytes,
                                     space: colorSpace,
                                     bitmapInfo: bitmapInfo,
                                     provider: provider,
                                     decode: nil,
                                     shouldInterpolate: false,
                                     intent: .defaultIntent) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
                DispatchQueue.main.async {
                    rendererWrapper?.onScreenshotReady?(nsImage)
                }
            }
        }
    }
    
    public func exportFullSeismicImage(completion: @escaping (NSImage?) -> Void) {
        guard let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            completion(nil)
            return
        }
        
        let maxWidth: Float = 16384.0
        let maxHeight: Float = 16384.0
        let windowAspect = Float(lastViewSize.width / max(1.0, lastViewSize.height))
        let desiredAspect = windowAspect * (zoomX / zoomY)
        
        var targetHeight = Float(max(ns, 2000))
        var targetWidth = targetHeight * desiredAspect
        
        if targetWidth > maxWidth {
            let scale = maxWidth / targetWidth
            targetWidth *= scale
            targetHeight *= scale
        }
        
        if targetHeight > maxHeight {
            let scale = maxHeight / targetHeight
            targetWidth *= scale
            targetHeight *= scale
        }
        
        let texWidth = max(1, Int(targetWidth))
        let texHeight = max(1, Int(targetHeight))
        
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: texWidth, height: texHeight, mipmapped: false)
        texDesc.usage = MTLTextureUsage(rawValue: MTLTextureUsage.renderTarget.rawValue | MTLTextureUsage.shaderRead.rawValue)
        #if targetEnvironment(macCatalyst) || os(macOS)
        texDesc.storageMode = .managed
        #else
        texDesc.storageMode = .shared
        #endif
        
        guard let offscreenTexture = device?.makeTexture(descriptor: texDesc) else {
            completion(nil)
            return
        }
        
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = offscreenTexture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.1, alpha: 1.0)
        passDesc.colorAttachments[0].storeAction = .store
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            commandBuffer.commit()
            completion(nil)
            return
        }
        
        if (displayMode == 1 || displayMode == 2), let vdPipeline = vdPipeline {
            textureMutex.lock()
            if let tex = seismicTexture {
                renderEncoder.setRenderPipelineState(vdPipeline)
                renderEncoder.setFragmentTexture(tex, index: 0)
                
                var vdUniforms = struct_VDUniforms(
                    gain: gain,
                    colormap: Int32(colormap),
                    clipVal: clipPercentile,
                    scale: SIMD2<Float>(1.0, 1.0),
                    translate: SIMD2<Float>(0.0, 0.0)
                )
                
                renderEncoder.setFragmentBytes(&vdUniforms, length: MemoryLayout<struct_VDUniforms>.size, index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            textureMutex.unlock()
        }
        
        if (displayMode == 0 || displayMode == 2), let wigglePipeline = wigglePipeline {
            wiggleMutex.lock()
            
            let scaleX = 2.0 / Float(numTraces)
            let translateX: Float = -1.0
            let scaleY = -2.0 / Float(ns)
            let translateY: Float = 1.0
            
            var wiggleUniforms = struct_WiggleUniforms(
                color: wiggleColor,
                scale: SIMD2<Float>(scaleX, scaleY),
                translate: SIMD2<Float>(translateX, translateY)
            )
            
            renderEncoder.setRenderPipelineState(wigglePipeline)
            renderEncoder.setVertexBytes(&wiggleUniforms, length: MemoryLayout<struct_WiggleUniforms>.size, index: 1)
            renderEncoder.setFragmentBytes(&wiggleUniforms, length: MemoryLayout<struct_WiggleUniforms>.size, index: 1)
            
            if let fillBuf = wiggleFillBuffer, wiggleFillCount > 0 {
                renderEncoder.setVertexBuffer(fillBuf, offset: 0, index: 0)
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: wiggleFillCount)
            }
            
            if let lineBuf = wiggleVertexBuffer, wiggleVertexCount > 0 {
                renderEncoder.setVertexBuffer(lineBuf, offset: 0, index: 0)
                renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: wiggleVertexCount)
            }
            
            wiggleMutex.unlock()
        }
        
        renderEncoder.endEncoding()
        
        #if targetEnvironment(macCatalyst) || os(macOS)
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.synchronize(resource: offscreenTexture)
            blitEncoder.endEncoding()
        }
        #endif
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let rowBytes = texWidth * 4
        var buffer = [UInt8](repeating: 0, count: rowBytes * texHeight)
        let region = MTLRegionMake2D(0, 0, texWidth, texHeight)
        
        offscreenTexture.getBytes(&buffer, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let data2 = Data(bytes: &buffer, count: buffer.count)
        
        if let provider = CGDataProvider(data: data2 as CFData),
           let cgImage = CGImage(width: texWidth, height: texHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: texWidth, height: texHeight))
            DispatchQueue.main.async {
                completion(nsImage)
            }
        } else {
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }
    
    private func getFallbackShaders() -> String {
        return """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexInput {
            float2 position [[attribute(0)]];
            float4 color    [[attribute(1)]];
        };
        struct VertexOutput {
            float4 position [[position]];
            float4 color;
            float2 uv;
        };
        vertex VertexOutput vd_vertex(uint vertexID [[vertex_id]]) {
            float2 positions[4] = { float2(-1.0, 1.0), float2(1.0, 1.0), float2(-1.0, -1.0), float2(1.0, -1.0) };
            float2 uvs[4] = { float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0), float2(1.0, 1.0) };
            VertexOutput out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.uv = uvs[vertexID];
            out.color = float4(1.0);
            return out;
        }
        struct VDUniforms {
            float gain;
            int colormap;
            float clipVal;
            float2 scale;
            float2 translate;
        };
        fragment float4 vd_fragment(VertexOutput in [[stage_in]],
                                    texture2d<float> seismicTex [[texture(0)]],
                                    constant VDUniforms& uniforms [[buffer(0)]]) {
            float2 uv = in.uv * uniforms.scale + uniforms.translate;
            if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return float4(0.08, 0.09, 0.1, 1.0);
            constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
            float sampleVal = seismicTex.sample(textureSampler, uv).r;
            float value = sampleVal * uniforms.gain;
            value = clamp(value, -uniforms.clipVal, uniforms.clipVal) / uniforms.clipVal;
            if (uniforms.colormap == 0) {
                float gray = (value + 1.0) * 0.5;
                return float4(gray, gray, gray, 1.0);
            } else if (uniforms.colormap == 1) {
                if (value < 0.0) return float4(1.0 - (-value), 1.0 - (-value), 1.0, 1.0);
                else return float4(1.0, 1.0 - value, 1.0 - value, 1.0);
            } else if (uniforms.colormap == 2) {
                float t = (value + 1.0) * 0.5;
                return float4(clamp(sin(t*3.14),0.0,1.0), clamp(sin((t-0.33)*3.14),0.0,1.0), clamp(sin((t-0.66)*3.14),0.0,1.0), 1.0);
            } else {
                if (value < 0.0) return float4(pow(1.0 - (-value), 3.0), pow(1.0 - (-value), 2.0), 0.6 + 0.4 * (1.0 - (-value)), 1.0);
                else return float4(0.6 + 0.4 * (1.0 - value), pow(1.0 - value, 2.0), pow(1.0 - value, 3.0), 1.0);
            }
        }
        struct WiggleUniforms {
            float4 color;
            float2 scale;
            float2 translate;
        };
        vertex VertexOutput wiggle_vertex(VertexInput in [[stage_in]], constant WiggleUniforms& uniforms [[buffer(1)]]) {
            VertexOutput out;
            out.position = float4(in.position * uniforms.scale + uniforms.translate, 0.0, 1.0);
            out.color = in.color;
            out.uv = float2(0.0);
            return out;
        }
        fragment float4 wiggle_fragment(VertexOutput in [[stage_in]], constant WiggleUniforms& uniforms [[buffer(1)]]) {
            if (in.color.a > 0.0) return in.color;
            return uniforms.color;
        }
        
        // --- 3D Shaders ---
        struct Uniforms3D {
            float4x4 mvpMatrix;
            float gain;
            int colormap;
            float clipVal;
            float padding;
        };
        
        struct Vertex3DInput {
            float3 position [[attribute(0)]];
            float2 uv       [[attribute(1)]];
        };
        
        struct Vertex3DOutput {
            float4 position [[position]];
            float2 uv;
        };
        
        vertex Vertex3DOutput vertex_3d(Vertex3DInput in [[stage_in]], constant Uniforms3D& uniforms [[buffer(1)]]) {
            Vertex3DOutput out;
            out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
            out.uv = in.uv;
            return out;
        }
        
        fragment float4 fragment_3d(Vertex3DOutput in [[stage_in]],
                                    texture2d<float> sliceTex [[texture(0)]],
                                    constant Uniforms3D& uniforms [[buffer(0)]]) {
            constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
            float sampleVal = sliceTex.sample(textureSampler, in.uv).r;
            float value = sampleVal * uniforms.gain;
            value = clamp(value, -uniforms.clipVal, uniforms.clipVal) / uniforms.clipVal;
            
            if (uniforms.colormap == 0) {
                float gray = (value + 1.0) * 0.5;
                return float4(gray, gray, gray, 1.0);
            } else if (uniforms.colormap == 1) {
                if (value < 0.0) return float4(1.0 - (-value), 1.0 - (-value), 1.0, 1.0);
                else return float4(1.0, 1.0 - value, 1.0 - value, 1.0);
            } else if (uniforms.colormap == 2) {
                float t = (value + 1.0) * 0.5;
                return float4(clamp(sin(t*3.14),0.0,1.0), clamp(sin((t-0.33)*3.14),0.0,1.0), clamp(sin((t-0.66)*3.14),0.0,1.0), 1.0);
            } else {
                if (value < 0.0) return float4(pow(1.0 - (-value), 3.0), pow(1.0 - (-value), 2.0), 0.6 + 0.4 * (1.0 - (-value)), 1.0);
                else return float4(0.6 + 0.4 * (1.0 - value), pow(1.0 - value, 2.0), pow(1.0 - value, 3.0), 1.0);
            }
        }
        
        // --- 3D Bounding Box Shaders ---
        struct Line3DUniforms {
            float4x4 mvpMatrix;
            float4 color;
        };
        
        vertex Vertex3DOutput vertex_line3d(uint vertexID [[vertex_id]], constant Line3DUniforms& uniforms [[buffer(0)]]) {
            float3 positions[8] = {
                float3(-1.0, -1.0, -1.0), float3(1.0, -1.0, -1.0),
                float3(1.0, 1.0, -1.0), float3(-1.0, 1.0, -1.0),
                float3(-1.0, -1.0, 1.0), float3(1.0, -1.0, 1.0),
                float3(1.0, 1.0, 1.0), float3(-1.0, 1.0, 1.0)
            };
            int indices[24] = {
                0, 1, 1, 2, 2, 3, 3, 0, // Back face
                4, 5, 5, 6, 6, 7, 7, 4, // Front face
                0, 4, 1, 5, 2, 6, 3, 7  // Connecting lines
            };
            Vertex3DOutput out;
            float3 pos = positions[indices[vertexID]];
            out.position = uniforms.mvpMatrix * float4(pos, 1.0);
            out.uv = float2(0.0);
            return out;
        }
        
        fragment float4 fragment_line3d(Vertex3DOutput in [[stage_in]], constant Line3DUniforms& uniforms [[buffer(0)]]) {
            return uniforms.color;
        }
        """;
    }
}

// C-compatible struct layout mirrors for shader buffer passing
struct struct_VDUniforms {
    var gain: Float
    var colormap: Int32
    var clipVal: Float
    var scale: SIMD2<Float>
    var translate: SIMD2<Float>
}

struct struct_WiggleUniforms {
    var color: SIMD4<Float>
    var scale: SIMD2<Float>
    var translate: SIMD2<Float>
}

struct struct_Uniforms3D {
    var mvpMatrix: simd_float4x4
    var gain: Float
    var colormap: Int32
    var clipVal: Float
    var padding: Float = 0.0
}

struct struct_Line3DUniforms {
    var mvpMatrix: simd_float4x4
    var color: SIMD4<Float>
}

struct MatrixMath {
    static func perspective(fovyRadians: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1.0 / tan(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        let ws = (near * far) / (near - far)
        
        return simd_float4x4(
            SIMD4<Float>(xs,  0,  0,  0),
            SIMD4<Float>( 0, ys,  0,  0),
            SIMD4<Float>( 0,  0, zs, -1),
            SIMD4<Float>( 0,  0, ws,  0)
        )
    }
    
    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        
        return simd_float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        )
    }
    
    static func scale(x: Float, y: Float, z: Float) -> simd_float4x4 {
        return simd_float4x4(
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}

// Custom subclass of MTKView to capture scroll, pan, and pinch events on macOS
public class InteractiveMTKView: MTKView {
    public var renderer: MetalRendererWrapper?
    
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    private var dragStartYaw: Float = 0.0
    private var dragStartPitch: Float = 0.0
    private var dragStartPan3D: SIMD3<Float>?
    private var dragStartPoint: NSPoint? = nil
    private var dragStartPanX: Float = 0.0
    private var dragStartPanY: Float = 0.0
    private var didDrag = false
    
    public override func scrollWheel(with event: NSEvent) {
        guard let renderer = renderer else {
            super.scrollWheel(with: event)
            return
        }
        
        if renderer.is3DMode {
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command) {
                let zoomFactor: Float = event.scrollingDeltaY > 0 ? 1.05 : 0.95
                if event.modifierFlags.contains(.shift) {
                    renderer.zoomX = max(0.1, min(200.0, renderer.zoomX * zoomFactor))
                } else if event.modifierFlags.contains(.command) {
                    renderer.zoomY = max(0.1, min(200.0, renderer.zoomY * zoomFactor))
                }
                renderer.triggerRedraw()
            } else {
                let zoomSensitivity: Float = 0.05
                let delta = Float(event.scrollingDeltaY)
                let dy = event.hasPreciseScrollingDeltas ? delta * 0.1 : delta
                renderer.cameraDistance = max(1.0, min(10.0, renderer.cameraDistance - dy * zoomSensitivity))
                renderer.triggerRedraw()
            }
        } else {
            let zoomFactor: Float = event.scrollingDeltaY > 0 ? 1.05 : 0.95
            if event.modifierFlags.contains(.shift) {
                renderer.zoomX = max(0.1, min(200.0, renderer.zoomX * zoomFactor))
            } else if event.modifierFlags.contains(.command) {
                renderer.zoomY = max(0.1, min(200.0, renderer.zoomY * zoomFactor))
            } else {
                renderer.zoomX = max(0.1, min(200.0, renderer.zoomX * zoomFactor))
                renderer.zoomY = max(0.1, min(200.0, renderer.zoomY * zoomFactor))
            }
            renderer.triggerRedraw()
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard let renderer = renderer else {
            super.mouseDown(with: event)
            return
        }
        let localPoint = self.convert(event.locationInWindow, from: nil)
        dragStartPoint = localPoint
        
        if renderer.is3DMode {
            dragStartYaw = renderer.cameraYaw
            dragStartPitch = renderer.cameraPitch
            dragStartPan3D = renderer.pan3D
        } else {
            dragStartPanX = renderer.panX
            dragStartPanY = renderer.panY
        }
        didDrag = false
    }
    
    public override func mouseDragged(with event: NSEvent) {
        guard let renderer = renderer, let startPoint = dragStartPoint else {
            super.mouseDragged(with: event)
            return
        }
        
        let currentPoint = self.convert(event.locationInWindow, from: nil)
        let deltaX = Float(currentPoint.x - startPoint.x)
        let deltaY = Float(currentPoint.y - startPoint.y)
        
        if abs(deltaX) > 2 || abs(deltaY) > 2 {
            didDrag = true
        }
        
        if renderer.is3DMode {
            let sensitivity: Float = 0.007
            renderer.cameraYaw = dragStartYaw + deltaX * sensitivity
            renderer.cameraPitch = max(-1.4, min(1.4, dragStartPitch - deltaY * sensitivity))
            renderer.triggerRedraw()
        } else {
            let viewWidth = Float(self.bounds.width)
            let viewHeight = Float(self.bounds.height)
            let numTraces = Float(renderer.instance.numTraces)
            let ns = Float(renderer.instance.ns)
            
            if numTraces > 0 && ns > 0 && viewWidth > 0 && viewHeight > 0 {
                let traceDelta = deltaX * (numTraces / (viewWidth * renderer.zoomX))
                renderer.panX = dragStartPanX - traceDelta
                
                let sampleDelta = deltaY * (ns / (viewHeight * renderer.zoomY))
                renderer.panY = dragStartPanY + sampleDelta
                
                renderer.triggerRedraw()
            }
        }
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        guard let renderer = renderer else {
            super.rightMouseDown(with: event)
            return
        }
        let localPoint = self.convert(event.locationInWindow, from: nil)
        dragStartPoint = localPoint
        if renderer.is3DMode {
            dragStartPan3D = renderer.pan3D
            didDrag = false
        }
    }
    
    public override func rightMouseDragged(with event: NSEvent) {
        guard let renderer = renderer, let startPoint = dragStartPoint, let startPan = dragStartPan3D else {
            super.rightMouseDragged(with: event)
            return
        }
        let currentPoint = self.convert(event.locationInWindow, from: nil)
        let deltaX = Float(currentPoint.x - startPoint.x)
        let deltaY = Float(currentPoint.y - startPoint.y)
        
        if renderer.is3DMode {
            let sensitivity: Float = 0.005 * renderer.cameraDistance
            let cosY = cos(renderer.cameraYaw)
            let sinY = sin(renderer.cameraYaw)
            
            let right = SIMD3<Float>(cosY, 0.0, -sinY)
            let up = SIMD3<Float>(0.0, 1.0, 0.0)
            
            renderer.pan3D = startPan - right * (deltaX * sensitivity) + up * (deltaY * sensitivity)
            renderer.triggerRedraw()
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        guard let renderer = renderer else {
            super.mouseUp(with: event)
            return
        }
        
        if !renderer.is3DMode && !didDrag, let localPoint = dragStartPoint {
            let viewWidth = Float(self.bounds.width)
            let numTraces = Float(renderer.instance.numTraces)
            
            if viewWidth > 0 && numTraces > 0 {
                let relativeX = Float(localPoint.x) / viewWidth
                let u = (relativeX - 0.5) / renderer.zoomX + 0.5 + renderer.panX / numTraces
                let traceIdx = Int(floor(u * numTraces))
                
                print("SwiftSeis [Debug] click relativeX: \(relativeX), u: \(u), traceIdx: \(traceIdx), numTraces: \(numTraces)")
                
                if traceIdx >= 0 && traceIdx < renderer.instance.numTraces {
                    if traceIdx < renderer.lastTraces.count {
                        let absoluteId = renderer.lastTraces[traceIdx].id
                        if renderer.selectedTraceIndices.contains(absoluteId) {
                            renderer.selectedTraceIndices.remove(absoluteId)
                        } else {
                            renderer.selectedTraceIndices = [absoluteId]
                        }
                    }
                } else {
                    renderer.selectedTraceIndices.removeAll()
                }
            }
        }
        
        dragStartPoint = nil
        didDrag = false
    }
    
    public override func magnify(with event: NSEvent) {
        guard let renderer = renderer else {
            super.magnify(with: event)
            return
        }
        
        let factor = Float(1.0 + event.magnification)
        if renderer.is3DMode {
            renderer.cameraDistance = max(1.0, min(10.0, renderer.cameraDistance / factor))
        } else {
            renderer.zoomX = max(0.1, min(200.0, renderer.zoomX * factor))
            renderer.zoomY = max(0.1, min(200.0, renderer.zoomY * factor))
        }
        renderer.triggerRedraw()
    }
}

// SwiftUI MetalView Representable wrapper
public struct MetalView: NSViewRepresentable {
    @ObservedObject var renderer: MetalRendererWrapper
    
    public init(renderer: MetalRendererWrapper) {
        self.renderer = renderer
    }
    
    public func makeNSView(context: Context) -> MTKView {
        let mtkView = InteractiveMTKView()
        mtkView.renderer = renderer
        mtkView.device = renderer.instance.device
        mtkView.delegate = renderer.instance
        mtkView.clearColor = MTLClearColor(red: 0.08, green: 0.09, blue: 0.1, alpha: 1.0)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearDepth = 1.0
        mtkView.enableSetNeedsDisplay = false // keep rendering dynamically
        mtkView.isPaused = false
        mtkView.framebufferOnly = false // Allow CPU texture capture for screenshots
        
        // Enable touch/gesture tracking
        mtkView.allowedTouchTypes = [.indirect]
        return mtkView
    }
    
    public func updateNSView(_ nsView: MTKView, context: Context) {
        if let interactiveView = nsView as? InteractiveMTKView {
            interactiveView.renderer = renderer
        }
        nsView.setNeedsDisplay(nsView.bounds)
    }
}

public class MetalRendererWrapper: ObservableObject {
    public let instance = MetalRenderer()
    
    @Published public var captureScreenshot: Bool = false
    public var onScreenshotReady: ((NSImage) -> Void)?
    
    public func exportFullSeismicImage(completion: @escaping (NSImage?) -> Void) {
        if instance.is3DMode {
            self.captureScreenshot = true
            self.onScreenshotReady = completion
            self.triggerRedraw()
            return
        }
        instance.exportFullSeismicImage(completion: completion)
    }
    
    private var lastSamples: [[Float]] = []
    private var lastNs: Int = 1
    public var lastTraces: [TraceHeader] = []
    
    @Published public var selectedTraceIndices: Set<Int> = [] {
        didSet {
            let localIndices = Set(selectedTraceIndices.compactMap { selId in
                lastTraces.firstIndex(where: { $0.id == selId })
            })
            instance.updateWiggleGeometry(samples: lastSamples, ns: lastNs, selectedTraceIndices: localIndices)
            triggerRedraw()
        }
    }
    
    public var ns: Int {
        get { return instance.ns }
        set { instance.ns = newValue }
    }
    
    @Published public var displayMode: Int = 1 {
        didSet { instance.displayMode = displayMode }
    }
    @Published public var gain: Float = 1.0 {
        didSet { instance.gain = gain }
    }
    @Published public var colormap: Int = 1 {
        didSet { instance.colormap = colormap }
    }
    @Published public var clipPercentile: Float = 0.5 {
        didSet { instance.clipPercentile = clipPercentile }
    }
    @Published public var wiggleScale: Float = 2.5 {
        didSet { instance.wiggleScale = wiggleScale }
    }
    
    @Published public var zoomX: Float = 1.0 {
        didSet { instance.zoomX = zoomX }
    }
    @Published public var zoomY: Float = 1.0 {
        didSet { instance.zoomY = zoomY }
    }
    @Published public var zScale3D: Float = 1.0 {
        didSet { instance.zScale3D = zScale3D }
    }
    @Published public var panX: Float = 0.0 {
        didSet { instance.panX = panX }
    }
    @Published public var panY: Float = 0.0 {
        didSet { instance.panY = panY }
    }
    
    @Published public var is3DMode: Bool = false {
        didSet { instance.is3DMode = is3DMode }
    }
    @Published public var cameraYaw: Float = -0.5 {
        didSet { instance.cameraYaw = cameraYaw }
    }
    @Published public var cameraPitch: Float = 0.5 {
        didSet { instance.cameraPitch = cameraPitch }
    }
    @Published public var cameraDistance: Float = 3.0 {
        didSet { instance.cameraDistance = cameraDistance }
    }
    @Published public var pan3D: SIMD3<Float> = SIMD3<Float>(0, 0, 0) {
        didSet { instance.pan3D = pan3D }
    }
    @Published public var activeInlineIndex: Int = 0 {
        didSet { instance.activeInlineIndex = activeInlineIndex }
    }
    @Published public var activeCrosslineIndex: Int = 0 {
        didSet { instance.activeCrosslineIndex = activeCrosslineIndex }
    }
    @Published public var activeZIndex: Int = 0 {
        didSet { instance.activeZIndex = activeZIndex }
    }
    @Published public var numInlines: Int = 1 {
        didSet { instance.numInlines = numInlines }
    }
    @Published public var numCrosslines: Int = 1 {
        didSet { instance.numCrosslines = numCrosslines }
    }
    
    public func updateInlineTexture(with samples: [[Float]], ns: Int) {
        instance.updateInlineTexture(with: samples, ns: ns) { [weak self] in
            self?.triggerRedraw()
        }
    }
    
    public func updateCrosslineTexture(with samples: [[Float]], ns: Int) {
        instance.updateCrosslineTexture(with: samples, ns: ns) { [weak self] in
            self?.triggerRedraw()
        }
    }
    
    public func updateZSliceTexture(with samples: [[Float]], ns: Int) {
        instance.updateZSliceTexture(with: samples, ns: ns) { [weak self] in
            self?.triggerRedraw()
        }
    }
    
    public func loadData(samples: [[Float]], traces: [TraceHeader], ns: Int, selectedTraceIndices: Set<Int> = []) {
        self.lastSamples = samples
        self.lastTraces = traces
        self.lastNs = ns
        self.selectedTraceIndices = selectedTraceIndices
        instance.updateTexture(with: samples, ns: ns)
        
        let localIndices = Set(selectedTraceIndices.compactMap { selId in
            traces.firstIndex(where: { $0.id == selId })
        })
        instance.updateWiggleGeometry(samples: samples, ns: ns, selectedTraceIndices: localIndices)
        objectWillChange.send()
    }
    
    public func triggerRedraw() {
        objectWillChange.send()
    }
}
