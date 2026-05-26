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
    static func bake(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        cameras: [AtlasBakeInputCamera],
        atlasResolution: Int = 2048,
        cameraBatchSize: Int = 16,
        downsampleFactor: Int = 2,  // 1920×1440 → 960×720
        progress: ((Float, String) -> Void)? = nil,
    ) throws -> AtlasBakeResult {
        // ────────────────────────────────────────────────────────────────────
        // 1. xatlas UV unwrap
        // ────────────────────────────────────────────────────────────────────
        progress?(0.0, "xatlas UV unwrap…")
        let posData = positions.withUnsafeBufferPointer {
            Data(buffer: UnsafeBufferPointer(start: $0.baseAddress, count: $0.count))
        }
        let nrmData = normals.withUnsafeBufferPointer {
            Data(buffer: UnsafeBufferPointer(start: $0.baseAddress, count: $0.count))
        }
        // SIMD3<Float> stride = 16. xatlas C API kutadigan stride = 12 (3 floats).
        // Pack tightly: rebuild 3-float-packed buffers.
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
        let atlasW: Int = Int(truncatingIfNeeded: xResult.atlasWidth)
        let atlasH: Int = Int(truncatingIfNeeded: xResult.atlasHeight)
        progress?(0.10, "Atlas: \(atlasW)×\(atlasH), \(outVC) vert, \(outIC/3) tri")

        // Unpack output
        let outPositions = unpackSIMD3(xResult.positions, count: outVC)
        let outNormals = unpackSIMD3(xResult.normals, count: outVC)
        let outUVs = unpackSIMD2(xResult.uvs, count: outVC)
        let outIndices = unpackUInt32(xResult.indices, count: outIC)

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
            let dilFunc = library.makeFunction(name: "dilateAtlas")
        else {
            throw AtlasBakeError.metalSetup("kernel functions not found")
        }
        let bakeState = try device.makeComputePipelineState(function: bakeFunc)
        let normState = try device.makeComputePipelineState(function: normFunc)
        let dilState = try device.makeComputePipelineState(function: dilFunc)
        guard let cmdQueue = device.makeCommandQueue() else {
            throw AtlasBakeError.metalSetup("command queue")
        }

        // Allocate accumulator buffers
        let pixCount = atlasW * atlasH
        let colorBuf = device.makeBuffer(length: pixCount * 16, options: .storageModeShared)!
        let weightBuf = device.makeBuffer(length: pixCount * 4, options: .storageModeShared)!
        memset(colorBuf.contents(), 0, pixCount * 16)
        memset(weightBuf.contents(), 0, pixCount * 4)

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
        let atlasTex = device.makeTexture(descriptor: outTexDesc)!
        let dilatedTex = device.makeTexture(descriptor: outTexDesc)!

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
                camPtr[slot] = makeMetalCam(cam)
            }

            // Build params
            var params = AtlasParams(
                cameraCount: UInt32(batchCount),
                atlasW: UInt32(atlasW),
                atlasH: UInt32(atlasH),
                minCamAlign: 0.05,  // 0.15→0.05: ko'proq kamera contribute qiladi
                minFaceDot: 0.05,  // 0.18→0.05 (~87°): yon angle'lar ham qabul
                maxDistance: 8.0,  // 6→8 m: uzoq devor/pol uchun
                occlusionTolerance: 100.0,  // ~disabled — diagnostic: ko'p gray sabab occlusion emasligini bilish
                pad: 0,
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

        do {
            guard let cmdBuf = cmdQueue.makeCommandBuffer(),
                  let enc = cmdBuf.makeComputeCommandEncoder() else {
                throw AtlasBakeError.metalSetup("normalize encoder")
            }
            enc.setComputePipelineState(normState)
            enc.setBuffer(colorBuf, offset: 0, index: 0)
            enc.setBuffer(weightBuf, offset: 0, index: 1)
            enc.setTexture(posTexture, index: 0)
            enc.setTexture(atlasTex, index: 1)
            let tgSize = MTLSize(width: 16, height: 16, depth: 1)
            let tgCount = MTLSize(width: (atlasW + 15) / 16, height: (atlasH + 15) / 16, depth: 1)
            enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
        }

        // Dilate (2 passes — boundary'larni biroz kengaytirish)
        var src = atlasTex
        var dst = dilatedTex
        for _ in 0..<2 {
            guard let cmdBuf = cmdQueue.makeCommandBuffer(),
                  let enc = cmdBuf.makeComputeCommandEncoder() else { break }
            enc.setComputePipelineState(dilState)
            enc.setTexture(src, index: 0)
            enc.setTexture(dst, index: 1)
            let tgSize = MTLSize(width: 16, height: 16, depth: 1)
            let tgCount = MTLSize(width: (atlasW + 15) / 16, height: (atlasH + 15) / 16, depth: 1)
            enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            swap(&src, &dst)
        }
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
        let maxTexSize = 4096
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
}

private func makeMetalCam(_ cam: AtlasBakeInputCamera) -> MetalAtlasCamera {
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
    )
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
