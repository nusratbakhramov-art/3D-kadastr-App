import Foundation
import simd

/// Collapses the overlapping per-frame depth patches produced by `DepthMesher`
/// into a single clean surface.
///
/// `DepthMesher.buildMesh` concatenates one triangulated patch per LiDAR frame,
/// so the same physical wall is represented by many near-coincident layers from
/// different camera poses. That stack causes z-fighting, blocky duplicated
/// surfaces and floating noise. This pass snaps vertices onto a uniform voxel
/// grid (`cell` metres per side): every vertex that lands in the same voxel is
/// merged into ONE output vertex, so coincident layers fuse into a single sheet.
///
/// Winding is preserved exactly. We only *remap* a triangle's indices to the
/// welded vertices and keep the `(a, b, c)` order untouched, so the
/// camera-facing orientation that drives the dollhouse back-face cull survives.
/// Triangles that collapse onto fewer than three distinct voxels are dropped.
enum VoxelWelder {

    /// Weld `mesh` onto a voxel grid of `cell` metres. Returns a deduplicated
    /// `ConsolidatedMesh` with averaged positions, normalized accumulated
    /// normals, and remapped (winding-preserving) triangles.
    ///
    /// - Parameters:
    ///   - mesh: concatenated per-frame mesh from `DepthMesher.buildMesh`.
    ///   - cell: voxel edge length in metres (default 1.2 cm). Larger ⇒ more
    ///           aggressive merging / fewer vertices; smaller ⇒ finer detail.
    static func weld(_ mesh: ConsolidatedMesh, cell: Float = 0.012) -> ConsolidatedMesh {
        let vertexCount = mesh.positions.count
        guard vertexCount > 0, cell > 0 else { return mesh }

        let inv = 1 / cell

        // Map each unique voxel key -> index into the welded vertex arrays.
        // Reserve generously: real scans dedup heavily, but starting roomy
        // avoids rehash churn on the first pass.
        var voxelToWelded = [Int64: Int32](minimumCapacity: vertexCount)

        // welded[i] = old-index -> new welded index, built as we discover voxels.
        var remap = [Int32](repeating: -1, count: vertexCount)

        var weldedPositions: [SIMD3<Float>] = []
        var weldedNormalSums: [SIMD3<Float>] = []
        var weldedCounts: [Float] = []
        weldedPositions.reserveCapacity(vertexCount / 2 + 1)
        weldedNormalSums.reserveCapacity(vertexCount / 2 + 1)
        weldedCounts.reserveCapacity(vertexCount / 2 + 1)

        let positions = mesh.positions
        let normals = mesh.normals
        let hasNormals = normals.count == vertexCount

        for i in 0..<vertexCount {
            let p = positions[i]
            // floor() so the voxel coordinate is stable across the cell boundary
            // and symmetric around the origin (Int conversion truncates toward 0).
            let ix = Int32(floor(p.x * inv))
            let iy = Int32(floor(p.y * inv))
            let iz = Int32(floor(p.z * inv))
            let key = packVoxel(ix, iy, iz)

            let welded: Int32
            if let existing = voxelToWelded[key] {
                welded = existing
                let w = Int(existing)
                weldedPositions[w] += p
                if hasNormals { weldedNormalSums[w] += normals[i] }
                weldedCounts[w] += 1
            } else {
                welded = Int32(weldedPositions.count)
                voxelToWelded[key] = welded
                weldedPositions.append(p)
                weldedNormalSums.append(hasNormals ? normals[i] : SIMD3<Float>(0, 0, 0))
                weldedCounts.append(1)
            }
            remap[i] = welded
        }

        // Average accumulated positions; normalize accumulated normals.
        let outCount = weldedPositions.count
        var outPositions = [SIMD3<Float>](repeating: .zero, count: outCount)
        var outNormals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: outCount)
        for w in 0..<outCount {
            let c = weldedCounts[w]
            outPositions[w] = weldedPositions[w] / c
            let nLen = simd_length(weldedNormalSums[w])
            if nLen > 1e-5 {
                outNormals[w] = weldedNormalSums[w] / nLen
            }
        }

        // Remap triangles, preserving (a, b, c) winding. Drop triangles that
        // collapse onto fewer than three distinct voxels, AND deduplicate the
        // many identical triangles the overlapping per-frame layers produce
        // (same 3 voxels). Without this dedup the triangle count barely drops
        // even though the geometry has fused — which starves the atlas packer.
        let oldIndices = mesh.indices
        var outIndices: [UInt32] = []
        outIndices.reserveCapacity(oldIndices.count)
        var seen = Set<Int64>()
        var t = 0
        let triEnd = oldIndices.count - 2
        while t < triEnd {
            let a = remap[Int(oldIndices[t])]
            let b = remap[Int(oldIndices[t + 1])]
            let c = remap[Int(oldIndices[t + 2])]
            if a != b && a != c && b != c {
                // Canonical (sorted) key so duplicates collapse regardless of winding.
                var s0 = a, s1 = b, s2 = c
                if s0 > s1 { swap(&s0, &s1) }
                if s1 > s2 { swap(&s1, &s2) }
                if s0 > s1 { swap(&s0, &s1) }
                let key = (Int64(s0) << 42) | (Int64(s1) << 21) | Int64(s2)
                if seen.insert(key).inserted {
                    outIndices.append(UInt32(a))
                    outIndices.append(UInt32(b))
                    outIndices.append(UInt32(c))
                }
            }
            t += 3
        }

        return ConsolidatedMesh(positions: outPositions, normals: outNormals, indices: outIndices)
    }

    /// Pack signed voxel coords into a single Int64 key. Each axis gets 21 bits
    /// (range ±1,048,575 voxels ⇒ ±~12.6 km at 1.2 cm cells — far beyond any
    /// room), biased to non-negative before packing so the bit layout is unique.
    @inline(__always)
    private static func packVoxel(_ x: Int32, _ y: Int32, _ z: Int32) -> Int64 {
        let bias: Int64 = 1 << 20            // 1,048,576
        let mask: Int64 = (1 << 21) - 1      // 21 bits
        let bx = (Int64(x) + bias) & mask
        let by = (Int64(y) + bias) & mask
        let bz = (Int64(z) + bias) & mask
        return (bx << 42) | (by << 21) | bz
    }
}
