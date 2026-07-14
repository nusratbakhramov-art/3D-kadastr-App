import Foundation
import simd

/// Skan qilinmagan INTERIOR teshiklarni (stol tagi, stullar orasi, okklyuziya crevice)
/// SILLIQ sirt bilan to'ldiradi (Liepa 2003 uslubida: ear-clip → sentroid-refine → membrane
/// fairing). Tashqi chegara (xona silueti) va TEKIS katta ochiqlik (deraza/eshik) OCHIQ qoladi.
///
/// - Kichik teshik (≤smallCap): har shakl, silliqlashsiz (mayda, kerak emas).
/// - Katta teshik: FAQAT NOTEKIS (3D crevice — okklyuziya) bo'lsa to'ldiriladi; katta TEKIS
///   ochiqlik (deraza/eshik, planar) ochiq qoldiriladi. To'ldirilгач sentroid qo'shib
///   (T-junction'siz 1→3 split) va Laplacian membrane fairing bilan SILLIQ egri patch.
enum MeshSmoothFill {

    static func fill(_ mesh: WeldedMesh,
                     smallCap: Int = 150,
                     maxHoleEdges: Int = 4000,
                     refineLevels: Int = 3,
                     fairIterations: Int = 60,
                     planarTol: Float = 0.07) -> WeldedMesh {
        let P0 = mesh.positions, idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 200 else { return mesh }

        func key(_ a: UInt32, _ b: UInt32) -> UInt64 { (UInt64(a) << 32) | UInt64(b) }
        var dirEdges = Set<UInt64>(); dirEdges.reserveCapacity(faceCount * 3)
        for f in 0..<faceCount {
            let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
            dirEdges.insert(key(a, b)); dirEdges.insert(key(b, c)); dirEdges.insert(key(c, a))
        }
        var next = [UInt32: UInt32](minimumCapacity: 2048)
        for f in 0..<faceCount {
            let v = [idx[f*3], idx[f*3+1], idx[f*3+2]]
            for e in 0..<3 {
                let a = v[e], b = v[(e+1) % 3]
                if !dirEdges.contains(key(b, a)) { next[a] = b }
            }
        }
        guard !next.isEmpty else { return mesh }

        // Barcha chegara halqalarini yig'
        var visited = Set<UInt32>()
        var loops: [[UInt32]] = []
        for start in next.keys {
            if visited.contains(start) { continue }
            var loop = [UInt32](); var cur = start; var ok = true
            while !visited.contains(cur) {
                visited.insert(cur); loop.append(cur)
                guard let n = next[cur] else { ok = false; break }
                cur = n
                if cur == start { break }
                if loop.count > maxHoleEdges + 2 { ok = false; break }
            }
            if ok, cur == start, loop.count >= 3, loop.count <= maxHoleEdges { loops.append(loop) }
        }
        guard !loops.isEmpty else { return mesh }

        // Eng KATTA halqa = tashqi chegara (siluet) — TO'LDIRILMAYDI
        var largestIdx = 0, largestLen = -1
        for (i, l) in loops.enumerated() where l.count > largestLen { largestLen = l.count; largestIdx = i }

        var newPos = P0
        var newIdx = idx
        var adj = [Int: Set<Int>]()          // patch qo'shnilik (fairing uchun)
        var movable = Set<Int>()             // sentroid vertekslar (siljiydigan)
        func addTri(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            newIdx.append(a); newIdx.append(b); newIdx.append(c)
            let ia = Int(a), ib = Int(b), ic = Int(c)
            adj[ia, default: []].insert(ib); adj[ia, default: []].insert(ic)
            adj[ib, default: []].insert(ia); adj[ib, default: []].insert(ic)
            adj[ic, default: []].insert(ia); adj[ic, default: []].insert(ib)
        }

        var filled = 0
        for (li, loop) in loops.enumerated() {
            if li == largestIdx { continue }                       // tashqi chegara ochiq
            let n = loop.count
            let pts = loop.map { P0[Int($0)] }

            // planarlik + o'lcham
            let (nrm, dev) = planeFit(pts)
            var mn = SIMD3<Float>(1e9,1e9,1e9), mx = -mn
            for p in pts { mn = simd_min(mn,p); mx = simd_max(mx,p) }
            let diag = simd_length(mx - mn)

            let doFill: Bool
            if n <= smallCap {
                doFill = true                                      // mayda — har shakl
            } else {
                // katta: notekis (3D crevice) bo'lsa to'ldir; katta TEKIS (deraza/eshik) ochiq
                let isPlanarOpening = (dev <= planarTol) && (diag > 0.6)
                doFill = !isPlanarOpening
            }
            _ = nrm
            guard doFill else { continue }

            guard let tris = earClip(pts) else { continue }
            var patch: [(UInt32, UInt32, UInt32)] = tris.map { (loop[$0.2], loop[$0.1], loop[$0.0]) }  // teskari winding

            // KATTA teshikni refine + fair (silliq egri patch). Mayda teshik tekis qoladi.
            let doSmooth = (n > smallCap) || (diag > 0.4)
            if doSmooth {
                for _ in 0..<refineLevels {
                    var nextTris: [(UInt32, UInt32, UInt32)] = []
                    nextTris.reserveCapacity(patch.count * 3)
                    for (a, b, c) in patch {
                        let g = UInt32(newPos.count)
                        newPos.append((newPos[Int(a)] + newPos[Int(b)] + newPos[Int(c)]) / 3)
                        movable.insert(Int(g))
                        nextTris.append((a, b, g)); nextTris.append((b, c, g)); nextTris.append((c, a, g))
                    }
                    patch = nextTris
                }
            }
            for (a, b, c) in patch { addTri(a, b, c) }
            filled += 1
        }

        // MEMBRANE FAIRING — siljiydigan (sentroid) vertekslarни qo'shnilar o'rtachasига (Laplacian),
        // chegara vertekslari QOTIRILGAN → silliq minimal-sirt patch.
        if !movable.isEmpty {
            let movArr = Array(movable)
            for _ in 0..<fairIterations {
                var upd = [Int: SIMD3<Float>](minimumCapacity: movArr.count)
                for v in movArr {
                    guard let ns = adj[v], !ns.isEmpty else { continue }
                    var acc = SIMD3<Float>(0,0,0)
                    for w in ns { acc += newPos[w] }
                    upd[v] = acc / Float(ns.count)
                }
                for (v, p) in upd { newPos[v] = p }
            }
        }

        NSLog("MeshSmoothFill: %d interior teshik silliq to'ldirildi (+%d vertex)", filled, newPos.count - P0.count)
        if filled == 0 { return mesh }
        return WeldedMesh(positions: newPos, normals: [], indices: newIdx)
    }

