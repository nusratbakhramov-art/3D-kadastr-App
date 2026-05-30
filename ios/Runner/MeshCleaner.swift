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

    // MARK: - Laplacian smoothing (Phase 4.2)

    /// Taubin λ/μ smoothing — Laplacian o'rniga, mesh hajmi va detail
    /// saqlanadi (oddiy Laplacian uzoq iter'larda mesh'ni "shrink" qiladi).
    ///
    /// Iter har bosqichida ikki pass:
    ///   1. Positive λ (smoothing): v ← v + λ(L(v))
    ///   2. Negative μ (anti-shrink): v ← v + μ(L(v))   (μ < -λ)
    ///
    /// Standart qiymatlar: λ=0.5, μ=-0.53, iter=3 → silliq surface,
    /// detail (sofa edges, table legs) saqlanadi. 5cm voxel stair-step'i
    /// va ARKit anchor seam'lari deyarli yo'qoladi.
    static func taubinSmooth(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        lambda: Float = 0.5,
        mu: Float = -0.53,
        iterations: Int = 3,
        edgeSharpness: Float = 0,   // 0 = oddiy Taubin; >0 = edge-aware (qirra saqlash)
        normalPresmoothIterations: Int = 0,   // >0: edge-normalni qotirishdan oldin tekislash
    ) -> CleanedMesh {
        if vertices.count < 4 || triangles.isEmpty {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }

        // Build vertex adjacency (set of neighbors via shared edges)
        var adjacency: [Set<UInt32>] = Array(repeating: Set<UInt32>(), count: vertices.count)
        for t in triangles {
            adjacency[Int(t.v0)].insert(t.v1); adjacency[Int(t.v0)].insert(t.v2)
            adjacency[Int(t.v1)].insert(t.v0); adjacency[Int(t.v1)].insert(t.v2)
            adjacency[Int(t.v2)].insert(t.v0); adjacency[Int(t.v2)].insert(t.v1)
        }

        // Edge-detection normallari. KALIT: xom LiDAR normal 5cm-voxel STAIR-STEP'li
        // (qo'shni yuza ko'pincha 90° farq) — to'g'ridan edge-aware'ga berilsa har
        // stair "qirra" deb belgilanib silliqlash bloklanadi (HAQIQIY pipeline'da
        // edgeSharpness=2 → 3%, presmooth+es12 → faqat 20%). Yechim: pozitsiyani
        // VAQTINCHA silliqlab (temp mesh, asl verts O'ZGARMAYDI) normalni qayta
        // hisoblaймиз — voxel-stair yo'qoladi, aniq normal qoladi. Keyin presmooth
        // bump-shovqinни o'chiradi, strukturaviy qirra (quti/divan/eshik) signalini
        // saqlaydi. Qotirilгани (iter'da yangilanmas) uchun qirra joyi o'zgarmaydi.
        var edgeNormals = normals
        if edgeSharpness > 0 {
            var tempVerts = vertices
            let preIters = max(3, normalPresmoothIterations / 3)
            for _ in 0..<preIters {
                tempVerts = laplacianPass(verts: tempVerts, normals: normals, adjacency: adjacency, weight: lambda, edgeSharpness: 0)
                tempVerts = laplacianPass(verts: tempVerts, normals: normals, adjacency: adjacency, weight: mu, edgeSharpness: 0)
            }
            let cleanNormals = recomputeVertexNormals(verts: tempVerts, triangles: triangles, fallback: normals)
            edgeNormals = normalPresmoothIterations > 0
                ? presmoothNormalField(cleanNormals, adjacency: adjacency, iterations: normalPresmoothIterations)
                : cleanNormals
        }

        var verts = vertices
        for _ in 0..<iterations {
            // Pass 1: λ smoothing
            verts = laplacianPass(verts: verts, normals: edgeNormals, adjacency: adjacency, weight: lambda, edgeSharpness: edgeSharpness)
            // Pass 2: μ anti-shrink
            verts = laplacianPass(verts: verts, normals: edgeNormals, adjacency: adjacency, weight: mu, edgeSharpness: edgeSharpness)
        }

        // Recompute vertex normals from final positions (smoothed mesh →
        // need re-normalized normals for atlas baker face-dot rejection).
        let newNormals = recomputeVertexNormals(verts: verts, triangles: triangles, fallback: normals)
        NSLog("KADASTR taubinSmooth: \(iterations) iter (preIters \(max(3, normalPresmoothIterations/3))), \(vertices.count) vert")
        return CleanedMesh(vertices: verts, normals: newNormals, triangles: triangles)
    }

    private static func laplacianPass(
        verts: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        adjacency: [Set<UInt32>],
        weight: Float,
        edgeSharpness: Float,
    ) -> [SIMD3<Float>] {
        var out = verts
        let edgeAware = edgeSharpness > 0
        for i in 0..<verts.count {
            let neighbors = adjacency[i]
            if neighbors.isEmpty { continue }
            let ni = normals[i]
            var sum = SIMD3<Float>(0, 0, 0)
            var wsum: Float = 0
            for n in neighbors {
                // Edge-aware vazn: qo'shni vertex normal o'xshashligi (dot). Tekis
                // yuza (o'xshash normal → vazn≈1) kuchli silliqlanadi; qirra (farqli
                // normal → vazn≈0) saqlanadi. edgeSharpness pog'onasi qirrani keskin
                // ajratadi (6 → 30° farq vaznni ~0.3 ga, 60° ni ~0.01 ga tushiradi).
                let w: Float
                if edgeAware {
                    let nd = max(0, simd_dot(ni, normals[Int(n)]))
                    w = pow(nd, edgeSharpness)
                } else {
                    w = 1
                }
                sum += verts[Int(n)] * w
                wsum += w
            }
            if wsum < 1e-6 { continue }
            let centroid = sum / wsum
            let delta = centroid - verts[i]
            out[i] = verts[i] + delta * weight
        }
        return out
    }

    /// Vertex normallarini uchburchak yuz-normallari yig'indisidan qayta hisoblaydi
    /// (area-weighted). counts==0 vertex'lar uchun fallback.
    private static func recomputeVertexNormals(
        verts: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        fallback: [SIMD3<Float>],
    ) -> [SIMD3<Float>] {
        var newNormals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: verts.count)
        var counts = [Int](repeating: 0, count: verts.count)
        for t in triangles {
            let n = simd_cross(verts[Int(t.v1)] - verts[Int(t.v0)], verts[Int(t.v2)] - verts[Int(t.v0)])
            let len = simd_length(n)
            if len < 1e-9 { continue }
            let nn = n / len
            newNormals[Int(t.v0)] += nn; counts[Int(t.v0)] += 1
            newNormals[Int(t.v1)] += nn; counts[Int(t.v1)] += 1
            newNormals[Int(t.v2)] += nn; counts[Int(t.v2)] += 1
        }
        for i in 0..<newNormals.count {
            if counts[i] > 0 {
                let avg = newNormals[i] / Float(counts[i])
                let len = simd_length(avg)
                newNormals[i] = len > 1e-9 ? avg / len : fallback[i]
            } else {
                newNormals[i] = fallback[i]
            }
        }
        return newNormals
    }

    /// Phase 14: RANSAC plane-snap — devor/pol/shiftni TEKIS qiladi. Katta planar
    /// yuzalarni RANSAC bilan topib (vertex+normal candidate), ±band ichidagi VA
    /// normali mos vertexlarni planega proyeksiya qiladi. normal-gate mebel/qirra/
    /// puf'ni saqlaydi (snap qilmaydi). Ref[18] agent tavsiyasi (DL primitive emas —
    /// oddiy RANSAC, on-device bir necha soniya). Mac prototip (scan_009): 7 plane,
    /// 69% snap, avg 7.8mm, pol/devor tekis, mebel saqlangan.
    static func snapToPlanes(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        band: Float = 0.05,       // 5cm: bumpy devorни (depth noise amplitudasi) to'liq ushlash
        normalDot: Float = 0.6,   // looser: bumpy devor normali og'ishgan — 0.9 gate ularni rad etardi (tekislamasdi). 0.6 ushlaydi, mebel (qarama-qarshi normal) rad etiladi
        minInliers: Int = 1200,   // bake mesh decimated (tekis devor=kam vertex) → past chegara
        maxPlanes: Int = 18,
        candidates: Int = 220,
    ) -> CleanedMesh {
        let nv = vertices.count
        if nv < minInliers || triangles.isEmpty {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }
        let vn = normals
        var assigned = [Int](repeating: -1, count: nv)
        var avail = [Bool](repeating: true, count: nv)
        var planes: [(c: SIMD3<Float>, n: SIMD3<Float>)] = []

        var rng: UInt64 = 0x9E3779B97F4A7C15
        @inline(__always) func rand(_ bound: Int) -> Int {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Int((rng >> 33) % UInt64(max(bound, 1)))
        }

        for _ in 0..<maxPlanes {
            var pool: [Int] = []
            pool.reserveCapacity(nv)
            for i in 0..<nv where avail[i] { pool.append(i) }
            if pool.count < minInliers { break }

            var bestCnt = 0
            var bestC = SIMD3<Float>(0, 0, 0)
            var bestN = SIMD3<Float>(0, 1, 0)
            // candidate counting subsample (stride 2) — tezlik uchun
            for _ in 0..<candidates {
                let ci = pool[rand(pool.count)]
                let pp = vertices[ci]; let pn = vn[ci]
                var cnt = 0
                var j = 0
                while j < pool.count {
                    let i = pool[j]
                    if abs(simd_dot(vertices[i] - pp, pn)) < band && simd_dot(vn[i], pn) > normalDot { cnt += 1 }
                    j += 2
                }
                if cnt > bestCnt { bestCnt = cnt; bestC = pp; bestN = pn }
            }
            if bestCnt * 2 < minInliers { break }   // *2: subsample kompensatsiyasi

            // refit: inlier markazi + o'rtacha normal (eigen kerak emas — gate normal mos)
            var sumP = SIMD3<Float>(0, 0, 0); var sumN = SIMD3<Float>(0, 0, 0); var k = 0
            for i in pool where abs(simd_dot(vertices[i] - bestC, bestN)) < band && simd_dot(vn[i], bestN) > normalDot {
                sumP += vertices[i]; sumN += vn[i]; k += 1
            }
            if k < minInliers {
                for i in pool where abs(simd_dot(vertices[i] - bestC, bestN)) < band && simd_dot(vn[i], bestN) > normalDot { avail[i] = false }
                continue
            }
            let c = sumP / Float(k)
            let n = simd_normalize(sumN)
            let pidx = planes.count
            for i in pool where abs(simd_dot(vertices[i] - c, n)) < band && simd_dot(vn[i], n) > normalDot {
                assigned[i] = pidx; avail[i] = false
            }
            planes.append((c, n))
        }

        if planes.isEmpty {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }

        var out = vertices
        for i in 0..<nv where assigned[i] >= 0 {
            let (c, n) = planes[assigned[i]]
            out[i] = vertices[i] - simd_dot(vertices[i] - c, n) * n
        }
        // FLIP-PREVENTION: snap ba'zi triangle'ni ag'daradi (single-sided material → qora
        // teshik). Ag'darilgan triangle vertexlarini originalga qaytaramiz (teshik yo'q,
        // o'sha joyda kichik bump qoladi). 3 iter (revert qo'shni triangle'ni re-flip qilishi mumkin).
        @inline(__always) func flipDot(_ t: (v0: UInt32, v1: UInt32, v2: UInt32)) -> Float {
            let o = simd_cross(vertices[Int(t.v1)] - vertices[Int(t.v0)], vertices[Int(t.v2)] - vertices[Int(t.v0)])
            let m = simd_cross(out[Int(t.v1)] - out[Int(t.v0)], out[Int(t.v2)] - out[Int(t.v0)])
            return simd_dot(o, m)
        }
        for _ in 0..<3 {
            var reverted = 0
            for t in triangles where flipDot(t) < 0 {
                out[Int(t.v0)] = vertices[Int(t.v0)]
                out[Int(t.v1)] = vertices[Int(t.v1)]
                out[Int(t.v2)] = vertices[Int(t.v2)]
                reverted += 1
            }
            if reverted == 0 { break }
        }
        var moved = 0
        for i in 0..<nv where simd_length(out[i] - vertices[i]) > 1e-6 { moved += 1 }
        let newNormals = recomputeVertexNormals(verts: out, triangles: triangles, fallback: normals)
        NSLog("KADASTR planeSnap: \(planes.count) plane, snapped \(moved)/\(nv) vert (\(nv > 0 ? moved * 100 / nv : 0)%)")
        return CleanedMesh(vertices: out, normals: newNormals, triangles: triangles)
    }

    /// Phase 14: plane-constrained Laplacian — devor/pol/shiftni TEKIS + SILLIQ qiladi.
    /// RANSAC plane-vertexlariga: umbrella Laplacian (silliq) + planega ASTA tortish
    /// (flatten). QATTIQ snap EMAS → smoothing patchwork/faceting'ni oldini oladi
    /// (snapToPlanes faceting yaratardi; bu yo'q). Faqat plane-vert ko'chadi (mebel/quti
    /// sharp edge SAQLANADI). Mac (scan_009): devor RMS 14.3mm → 2.1mm, faceting yo'q.
    static func flattenWallsLaplacian(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        iterations: Int = 15,
        lambda: Float = 0.5,
        pull: Float = 0.5,        // kuchliroq: LiDAR horizontal banding'ni to'liq tekislash (Mac: RMS 17.6→1.7mm)
        band: Float = 0.08,       // 8cm: katta amplitudali bandni ham ushlash
        normalDot: Float = 0.4,   // looser: band ridge normallari og'ishgan, 0.55 ularni rad etardi
        minInliers: Int = 2500,
        maxPlanes: Int = 18,
        candidates: Int = 200,
    ) -> CleanedMesh {
        let nv = vertices.count
        if nv < minInliers || triangles.isEmpty {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }
        let vn = normals
        var assigned = [Int](repeating: -1, count: nv)
        var avail = [Bool](repeating: true, count: nv)
        var planes: [(c: SIMD3<Float>, n: SIMD3<Float>)] = []
        var rng: UInt64 = 0x9E3779B97F4A7C15
        @inline(__always) func rand(_ b: Int) -> Int {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Int((rng >> 33) % UInt64(max(b, 1)))
        }
        for _ in 0..<maxPlanes {
            var pool: [Int] = []; pool.reserveCapacity(nv)
            for i in 0..<nv where avail[i] { pool.append(i) }
            if pool.count < minInliers { break }
            var bestCnt = 0; var bC = SIMD3<Float>(0, 0, 0); var bN = SIMD3<Float>(0, 1, 0)
            for _ in 0..<candidates {
                let ci = pool[rand(pool.count)]; let pp = vertices[ci]; let pn = vn[ci]
                var cnt = 0; var j = 0
                while j < pool.count {
                    let i = pool[j]
                    if abs(simd_dot(vertices[i] - pp, pn)) < band && simd_dot(vn[i], pn) > normalDot { cnt += 1 }
                    j += 2
                }
                if cnt > bestCnt { bestCnt = cnt; bC = pp; bN = pn }
            }
            if bestCnt * 2 < minInliers { break }
            var sumP = SIMD3<Float>(0, 0, 0); var sumN = SIMD3<Float>(0, 0, 0); var k = 0
            for i in pool where abs(simd_dot(vertices[i] - bC, bN)) < band && simd_dot(vn[i], bN) > normalDot {
                sumP += vertices[i]; sumN += vn[i]; k += 1
            }
            if k < minInliers {
                for i in pool where abs(simd_dot(vertices[i] - bC, bN)) < band && simd_dot(vn[i], bN) > normalDot { avail[i] = false }
                continue
            }
            let c = sumP / Float(k); let n = simd_normalize(sumN); let pidx = planes.count
            for i in pool where abs(simd_dot(vertices[i] - c, n)) < band && simd_dot(vn[i], n) > normalDot {
                assigned[i] = pidx; avail[i] = false
            }
            planes.append((c, n))
        }
        if planes.isEmpty {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }
        // adjacency (precompute neighbor arrays)
        var adj = [Set<UInt32>](repeating: [], count: nv)
        for t in triangles {
            adj[Int(t.v0)].insert(t.v1); adj[Int(t.v0)].insert(t.v2)
            adj[Int(t.v1)].insert(t.v0); adj[Int(t.v1)].insert(t.v2)
            adj[Int(t.v2)].insert(t.v0); adj[Int(t.v2)].insert(t.v1)
        }
        var nbr = [[Int]](repeating: [], count: nv)
        for i in 0..<nv { nbr[i] = adj[i].map { Int($0) } }
        let plv = (0..<nv).filter { assigned[$0] >= 0 }
        var P = vertices
        for _ in 0..<iterations {
            var newP = P
            for i in plv {
                let ns = nbr[i]
                if ns.isEmpty { continue }
                var avg = SIMD3<Float>(0, 0, 0)
                for j in ns { avg += P[j] }
                avg /= Float(ns.count)
                var p = P[i] + lambda * (avg - P[i])
                let (c, n) = planes[assigned[i]]
                p = p - pull * simd_dot(p - c, n) * n
                newP[i] = p
            }
            P = newP
        }
        let newNormals = recomputeVertexNormals(verts: P, triangles: triangles, fallback: normals)
        NSLog("KADASTR flattenLaplacian: \(planes.count) plane, \(plv.count)/\(nv) plane-vert flattened")
        return CleanedMesh(vertices: P, normals: newNormals, triangles: triangles)
    }

    // MARK: - Concave footprint helpers (Phase 15b)
    // Occupancy-based footprint → har shaklni ushlaydi (L-room, alkov, concave notch).
    // Mac (wall_complete v1-v5, kadastr_raw.obj L-room) isbotlandi: 6-burchak concave,
    // watertight ✓, 22.8 m². RANSAC convex (4 burchak quti) o'rniga.

    /// Barcha vertexni XZ ga proyeksiya → occupancy grid (true=band egallangan).
    private static func occupancyMask(_ V: [SIMD3<Float>], res: Float)
        -> (mask: [Bool], w: Int, h: Int, minX: Float, minZ: Float) {
        var minX = Float.greatestFiniteMagnitude, minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
        for v in V { minX = min(minX, v.x); maxX = max(maxX, v.x); minZ = min(minZ, v.z); maxZ = max(maxZ, v.z) }
        minX -= 0.3; minZ -= 0.3; maxX += 0.3; maxZ += 0.3
        let w = max(1, Int(((maxX - minX) / res).rounded(.up)))
        let h = max(1, Int(((maxZ - minZ) / res).rounded(.up)))
        var mask = [Bool](repeating: false, count: w * h)
        for v in V {
            let gx = min(w - 1, max(0, Int((v.x - minX) / res)))
            let gz = min(h - 1, max(0, Int((v.z - minZ) / res)))
            mask[gz * w + gx] = true
        }
        return (mask, w, h, minX, minZ)
    }

    private static func dilateMask(_ m: [Bool], _ w: Int, _ h: Int, _ k: Int) -> [Bool] {
        var cur = m
        for _ in 0..<k {
            var o = cur
            for y in 0..<h { for x in 0..<w where cur[y * w + x] {
                for dy in -1...1 { for dx in -1...1 {
                    let ny = y + dy, nx = x + dx
                    if ny >= 0 && ny < h && nx >= 0 && nx < w { o[ny * w + nx] = true }
                } }
            } }
            cur = o
        }
        return cur
    }

    private static func erodeMask(_ m: [Bool], _ w: Int, _ h: Int, _ k: Int) -> [Bool] {
        dilateMask(m.map { !$0 }, w, h, k).map { !$0 }
    }

    /// Border'dan bo'sh kataklar = tashqari (flood). inside = ~tashqari (occ + ichki teshik).
    private static func fillInside(_ occ: [Bool], _ w: Int, _ h: Int) -> [Bool] {
        var outside = [Bool](repeating: false, count: w * h)
        var stack = [Int]()
        @inline(__always) func push(_ i: Int) { if !occ[i] && !outside[i] { outside[i] = true; stack.append(i) } }
        for x in 0..<w { push(x); push((h - 1) * w + x) }
        for y in 0..<h { push(y * w); push(y * w + w - 1) }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            if x > 0 { push(i - 1) }; if x < w - 1 { push(i + 1) }
            if y > 0 { push(i - w) }; if y < h - 1 { push(i + w) }
        }
        return (0..<w * h).map { !outside[$0] }
    }

    private static func largestComponent(_ m: [Bool], _ w: Int, _ h: Int) -> [Bool] {
        var label = [Int](repeating: 0, count: w * h)
        var cur = 0, best = 0, bestLabel = 0
        var stack = [Int]()
        for s in 0..<w * h where m[s] && label[s] == 0 {
            cur += 1; var cnt = 0; label[s] = cur; stack.append(s)
            while let i = stack.popLast() {
                cnt += 1
                let x = i % w, y = i / w
                for dy in -1...1 { for dx in -1...1 {
                    let ny = y + dy, nx = x + dx
                    if ny >= 0 && ny < h && nx >= 0 && nx < w {
                        let j = ny * w + nx
                        if m[j] && label[j] == 0 { label[j] = cur; stack.append(j) }
                    }
                } }
            }
            if cnt > best { best = cnt; bestLabel = cur }
        }
        return (0..<w * h).map { label[$0] == bestLabel }
    }

    /// Moore-neighbor boundary trace (8-connectivity). Grid (y,x) ketma-ketligi.
    private static func mooreTrace(_ m: [Bool], _ w: Int, _ h: Int) -> [(Int, Int)] {
        var sy = -1, sx = -1
        outer: for y in 0..<h { for x in 0..<w where m[y * w + x] { sy = y; sx = x; break outer } }
        if sy < 0 { return [] }
        let nbr = [(0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1)]
        var cont: [(Int, Int)] = [(sy, sx)]
        var cy = sy, cx = sx, bd = 0
        var guardN = 0
        while guardN < 10 * w * h {
            guardN += 1
            var found = false
            for k in 0..<8 {
                let di = (bd + k) % 8
                let (dy, dx) = nbr[di]
                let ny = cy + dy, nx = cx + dx
                if ny >= 0 && ny < h && nx >= 0 && nx < w && m[ny * w + nx] {
                    cont.append((ny, nx)); bd = (di + 6) % 8; cy = ny; cx = nx; found = true; break
                }
            }
            if !found { break }
            if cy == sy && cx == sx && cont.count > 2 { break }
        }
        if cont.count > 1 { cont.removeLast() }
        return cont
    }

    private static func douglasPeucker(_ pts: [SIMD2<Float>], _ eps: Float) -> [SIMD2<Float>] {
        if pts.count < 3 { return pts }
        let a = pts.first!, b = pts.last!
        let ab = b - a; let L = simd_length(ab)
        var maxD: Float = -1; var idx = 0
        for i in 1..<pts.count - 1 {
            let p = pts[i] - a
            let d = L < 1e-9 ? simd_length(pts[i] - a) : abs(p.x * ab.y - p.y * ab.x) / L
            if d > maxD { maxD = d; idx = i }
        }
        if maxD > eps {
            let left = douglasPeucker(Array(pts[0...idx]), eps)
            let right = douglasPeucker(Array(pts[idx..<pts.count]), eps)
            return Array(left.dropLast()) + right
        }
        return [a, b]
    }

    /// Ketma-ket bir xil yo'nalishli (H=0:v const / V=1:u const) edge'larni run'ga
    /// birlashtir. const = edge-uzunlik og'irlikli o'rtacha.
    private static func edgeRuns(_ P: [SIMD2<Float>]) -> [(cls: Int, k: Float)]? {
        let n = P.count
        if n < 4 { return nil }
        var ec = [Int](repeating: 0, count: n)
        var el = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let e = P[(i + 1) % n] - P[i]
            el[i] = simd_length(e)
            ec[i] = abs(e.x) >= abs(e.y) ? 0 : 1
        }
        var s = -1
        for i in 0..<n where ec[i] != ec[(i + n - 1) % n] { s = i; break }
        if s < 0 { return nil }
        var runs: [(cls: Int, num: Float, den: Float)] = []
        for k in 0..<n {
            let i = (s + k) % n
            let c = ec[i]
            let emid = (P[i] + P[(i + 1) % n]) * 0.5
            let key = c == 0 ? emid.y : emid.x
            if var last = runs.last, last.cls == c {
                last.num += key * el[i]; last.den += el[i]; runs[runs.count - 1] = last
            } else {
                runs.append((c, key * el[i], el[i]))
            }
        }
        var R = runs.map { (cls: $0.cls, k: $0.num / max($0.den, 1e-9)) }
        if R.count > 1 && R[0].cls == R[R.count - 1].cls {
            R[0].k = (R[0].k + R[R.count - 1].k) / 2; R.removeLast()
        }
        return R
    }

    private static func cornersOfRuns(_ R: [(cls: Int, k: Float)]) -> [SIMD2<Float>] {
        let m = R.count
        var C = [SIMD2<Float>]()
        for k in 0..<m {
            let a = R[k], b = R[(k + 1) % m]
            C.append(a.cls == 0 ? SIMD2<Float>(b.k, a.k) : SIMD2<Float>(a.k, b.k))
        }
        return C
    }

    /// Rektilinear regularizatsiya: run-merge + minLen'dan qisqa run'ni iterativ o'chir
    /// (qo'shni parallel ikki run birlashadi → mebel/shovqin zigzag yo'qoladi).
    private static func regularizeRect(_ P: [SIMD2<Float>], minLen: Float) -> [SIMD2<Float>] {
        guard var R = edgeRuns(P) else { return P }
        var guardN = 0
        while R.count > 4 && guardN < 200 {
            guardN += 1
            let C = cornersOfRuns(R); let m = R.count
            var minL = Float.greatestFiniteMagnitude; var ki = 0
            for k in 0..<m {
                let l = simd_length(C[k] - C[(k + m - 1) % m])
                if l < minL { minL = l; ki = k }
            }
            if minL >= minLen { break }
            let a = R[(ki + m - 1) % m], b = R[(ki + 1) % m]
            let merged = (cls: a.cls, k: (a.k + b.k) / 2)
            var newR = [(cls: Int, k: Float)]()
            for j in 0..<m {
                if j == (ki + m - 1) % m { newR.append(merged) }
                else if j == ki || j == (ki + 1) % m { continue }
                else { newR.append(R[j]) }
            }
            var out = [(cls: Int, k: Float)]()
            for r in newR {
                if let last = out.last, last.cls == r.cls { out[out.count - 1].k = (out[out.count - 1].k + r.k) / 2 }
                else { out.append(r) }
            }
            if out.count > 1 && out[0].cls == out[out.count - 1].cls {
                out[0].k = (out[0].k + out[out.count - 1].k) / 2; out.removeLast()
            }
            R = out
        }
        return cornersOfRuns(R)
    }

    /// Ear clipping (CCW polygon). Concave footprint floor/ceiling triangulatsiyasi.
    /// (Centroid-fan concave'da uchburchakni polygon tashqarisiga chiqaradi — yaramaydi.)
    private static func earClip(_ P: [SIMD2<Float>]) -> [(Int, Int, Int)] {
        let n = P.count
        if n < 3 { return [] }
        var idx = Array(0..<n)
        var tris = [(Int, Int, Int)]()
        @inline(__always) func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func inTri(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
            let d1 = cross(p, a, b), d2 = cross(p, b, c), d3 = cross(p, c, a)
            let neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0
            return !(neg && pos)
        }
        var guardN = 0
        while idx.count > 3 && guardN < 10 * n {
            guardN += 1
            var clipped = false
            for k in 0..<idx.count {
                let i0 = idx[(k + idx.count - 1) % idx.count], i1 = idx[k], i2 = idx[(k + 1) % idx.count]
                let a = P[i0], b = P[i1], c = P[i2]
                if cross(a, b, c) <= 0 { continue }  // reflex burchak → ear emas
                var ok = true
                for j in idx where j != i0 && j != i1 && j != i2 {
                    if inTri(P[j], a, b, c) { ok = false; break }
                }
                if ok { tris.append((i0, i1, i2)); idx.remove(at: k); clipped = true; break }
            }
            if !clipped { break }
        }
        if idx.count == 3 { tris.append((idx[0], idx[1], idx[2])) }
        return tris
    }

    /// Phase 15b: CONCAVE footprint clean-room. θ (vertikal vertex-normal circular mean
    /// mod 90) → occupancy mask → close → fill → largest CC → Moore kontur → room-frame
    /// → Douglas-Peucker → rektilinear regularizatsiya → world burchaklar → ear-clip
    /// floor/ceiling + wall extrude (INWARD normal). nil → caller convex fallback'ga tushadi.
    static func buildCleanRoomConcave(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
    ) -> CleanedMesh? {
        let V = vertices, N = normals, nv = V.count
        if nv < 3000 || triangles.isEmpty { return nil }
        // θ: vertikal vertex-normallar (|ny|<0.5) circular mean (mod 90 → ×4).
        var sx: Float = 0, sy: Float = 0
        for n in N where abs(n.y) < 0.5 {
            let ang = atan2(n.z, n.x) * 4
            sx += cos(ang); sy += sin(ang)
        }
        let theta = atan2(sy, sx) / 4
        let ct = cos(theta), st = sin(theta)
        @inline(__always) func toRoom(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2<Float>(ct * p.x + st * p.y, -st * p.x + ct * p.y) }
        @inline(__always) func toWorld(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2<Float>(ct * p.x - st * p.y, st * p.x + ct * p.y) }
        // Occupancy → solid footprint mask.
        let res: Float = 0.05
        let (occ0, w, h, minX, minZ) = occupancyMask(V, res: res)
        if w < 4 || h < 4 { return nil }
        let closed = erodeMask(dilateMask(occ0, w, h, 2), w, h, 2)
        var inside = fillInside(closed, w, h)
        inside = dilateMask(erodeMask(inside, w, h, 1), w, h, 1)  // open: kichik shovqin
        let cc = largestComponent(inside, w, h)
        // Moore kontur → world XZ.
        let traced = mooreTrace(cc, w, h)
        if traced.count < 8 { return nil }
        let contour = traced.map { (yx) -> SIMD2<Float> in
            SIMD2<Float>(minX + (Float(yx.1) + 0.5) * res, minZ + (Float(yx.0) + 0.5) * res)
        }
        // Room-frame → DP → regularize → world burchaklar.
        var uv = contour.map { toRoom($0) }
        uv.append(uv[0])
        var simp = douglasPeucker(uv, 0.05)
        if simp.count > 1 { simp.removeLast() }
        let regUV = regularizeRect(simp, minLen: 0.6)
        if regUV.count < 4 { return nil }
        var corners = regUV.map { toWorld($0) }
        // CCW majburla (shoelace > 0).
        func shoelace(_ P: [SIMD2<Float>]) -> Float {
            var s: Float = 0; let m = P.count
            for i in 0..<m { s += P[i].x * P[(i + 1) % m].y - P[(i + 1) % m].x * P[i].y }
            return 0.5 * s
        }
        if shoelace(corners) < 0 { corners.reverse() }
        let area = abs(shoelace(corners))
        if area < 1.0 || area > 400.0 { return nil }  // sanity: 1-400 m²
        // floor/ceil Y.
        let ys = V.map { $0.y }.sorted()
        let floorY = ys[ys.count / 100], ceilY = ys[ys.count * 99 / 100]
        if ceilY - floorY < 1.2 { return nil }
        // Mesh: shared floor/ceil verts (watertight).
        let nc = corners.count
        var outV: [SIMD3<Float>] = []
        for p in corners { outV.append(SIMD3<Float>(p.x, floorY, p.y)) }   // 0..<nc floor
        for p in corners { outV.append(SIMD3<Float>(p.x, ceilY, p.y)) }    // nc..<2nc ceil
        var outT: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        let caps = earClip(corners)
        if caps.count < nc - 2 { return nil }  // triangulatsiya muvaffaqiyatsiz
        // Floor caps: inward normal = UP (+Y).
        for (a, b, c) in caps {
            let A = outV[a], B = outV[b], C = outV[c]
            let nrm = simd_cross(B - A, C - A)
            if nrm.y > 0 { outT.append((UInt32(a), UInt32(b), UInt32(c))) }
            else { outT.append((UInt32(a), UInt32(c), UInt32(b))) }
        }
        // Ceiling caps: inward normal = DOWN (−Y).
        for (a, b, c) in caps {
            let A = outV[nc + a], B = outV[nc + b], C = outV[nc + c]
            let nrm = simd_cross(B - A, C - A)
            if nrm.y < 0 { outT.append((UInt32(nc + a), UInt32(nc + b), UInt32(nc + c))) }
            else { outT.append((UInt32(nc + a), UInt32(nc + c), UInt32(nc + b))) }
        }
        // Walls: har edge i→i+1. INWARD normal = footprint QIRRA yo'nalishidan (CCW
        // polygon, shoelace>0 → interior qirraning CHAP tomonida: XZ normal = (-dz, dx)).
        // DIQQAT: centroid EMAS — concave (L) xonada centroid ba'zi devorning NOTO'G'RI
        // tomonida bo'lib, o'sha devorni teskari (outward) qilardi (qora/ichkari-tashqari).
        for i in 0..<nc {
            let j = (i + 1) % nc
            let a2 = corners[i], b2 = corners[j]
            let inward = SIMD3<Float>(-(b2.y - a2.y), 0, b2.x - a2.x)  // CCW interior (XZ; .y=z)
            var q = [i, nc + i, nc + j, j].map { UInt32($0) }  // fl_i, ce_i, ce_j, fl_j
            let A = outV[Int(q[0])], B = outV[Int(q[1])], C = outV[Int(q[2])]
            let fn = simd_cross(B - A, C - A)
            if simd_dot(fn, inward) < 0 { q = [i, j, nc + j, nc + i].map { UInt32($0) } }
            outT.append((q[0], q[1], q[2])); outT.append((q[0], q[2], q[3]))
        }
        let outN = recomputeVertexNormals(verts: outV, triangles: outT,
                                          fallback: [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: outV.count))
        NSLog("KADASTR buildCleanRoomConcave: θ=\(Int(theta * 180 / .pi))° \(nc) burchak \(String(format: "%.1f", area))m² → \(outV.count)v \(outT.count)tri")
        return CleanedMesh(vertices: outV, normals: outN, triangles: outT)
    }

    /// Phase 15 (wall-completion): messy TSDF mesh o'rniga TOZA WATERTIGHT xona quradi.
    /// Avval CONCAVE (occupancy) — L-room/alkov ushlaydi. Muvaffaqiyatsiz bo'lsa pastdagi
    /// RANSAC CONVEX fallback (4-burchak quti). INWARD normal (bake kameralar ichkarida).
    /// Mac validatsiya: concave 6-burchak/22.8m² watertight, convex 16 tri. Plan topilmasa input.
    static func buildCleanRoom(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
    ) -> CleanedMesh {
        let nv = vertices.count
        if nv < 3000 || triangles.isEmpty { return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles) }
        // Phase 15b: avval CONCAVE (occupancy) — L-room/alkov/notch ushlaydi. nil bo'lsa
        // pastdagi RANSAC convex fallback ishlaydi (degradatsiya, crash emas).
        if let concave = buildCleanRoomConcave(vertices: vertices, normals: normals, triangles: triangles) {
            return concave
        }
        let V = vertices, N = normals
        let band: Float = 0.08, ndot: Float = 0.5, minIn = 3000, maxP = 16, candN = 250
        var assigned = [Int](repeating: -1, count: nv)
        var avail = [Bool](repeating: true, count: nv)
        var planes: [(c: SIMD3<Float>, n: SIMD3<Float>)] = []
        var rng: UInt64 = 7
        @inline(__always) func rnd(_ b: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(max(b, 1))) }
        for _ in 0..<maxP {
            var pool: [Int] = []; for i in 0..<nv where avail[i] { pool.append(i) }
            if pool.count < minIn { break }
            var bc = 0; var bC = SIMD3<Float>(0, 0, 0); var bN = SIMD3<Float>(0, 1, 0)
            for _ in 0..<candN {
                let ci = pool[rnd(pool.count)]; let pp = V[ci]; let pn = N[ci]
                var cnt = 0; var j = 0
                while j < pool.count { let i = pool[j]; if abs(simd_dot(V[i] - pp, pn)) < band && simd_dot(N[i], pn) > ndot { cnt += 1 }; j += 2 }
                if cnt > bc { bc = cnt; bC = pp; bN = pn }
            }
            if bc * 2 < minIn { break }
            var sumP = SIMD3<Float>(0, 0, 0); var sumN = SIMD3<Float>(0, 0, 0); var k = 0
            for i in pool where abs(simd_dot(V[i] - bC, bN)) < band && simd_dot(N[i], bN) > ndot { sumP += V[i]; sumN += N[i]; k += 1 }
            if k < minIn { for i in pool where abs(simd_dot(V[i] - bC, bN)) < band && simd_dot(N[i], bN) > ndot { avail[i] = false }; continue }
            let c = sumP / Float(k); let n = simd_normalize(sumN); let pidx = planes.count
            for i in pool where abs(simd_dot(V[i] - c, n)) < band && simd_dot(N[i], n) > ndot { assigned[i] = pidx; avail[i] = false }
            planes.append((c, n))
        }
        let ys = V.map { $0.y }.sorted()
        let floorY = ys[ys.count / 100], ceilY = ys[ys.count * 99 / 100]
        struct Wall { var n: SIMD2<Float>; var off: Float; var cen: SIMD2<Float>; var ninl: Int }
        var W: [Wall] = []
        for (pi, pl) in planes.enumerated() {
            if abs(pl.n.y) > 0.7 { continue }
            let nxz = SIMD2<Float>(pl.n.x, pl.n.z); let L = simd_length(nxz)
            if L < 0.3 { continue }
            let nn = nxz / L; let cxz = SIMD2<Float>(pl.c.x, pl.c.z)
            var cc = 0; for v in assigned where v == pi { cc += 1 }
            W.append(Wall(n: nn, off: simd_dot(cxz, nn), cen: cxz, ninl: cc))
        }
        W.sort { $0.ninl > $1.ninl }
        var merged: [Wall] = []
        for w in W where !merged.contains(where: { simd_dot($0.n, w.n) > 0.9 }) { merged.append(w) }
        W = merged
        if W.count < 3 { return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles) }
        let ctr = W.reduce(SIMD2<Float>(0, 0)) { $0 + $1.cen } / Float(W.count)
        W.sort { atan2($0.cen.y - ctr.y, $0.cen.x - ctr.x) < atan2($1.cen.y - ctr.y, $1.cen.x - ctr.x) }
        func lineInt(_ a: Wall, _ b: Wall) -> SIMD2<Float>? {
            let det = a.n.x * b.n.y - a.n.y * b.n.x
            if abs(det) < 1e-6 { return nil }
            return SIMD2<Float>((a.off * b.n.y - b.off * a.n.y) / det, (a.n.x * b.off - b.n.x * a.off) / det)
        }
        var corners: [SIMD2<Float>] = []
        for i in 0..<W.count { if let p = lineInt(W[i], W[(i + 1) % W.count]) { corners.append(p) } }
        if corners.count < 3 { return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles) }
        var outV: [SIMD3<Float>] = []; var outT: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        let mid = SIMD3<Float>(ctr.x, (floorY + ceilY) / 2, ctr.y)
        func quad(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>) {
            let b = UInt32(outV.count)
            var v = [p0, p1, p2, p3]
            let fn = simd_cross(v[1] - v[0], v[2] - v[0])
            if simd_dot(fn, mid - (v[0] + v[2]) / 2) < 0 { v = [p0, p3, p2, p1] }
            outV += v; outT.append((b, b + 1, b + 2)); outT.append((b, b + 2, b + 3))
        }
        let nc = corners.count
        for i in 0..<nc {
            let a = corners[i], b = corners[(i + 1) % nc]
            quad(SIMD3<Float>(a.x, floorY, a.y), SIMD3<Float>(b.x, floorY, b.y),
                 SIMD3<Float>(b.x, ceilY, b.y), SIMD3<Float>(a.x, ceilY, a.y))
        }
        let fc = SIMD3<Float>(ctr.x, floorY, ctr.y), cc2 = SIMD3<Float>(ctr.x, ceilY, ctr.y)
        for i in 0..<nc {
            let a = corners[i], b = corners[(i + 1) % nc]
            var b0 = UInt32(outV.count); outV += [fc, SIMD3<Float>(a.x, floorY, a.y), SIMD3<Float>(b.x, floorY, b.y)]
            if simd_cross(outV[Int(b0) + 1] - outV[Int(b0)], outV[Int(b0) + 2] - outV[Int(b0)]).y < 0 { outT.append((b0, b0 + 2, b0 + 1)) } else { outT.append((b0, b0 + 1, b0 + 2)) }
            b0 = UInt32(outV.count); outV += [cc2, SIMD3<Float>(a.x, ceilY, a.y), SIMD3<Float>(b.x, ceilY, b.y)]
            if simd_cross(outV[Int(b0) + 1] - outV[Int(b0)], outV[Int(b0) + 2] - outV[Int(b0)]).y > 0 { outT.append((b0, b0 + 2, b0 + 1)) } else { outT.append((b0, b0 + 1, b0 + 2)) }
        }
        let outN = recomputeVertexNormals(verts: outV, triangles: outT, fallback: [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: outV.count))
        NSLog("KADASTR buildCleanRoom: \(W.count) devor, \(corners.count) burchak → \(outV.count)v \(outT.count)tri")
        return CleanedMesh(vertices: outV, normals: outN, triangles: outT)
    }

    /// QEM (Garland-Heckbert) edge-collapse decimation. Planar yuzalarni agressiv
    /// soddalashtiradi (kamroq tri), keskin qirralarni saqlaydi (quadric error +
    /// boundary penalty). xatlas UV unwrap tri soniga sezgir (269k→35min); decimate
    /// 120k ~2x tez. Mac prototip (scan_007): detail to'liq saqlandi, tekis yuza
    /// tri'lari yarmiga. Hisob-kitob Double (precision), I/O Float.
    static func decimate(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        targetTriangles: Int,
    ) -> CleanedMesh {
        if triangles.count <= targetTriangles || vertices.count < 4 {
            return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles)
        }
        let nv = vertices.count
        var verts = vertices.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) }
        var tris = triangles.map { (Int($0.v0), Int($0.v1), Int($0.v2)) }

        var Q = [[Double]](repeating: [Double](repeating: 0, count: 10), count: nv)
        func addPlaneTo(_ vi: Int, _ p: SIMD4<Double>, _ scale: Double) {
            let k = [p.x*p.x, p.x*p.y, p.x*p.z, p.x*p.w, p.y*p.y, p.y*p.z, p.y*p.w, p.z*p.z, p.z*p.w, p.w*p.w]
            for t in 0..<10 { Q[vi][t] += k[t] * scale }
        }
        func qadd(_ A: [Double], _ B: [Double]) -> [Double] { var r = A; for t in 0..<10 { r[t] += B[t] }; return r }
        func qerror(_ q: [Double], _ v: SIMD3<Double>) -> Double {
            let x = v.x, y = v.y, z = v.z
            return q[0]*x*x + 2*q[1]*x*y + 2*q[2]*x*z + 2*q[3]*x + q[4]*y*y + 2*q[5]*y*z + 2*q[6]*y + q[7]*z*z + 2*q[8]*z + q[9]
        }
        func optimalPos(_ q: [Double], _ fb: SIMD3<Double>) -> SIMD3<Double> {
            let m = simd_double3x3(rows: [SIMD3<Double>(q[0],q[1],q[2]), SIMD3<Double>(q[1],q[4],q[5]), SIMD3<Double>(q[2],q[5],q[7])])
            if abs(simd_determinant(m)) < 1e-12 { return fb }
            return simd_inverse(m) * SIMD3<Double>(-q[3], -q[6], -q[8])
        }
        for (i0, i1, i2) in tris {
            let nrm = simd_cross(verts[i1]-verts[i0], verts[i2]-verts[i0])
            let len = simd_length(nrm); if len < 1e-12 { continue }
            let un = nrm/len; let d = -simd_dot(un, verts[i0])
            addPlaneTo(i0, SIMD4<Double>(un.x, un.y, un.z, d), 1)
            addPlaneTo(i1, SIMD4<Double>(un.x, un.y, un.z, d), 1)
            addPlaneTo(i2, SIMD4<Double>(un.x, un.y, un.z, d), 1)
        }
        var vertTris = [Set<Int>](repeating: [], count: nv)
        for (ti, t) in tris.enumerated() { vertTris[t.0].insert(ti); vertTris[t.1].insert(ti); vertTris[t.2].insert(ti) }
        var triAlive = [Bool](repeating: true, count: tris.count)
        var vertAlive = [Bool](repeating: true, count: nv)
        var vertVer = [Int](repeating: 0, count: nv)
        func ekey(_ i: Int, _ j: Int) -> UInt64 { UInt64(min(i,j)) << 32 | UInt64(max(i,j)) }
        func triEdges(_ t: (Int,Int,Int)) -> [(Int,Int)] { [(t.0,t.1),(t.1,t.2),(t.0,t.2)] }
        var edgeCount = [UInt64: Int]()
        for t in tris { for e in triEdges(t) { edgeCount[ekey(e.0,e.1), default: 0] += 1 } }
        for (key, cnt) in edgeCount where cnt == 1 {  // boundary edge → saqlash penalty
            let i = Int(key >> 32), j = Int(key & 0xFFFFFFFF)
            let edge = verts[j] - verts[i]
            if let anyTri = vertTris[i].first(where: { triAlive[$0] }) {
                let t = tris[anyTri]
                let fn = simd_cross(verts[t.1]-verts[t.0], verts[t.2]-verts[t.0])
                var perp = simd_cross(edge, fn); let l = simd_length(perp)
                if l > 1e-12 { perp /= l; let d = -simd_dot(perp, verts[i])
                    addPlaneTo(i, SIMD4<Double>(perp.x, perp.y, perp.z, d), 1000)
                    addPlaneTo(j, SIMD4<Double>(perp.x, perp.y, perp.z, d), 1000)
                }
            }
        }
        struct Cand { let cost: Double; let i: Int; let j: Int; let vi: Int; let vj: Int; let pos: SIMD3<Double> }
        var heap = [Cand]()
        func siftUp(_ idx0: Int) { var idx = idx0; while idx > 0 { let p = (idx-1)/2; if heap[idx].cost < heap[p].cost { heap.swapAt(idx,p); idx = p } else { break } } }
        func siftDown(_ idx0: Int) { var idx = idx0; let cnt = heap.count; while true { var s = idx; let l = 2*idx+1, r = 2*idx+2; if l<cnt && heap[l].cost<heap[s].cost { s=l }; if r<cnt && heap[r].cost<heap[s].cost { s=r }; if s != idx { heap.swapAt(idx,s); idx=s } else { break } } }
        func push(_ c: Cand) { heap.append(c); siftUp(heap.count-1) }
        func pop() -> Cand? { if heap.isEmpty { return nil }; let top = heap[0]; heap[0] = heap[heap.count-1]; heap.removeLast(); if !heap.isEmpty { siftDown(0) }; return top }
        func makeCand(_ i: Int, _ j: Int) -> Cand {
            let q = qadd(Q[i], Q[j])
            let mid = (verts[i]+verts[j])*0.5
            var best = mid; var bestE = Double.infinity
            for c in [optimalPos(q, mid), mid, verts[i], verts[j]] { let e = qerror(q, c); if e < bestE { bestE = e; best = c } }
            return Cand(cost: bestE, i: i, j: j, vi: vertVer[i], vj: vertVer[j], pos: best)
        }
        var seeded = Set<UInt64>()
        for t in tris { for e in triEdges(t) { let k = ekey(e.0,e.1); if !seeded.contains(k) { seeded.insert(k); push(makeCand(e.0, e.1)) } } }
        var aliveTriCount = tris.count
        func neighbors(_ i: Int) -> Set<Int> {
            var s = Set<Int>(); for ti in vertTris[i] where triAlive[ti] { let t = tris[ti]; s.insert(t.0); s.insert(t.1); s.insert(t.2) }; s.remove(i); return s
        }
        while aliveTriCount > targetTriangles, let c = pop() {
            if !vertAlive[c.i] || !vertAlive[c.j] || vertVer[c.i] != c.vi || vertVer[c.j] != c.vj { continue }
            let i = c.i, j = c.j
            verts[i] = c.pos; Q[i] = qadd(Q[i], Q[j]); vertAlive[j] = false
            for ti in vertTris[j] where triAlive[ti] {
                var t = tris[ti]
                if t.0 == j { t.0 = i }; if t.1 == j { t.1 = i }; if t.2 == j { t.2 = i }
                if t.0 == t.1 || t.1 == t.2 || t.0 == t.2 { triAlive[ti] = false; aliveTriCount -= 1 }
                else { tris[ti] = t; vertTris[i].insert(ti) }
            }
            vertVer[i] += 1; vertVer[j] += 1
            for nb in neighbors(i) where vertAlive[nb] { push(makeCand(i, nb)) }
        }
        var remap = [Int](repeating: -1, count: nv)
        var outV = [SIMD3<Float>]()
        for vi in 0..<nv where vertAlive[vi] { remap[vi] = outV.count; outV.append(SIMD3<Float>(Float(verts[vi].x), Float(verts[vi].y), Float(verts[vi].z))) }
        var outT = [(v0: UInt32, v1: UInt32, v2: UInt32)]()
        for (ti, t) in tris.enumerated() where triAlive[ti] {
            let a = remap[t.0], b = remap[t.1], cc = remap[t.2]
            if a >= 0 && b >= 0 && cc >= 0 && a != b && b != cc && a != cc { outT.append((UInt32(a), UInt32(b), UInt32(cc))) }
        }
        let fallback = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: outV.count)
        let outNormals = recomputeVertexNormals(verts: outV, triangles: outT, fallback: fallback)
        NSLog("KADASTR decimate: \(triangles.count) → \(outT.count) tri (\(vertices.count) → \(outV.count) vert)")
        return CleanedMesh(vertices: outV, normals: outNormals, triangles: outT)
    }

    /// Speckle removal — floating spike + ragged border vertex'larni qo'shnilar
    /// markaziga TORTADI (o'chirmaydi → teshik yo'q). Spike: 1-ring o'rtacha masofa
    /// > mean+1.5σ (mesh yuzasidan chiqib turgan nuqta). Border: boundary edge
    /// (1 tri) vertex (ragged chekka). Laplacian pull weight 0.7, edge-aware EMAS
    /// (spike'ni majburiy tortish). Mac (scan_007): ichki speckle ketdi, chekka
    /// silliqlandi, teshik 0. SOR-o'chirish va erosion teshik berardi — pull bermaydi.
    static func removeSpeckle(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        iterations: Int = 5,
    ) -> CleanedMesh {
        let nv = vertices.count
        if nv < 4 || triangles.isEmpty { return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles) }
        var adj = [Set<UInt32>](repeating: [], count: nv)
        for t in triangles {
            adj[Int(t.v0)].insert(t.v1); adj[Int(t.v0)].insert(t.v2)
            adj[Int(t.v1)].insert(t.v0); adj[Int(t.v1)].insert(t.v2)
            adj[Int(t.v2)].insert(t.v0); adj[Int(t.v2)].insert(t.v1)
        }
        var ringDist = [Float](repeating: 0, count: nv)
        for i in 0..<nv {
            let nb = adj[i]; if nb.isEmpty { continue }
            var s: Float = 0; for n in nb { s += simd_length(vertices[Int(n)] - vertices[i]) }
            ringDist[i] = s / Float(nb.count)
        }
        let valid = ringDist.filter { $0 > 0 }
        if valid.isEmpty { return CleanedMesh(vertices: vertices, normals: normals, triangles: triangles) }
        let mean = valid.reduce(0, +) / Float(valid.count)
        let variance = valid.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(valid.count)
        let thr = mean + 1.5 * sqrt(variance)
        func ek(_ i: Int, _ j: Int) -> UInt64 { UInt64(min(i, j)) << 32 | UInt64(max(i, j)) }
        var ec = [UInt64: Int]()
        for t in triangles { for e in [(Int(t.v0), Int(t.v1)), (Int(t.v1), Int(t.v2)), (Int(t.v0), Int(t.v2))] { ec[ek(e.0, e.1), default: 0] += 1 } }
        var pullMask = (0..<nv).map { ringDist[$0] > thr }
        for (key, c) in ec where c == 1 { pullMask[Int(key >> 32)] = true; pullMask[Int(key & 0xFFFFFFFF)] = true }
        var verts = vertices
        for _ in 0..<iterations {
            var newV = verts
            for i in 0..<nv where pullMask[i] {
                let nb = adj[i]; if nb.isEmpty { continue }
                var c = SIMD3<Float>(0, 0, 0); for n in nb { c += verts[Int(n)] }
                newV[i] = verts[i] * 0.3 + (c / Float(nb.count)) * 0.7
            }
            verts = newV
        }
        let outNormals = recomputeVertexNormals(verts: verts, triangles: triangles, fallback: normals)
        NSLog("KADASTR removeSpeckle: \(pullMask.filter { $0 }.count)/\(nv) verts pulled (\(iterations) iter)")
        return CleanedMesh(vertices: verts, normals: outNormals, triangles: triangles)
    }

    /// Normal field'ni vertex'ga TEGMASDAN Laplacian-tekislaydi (0.4 o'zi + 0.6
    /// qo'shni o'rta, har iter renormalize). LiDAR bump-shovqinini o'chiradi,
    /// lekin keskin qirra signalini (yuqori amplituda) saqlaydi. taubinSmooth shu
    /// natijani qotirib edge-aware vazn uchun ishlatadi.
    private static func presmoothNormalField(
        _ normals: [SIMD3<Float>],
        adjacency: [Set<UInt32>],
        iterations: Int,
    ) -> [SIMD3<Float>] {
        var nrm = normals
        for _ in 0..<iterations {
            var out = nrm
            for i in 0..<nrm.count {
                let neighbors = adjacency[i]
                if neighbors.isEmpty { continue }
                var s = SIMD3<Float>(0, 0, 0)
                for n in neighbors { s += nrm[Int(n)] }
                let avg = s / Float(neighbors.count)
                let blended = nrm[i] * 0.4 + avg * 0.6
                let len = simd_length(blended)
                out[i] = len > 1e-6 ? blended / len : nrm[i]
            }
            nrm = out
        }
        return nrm
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
