import Foundation
import simd

/// Post-weld noise removal for the depth-reconstructed mesh.
///
/// `DepthMesher` concatenates per-frame patches; after `VoxelWelder.weld` fuses
/// coincident vertices into a single shared-vertex mesh, the surface forms a few
/// large connected components (walls, floor, furniture) plus many tiny floating
/// fragments — speckle from depth noise, stray edges at discontinuities, and
/// half-seen objects. Those fragments are visually distracting "flying bits".
///
/// This pass treats the welded mesh as a graph (vertices = nodes, triangles
/// connect their 3 vertices) and discards every connected component whose
/// triangle count falls below a threshold, keeping only substantial surfaces.
///
/// Winding is preserved exactly: surviving triangles keep their original
/// `(a, b, c)` order — only the integer index *values* are remapped to the
/// compacted vertex array. This upholds the inward-normal / dollhouse-cutaway
/// invariant the viewer relies on.
enum MeshCleanup {

    /// Remove small disconnected islands (flying noise bits).
    ///
    /// Connectivity is defined by shared vertices: two triangles are in the same
    /// component if they share at least one vertex (directly or transitively).
    ///
    /// - Parameters:
    ///   - mesh: an already-welded mesh (shared vertices). Call this *after*
    ///     `VoxelWelder.weld` — on the raw concatenated DepthMesher output every
    ///     per-frame patch is a separate component and nothing would merge.
    ///   - minComponentTriangles: keep only components with at least this many
    ///     triangles. ~80 is a good default for room scans.
    /// - Returns: a compact mesh containing only surviving triangles and the
    ///   vertices they reference, with winding order preserved per triangle.
    static func removeSmallComponents(
        _ mesh: ConsolidatedMesh,
        minComponentTriangles: Int = 80
    ) -> ConsolidatedMesh {
        let vertexCount = mesh.positions.count
        let triCount = mesh.indices.count / 3

        // Nothing to do on trivial input.
        guard vertexCount > 0, triCount > 0, minComponentTriangles > 1 else {
            return mesh
        }

        // --- Union-find (disjoint set) over vertices, with path compression
        //     and union by rank for near-flat trees. ----------------------------
        var parent = [Int](0..<vertexCount)
        var rank = [UInt8](repeating: 0, count: vertexCount)

        // Iterative find with full path compression (avoids deep recursion on
        // long chains and avoids per-call closure overhead on large meshes).
        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            // Compress: point every node on the path straight at the root.
            var node = x
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra == rb { return }
            if rank[ra] < rank[rb] {
                parent[ra] = rb
            } else if rank[ra] > rank[rb] {
                parent[rb] = ra
            } else {
                parent[rb] = ra
                rank[ra] &+= 1
            }
        }

        // Union the 3 vertices of every (non-degenerate) triangle. Degenerate
        // triangles (a duplicate index) carry no connectivity information and are
        // dropped entirely below, so we skip them here too.
        mesh.indices.withUnsafeBufferPointer { idx in
            var t = 0
            while t < triCount {
                let base = t * 3
                let a = Int(idx[base])
                let b = Int(idx[base + 1])
                let c = Int(idx[base + 2])
                t += 1
                // Skip degenerate or out-of-range triangles defensively.
                if a == b || a == c || b == c { continue }
                if a >= vertexCount || b >= vertexCount || c >= vertexCount { continue }
                union(a, b)
                union(a, c)
            }
        }

        // --- Count triangles per component root. ----------------------------
        var triPerRoot = [Int: Int]()
        triPerRoot.reserveCapacity(triCount)
        mesh.indices.withUnsafeBufferPointer { idx in
            var t = 0
            while t < triCount {
                let base = t * 3
                let a = Int(idx[base])
                let b = Int(idx[base + 1])
                let c = Int(idx[base + 2])
                t += 1
                if a == b || a == c || b == c { continue }
                if a >= vertexCount || b >= vertexCount || c >= vertexCount { continue }
                // All three vertices share a root after unioning above.
                triPerRoot[find(a), default: 0] += 1
            }
        }

