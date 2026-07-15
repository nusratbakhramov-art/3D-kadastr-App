import Foundation
import simd

/// Kuzatilgan bo'sh fazo bo'yicha kesish (free-space carving, Polycam uslubi).
///
/// Poisson rekonstruksiya ko'rilmagan hududlarda (obyekt va devor orasida)
/// "parda"/halo yuzalarini to'qib chiqaradi. Keyin texrecon ularга obyekt
/// piksellarini proyeksiya qiladi — devorda "sharpa" (ghost) paydo bo'ladi.
///
/// GIBRID mezon — cho'qqi phantom faqat QUYIDAGILAR BARI bajarilsa:
///  (a) kamida `minVotes` kadr undan NARIROQNI ko'rgan (depth - zc > margin);
///  (b) cho'qqi kirish nuqta-bulutidan `supportRadius` dan UZOQ (tayanchsiz) —
///      haqiqiy yuzalar nuqtalar ustida yotadi, poza drifti ularni kesolmaydi;
///  (c) nur cho'qqi normaliga ≤70° og'ishda tushgan — sirpanma (grazing)
///      burchak ostidagi depth xatosi nur bo'ylab e/sin(θ) ga cho'ziladi va
///      yolg'on "bo'sh fazo" beradi (divan/pol krapinkasi regressiyasi);
///  (d) ovoz bergan kameralar fazoda ≥`minCamSpread` tarqalgan — yonma-yon
///      kadrlar bitta dalilning nusxalari, mustaqil emas.
///
/// Haqiqiy, lekin ko'rinmagan yuzalar (obyekt ORQAsidagi devor) hech qachon
/// (a) ovozini olmaydi — saqlanadi. Parda esa ham "narini ko'rilgan" (a),
/// ham tayanchsiz (b) — kesiladi.
enum FreeSpaceCarver {

    /// Bitta keyframe'ning depth ma'lumoti (proyeksiya matematikasi FusionEngine bilan bir xil).
    struct DepthFrame {
        let R: simd_float3x3          // kamera->world rotatsiya (ustunlar)
        let t: SIMD3<Float>           // kamera markazi (world)
        let fx: Float, fy: Float, cx: Float, cy: Float   // depth o'lchamiga moslangan
        let dw: Int, dh: Int
        let depthMM: [UInt16]         // mm (0 = yaroqsiz)
        let conf: [UInt8]?            // 0/1/2 (nil = fayl yo'q, ishonamiz)
    }

    // MARK: - Sozlamalar

    /// Ovoz chegarasi: depth - zc > baseMargin + relMargin*zc bo'lsa "bo'sh fazo".
    /// baseMargin — Poisson shishishi (~3sm) + poza drifti (~2sm) zaxirasi
    /// (TSDF amaliyotida truncation 4–6sm); relMargin — LiDAR xatosi masofaga
    /// proporsional (~1-2%). 2m da jami ~9sm, 3.5m da ~12sm.
    private static let baseMargin: Float = 0.05
    private static let relMargin: Float = 0.02
    /// Kamida shuncha MUSTAQIL kadr "bo'sh fazo" desagina cho'qqi phantom —
    /// torroq margin bilan drift keltirgan yolg'on kesishlarni yo'q qiladi.
    private static let minVotes = 3
    /// Ovoz uchun maksimal ishonchli depth (Apple LiDAR ichkarida ~3.5m gacha
    /// ishonchli — undan nariги o'qish kesish uchun ovoz bera olmaydi).
    private static let maxVoteDepth: Float = 3.5
    /// Ishlatiladigan kadrlar soni (tekis stride bilan tanlanadi).
    private static let maxCarveFrames = 150
    /// (b) Tayanch radiusi: kirish nuqta-bulutidan shu masofada nuqta bo'lsa —
    /// cho'qqi tayanchli, phantom bo'la olmaydi (2sm voxel bulut + ~3sm Poisson
    /// siljishini qoplaydi).
    private static let supportRadius: Float = 0.05
    /// (c) Nur-normal burchagi chegarasi: cos(70°) — sirpanma nurlar ovoz bermaydi.
    private static let minIncidenceCos: Float = 0.342
    /// (d) Ovoz bergan kameralar orasidagi minimal tarqalish (m).
    private static let minCamSpread: Float = 0.5
    /// Kesishdan keyin qolgan mayda uzuk orollarni tashlash chegarasi.
    private static let minComponentVerts = 120

