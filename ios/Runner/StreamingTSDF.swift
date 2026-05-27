// StreamingTSDF — real-time TSDF accumulator.
//
// Capture davomida ARKit'dan kelgan har depth frame'ni voxel grid'ga sinx
// integrate qiladi. Polycam-style continuous fusion:
//   • Capture davomida tinimsiz ko'p depth observation'lar averaging qilinadi
//   • Mesh sifat ARKit'ning anchor mesh'idan ham yaxshi (multi-view averaging)
//   • Foydalanuvchi qaragan har joy voxel grid'ga "yopishadi"
//
// Existing TSDFIntegrator.metal kerneli ishlatiladi (integrateDepth). Lekin
// batch o'rniga streaming: buffer'lar capture davomida tirik qoladi, kerneli
// har frame uchun bir marta chaqiriladi.
//
// Memory: 5cm voxel × 8m³ ≈ 2M voxel × 8 bayt (sdf+weight) = 16 MB.
// Performance: ~2M voxel × Metal compute ≈ 0.5–1 ms per frame on A16.

import Foundation
import Metal
import ARKit
import simd
import CoreVideo

final class StreamingTSDF {
    private let device: MTLDevice
    private let cmdQueue: MTLCommandQueue
    private let integrateState: MTLComputePipelineState
    private let integrateColorState: MTLComputePipelineState?
    // Phase 7.6: offline RGB variant — JPG'dan RGBA texture sample qiladi
    private let integrateColorRGBState: MTLComputePipelineState?

    let origin: SIMD3<Float>
    let voxelSize: Float
    let gridX: Int
    let gridY: Int
    let gridZ: Int
    let truncation: Float
    let maxIntegrationDepth: Float

    let sdfBuffer: MTLBuffer
    let weightBuffer: MTLBuffer
    let colorBuffer: MTLBuffer  // float4 per voxel: rgb + colorWeight in .a

    private var paramsBuffer: MTLBuffer
    private var cameraBuffer: MTLBuffer
    private var depthTexture: MTLTexture?
    private var depthW: Int = 0
    private var depthH: Int = 0

    // CVMetalTextureCache — zero-copy YUV planes from ARFrame.capturedImage
    private var textureCache: CVMetalTextureCache?

    private(set) var integratedFrameCount: Int = 0

    // Matches TSDFParams flat layout in TSDFIntegrator.metal
    private struct ParamsLayout {
        var originX: Float; var originY: Float; var originZ: Float; var voxelSize: Float
        var gridX: UInt32; var gridY: UInt32; var gridZ: UInt32; var pad1: UInt32
        var truncation: Float; var maxIntegrationDepth: Float; var pad2: Float; var pad3: Float
    }

    // Matches TSDFCamera in TSDFIntegrator.metal
    private struct CameraLayout {
        var invTransform: simd_float4x4
        var intrinsics: simd_float3x3
        var imageSize: SIMD2<Float>
    }

    /// Init centred grid. `centerWorld` — ekspected room midpoint (camera initial pos).
    /// `extents` — full box size (e.g. SIMD3<Float>(8, 4, 8) for 8m×4m×8m room).
    init?(
        centerWorld: SIMD3<Float>,
        extents: SIMD3<Float> = SIMD3<Float>(8, 4, 8),
        voxelSize: Float = 0.05,
        truncation: Float = 0.12,
        maxIntegrationDepth: Float = 4.0,
    ) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              let integrateFn = library.makeFunction(name: "integrateDepth"),
              let cmdQueue = device.makeCommandQueue() else { return nil }
        do {
            self.integrateState = try device.makeComputePipelineState(function: integrateFn)
        } catch {
            NSLog("KADASTR StreamingTSDF pipeline state failed: \(error)")
            return nil
        }
        // Optional color kernel — fallback to depth-only if missing
        if let colorFn = library.makeFunction(name: "integrateDepthColor") {
            self.integrateColorState = try? device.makeComputePipelineState(function: colorFn)
        } else {
            self.integrateColorState = nil
        }
        // Phase 7.6: offline RGB variant
        if let colorRGBFn = library.makeFunction(name: "integrateDepthColorRGB") {
            self.integrateColorRGBState = try? device.makeComputePipelineState(function: colorRGBFn)
        } else {
            self.integrateColorRGBState = nil
        }