        // --- Rebuild compactly: surviving triangles + referenced vertices. --
        // remap[old] = new index in the compacted arrays, or -1 if not yet seen.
        var remap = [Int32](repeating: -1, count: vertexCount)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        indices.reserveCapacity(mesh.indices.count)

        // Normals may be absent/short in pathological input; guard the lookup.
        let haveNormals = mesh.normals.count == vertexCount

        @inline(__always)
        func mapped(_ old: Int) -> UInt32 {
            let r = remap[old]
            if r >= 0 { return UInt32(r) }
            let newIndex = positions.count
            remap[old] = Int32(newIndex)
            positions.append(mesh.positions[old])
            normals.append(haveNormals ? mesh.normals[old] : SIMD3(0, 1, 0))
            return UInt32(newIndex)
        }

        mesh.indices.withUnsafeBufferPointer { idx in
            var t = 0
            while t < triCount {
                let base = t * 3
                let a = Int(idx[base])
                let b = Int(idx[base + 1])
                let c = Int(idx[base + 2])
                t += 1
                // Drop degenerate / out-of-range triangles defensively.
                if a == b || a == c || b == c { continue }
                if a >= vertexCount || b >= vertexCount || c >= vertexCount { continue }
                // Keep only triangles in a large-enough component.
                guard (triPerRoot[find(a)] ?? 0) >= minComponentTriangles else { continue }
                // Preserve winding: emit a, b, c in their original order.
                indices.append(mapped(a))
                indices.append(mapped(b))
                indices.append(mapped(c))
            }
        }

