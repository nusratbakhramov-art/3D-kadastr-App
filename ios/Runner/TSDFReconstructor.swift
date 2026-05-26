// TSDFReconstructor — Volumetric surface reconstruction from LiDAR depth maps.
//
// Algoritm:
//   1. Bounding box hisoblanadi (ARKit mesh vertex'laridan)
//   2. Voxel grid yaratish (default 2cm rezolyutsiya)
//   3. Har photo'ning LiDAR depth map'ini Metal compute orqali grid'ga integrate
//   4. Optional smoothing
//   5. Marching cubes (CPU) → watertight triangle mesh
//
// Output: hole-free mesh ARKit'ning chala mesh'iga qaraganda.

import Foundation
import Metal
import simd

struct TSDFInputCamera {
    let transform: simd_float4x4
    let intrinsics: simd_float3x3   // calibrated for RGB image
    let imageWidth: Float            // RGB image full width (intrinsics reference)
    let imageHeight: Float           // RGB image full height
    let depthURL: URL
    let depthWidth: Int              // depth map actual width
    let depthHeight: Int
}

struct TSDFResult {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)]
    let voxelSize: Float
}

enum TSDFError: Error {
    case metalSetup(String)
    case noCameras
}

final class TSDFReconstructor {
    static func reconstruct(
        boundingMin: SIMD3<Float>,
        boundingMax: SIMD3<Float>,
        cameras: [TSDFInputCamera],
        voxelSize: Float = 0.025,    // 2.5 cm
        truncation: Float = 0.10,    // 10 cm (4 voxels)
        maxIntegrationDepth: Float = 4.0,
        progress: ((Float, String) -> Void)? = nil,
    ) throws -> TSDFResult {
        guard !cameras.isEmpty else { throw TSDFError.noCameras }

        progress?(0.0, "TSDF grid yaratish…")

        // Pad bbox to ensure coverage
        let pad: Float = 0.20
        let bMin = boundingMin - SIMD3<Float>(repeating: pad)
        let bMax = boundingMax + SIMD3<Float>(repeating: pad)
        let extent = bMax - bMin

        let gridX = max(8, Int(ceil(extent.x / voxelSize)))
        let gridY = max(8, Int(ceil(extent.y / voxelSize)))
        let gridZ = max(8, Int(ceil(extent.z / voxelSize)))
        let totalVoxels = gridX * gridY * gridZ

        progress?(0.05, "Grid: \(gridX)×\(gridY)×\(gridZ) = \(totalVoxels) voxel")

        // ────────────────────────────────────────────────────────────────────
        // Metal setup
        // ────────────────────────────────────────────────────────────────────
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              let integrateFn = library.makeFunction(name: "integrateDepth"),
              let cmdQueue = device.makeCommandQueue()
        else { throw TSDFError.metalSetup("Metal init") }
        let integrateState = try device.makeComputePipelineState(function: integrateFn)

        // Allocate SDF + weight buffers
        let bufferLen = totalVoxels * 4  // float32
        guard let sdfBuf = device.makeBuffer(length: bufferLen, options: .storageModeShared),
              let wBuf = device.makeBuffer(length: bufferLen, options: .storageModeShared)
        else { throw TSDFError.metalSetup("buffer alloc") }
        memset(sdfBuf.contents(), 0, bufferLen)
        memset(wBuf.contents(), 0, bufferLen)

        // Params constant
        struct TSDFParams {
            var originX: Float; var originY: Float; var originZ: Float; var voxelSize: Float
            var gridX: UInt32; var gridY: UInt32; var gridZ: UInt32; var pad1: UInt32
            var truncation: Float; var maxDepth: Float; var pad2: Float; var pad3: Float
        }
        var params = TSDFParams(
            originX: bMin.x, originY: bMin.y, originZ: bMin.z, voxelSize: voxelSize,
            gridX: UInt32(gridX), gridY: UInt32(gridY), gridZ: UInt32(gridZ), pad1: 0,
            truncation: truncation, maxDepth: maxIntegrationDepth, pad2: 0, pad3: 0,
        )

        struct TSDFCamera {
            var invTransform: simd_float4x4
            var intrinsics: simd_float3x3
            var imageSize: SIMD2<Float>
        }

        // Auto-detect actual depth dims from the first available depth file
        // (camera struct's depthWidth/Height may not match the saved file)
        var depthW = cameras[0].depthWidth
        var depthH = cameras[0].depthHeight
        for cam in cameras {
            if let probe = loadDepthFloatsWithDims(url: cam.depthURL) {
                depthW = probe.width
                depthH = probe.height
                NSLog("KADASTR TSDF probed depth dims: \(depthW)×\(depthH)")
                break
            }
        }
        let depthTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MTLPixelFormat.r32Float, width: depthW, height: depthH, mipmapped: false,
        )
        depthTexDesc.usage = MTLTextureUsage.shaderRead
        depthTexDesc.storageMode = MTLStorageMode.shared
        guard let depthTex = device.makeTexture(descriptor: depthTexDesc) else {
            throw TSDFError.metalSetup("depth tex")
        }

