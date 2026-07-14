import Foundation
import simd

/// TSDF geometriya (Polycam uslubi) — texrecon uchun Poisson O'RNIGA.
///
/// Poisson yopiq (watertight) yuza quradi va ko'rilmagan hududlarda "parda"
/// to'qiydi — keyin uni FreeSpaceCarver bilan kesishga majbur bo'lamiz.
/// TSDF esa bo'sh fazoni integratsiya PAYTIDA o'yadi (har depth o'qishi kamera
/// va yuza orasini "bo'sh" deb belgilaydi) — parda UMUMAN paydo bo'lmaydi.
/// Ko'rilmagan joylar teshik bo'lib qoladi; mayda teshiklar lokal to'ldiriladi
/// (smallHoleFill), kattalari ochiq qoladi (halol: ko'rilmagan = yo'q).
///
/// FusionEngine'dan farqi: faqat geometriya (rang yo'q), mayda voxel (1.5sm dan),
/// VAZNLI integratsiya (conf × 1/z²) va ICP bilan aniqlashgan pozalar.
enum TSDFGeometry {

    // MARK: - Sozlamalar

    /// Boshlang'ich voxel (m) — 12mm: zinapoya kichikroq, qirralar roundroq.
    private static let voxelStart: Float = 0.012
    /// Xotira qopqog'i (Float tsdf + Float wsum = 8B/voxel → 20M ≈ 160MB).
    private static let maxVoxels = 20_000_000
    /// TSDF uchun kadrlar soni (tekis stride) — qamrov/vaqt muvozanati.
    private static let maxFrames = 240
    /// Zich keshdan olinadigan maksimal kadr (13× ko'p kuzatuv, ~18-25s integratsiya).
    private static let maxDenseFrames = 600
    /// Depth ishonch oralig'i (m).
    private static let minZ: Float = 0.15
    private static let maxZ: Float = 4.0
    /// Og'irlik qopqog'i (running average to'yinishi).
    private static let weightCap: Float = 100
    /// Mayda orol chegarasi (cho'qqi).
    private static let minComponentVerts = 150
    /// Teshik perimetri chegarasi (m) — bundan kattasi halol ochiq qoladi.
    /// 4m: yirik ko'rilmagan zonalar (stol osti) ham MEMBRANA bilan yopiladi
    /// — chegarasi halqaga mahkamlangan silliq parda, havoga chiqa olmaydi;
    /// rangini FillColorizer yumshoq gradienti beradi. Eshik odatda yopiq
    /// halqa emas — unga tegilmaydi.
    static let holePerimeterMax: Float = 4.0
    private static let holeMaxEdges = 400
    /// Yuza chiqarish uchun minimal voxel vazni. 0.45: yaqin masofadagi yakka
    /// BARQAROR o'qish o'tadi (qora monitor yuzasi saqlanadi, vazni ~0.5-1.0),
    /// uzoq/sirpanma yakka miltillash (vazni ~0.15-0.3) esa filtrlanadi —
    /// oq "konfetti" qobiqlar chiqmaydi (5.2.0-e'da isbotlangan qiymat).
    private static let extractMinWeight: Float = 0.45

    // MARK: - Diskdan qurish (app yo'li)

    /// TSDF mesh: ZICH kesh (dense_poses.json + dense/*.bin, ICP'dan keyin)
    /// birinchi tanlov — 10-20× ko'p kuzatuv, shovqin cho'kadi, teshik kam.
    /// Zich kesh yo'q bo'lsa (eski skan) — keyframe depth (frames.json) zaxira.
    /// Kamida 10 depth kadr kerak, aks holda nil (Poisson yo'liga).
    static func build(paths: ScanPaths, log: ((String) -> Void)? = nil) -> LiDARMeshData? {
        let dense = DenseDepthStore.loadFrames(posesJSON: paths.densePosesJSON,
                                               folder: paths.denseFolder,
                                               maxFrames: maxDenseFrames)
        if dense.count >= 50 {
            log?("TSDF manba=DENSE kadrlar=\(dense.count)")
            return integrate(frames: dense, log: log)
        }
        let frames = FreeSpaceCarver.loadFrames(framesJSON: paths.framesJSON,
                                                depthFolder: paths.depthFolder,
                                                maxFrames: maxFrames)
        guard frames.count >= 10 else {
            log?("TSDF skip: depth kadrlari yetarli emas (\(frames.count))")
            return nil
        }
        log?("TSDF manba=keyframe kadrlar=\(frames.count)")
        return integrate(frames: frames, log: log)
    }