        return ConsolidatedMesh(positions: positions, normals: normals, indices: indices)
    }

    /// Erode the ragged boundary fringe — the thin "torn paper" skirt at the edge
    /// of the scanned area that makes results look unfinished next to Polycam.
    /// Each pass drops triangles with ≥2 vertices on a boundary edge (used by a
    /// single triangle), peeling one ring of fringe.
    static func erodeBoundary(_ mesh: ConsolidatedMesh, iterations: Int) -> ConsolidatedMesh {
        guard iterations > 0 else { return mesh }
        var indices = mesh.indices

        func edgeKey(_ a: UInt32, _ b: UInt32) -> UInt64 {
            let lo = min(a, b), hi = max(a, b)
            return (UInt64(lo) << 32) | UInt64(hi)
        }

        for _ in 0..<iterations {
            var edgeUse: [UInt64: Int] = [:]
            edgeUse.reserveCapacity(indices.count)
            var t = 0
            while t + 2 < indices.count {
                let a = indices[t], b = indices[t + 1], c = indices[t + 2]
                edgeUse[edgeKey(a, b), default: 0] += 1
                edgeUse[edgeKey(b, c), default: 0] += 1
                edgeUse[edgeKey(a, c), default: 0] += 1
                t += 3
            }
            var boundary = Set<UInt32>()
            for (key, count) in edgeUse where count == 1 {
                boundary.insert(UInt32(key >> 32))
                boundary.insert(UInt32(key & 0xFFFF_FFFF))
            }
            guard !boundary.isEmpty else { break }

            var out: [UInt32] = []
            out.reserveCapacity(indices.count)
            t = 0
            while t + 2 < indices.count {
                let a = indices[t], b = indices[t + 1], c = indices[t + 2]
                let onBoundary = (boundary.contains(a) ? 1 : 0)
                    + (boundary.contains(b) ? 1 : 0)
                    + (boundary.contains(c) ? 1 : 0)
                if onBoundary < 2 {
                    out.append(a); out.append(b); out.append(c)
                }
                t += 3
            }
            indices = out
        }

        return ConsolidatedMesh(positions: mesh.positions, normals: mesh.normals, indices: indices)
    }

    /// Fill small interior holes (e.g. door glass, which returns no LiDAR depth)
    /// by triangulating their boundary loop with a centre fan. Large loops — the
    /// mesh's outer edge and big gaps — are left alone (`maxDiagonal`).
    static func fillHoles(_ mesh: ConsolidatedMesh, maxDiagonal: Float) -> ConsolidatedMesh {
        func edgeKey(_ a: UInt32, _ b: UInt32) -> UInt64 {
            let lo = min(a, b), hi = max(a, b)
            return (UInt64(lo) << 32) | UInt64(hi)
        }
        var edgeUse: [UInt64: Int] = [:]
        edgeUse.reserveCapacity(mesh.indices.count)
        var t = 0
        while t + 2 < mesh.indices.count {
            let a = mesh.indices[t], b = mesh.indices[t + 1], c = mesh.indices[t + 2]
            edgeUse[edgeKey(a, b), default: 0] += 1
            edgeUse[edgeKey(b, c), default: 0] += 1
            edgeUse[edgeKey(a, c), default: 0] += 1
            t += 3
        }
        // Boundary-edge adjacency (a clean hole = each vertex has exactly 2).
        var adj: [UInt32: [UInt32]] = [:]
        for (key, count) in edgeUse where count == 1 {
            let a = UInt32(key >> 32), b = UInt32(key & 0xFFFF_FFFF)
            adj[a, default: []].append(b)
            adj[b, default: []].append(a)
        }
        guard !adj.isEmpty else { return mesh }

        var positions = mesh.positions
        var normals = mesh.normals
        var indices = mesh.indices
        var visited = Set<UInt32>()

        for start in adj.keys {
            if visited.contains(start) { continue }
            guard adj[start]?.count == 2 else { continue }

            // Trace the loop: always step to the neighbour we didn't come from.
            var loop: [UInt32] = [start]
            visited.insert(start)
            var prev = start
            var cur = adj[start]![0]
            var ok = true
            while cur != start {
                guard !visited.contains(cur), let nbrs = adj[cur], nbrs.count == 2 else { ok = false; break }
                loop.append(cur)
                visited.insert(cur)
                let next = nbrs[0] == prev ? nbrs[1] : nbrs[0]
                prev = cur
                cur = next
                if loop.count > 4000 { ok = false; break }
            }
            guard ok, loop.count >= 3 else { continue }

            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            var centroid = SIMD3<Float>(repeating: 0)
            var normal = SIMD3<Float>(repeating: 0)
            for v in loop {
                let p = positions[Int(v)]
                lo = simd_min(lo, p); hi = simd_max(hi, p); centroid += p
                normal += normals[Int(v)]
            }
            guard simd_length(hi - lo) <= maxDiagonal else { continue }   // outer edge / big gap
            centroid /= Float(loop.count)
            normal = simd_length(normal) > 1e-5 ? simd_normalize(normal) : SIMD3(0, 1, 0)

            let ci = UInt32(positions.count)
            positions.append(centroid)
            normals.append(normal)
            for i in 0..<loop.count {
                let a = loop[i], b = loop[(i + 1) % loop.count]
                let geo = simd_cross(positions[Int(a)] - centroid, positions[Int(b)] - centroid)
                if simd_dot(geo, normal) >= 0 {
                    indices.append(ci); indices.append(a); indices.append(b)
                } else {
                    indices.append(ci); indices.append(b); indices.append(a)
                }
            }
        }
        return ConsolidatedMesh(positions: positions, normals: normals, indices: indices)
    }

    // MARK: - Flattening & denoising (Polycam-style clean surfaces)

    /// Vertex→neighbour-vertex adjacency from the triangle edges.
    static func buildAdjacency(_ indices: [UInt32], vertexCount: Int) -> [[Int]] {
        guard vertexCount > 0 else { return [] }
        var sets = [Set<Int>](repeating: [], count: vertexCount)
        var t = 0
        while t + 2 < indices.count {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2]); t += 3
            if a == b || b == c || a == c { continue }
            if a >= vertexCount || b >= vertexCount || c >= vertexCount { continue }
            sets[a].insert(b); sets[a].insert(c)
            sets[b].insert(a); sets[b].insert(c)
            sets[c].insert(a); sets[c].insert(b)
        }
        return sets.map { Array($0) }
    }

    /// Area-weighted per-vertex normals (consistent with each triangle's winding).
    static func recomputeVertexNormals(_ mesh: ConsolidatedMesh) -> ConsolidatedMesh {
        var normals = [SIMD3<Float>](repeating: .zero, count: mesh.positions.count)
        var t = 0
        while t + 2 < mesh.indices.count {
            let a = Int(mesh.indices[t]), b = Int(mesh.indices[t + 1]), c = Int(mesh.indices[t + 2]); t += 3
            let n = simd_cross(mesh.positions[b] - mesh.positions[a], mesh.positions[c] - mesh.positions[a])
            normals[a] += n; normals[b] += n; normals[c] += n
        }
        for i in 0..<normals.count {
            normals[i] = simd_length(normals[i]) > 1e-9 ? simd_normalize(normals[i]) : SIMD3(0, 1, 0)
        }
        return ConsolidatedMesh(positions: mesh.positions, normals: normals, indices: mesh.indices)
    }

    /// Clamp spike outliers: a vertex whose distance to its neighbour centroid is
    /// a large outlier (a LiDAR "stalactite") is pulled onto that centroid. A few
    /// passes remove the protruding spikes that smoothing alone leaves behind.
    static func removeSpeckle(_ mesh: ConsolidatedMesh, iterations: Int = 5, threshold: Float = 0.04) -> ConsolidatedMesh {
        let n = mesh.positions.count
        guard n > 0, iterations > 0 else { return mesh }
        let adj = buildAdjacency(mesh.indices, vertexCount: n)
        var pos = mesh.positions
        for _ in 0..<iterations {
            var out = pos
            for i in 0..<n {
                let nbrs = adj[i]; if nbrs.count < 3 { continue }
                var c = SIMD3<Float>(repeating: 0)
                for j in nbrs { c += pos[j] }
                c /= Float(nbrs.count)
                if simd_distance(pos[i], c) > threshold { out[i] = c }
            }
            pos = out
        }
        return recomputeVertexNormals(ConsolidatedMesh(positions: pos, normals: mesh.normals, indices: mesh.indices))
    }

    /// Taubin λ/μ smoothing (shrink-free). `edgeSharpness` down-weights neighbours
    /// across a sharp normal difference so furniture edges/corners are preserved
    /// while flat noise is smoothed out. `skip[i]` holds a vertex fixed — pass the
    /// snapped-wall mask so dead-flat walls are never re-wobbled.
    static func taubinSmooth(_ mesh: ConsolidatedMesh, lambda: Float = 0.5, mu: Float = -0.53,
                             iterations: Int = 3, edgeSharpness: Float = 0, skip: [Bool]? = nil) -> ConsolidatedMesh {
        let n = mesh.positions.count
        guard n > 0, iterations > 0 else { return mesh }
        let adj = buildAdjacency(mesh.indices, vertexCount: n)
        var pos = mesh.positions
        var nrm = recomputeVertexNormals(mesh).normals

        func step(_ factor: Float) {
            var out = pos
            for i in 0..<n {
                if let skip, i < skip.count, skip[i] { continue }
                let nbrs = adj[i]; if nbrs.isEmpty { continue }
                var sum = SIMD3<Float>(repeating: 0); var wsum: Float = 0
                for j in nbrs {
                    var w: Float = 1
                    if edgeSharpness > 0 { w = powf(max(0, simd_dot(nrm[i], nrm[j])), edgeSharpness) }
                    sum += pos[j] * w; wsum += w
                }
                if wsum > 1e-6 { out[i] = pos[i] + (sum / wsum - pos[i]) * factor }
            }
            pos = out
        }
        for _ in 0..<iterations {
            step(lambda)
            step(mu)
            if edgeSharpness > 0 {
                nrm = recomputeVertexNormals(ConsolidatedMesh(positions: pos, normals: nrm, indices: mesh.indices)).normals
            }
        }
        return recomputeVertexNormals(ConsolidatedMesh(positions: pos, normals: nrm, indices: mesh.indices))
    }
}