    /// Eng-mos tekislik normali + maksimal og'ish (planarlik o'lchovi).
    private static func planeFit(_ pts: [SIMD3<Float>]) -> (SIMD3<Float>, Float) {
        let n = pts.count
        var nrm = SIMD3<Float>(0,0,0)
        for i in 0..<n {
            let a = pts[i], b = pts[(i+1) % n]
            nrm.x += (a.y - b.y) * (a.z + b.z)
            nrm.y += (a.z - b.z) * (a.x + b.x)
            nrm.z += (a.x - b.x) * (a.y + b.y)
        }
        let nl = simd_length(nrm)
        guard nl > 1e-9 else { return (SIMD3<Float>(0,1,0), 1e9) }
        nrm /= nl
        let c = pts.reduce(SIMD3<Float>(0,0,0), +) / Float(n)
        var dev: Float = 0
        for p in pts { dev = max(dev, abs(simd_dot(p - c, nrm))) }
        return (nrm, dev)
    }

    /// 3D ko'pburchakni eng-mos tekislikка proyeksiya qilib ear-clipping bilan uchburchaklaydi.
    private static func earClip(_ poly3: [SIMD3<Float>]) -> [(Int, Int, Int)]? {
        let n = poly3.count
        guard n >= 3 else { return nil }
        if n == 3 { return [(0, 1, 2)] }
        var nrm = SIMD3<Float>(0, 0, 0)
        for i in 0..<n {
            let a = poly3[i], b = poly3[(i+1) % n]
            nrm.x += (a.y - b.y) * (a.z + b.z); nrm.y += (a.z - b.z) * (a.x + b.x); nrm.z += (a.x - b.x) * (a.y + b.y)
        }
        let nl = simd_length(nrm); guard nl > 1e-12 else { return nil }; nrm /= nl
        var u = simd_cross(nrm, SIMD3<Float>(0, 1, 0))
        if simd_length(u) < 1e-6 { u = simd_cross(nrm, SIMD3<Float>(1, 0, 0)) }
        u = simd_normalize(u)
        let v = simd_cross(nrm, u)
        let c = poly3.reduce(SIMD3<Float>(0,0,0), +) / Float(n)
        var pts2 = poly3.map { p -> SIMD2<Float> in let d = p - c; return SIMD2(simd_dot(d, u), simd_dot(d, v)) }
        var area: Float = 0
        for i in 0..<n { let a = pts2[i], b = pts2[(i+1) % n]; area += a.x * b.y - b.x * a.y }
        var order = Array(0..<n)
        if area < 0 { order.reverse(); pts2.reverse() }
        func cross2(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func inside(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ cc: SIMD2<Float>) -> Bool {
            let d1 = cross2(p, a, b), d2 = cross2(p, b, cc), d3 = cross2(p, cc, a)
            let hasNeg = d1 < 0 || d2 < 0 || d3 < 0, hasPos = d1 > 0 || d2 > 0 || d3 > 0
            return !(hasNeg && hasPos)
        }
        var remaining = Array(0..<pts2.count)
        var out = [(Int, Int, Int)]()
        var guardCount = 0
        while remaining.count > 3 && guardCount < pts2.count * pts2.count {
            guardCount += 1
            var clipped = false
            let m = remaining.count
            for i in 0..<m {
                let ip = remaining[(i + m - 1) % m], ic = remaining[i], inx = remaining[(i + 1) % m]
                let a = pts2[ip], b = pts2[ic], cc = pts2[inx]
                if cross2(a, b, cc) <= 0 { continue }
                var ear = true
                for r in remaining where r != ip && r != ic && r != inx {
                    if inside(pts2[r], a, b, cc) { ear = false; break }
                }
                if !ear { continue }
                out.append((order[ip], order[ic], order[inx]))
                remaining.remove(at: i); clipped = true; break
            }
            if !clipped { break }
        }
        if remaining.count == 3 { out.append((order[remaining[0]], order[remaining[1]], order[remaining[2]])) }
        return out.isEmpty ? nil : out
    }
}