        // ────────────────────────────────────────────────────────────────────
        // Integrate each camera
        // ────────────────────────────────────────────────────────────────────
        let tgSize = MTLSize(width: 4, height: 4, depth: 4)
        let tgCount = MTLSize(
            width: (gridX + 3) / 4,
            height: (gridY + 3) / 4,
            depth: (gridZ + 3) / 4,
        )

        var loadedCount = 0
        var skippedCount = 0
        for (i, cam) in cameras.enumerated() {
            autoreleasepool {
                guard let depthData = loadDepthFloats(url: cam.depthURL, expectedW: depthW, expectedH: depthH) else {
                    skippedCount += 1
                    if skippedCount <= 3 {
                        NSLog("KADASTR TSDF depth skip [\(i)]: url=\(cam.depthURL.lastPathComponent) expected=\(depthW)×\(depthH)")
                    }
                    return
                }
                loadedCount += 1
                depthData.withUnsafeBufferPointer { buf in
                    depthTex.replace(
                        region: MTLRegionMake2D(0, 0, depthW, depthH),
                        mipmapLevel: 0,
                        withBytes: buf.baseAddress!,
                        bytesPerRow: depthW * 4,
                    )
                }

                var camStruct = TSDFCamera(
                    invTransform: cam.transform.inverse,
                    intrinsics: cam.intrinsics,
                    imageSize: SIMD2<Float>(cam.imageWidth, cam.imageHeight),
                )
                guard let camBuf = device.makeBuffer(bytes: &camStruct, length: MemoryLayout<TSDFCamera>.stride, options: .storageModeShared),
                      let paramBuf = device.makeBuffer(bytes: &params, length: MemoryLayout<TSDFParams>.stride, options: .storageModeShared),
                      let cmdBuf = cmdQueue.makeCommandBuffer(),
                      let enc = cmdBuf.makeComputeCommandEncoder()
                else { return }
                enc.setComputePipelineState(integrateState)
                enc.setBuffer(sdfBuf, offset: 0, index: 0)
                enc.setBuffer(wBuf, offset: 0, index: 1)
                enc.setBuffer(paramBuf, offset: 0, index: 2)
                enc.setBuffer(camBuf, offset: 0, index: 3)
                enc.setTexture(depthTex, index: 0)
                enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
                enc.endEncoding()
                cmdBuf.commit()
                cmdBuf.waitUntilCompleted()
            }

            if (i + 1) % 5 == 0 || i == cameras.count - 1 {
                progress?(
                    0.10 + 0.70 * Float(i + 1) / Float(cameras.count),
                    "Integrate \(i + 1)/\(cameras.count)",
                )
            }
        }

        NSLog("KADASTR TSDF integ: loaded=\(loadedCount), skipped=\(skippedCount), bbox=\(bMin)..\(bMax)")

        // ────────────────────────────────────────────────────────────────────
        // Marching cubes (CPU)
        // ────────────────────────────────────────────────────────────────────
        progress?(0.82, "Marching cubes…")
        let sdfPtr = sdfBuf.contents().assumingMemoryBound(to: Float.self)
        let wPtr = wBuf.contents().assumingMemoryBound(to: Float.self)

        let sdfArray = UnsafeBufferPointer(start: sdfPtr, count: totalVoxels)
        let weightArray = UnsafeBufferPointer(start: wPtr, count: totalVoxels)

        let result = marchingCubes(
            sdf: sdfArray, weight: weightArray,
            gridX: gridX, gridY: gridY, gridZ: gridZ,
            origin: bMin, voxelSize: voxelSize,
            progress: { p in progress?(0.82 + p * 0.12, "Marching cubes…") },
        )

        progress?(0.95, "Vertex dedupe…")

