import Foundation
import simd

/// Oriented nuqta bulutidan silliq, yaxlit (watertight) mesh quradi —
/// Scaniverse `PoissonMeshing` bosqichining engil, o'zi-yetarli muqobili.
///
/// Usul: IMLS (Implicit Moving Least Squares) belgili masofa maydoni +
/// narrow-band Marching Cubes + Laplacian silliqlash. Poisson bilan bir
/// oiladan (implicit surface), lekin Kazhdan template-kutubxonasisiz.
enum ImplicitMesher {

    /// Voxel o'lchami (metr). Kichikroq = zichroq/silliqroq, lekin sekinroq.
    static func reconstruct(
        points: [PointCloudBuilder.Point],
        voxelSize: Float = 0.022,
        simplify: Bool = true,
        onProgress: ((String, Int) -> Void)? = nil
    ) -> WeldedMesh? {
        guard points.count > 100 else { return nil }

        onProgress?("Hajm qurilmoqda", 0)

        // 1) Spatial hash — IMLS uchun qo'shni nuqtalarni tez topish
        let searchRadius = voxelSize * 2.2
        let cellSize = searchRadius
        let invCell = 1 / cellSize
        var hash: [SIMD3<Int32>: [Int32]] = [:]
        hash.reserveCapacity(points.count)
        var minB = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxB = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for (i, p) in points.enumerated() {
            let c = SIMD3<Int32>(
                Int32((p.position.x * invCell).rounded(.down)),
                Int32((p.position.y * invCell).rounded(.down)),
                Int32((p.position.z * invCell).rounded(.down))
            )
            hash[c, default: []].append(Int32(i))
            minB = simd_min(minB, p.position)
            maxB = simd_max(maxB, p.position)
        }

        let invVoxel = 1 / voxelSize
        let h2 = (voxelSize * 1.1) * (voxelSize * 1.1)  // Gauss kengligi
        let r2 = searchRadius * searchRadius

        // IMLS belgili masofa: f(x) = Σ w·dot(x-p, n) / Σ w
        // Σw juda kichik bo'lsa — nuqta yaqin emas (noaniq)
        func sdf(_ x: SIMD3<Float>) -> Float? {
            let base = SIMD3<Int32>(
                Int32((x.x * invCell).rounded(.down)),
                Int32((x.y * invCell).rounded(.down)),
                Int32((x.z * invCell).rounded(.down))
            )
            var wSum: Float = 0
            var fSum: Float = 0
            for dz in -1...1 {
                for dy in -1...1 {
                    for dx in -1...1 {
                        let key = SIMD3<Int32>(base.x + Int32(dx), base.y + Int32(dy), base.z + Int32(dz))
                        guard let bucket = hash[key] else { continue }
                        for idx in bucket {
                            let p = points[Int(idx)]
                            let diff = x - p.position
                            let d2 = simd_length_squared(diff)
                            if d2 > r2 { continue }
                            let w = expf(-d2 / h2)
                            wSum += w
                            fSum += w * simd_dot(diff, p.normal)
                        }
                    }
                }
            }
            guard wSum > 0.05 else { return nil }
            return fSum / wSum
        }

        // 2) Narrow-band: har nuqta atrofidagi voxel korpuslarini belgilaymiz,
        // faqat sirt yaqinidagi kataklarni marching cubes'ga beramiz.
        onProgress?("Sirt aniqlanmoqda", 20)
        var candidateCells = Set<SIMD3<Int32>>()
        candidateCells.reserveCapacity(points.count * 4)
        for p in points {
            let vc = SIMD3<Int32>(
                Int32((p.position.x * invVoxel).rounded(.down)),
                Int32((p.position.y * invVoxel).rounded(.down)),
                Int32((p.position.z * invVoxel).rounded(.down))
            )
            for dz in -1...1 {
                for dy in -1...1 {
                    for dx in -1...1 {
                        candidateCells.insert(SIMD3<Int32>(vc.x + Int32(dx), vc.y + Int32(dy), vc.z + Int32(dz)))
                    }
                }
            }
        }

        // 3) Korner SDF keshi
        var cornerCache: [SIMD3<Int32>: Float] = [:]
        cornerCache.reserveCapacity(candidateCells.count * 2)
        func cornerSDF(_ c: SIMD3<Int32>) -> Float {
            if let v = cornerCache[c] { return v }
            let x = SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)) * voxelSize
            let v = sdf(x) ?? Float.greatestFiniteMagnitude
            cornerCache[c] = v
            return v
        }

        // 4) Marching cubes (narrow-band)
        onProgress?("Mesh qurilmoqda", 40)
        var vertexMap: [SIMD3<Int64>: UInt32] = [:]  // qirra kaliti → vertex indeks
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let cornerOffset: [SIMD3<Int32>] = [
            [0,0,0],[1,0,0],[1,1,0],[0,1,0],
            [0,0,1],[1,0,1],[1,1,1],[0,1,1]
        ]

        for cell in candidateCells {
            var cornerVals = [Float](repeating: 0, count: 8)
            var cubeIndex = 0
            var valid = true
            for i in 0..<8 {
                let c = cell &+ cornerOffset[i]
                let v = cornerSDF(c)
                if v == Float.greatestFiniteMagnitude { valid = false; break }
                cornerVals[i] = v
                if v < 0 { cubeIndex |= (1 << i) }
            }
            guard valid else { continue }
            let edges = MarchingCubes.edgeTable[cubeIndex]
            if edges == 0 { continue }

            var edgeVerts = [UInt32](repeating: 0, count: 12)
            for e in 0..<12 where (edges & (1 << e)) != 0 {
                let (a, b) = MarchingCubes.edgeCorners[e]
                let ca = cell &+ cornerOffset[a]
                let cb = cell &+ cornerOffset[b]
                edgeVerts[e] = getEdgeVertex(
                    ca, cb, cornerVals[a], cornerVals[b],
                    voxelSize: voxelSize, map: &vertexMap, positions: &positions
                )
            }

            let tri = MarchingCubes.triTable[cubeIndex]
            var t = 0
            while t < 16 && tri[t] != -1 {
                indices.append(edgeVerts[Int(tri[t])])
                indices.append(edgeVerts[Int(tri[t + 1])])
                indices.append(edgeVerts[Int(tri[t + 2])])
                t += 3
            }
        }

        guard positions.count > 10, indices.count >= 3 else { return nil }

        // 5) Laplacian silliqlash (marching-cubes zinapoyasini yumshatadi)
        onProgress?("Silliqlanmoqda", 70)
        laplacianSmooth(positions: &positions, indices: indices, iterations: 3, factor: 0.5)

        // 6) Decimation (Scaniverse "Simplification" bosqichi) — uchburchak sonini
        // kamaytiradi: xatlas'ni tezlashtiradi.
        // MUHIM: simplify TRIM'DAN KEYIN qilinishi kerak. Qo'pol (soddalashtirilgan)
        // mesh'ni trim qilish komponentlarni 400-face chegaradan pastga tushirib
        // 90% o'chiradi (katta xonada teshik/parcha). Shuning uchun OnDeviceTexturing
        // `simplify: false` bilan chaqiradi, trim'dan keyin `simplifyMesh` ni ishlatadi.
        var mesh = WeldedMesh(positions: positions, normals: [], indices: indices)
        if simplify {
            onProgress?("Soddalashtirilmoqda", 82)
            mesh = simplifyMesh(mesh, targetTriangles: 150_000)
        }
        let normals = computeNormals(positions: mesh.positions, indices: mesh.indices)
        onProgress?("Mesh tayyor", 90)
        return WeldedMesh(positions: mesh.positions, normals: normals, indices: mesh.indices)
    }

    /// meshopt decimation — target uchburchakka kamaytiradi (topologiyani saqlaydi, teshik ochmaydi).
    /// TRIM'DAN KEYIN chaqiring (zich mesh'da trim toza ishlaydi, keyin bu tezlik uchun kamaytiradi).
    static func simplifyMesh(_ m: WeldedMesh, targetTriangles: Int, targetError: Float = 0.02) -> WeldedMesh {
        guard m.indices.count / 3 > targetTriangles else { return m }
        var flat = [Float](repeating: 0, count: m.positions.count * 3)
        for (i, p) in m.positions.enumerated() {
            flat[i * 3] = p.x; flat[i * 3 + 1] = p.y; flat[i * 3 + 2] = p.z
        }
        guard let simplified = MeshOptBridge.simplifyIndices(
            m.indices, indexCount: UInt(m.indices.count),
            positions: flat, vertexCount: UInt(m.positions.count),
            targetTriangles: UInt(targetTriangles), targetError: targetError
        ) else { return m }
        var newIndices = [UInt32](repeating: 0, count: simplified.count / 4)
        simplified.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt32.self)
            for i in 0..<newIndices.count { newIndices[i] = ptr[i] }
        }
        guard newIndices.count >= 3 else { return m }
        return WeldedMesh(positions: m.positions, normals: [], indices: newIndices)
    }

    // MARK: - Edge vertex (qirrada iso-kesishma)

    private static func getEdgeVertex(
        _ ca: SIMD3<Int32>, _ cb: SIMD3<Int32>, _ va: Float, _ vb: Float,
        voxelSize: Float,
        map: inout [SIMD3<Int64>: UInt32], positions: inout [SIMD3<Float>]
    ) -> UInt32 {
        // Qirra kaliti: ikki korner (tartiblangan)
        let (lo, hi): (SIMD3<Int32>, SIMD3<Int32>) = lessThan(ca, cb) ? (ca, cb) : (cb, ca)
        let key = SIMD3<Int64>(
            (Int64(lo.x) << 21) | Int64(hi.x & 0x1FFFFF),
            (Int64(lo.y) << 21) | Int64(hi.y & 0x1FFFFF),
            (Int64(lo.z) << 21) | Int64(hi.z & 0x1FFFFF)
        )
        if let v = map[key] { return v }

        let denom = va - vb
        let t: Float = abs(denom) > 1e-8 ? va / denom : 0.5
        let pa = SIMD3<Float>(Float(ca.x), Float(ca.y), Float(ca.z)) * voxelSize
        let pb = SIMD3<Float>(Float(cb.x), Float(cb.y), Float(cb.z)) * voxelSize
        let pos = pa + (pb - pa) * simd_clamp(t, 0, 1)

        let index = UInt32(positions.count)
        positions.append(pos)
        map[key] = index
        return index
    }

    private static func lessThan(_ a: SIMD3<Int32>, _ b: SIMD3<Int32>) -> Bool {
        if a.x != b.x { return a.x < b.x }
        if a.y != b.y { return a.y < b.y }
        return a.z < b.z
    }

    // MARK: - Geometry helpers

    private static func computeNormals(
        positions: [SIMD3<Float>], indices: [UInt32]
    ) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var t = 0
        while t + 2 < indices.count {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            t += 3
            let fn = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += fn; normals[b] += fn; normals[c] += fn
        }
        for i in 0..<normals.count {
            let len = simd_length(normals[i])
            normals[i] = len > 1e-8 ? normals[i] / len : SIMD3<Float>(0, 1, 0)
        }
        return normals
    }

    /// BILATERAL (normal-og'irlikli) Taubin silliqlash — tekis joylarni (devor, pol)
    /// TEKISLAYDI, lekin burchak/qirralarni SAQLAYDI. Qo'shni verteks o'sha tekislikда
    /// bo'lsa (normali o'xshash) → og'irligi katta → tekislanadi; burchak orqasida bo'lsa
    /// (normali farqli) → og'irligi kichik → tegilmaydi. Shu bilan shovqinli skandagi
    /// "eritilgan/to'lqin" devorlar tekislanadi, burchaklar aniq qoladi.
    private static func laplacianSmooth(
        positions: inout [SIMD3<Float>], indices: [UInt32],
        iterations: Int, factor: Float
    ) {
        var nbList = [[UInt32]](repeating: [], count: positions.count)
        do {
            var seen = [Set<UInt32>](repeating: [], count: positions.count)
            var t = 0
            while t + 2 < indices.count {
                let a = indices[t], b = indices[t + 1], c = indices[t + 2]; t += 3
                for (u, v) in [(a, b), (a, c), (b, a), (b, c), (c, a), (c, b)] {
                    if seen[Int(u)].insert(v).inserted { nbList[Int(u)].append(v) }
                }
            }
        }
        let lambda: Float = 0.6
        let mu: Float = -0.62   // |μ| > λ — Taubin (qisqarishni bekor qiladi)

        func vertexNormals() -> [SIMD3<Float>] {
            var n = [SIMD3<Float>](repeating: .zero, count: positions.count)
            var t = 0
            while t + 2 < indices.count {
                let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2]); t += 3
                let fn = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
                n[a] += fn; n[b] += fn; n[c] += fn
            }
            for i in 0..<n.count { let l = simd_length(n[i]); if l > 1e-9 { n[i] /= l } }
            return n
        }
        func step(_ f: Float, _ nrm: [SIMD3<Float>]) {
            var next = positions
            for i in 0..<positions.count {
                let nb = nbList[i]
                if nb.isEmpty { continue }
                let ni = nrm[i]
                var acc = SIMD3<Float>.zero
                var wsum: Float = 0
                for j in nb {
                    // normal o'xshashligi^3 — qirralarni keskin saqlaydi, tekislikni tekislaydi
                    let s = max(0, simd_dot(ni, nrm[Int(j)]))
                    let w = s * s * s + 0.02   // +epsilon: butunlay izolyatsiya bo'lmasin
                    acc += positions[Int(j)] * w; wsum += w
                }
                if wsum > 1e-6 {
                    next[i] = positions[i] + (acc / wsum - positions[i]) * f
                }
            }
            positions = next
        }
        for _ in 0..<iterations {
            let nrm = vertexNormals()
            step(lambda, nrm)
            step(mu, nrm)
        }
        _ = factor
    }
}
