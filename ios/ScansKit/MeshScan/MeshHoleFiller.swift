import Foundation
import simd

/// Mesh'dagi KICHIK-O'RTA teshiklarni yopadi (Hoppe bo'shliqlari + trim qoldirgan teshiklar).
/// KATTA ochiqliklar (eshik, tashqi chegara) ochiq qoladi.
///
/// To'ldirish EAR-CLIPPING bilan: yangi (markaz) vertex QO'SHILMAYDI — teshik ko'pburchagi
/// o'zining eng-mos tekisligiga proyeksiya qilinib, faqat mavjud chegara vertekslari bilan
/// uchburchaklanadi. Shu bilan to'ldiruvchi yuzlar sirtda yotadi → tekstura toza (markaz-fan
/// usulidagi "jigarrang yulduzcha" artefakti yo'q).
enum MeshHoleFiller {

    /// - maxHoleEdges: ixtiyoriy SHAKLDAGI teshik shu chegara ichida to'ldiriladi.
    /// - maxFloorCeilEdges: KATTA teshik (150..800 qirra) FAQAT gorizontal-tekis bo'lsa
    ///   (pol/shift) to'ldiriladi — LiDAR yaltiroq plitka/shift chirog'ida bo'sh qaytaradi,
    ///   lekin RGB kadr o'sha polni KO'RGAN → tekis to'ldiruv homografiya bilan mukammal
    ///   teksturalanadi (qora teshik o'rniga haqiqiy pol/shift). Vertikal katta teshik
    ///   (deraza/eshik) TEGILMAYDI — ochiq qoladi.
    static func fill(_ mesh: WeldedMesh,
                     maxHoleEdges: Int = 60,
                     maxFloorCeilEdges: Int = 800,
                     planarTol: Float = 0.06) -> WeldedMesh {
        let idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 10 else { return mesh }
        let P = mesh.positions
        let loopCap = max(maxHoleEdges, maxFloorCeilEdges)

        func key(_ a: UInt32, _ b: UInt32) -> UInt64 { (UInt64(a) << 32) | UInt64(b) }

        var dirEdges = Set<UInt64>(); dirEdges.reserveCapacity(faceCount * 3)
        for f in 0..<faceCount {
            let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
            dirEdges.insert(key(a, b)); dirEdges.insert(key(b, c)); dirEdges.insert(key(c, a))
        }
        var next = [UInt32: UInt32](minimumCapacity: 1024)
        for f in 0..<faceCount {
            let v = [idx[f*3], idx[f*3+1], idx[f*3+2]]
            for e in 0..<3 {
                let a = v[e], b = v[(e+1) % 3]
                if !dirEdges.contains(key(b, a)) { next[a] = b }
            }
        }
        guard !next.isEmpty else { return mesh }

        var newIndices = mesh.indices
        var visited = Set<UInt32>()
        var filled = 0, skipped = 0

        for start in next.keys {
            if visited.contains(start) { continue }
            var loop = [UInt32]()
            var cur = start; var ok = true
            while !visited.contains(cur) {
                visited.insert(cur); loop.append(cur)
                guard let n = next[cur] else { ok = false; break }
                cur = n
                if cur == start { break }
                if loop.count > loopCap + 2 { ok = false; break }
            }
            guard ok, cur == start, loop.count >= 3, loop.count <= loopCap else { skipped += 1; continue }

            let loopPts = loop.map { P[Int($0)] }

            // To'ldirish qaroriga kel: kichik teshik (ixtiyoriy shakl) yoki KATTA gorizontal-tekis
            // teshik (pol/shift). Katta lekin tekis-emas / vertikal teshik (deraza) ochiq qoldiriladi.
            let fillable: Bool
            if loop.count <= maxHoleEdges {
                fillable = true
            } else {
                fillable = isHorizontalPlanarHole(loopPts, tol: planarTol)
            }
            guard fillable else { skipped += 1; continue }

            // Chegara (a→b, yuz tartibida); to'ldiruvchi yuzlar TESKARI winding bo'lishi kerak.
            if let tris = earClip(loopPts) {
                for t in tris {
                    // t = (i,j,k) loop-tartibidagi indekslar; teskari: k,j,i
                    newIndices.append(loop[t.2]); newIndices.append(loop[t.1]); newIndices.append(loop[t.0])
                }
                filled += 1
            } else { skipped += 1 }
        }
        NSLog("MeshHoleFiller: %d teshik to'ldirildi, %d ochiqlik qoldi", filled, skipped)
        if filled == 0 { return mesh }
        return WeldedMesh(positions: mesh.positions, normals: [], indices: newIndices)
    }

