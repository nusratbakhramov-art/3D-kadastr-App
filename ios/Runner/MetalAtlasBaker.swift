// MetalAtlasBaker — xatlas UV unwrap + Metal compute atlas baking pipeline.
//
// Flow:
//   1. CPU: ARKit mesh → xatlas UV unwrap (per-vertex UV in 2048 atlas)
//   2. CPU: rasterize triangles → position/normal textures (per atlas pixel)
//   3. Metal: batch process cameras → accumulate color + weight buffers
//   4. Metal: normalize → RGBA8 atlas
//   5. Metal: dilate → bleed edges for bilinear filtering safety
//   6. Read back atlas image, return with unwrapped geometry
//
// Output: AtlasBakeResult — atlas UIImage + new mesh (vertices, normals, UVs,
// indices) ready for SCNGeometry.

import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics
import ImageIO
import UIKit

// MARK: - Public API

struct AtlasBakeInputCamera {
    let transform: simd_float4x4      // camera → world
    let intrinsics: simd_float3x3
    let imageURL: URL                 // RGB JPEG
    let imageWidth: Float
    let imageHeight: Float
    let depthURL: URL?                // LiDAR depth (depth_NNNN.bin)
    let depthWidth: Int               // 256 odatda
    let depthHeight: Int              // 192 odatda
    // Phase 3.3: variance-of-Laplacian sharpness [0..1] — 0=blurry, 1=sharp.
    // Bake kernel weight'ga ko'paytiriladi: motion-blur foto'lar kamroq hissa.
    var sharpness: Float = 0.5
}

struct AtlasBakeResult {
    let atlas: UIImage                // baked RGBA atlas
    let vertices: [SIMD3<Float>]      // xatlas-unwrapped vertices (world)
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]           // [0..1]
    let indices: [UInt32]
    let atlasWidth: Int
    let atlasHeight: Int
}

enum AtlasBakeError: LocalizedError {
    case xatlasFailed(String)
    case metalSetup(String)
    case imageLoad(String)

    var errorDescription: String? {
        switch self {
        case .xatlasFailed(let s): return "xatlas: \(s)"
        case .metalSetup(let s): return "Metal: \(s)"
        case .imageLoad(let s): return "Image load: \(s)"
        }
    }
}

final class MetalAtlasBaker {
    /// Voxel color fallback uchun StreamingTSDF ma'lumotlari. Atlas piksel
    /// hech qaysi cameradan rang olmagan bo'lsa, world pos → voxel rang.
    struct VoxelColorVolume {
        let buffer: MTLBuffer            // float4 per voxel (rgb + colorWeight in .a)
        let origin: SIMD3<Float>
        let voxelSize: Float
        let gridX: Int
        let gridY: Int
        let gridZ: Int
    }

