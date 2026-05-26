// MeshCleaner — mesh boundary va sifat cleanup pipeline.
//
// 4 ta operatsiya:
//   1. Weld vertices    — anchor chegaralari pozitsiya bo'yicha birlashtiriladi
//   2. Remove slivers   — degenerat thin triangle'lar tashlanadi
//   3. Drop small comps — kichik disconnected mesh fragment'lar tashlanadi
//   4. Fill small holes — ear-clipping (fan emas) tabiiy ko'rinish saqlanadi

import Foundation
import simd

struct CleanedMesh {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)]
}

enum MeshCleaner {
    /// Weld-only decimation — katta mesh'larni xavfsiz kichraytirish uchun.
    /// Full clean() ko'p memory yeydi (edge-adjacency hash table 100k+ tri'da
    /// ~200 MB). Weld alone faqat vertex hash table ishlatadi — kichikroq.
    /// epsilon = welding radius (kattaroq → ko'proq vertex birlashadi → kichik mesh).
    static func weldOnly(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        epsilon: Float,
    ) -> CleanedMesh {
        let (v, n, t) = weldVertices(
            vertices: vertices, normals: normals, triangles: triangles, epsilon: epsilon,
        )
        NSLog("KADASTR weldOnly @\(String(format: "%.0fmm", epsilon * 1000)): \(vertices.count) → \(v.count) vert, \(triangles.count) → \(t.count) tri")
        return CleanedMesh(vertices: v, normals: n, triangles: t)
    }

    static func clean(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        weldEpsilon: Float = 0.02,
        minComponentTris: Int = 30,
        slimAspectThreshold: Float = 0.015,
        maxHoleBoundary: Int = 12,
    ) -> CleanedMesh {
        // 1. Weld
        var (v, n, t) = weldVertices(
            vertices: vertices, normals: normals, triangles: triangles, epsilon: weldEpsilon,
        )
        NSLog("KADASTR clean.weld: \(vertices.count) → \(v.count) vert, \(triangles.count) → \(t.count) tri")

        // 2. Remove slivers
        let beforeSliv = t.count
        t = removeSlivers(vertices: v, triangles: t, aspectThreshold: slimAspectThreshold)
        NSLog("KADASTR clean.sliver: \(beforeSliv) → \(t.count) tri")

        // 3. Drop small disconnected components
        let beforeFrag = t.count
        t = dropSmallComponents(vertices: v, triangles: t, minTris: minComponentTris)
        NSLog("KADASTR clean.frag: \(beforeFrag) → \(t.count) tri")

        // 4. Fill small holes (ear-clipping, not fan)
        let beforeHole = t.count
        (v, n, t) = fillSmallHoles(
            vertices: v, normals: n, triangles: t, maxEdges: maxHoleBoundary,
        )
        NSLog("KADASTR clean.holes: \(beforeHole) → \(t.count) tri (+\(t.count - beforeHole))")

        return CleanedMesh(vertices: v, normals: n, triangles: t)
    }

    // MARK: - 1. Vertex welding

