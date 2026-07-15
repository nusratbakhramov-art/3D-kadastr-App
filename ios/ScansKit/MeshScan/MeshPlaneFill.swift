import Foundation
import simd

/// POL va SHIFT teshiklarini (yaltiroq plitka LiDAR bo'shligi, shift chiroq/beam oralig'i)
/// OCCUPANCY-GRID usuli bilan yopadi — chegara-halqasiga TAYANMAYDI (haqiqiy pol/shift
/// teshiklari 3D'da ilon-izi halqa bilan o'ralgan, ear-clip ularni yopolmaydi).
///
/// Usul: pol/shift tekisligini top → XZ occupancy grid'ga rasterizatsiya → chekkadan
/// flood-fill → FAQAT O'RALGAN (enclosed) bo'sh kataklarni tekis to'ldir. Devor kataklari
/// TO'SIQ bo'ladi (devor tagidagi teshik ham yopiladi). Skanlanmagan ochiq soha va eshik
/// tashqariga ulanadi → flood-fill yetadi → OCHIQ qoladi (qora "o'ylab topilgan" sirt yo'q).
///
/// Tekis to'ldiruv homografiya bilan mukammal teksturalanadi (RGB kadr polni/shiftni ko'rgan).
enum MeshPlaneFill {

    static func fill(_ mesh: WeldedMesh,
                     cell: Float = 0.05,
                     planeTol: Float = 0.08,
                     minPlaneArea: Float = 1.5,
                     wallCloseR: Int = 8) -> WeldedMesh {
        let V = mesh.positions, idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 500, V.count > 100 else { return mesh }

        // Yuz normal + markaz + yuza
        var fNy = [Float](repeating: 0, count: faceCount)   // normal.y
        var fCy = [Float](repeating: 0, count: faceCount)   // centroid.y
        var fA  = [Float](repeating: 0, count: faceCount)
        for f in 0..<faceCount {
            let a = V[Int(idx[f*3])], b = V[Int(idx[f*3+1])], c = V[Int(idx[f*3+2])]
            let cr = simd_cross(b - a, c - a)
            let l = simd_length(cr)
            fA[f] = 0.5 * l
            fNy[f] = l > 1e-9 ? cr.y / l : 0
            fCy[f] = (a.y + b.y + c.y) / 3
        }

        // Gorizontal yuzlar → pol/shift Y ni area-vaznli top
        var minYh: Float = 1e9, maxYh: Float = -1e9
        for f in 0..<faceCount where abs(fNy[f]) > 0.9 && fA[f] > 1e-5 {
            minYh = min(minYh, fCy[f]); maxYh = max(maxYh, fCy[f])
        }
        guard maxYh > minYh else { return mesh }

        func planeY(nearLow: Bool) -> (y: Float, area: Float) {
            var accY: Float = 0, accA: Float = 0
            for f in 0..<faceCount where abs(fNy[f]) > 0.9 {
                let cy = fCy[f]
                let ok = nearLow ? (cy < minYh + 0.20) : (cy > maxYh - 0.20)
                if ok { accY += cy * fA[f]; accA += fA[f] }
            }
            return (accA > 1e-6 ? accY / accA : 0, accA)
        }
        let floorP = planeY(nearLow: true)
        let ceilP  = planeY(nearLow: false)

        // XZ chegara (barcha vertekslardan)
        var minX: Float = 1e9, maxX: Float = -1e9, minZ: Float = 1e9, maxZ: Float = -1e9
        for p in V { minX = min(minX, p.x); maxX = max(maxX, p.x); minZ = min(minZ, p.z); maxZ = max(maxZ, p.z) }
        let W = max(1, Int((maxX - minX) / cell) + 2)
        let H = max(1, Int((maxZ - minZ) / cell) + 2)
        guard W * H < 4_000_000 else { return mesh }

        @inline(__always) func gi(_ x: Float) -> Int { min(W - 1, max(0, Int((x - minX) / cell))) }
        @inline(__always) func gj(_ z: Float) -> Int { min(H - 1, max(0, Int((z - minZ) / cell))) }

        // Devor (vertikal) yuzlarini XZ'ga rasterizatsiya → TO'SIQ
        var wall = [Bool](repeating: false, count: W * H)
        for f in 0..<faceCount where abs(fNy[f]) < 0.35 {
            rasterTri(V[Int(idx[f*3])], V[Int(idx[f*3+1])], V[Int(idx[f*3+2])], minX, minZ, cell, W, H, gi, gj) { wall[$1 * W + $0] = true }
        }

        // DEVOR HALQASI TIRQISHLARINI YOPAMIZ (close = dilate→erode, ≤2*Rw katak).
        // Skanlanmagan devor bo'lagi / tor eshik tirqishidan tashqi bo'shliq pol/shift
        // ichiga "sizib" kirsa — katta skanlanmagan pol teshigi OCHIQ (qora) qolardi.
        // Yopilgan halqa → flood-fill faqat CHINAKAM tashqarига yetadi → ichki pol to'liq
        // to'ladi. Erode'da chegaradan tashqari "TO'SIQ bor" deb qaraladi (chekka devor
        // yo'qolmasin). Bu FAQAT reach-to'sig'i uchun; haqiqiy `wall` skip'i o'zgarmaydi.
        var wallClosed = wall
        if wallCloseR > 0 {
            let r = wallCloseR
            var dil = [Bool](repeating: false, count: W * H)
            for z in 0..<H { for x in 0..<W {
                if !wall[z * W + x] { continue }
                let x0 = max(0, x - r), x1 = min(W - 1, x + r), z0 = max(0, z - r), z1 = min(H - 1, z + r)
                for zz in z0...z1 { for xx in x0...x1 { dil[zz * W + xx] = true } }
            } }
            var ero = [Bool](repeating: false, count: W * H)
            for z in 0..<H { for x in 0..<W {
                var all = true
                outer: for dz in -r...r { for dx in -r...r {
                    let zz = z + dz, xx = x + dx
                    if zz < 0 || zz >= H || xx < 0 || xx >= W { continue }  // OOB = to'siq bor
                    if !dil[zz * W + xx] { all = false; break outer }
                } }
                ero[z * W + x] = all
            } }
            wallClosed = ero
        }

        var newPos = mesh.positions
        var newIdx = mesh.indices
        var midCache = [Int: UInt32](minimumCapacity: 4096)
        var addedCells = 0

        // Bitta tekislik uchun: occ grid → flood-fill → o'ralgan teshiklarni to'ldir
        func fillPlane(y: Float, isFloor: Bool, area: Float) {
            guard area >= minPlaneArea else { return }
            var occ = [Bool](repeating: false, count: W * H)
            for f in 0..<faceCount where abs(fNy[f]) > 0.9 && abs(fCy[f] - y) < planeTol {
                rasterTri(V[Int(idx[f*3])], V[Int(idx[f*3+1])], V[Int(idx[f*3+2])], minX, minZ, cell, W, H, gi, gj) { occ[$1 * W + $0] = true }
            }
            // barrier = occ OR wallClosed (tirqishlar yopilgan → tashqi sizish yo'q)
            var barrier = occ
            for i in 0..<barrier.count where wallClosed[i] { barrier[i] = true }
            // flood fill chekkadan (!barrier)
            var reach = [Bool](repeating: false, count: W * H)
            var stack = [Int]()
            for x in 0..<W { for z in [0, H - 1] { let k = z * W + x; if !barrier[k] && !reach[k] { reach[k] = true; stack.append(k) } } }
            for z in 0..<H { for x in [0, W - 1] { let k = z * W + x; if !barrier[k] && !reach[k] { reach[k] = true; stack.append(k) } } }
            while let k = stack.popLast() {
                let x = k % W, z = k / W
                if x > 0 { let n = k - 1; if !barrier[n] && !reach[n] { reach[n] = true; stack.append(n) } }
                if x < W - 1 { let n = k + 1; if !barrier[n] && !reach[n] { reach[n] = true; stack.append(n) } }
                if z > 0 { let n = k - W; if !barrier[n] && !reach[n] { reach[n] = true; stack.append(n) } }
                if z < H - 1 { let n = k + W; if !barrier[n] && !reach[n] { reach[n] = true; stack.append(n) } }
            }
            // MORFOLOGIK YOPISH (closing) — ingichka bo'shliqni (shift pog'onasi riser'i,
            // tor dropout ≤~20 sm) yopadi; keng eshik (~80 sm) yopilMAYdi. dilate→erode.
            let R = 2
            func dilate(_ g: [Bool]) -> [Bool] {
                var o = [Bool](repeating: false, count: W * H)
                for z in 0..<H { for x in 0..<W {
                    if !g[z * W + x] { continue }
                    let x0 = max(0, x - R), x1 = min(W - 1, x + R), z0 = max(0, z - R), z1 = min(H - 1, z + R)
                    for zz in z0...z1 { for xx in x0...x1 { o[zz * W + xx] = true } }
                } }
                return o
            }
            func erode(_ g: [Bool]) -> [Bool] {
                var o = [Bool](repeating: false, count: W * H)
                for z in 0..<H { for x in 0..<W {
                    if x < R || x >= W - R || z < R || z >= H - R { continue }
                    var all = true
                    outer: for zz in (z - R)...(z + R) { for xx in (x - R)...(x + R) { if !g[zz * W + xx] { all = false; break outer } } }
                    o[z * W + x] = all
                } }
                return o
            }
            let closed = erode(dilate(occ))   // occ + ingichka bo'shliqlar
            // hole = O'RALGAN (chekkaga ulanmagan) VA polda/shiftda sirt YO'Q
            @inline(__always) func corner(_ ci: Int, _ cj: Int) -> UInt32 {
                let key = cj * (W + 1) + ci
                if let v = midCache[key] { return v }
                let vx = minX + Float(ci) * cell
                let vz = minZ + Float(cj) * cell
                let vid = UInt32(newPos.count)
                newPos.append(SIMD3<Float>(vx, y, vz))
                midCache[key] = vid
                return vid
            }
            for z in 0..<H { for x in 0..<W {
                let k = z * W + x
                if occ[k] || wall[k] { continue }               // sirt bor / devor chizig'i — tegma
                // to'ldir: O'RALGAN (chekkaga ulanmagan) YOKI ingichka bo'shliq (closing bilan)
                if reach[k] && !closed[k] { continue }
                addedCells += 1
                let a = corner(x, z), b = corner(x + 1, z), c = corner(x + 1, z + 1), d = corner(x, z + 1)
                if isFloor {
                    // normal +Y (xonaga qaragan pol)
                    newIdx.append(a); newIdx.append(d); newIdx.append(c)
                    newIdx.append(a); newIdx.append(c); newIdx.append(b)
                } else {
                    // normal -Y (pastga qaragan shift)
                    newIdx.append(a); newIdx.append(c); newIdx.append(d)
                    newIdx.append(a); newIdx.append(b); newIdx.append(c)
                }
            } }
            midCache.removeAll(keepingCapacity: true)
        }

        fillPlane(y: floorP.y, isFloor: true, area: floorP.area)
        fillPlane(y: ceilP.y, isFloor: false, area: ceilP.area)

        NSLog("MeshPlaneFill: pol y=%.2f (A=%.1f), shift y=%.2f (A=%.1f), %d katak to'ldirildi",
              floorP.y, floorP.area, ceilP.y, ceilP.area, addedCells)
        if addedCells == 0 { return mesh }
        return WeldedMesh(positions: newPos, normals: [], indices: newIdx)
    }