        // Vertex deduplication — MC har triangle uchun 3 ta yangi vertex chiqaradi
        // (triangle soup). Dedupe qilmasak xatlas chukib qoladi. Position'ni
        // 0.5mm aniqlikgacha yaxlitlab hash key sifatida ishlatamiz.
        let deduped = dedupeMesh(vertices: result.vertices, normals: result.normals, triangles: result.triangles)

        progress?(0.98, "Mesh: \(deduped.vertices.count) vert, \(deduped.triangles.count) tri")
        progress?(1.0, "TSDF ✓")

        return TSDFResult(
            vertices: deduped.vertices,
            normals: deduped.normals,
            triangles: deduped.triangles,
            voxelSize: voxelSize,
        )
    }
}

// MARK: - Marching cubes (CPU)

private struct MCResult {
    var vertices: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)]
}

private func marchingCubes(
    sdf: UnsafeBufferPointer<Float>,
    weight: UnsafeBufferPointer<Float>,
    gridX: Int, gridY: Int, gridZ: Int,
    origin: SIMD3<Float>,
    voxelSize: Float,
    progress: (Float) -> Void,
) -> MCResult {
    var vertices: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
    vertices.reserveCapacity(200_000)
    triangles.reserveCapacity(100_000)

    @inline(__always) func idx(_ x: Int, _ y: Int, _ z: Int) -> Int {
        return x + y * gridX + z * gridX * gridY
    }
    @inline(__always) func validCorner(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        return weight[idx(x, y, z)] > 0.5
    }

    let cornerOffsets: [(Int, Int, Int)] = [
        (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
        (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1),
    ]
    // Edge endpoints (which corners each of 12 edges connects)
    let edgeEnds: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 0),
        (4, 5), (5, 6), (6, 7), (7, 4),
        (0, 4), (1, 5), (2, 6), (3, 7),
    ]

    let edgeTable = MarchingCubesTables.edgeTable
    let triTable = MarchingCubesTables.triTable

    let cellsX = gridX - 1
    let cellsY = gridY - 1
    let cellsZ = gridZ - 1
    let totalCells = cellsX * cellsY * cellsZ
    var processedCells = 0

    for z in 0..<cellsZ {
        for y in 0..<cellsY {
            for x in 0..<cellsX {
                // Skip if any corner has zero weight (no data)
                var allValid = true
                for off in cornerOffsets where !validCorner(x + off.0, y + off.1, z + off.2) {
                    allValid = false
                    break
                }
                if !allValid { continue }

                // Compute case index
                var caseIdx = 0
                var cornerVals = [Float](repeating: 0, count: 8)
                for (i, off) in cornerOffsets.enumerated() {
                    let v = sdf[idx(x + off.0, y + off.1, z + off.2)]
                    cornerVals[i] = v
                    if v < 0 { caseIdx |= (1 << i) }
                }
                if caseIdx == 0 || caseIdx == 255 { continue }
                let edgeMask = edgeTable[caseIdx]
                if edgeMask == 0 { continue }

                // For each of 12 edges, if intersected, compute vertex
                var edgeVerts = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: 12)
                for e in 0..<12 where (edgeMask & (1 << e)) != 0 {
                    let (a, b) = edgeEnds[e]
                    let oa = cornerOffsets[a]
                    let ob = cornerOffsets[b]
                    let pa = SIMD3<Float>(Float(x + oa.0), Float(y + oa.1), Float(z + oa.2))
                    let pb = SIMD3<Float>(Float(x + ob.0), Float(y + ob.1), Float(z + ob.2))
                    let va = cornerVals[a]
                    let vb = cornerVals[b]
                    let t = (abs(vb - va) > 1e-6) ? (-va / (vb - va)) : 0.5
                    let p = mix(pa, pb, t: t)
                    edgeVerts[e] = origin + p * voxelSize
                }

                // Emit triangles
                let row = triTable[caseIdx]
                var i = 0
                while i + 2 < 16 && row[i] >= 0 {
                    let e0 = Int(row[i])
                    let e1 = Int(row[i + 1])
                    let e2 = Int(row[i + 2])
                    let v0 = edgeVerts[e0]
                    let v1 = edgeVerts[e1]
                    let v2 = edgeVerts[e2]
                    let a = v1 - v0
                    let b = v2 - v0
                    let nVec = SIMD3<Float>(
                        a.y * b.z - a.z * b.y,
                        a.z * b.x - a.x * b.z,
                        a.x * b.y - a.y * b.x,
                    )
                    let n = simd_normalize(nVec)
                    let base = UInt32(vertices.count)
                    vertices.append(v0)
                    vertices.append(v1)
                    vertices.append(v2)
                    normals.append(n)
                    normals.append(n)
                    normals.append(n)
                    triangles.append((base, base + 1, base + 2))
                    i += 3
                }

                processedCells += 1
            }
        }
        if z % 10 == 0 {
            progress(Float(z * cellsX * cellsY + cellsX * cellsY) / Float(max(totalCells, 1)))
        }
    }

    return MCResult(vertices: vertices, normals: normals, triangles: triangles)
}