    // MARK: - Kadr yuklash

    /// frames.json + depth/*.bin dan depth kadrlari. Depth yo'q bo'lsa bo'sh.
    /// maxFrames — tekis stride bilan cheklov (carving 150, TSDF 240).
    static func loadFrames(framesJSON: URL, depthFolder: URL,
                           maxFrames: Int = maxCarveFrames) -> [DepthFrame] {
        guard let data = try? Data(contentsOf: framesJSON),
              let poses = try? JSONDecoder().decode([KeyframePose].self, from: data) else { return [] }

        // Depth o'lchami bor pozalar; keyin tekis stride bilan cheklaymiz.
        let eligible = poses.filter { ($0.depthWidth ?? 0) > 0 && ($0.depthHeight ?? 0) > 0 }
        guard !eligible.isEmpty else { return [] }
        // Ceil — aks holda (masalan 600/240=2.5→2) qopqoqdan oshib ketadi.
        let stride = max(1, (eligible.count + maxFrames - 1) / maxFrames)

        var frames: [DepthFrame] = []
        var i = 0
        while i < eligible.count && frames.count < maxFrames {
            let pose = eligible[i]; i += stride
            guard let dw = pose.depthWidth, let dh = pose.depthHeight else { continue }
            let dURL = depthFolder.appendingPathComponent(String(format: "depth_%04d.bin", pose.index))
            guard let dData = try? Data(contentsOf: dURL), dData.count == dw * dh * 2 else { continue }
            var depthMM = [UInt16](repeating: 0, count: dw * dh)
            dData.withUnsafeBytes { raw in
                depthMM.withUnsafeMutableBytes { $0.copyMemory(from: raw) }
            }
            var conf: [UInt8]? = nil
            let cURL = depthFolder.appendingPathComponent(String(format: "conf_%04d.bin", pose.index))
            if let cData = try? Data(contentsOf: cURL), cData.count == dw * dh {
                conf = [UInt8](cData)
            }

            let t = pose.transform
            let R = simd_float3x3(
                SIMD3(t[0], t[1], t[2]),
                SIMD3(t[4], t[5], t[6]),
                SIMD3(t[8], t[9], t[10]))
            let k = pose.intrinsics
            let sx = Float(pose.width) / Float(dw)
            let sy = Float(pose.height) / Float(dh)
            frames.append(DepthFrame(
                R: R, t: SIMD3(t[12], t[13], t[14]),
                fx: k[0] / sx, fy: k[4] / sy, cx: k[6] / sx, cy: k[7] / sy,
                dw: dw, dh: dh, depthMM: depthMM, conf: conf))
        }
        return frames
    }

    // MARK: - Kesish