    static func bake(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        cameras: [AtlasBakeInputCamera],
        atlasResolution: Int = 2048,
        cameraBatchSize: Int = 16,
        downsampleFactor: Int = 2,  // 1920×1440 → 960×720
        voxelColor: VoxelColorVolume? = nil,  // Variant A Phase 2: voxel color fallback
        useCubeProjectionUV: Bool = false,  // Phase 9.4: xatlas o'rniga cube UV
        progress: ((Float, String) -> Void)? = nil,
    ) throws -> AtlasBakeResult {
        // ────────────────────────────────────────────────────────────────────
        // 1. UV unwrap — xatlas yoki cube projection
        // ────────────────────────────────────────────────────────────────────
        let outPositions: [SIMD3<Float>]
        let outNormals: [SIMD3<Float>]
        let outUVs: [SIMD2<Float>]
        let outIndices: [UInt32]
        let atlasW: Int
        let atlasH: Int

        if useCubeProjectionUV {
            // Phase 9.4: Cube projection — 6 chart only, NO fragment artifacts.
            progress?(0.0, "Cube projection UV…")
            NSLog("KADASTR CubeUV input: \(positions.count) vert, \(triangles.count) tri")
            let result = CubeProjectionUV.unwrap(
                positions: positions,
                normals: normals,
                triangles: triangles,
                atlasResolution: atlasResolution,
            )
            outPositions = result.positions
            outNormals = result.normals
            outUVs = result.uvs
            outIndices = result.indices
            atlasW = result.atlasWidth
            atlasH = result.atlasHeight
            NSLog("KADASTR CubeUV OK: atlas=\(atlasW)×\(atlasH), \(outPositions.count)v/\(outIndices.count/3)t")
            progress?(0.10, "Cube UV: \(atlasW)×\(atlasH), \(outPositions.count) vert")
        } else {
            // Original: xatlas UV unwrap (chart-based)
            progress?(0.0, "xatlas UV unwrap…")
            let posData = positions.withUnsafeBufferPointer {
                Data(buffer: UnsafeBufferPointer(start: $0.baseAddress, count: $0.count))
            }
            let nrmData = normals.withUnsafeBufferPointer {
                Data(buffer: UnsafeBufferPointer(start: $0.baseAddress, count: $0.count))
            }
            let posPacked = packSIMD3(positions)
            let nrmPacked = packSIMD3(normals)
            var triFlat: [UInt32] = []
            triFlat.reserveCapacity(triangles.count * 3)
            for t in triangles {
                triFlat.append(t.v0); triFlat.append(t.v1); triFlat.append(t.v2)
            }
            let idxData = triFlat.withUnsafeBufferPointer {
                Data(buffer: UnsafeBufferPointer(start: $0.baseAddress, count: $0.count))
            }

            NSLog("KADASTR xatlas input: \(positions.count) vert, \(triangles.count) tri")
            let xResult: XAtlasResult
            do {
                xResult = try XAtlasBridge.unwrapMesh(
                    withPositions: posPacked,
                    normals: nrmPacked,
                    indices: idxData,
                    vertexCount: UInt(positions.count),
                    triangleCount: UInt(triangles.count),
                    atlasResolution: UInt32(atlasResolution),
                )
            } catch let nsErr as NSError {
                let detail = "code=\(nsErr.code) \(nsErr.localizedDescription) (input: \(positions.count)v/\(triangles.count)t)"
                NSLog("KADASTR xatlas FAILED: \(detail)")
                throw AtlasBakeError.xatlasFailed(detail)
            }
            NSLog("KADASTR xatlas OK: atlas=\(xResult.atlasWidth)×\(xResult.atlasHeight), \(xResult.vertexCount)v/\(xResult.indexCount/3)t")
            _ = posData; _ = nrmData  // silence unused

            let outVC: Int = Int(truncatingIfNeeded: xResult.vertexCount)
            let outIC: Int = Int(truncatingIfNeeded: xResult.indexCount)
            atlasW = Int(truncatingIfNeeded: xResult.atlasWidth)
            atlasH = Int(truncatingIfNeeded: xResult.atlasHeight)
            progress?(0.10, "Atlas: \(atlasW)×\(atlasH), \(outVC) vert, \(outIC/3) tri")

            outPositions = unpackSIMD3(xResult.positions, count: outVC)
            outNormals = unpackSIMD3(xResult.normals, count: outVC)
            outUVs = unpackSIMD2(xResult.uvs, count: outVC)
            outIndices = unpackUInt32(xResult.indices, count: outIC)
        }
        let outVC = outPositions.count
        let outIC = outIndices.count

        // ────────────────────────────────────────────────────────────────────
        // 2. CPU rasterization → position + normal textures
        // ────────────────────────────────────────────────────────────────────
        progress?(0.15, "Rasterizatsiya \(atlasW)×\(atlasH)…")
        var positionTex = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 0), count: atlasW * atlasH)
        var normalTex = [SIMD4<Float>](repeating: SIMD4<Float>(0, 1, 0, 0), count: atlasW * atlasH)

        let triCount = outIC / 3
        for ti in 0..<triCount {
            let i0 = Int(outIndices[ti * 3 + 0])
            let i1 = Int(outIndices[ti * 3 + 1])
            let i2 = Int(outIndices[ti * 3 + 2])
            rasterizeTriangle(
                uv0: outUVs[i0], uv1: outUVs[i1], uv2: outUVs[i2],
                w0: outPositions[i0], w1: outPositions[i1], w2: outPositions[i2],
                n0: outNormals[i0], n1: outNormals[i1], n2: outNormals[i2],
                atlasW: atlasW, atlasH: atlasH,
                positionTex: &positionTex, normalTex: &normalTex,
            )
        }

        // ────────────────────────────────────────────────────────────────────
        // 3. Metal setup
        // ────────────────────────────────────────────────────────────────────
        progress?(0.25, "Metal pipeline…")
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw AtlasBakeError.metalSetup("no Metal device")
        }
        guard let library = device.makeDefaultLibrary() else {
            throw AtlasBakeError.metalSetup("default library missing")
        }
        guard
            let bakeFunc = library.makeFunction(name: "bakeAtlasBatch"),
            let normFunc = library.makeFunction(name: "normalizeAtlas"),
            let normBestFunc = library.makeFunction(name: "normalizeBest"),       // Multi-band
            let combineFunc = library.makeFunction(name: "multiBandCombine"),     // Multi-band
            let dilFunc = library.makeFunction(name: "dilateAtlas"),
            let wideBlurFunc = library.makeFunction(name: "blurSeparableWide")  // Phase 17 seam leveling
        else {
            throw AtlasBakeError.metalSetup("kernel functions not found")
        }
        let bakeState = try device.makeComputePipelineState(function: bakeFunc)
        let normState = try device.makeComputePipelineState(function: normFunc)
        let normBestState = try device.makeComputePipelineState(function: normBestFunc)
        let combineState = try device.makeComputePipelineState(function: combineFunc)
        let dilState = try device.makeComputePipelineState(function: dilFunc)
        let wideBlurState = try device.makeComputePipelineState(function: wideBlurFunc)
        guard let cmdQueue = device.makeCommandQueue() else {
            throw AtlasBakeError.metalSetup("command queue")
        }

        // Allocate accumulator buffers
        let pixCount = atlasW * atlasH
        let colorBuf = device.makeBuffer(length: pixCount * 16, options: .storageModeShared)!
        let weightBuf = device.makeBuffer(length: pixCount * 4, options: .storageModeShared)!
        // Multi-band: best-view accumulator (rgb=bestColor, a=bestScore).
        let bestBuf = device.makeBuffer(length: pixCount * 16, options: .storageModeShared)!
        memset(colorBuf.contents(), 0, pixCount * 16)
        memset(weightBuf.contents(), 0, pixCount * 4)
        memset(bestBuf.contents(), 0, pixCount * 16)

        // Upload position/normal textures
        let posTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: atlasW, height: atlasH, mipmapped: false,
        )
        posTexDesc.usage = MTLTextureUsage.shaderRead
        posTexDesc.storageMode = MTLStorageMode.shared
        let posTexture = device.makeTexture(descriptor: posTexDesc)!
        positionTex.withUnsafeBytes { raw in
            posTexture.replace(
                region: MTLRegionMake2D(0, 0, atlasW, atlasH),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: atlasW * 16,
            )
        }
        let nrmTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: atlasW, height: atlasH, mipmapped: false,
        )
        nrmTexDesc.usage = MTLTextureUsage.shaderRead
        nrmTexDesc.storageMode = MTLStorageMode.shared
        let nrmTexture = device.makeTexture(descriptor: nrmTexDesc)!
        // Convert Float32→Float16 packed
        let nrm16 = convertNormalsToHalf(normalTex)
        nrm16.withUnsafeBytes { raw in
            nrmTexture.replace(
                region: MTLRegionMake2D(0, 0, atlasW, atlasH),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: atlasW * 8,
            )
        }

        // Output atlas texture
        let outTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: atlasW, height: atlasH, mipmapped: false,
        )
        outTexDesc.usage = MTLTextureUsage([.shaderRead, .shaderWrite])
        outTexDesc.storageMode = MTLStorageMode.shared
        let atlasTex = device.makeTexture(descriptor: outTexDesc)!     // AVG (low-freq base)
        let dilatedTex = device.makeTexture(descriptor: outTexDesc)!
        // Multi-band textures.
        let bestTex = device.makeTexture(descriptor: outTexDesc)!      // BEST-VIEW (high-freq)
        let combineTex = device.makeTexture(descriptor: outTexDesc)!   // multi-band output
        let avgScratchA = device.makeTexture(descriptor: outTexDesc)!  // avg blur ping-pong
        let avgScratchB = device.makeTexture(descriptor: outTexDesc)!
        let bestScratchA = device.makeTexture(descriptor: outTexDesc)! // best blur ping-pong
        let bestScratchB = device.makeTexture(descriptor: outTexDesc)!

        // ────────────────────────────────────────────────────────────────────
        // 4. Batched camera processing
        // ────────────────────────────────────────────────────────────────────
        let totalCams = cameras.count
        let firstW: Float = cameras.first?.imageWidth ?? 1920
        let firstH: Float = cameras.first?.imageHeight ?? 1440
        let imgW: Int = Int(firstW) / downsampleFactor
        let imgH: Int = Int(firstH) / downsampleFactor
        let depthW = cameras.first?.depthWidth ?? 256
        let depthH = cameras.first?.depthHeight ?? 192

        // Phase 16: exposure/WB gain equalization (fotolar orasidagi yorqinlik/rang sakrashi
        // → tekstura choklari). KADASTR_NO_GAIN o'chiradi.
        let expGains: [SIMD3<Float>] = ProcessInfo.processInfo.environment["KADASTR_NO_GAIN"] != nil
            ? [SIMD3<Float>](repeating: SIMD3<Float>(1, 1, 1), count: cameras.count)
            : computeExposureGains(positions: positions, normals: normals, cameras: cameras)

        // Phase 17b: soft best-view exponent. Past (4)=tiniqroq (biroz seam),
        // yuqori (8)=silliqroq (seamless). Default 8 — eng toza, detail saqlangan
        // (region ichida 1 kamera dominant → sharp; chegarada blend → seam yo'q).
        let softViewPower = Float(ProcessInfo.processInfo.environment["KADASTR_VIEW_POWER"].flatMap { Float($0) } ?? 8)
        NSLog("KADASTR soft best-view power = \(softViewPower)")

        let numBatches = (totalCams + cameraBatchSize - 1) / cameraBatchSize
        for batchIdx in 0..<numBatches {
            let start = batchIdx * cameraBatchSize
            let end = min(start + cameraBatchSize, totalCams)
            let batchCount = end - start
            progress?(
                0.30 + 0.55 * Float(batchIdx) / Float(max(numBatches, 1)),
                "Batch \(batchIdx + 1)/\(numBatches) (\(batchCount) cam)",
            )

            // Allocate texture arrays for this batch
            let imgArrDesc = MTLTextureDescriptor()
            imgArrDesc.textureType = MTLTextureType.type2DArray
            imgArrDesc.pixelFormat = MTLPixelFormat.rgba8Unorm
            imgArrDesc.width = imgW
            imgArrDesc.height = imgH
            imgArrDesc.arrayLength = batchCount
            imgArrDesc.usage = MTLTextureUsage.shaderRead
            imgArrDesc.storageMode = MTLStorageMode.shared
            guard let imgArr = device.makeTexture(descriptor: imgArrDesc) else { continue }

            let depthArrDesc = MTLTextureDescriptor()
            depthArrDesc.textureType = MTLTextureType.type2DArray
            depthArrDesc.pixelFormat = MTLPixelFormat.r32Float
            depthArrDesc.width = depthW
            depthArrDesc.height = depthH
            depthArrDesc.arrayLength = batchCount
            depthArrDesc.usage = MTLTextureUsage.shaderRead
            depthArrDesc.storageMode = MTLStorageMode.shared
            guard let depthArr = device.makeTexture(descriptor: depthArrDesc) else { continue }

            // Upload images and depth maps for this batch
            for (slot, ci) in (start..<end).enumerated() {
                let cam = cameras[ci]
                autoreleasepool {
                    if let pix = loadDownsampledRGBA(url: cam.imageURL, targetW: imgW, targetH: imgH) {
                        imgArr.replace(
                            region: MTLRegionMake2D(0, 0, imgW, imgH),
                            mipmapLevel: 0,
                            slice: slot,
                            withBytes: pix.data,
                            bytesPerRow: imgW * 4,
                            bytesPerImage: imgW * imgH * 4,
                        )
                        pix.data.deallocate()
                    }
                    if let durl = cam.depthURL,
                       let depthData = loadDepthFloats(url: durl, expectedW: depthW, expectedH: depthH)
                    {
                        depthData.withUnsafeBufferPointer { buf in
                            depthArr.replace(
                                region: MTLRegionMake2D(0, 0, depthW, depthH),
                                mipmapLevel: 0,
                                slice: slot,
                                withBytes: buf.baseAddress!,
                                bytesPerRow: depthW * 4,
                                bytesPerImage: depthW * depthH * 4,
                            )
                        }
                    }
                }
            }

            // Build camera struct buffer
            let camStructSize = MemoryLayout<MetalAtlasCamera>.stride
            let camBuf = device.makeBuffer(length: camStructSize * batchCount, options: .storageModeShared)!
            let camPtr = camBuf.contents().bindMemory(to: MetalAtlasCamera.self, capacity: batchCount)
            for (slot, ci) in (start..<end).enumerated() {
                let cam = cameras[ci]
                camPtr[slot] = makeMetalCam(cam, gain: ci < expGains.count ? expGains[ci] : SIMD3<Float>(1, 1, 1))
            }

            // Build params
            var params = AtlasParams(
                cameraCount: UInt32(batchCount),
                atlasW: UInt32(atlasW),
                atlasH: UInt32(atlasH),
                minCamAlign: 0.05,  // 0.15→0.05: ko'proq kamera contribute qiladi
                minFaceDot: 0.05,  // 0.18→0.05 (~87°): yon angle'lar ham qabul
                maxDistance: 8.0,  // 6→8 m: uzoq devor/pol uchun
                occlusionTolerance: 0.20,  // 0.10→0.20m: 0.10 juda qattiq edi — pose drift
                // 64mm (~10cm depth xato) tekis yuzalarni noto'g'ri rad etib teshik/voxel
                // katakchalar berardi. 0.20 o'zini-o'zi to'sishni toleratsiya qiladi, lekin
                // xalta (>20cm oldinda) hali to'silган deb rad etiladi.
                // pad = hardOcclusion flag: clean room (KADASTR_CLEAN_ROOM)'da mebel devorга
                // proyeksiya bo'lmasligi uchun occluded kamerani TO'LIQ rad etadi.
                pad: ProcessInfo.processInfo.environment["KADASTR_CLEAN_ROOM"] != nil ? 1 : 0,
                viewPower: softViewPower,
            )
            let paramBuf = device.makeBuffer(bytes: &params, length: MemoryLayout<AtlasParams>.stride, options: .storageModeShared)!

            // Dispatch
            guard let cmdBuf = cmdQueue.makeCommandBuffer(),
                  let enc = cmdBuf.makeComputeCommandEncoder() else { continue }
            enc.setComputePipelineState(bakeState)
            enc.setBuffer(colorBuf, offset: 0, index: 0)
            enc.setBuffer(weightBuf, offset: 0, index: 1)
            enc.setBuffer(camBuf, offset: 0, index: 2)
            enc.setBuffer(paramBuf, offset: 0, index: 3)
            enc.setBuffer(bestBuf, offset: 0, index: 4)  // Multi-band best accumulator
            enc.setTexture(posTexture, index: 0)
            enc.setTexture(nrmTexture, index: 1)
            enc.setTexture(imgArr, index: 2)
            enc.setTexture(depthArr, index: 3)

            let tgSize = MTLSize(width: 16, height: 16, depth: 1)
            let tgCount = MTLSize(
                width: (atlasW + 15) / 16,
                height: (atlasH + 15) / 16,
                depth: 1,
            )
            enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }

        // ────────────────────────────────────────────────────────────────────
        // 5. Normalize + dilate
        // ────────────────────────────────────────────────────────────────────
        progress?(0.88, "Normalize + dilate…")

        var normParams = AtlasParams(
            cameraCount: 0, atlasW: UInt32(atlasW), atlasH: UInt32(atlasH),
            minCamAlign: 0, minFaceDot: 0, maxDistance: 0, occlusionTolerance: 0, pad: 0,
        )
        _ = normParams

        // Variant A Phase 2: voxel color fallback uchun buffer/params. Mavjud
        // bo'lsa atlas piksel gray fallback o'rniga voxel rang qabul qiladi.
        struct VoxelParamsLayout {
            var originX: Float; var originY: Float; var originZ: Float; var voxelSize: Float
            var gridX: UInt32; var gridY: UInt32; var gridZ: UInt32; var hasVoxelColor: UInt32
        }
        // Always need a buffer at index 2 (shader can't conditionally bind). If
        // no voxel color provided, use a dummy 1-element buffer (hasVoxelColor=0).
        let voxelBufToBind: MTLBuffer
        let voxelParamsBuf: MTLBuffer
        if let vc = voxelColor {
            voxelBufToBind = vc.buffer
            var vp = VoxelParamsLayout(
                originX: vc.origin.x, originY: vc.origin.y, originZ: vc.origin.z,
                voxelSize: vc.voxelSize,
                gridX: UInt32(vc.gridX), gridY: UInt32(vc.gridY), gridZ: UInt32(vc.gridZ),
                hasVoxelColor: 1,
            )
            guard let pBuf = device.makeBuffer(bytes: &vp, length: MemoryLayout<VoxelParamsLayout>.stride, options: .storageModeShared) else {
                throw AtlasBakeError.metalSetup("voxel params buffer")
            }
            voxelParamsBuf = pBuf
        } else {
            // Dummy buffer (1 float4 of zeros, hasVoxelColor=0 → shader skips)
            guard let dummy = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
                throw AtlasBakeError.metalSetup("voxel dummy buffer")
            }
            memset(dummy.contents(), 0, MemoryLayout<SIMD4<Float>>.stride)
            voxelBufToBind = dummy
            var vp = VoxelParamsLayout(
                originX: 0, originY: 0, originZ: 0, voxelSize: 1,
                gridX: 1, gridY: 1, gridZ: 1, hasVoxelColor: 0,
            )
            guard let pBuf = device.makeBuffer(bytes: &vp, length: MemoryLayout<VoxelParamsLayout>.stride, options: .storageModeShared) else {
                throw AtlasBakeError.metalSetup("voxel params buffer")
            }
            voxelParamsBuf = pBuf
        }

        do {
            guard let cmdBuf = cmdQueue.makeCommandBuffer(),
                  let enc = cmdBuf.makeComputeCommandEncoder() else {
                throw AtlasBakeError.metalSetup("normalize encoder")
            }
            enc.setComputePipelineState(normState)
            enc.setBuffer(colorBuf, offset: 0, index: 0)
            enc.setBuffer(weightBuf, offset: 0, index: 1)
            enc.setBuffer(voxelBufToBind, offset: 0, index: 2)
            enc.setBuffer(voxelParamsBuf, offset: 0, index: 3)
            enc.setTexture(posTexture, index: 0)
            enc.setTexture(atlasTex, index: 1)
            let tgSize = MTLSize(width: 16, height: 16, depth: 1)
            let tgCount = MTLSize(width: (atlasW + 15) / 16, height: (atlasH + 15) / 16, depth: 1)
            enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }

        // ── Multi-band: BEST-VIEW atlas (yuqori chastota detail manbasi) → bestTex ──
        do {
            guard let cmdBuf = cmdQueue.makeCommandBuffer(),
                  let enc = cmdBuf.makeComputeCommandEncoder() else {
                throw AtlasBakeError.metalSetup("normalizeBest encoder")
            }
            enc.setComputePipelineState(normBestState)
            enc.setBuffer(bestBuf, offset: 0, index: 0)
            enc.setBuffer(voxelBufToBind, offset: 0, index: 2)
            enc.setBuffer(voxelParamsBuf, offset: 0, index: 3)
            enc.setTexture(posTexture, index: 0)
            enc.setTexture(bestTex, index: 1)
            let tg = MTLSize(width: 16, height: 16, depth: 1)
            let tc = MTLSize(width: (atlasW + 15) / 16, height: (atlasH + 15) / 16, depth: 1)
            enc.dispatchThreadgroups(tc, threadsPerThreadgroup: tg)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }

        // Single-texture pass helper (smooth/dilate: texture0 → texture1).
        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let tgCount = MTLSize(width: (atlasW + 15) / 16, height: (atlasH + 15) / 16, depth: 1)
        let runPass: (MTLComputePipelineState, MTLTexture, MTLTexture) -> Void = { state, inTex, outTex in
            guard let cb = cmdQueue.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return }
            e.setComputePipelineState(state)
            e.setTexture(inTex, index: 0)
            e.setTexture(outTex, index: 1)
            e.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
            e.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
        }
        // Phase 17: Poisson-style seam leveling — KENG separable Gaussian bilan
        // past-chastotani (exposure/rang seam) ajratamiz. Eski 3x3 gaussBlur radiusi
        // juda kichik edi (~6 px) → seam (chart ichida o'nlab-yuzlab piksel kenglik)
        // ajralmay, multi-band blur bo'lib qolardi. Keng radius (sigma~R/2) past-
        // chastotani to'liq ajratadi: best'ning detali (qirra/matn/plitka) saqlanadi,
        // faqat seam'ning past-chastota ofseti avg (seamless) tomon suriladi.
        struct WideBlurParamsLayout { var radius: UInt32; var direction: UInt32; var pad0: UInt32; var pad1: UInt32 }
        let seamRadius = UInt32(ProcessInfo.processInfo.environment["KADASTR_SEAM_RADIUS"].flatMap { Int($0) } ?? 48)
        // Separable: H (input→a), keyin V (a→b). b past-chastota natija.
        let wideBlur: (MTLTexture, MTLTexture, MTLTexture) -> MTLTexture = { input, a, b in
            for dir in 0..<2 {
                var bp = WideBlurParamsLayout(radius: seamRadius, direction: UInt32(dir), pad0: 0, pad1: 0)
                let bpBuf = device.makeBuffer(bytes: &bp, length: MemoryLayout<WideBlurParamsLayout>.stride, options: .storageModeShared)!
                let inT = dir == 0 ? input : a
                let outT = dir == 0 ? a : b
                guard let cb = cmdQueue.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { continue }
                e.setComputePipelineState(wideBlurState)
                e.setTexture(inT, index: 0)
                e.setTexture(outT, index: 1)
                e.setBuffer(bpBuf, offset: 0, index: 0)
                e.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
                e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            }
            return b
        }

        // Multi-band combine: final = blur(avg) + (best − blur(best)).
        // blur(avg) = seamless past-chastota base; (best − blur(best)) = sharp detail.
        progress?(0.90, "Seam leveling (wide blur)…")
        let avgLow = wideBlur(atlasTex, avgScratchA, avgScratchB)
        let bestLow = wideBlur(bestTex, bestScratchA, bestScratchB)
        do {
            guard let cmdBuf = cmdQueue.makeCommandBuffer(),
                  let enc = cmdBuf.makeComputeCommandEncoder() else {
                throw AtlasBakeError.metalSetup("combine encoder")
            }
            enc.setComputePipelineState(combineState)
            enc.setTexture(avgLow, index: 0)
            enc.setTexture(bestTex, index: 1)   // sharp, preserved
            enc.setTexture(bestLow, index: 2)
            enc.setTexture(combineTex, index: 3)
            enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }

        // Dilate combine natijasi — cube UV / rasterizatsiya bo'shliqlari va
        // occlusion teshiklarini sharp qo'shni rang bilan to'ldirish (4→12 pass).
        // MUHIM: dilate rangli (alpha>0.5) piksellarni TEGMAYDI — faqat bo'sh
        // joyni to'ldiradi → tiniqlikka zarari yo'q, blur bermaydi.
        // Phase 17/17b: final atlas manbasi.
        //  • DEFAULT "soft": atlasTex = score⁶ weighted avg (soft best-view). Region
        //    ichida 1 kamera dominant (sharp), chegarada blend (konsentrik naqsh/seam
        //    yo'qoladi). Eng toza — keskin best-view region chegaralari yo'q.
        //  • "combine": multi-band (wideBlur seam leveling) — best high-freq + avg low.
        //  • "raw": eski best-view argmax (keskin patchwork — faqat taqqoslash).
        let viewMode = ProcessInfo.processInfo.environment["KADASTR_VIEW_MODE"] ?? "soft"
        var src = viewMode == "raw" ? bestTex : (viewMode == "combine" ? combineTex : atlasTex)
        var dst = dilatedTex
        for _ in 0..<24 { runPass(dilState, src, dst); swap(&src, &dst) }
        let finalTex = src

        // ────────────────────────────────────────────────────────────────────
        // 6. Read back atlas
        // ────────────────────────────────────────────────────────────────────
        progress?(0.95, "Atlas → UIImage…")
        let rowBytes = atlasW * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * atlasH)
        bytes.withUnsafeMutableBytes { raw in
            finalTex.getBytes(
                raw.baseAddress!, bytesPerRow: rowBytes,
                from: MTLRegionMake2D(0, 0, atlasW, atlasH),
                mipmapLevel: 0,
            )
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGImageByteOrderInfo.order32Big.rawValue
        let providerData = Data(bytes)
        guard let provider = CGDataProvider(data: providerData as CFData),
              let cgImage = CGImage(
                  width: atlasW, height: atlasH,
                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                  space: cs, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent,
              )
        else {
            throw AtlasBakeError.metalSetup("CGImage")
        }

        // Texture cap — 4096 USDZ uchun (downscale faqat oshib ketsa).
        let finalCG: CGImage
        var finalW = atlasW, finalH = atlasH
        let maxTexSize = 4096   // 4K atlas (tezlik bottleneck — xatlas pack)
        if atlasW > maxTexSize || atlasH > maxTexSize {
            let scale = Float(maxTexSize) / Float(max(atlasW, atlasH))
            finalW = Int(Float(atlasW) * scale)
            finalH = Int(Float(atlasH) * scale)
            NSLog("KADASTR atlas downscale \(atlasW)×\(atlasH) → \(finalW)×\(finalH)")
            let dCS = CGColorSpaceCreateDeviceRGB()
            let dInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                | CGImageByteOrderInfo.order32Big.rawValue
            guard let dCtx = CGContext(
                data: nil, width: finalW, height: finalH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: dCS, bitmapInfo: dInfo,
            ) else { throw AtlasBakeError.metalSetup("downscale ctx") }
            dCtx.interpolationQuality = .high
            dCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: finalW, height: finalH))
            guard let scaled = dCtx.makeImage() else {
                throw AtlasBakeError.metalSetup("downscale image")
            }
            finalCG = scaled
        } else {
            finalCG = cgImage
        }
        let atlasImage = UIImage(cgImage: finalCG)

        progress?(1.0, "Atlas tayyor ✓")

        return AtlasBakeResult(
            atlas: atlasImage,
            vertices: outPositions,
            normals: outNormals,
            uvs: outUVs,
            indices: outIndices,
            atlasWidth: finalW,
            atlasHeight: finalH,
        )
    }
}

