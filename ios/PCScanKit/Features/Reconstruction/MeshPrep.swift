import Foundation
import RoomPlan
import simd

/// ARKit real-time meshini teksturalashdan oldin tozalaydi (on-device).
/// Bosqichlar (prep_arkit.py Swift porti):
///   1. Weld — ARMeshAnchor plitkalarini bitta gridga payvandlash (dublikat cho'qqilar).
///   2. Plane-snap — RoomPlan devor/pol tekisliklariga yaqin cho'qqilarni tekislash.
///   3. Laplacian smoothing — g'adur-budurni yumshatish (snap qilinganlarga kamroq).
///   4. Kichik komponentlarni tashlash — shovqin bo'laklarini olib tashlash.
enum MeshPrep {

    /// Natija: teksturalanadigan teshikli mesh + alohida teshik-to'ldirish meshi.
    /// Teshikli mesh texrecon bilan teksturalanadi (o'tkir atlas), fill meshi
    /// keyin atlas chegara rangi bilan bo'yaladi (FillColorizer).
    static func clean(_ mesh: LiDARMeshData, room: CapturedRoom,
                      log: ((String) -> Void)? = nil) -> (holed: LiDARMeshData, fill: LiDARMeshData) {
        var (verts, norms, faces) = unpack(mesh)
        log?("MESHPREP in verts=\(verts.count) faces=\(faces.count)")

        (verts, norms, faces) = weld(verts, norms, faces, grid: 0.005)
        log?("MESHPREP welded verts=\(verts.count) faces=\(faces.count)")

        var snapped = [Bool](repeating: false, count: verts.count)
        planeSnap(&verts, norms, &snapped, room: room)
        let pct = verts.isEmpty ? 0 : Int(Double(snapped.filter { $0 }.count) / Double(verts.count) * 100)
        log?("MESHPREP snapped=\(pct)%")

        smooth(&verts, faces: faces, snapped: snapped, iterations: 3)

        (verts, faces) = dropSmallComponents(verts, faces, minVerts: 80)
        log?("MESHPREP kept verts=\(verts.count) faces=\(faces.count)")

        // Teshiklarni alohida meshга to'ldiramiz (asosiy mesh teshikli qoladi).
        let (fillVerts, fillTris, filled) = fillHoles(verts, faces, maxPerimeter: 2.0)
        log?("MESHPREP fill holes=\(filled) fillVerts=\(fillVerts.count) fillTris=\(fillTris.count)")

        return (repack(verts, faces), repackTris(fillVerts, fillTris))
    }

    // MARK: - Ichki tur

    private struct Tri { var a: Int; var b: Int; var c: Int }

    private static func unpack(_ mesh: LiDARMeshData) -> ([SIMD3<Float>], [SIMD3<Float>], [Tri]) {
        let vc = mesh.vertexCount
        var verts = [SIMD3<Float>](); verts.reserveCapacity(vc)
        var norms = [SIMD3<Float>](); norms.reserveCapacity(vc)
        for i in 0..<vc {
            verts.append(SIMD3(mesh.positions[i*3], mesh.positions[i*3+1], mesh.positions[i*3+2]))
            norms.append(SIMD3(mesh.normals[i*3], mesh.normals[i*3+1], mesh.normals[i*3+2]))
        }
        var faces = [Tri](); faces.reserveCapacity(mesh.indices.count / 3)
        var i = 0
        while i + 2 < mesh.indices.count {
            faces.append(Tri(a: Int(mesh.indices[i]), b: Int(mesh.indices[i+1]), c: Int(mesh.indices[i+2])))
            i += 3
        }
        return (verts, norms, faces)
    }

    private static func repack(_ verts: [SIMD3<Float>], _ faces: [Tri]) -> LiDARMeshData {
        var positions = [Float](); positions.reserveCapacity(verts.count * 3)
        var normals = [Float](); normals.reserveCapacity(verts.count * 3)
        let vnorm = vertexNormals(verts, faces)
        for i in 0..<verts.count {
            positions.append(verts[i].x); positions.append(verts[i].y); positions.append(verts[i].z)
            normals.append(vnorm[i].x); normals.append(vnorm[i].y); normals.append(vnorm[i].z)
        }
        var indices = [UInt32](); indices.reserveCapacity(faces.count * 3)
        for f in faces { indices.append(UInt32(f.a)); indices.append(UInt32(f.b)); indices.append(UInt32(f.c)) }
        return LiDARMeshData(positions: positions, normals: normals, indices: indices)
    }

    // MARK: - 1. Weld