    /// Phantom (bo'sh fazoda yotgan) uchburchaklarni olib tashlaydi va
    /// mayda uzuk orollarni tozalab, zichlashtirilgan mesh qaytaradi.
    /// `supportPoints` — Poisson'ga kirgan nuqta-bulut: unga yaqin cho'qqilar
    /// (haqiqiy yuzalar) hech qachon kesilmaydi (gibrid (b) sharti).
    static func carve(_ mesh: LiDARMeshData, frames: [DepthFrame],
                      supportPoints: [SIMD3<Float>],
                      log: ((String) -> Void)? = nil) -> LiDARMeshData {
        let vc = mesh.vertexCount
        guard vc > 0, !frames.isEmpty else { return mesh }

        // Har kadr uchun world->camera oldindan hisoblaymiz.
        let RTs = frames.map { $0.R.transpose }

        // (b) Tayanch to'ri: kirish nuqtalarini supportRadius katakli hash-gridga
        // joylaymiz — so'rov 27 qo'shni katak ichida aniq masofa bilan.
        let cell = supportRadius
        var supportGrid = [SIMD3<Int32>: [SIMD3<Float>]](minimumCapacity: supportPoints.count)
        @inline(__always) func gridKey(_ p: SIMD3<Float>) -> SIMD3<Int32> {
            SIMD3(Int32(floor(p.x / cell)), Int32(floor(p.y / cell)), Int32(floor(p.z / cell)))
        }
        for p in supportPoints { supportGrid[gridKey(p), default: []].append(p) }
        let r2 = supportRadius * supportRadius
        @inline(__always) func isSupported(_ p: SIMD3<Float>) -> Bool {
            let k = gridKey(p)
            for dx in Int32(-1)...1 {
                for dy in Int32(-1)...1 {
                    for dz in Int32(-1)...1 {
                        guard let pts = supportGrid[SIMD3(k.x + dx, k.y + dy, k.z + dz)] else { continue }
                        for q in pts where simd_distance_squared(p, q) <= r2 { return true }
                    }
                }
            }
            return false
        }

        // 1. Har cho'qqi uchun gibrid tekshiruv (parallel).
        var phantom = [Bool](repeating: false, count: vc)
        let chunk = 4096
        let chunks = (vc + chunk - 1) / chunk
        mesh.positions.withUnsafeBufferPointer { pp in
            mesh.normals.withUnsafeBufferPointer { nn in
                phantom.withUnsafeMutableBufferPointer { ph in
                    DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                        let lo = ci * chunk, hi = min(lo + chunk, vc)
                        for vi in lo..<hi {
                            let p = SIMD3<Float>(pp[vi * 3], pp[vi * 3 + 1], pp[vi * 3 + 2])

                            // (b) Tayanchli cho'qqi — haqiqiy yuza, teshib bo'lmaydi.
                            if isSupported(p) { continue }

                            let n = SIMD3<Float>(nn[vi * 3], nn[vi * 3 + 1], nn[vi * 3 + 2])
                            let nLen = simd_length(n)

                            var votePositions: [SIMD3<Float>] = []
                            var spreadOK = false
                            for (fi, f) in frames.enumerated() {
                                let lc = RTs[fi] * (p - f.t)
                                let zc = -lc.z                       // ARKit: -Z oldinga
                                guard zc > 0.15 else { continue }

                                // (c) Sirpanma nur ovoz bermaydi: nur-normal burchagi ≤70°.
                                if nLen > 1e-6 {
                                    let toCam = f.t - p
                                    let cosInc = abs(simd_dot(n, toCam)) / (nLen * simd_length(toCam))
                                    if cosInc < minIncidenceCos { continue }
                                }

                                let u = lc.x / zc * f.fx + f.cx
                                let v = -lc.y / zc * f.fy + f.cy     // Y flip (FusionEngine bilan bir xil)
                                let iu = Int(u), iv = Int(v)
                                guard iu >= 1, iv >= 1, iu < f.dw - 1, iv < f.dh - 1 else { continue }

                                let margin = baseMargin + relMargin * zc

                                // Tez yo'l: markaz piksel bo'sh fazoni ko'rsatmasa, 3x3 min
                                // undan kichik bo'la olmaydi — ovoz bo'lishi mumkin emas.
                                let ci0 = iv * f.dw + iu
                                let dc = f.depthMM[ci0]
                                if dc == 0 { continue }
                                if let c = f.conf, c[ci0] < 1 { continue }
                                let dcM = Float(dc) / 1000
                                guard dcM > 0.1, dcM < maxVoteDepth, dcM - zc > margin else { continue }

                                // 3x3 MIN filtr: obyekt chetidagi "uchayotgan" piksellar
                                // haqiqiy chekka cho'qqilarni yolg'ondan kesmasligi uchun —
                                // butun atrof ham NARIROQNI ko'rgan bo'lishi shart.
                                var dminMM = dc
                                var valid = true
                                for dy in -1...1 {
                                    for dx in -1...1 {
                                        let di = (iv + dy) * f.dw + (iu + dx)
                                        let dv = f.depthMM[di]
                                        if dv == 0 { valid = false; break }
                                        if let c = f.conf, c[di] < 1 { valid = false; break }
                                        if dv < dminMM { dminMM = dv }
                                    }
                                    if !valid { break }
                                }
                                guard valid else { continue }
                                let d = Float(dminMM) / 1000
                                guard d > 0.1, d - zc > margin else { continue }

                                // (d) Ovozlar mustaqilligi: kameralar tarqalishini kuzatamiz.
                                if !spreadOK {
                                    for q in votePositions where simd_distance(q, f.t) >= minCamSpread {
                                        spreadOK = true; break
                                    }
                                }
                                votePositions.append(f.t)
                                if votePositions.count >= minVotes && spreadOK { break }
                            }
                            if votePositions.count >= minVotes && spreadOK { ph[vi] = true }
                        }
                    }
                }
            }
        }