// MARK: - Internal types

private struct MetalAtlasCamera {
    var invTransform: simd_float4x4   // 64 bytes
    var intrinsics: simd_float3x3     // 48 bytes (3 cols of float4, packed)
    var imageSize: SIMD2<Float>       // 8
    var depthSize: SIMD2<Float>       // 8
    var position: SIMD3<Float>        // 16 (SIMD3 = 16 bytes)
    var forward: SIMD3<Float>         // 16
    // Phase 3.3: variance-of-Laplacian sharpness [0..1] + 12 bytes pad to keep
    // 16-byte alignment. Metal AtlasCamera struct must match.
    var sharpness: Float              // 4
    // Phase 16: per-camera exposure/WB gain (pad o'rniga — hajm o'zgarmaydi). Shader
    // sample'ga ko'paytiriladi → fotolar rang jihatdan moslanadi (tekstura choklari yo'qoladi).
    var gainR: Float = 1; var gainG: Float = 1; var gainB: Float = 1  // 12
}

private struct AtlasParams {
    var cameraCount: UInt32
    var atlasW: UInt32
    var atlasH: UInt32
    var minCamAlign: Float
    var minFaceDot: Float
    var maxDistance: Float
    var occlusionTolerance: Float
    var pad: Float
    var viewPower: Float = 8  // Phase 17b: soft best-view exponent (KADASTR_VIEW_POWER)
}