    /// Teshik chegarasi GORIZONTAL (pol/shift) va TEKIS bo'lsa `true`. Katta teshiklarni
    /// faqat shunda to'ldiramiz — vertikal katta ochiqlik (deraza/eshik) ochiq qolsin.
    private static func isHorizontalPlanarHole(_ pts: [SIMD3<Float>], tol: Float) -> Bool {
        let n = pts.count
        guard n >= 4 else { return false }
        // Newell normali (eng-mos tekislik)
        var nrm = SIMD3<Float>(0, 0, 0)
        for i in 0..<n {
            let a = pts[i], b = pts[(i+1) % n]
            nrm.x += (a.y - b.y) * (a.z + b.z)
            nrm.y += (a.z - b.z) * (a.x + b.x)
            nrm.z += (a.x - b.x) * (a.y + b.y)
        }
        let nl = simd_length(nrm)
        guard nl > 1e-9 else { return false }
        nrm /= nl
        // GORIZONTAL bo'lishi shart (pol/shift): normal ~ ±Y
        guard abs(nrm.y) > 0.85 else { return false }
        // TEKIS bo'lishi shart: har verteks tekislikdan tol ichida
        let c = pts.reduce(SIMD3<Float>(0,0,0), +) / Float(n)
        var maxDev: Float = 0
        for p in pts { maxDev = max(maxDev, abs(simd_dot(p - c, nrm))) }
        return maxDev <= tol
    }

    /// 3D ko'pburchakni eng-mos tekislikка proyeksiya qilib ear-clipping bilan uchburchaklaydi.
    /// Qaytadi: loop ichidagi indekslar uchligi (winding = kirish loop yo'nalishi).
    private static func earClip(_ poly3: [SIMD3<Float>]) -> [(Int, Int, Int)]? {
        let n = poly3.count
        guard n >= 3 else { return nil }
        if n == 3 { return [(0, 1, 2)] }

        // Eng-mos tekislik normali (Newell metodi)
        var nrm = SIMD3<Float>(0, 0, 0)
        for i in 0..<n {
            let a = poly3[i], b = poly3[(i+1) % n]
            nrm.x += (a.y - b.y) * (a.z + b.z)
            nrm.y += (a.z - b.z) * (a.x + b.x)
            nrm.z += (a.x - b.x) * (a.y + b.y)
        }
        let nl = simd_length(nrm)
        guard nl > 1e-12 else { return nil }
        nrm /= nl
        // Tekislik bazisi
        var u = simd_cross(nrm, SIMD3<Float>(0, 1, 0))
        if simd_length(u) < 1e-6 { u = simd_cross(nrm, SIMD3<Float>(1, 0, 0)) }
        u = simd_normalize(u)
        let v = simd_cross(nrm, u)
        let c = poly3.reduce(SIMD3<Float>(0,0,0), +) / Float(n)
        var pts2 = poly3.map { p -> SIMD2<Float> in let d = p - c; return SIMD2(simd_dot(d, u), simd_dot(d, v)) }

        // Ko'pburchak yo'nalishi (imzolangan yuza) — CCW ga keltiramiz
        var area: Float = 0
        for i in 0..<n { let a = pts2[i], b = pts2[(i+1) % n]; area += a.x * b.y - b.x * a.y }
        var order = Array(0..<n)
        if area < 0 { order.reverse(); pts2.reverse() }

        func cross2(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func inside(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ cc: SIMD2<Float>) -> Bool {
            let d1 = cross2(p, a, b), d2 = cross2(p, b, cc), d3 = cross2(p, cc, a)
            let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
            let hasPos = d1 > 0 || d2 > 0 || d3 > 0
            return !(hasNeg && hasPos)
        }

        var remaining = Array(0..<pts2.count)   // pts2/order ichidagi indekslar
        var out = [(Int, Int, Int)]()
        var guardCount = 0
        while remaining.count > 3 && guardCount < pts2.count * pts2.count {
            guardCount += 1
            var clipped = false
            let m = remaining.count
            for i in 0..<m {
                let ip = remaining[(i + m - 1) % m], ic = remaining[i], inx = remaining[(i + 1) % m]
                let a = pts2[ip], b = pts2[ic], cc = pts2[inx]
                if cross2(a, b, cc) <= 0 { continue }   // qavariq emas
                var ear = true
                for r in remaining where r != ip && r != ic && r != inx {
                    if inside(pts2[r], a, b, cc) { ear = false; break }
                }
                if !ear { continue }
                out.append((order[ip], order[ic], order[inx]))
                remaining.remove(at: i)
                clipped = true
                break
            }
            if !clipped { break }   // degenerat — chiqamiz
        }
        if remaining.count == 3 {
            out.append((order[remaining[0]], order[remaining[1]], order[remaining[2]]))
        }
        return out.isEmpty ? nil : out
    }
}
