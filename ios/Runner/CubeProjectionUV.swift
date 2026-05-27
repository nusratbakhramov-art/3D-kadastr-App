// CubeProjectionUV — Variant B: xatlas o'rniga oddiy cube projection UV unwrap.
//
// Maqsad: chart fragment artifact'larini butunlay yo'q qilish. xatlas mesh'ni
// minglab kichik chart'larga bo'ladi → render'da gap/seam'lar ko'rinadi.
// Cube projection esa har triangle'ni 6 ta yuzdan biriga proyeksiya qiladi —
// JAMI 6 chart bor, fragment yo'q.
//
// Atlas layout (4096×4096 → 3×2 grid, har face = 1365×2048):
//   +X  |  +Y  |  +Z
//   ----+------+----
//   -X  |  -Y  |  -Z
//
// Trade-off:
//   ✅ NO fragment artifact (faqat 6 chart)
//   ✅ Tezroq (xatlas yo'q, ~100ms)
//   ⚠️  UV distortion oblik yuzlarda (45° devor → biroz cho'zilgan)
//   ⚠️  Triangle vertex sharing yo'q → output vert count = 3 × tri count

import Foundation
import simd

enum CubeProjectionUV {

    struct Result {
        let positions: [SIMD3<Float>]    // 3 × triCount (no sharing)
        let normals: [SIMD3<Float>]
        let uvs: [SIMD2<Float>]
        let indices: [UInt32]            // sequential: 0,1,2, 3,4,5, ...
        let atlasWidth: Int
        let atlasHeight: Int
    }