private func makeMetalCam(_ cam: AtlasBakeInputCamera, gain: SIMD3<Float> = SIMD3<Float>(1, 1, 1)) -> MetalAtlasCamera {
    let inv = cam.transform.inverse
    let pos = SIMD3<Float>(cam.transform.columns.3.x, cam.transform.columns.3.y, cam.transform.columns.3.z)
    let fwd = -simd_normalize(SIMD3<Float>(
        cam.transform.columns.2.x, cam.transform.columns.2.y, cam.transform.columns.2.z,
    ))
    return MetalAtlasCamera(
        invTransform: inv,
        intrinsics: cam.intrinsics,
        imageSize: SIMD2<Float>(cam.imageWidth, cam.imageHeight),
        depthSize: SIMD2<Float>(Float(cam.depthWidth), Float(cam.depthHeight)),
        position: pos,
        forward: fwd,
        sharpness: cam.sharpness,
        gainR: gain.x, gainG: gain.y, gainB: gain.z,
    )
}

/// Phase 16: per-camera exposure/WB gain (Brown-Lowe overlap matching). Bir nechta kamera
/// ko'rgan yuza nuqtalarida ranglar mos kelishi uchun per-camera RGB gain yechiladi → fotolar
/// orasidagi yorqinlik/rang sakrashi (tekstura choklari) yo'qoladi, tiniqlik saqlanadi.
/// Proyeksiya shader bilan AYNAN bir xil (camSpace.x, -camSpace.y, depth; K matritsa).
private func computeExposureGains(
    positions: [SIMD3<Float>], normals: [SIMD3<Float>], cameras: [AtlasBakeInputCamera],
) -> [SIMD3<Float>] {
    let n = cameras.count
    var gains = [SIMD3<Float>](repeating: SIMD3<Float>(1, 1, 1), count: n)
    if n < 2 || positions.isEmpty { return gains }
    let DS = 6
    struct GC {
        let inv: simd_float4x4; let K: simd_float3x3; let W, H: Float; let pos, fwd: SIMD3<Float>
        let px: [Float]; let pw, ph: Int; let depth: [Float]; let dw, dh: Int
    }
    var gc: [GC] = []
    for cam in cameras {
        var rgb: [Float] = []; var pw = 0, ph = 0
        if let img = UIImage(contentsOfFile: cam.imageURL.path), let cgi = img.cgImage {
            let w = max(1, cgi.width / DS), h = max(1, cgi.height / DS)
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            if let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(cgi, in: CGRect(x: 0, y: 0, width: w, height: h))
                rgb = [Float](repeating: 0, count: w * h * 3)
                for p in 0..<w * h { rgb[p * 3] = Float(buf[p * 4]) / 255; rgb[p * 3 + 1] = Float(buf[p * 4 + 1]) / 255; rgb[p * 3 + 2] = Float(buf[p * 4 + 2]) / 255 }
                pw = w; ph = h
            }
        }
        var depth: [Float] = []; var dw = 0, dh = 0
        if let du = cam.depthURL, let dd = try? Data(contentsOf: du), dd.count >= 8 + cam.depthWidth * cam.depthHeight * 4 {
            dw = cam.depthWidth; dh = cam.depthHeight
            depth = dd.withUnsafeBytes { raw in
                let f = raw.baseAddress!.advanced(by: 8).assumingMemoryBound(to: Float.self)
                return Array(UnsafeBufferPointer(start: f, count: dw * dh))
            }
        }
        let pos = SIMD3<Float>(cam.transform.columns.3.x, cam.transform.columns.3.y, cam.transform.columns.3.z)
        let fwd = -simd_normalize(SIMD3<Float>(cam.transform.columns.2.x, cam.transform.columns.2.y, cam.transform.columns.2.z))
        gc.append(GC(inv: cam.transform.inverse, K: cam.intrinsics, W: cam.imageWidth, H: cam.imageHeight,
                     pos: pos, fwd: fwd, px: rgb, pw: pw, ph: ph, depth: depth, dw: dw, dh: dh))
    }
    // pairwise overlap means: pairSum[(i*n+j)] = sum of cam i color over co-obs (i,j)
    var pairSum = [SIMD3<Double>](repeating: SIMD3<Double>(0, 0, 0), count: n * n)
    var pairCnt = [Int](repeating: 0, count: n * n)
    let step = max(1, positions.count / 60000)
    var vi = 0
    while vi < positions.count {
        let P = positions[vi]; let Nv = normals[vi]; vi += step
        var vis: [(Int, SIMD3<Float>)] = []
        for (ci, c) in gc.enumerated() where c.pw > 0 {
            let toV = P - c.pos; let dist = simd_length(toV); if dist < 0.05 { continue }
            let toVn = toV / dist
            if simd_dot(c.fwd, toVn) <= 0.1 { continue }
            if simd_dot(Nv, -toVn) <= 0.1 { continue }
            let cs = c.inv * SIMD4<Float>(P, 1); let d = -cs.z
            if d <= 0.05 { continue }
            let proj = c.K * SIMD3<Float>(cs.x, -cs.y, d)
            if proj.z <= 0 { continue }
            let pu = proj.x / proj.z, pv = proj.y / proj.z
            if pu < 0 || pu >= c.W || pv < 0 || pv >= c.H { continue }
            if c.dw > 0 {
                let dmx = min(c.dw - 1, max(0, Int(pu / c.W * Float(c.dw))))
                let dmy = min(c.dh - 1, max(0, Int(pv / c.H * Float(c.dh))))
                let dm = c.depth[dmy * c.dw + dmx]
                if dm <= 0.05 || abs(d - dm) > 0.12 { continue }
            }
            let ix = min(c.pw - 1, max(0, Int(pu / c.W * Float(c.pw))))
            let iy = min(c.ph - 1, max(0, c.ph - 1 - Int(pv / c.H * Float(c.ph))))  // CGContext bottom-up
            let si = (iy * c.pw + ix) * 3
            vis.append((ci, SIMD3<Float>(c.px[si], c.px[si + 1], c.px[si + 2])))
        }
        if vis.count < 2 { continue }
        for a in 0..<vis.count {
            for b in (a + 1)..<vis.count {
                let (i, ci) = vis[a]; let (j, cj) = vis[b]
                pairSum[i * n + j] += SIMD3<Double>(Double(ci.x), Double(ci.y), Double(ci.z))
                pairSum[j * n + i] += SIMD3<Double>(Double(cj.x), Double(cj.y), Double(cj.z))
                pairCnt[i * n + j] += 1; pairCnt[j * n + i] += 1
            }
        }
    }
    for ch in 0..<3 {
        var M = [Double](repeating: 0, count: n * n)
        var b = [Double](repeating: 0, count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let cnt = pairCnt[i * n + j]; if cnt < 20 { continue }
                let mi = pairSum[i * n + j][ch] / Double(cnt)
                let mj = pairSum[j * n + i][ch] / Double(cnt)
                let N_ = Double(cnt)
                M[i * n + i] += N_ * mi * mi; M[j * n + j] += N_ * mj * mj
                M[i * n + j] -= N_ * mi * mj; M[j * n + i] -= N_ * mi * mj
            }
        }
        // ADAPTIV regularizatsiya: tizim near-singular (gauge erkinligi + siyrak kamera grafi)
        // → naive Gaussian solve diverge qilardi (gain'lar clamp'ga urilardi). lambda ~ avg
        // diagonal'ning 10%i → yaxshi shartlangan, gain'lar 1 atrofida, faqat overlap dalili kuchli
        // bo'lsa siljiydi.
        var diagSum = 0.0; for i in 0..<n { diagSum += M[i * n + i] }
        let lambda = max(5.0, 0.1 * diagSum / Double(n))
        for i in 0..<n { M[i * n + i] += lambda; b[i] += lambda }
        let g = solveLinearSystem(M, b, n)
        for i in 0..<n { gains[i][ch] = Float(min(1.7, max(0.6, g[i]))) }
    }
    // SINGLE-SCALAR normalize (umumiy median, per-channel EMAS) → cross-channel balans
    // saqlanadi (global rang/WB o'zgarmaydi), faqat per-camera farqlar tuzatiladi.
    var allG: [Float] = []
    for i in 0..<n { allG.append(gains[i].x); allG.append(gains[i].y); allG.append(gains[i].z) }
    allG.sort()
    let med = allG[allG.count / 2]
    if med > 1e-3 {
        for i in 0..<n {
            gains[i] = simd_clamp(gains[i] / med, SIMD3<Float>(0.6, 0.6, 0.6), SIMD3<Float>(1.7, 1.7, 1.7))
        }
    }
    let gmin = gains.map { min($0.x, min($0.y, $0.z)) }.min() ?? 1
    let gmax = gains.map { max($0.x, max($0.y, $0.z)) }.max() ?? 1
    NSLog("KADASTR exposure gains: \(n) kamera, gain \(String(format: "%.2f", gmin))..\(String(format: "%.2f", gmax))")
    return gains
}