        // 2. Uchburchak phantom — 3 cho'qqidan kamida 2 tasi phantom bo'lsa
        //    (parda ichi to'liq ketadi, devor/obyektga tutashgan halqa qoladi).
        var keptIdx = [UInt32]()
        keptIdx.reserveCapacity(mesh.indices.count)
        var removedTris = 0
        var ti = 0
        while ti + 2 < mesh.indices.count {
            let a = Int(mesh.indices[ti]), b = Int(mesh.indices[ti + 1]), c = Int(mesh.indices[ti + 2])
            let phCount = (phantom[a] ? 1 : 0) + (phantom[b] ? 1 : 0) + (phantom[c] ? 1 : 0)
            if phCount < 2 {
                keptIdx.append(mesh.indices[ti]); keptIdx.append(mesh.indices[ti + 1]); keptIdx.append(mesh.indices[ti + 2])
            } else {
                removedTris += 1
            }
            ti += 3
        }
        let phantomVerts = phantom.lazy.filter { $0 }.count
        log?("CARVE frames=\(frames.count) phantomVerts=\(phantomVerts)/\(vc) removedTris=\(removedTris)")
        guard removedTris > 0 else { return mesh }

        // 3. Kesишdan qolgan mayda orollarni tashlaymiz.
        keptIdx = removeSmallComponents(indices: keptIdx, vertexCount: vc, minVerts: minComponentVerts, log: log)

        // 4. Ishlatilmagan cho'qqilarni zichlashtiramiz.
        return compact(positions: mesh.positions, normals: mesh.normals, indices: keptIdx)
    }

    // MARK: - Mayda orollar (union-find)

    /// minVerts dan kichik bog'langan komponentlardagi uchburchaklarni olib tashlaydi.
    static func removeSmallComponents(indices: [UInt32], vertexCount: Int,
                                      minVerts: Int, log: ((String) -> Void)? = nil) -> [UInt32] {
        guard vertexCount > 0, !indices.isEmpty else { return indices }
        var parent = [Int32](repeating: -1, count: vertexCount)   // -1 = ishlatilmagan
        func find(_ x: Int32) -> Int32 {
            var r = x
            while parent[Int(r)] != r { r = parent[Int(r)] }
            var c = x
            while parent[Int(c)] != r { let n = parent[Int(c)]; parent[Int(c)] = r; c = n }
            return r
        }
        func union(_ a: Int32, _ b: Int32) {
            if parent[Int(a)] == -1 { parent[Int(a)] = a }
            if parent[Int(b)] == -1 { parent[Int(b)] = b }
            let ra = find(a), rb = find(b)
            if ra != rb { parent[Int(ra)] = rb }
        }
        var ti = 0
        while ti + 2 < indices.count {
            union(Int32(indices[ti]), Int32(indices[ti + 1]))
            union(Int32(indices[ti + 1]), Int32(indices[ti + 2]))
            ti += 3
        }
        var sizes = [Int32: Int]()
        for v in 0..<vertexCount where parent[v] != -1 {
            sizes[find(Int32(v)), default: 0] += 1
        }
        var out = [UInt32]()
        out.reserveCapacity(indices.count)
        var dropped = 0
        ti = 0
        while ti + 2 < indices.count {
            let root = find(Int32(indices[ti]))
            if (sizes[root] ?? 0) >= minVerts {
                out.append(indices[ti]); out.append(indices[ti + 1]); out.append(indices[ti + 2])
            } else {
                dropped += 1
            }
            ti += 3
        }
        if dropped > 0 { log?("CARVE small components: -\(dropped) tris") }
        return out
    }

    // MARK: - Zichlashtirish

    /// Indekslarda ishlatilmagan cho'qqilarni olib tashlab, qayta raqamlaydi.
    private static func compact(positions: [Float], normals: [Float], indices: [UInt32]) -> LiDARMeshData {
        let vc = positions.count / 3
        var remap = [Int32](repeating: -1, count: vc)
        var pos = [Float](); var nrm = [Float]()
        var idx = [UInt32](); idx.reserveCapacity(indices.count)
        for i in indices {
            let v = Int(i)
            if remap[v] == -1 {
                remap[v] = Int32(pos.count / 3)
                pos.append(positions[v * 3]); pos.append(positions[v * 3 + 1]); pos.append(positions[v * 3 + 2])
                nrm.append(normals[v * 3]); nrm.append(normals[v * 3 + 1]); nrm.append(normals[v * 3 + 2])
            }
            idx.append(UInt32(remap[v]))
        }
        return LiDARMeshData(positions: pos, normals: nrm, indices: idx)
    }
}