    private static func weldVertices(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        epsilon: Float,
    ) -> (vertices: [SIMD3<Float>], normals: [SIMD3<Float>], triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)]) {
        let scale: Float = 1.0 / epsilon
        var weldMap: [SIMD3<Int32>: UInt32] = [:]
        weldMap.reserveCapacity(vertices.count)
        var remap = [UInt32](repeating: 0, count: vertices.count)
        var outV: [SIMD3<Float>] = []
        var nAcc: [SIMD3<Float>] = []
        var nCnt: [Int] = []
        outV.reserveCapacity(vertices.count)
        nAcc.reserveCapacity(vertices.count)
        nCnt.reserveCapacity(vertices.count)

        for (oi, v) in vertices.enumerated() {
            let key = SIMD3<Int32>(
                Int32((v.x * scale).rounded()),
                Int32((v.y * scale).rounded()),
                Int32((v.z * scale).rounded()),
            )
            if let ex = weldMap[key] {
                remap[oi] = ex
                nAcc[Int(ex)] += normals[oi]
                nCnt[Int(ex)] += 1
            } else {
                let ni = UInt32(outV.count)
                weldMap[key] = ni
                remap[oi] = ni
                outV.append(v)
                nAcc.append(normals[oi])
                nCnt.append(1)
            }
        }

        var outN = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: outV.count)
        for i in 0..<outV.count {
            let s = nAcc[i] / Float(max(nCnt[i], 1))
            let l = simd_length(s)
            outN[i] = l > 1e-6 ? s / l : SIMD3<Float>(0, 1, 0)
        }

        var outT: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        outT.reserveCapacity(triangles.count)
        for tr in triangles {
            let i0 = remap[Int(tr.v0)]
            let i1 = remap[Int(tr.v1)]
            let i2 = remap[Int(tr.v2)]
            if i0 != i1 && i1 != i2 && i0 != i2 {
                outT.append((v0: i0, v1: i1, v2: i2))
            }
        }
        return (outV, outN, outT)
    }

    // MARK: - 2. Sliver removal

    /// Triangle area / perimeter² ratio. Equilateral ≈ 0.144, sliver → 0.
    private static func removeSlivers(
        vertices: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        aspectThreshold: Float,
    ) -> [(v0: UInt32, v1: UInt32, v2: UInt32)] {
        var out: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        out.reserveCapacity(triangles.count)
        for t in triangles {
            let a = vertices[Int(t.v0)]
            let b = vertices[Int(t.v1)]
            let c = vertices[Int(t.v2)]
            let e0 = simd_distance(a, b)
            let e1 = simd_distance(b, c)
            let e2 = simd_distance(c, a)
            let p = e0 + e1 + e2
            if p < 1e-6 { continue }
            let normalVec = simd_cross(b - a, c - a)
            let area = 0.5 * simd_length(normalVec)
            let aspect = area / (p * p)
            if aspect >= aspectThreshold {
                out.append(t)
            }
        }
        return out
    }

    // MARK: - Camera coverage filter (Polycam-style focus crop)

    /// Filter input — har camera uchun pozitsiya, forward, intrinsics
    struct CoverageCamera {
        let position: SIMD3<Float>
        let forward: SIMD3<Float>         // world-space view direction (-Z column)
        let invTransform: simd_float4x4   // world → camera
        let intrinsics: simd_float3x3
        let imageW: Float
        let imageH: Float
    }

    /// Har triangle markazini har camera frustum'iga proyeksiya qiladi.
    /// Triangle camera view cone'ida + image bounds ichida → coverage++.
    /// Coverage < minCoverage → drop. Periferyada brief ko'ringan devor/pol
    /// fragmentlari avtomatik kesiladi (Polycam-style focus crop).
    static func filterByCameraCoverage(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        cameras: [CoverageCamera],
        minCoverage: Int = 3,
        coneCosine: Float = 0.5,     // ~60° half-angle cone
        maxDistance: Float = 4.0,
    ) -> CleanedMesh {
        let triCount = triangles.count
        if triCount == 0 || cameras.isEmpty {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }

        var counts = [Int](repeating: 0, count: triCount)
        // Triangle markazlarini bir marta hisoblaymiz — har camera uchun reuse
        var centers = [SIMD3<Float>]()
        centers.reserveCapacity(triCount)
        for t in triangles {
            let v0 = vertices[Int(t.v0)]
            let v1 = vertices[Int(t.v1)]
            let v2 = vertices[Int(t.v2)]
            centers.append((v0 + v1 + v2) / 3.0)
        }

        for cam in cameras {
            let camPos = cam.position
            let camFwd = cam.forward
            let invT = cam.invTransform
            let K = cam.intrinsics
            let imgW = cam.imageW
            let imgH = cam.imageH
            for ti in 0..<triCount {
                let center = centers[ti]
                let toV = center - camPos
                let dist = simd_length(toV)
                if dist < 0.05 || dist > maxDistance { continue }
                let toVn = toV / dist
                if simd_dot(camFwd, toVn) < coneCosine { continue }

                let camSpace = invT * SIMD4<Float>(center, 1.0)
                let z = -camSpace.z
                if z < 0.05 { continue }
                let proj = K * SIMD3<Float>(camSpace.x, -camSpace.y, z)
                let pu = proj.x / proj.z
                let pv = proj.y / proj.z
                if pu < 0 || pu >= imgW || pv < 0 || pv >= imgH { continue }
                counts[ti] += 1
            }
        }

        var keptTris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        keptTris.reserveCapacity(triCount)
        for ti in 0..<triCount where counts[ti] >= minCoverage {
            keptTris.append(triangles[ti])
        }

        // Remap vertices — ishlatilgan vertex'lar
        var used = [Bool](repeating: false, count: vertices.count)
        for t in keptTris {
            used[Int(t.v0)] = true
            used[Int(t.v1)] = true
            used[Int(t.v2)] = true
        }
        var remap = [UInt32](repeating: 0, count: vertices.count)
        var outV: [SIMD3<Float>] = []
        var outN: [SIMD3<Float>] = []
        outV.reserveCapacity(vertices.count)
        outN.reserveCapacity(vertices.count)
        for vi in 0..<vertices.count where used[vi] {
            remap[vi] = UInt32(outV.count)
            outV.append(vertices[vi])
            outN.append(normals[vi])
        }
        let outT = keptTris.map { (
            v0: remap[Int($0.v0)],
            v1: remap[Int($0.v1)],
            v2: remap[Int($0.v2)],
        ) }
        NSLog("KADASTR coverage filter: kept \(outT.count) / \(triCount) tri (≥\(minCoverage) cams in cone)")
        return CleanedMesh(vertices: outV, normals: outN, triangles: outT)
    }

    // MARK: - Largest connected component filter (Polycam-style)

    /// Mesh'dan eng katta connected component'ni qoldiradi. Floating fragmentlar
    /// (LiDAR shovqin, yaltiroq sirt, uzoq joylar) tashlanadi.
    /// `minSizeRatio` — eng katta'ning shu nisbatidan kichik component'lar tashlanadi.
    /// Default 0.20 → 20%'dan kichik component'lar drop.
    static func keepLargestComponent(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        minSizeRatio: Double = 0.20,
    ) -> CleanedMesh {
        let triCount = triangles.count
        if triCount == 0 {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }

        // Edge → triangle adjacency
        struct EdgeKey: Hashable { let a: UInt32; let b: UInt32 }
        @inline(__always) func key(_ x: UInt32, _ y: UInt32) -> EdgeKey {
            return x < y ? EdgeKey(a: x, b: y) : EdgeKey(a: y, b: x)
        }
        var edgeToTris: [EdgeKey: [Int]] = [:]
        edgeToTris.reserveCapacity(triCount * 3)
        for (ti, t) in triangles.enumerated() {
            edgeToTris[key(t.v0, t.v1), default: []].append(ti)
            edgeToTris[key(t.v1, t.v2), default: []].append(ti)
            edgeToTris[key(t.v2, t.v0), default: []].append(ti)
        }

        // Triangle neighbors
        var neighbors: [[Int]] = Array(repeating: [], count: triCount)
        for tris in edgeToTris.values where tris.count >= 2 {
            for i in 0..<tris.count {
                for j in (i + 1)..<tris.count {
                    neighbors[tris[i]].append(tris[j])
                    neighbors[tris[j]].append(tris[i])
                }
            }
        }

        // BFS components
        var compId = [Int](repeating: -1, count: triCount)
        var compSize: [Int] = []
        for start in 0..<triCount where compId[start] == -1 {
            let id = compSize.count
            var size = 0
            var stack = [start]
            compId[start] = id
            while let cur = stack.popLast() {
                size += 1
                for nb in neighbors[cur] where compId[nb] == -1 {
                    compId[nb] = id
                    stack.append(nb)
                }
            }
            compSize.append(size)
        }

        guard let maxSize = compSize.max(), maxSize > 0 else {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }
        let threshold = Int(Double(maxSize) * minSizeRatio)
        NSLog("KADASTR LCC: \(compSize.count) component, max=\(maxSize), threshold=\(threshold)")

        // Keep triangles in components ≥ threshold (largest + close-to-largest)
        var keptTris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        keptTris.reserveCapacity(triCount)
        for (ti, t) in triangles.enumerated() {
            if compSize[compId[ti]] >= threshold {
                keptTris.append(t)
            }
        }

        // Remap vertices — faqat ishlatilgan vertex'larni saqlash
        var used = [Bool](repeating: false, count: vertices.count)
        for t in keptTris {
            used[Int(t.v0)] = true
            used[Int(t.v1)] = true
            used[Int(t.v2)] = true
        }
        var remap = [UInt32](repeating: 0, count: vertices.count)
        var outV: [SIMD3<Float>] = []
        var outN: [SIMD3<Float>] = []
        outV.reserveCapacity(vertices.count)
        outN.reserveCapacity(vertices.count)
        for vi in 0..<vertices.count where used[vi] {
            remap[vi] = UInt32(outV.count)
            outV.append(vertices[vi])
            outN.append(normals[vi])
        }
        let outT = keptTris.map { (
            v0: remap[Int($0.v0)],
            v1: remap[Int($0.v1)],
            v2: remap[Int($0.v2)],
        ) }
        NSLog("KADASTR LCC kept: \(outV.count) vert, \(outT.count) tri (was \(vertices.count)/\(triCount))")
        return CleanedMesh(vertices: outV, normals: outN, triangles: outT)
    }

    // MARK: - 3. Drop small connected components

    private static func dropSmallComponents(
        vertices: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        minTris: Int,
    ) -> [(v0: UInt32, v1: UInt32, v2: UInt32)] {
        let triCount = triangles.count
        if triCount == 0 { return [] }

        // Build edge → triangle adjacency
        struct EdgeKey: Hashable { let a: UInt32; let b: UInt32 }
        @inline(__always) func key(_ x: UInt32, _ y: UInt32) -> EdgeKey {
            return x < y ? EdgeKey(a: x, b: y) : EdgeKey(a: y, b: x)
        }
        var edgeToTris: [EdgeKey: [Int]] = [:]
        edgeToTris.reserveCapacity(triCount * 3)
        for (ti, t) in triangles.enumerated() {
            edgeToTris[key(t.v0, t.v1), default: []].append(ti)
            edgeToTris[key(t.v1, t.v2), default: []].append(ti)
            edgeToTris[key(t.v2, t.v0), default: []].append(ti)
        }

        // Build triangle adjacency (which triangles share an edge with each one)
        var neighbors: [[Int]] = Array(repeating: [], count: triCount)
        for tris in edgeToTris.values where tris.count >= 2 {
            for i in 0..<tris.count {
                for j in (i + 1)..<tris.count {
                    neighbors[tris[i]].append(tris[j])
                    neighbors[tris[j]].append(tris[i])
                }
            }
        }

        // BFS to find connected components
        var compId = [Int](repeating: -1, count: triCount)
        var compSize: [Int] = []
        for start in 0..<triCount where compId[start] == -1 {
            let id = compSize.count
            var size = 0
            var stack = [start]
            compId[start] = id
            while let cur = stack.popLast() {
                size += 1
                for nb in neighbors[cur] where compId[nb] == -1 {
                    compId[nb] = id
                    stack.append(nb)
                }
            }
            compSize.append(size)
        }

        // Keep only triangles in components ≥ minTris
        var out: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        out.reserveCapacity(triCount)
        for (ti, t) in triangles.enumerated() {
            if compSize[compId[ti]] >= minTris {
                out.append(t)
            }
        }
        return out
    }

    // MARK: - 4. Fill small holes (ear-clipping)

    private static func fillSmallHoles(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        maxEdges: Int,
    ) -> (vertices: [SIMD3<Float>], normals: [SIMD3<Float>], triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)]) {
        struct EdgeKey: Hashable { let a: UInt32; let b: UInt32 }
        @inline(__always) func key(_ x: UInt32, _ y: UInt32) -> EdgeKey {
            return x < y ? EdgeKey(a: x, b: y) : EdgeKey(a: y, b: x)
        }
        var edgeCnt: [EdgeKey: Int] = [:]
        edgeCnt.reserveCapacity(triangles.count * 3)
        for t in triangles {
            edgeCnt[key(t.v0, t.v1), default: 0] += 1
            edgeCnt[key(t.v1, t.v2), default: 0] += 1
            edgeCnt[key(t.v2, t.v0), default: 0] += 1
        }

        // Directed boundary edges (only edges with count == 1)
        var directed: [UInt32: UInt32] = [:]
        for t in triangles {
            let pairs: [(UInt32, UInt32)] = [(t.v0, t.v1), (t.v1, t.v2), (t.v2, t.v0)]
            for (a, b) in pairs where edgeCnt[key(a, b)] == 1 {
                directed[a] = b
            }
        }

        // Trace loops
        var visited = Set<UInt32>()
        var loops: [[UInt32]] = []
        for start in directed.keys where !visited.contains(start) {
            var loop: [UInt32] = []
            var cur = start
            var step = 0
            while !visited.contains(cur) && step <= maxEdges + 1 {
                visited.insert(cur)
                loop.append(cur)
                guard let nx = directed[cur] else { break }
                cur = nx
                step += 1
            }
            if loop.count >= 3 && loop.count <= maxEdges && cur == start {
                loops.append(loop)
            }
        }

        if loops.isEmpty {
            return (vertices, normals, triangles)
        }

        var outTris = triangles
        for loop in loops {
            let tris = earClipLoop3D(loop: loop, vertices: vertices, normals: normals)
            outTris.append(contentsOf: tris)
        }
        return (vertices, normals, outTris)
    }

    /// Project 3D loop to 2D plane (PCA), ear-clip, return triangles in original
    /// vertex indices. Fan triangulation o'rniga proper ear-clipping — uzun
    /// spike yo'q, kichik tabiiy triangle'lar.
    private static func earClipLoop3D(
        loop: [UInt32], vertices: [SIMD3<Float>], normals: [SIMD3<Float>],
    ) -> [(v0: UInt32, v1: UInt32, v2: UInt32)] {
        let n = loop.count
        if n < 3 { return [] }
        if n == 3 {
            return [(v0: loop[0], v1: loop[1], v2: loop[2])]
        }

        // Compute plane normal (average of loop vertex normals)
        var avgN = SIMD3<Float>(0, 0, 0)
        for vi in loop { avgN += normals[Int(vi)] }
        let nLen = simd_length(avgN)
        let planeN = nLen > 1e-6 ? avgN / nLen : SIMD3<Float>(0, 1, 0)

        // Compute centroid
        var centroid = SIMD3<Float>(0, 0, 0)
        for vi in loop { centroid += vertices[Int(vi)] }
        centroid /= Float(n)

        // Build 2D basis on the plane (any 2 perpendicular vectors)
        let helper: SIMD3<Float> = abs(planeN.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let u = simd_normalize(simd_cross(planeN, helper))
        let v = simd_normalize(simd_cross(planeN, u))

        // Project loop to 2D
        var pts2D: [SIMD2<Float>] = []
        for vi in loop {
            let p = vertices[Int(vi)] - centroid
            pts2D.append(SIMD2<Float>(simd_dot(p, u), simd_dot(p, v)))
        }

        // Ear-clipping in 2D
        var indices = Array(0..<n)
        var output: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        var safety = n * n  // bound iterations
        while indices.count > 3 && safety > 0 {
            safety -= 1
            var clipped = false
            let m = indices.count
            for i in 0..<m {
                let prev = indices[(i + m - 1) % m]
                let cur = indices[i]
                let next = indices[(i + 1) % m]
                if isEar(prev: prev, cur: cur, next: next, indices: indices, pts: pts2D) {
                    output.append((v0: loop[prev], v1: loop[cur], v2: loop[next]))
                    indices.remove(at: i)
                    clipped = true
                    break
                }
            }
            if !clipped { break }  // no ear found — bail
        }
        if indices.count == 3 {
            output.append((v0: loop[indices[0]], v1: loop[indices[1]], v2: loop[indices[2]]))
        }
        return output
    }

    private static func isEar(
        prev: Int, cur: Int, next: Int, indices: [Int], pts: [SIMD2<Float>],
    ) -> Bool {
        let a = pts[prev]
        let b = pts[cur]
        let c = pts[next]
        // Convex check (CCW)
        let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        if cross <= 0 { return false }
        // No other vertex inside the triangle (abc)
        for idx in indices where idx != prev && idx != cur && idx != next {
            if pointInTriangle(p: pts[idx], a: a, b: b, c: c) { return false }
        }
        return true
    }

    private static func pointInTriangle(
        p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>, c: SIMD2<Float>,
    ) -> Bool {
        let d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
        let d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
        let d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }
}
