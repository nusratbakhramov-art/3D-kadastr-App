import Foundation
import simd

/// Xona KONVERTIDAN (envelope) TASHQARIDAGI floating mesh (devor/pol/shift chetlaridan
/// bo'sh fazoga cho'zilgan ingichka tendril/flap) ni KESADI. Xona ichi butunlay saqlanadi.
///
/// Usul (deep-research 2026-07-13 tavsiyasi — footprint/envelope clip): pol/shift Y ni top →
/// pol∪shift XZ-occupancy = xona FOOTPRINT'i (interior) → teshiklar yopiladi (close) →
/// margin bilan kengaytiriladi → FAQAT footprint ICHIDAGI (XZ) VA [floorY-m, ceilY+m] Y
/// oralig'idagi yuzlar QOLADI; tashqarisi (tendril) KESILADI.
///
/// "Kameralar doim xona ichida" priori bilan mos: pol = interior; tendril pol'dan tashqarida.
enum MeshEnvelopeClip {

    static func clip(_ mesh: WeldedMesh,
                     cell: Float = 0.05,
                     xzMargin: Float = 0.25,
                     yMargin: Float = 0.30,
                     minFootprintArea: Float = 1.0) -> WeldedMesh {
        let V = mesh.positions, idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 500, V.count > 100 else { return mesh }

        // Yuz normal.y + markaz
        var fNy = [Float](repeating: 0, count: faceCount)
        var fC  = [SIMD3<Float>](repeating: .zero, count: faceCount)
        var horizArea: Float = 0
        for f in 0..<faceCount {
            let a = V[Int(idx[f*3])], b = V[Int(idx[f*3+1])], c = V[Int(idx[f*3+2])]
            let cr = simd_cross(b - a, c - a); let l = simd_length(cr)
            fNy[f] = l > 1e-9 ? cr.y / l : 0
            fC[f]  = (a + b + c) / 3
            if abs(fNy[f]) > 0.9 { horizArea += 0.5 * l }
        }
        guard horizArea > minFootprintArea else { return mesh }   // gorizontal sirt yetarli emas — xavfsiz chiqish

        // pol/shift Y (gorizontal yuz markazlari min/max klaster, area yo'q — soddaroq: min/max)
        var minYh: Float = 1e9, maxYh: Float = -1e9
        for f in 0..<faceCount where abs(fNy[f]) > 0.9 { minYh = min(minYh, fC[f].y); maxYh = max(maxYh, fC[f].y) }
        guard maxYh > minYh + 0.5 else { return mesh }
        func planeY(_ low: Bool) -> Float {
            var acc: Float = 0, n = 0
            for f in 0..<faceCount where abs(fNy[f]) > 0.9 {
                let cy = fC[f].y
                if (low ? cy < minYh + 0.20 : cy > maxYh - 0.20) { acc += cy; n += 1 }
            }
            return n > 0 ? acc / Float(n) : (low ? minYh : maxYh)
        }
        let floorY = planeY(true), ceilY = planeY(false)

        // XZ grid
        var minX: Float = 1e9, maxX: Float = -1e9, minZ: Float = 1e9, maxZ: Float = -1e9
        for p in V { minX = min(minX, p.x); maxX = max(maxX, p.x); minZ = min(minZ, p.z); maxZ = max(maxZ, p.z) }
        let pad = xzMargin + 4 * cell
        minX -= pad; minZ -= pad; maxX += pad; maxZ += pad
        let W = max(1, Int((maxX - minX) / cell) + 1)
        let H = max(1, Int((maxZ - minZ) / cell) + 1)
        guard W * H < 6_000_000 else { return mesh }
        @inline(__always) func gi(_ x: Float) -> Int { min(W-1, max(0, Int((x - minX) / cell))) }
        @inline(__always) func gj(_ z: Float) -> Int { min(H-1, max(0, Int((z - minZ) / cell))) }

        // FOOTPRINT = pol∪shift XZ-occupancy (gorizontal yuzlarni rasterizatsiya)
        var occ = [Bool](repeating: false, count: W * H)
        for f in 0..<faceCount where abs(fNy[f]) > 0.9 {
            let a = V[Int(idx[f*3])], b = V[Int(idx[f*3+1])], c = V[Int(idx[f*3+2])]
            let cy = fC[f].y
            // faqat pol yoki shift darajasidagi gorizontal (mebel usti emas — lekin ular ham interior, mayli)
            if abs(cy - floorY) > 0.15 && abs(cy - ceilY) > 0.15 && (cy < floorY || cy > ceilY) { continue }
            rasterTri(a, b, c, minX, minZ, cell, W, H, gi, gj) { occ[$1 * W + $0] = true }
        }

        // CLOSE (teshik yop) → OPEN (INGICHKA tendril/protruziyani OLIB TASHLA — asosiy xona
        // katta, saqlanadi; tendril ingichka, yo'qoladi) → MARGIN DILATE (devor saqlansin).
        occ = dilate(occ, W, H, 3); occ = erode(occ, W, H, 3)          // close: teshik yop
        let Ropen = 7
        occ = erode(occ, W, H, Ropen); occ = dilate(occ, W, H, Ropen)  // open: ingichka tendril ket
        let Rmargin = max(1, Int((xzMargin / cell).rounded()))
        let mask = dilate(occ, W, H, Rmargin)     // xona interior + margin (devor)

        // KESISH: markaz XZ mask ichidа VA Y ∈ [floorY-m, ceilY+m] bo'lsa qoldir
        let yLo = floorY - yMargin, yHi = ceilY + yMargin
        var keep = [Bool](repeating: true, count: faceCount)
        var cut = 0
        for f in 0..<faceCount {
            let c = fC[f]
            if c.y < yLo || c.y > yHi { keep[f] = false; cut += 1; continue }
            if !mask[gj(c.z) * W + gi(c.x)] { keep[f] = false; cut += 1 }
        }
        // XAVFSIZLIK: agar juda ko'p (>35%) kesilsa — footprint noto'g'ri → o'zgartirMA.
        if cut == 0 || cut > faceCount * 35 / 100 {
            NSLog("MeshEnvelopeClip: floorY=%.2f ceilY=%.2f, %d/%d — SKIP", floorY, ceilY, cut, faceCount)
            return mesh
        }

        // Clip qolgan MAYDA AJRALGAN fragmentlarни (tendril qoldiqlari) o'chir — teksturalash
        // ularni ko'p patch qilib xotira portlatmasin + toza natija.
        keep = removeSmallComponents(idx, keep, minFaces: 40)
        cut = keep.filter { !$0 }.count
        NSLog("MeshEnvelopeClip: floorY=%.2f ceilY=%.2f, %d/%d yuz kesildi (+fragment)", floorY, ceilY, cut, faceCount)

        // Yangi mesh (ishlatilgan vertekslarni ixchamlash)
        var remap = [Int32](repeating: -1, count: V.count)
        var newPos = [SIMD3<Float>](); var newIdx = [UInt32]()
        for f in 0..<faceCount where keep[f] {
            for k in 0..<3 {
                let vi = Int(idx[f*3+k])
                if remap[vi] < 0 { remap[vi] = Int32(newPos.count); newPos.append(V[vi]) }
                newIdx.append(UInt32(remap[vi]))
            }
        }
        return WeldedMesh(positions: newPos, normals: [], indices: newIdx)
    }