@inline(__always)
private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    return a + (b - a) * t
}

// MARK: - Vertex deduplication

/// Marching cubes triangle soup'ini shared-vertex mesh'ga aylantiradi.
/// Position 0.5mm gacha yaxlitlanib hash key sifatida ishlatiladi.
/// Bir xil pozitsiyadagi normal'lar o'rtacha olinadi.
/// Degenerate triangle'lar (2+ vertex bir xil) tashlanadi.
private func dedupeMesh(
    vertices: [SIMD3<Float>],
    normals: [SIMD3<Float>],
    triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
) -> MCResult {
    let scale: Float = 2000  // 0.5 mm precision
    var dedupeMap: [SIMD3<Int32>: UInt32] = [:]
    dedupeMap.reserveCapacity(vertices.count / 3)
    var remap = [UInt32](repeating: 0, count: vertices.count)
    var newVerts: [SIMD3<Float>] = []
    var normalSum: [SIMD3<Float>] = []
    var normalCount: [Int] = []
    newVerts.reserveCapacity(vertices.count / 3)
    normalSum.reserveCapacity(vertices.count / 3)
    normalCount.reserveCapacity(vertices.count / 3)

    for (oldIdx, v) in vertices.enumerated() {
        let key = SIMD3<Int32>(
            Int32((v.x * scale).rounded()),
            Int32((v.y * scale).rounded()),
            Int32((v.z * scale).rounded()),
        )
        if let existing = dedupeMap[key] {
            remap[oldIdx] = existing
            normalSum[Int(existing)] += normals[oldIdx]
            normalCount[Int(existing)] += 1
        } else {
            let newIdx = UInt32(newVerts.count)
            dedupeMap[key] = newIdx
            remap[oldIdx] = newIdx
            newVerts.append(v)
            normalSum.append(normals[oldIdx])
            normalCount.append(1)
        }
    }

    // Average normals
    var newNormals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: newVerts.count)
    for i in 0..<newVerts.count {
        let n = normalSum[i] / Float(max(normalCount[i], 1))
        let len = simd_length(n)
        newNormals[i] = len > 1e-6 ? n / len : SIMD3<Float>(0, 1, 0)
    }

    // Remap triangle indices; drop degenerate
    var newTris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
    newTris.reserveCapacity(triangles.count)
    for t in triangles {
        let i0 = remap[Int(t.v0)]
        let i1 = remap[Int(t.v1)]
        let i2 = remap[Int(t.v2)]
        if i0 != i1 && i1 != i2 && i0 != i2 {
            newTris.append((v0: i0, v1: i1, v2: i2))
        }
    }

    return MCResult(vertices: newVerts, normals: newNormals, triangles: newTris)
}

// MARK: - Depth loader

/// Loads depth file (w, h, w*h floats). Returns the loaded array AND actual
/// dimensions (which may differ from expectations).
private func loadDepthFloatsWithDims(url: URL) -> (data: [Float], width: Int, height: Int)? {
    guard let data = try? Data(contentsOf: url), data.count >= 8 else { return nil }
    let w = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) }
    let h = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) }
    let pix = Int(w) * Int(h)
    if pix <= 0 { return nil }
    let expectedBytes = 8 + pix * 4
    if data.count < expectedBytes { return nil }
    var out = [Float](repeating: 0, count: pix)
    out.withUnsafeMutableBufferPointer { buf in
        data.withUnsafeBytes { raw in
            let src = raw.baseAddress!.advanced(by: 8).assumingMemoryBound(to: Float.self)
            memcpy(buf.baseAddress, src, pix * 4)
        }
    }
    return (out, Int(w), Int(h))
}

private func loadDepthFloats(url: URL, expectedW: Int, expectedH: Int) -> [Float]? {
    guard let r = loadDepthFloatsWithDims(url: url) else { return nil }
    if r.width != expectedW || r.height != expectedH { return nil }
    return r.data
}