/// Kichik simmetrik tizim yechuvchi (Gauss-Jordan, n≈kamera soni).
private func solveLinearSystem(_ Ain: [Double], _ bin: [Double], _ n: Int) -> [Double] {
    var A = Ain; var b = bin
    for col in 0..<n {
        var piv = col
        for r in (col + 1)..<n where abs(A[r * n + col]) > abs(A[piv * n + col]) { piv = r }
        if abs(A[piv * n + col]) < 1e-12 { continue }
        if piv != col {
            for c in 0..<n { A.swapAt(col * n + c, piv * n + c) }
            b.swapAt(col, piv)
        }
        for r in 0..<n where r != col {
            let f = A[r * n + col] / A[col * n + col]
            if f == 0 { continue }
            for c in col..<n { A[r * n + c] -= f * A[col * n + c] }
            b[r] -= f * b[col]
        }
    }
    var x = [Double](repeating: 1, count: n)
    for i in 0..<n { x[i] = abs(A[i * n + i]) > 1e-12 ? b[i] / A[i * n + i] : 1.0 }
    return x
}

// MARK: - Triangle rasterization

private func rasterizeTriangle(
    uv0: SIMD2<Float>, uv1: SIMD2<Float>, uv2: SIMD2<Float>,
    w0: SIMD3<Float>, w1: SIMD3<Float>, w2: SIMD3<Float>,
    n0: SIMD3<Float>, n1: SIMD3<Float>, n2: SIMD3<Float>,
    atlasW: Int, atlasH: Int,
    positionTex: inout [SIMD4<Float>], normalTex: inout [SIMD4<Float>],
) {
    let aw = Float(atlasW)
    let ah = Float(atlasH)
    let p0 = SIMD2<Float>(uv0.x * aw, uv0.y * ah)
    let p1 = SIMD2<Float>(uv1.x * aw, uv1.y * ah)
    let p2 = SIMD2<Float>(uv2.x * aw, uv2.y * ah)

    let minX = max(0, Int(floor(min(p0.x, min(p1.x, p2.x)))) - 1)
    let maxX = min(atlasW - 1, Int(ceil(max(p0.x, max(p1.x, p2.x)))) + 1)
    let minY = max(0, Int(floor(min(p0.y, min(p1.y, p2.y)))) - 1)
    let maxY = min(atlasH - 1, Int(ceil(max(p0.y, max(p1.y, p2.y)))) + 1)
    if minX > maxX || minY > maxY { return }

    let edge0 = p1 - p0
    let edge1 = p2 - p0
    let d00 = simd_dot(edge0, edge0)
    let d01 = simd_dot(edge0, edge1)
    let d11 = simd_dot(edge1, edge1)
    let denom = d00 * d11 - d01 * d01
    if abs(denom) < 1e-9 { return }  // degenerate
    let invDen = 1.0 / denom

    for y in minY...maxY {
        for x in minX...maxX {
            let p = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
            let v2 = p - p0
            let d20 = simd_dot(v2, edge0)
            let d21 = simd_dot(v2, edge1)
            let v = (d11 * d20 - d01 * d21) * invDen
            let w = (d00 * d21 - d01 * d20) * invDen
            let u = 1 - v - w
            // Allow tiny epsilon for edge inclusion
            if u < -0.001 || v < -0.001 || w < -0.001 { continue }
            let world = w0 * u + w1 * v + w2 * w
            let normal = simd_normalize(n0 * u + n1 * v + n2 * w)
            let idx = y * atlasW + x
            positionTex[idx] = SIMD4<Float>(world.x, world.y, world.z, 1.0)
            normalTex[idx] = SIMD4<Float>(normal.x, normal.y, normal.z, 0.0)
        }
    }
}