    /// Ulangan komponentlarni top (umumiy qirra), minFaces'dan kichiklarni keep=false qil.
    private static func removeSmallComponents(_ idx: [UInt32], _ keep0: [Bool], minFaces: Int) -> [Bool] {
        let fc = idx.count / 3
        var keep = keep0
        func ekey(_ a: UInt32, _ b: UInt32) -> UInt64 { let lo = min(a,b), hi = max(a,b); return (UInt64(lo) << 32) | UInt64(hi) }
        var edgeFaces = [UInt64: [Int]](minimumCapacity: fc)
        for f in 0..<fc where keep[f] {
            let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
            edgeFaces[ekey(a,b), default: []].append(f)
            edgeFaces[ekey(b,c), default: []].append(f)
            edgeFaces[ekey(c,a), default: []].append(f)
        }
        var parent = Array(0..<fc)
        func find(_ x: Int) -> Int { var r = x; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        func union(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[ra] = rb } }
        for (_, fs) in edgeFaces where fs.count >= 2 { for i in 1..<fs.count { union(fs[0], fs[i]) } }
        var size = [Int: Int]()
        for f in 0..<fc where keep[f] { size[find(f), default: 0] += 1 }
        for f in 0..<fc where keep[f] { if (size[find(f)] ?? 0) < minFaces { keep[f] = false } }
        return keep
    }

    private static func dilate(_ g: [Bool], _ W: Int, _ H: Int, _ R: Int) -> [Bool] {
        var o = [Bool](repeating: false, count: W * H)
        for z in 0..<H { for x in 0..<W {
            if !g[z*W+x] { continue }
            let x0 = max(0,x-R), x1 = min(W-1,x+R), z0 = max(0,z-R), z1 = min(H-1,z+R)
            for zz in z0...z1 { for xx in x0...x1 { o[zz*W+xx] = true } }
        } }
        return o
    }
    private static func erode(_ g: [Bool], _ W: Int, _ H: Int, _ R: Int) -> [Bool] {
        var o = [Bool](repeating: false, count: W * H)
        for z in 0..<H { for x in 0..<W {
            if x < R || x >= W-R || z < R || z >= H-R { continue }
            var all = true
            outer: for zz in (z-R)...(z+R) { for xx in (x-R)...(x+R) { if !g[zz*W+xx] { all = false; break outer } } }
            o[z*W+x] = all
        } }
        return o
    }

    @inline(__always)
    private static func rasterTri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                                  _ minX: Float, _ minZ: Float, _ cell: Float, _ W: Int, _ H: Int,
                                  _ gi: (Float) -> Int, _ gj: (Float) -> Int, _ mark: (Int, Int) -> Void) {
        let i0 = gi(min(a.x, min(b.x, c.x))), i1 = gi(max(a.x, max(b.x, c.x)))
        let j0 = gj(min(a.z, min(b.z, c.z))), j1 = gj(max(a.z, max(b.z, c.z)))
        let d = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
        if abs(d) < 1e-12 { for j in j0...j1 { for i in i0...i1 { mark(i, j) } }; return }
        for j in j0...j1 {
            let pz = minZ + (Float(j) + 0.5) * cell
            for i in i0...i1 {
                let px = minX + (Float(i) + 0.5) * cell
                let l1 = ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / d
                let l2 = ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / d
                let l3 = 1 - l1 - l2
                if l1 >= -0.02 && l2 >= -0.02 && l3 >= -0.02 { mark(i, j) }
            }
        }
    }
}