    private static func weld(_ verts: [SIMD3<Float>], _ norms: [SIMD3<Float>], _ faces: [Tri],
                             grid: Float) -> ([SIMD3<Float>], [SIMD3<Float>], [Tri]) {
        var map = [SIMD3<Int32>: Int](minimumCapacity: verts.count)
        var newVerts = [SIMD3<Float>](); newVerts.reserveCapacity(verts.count)
        var newNorms = [SIMD3<Float>](); newNorms.reserveCapacity(verts.count)
        var remap = [Int](repeating: 0, count: verts.count)
        let inv = 1 / grid
        for i in 0..<verts.count {
            let v = verts[i]
            let key = SIMD3<Int32>(Int32((v.x * inv).rounded()),
                                   Int32((v.y * inv).rounded()),
                                   Int32((v.z * inv).rounded()))
            if let idx = map[key] {
                remap[i] = idx
            } else {
                let idx = newVerts.count
                map[key] = idx
                newVerts.append(v)
                newNorms.append(norms[i])
                remap[i] = idx
            }
        }
        var newFaces = [Tri](); newFaces.reserveCapacity(faces.count)
        for f in faces {
            let a = remap[f.a], b = remap[f.b], c = remap[f.c]
            if a != b && b != c && a != c { newFaces.append(Tri(a: a, b: b, c: c)) }
        }
        return (newVerts, newNorms, newFaces)
    }

    // MARK: - 2. Plane snap