// MARK: - Image / depth I/O

private struct DownsampledPixels {
    let data: UnsafeMutablePointer<UInt8>
    let width: Int
    let height: Int
    let bytesPerRow: Int
}

private func loadDownsampledRGBA(url: URL, targetW: Int, targetH: Int) -> DownsampledPixels? {
    guard
        let src = CGImageSourceCreateWithURL(url as CFURL, nil),
        let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    let bpr = targetW * 4
    let total = bpr * targetH
    let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: total)
    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.noneSkipLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
    guard let ctx = CGContext(
        data: ptr, width: targetW, height: targetH,
        bitsPerComponent: 8, bytesPerRow: bpr,
        space: cs, bitmapInfo: info,
    ) else {
        ptr.deallocate()
        return nil
    }
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
    return DownsampledPixels(data: ptr, width: targetW, height: targetH, bytesPerRow: bpr)
}

private func loadDepthFloats(url: URL, expectedW: Int, expectedH: Int) -> [Float]? {
    guard let data = try? Data(contentsOf: url), data.count >= 8 else { return nil }
    let w = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) }
    let h = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) }
    let pix = Int(w) * Int(h)
    if pix <= 0 { return nil }
    if Int(w) != expectedW || Int(h) != expectedH {
        // Could resample, but for now just bail
        return nil
    }
    var out = [Float](repeating: 0, count: pix)
    out.withUnsafeMutableBufferPointer { buf in
        data.withUnsafeBytes { raw in
            let src = raw.baseAddress!.advanced(by: 8).assumingMemoryBound(to: Float.self)
            memcpy(buf.baseAddress, src, pix * 4)
        }
    }
    return out
}