    // MARK: - Sof yadro (macOS'da test qilinadi)

    static func integrate(frames: [FreeSpaceCarver.DepthFrame],
                          log: ((String) -> Void)? = nil) -> LiDARMeshData? {
        // ===== 1. Chegara (depth namunalaridan) =====
        var mins = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxs = -mins
        for f in stride(from: 0, to: frames.count, by: max(1, frames.count / 20)).map({ frames[$0] }) {
            for v in stride(from: 0, to: f.dh, by: 8) {
                for u in stride(from: 0, to: f.dw, by: 8) {
                    let i = v * f.dw + u
                    let mm = f.depthMM[i]
                    guard mm > 0 else { continue }
                    if let c = f.conf, c[i] < 1 { continue }
                    let z = Float(mm) / 1000
                    guard z > minZ, z < maxZ else { continue }
                    let X = (Float(u) - f.cx) / f.fx * z
                    let Y = (Float(v) - f.cy) / f.fy * z
                    let world = f.R * SIMD3(X, -Y, -z) + f.t
                    mins = simd_min(mins, world)
                    maxs = simd_max(maxs, world)
                }
            }
        }
        guard mins.x < maxs.x else { return nil }
        mins -= SIMD3(repeating: 0.12)
        maxs += SIMD3(repeating: 0.12)
        // Yakka buzuq o'qish hajmni portlatmasin.
        maxs = simd_min(maxs, mins + SIMD3(repeating: 12))

        // ===== 2. Voxel o'lchami (xotira qopqog'i ostida eng mayda) =====
        var vox = voxelStart
        var dims = SIMD3<Int>(0, 0, 0)
        while true {
            dims = SIMD3(Int(ceil((maxs.x - mins.x) / vox)),
                         Int(ceil((maxs.y - mins.y) / vox)),
                         Int(ceil((maxs.z - mins.z) / vox)))
            if dims.x * dims.y * dims.z <= maxVoxels { break }
            vox *= 1.15
        }
        let total = dims.x * dims.y * dims.z
        let trunc: Float = max(0.045, vox * 3)
        log?("TSDF vox=\(String(format: "%.0f", vox * 1000))mm dims=\(dims.x)x\(dims.y)x\(dims.z) frames=\(frames.count)")

        // ===== 3. VAZNLI integratsiya (kadr ichida slab-parallel) =====
        var tsdf = [Float](repeating: 1, count: total)
        var wsum = [Float](repeating: 0, count: total)

        tsdf.withUnsafeMutableBufferPointer { tPtr in
            wsum.withUnsafeMutableBufferPointer { wPtr in
                for f in frames {
                    let RT = f.R.transpose
                    let colX = RT * SIMD3<Float>(vox, 0, 0)
                    let colY = RT * SIMD3<Float>(0, vox, 0)
                    let colZ = RT * SIMD3<Float>(0, 0, vox)
                    let base0 = RT * (mins + SIMD3(repeating: vox / 2) - f.t)
                    let ny = dims.y, nz = dims.z

                    f.depthMM.withUnsafeBufferPointer { dPtr in
                        // i-slablar bir-biriga yozmaydi — parallel xavfsiz.
                        DispatchQueue.concurrentPerform(iterations: dims.x) { i in
                            let lcI = base0 + colX * Float(i)
                            var idx = i * ny * nz
                            for j in 0..<ny {
                                let lcJ = lcI + colY * Float(j)
                                for k in 0..<nz {
                                    let lc = lcJ + colZ * Float(k)
                                    let cellIdx = idx
                                    idx += 1
                                    let zc = -lc.z
                                    if zc <= minZ { continue }
                                    let u = lc.x / zc * f.fx + f.cx
                                    let v = -lc.y / zc * f.fy + f.cy
                                    if u < 0 || v < 0 { continue }
                                    let iu = Int(u), iv = Int(v)
                                    if iu >= f.dw || iv >= f.dh { continue }
                                    let di = iv * f.dw + iu
                                    let mm = dPtr[di]
                                    if mm == 0 { continue }
                                    // Vazn: confidence × masofa (uzoq o'qish shovqinli).
                                    var w: Float = 1
                                    if let c = f.conf {
                                        let cv = c[di]
                                        if cv == 0 { continue }
                                        w = cv >= 2 ? 1 : 0.5
                                    }
                                    let d = Float(mm) / 1000
                                    if d <= minZ || d >= maxZ { continue }
                                    let sdf = d - zc
                                    if sdf <= -trunc { continue }
                                    w *= min(1, 2.25 / (zc * zc))   // 1.5m gacha to'liq vazn
                                    let s = min(max(sdf / trunc, -1), 1)
                                    let wOld = wPtr[cellIdx]
                                    tPtr[cellIdx] = (tPtr[cellIdx] * wOld + s * w) / (wOld + w)
                                    wPtr[cellIdx] = min(wOld + w, weightCap)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===== 4. Yuza + orientatsiya + silliqlash =====
        // weights=wsum: yuza faqat IKKALA vokseli ISHONCHLI kuzatilgan
        // (w>extractMinWeight) qirralarda — devor ortidagi soxta "orqa qobiq",
        // kuzatuv chegarasidagi "parda" va yakka-o'qish "konfetti" qobiqlari
        // chiqmaydi (Open3D valid-voxel extraction uslubi + vazn chegarasi).
        var mesh = SurfaceNets.extract(tsdf: tsdf, dims: dims, mins: mins, vox: vox,
                                       weights: wsum, minWeight: extractMinWeight)
        tsdf = []; wsum = []
        guard !mesh.positions.isEmpty, !mesh.faces.isEmpty else { return nil }

        // Global orientatsiya: kameralar (xona ichi) tomon.
        var camCentroid = SIMD3<Float>.zero
        for f in frames { camCentroid += f.t }
        camCentroid /= Float(frames.count)
        let normals = vertexNormals(positions: mesh.positions, faces: mesh.faces)
        var dotSum: Float = 0
        let nV = mesh.positions.count
        for i in stride(from: 0, to: nV, by: max(1, nV / 5000)) {
            dotSum += simd_dot(normals[i], camCentroid - mesh.positions[i])
        }
        if dotSum < 0 {
            var fi = 0
            while fi < mesh.faces.count { mesh.faces.swapAt(fi + 1, fi + 2); fi += 3 }
        }

        // Taubin silliqlash (λ|μ juftligi, 6 juft) — voxel zinapoyasi va
        // qirraliknи avvalgi 2×Laplacian'dan kuchliroq yumshatadi, lekin
        // hajmni saqlaydi (sof Laplacian ko'p iteratsiyada meshni toraytirib
        // o'lchamlarni buzardi). Tekis devorlarga ta'siri yo'q — qo'shnilar
        // o'rtachasi baribir tekislikda yotadi.
        let taubin: [Float] = [0.5, -0.53]
        for pass in 0..<12 {
            let lam = taubin[pass % 2]
            var acc = [SIMD3<Float>](repeating: .zero, count: nV)
            var cnt = [Float](repeating: 0, count: nV)
            var fi = 0
            while fi < mesh.faces.count {
                let a = Int(mesh.faces[fi]), b = Int(mesh.faces[fi + 1]), c = Int(mesh.faces[fi + 2])
                acc[a] += mesh.positions[b] + mesh.positions[c]; cnt[a] += 2
                acc[b] += mesh.positions[a] + mesh.positions[c]; cnt[b] += 2
                acc[c] += mesh.positions[a] + mesh.positions[b]; cnt[c] += 2
                fi += 3
            }
            for i in 0..<nV where cnt[i] > 0 {
                mesh.positions[i] += (acc[i] / cnt[i] - mesh.positions[i]) * lam
            }
        }

        // ===== 5. Mayda orollar + zichlashtirish =====
        let kept = FreeSpaceCarver.removeSmallComponents(indices: mesh.faces, vertexCount: nV,
                                                         minVerts: minComponentVerts, log: log)
        var flatPos = [Float](); flatPos.reserveCapacity(nV * 3)
        for p in mesh.positions { flatPos.append(p.x); flatPos.append(p.y); flatPos.append(p.z) }
        let compacted = compact(positions: flatPos, indices: kept)
        guard !compacted.isEmpty else { return nil }
        log?("TSDF mesh verts=\(compacted.vertexCount) tris=\(compacted.indices.count / 3)")
        return compacted
    }

    // MARK: - Membrana (halqa ustiga silliq parda)

    /// Halqa ustiga membrana: centroid-fan → subdivide (qirra ~6sm gacha) →
    /// Laplacian relax (chegara MAHKAM, faqat ichki nuqtalar silliqlanadi).
    /// Natija — yumshoq egri parda: "chodir" uchi ham, g'ijim ham yo'q.
    /// Chegarasi halqaning o'zi bo'lgani uchun yamoq havoga chiqa olmaydi.
    private static func buildMembrane(ring: [SIMD3<Float>]) -> (verts: [SIMD3<Float>], tris: [UInt32]) {
        let n = ring.count
        var verts = ring
        var isBoundary = [Bool](repeating: true, count: n)
        var centroid = SIMD3<Float>.zero
        for p in ring { centroid += p }
        centroid /= Float(n)
        verts.append(centroid)
        isBoundary.append(false)

        var tris: [UInt32] = []
        tris.reserveCapacity(n * 3)
        let ci = UInt32(n)
        for i in 0..<n {
            tris.append(UInt32(i)); tris.append(UInt32((i + 1) % n)); tris.append(ci)
        }

        // Subdivide darajasi: parda qirrasi ~6sm bo'lguncha (maks 2).
        var perim: Float = 0
        for i in 0..<n { perim += simd_distance(ring[i], ring[(i + 1) % n]) }
        var levels = 0
        if perim > 1.2 { levels = 2 } else if perim > 0.5 { levels = 1 }

        // Chegara qirralari — bo'linganda o'rta nuqta ham chegara bo'lib qoladi
        // (aks holda relax chegarani halqadan ajratib yuboradi).
        var boundaryEdges = Set<UInt64>()
        @inline(__always) func ekey(_ a: UInt32, _ b: UInt32) -> UInt64 {
            a < b ? (UInt64(a) << 32 | UInt64(b)) : (UInt64(b) << 32 | UInt64(a))
        }
        for i in 0..<n { boundaryEdges.insert(ekey(UInt32(i), UInt32((i + 1) % n))) }

        for _ in 0..<levels {
            var mid = [UInt64: UInt32]()
            var newBoundaryEdges = Set<UInt64>()
            func midpoint(_ a: UInt32, _ b: UInt32) -> UInt32 {
                let key = ekey(a, b)
                if let m = mid[key] { return m }
                let m = UInt32(verts.count)
                verts.append((verts[Int(a)] + verts[Int(b)]) / 2)
                let onBoundary = boundaryEdges.contains(key)
                isBoundary.append(onBoundary)
                if onBoundary {
                    newBoundaryEdges.insert(ekey(a, m))
                    newBoundaryEdges.insert(ekey(m, b))
                }
                mid[key] = m
                return m
            }
            var out: [UInt32] = []
            out.reserveCapacity(tris.count * 4)
            var t = 0
            while t + 2 < tris.count {
                let a = tris[t], b = tris[t + 1], c = tris[t + 2]
                t += 3
                let ab = midpoint(a, b), bc = midpoint(b, c), ca = midpoint(c, a)
                out.append(contentsOf: [a, ab, ca,   ab, b, bc,   ca, bc, c,   ab, bc, ca])
            }
            tris = out
            boundaryEdges = newBoundaryEdges
        }

        // Relax: ichki nuqtalar qo'shnilar o'rtachasiga (25 iteratsiya) —
        // parda minimal-yuzaga yaqin silliq shakl oladi.
        var interior: [Int] = []
        for v in 0..<verts.count where !isBoundary[v] { interior.append(v) }
        if !interior.isEmpty {
            var nbrs = [[Int32]](repeating: [], count: verts.count)
            var t = 0
            while t + 2 < tris.count {
                let a = Int(tris[t]), b = Int(tris[t + 1]), c = Int(tris[t + 2])
                t += 3
                nbrs[a].append(Int32(b)); nbrs[a].append(Int32(c))
                nbrs[b].append(Int32(a)); nbrs[b].append(Int32(c))
                nbrs[c].append(Int32(a)); nbrs[c].append(Int32(b))
            }
            for _ in 0..<25 {
                var next = verts
                for v in interior where !nbrs[v].isEmpty {
                    var s = SIMD3<Float>.zero
                    for u in nbrs[v] { s += verts[Int(u)] }
                    next[v] = s / Float(nbrs[v].count)
                }
                verts = next
            }
        }
        return (verts, tris)
    }

    // MARK: - Degenerativ uchburchaklar

    /// Nol/deyarli-nol yuzali (sliver) uchburchaklarni tashlaydi. Taubin va
    /// chegara silliqlash decimation sliver'larini kollinear qilib qo'yishi
    /// mumkin — texrecon local_seam_leveling bunday yuzada
    /// TexturePatch::get_pixel_value assert'i bilan CRASH bo'ladi (SIGABRT).
    static func dropDegenerate(_ mesh: LiDARMeshData, log: ((String) -> Void)? = nil) -> LiDARMeshData {
        guard !mesh.isEmpty else { return mesh }
        var kept = [UInt32]()
        kept.reserveCapacity(mesh.indices.count)
        var dropped = 0
        var ti = 0
        while ti + 2 < mesh.indices.count {
            let ia = mesh.indices[ti], ib = mesh.indices[ti + 1], ic = mesh.indices[ti + 2]
            ti += 3
            if ia == ib || ib == ic || ia == ic { dropped += 1; continue }
            let a = Int(ia), b = Int(ib), c = Int(ic)
            let pa = SIMD3<Float>(mesh.positions[a*3], mesh.positions[a*3+1], mesh.positions[a*3+2])
            let pb = SIMD3<Float>(mesh.positions[b*3], mesh.positions[b*3+1], mesh.positions[b*3+2])
            let pc = SIMD3<Float>(mesh.positions[c*3], mesh.positions[c*3+1], mesh.positions[c*3+2])
            let cr = simd_cross(pb - pa, pc - pa)
            // |cross|² < 1e-14 → yuza < ~0.05mm² — sliver, ko'zga ko'rinmaydi.
            if simd_length_squared(cr) < 1e-14 { dropped += 1; continue }
            kept.append(ia); kept.append(ib); kept.append(ic)
        }
        guard dropped > 0 else { return mesh }
        log?("DEGEN: \(dropped) sliver uchburchak tashlandi")
        return compact(positions: mesh.positions, indices: kept)
    }

    // MARK: - Yakuniy mesh silliqlash (decimation'dan keyin)

    /// Taubin (λ|μ) silliqlash — YAKUNIY (decimation qilingan) meshda.
    /// meshopt decimation TSDF ichidagi silliqlashdan keyin qirralarni
    /// qaytadan burchakli qiladi — bu o'tish ko'rinадиган qirralarni
    /// yumshatadi, hajm saqlanadi. Normallar qayta hisoblanadi.
    static func taubinSmooth(_ mesh: LiDARMeshData, pairs: Int) -> LiDARMeshData {
        guard !mesh.isEmpty, pairs > 0 else { return mesh }
        let nV = mesh.vertexCount
        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(nV)
        for i in 0..<nV {
            positions.append(SIMD3(mesh.positions[i*3], mesh.positions[i*3+1], mesh.positions[i*3+2]))
        }
        let taubin: [Float] = [0.5, -0.53]
        for pass in 0..<(pairs * 2) {
            let lam = taubin[pass % 2]
            var acc = [SIMD3<Float>](repeating: .zero, count: nV)
            var cnt = [Float](repeating: 0, count: nV)
            var fi = 0
            while fi + 2 < mesh.indices.count {
                let a = Int(mesh.indices[fi]), b = Int(mesh.indices[fi + 1]), c = Int(mesh.indices[fi + 2])
                acc[a] += positions[b] + positions[c]; cnt[a] += 2
                acc[b] += positions[a] + positions[c]; cnt[b] += 2
                acc[c] += positions[a] + positions[b]; cnt[c] += 2
                fi += 3
            }
            for i in 0..<nV where cnt[i] > 0 {
                positions[i] += (acc[i] / cnt[i] - positions[i]) * lam
            }
        }
        var flat = [Float](); flat.reserveCapacity(nV * 3)
        for p in positions { flat.append(p.x); flat.append(p.y); flat.append(p.z) }
        var normals = [Float](repeating: 0, count: nV * 3)
        computeFlatNormals(positions: flat, indices: mesh.indices, into: &normals)
        return LiDARMeshData(positions: flat, normals: normals, indices: mesh.indices)
    }

    // MARK: - Ochiq chegara silliqlash

    /// Skan qamrovi tugagan joyda mesh chegarasi voxel "arra tishi" bo'lib
    /// qoladi (pol/devor cheti zigzag). Ichki (Taubin) silliqlash chegara
    /// shaklini saqlaydi — shuning uchun chegara halqalari ALOHIDA silliqlanadi:
    /// har chegara cho'qqisi o'zining ikki chegara qo'shnisi o'rtachasiga
    /// tortiladi (ichki cho'qqilar qimirlamaydi, o'lchamlar saqlanadi).
    static func smoothBoundary(_ mesh: LiDARMeshData, iterations: Int = 20,
                               strength: Float = 0.6,
                               log: ((String) -> Void)? = nil) -> LiDARMeshData {
        let idx = mesh.indices
        guard idx.count >= 3, !mesh.positions.isEmpty else { return mesh }

        // Yo'nalishsiz qirra sanog'i: 1 marta uchragani — chegara.
        var undirected = [UInt64: Int](minimumCapacity: idx.count)
        @inline(__always) func ukey(_ a: UInt32, _ b: UInt32) -> UInt64 {
            a < b ? (UInt64(a) << 32 | UInt64(b)) : (UInt64(b) << 32 | UInt64(a))
        }
        var ti = 0
        while ti + 2 < idx.count {
            let a = idx[ti], b = idx[ti + 1], c = idx[ti + 2]
            undirected[ukey(a, b), default: 0] += 1
            undirected[ukey(b, c), default: 0] += 1
            undirected[ukey(c, a), default: 0] += 1
            ti += 3
        }
        var nbrs = [Int: [Int]]()
        for (k, cnt) in undirected where cnt == 1 {
            let a = Int(k >> 32), b = Int(k & 0xFFFFFFFF)
            nbrs[a, default: []].append(b)
            nbrs[b, default: []].append(a)
        }
        guard !nbrs.isEmpty else { return mesh }

        var pos = mesh.positions
        for _ in 0..<iterations {
            var next = pos
            for (v, ns) in nbrs where ns.count == 2 {   // non-manifold tugunlar qimirlamaydi
                let p = SIMD3<Float>(pos[v*3], pos[v*3+1], pos[v*3+2])
                let p1 = SIMD3<Float>(pos[ns[0]*3], pos[ns[0]*3+1], pos[ns[0]*3+2])
                let p2 = SIMD3<Float>(pos[ns[1]*3], pos[ns[1]*3+1], pos[ns[1]*3+2])
                let m = p + ((p1 + p2) / 2 - p) * strength
                next[v*3] = m.x; next[v*3+1] = m.y; next[v*3+2] = m.z
            }
            pos = next
        }
        log?("BOUNDARY smooth: \(nbrs.count) chegara cho'qqisi, \(iterations) iter")
        return LiDARMeshData(positions: pos, normals: mesh.normals, indices: idx)
    }

    // MARK: - Mayda teshiklarni lokal to'ldirish

    /// Chegara halqalarini topib, perimetri kichiklarini centroid-fan bilan
    /// yopadi. Natija — ALOHIDA fill mesh (FillColorizer atlas chegara rangi
    /// bilan bo'yaydi, MeshPrep zaxira yo'lidagi kabi). Katta teshiklar
    /// (eshik/deraza/ko'rilmagan devor) halol ochiq qoladi.
    static func smallHoleFill(_ mesh: LiDARMeshData,
                              maxPerimeter: Float = holePerimeterMax,
                              log: ((String) -> Void)? = nil) -> LiDARMeshData? {
        let idx = mesh.indices
        guard idx.count >= 3 else { return nil }

        // Yo'naltirilgan qirralar; juftsizlari — chegara.
        var edgeSet = Set<Int64>(minimumCapacity: idx.count)
        @inline(__always) func ekey(_ a: UInt32, _ b: UInt32) -> Int64 {
            (Int64(a) << 32) | Int64(b)
        }
        var ti = 0
        while ti + 2 < idx.count {
            let a = idx[ti], b = idx[ti + 1], c = idx[ti + 2]
            edgeSet.insert(ekey(a, b)); edgeSet.insert(ekey(b, c)); edgeSet.insert(ekey(c, a))
            ti += 3
        }
        // Chegara qirrasi (a,b): teskarisi (b,a) yo'q. successor xarita.
        var succ = [UInt32: UInt32]()
        var nonManifold = Set<UInt32>()
        for key in edgeSet {
            let a = UInt32(truncatingIfNeeded: key >> 32)
            let b = UInt32(truncatingIfNeeded: key & 0xFFFFFFFF)
            if !edgeSet.contains(ekey(b, a)) {
                if succ[a] != nil { nonManifold.insert(a) }   // 2+ chiquvchi chegara
                succ[a] = b
            }
        }

        var fillPos: [Float] = []
        var fillIdx: [UInt32] = []
        var visited = Set<UInt32>()
        var filled = 0, skippedBig = 0

        for (start, _) in succ {
            if visited.contains(start) || nonManifold.contains(start) { continue }
            // Halqani kuzatamiz.
            var loop: [UInt32] = [start]
            var cur = start
            var ok = false
            while loop.count <= holeMaxEdges {
                guard let nxt = succ[cur], !nonManifold.contains(nxt) else { break }
                if nxt == start { ok = true; break }
                loop.append(nxt)
                cur = nxt
            }
            for v in loop { visited.insert(v) }
            guard ok, loop.count >= 3 else { continue }

            // Perimetr.
            var perim: Float = 0
            var centroid = SIMD3<Float>.zero
            var pts: [SIMD3<Float>] = []
            pts.reserveCapacity(loop.count)
            for v in loop {
                let p = SIMD3(mesh.positions[Int(v)*3], mesh.positions[Int(v)*3+1], mesh.positions[Int(v)*3+2])
                pts.append(p); centroid += p
            }
            centroid /= Float(loop.count)
            for i in 0..<loop.count { perim += simd_distance(pts[i], pts[(i + 1) % loop.count]) }
            guard perim <= maxPerimeter else { skippedBig += 1; continue }

            // Membrana: halqa ustiga silliq parda (fan → subdivide → relax).
            // Chegarasi halqaga mahkam — havoga chiqa olmaydi. Winding fan
            // konvensiyasi bilan bir xil (b, a, c — teskari).
            let base = UInt32(fillPos.count / 3)
            let mem = buildMembrane(ring: pts)
            for p in mem.verts { fillPos.append(p.x); fillPos.append(p.y); fillPos.append(p.z) }
            var mt = 0
            while mt + 2 < mem.tris.count {
                fillIdx.append(base + mem.tris[mt + 1])
                fillIdx.append(base + mem.tris[mt])
                fillIdx.append(base + mem.tris[mt + 2])
                mt += 3
            }
            filled += 1
        }

        guard !fillIdx.isEmpty else {
            log?("TSDF holes: to'ldirish yo'q (katta=\(skippedBig))")
            return nil
        }
        log?("TSDF holes: \(filled) ta mayda yopildi (\(fillIdx.count / 3) tris), katta=\(skippedBig) ochiq")
        var normals = [Float](repeating: 0, count: fillPos.count)
        computeFlatNormals(positions: fillPos, indices: fillIdx, into: &normals)
        return LiDARMeshData(positions: fillPos, normals: normals, indices: fillIdx)
    }

    // MARK: - Yordamchilar

    private static func vertexNormals(positions: [SIMD3<Float>], faces: [UInt32]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var fi = 0
        while fi < faces.count {
            let a = Int(faces[fi]), b = Int(faces[fi + 1]), c = Int(faces[fi + 2])
            let n = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += n; normals[b] += n; normals[c] += n
            fi += 3
        }
        for i in 0..<normals.count {
            let l = simd_length(normals[i])
            normals[i] = l > 1e-8 ? normals[i] / l : SIMD3(0, 1, 0)
        }
        return normals
    }

    private static func computeFlatNormals(positions: [Float], indices: [UInt32], into normals: inout [Float]) {
        let vc = positions.count / 3
        var acc = [SIMD3<Float>](repeating: .zero, count: vc)
        var t = 0
        while t + 2 < indices.count {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2]); t += 3
            let pa = SIMD3(positions[a*3], positions[a*3+1], positions[a*3+2])
            let pb = SIMD3(positions[b*3], positions[b*3+1], positions[b*3+2])
            let pc = SIMD3(positions[c*3], positions[c*3+1], positions[c*3+2])
            let fn = simd_cross(pb - pa, pc - pa)
            acc[a] += fn; acc[b] += fn; acc[c] += fn
        }
        for i in 0..<vc {
            let l = simd_length(acc[i])
            let n = l > 1e-8 ? acc[i] / l : SIMD3<Float>(0, 1, 0)
            normals[i*3] = n.x; normals[i*3+1] = n.y; normals[i*3+2] = n.z
        }
    }

    private static func compact(positions: [Float], indices: [UInt32]) -> LiDARMeshData {
        let vc = positions.count / 3
        var remap = [Int32](repeating: -1, count: vc)
        var pos = [Float]()
        var idx = [UInt32](); idx.reserveCapacity(indices.count)
        for i in indices {
            let v = Int(i)
            if remap[v] == -1 {
                remap[v] = Int32(pos.count / 3)
                pos.append(positions[v*3]); pos.append(positions[v*3+1]); pos.append(positions[v*3+2])
            }
            idx.append(UInt32(remap[v]))
        }
        var normals = [Float](repeating: 0, count: pos.count)
        computeFlatNormals(positions: pos, indices: idx, into: &normals)
        return LiDARMeshData(positions: pos, normals: normals, indices: idx)
    }
}