        // Texture cache for zero-copy YUV planes
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache
        self.device = device
        self.cmdQueue = cmdQueue
        self.voxelSize = voxelSize
        self.truncation = truncation
        self.maxIntegrationDepth = maxIntegrationDepth

        self.origin = centerWorld - extents * 0.5
        self.gridX = max(8, Int(ceil(extents.x / voxelSize)))
        self.gridY = max(8, Int(ceil(extents.y / voxelSize)))
        self.gridZ = max(8, Int(ceil(extents.z / voxelSize)))
        let total = gridX * gridY * gridZ
        let bufferLen = total * MemoryLayout<Float>.stride

        // Color buffer: float4 per voxel (rgb + colorWeight). +16 bytes/voxel.
        let colorLen = total * MemoryLayout<SIMD4<Float>>.stride
        guard let sdfBuf = device.makeBuffer(length: bufferLen, options: .storageModeShared),
              let wBuf = device.makeBuffer(length: bufferLen, options: .storageModeShared),
              let colorBuf = device.makeBuffer(length: colorLen, options: .storageModeShared),
              let pBuf = device.makeBuffer(length: MemoryLayout<ParamsLayout>.stride, options: .storageModeShared),
              let cBuf = device.makeBuffer(length: MemoryLayout<CameraLayout>.stride, options: .storageModeShared)
        else {
            NSLog("KADASTR StreamingTSDF buffer alloc failed")
            return nil
        }
        self.sdfBuffer = sdfBuf
        self.weightBuffer = wBuf
        self.colorBuffer = colorBuf
        self.paramsBuffer = pBuf
        self.cameraBuffer = cBuf
        memset(sdfBuf.contents(), 0, bufferLen)
        memset(wBuf.contents(), 0, bufferLen)
        memset(colorBuf.contents(), 0, colorLen)

        // Write params once (origin + grid + truncation never change during scan)
        var params = ParamsLayout(
            originX: origin.x, originY: origin.y, originZ: origin.z,
            voxelSize: voxelSize,
            gridX: UInt32(gridX), gridY: UInt32(gridY), gridZ: UInt32(gridZ), pad1: 0,
            truncation: truncation, maxIntegrationDepth: maxIntegrationDepth, pad2: 0, pad3: 0,
        )
        memcpy(paramsBuffer.contents(), &params, MemoryLayout<ParamsLayout>.stride)