// MARK: - SIMD packing helpers

private func packSIMD3(_ arr: [SIMD3<Float>]) -> Data {
    var out = Data(count: arr.count * 12)
    out.withUnsafeMutableBytes { raw in
        let dst = raw.baseAddress!.assumingMemoryBound(to: Float.self)
        for (i, v) in arr.enumerated() {
            dst[i * 3 + 0] = v.x
            dst[i * 3 + 1] = v.y
            dst[i * 3 + 2] = v.z
        }
    }
    return out
}

private func unpackSIMD3(_ data: Data, count: Int) -> [SIMD3<Float>] {
    var out = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: count)
    data.withUnsafeBytes { raw in
        let src = raw.baseAddress!.assumingMemoryBound(to: Float.self)
        for i in 0..<count {
            out[i] = SIMD3<Float>(src[i * 3], src[i * 3 + 1], src[i * 3 + 2])
        }
    }
    return out
}

private func unpackSIMD2(_ data: Data, count: Int) -> [SIMD2<Float>] {
    var out = [SIMD2<Float>](repeating: SIMD2<Float>(0, 0), count: count)
    data.withUnsafeBytes { raw in
        let src = raw.baseAddress!.assumingMemoryBound(to: Float.self)
        for i in 0..<count {
            out[i] = SIMD2<Float>(src[i * 2], src[i * 2 + 1])
        }
    }
    return out
}