    private static func planeSnap(_ verts: inout [SIMD3<Float>], _ norms: [SIMD3<Float>],
                                  _ snapped: inout [Bool], room: CapturedRoom) {
        func snapPlane(_ transform: simd_float4x4, dist: Float) {
            let n = simd_normalize(SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            let c = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            for i in 0..<verts.count where !snapped[i] {
                let d = simd_dot(verts[i] - c, n)
                if abs(d) < dist && abs(simd_dot(norms[i], n)) > 0.5 {
                    verts[i] -= d * n
                    snapped[i] = true
                }
            }
        }
        for wall in room.walls { snapPlane(wall.transform, dist: 0.10) }
        for floor in room.floors { snapPlane(floor.transform, dist: 0.06) }
    }

    // MARK: - 3. Laplacian smoothing

    private static func smooth(_ verts: inout [SIMD3<Float>], faces: [Tri], snapped: [Bool], iterations: Int) {
        let n = verts.count
        for _ in 0..<iterations {
            var acc = [SIMD3<Float>](repeating: .zero, count: n)
            var cnt = [Float](repeating: 0, count: n)
            for f in faces {
                for (u, w) in [(f.a, f.b), (f.b, f.c), (f.c, f.a)] {
                    acc[u] += verts[w]; cnt[u] += 1
                    acc[w] += verts[u]; cnt[w] += 1
                }
            }
            for i in 0..<n where cnt[i] > 0 {
                let avg = acc[i] / cnt[i]
                let lam: Float = snapped[i] ? 0.1 : 0.4
                verts[i] += lam * (avg - verts[i])
            }
        }
    }

    // MARK: - 4. Kichik komponentlarni tashlash

    private static func dropSmallComponents(_ verts: [SIMD3<Float>], _ faces: [Tri],
                                            minVerts: Int) -> ([SIMD3<Float>], [Tri]) {
        let n = verts.count
        var adj = [[Int]](repeating: [], count: n)
        for f in faces {
            adj[f.a].append(f.b); adj[f.b].append(f.a)
            adj[f.b].append(f.c); adj[f.c].append(f.b)
            adj[f.c].append(f.a); adj[f.a].append(f.c)
        }
        var comp = [Int](repeating: -1, count: n)
        var sizes = [Int]()
        var stack = [Int]()
        for s in 0..<n where comp[s] < 0 {
            let cid = sizes.count
            var size = 0
            comp[s] = cid; stack.append(s)
            while let u = stack.popLast() {
                size += 1
                for w in adj[u] where comp[w] < 0 { comp[w] = cid; stack.append(w) }
            }
            sizes.append(size)
        }
        var keepVert = [Bool](repeating: false, count: n)
        var newIndex = [Int](repeating: -1, count: n)
        var newVerts = [SIMD3<Float>]()
        for i in 0..<n where sizes[comp[i]] >= minVerts {
            keepVert[i] = true
            newIndex[i] = newVerts.count
            newVerts.append(verts[i])
        }
        var newFaces = [Tri]()
        for f in faces where keepVert[f.a] && keepVert[f.b] && keepVert[f.c] {
            newFaces.append(Tri(a: newIndex[f.a], b: newIndex[f.b], c: newIndex[f.c]))
        }
        return (newVerts, newFaces)
    }

    // MARK: - 5. Kichik geometriya teshiklarini to'ldirish

    /// Chegara halqalarini topib, perimetri kichik bo'lganlarini to'ldiradi — ALOHIDA
    /// fill meshга (asosiy mesh o'zgarmaydi). Qaytaradi: (fillVerts, fillTris, teshik soni).
    /// fillTris fillVerts massiviга indekslaydi (chegara cho'qqilari nusxalanadi).
    private static func fillHoles(_ verts: [SIMD3<Float>], _ faces: [Tri],
                                  maxPerimeter: Float) -> ([SIMD3<Float>], [Tri], Int) {
        var fillVerts = [SIMD3<Float>]()
        var fillTris = [Tri]()
        var vmap = [Int: Int]()                 // holed vert idx -> fill vert idx
        func mapV(_ hi: Int) -> Int {
            if let f = vmap[hi] { return f }
            let f = fillVerts.count; fillVerts.append(verts[hi]); vmap[hi] = f; return f
        }
        func ekey(_ a: Int, _ b: Int) -> UInt64 { (UInt64(UInt32(a)) << 32) | UInt64(UInt32(b)) }
        func ukey(_ a: Int, _ b: Int) -> UInt64 { ekey(min(a, b), max(a, b)) }

        // Yo'nalgan chegara qirralari: yo'nalishsiz juftlik faqat 1 marta uchraydi.
        var undirCount = [UInt64: Int](minimumCapacity: faces.count * 3)
        for f in faces {
            for (a, b) in [(f.a, f.b), (f.b, f.c), (f.c, f.a)] {
                undirCount[ukey(a, b), default: 0] += 1
            }
        }
        var nextMap = [Int: [Int]]()
        var boundary: [(Int, Int)] = []
        for f in faces {
            for (a, b) in [(f.a, f.b), (f.b, f.c), (f.c, f.a)] where undirCount[ukey(a, b)] == 1 {
                boundary.append((a, b))
                nextMap[a, default: []].append(b)
            }
        }
        guard !boundary.isEmpty else { return ([], [], 0) }

        // Yo'nalgan chegara qirralarini halqalarga bog'laymiz.
        var used = Set<UInt64>()
        var filledCount = 0
        for (a0, b0) in boundary {
            if used.contains(ekey(a0, b0)) { continue }
            var loop = [a0]
            var cur = b0
            used.insert(ekey(a0, b0))
            var ok = true
            var guardCounter = 0
            while cur != a0 {
                guardCounter += 1
                if guardCounter > 200_000 { ok = false; break }
                let cands = (nextMap[cur] ?? []).filter { !used.contains(ekey(cur, $0)) }
                guard let w = cands.first else { ok = false; break }
                used.insert(ekey(cur, w))
                loop.append(cur)
                cur = w
            }
            guard ok, loop.count >= 3 else { continue }

            // Perimetr — kichik teshiklarnigina to'ldiramiz.
            var perimeter: Float = 0
            for k in 0..<loop.count {
                perimeter += simd_distance(verts[loop[k]], verts[loop[(k + 1) % loop.count]])
            }
            if perimeter > maxPerimeter { continue }

            // Tekislik og'ishini o'lchaymiz (Newell normal + maksimal masofa).
            // Tekis halqa (shift/devor/pol) → ear-clip (tekis, toza).
            // Egri halqa (divan kabi obyekt) → fan (markaz cho'qqisi "ko'rilmagan" bo'lib
            // Poisson bilan atrofdagi rangга silliq aralashadi).
            var loopNormal = SIMD3<Float>(repeating: 0)
            var loopCenter = SIMD3<Float>(repeating: 0)
            for k in 0..<loop.count {
                let cur = verts[loop[k]], nxt = verts[loop[(k + 1) % loop.count]]
                loopNormal.x += (cur.y - nxt.y) * (cur.z + nxt.z)
                loopNormal.y += (cur.z - nxt.z) * (cur.x + nxt.x)
                loopNormal.z += (cur.x - nxt.x) * (cur.y + nxt.y)
                loopCenter += cur
            }
            loopCenter /= Float(loop.count)
            let nlen = simd_length(loopNormal)
            var deviation: Float = 1
            if nlen > 1e-9 {
                let unit = loopNormal / nlen
                deviation = 0
                for idx in loop { deviation = max(deviation, abs(simd_dot(verts[idx] - loopCenter, unit))) }
            }

            let planarTris = deviation < 0.04 ? triangulateLoop(loop, verts: verts) : []
            if !planarTris.isEmpty {
                // Ear-clip — mavjud chegara cho'qqilaridan (fill meshга nusxalab).
                for t in planarTris {
                    fillTris.append(Tri(a: mapV(t.a), b: mapV(t.b), c: mapV(t.c)))
                }
            } else {
                // Fan — markaz cho'qqisidan (egri halqa yoki ear-clip muvaffaqiyatsiz).
                let ci = fillVerts.count
                fillVerts.append(loopCenter)
                for k in 0..<loop.count {
                    fillTris.append(Tri(a: mapV(loop[k]), b: mapV(loop[(k + 1) % loop.count]), c: ci))
                }
            }
            filledCount += 1
        }
        return (fillVerts, fillTris, filledCount)
    }

    /// Cho'qqi/uchburchak massivlaridan LiDARMeshData (normallar hisoblanadi).
    private static func repackTris(_ verts: [SIMD3<Float>], _ tris: [Tri]) -> LiDARMeshData {
        repack(verts, tris)
    }

    /// Chegara halqasini eng mos tekislikда ear-clipping bilan uchburchaklaydi.
    /// Yangi cho'qqi qo'shmaydi (fan-spike'ni oldini oladi). Halqa tartibini saqlaydi
    /// — shu tufayli winding atrofdagi yuzalar bilan mos keladi.
    private static func triangulateLoop(_ loop: [Int], verts: [SIMD3<Float>]) -> [Tri] {
        let n = loop.count
        if n < 3 { return [] }
        if n == 3 { return [Tri(a: loop[0], b: loop[1], c: loop[2])] }

        // Newell usuli — eng mos tekislik normali.
        var normal = SIMD3<Float>(repeating: 0)
        for i in 0..<n {
            let cur = verts[loop[i]], nxt = verts[loop[(i + 1) % n]]
            normal.x += (cur.y - nxt.y) * (cur.z + nxt.z)
            normal.y += (cur.z - nxt.z) * (cur.x + nxt.x)
            normal.z += (cur.x - nxt.x) * (cur.y + nxt.y)
        }
        let nlen = simd_length(normal)
        guard nlen > 1e-9 else { return [] }
        normal /= nlen

        // Tekislikда 2D bazis.
        let ref: SIMD3<Float> = abs(normal.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        let u = simd_normalize(simd_cross(ref, normal))
        let v = simd_cross(normal, u)
        var pts = [SIMD2<Float>]()
        pts.reserveCapacity(n)
        for idx in loop {
            let p = verts[idx]
            pts.append(SIMD2(simd_dot(p, u), simd_dot(p, v)))
        }

        // Yo'nalish (halqa tartibini saqlaymiz, faqat konveks testini moslaymiz).
        var area: Float = 0
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            area += a.x * b.y - b.x * a.y
        }
        let orient: Float = area >= 0 ? 1 : -1

        func pointInTri(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
            let d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
            let d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
            let d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
            let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
            let hasPos = d1 > 0 || d2 > 0 || d3 > 0
            return !(hasNeg && hasPos)
        }

        var tris = [Tri]()
        var idxs = Array(0..<n)          // pts/loop ichidagi lokal indekslar
        var guardCounter = 0
        while idxs.count > 3 && guardCounter < 20_000 {
            guardCounter += 1
            let m = idxs.count
            var earFound = false
            for i in 0..<m {
                let l0 = idxs[(i + m - 1) % m], l1 = idxs[i], l2 = idxs[(i + 1) % m]
                let a = pts[l0], b = pts[l1], c = pts[l2]
                let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
                if cross * orient <= 0 { continue }        // refleks burchak — quloq emas
                var contains = false
                for j in idxs where j != l0 && j != l1 && j != l2 {
                    if pointInTri(pts[j], a, b, c) { contains = true; break }
                }
                if contains { continue }
                tris.append(Tri(a: loop[l0], b: loop[l1], c: loop[l2]))
                idxs.remove(at: i)
                earFound = true
                break
            }
            if !earFound { break }        // degenerativ — to'xtaymiz
        }
        if idxs.count == 3 {
            tris.append(Tri(a: loop[idxs[0]], b: loop[idxs[1]], c: loop[idxs[2]]))
            return tris
        }
        return []          // to'liq uchburchaklanmadi — chaqiruvchi fan zaxirani ishlatadi
    }

    // MARK: - Cho'qqi normallari (yuza normallaridan)

    private static func vertexNormals(_ verts: [SIMD3<Float>], _ faces: [Tri]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: verts.count)
        for f in faces {
            let e1 = verts[f.b] - verts[f.a]
            let e2 = verts[f.c] - verts[f.a]
            let fn = simd_cross(e1, e2)
            normals[f.a] += fn; normals[f.b] += fn; normals[f.c] += fn
        }
        for i in 0..<normals.count {
            let len = simd_length(normals[i])
            normals[i] = len > 1e-8 ? normals[i] / len : SIMD3(0, 1, 0)
        }
        return normals
    }
}