        NSLog(String(format: "KADASTR StreamingTSDF init: %d×%d×%d = %d voxels (%.1f MB)",
              gridX, gridY, gridZ, total, Double(bufferLen * 2) / 1024.0 / 1024.0))
    }

    /// Integrate one ARFrame's LiDAR depth into the voxel grid.
    /// Call from ARSessionDelegate.session(didUpdate:) every N frames.
    @available(iOS 14.0, *)
    func integrate(frame: ARFrame) {
        guard let depthPB = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else { return }

        let w = CVPixelBufferGetWidth(depthPB)
        let h = CVPixelBufferGetHeight(depthPB)

        // Recreate depth texture if dims changed (rare)
        if depthTexture == nil || depthW != w || depthH != h {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float, width: w, height: h, mipmapped: false,
            )
            desc.usage = MTLTextureUsage.shaderRead
            desc.storageMode = MTLStorageMode.shared
            depthTexture = device.makeTexture(descriptor: desc)
            depthW = w
            depthH = h
        }
        guard let depthTex = depthTexture else { return }

        // Upload depth map to texture (CVPixelBuffer Float32, row-major)
        CVPixelBufferLockBaseAddress(depthPB, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthPB, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthPB) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPB)
        depthTex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: base,
            bytesPerRow: bytesPerRow,
        )

        // Camera: inverse transform + intrinsics + image resolution.
        // ARKit's camera.intrinsics is for full RGB image, NOT depth. But for
        // TSDF we project voxel into RGB image coords and sample depth at the
        // SAME normalized UV — works because depth and RGB share the same
        // physical optics (just different resolution).
        let cam = frame.camera
        var camLayout = CameraLayout(
            invTransform: cam.transform.inverse,
            intrinsics: cam.intrinsics,
            imageSize: SIMD2<Float>(Float(cam.imageResolution.width), Float(cam.imageResolution.height)),
        )
        memcpy(cameraBuffer.contents(), &camLayout, MemoryLayout<CameraLayout>.stride)

        // Try YUV planes for color integration. ARFrame.capturedImage = NV12 biplanar.
        var yPlane: MTLTexture? = nil
        var cbcrPlane: MTLTexture? = nil
        if let cache = textureCache, let colorState = integrateColorState {
            let pixelBuffer = frame.capturedImage
            let pbW = CVPixelBufferGetWidth(pixelBuffer)
            let pbH = CVPixelBufferGetHeight(pixelBuffer)
            var yTexRef: CVMetalTexture?
            var cbcrTexRef: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, pixelBuffer, nil,
                .r8Unorm, pbW, pbH, 0, &yTexRef,
            )
            CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, pixelBuffer, nil,
                .rg8Unorm, pbW / 2, pbH / 2, 1, &cbcrTexRef,
            )
            if let yt = yTexRef, let ct = cbcrTexRef {
                yPlane = CVMetalTextureGetTexture(yt)
                cbcrPlane = CVMetalTextureGetTexture(ct)
            }
        }

        guard let cmdBuf = cmdQueue.makeCommandBuffer(),
              let enc = cmdBuf.makeComputeCommandEncoder() else { return }

        // Color kernel (depth + RGB) yoki fallback faqat depth.
        let useColor = (yPlane != nil && cbcrPlane != nil && integrateColorState != nil)
        if useColor, let colorState = integrateColorState {
            enc.setComputePipelineState(colorState)
            enc.setBuffer(sdfBuffer, offset: 0, index: 0)
            enc.setBuffer(weightBuffer, offset: 0, index: 1)
            enc.setBuffer(colorBuffer, offset: 0, index: 2)
            enc.setBuffer(paramsBuffer, offset: 0, index: 3)
            enc.setBuffer(cameraBuffer, offset: 0, index: 4)
            enc.setTexture(depthTex, index: 0)
            enc.setTexture(yPlane, index: 1)
            enc.setTexture(cbcrPlane, index: 2)
        } else {
            enc.setComputePipelineState(integrateState)
            enc.setBuffer(sdfBuffer, offset: 0, index: 0)
            enc.setBuffer(weightBuffer, offset: 0, index: 1)
            enc.setBuffer(paramsBuffer, offset: 0, index: 2)
            enc.setBuffer(cameraBuffer, offset: 0, index: 3)
            enc.setTexture(depthTex, index: 0)
        }

        let tgSize = MTLSize(width: 4, height: 4, depth: 4)
        let tgCount = MTLSize(
            width: (gridX + 3) / 4,
            height: (gridY + 3) / 4,
            depth: (gridZ + 3) / 4,
        )
        enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
        enc.endEncoding()
        cmdBuf.commit()
        // Don't wait — let Metal queue handle it async. Next frame can dispatch
        // while previous finishes. Light pressure since kernel is fast.

        integratedFrameCount += 1
    }

    // MARK: - Phase 7.6: Offline integration (from saved data)

    /// Saqlangan photo + depth + pose'lardan voxel grid'ga depth+color integrate
    /// qiladi (offline reprocess mode). Live `integrate(frame:)` o'rniga
    /// foydalanuvchi profilda Process bossa shu chaqiriladi.
    ///
    /// - Parameters:
    ///   - depth: row-major Float32 array (W×H), meters
    ///   - depthW, depthH: depth resolution (odatda 256×192)
    ///   - imageURL: JPG file URL
    ///   - cameraTransform: camera→world transform (poses.json'dan)
    ///   - intrinsics: pixel intrinsics scaled to image resolution
    ///   - imageWidth, imageHeight: image dimensions (Float)
    func integrateOffline(
        depth: [Float], depthW: Int, depthH: Int,
        imageURL: URL,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        imageWidth: Float, imageHeight: Float,
    ) {
        // RGB color integration (offline'da YUV o'rniga RGBA texture)
        guard let colorRGBState = self.integrateColorRGBState else {
            // Fallback: faqat depth (rang yo'q)
            integrateOfflineDepthOnly(
                depth: depth, depthW: depthW, depthH: depthH,
                cameraTransform: cameraTransform, intrinsics: intrinsics,
                imageWidth: imageWidth, imageHeight: imageHeight,
            )
            return
        }

        // 1. Depth → texture (R32Float)
        if depthTexture == nil || self.depthW != depthW || self.depthH != depthH {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float, width: depthW, height: depthH, mipmapped: false,
            )
            desc.usage = MTLTextureUsage.shaderRead
            desc.storageMode = MTLStorageMode.shared
            depthTexture = device.makeTexture(descriptor: desc)
            self.depthW = depthW
            self.depthH = depthH
        }
        guard let depthTex = depthTexture else { return }
        depth.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            depthTex.replace(
                region: MTLRegionMake2D(0, 0, depthW, depthH),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: depthW * 4,
            )
        }

        // 2. Image JPG → RGBA texture
        let imgW = Int(imageWidth)
        let imgH = Int(imageHeight)
        // Downsample for speed (full hi-res not needed for voxel color, 5cm sample)
        let targetW = min(imgW, 1024)
        let targetH = max(192, Int(Float(targetW) * Float(imgH) / max(1.0, Float(imgW))))
        guard let rgbTex = loadImageAsTexture(url: imageURL, width: targetW, height: targetH) else {
            NSLog("KADASTR offline integrate: image load FAILED \(imageURL.lastPathComponent)")
            return
        }

        // 3. Camera params
        var camLayout = CameraLayout(
            invTransform: cameraTransform.inverse,
            intrinsics: intrinsics,
            imageSize: SIMD2<Float>(imageWidth, imageHeight),
        )
        memcpy(cameraBuffer.contents(), &camLayout, MemoryLayout<CameraLayout>.stride)

        // 4. Dispatch
        guard let cmdBuf = cmdQueue.makeCommandBuffer(),
              let enc = cmdBuf.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(colorRGBState)
        enc.setBuffer(sdfBuffer, offset: 0, index: 0)
        enc.setBuffer(weightBuffer, offset: 0, index: 1)
        enc.setBuffer(colorBuffer, offset: 0, index: 2)
        enc.setBuffer(paramsBuffer, offset: 0, index: 3)
        enc.setBuffer(cameraBuffer, offset: 0, index: 4)
        enc.setTexture(depthTex, index: 0)
        enc.setTexture(rgbTex, index: 1)

        let tgSize = MTLSize(width: 4, height: 4, depth: 4)
        let tgCount = MTLSize(
            width: (gridX + 3) / 4,
            height: (gridY + 3) / 4,
            depth: (gridZ + 3) / 4,
        )
        enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
        enc.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        integratedFrameCount += 1
    }

    /// Fallback: faqat depth integration (rangsiz).
    private func integrateOfflineDepthOnly(
        depth: [Float], depthW: Int, depthH: Int,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        imageWidth: Float, imageHeight: Float,
    ) {
        if depthTexture == nil || self.depthW != depthW || self.depthH != depthH {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float, width: depthW, height: depthH, mipmapped: false,
            )
            desc.usage = MTLTextureUsage.shaderRead
            desc.storageMode = MTLStorageMode.shared
            depthTexture = device.makeTexture(descriptor: desc)
            self.depthW = depthW
            self.depthH = depthH
        }
        guard let depthTex = depthTexture else { return }
        depth.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            depthTex.replace(
                region: MTLRegionMake2D(0, 0, depthW, depthH),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: depthW * 4,
            )
        }
        var camLayout = CameraLayout(
            invTransform: cameraTransform.inverse,
            intrinsics: intrinsics,
            imageSize: SIMD2<Float>(imageWidth, imageHeight),
        )
        memcpy(cameraBuffer.contents(), &camLayout, MemoryLayout<CameraLayout>.stride)
        guard let cmdBuf = cmdQueue.makeCommandBuffer(),
              let enc = cmdBuf.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(integrateState)
        enc.setBuffer(sdfBuffer, offset: 0, index: 0)
        enc.setBuffer(weightBuffer, offset: 0, index: 1)
        enc.setBuffer(paramsBuffer, offset: 0, index: 2)
        enc.setBuffer(cameraBuffer, offset: 0, index: 3)
        enc.setTexture(depthTex, index: 0)
        let tgSize = MTLSize(width: 4, height: 4, depth: 4)
        let tgCount = MTLSize(
            width: (gridX + 3) / 4, height: (gridY + 3) / 4, depth: (gridZ + 3) / 4,
        )
        enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
        enc.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        integratedFrameCount += 1
    }

    /// JPG fayl → BGRA8 Metal texture (downsampled to width×height).
    private func loadImageAsTexture(url: URL, width: Int, height: Int) -> MTLTexture? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGImageByteOrderInfo.order32Big.rawValue
        let bpr = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = pixels.withUnsafeMutableBufferPointer { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bpr,
                space: cs, bitmapInfo: info,
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false,
        )
        desc.usage = MTLTextureUsage.shaderRead
        desc.storageMode = MTLStorageMode.shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        pixels.withUnsafeBytes { raw in
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: bpr,
            )
        }
        return tex
    }

    /// Sample voxel color at a world position (trilinear nearest). Returns nil
    /// if voxel has no color contribution (colorWeight == 0). Used as atlas
    /// baker fallback when no camera contributes to a pixel.
    func sampleColor(at worldPos: SIMD3<Float>) -> SIMD3<Float>? {
        let local = (worldPos - origin) / voxelSize
        let x = Int(local.x.rounded())
        let y = Int(local.y.rounded())
        let z = Int(local.z.rounded())
        if x < 0 || x >= gridX || y < 0 || y >= gridY || z < 0 || z >= gridZ { return nil }
        let idx = x + y * gridX + z * gridX * gridY
        let colorPtr = colorBuffer.contents().assumingMemoryBound(to: SIMD4<Float>.self)
        let c = colorPtr[idx]
        if c.w < 0.5 { return nil }
        return SIMD3<Float>(c.x, c.y, c.z)
    }

    /// Per-voxel color buffer pointer — for atlas baker direct GPU access.
    /// Layout matches sdf/weight: idx = x + y*gridX + z*gridX*gridY.
    /// Each voxel: float4 (rgb + colorWeight).
    var colorBufferPointer: UnsafePointer<SIMD4<Float>> {
        return UnsafePointer(colorBuffer.contents().assumingMemoryBound(to: SIMD4<Float>.self))
    }

    /// Extract the current TSDF as a triangle mesh via marching cubes (CPU).
    /// Reuses existing TSDFReconstructor's marching cubes implementation.
    /// Call at end of capture.
    func extractMesh() -> (vertices: [SIMD3<Float>], normals: [SIMD3<Float>], triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)])? {
        // Wait for any in-flight integration to finish
        cmdQueue.makeCommandBuffer().map { cb in
            cb.commit()
            cb.waitUntilCompleted()
        }

        let totalVoxels = gridX * gridY * gridZ
        let sdfPtr = sdfBuffer.contents().assumingMemoryBound(to: Float.self)
        let wPtr = weightBuffer.contents().assumingMemoryBound(to: Float.self)
        let sdfArray = UnsafeBufferPointer(start: sdfPtr, count: totalVoxels)
        let weightArray = UnsafeBufferPointer(start: wPtr, count: totalVoxels)

        return StreamingTSDF.marchingCubes(
            sdf: sdfArray, weight: weightArray,
            gridX: gridX, gridY: gridY, gridZ: gridZ,
            origin: origin, voxelSize: voxelSize,
        )
    }

    /// Adapter — calls existing marching cubes implementation from TSDFReconstructor.
    /// Since marching cubes is defined fileprivate, we expose a wrapper here.
    private static func marchingCubes(
        sdf: UnsafeBufferPointer<Float>,
        weight: UnsafeBufferPointer<Float>,
        gridX: Int, gridY: Int, gridZ: Int,
        origin: SIMD3<Float>, voxelSize: Float,
    ) -> (vertices: [SIMD3<Float>], normals: [SIMD3<Float>], triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)])? {
        return TSDFReconstructor.marchingCubesPublic(
            sdf: sdf, weight: weight,
            gridX: gridX, gridY: gridY, gridZ: gridZ,
            origin: origin, voxelSize: voxelSize,
        )
    }
}