    /// Uchburchakni (XZ proyeksiya) grid kataklariga rasterizatsiya (katak-markaz testi).
    @inline(__always)
    private static func rasterTri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                                  _ minX: Float, _ minZ: Float, _ cell: Float, _ W: Int, _ H: Int,
                                  _ gi: (Float) -> Int, _ gj: (Float) -> Int,
                                  _ mark: (Int, Int) -> Void) {
        let ax = a.x, az = a.z, bx = b.x, bz = b.z, cx = c.x, cz = c.z
        let i0 = gi(min(ax, min(bx, cx))), i1 = gi(max(ax, max(bx, cx)))
        let j0 = gj(min(az, min(bz, cz))), j1 = gj(max(az, max(bz, cz)))
        let d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
        if abs(d) < 1e-12 {
            // degenerat (ingichka devor chizig'i) — bbox kataklarini belgila
            for j in j0...j1 { for i in i0...i1 { mark(i, j) } }
            return
        }
        for j in j0...j1 {
            let pz = minZ + (Float(j) + 0.5) * cell
            for i in i0...i1 {
                let px = minX + (Float(i) + 0.5) * cell
                let l1 = ((bz - cz) * (px - cx) + (cx - bx) * (pz - cz)) / d
                let l2 = ((cz - az) * (px - cx) + (ax - cx) * (pz - cz)) / d
                let l3 = 1 - l1 - l2
                if l1 >= -0.02 && l2 >= -0.02 && l3 >= -0.02 { mark(i, j) }
            }
        }
    }
}
