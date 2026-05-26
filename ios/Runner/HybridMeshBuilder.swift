// HybridMeshBuilder — ARKit mesh + TSDF hole filling combination.
//
// Maqsad: ARKit'ning sharp tekstura'sini saqlash + LiDAR ko'rmagan joylarni
// TSDF reconstruction bilan to'ldirish.
//
// Algoritm:
//   1. ARKit anchor mesh (sharp, lekin hole'lar bilan) — birinchi
//   2. TSDF butun space'da reconstruction yuradi (depth maps'dan watertight)
//   3. TSDF mesh'dan FAQAT hole'larda yotgan triangle'lar tanlanadi:
//      - Har TSDF triangle markazi ARKit triangle markazlariga masofasi
//        tekshirilib >6 sm bo'lsa, hole'da → saqlanadi
//      - Yaqin (≤6 sm) bo'lsa, ARKit allaqachon u yerda mesh bor → tashlaymiz
//   4. ARKit triangles + filtered TSDF triangles = combined mesh
//
// Natija: ARKit ko'rgan joylarda sharp texture, ko'rmagan joylarda smooth fill.

import Foundation
import simd

struct HybridMeshResult {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)]
    let arkitCount: Int       // first arkitCount triangles are ARKit
    let fillCount: Int        // remaining triangles are TSDF hole fill
}

enum HybridMeshBuilder {
    /// ARKit + TSDF mesh'larni birlashtiradi. ARKit asos sifatida saqlanadi,
    /// TSDF triangle'lardan faqat hole'da yotganlari qo'shiladi.
    static func combine(
        arkitVerts: [SIMD3<Float>],
        arkitNormals: [SIMD3<Float>],
        arkitTris: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        tsdfVerts: [SIMD3<Float>],
        tsdfNormals: [SIMD3<Float>],
        tsdfTris: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        minDistanceFromArkit: Float = 0.06,   // 6 sm — bundan yaqinroq → tashla
    ) -> HybridMeshResult {
        if tsdfTris.isEmpty {
            return HybridMeshResult(
                vertices: arkitVerts, normals: arkitNormals, triangles: arkitTris,
                arkitCount: arkitTris.count, fillCount: 0,
            )
        }

        // Spatial hash of ARKit triangle centers for fast nearest-distance lookup
        let cellSize: Float = 0.10   // 10 sm cells
        var arkitGrid: [SIMD3<Int32>: [SIMD3<Float>]] = [:]
        arkitGrid.reserveCapacity(arkitTris.count / 8 + 8)

        @inline(__always) func cellKey(_ p: SIMD3<Float>) -> SIMD3<Int32> {
            return SIMD3<Int32>(
                Int32(floor(p.x / cellSize)),
                Int32(floor(p.y / cellSize)),
                Int32(floor(p.z / cellSize)),
            )
        }

        for tri in arkitTris {
            let c = (arkitVerts[Int(tri.v0)] + arkitVerts[Int(tri.v1)] + arkitVerts[Int(tri.v2)]) / 3
            arkitGrid[cellKey(c), default: []].append(c)
        }

        @inline(__always) func minDistance(from p: SIMD3<Float>) -> Float {
            let key = cellKey(p)
            var best: Float = .infinity
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        let k = SIMD3<Int32>(key.x + Int32(dx), key.y + Int32(dy), key.z + Int32(dz))
                        if let centers = arkitGrid[k] {
                            for q in centers {
                                let d = simd_distance(p, q)
                                if d < best { best = d }
                            }
                        }
                    }
                }
            }
            return best
        }

        // Keep TSDF triangles that are FAR from ARKit (i.e., in hole regions)
        var keepTriIndices: [Int] = []
        keepTriIndices.reserveCapacity(tsdfTris.count / 4)
        for (ti, tri) in tsdfTris.enumerated() {
            let v0 = tsdfVerts[Int(tri.v0)]
            let v1 = tsdfVerts[Int(tri.v1)]
            let v2 = tsdfVerts[Int(tri.v2)]
            let c = (v0 + v1 + v2) / 3
            if minDistance(from: c) >= minDistanceFromArkit {
                keepTriIndices.append(ti)
            }
        }

        NSLog("KADASTR hybrid: ARKit \(arkitTris.count) + TSDF \(tsdfTris.count) → keep \(keepTriIndices.count) hole-fill")

        // Combine: ARKit first (preserves vertex indices), then TSDF vertices used by kept tris
        var combinedVerts = arkitVerts
        var combinedNormals = arkitNormals
        var combinedTris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = arkitTris

        var tsdfVertRemap: [UInt32: UInt32] = [:]

        for ti in keepTriIndices {
            let tri = tsdfTris[ti]
            var indices = [UInt32](repeating: 0, count: 3)
            for (slot, v) in [tri.v0, tri.v1, tri.v2].enumerated() {
                if let mapped = tsdfVertRemap[v] {
                    indices[slot] = mapped
                } else {
                    let newIdx = UInt32(combinedVerts.count)
                    tsdfVertRemap[v] = newIdx
                    combinedVerts.append(tsdfVerts[Int(v)])
                    combinedNormals.append(tsdfNormals[Int(v)])
                    indices[slot] = newIdx
                }
            }
            combinedTris.append((v0: indices[0], v1: indices[1], v2: indices[2]))
        }

        return HybridMeshResult(
            vertices: combinedVerts,
            normals: combinedNormals,
            triangles: combinedTris,
            arkitCount: arkitTris.count,
            fillCount: keepTriIndices.count,
        )
    }
}