    /// Cube projection unwrap. Har triangle dominant normal yo'nalishiga
    /// proyeksiya qilinadi (6 ta cube face'dan biri).
    static func unwrap(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        atlasResolution: Int = 4096,
    ) -> Result {
        // Atlas layout: 3 cols × 2 rows. Each face takes 1/3 width × 1/2 height.
        let atlasW = atlasResolution
        let atlasH = atlasResolution
        let cellW = atlasW / 3   // ~1365 for 4096
        let cellH = atlasH / 2   // 2048 for 4096
        let cellPaddingPx: Float = 8  // border in atlas pixels (safe bleed)

        // 6 faces: +X(0), +Y(1), +Z(2), -X(3), -Y(4), -Z(5)
        let cellOriginPx: [(x: Int, y: Int)] = [
            (0 * cellW, 0 * cellH),         // +X (top-left)
            (1 * cellW, 0 * cellH),         // +Y
            (2 * cellW, 0 * cellH),         // +Z
            (0 * cellW, 1 * cellH),         // -X (bottom-left)
            (1 * cellW, 1 * cellH),         // -Y
            (2 * cellW, 1 * cellH),         // -Z
        ]

        // 1. Triangle → face assignment + collect projected coords per face
        struct TriFaceData {
            let faceIdx: Int
            let world0, world1, world2: SIMD3<Float>
            let proj0, proj1, proj2: SIMD2<Float>    // 2D before normalize
            let normal: SIMD3<Float>                  // averaged normal
        }
        var triData: [TriFaceData] = []
        triData.reserveCapacity(triangles.count)

        // Per-face min/max for normalization
        var faceMin: [SIMD2<Float>] = Array(repeating: SIMD2<Float>( .infinity,  .infinity), count: 6)
        var faceMax: [SIMD2<Float>] = Array(repeating: SIMD2<Float>(-.infinity, -.infinity), count: 6)

        for tri in triangles {
            let v0 = positions[Int(tri.v0)]
            let v1 = positions[Int(tri.v1)]
            let v2 = positions[Int(tri.v2)]
            let n0 = normals[Int(tri.v0)]
            let n1 = normals[Int(tri.v1)]
            let n2 = normals[Int(tri.v2)]
            // Triangle's geometric normal
            let geomN = simd_cross(v1 - v0, v2 - v0)
            let glen = simd_length(geomN)
            let avgN: SIMD3<Float>
            if glen > 1e-9 {
                avgN = geomN / glen
            } else {
                let nsum = n0 + n1 + n2
                let nlen = simd_length(nsum)
                avgN = nlen > 1e-9 ? nsum / nlen : SIMD3<Float>(0, 1, 0)
            }

            // Dominant axis (largest absolute component)
            let absN = SIMD3<Float>(abs(avgN.x), abs(avgN.y), abs(avgN.z))
            let faceIdx: Int
            let proj0: SIMD2<Float>
            let proj1: SIMD2<Float>
            let proj2: SIMD2<Float>
            if absN.x >= absN.y && absN.x >= absN.z {
                // X-dominant face
                if avgN.x > 0 {
                    faceIdx = 0  // +X: drop X, UV = (-Z, Y)
                    proj0 = SIMD2<Float>(-v0.z, v0.y)
                    proj1 = SIMD2<Float>(-v1.z, v1.y)
                    proj2 = SIMD2<Float>(-v2.z, v2.y)
                } else {
                    faceIdx = 3  // -X: drop X, UV = (Z, Y)
                    proj0 = SIMD2<Float>(v0.z, v0.y)
                    proj1 = SIMD2<Float>(v1.z, v1.y)
                    proj2 = SIMD2<Float>(v2.z, v2.y)
                }
            } else if absN.y >= absN.z {
                // Y-dominant face
                if avgN.y > 0 {
                    faceIdx = 1  // +Y: drop Y, UV = (X, Z)
                    proj0 = SIMD2<Float>(v0.x, v0.z)
                    proj1 = SIMD2<Float>(v1.x, v1.z)
                    proj2 = SIMD2<Float>(v2.x, v2.z)
                } else {
                    faceIdx = 4  // -Y: drop Y, UV = (X, -Z)
                    proj0 = SIMD2<Float>(v0.x, -v0.z)
                    proj1 = SIMD2<Float>(v1.x, -v1.z)
                    proj2 = SIMD2<Float>(v2.x, -v2.z)
                }
            } else {
                // Z-dominant face
                if avgN.z > 0 {
                    faceIdx = 2  // +Z: drop Z, UV = (X, Y)
                    proj0 = SIMD2<Float>(v0.x, v0.y)
                    proj1 = SIMD2<Float>(v1.x, v1.y)
                    proj2 = SIMD2<Float>(v2.x, v2.y)
                } else {
                    faceIdx = 5  // -Z: drop Z, UV = (-X, Y)
                    proj0 = SIMD2<Float>(-v0.x, v0.y)
                    proj1 = SIMD2<Float>(-v1.x, v1.y)
                    proj2 = SIMD2<Float>(-v2.x, v2.y)
                }
            }

            // Update face bounding box
            for p in [proj0, proj1, proj2] {
                faceMin[faceIdx] = simd_min(faceMin[faceIdx], p)
                faceMax[faceIdx] = simd_max(faceMax[faceIdx], p)
            }

            triData.append(TriFaceData(
                faceIdx: faceIdx,
                world0: v0, world1: v1, world2: v2,
                proj0: proj0, proj1: proj1, proj2: proj2,
                normal: avgN,
            ))
        }

        // 2. Build output vertex/UV/index arrays.
        // Each triangle → 3 new vertices (no sharing).
        var outPos: [SIMD3<Float>] = []
        var outNrm: [SIMD3<Float>] = []
        var outUVs: [SIMD2<Float>] = []
        var outIdx: [UInt32] = []
        outPos.reserveCapacity(triangles.count * 3)
        outNrm.reserveCapacity(triangles.count * 3)
        outUVs.reserveCapacity(triangles.count * 3)
        outIdx.reserveCapacity(triangles.count * 3)

        // Pre-compute per-face normalization: each face's projected coords
        // mapped to [0, 1] within its atlas cell, with padding.
        struct FaceTransform {
            let offset: SIMD2<Float>     // -faceMin
            let scaleU: Float            // (cellW - 2*pad) / atlasW / range.x
            let scaleV: Float            // (cellH - 2*pad) / atlasH / range.y
            let originU: Float           // cellOrigin.x + pad, atlas-normalized
            let originV: Float           // cellOrigin.y + pad
        }
        var faceTx: [FaceTransform] = []
        faceTx.reserveCapacity(6)
        for fi in 0..<6 {
            let minP = faceMin[fi]
            let maxP = faceMax[fi]
            var range = maxP - minP
            if range.x < 1e-6 { range.x = 1 }
            if range.y < 1e-6 { range.y = 1 }
            let usableW = Float(cellW) - 2 * cellPaddingPx
            let usableH = Float(cellH) - 2 * cellPaddingPx
            // Uniform scale per axis (preserve aspect: take min of W/range.x and H/range.y)
            let scaleU = usableW / range.x / Float(atlasW)
            let scaleV = usableH / range.y / Float(atlasH)
            let originU = (Float(cellOriginPx[fi].x) + cellPaddingPx) / Float(atlasW)
            let originV = (Float(cellOriginPx[fi].y) + cellPaddingPx) / Float(atlasH)
            faceTx.append(FaceTransform(
                offset: -minP,
                scaleU: scaleU, scaleV: scaleV,
                originU: originU, originV: originV,
            ))
        }

        func transformUV(faceIdx: Int, proj: SIMD2<Float>) -> SIMD2<Float> {
            let tx = faceTx[faceIdx]
            let shifted = proj + tx.offset
            return SIMD2<Float>(
                tx.originU + shifted.x * tx.scaleU,
                tx.originV + shifted.y * tx.scaleV,
            )
        }

        for (ti, tri) in triangles.enumerated() {
            let data = triData[ti]
            let n0 = normals[Int(tri.v0)]
            let n1 = normals[Int(tri.v1)]
            let n2 = normals[Int(tri.v2)]
            let uv0 = transformUV(faceIdx: data.faceIdx, proj: data.proj0)
            let uv1 = transformUV(faceIdx: data.faceIdx, proj: data.proj1)
            let uv2 = transformUV(faceIdx: data.faceIdx, proj: data.proj2)
            let base = UInt32(outPos.count)
            outPos.append(data.world0); outPos.append(data.world1); outPos.append(data.world2)
            outNrm.append(n0); outNrm.append(n1); outNrm.append(n2)
            outUVs.append(uv0); outUVs.append(uv1); outUVs.append(uv2)
            outIdx.append(base); outIdx.append(base + 1); outIdx.append(base + 2)
        }

        // Per-face tri count diagnostic
        var faceCounts = [Int](repeating: 0, count: 6)
        for d in triData { faceCounts[d.faceIdx] += 1 }
        NSLog("KADASTR CubeUV faces: +X=\(faceCounts[0]) +Y=\(faceCounts[1]) +Z=\(faceCounts[2]) -X=\(faceCounts[3]) -Y=\(faceCounts[4]) -Z=\(faceCounts[5])")

        return Result(
            positions: outPos, normals: outNrm, uvs: outUVs, indices: outIdx,
            atlasWidth: atlasW, atlasHeight: atlasH,
        )
    }
}