private func unpackUInt32(_ data: Data, count: Int) -> [UInt32] {
    var out = [UInt32](repeating: 0, count: count)
    data.withUnsafeBytes { raw in
        let src = raw.baseAddress!.assumingMemoryBound(to: UInt32.self)
        for i in 0..<count { out[i] = src[i] }
    }
    return out
}

private func convertNormalsToHalf(_ arr: [SIMD4<Float>]) -> [UInt16] {
    var out = [UInt16](repeating: 0, count: arr.count * 4)
    for (i, v) in arr.enumerated() {
        out[i * 4 + 0] = floatToHalf(v.x)
        out[i * 4 + 1] = floatToHalf(v.y)
        out[i * 4 + 2] = floatToHalf(v.z)
        out[i * 4 + 3] = floatToHalf(v.w)
    }
    return out
}

private func floatToHalf(_ f: Float) -> UInt16 {
    // IEEE 754 single (32-bit) → half (16-bit). Standard formula.
    let bits = f.bitPattern
    let sign = UInt16((bits >> 16) & 0x8000)
    let expF = Int((bits >> 23) & 0xFF) - 127 + 15
    let mantissa = (bits >> 13) & 0x3FF
    if expF >= 31 { return sign | 0x7C00 | UInt16(mantissa)  /* inf/nan */ }
    if expF <= 0 { return sign  /* denormal/underflow → 0 */ }
    return sign | (UInt16(expF) << 10) | UInt16(mantissa)
}
