import Foundation
import simd

/// Katta TEKIS sohalarni (devor, pol, shift) aniqlab, ularning vertekslarini fitlangan
/// tekislikka YOPISHTIRADI — shovqinli LiDAR'dan kelgan "to'lqinli/eritilgan" devorlarni
/// mukammal tekis qiladi. Burchak/qirra vertekslari (2+ tekislikка tegadigan) TEGILMAYDI.
///
/// Usul (greedy region-growing plane fitting): eng katta tekislikni top → inlier yuzlarni
/// belgila → keyingi tekislik → ... Har verteks FAQAT bitta tekislikка tegsa → proyeksiya.
enum MeshPlaneSnap {

    struct Plane { var n: SIMD3<Float>; var d: Float }   // n·x = d, |n|=1

    static func snap(
        _ mesh: WeldedMesh,
        distThresh: Float = 0.03,     // 3 sm — shu masofadagi yuz tekislikning inlieri
        angleCos: Float = 0.94,       // ~20° — normal shu qadar mos bo'lsa inlier
        minPlaneArea: Float = 1.2,    // m² — faqat KATTA tekisliklar (devor/pol/shift)
        maxPlanes: Int = 16
    ) -> WeldedMesh {
        let V = mesh.positions, idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 500 else { return mesh }

        // Yuz normal + markaz + yuza
        var fNv = [SIMD3<Float>](repeating: .zero, count: faceCount)
        var fCv = [SIMD3<Float>](repeating: .zero, count: faceCount)
        var fAv = [Float](repeating: 0, count: faceCount)
        for f in 0..<faceCount {
            let a = V[Int(idx[f*3])], b = V[Int(idx[f*3+1])], c = V[Int(idx[f*3+2])]
            let cr = simd_cross(b - a, c - a)
            let l = simd_length(cr)
            fAv[f] = 0.5 * l
            fNv[f] = l > 1e-9 ? cr / l : SIMD3<Float>(0, 1, 0)
            fCv[f] = (a + b + c) / 3
        }
        let fN = fNv, fC = fCv, fA = fAv   // immutable snapshot (parallel skan uchun)

        // PARALLEL inlier-skan: mesh chunk'larga bo'linadi, har chunk o'z natijasini
        // o'z slotiga yozadi (poyga yo'q), merge chunk tartibida → deterministik.
        let procs = max(2, min(16, ProcessInfo.processInfo.activeProcessorCount))
        let chunkSize = (faceCount + procs - 1) / procs
        struct ChunkRes { var inl: [Int] = []; var n = SIMD3<Float>.zero; var d: Float = 0; var a: Float = 0 }
        func scanInliers(_ pn: SIMD3<Float>, _ pd: Float, _ fp: [Int32],
                         _ angleCos: Float, _ distThresh: Float) -> ([Int], SIMD3<Float>, Float, Float) {
            var res = [ChunkRes](repeating: ChunkRes(), count: procs)
            res.withUnsafeMutableBufferPointer { rb in
                DispatchQueue.concurrentPerform(iterations: procs) { ci in
                    let lo = ci * chunkSize, hi = min(faceCount, lo + chunkSize)
                    if lo >= hi { return }
                    var r = ChunkRes()
                    fp.withUnsafeBufferPointer { fpb in
                        fN.withUnsafeBufferPointer { fnb in
                            fC.withUnsafeBufferPointer { fcb in
                                fA.withUnsafeBufferPointer { fab in
                                    for f in lo..<hi where fpb[f] < 0 {
                                        let dn = simd_dot(fnb[f], pn)
                                        if abs(dn) < angleCos { continue }
                                        let dc = simd_dot(fcb[f], pn)
                                        if abs(dc - pd) > distThresh { continue }
                                        r.inl.append(f)
                                        let s: Float = dn < 0 ? -1 : 1
                                        r.n += fnb[f] * (s * fab[f]); r.d += dc * fab[f]; r.a += fab[f]
                                    }
                                }
                            }
                        }
                    }
                    rb[ci] = r
                }
            }
            var inl = [Int](); var n = SIMD3<Float>.zero; var d: Float = 0; var a: Float = 0
            for r in res { inl.append(contentsOf: r.inl); n += r.n; d += r.d; a += r.a }
            return (inl, n, d, a)
        }

        // Greedy: eng katta yuzlardan boshlab tekislik o'stiramiz
        var order = Array(0..<faceCount).sorted { fA[$0] > fA[$1] }
        var facePlane = [Int32](repeating: -1, count: faceCount)   // yuz -> plane id
        var planes: [Plane] = []

        // TEZLIK: `consumed` — seed sifatida ISHLATILGAN region yuzlari. Har seed'ning
        // region-grow'i (qabul/rad) bo'lsa ham yuzlarini "consumed" qilamiz → ular QAYTA
        // seed BO'LMAYDI. Muhim xossa: KATTA tekislikning istalgan yuzidan seed qilsak,
        // region butun tekislikni qamrab area≥minPlaneArea → QABUL. Demak RAD etilgan
        // region'da katta-tekislik yuzi BO'LMAYDI → ularni consumed qilish xavfsiz.
        // Bu seed sonini "aniq klasterlar soni"ga cheklaydi (klutter sahnada minglab
        // seed × butun-mesh skan → O(seed×face) portlashi shu bilan bartaraf).
        // `consumed` faqat seed-tanlashga tegishli; region-grow hamon `facePlane<0`ni
        // ko'radi (consumed-lekin-tayinlanmagan yuz keyingi tekislik inlieri bo'la oladi).
        var consumed = [Bool](repeating: false, count: faceCount)
        var seedTries = 0
        var consecRejects = 0
        let tSnap0 = CFAbsoluteTimeGetCurrent()

        for seed in order {
            if planes.count >= maxPlanes { break }
            // ADAPTIV TO'XTASH: katta tekisliklar (devor/pol/shift) dastlabki seed'lardayoq
            // topiladi (ular yuza ulushi katta → tasodifiy seed tez uradi). Ketma-ket 1500 ta
            // seed RAD bo'lsa — qolgani klutter, katta tekislik qolmagan → to'xta.
            // (Skan parallel-arzon: qo'shimcha ming rad ≈ ~0.3s Mac / ~1-2s telefon.)
            if consecRejects >= 1500 { break }
            if seedTries >= 4000 { break }   // xavfsizlik chegarasi (pathologik sahna)
            if facePlane[seed] >= 0 || consumed[seed] { continue }
            if fA[seed] < 1e-5 { continue }
            seedTries += 1
            // dastlabki tekislik seed'dan
            var pn = fN[seed]
            var pd = simd_dot(pn, fC[seed])
            // 3 marta refine (PARALLEL butun-mesh skan). EARLY-REJECT: 1-passdayoq yuza
            // aniq kichik bo'lsa qolgan passlar tashlanadi. Katta tekislik to'liq refine.
            var inliers: [Int] = []
            var accAfinal: Float = 0
            let fp = facePlane   // CoW snapshot — skan davomida o'zgarmaydi
            for pass in 0..<3 {
                let (inl, accN, accD, accA) = scanInliers(pn, pd, fp, angleCos, distThresh)
                inliers = inl
                accAfinal = accA
                if accA < 1e-6 { break }
                if pass == 0 && (accA < minPlaneArea * 0.6 || inliers.count < 200) { break }
                let nn = simd_length(accN)
                if nn > 1e-6 { pn = accN / nn }
                pd = accD / accA
            }
            // Region yuzlarini consumed qil (qayta seed bo'lmasin — rad etilgan klaster ham)
            for f in inliers { consumed[f] = true }
            if accAfinal < minPlaneArea || inliers.count < 200 { consecRejects += 1; continue }
            consecRejects = 0
            let pid = Int32(planes.count)
            planes.append(Plane(n: pn, d: pd))
            for f in inliers { facePlane[f] = pid }
        }
        NSLog("MeshPlaneSnap: %d tekislik, %d seed, %.0f ms",
              planes.count, seedTries, (CFAbsoluteTimeGetCurrent() - tSnap0) * 1000)
        guard !planes.isEmpty else { return mesh }

        // Har verteks qaysi tekislik(lar)ga tegadi
        var vPlanes = [Set<Int32>](repeating: [], count: V.count)
        for f in 0..<faceCount {
            let p = facePlane[f]
            if p < 0 { continue }
            vPlanes[Int(idx[f*3])].insert(p)
            vPlanes[Int(idx[f*3+1])].insert(p)
            vPlanes[Int(idx[f*3+2])].insert(p)
        }

        // OCHIQ CHEGARA vertekslarini aniqlash (faqat 1 yuz ishlatgan qirra) — ularni
        // KO'CHIRMAYMIZ, aks holda teshik chegarasidа cho'zilgan "tikan" flaplar paydo bo'ladi.
        var edgeCount = [UInt64: Int](minimumCapacity: faceCount * 3)
        func ekey(_ a: UInt32, _ b: UInt32) -> UInt64 { let lo = min(a,b), hi = max(a,b); return (UInt64(lo) << 32) | UInt64(hi) }
        for f in 0..<faceCount {
            let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
            edgeCount[ekey(a,b), default: 0] += 1
            edgeCount[ekey(b,c), default: 0] += 1
            edgeCount[ekey(c,a), default: 0] += 1
        }
        var isBoundary = [Bool](repeating: false, count: V.count)
        for (e, cnt) in edgeCount where cnt == 1 {
            isBoundary[Int(e >> 32)] = true
            isBoundary[Int(e & 0xFFFFFFFF)] = true
        }

        // FAQAT bitta tekislikка tegadigan VA ochiq chegarada BO'LMAGAN vertekslarni
        // proyeksiya (ichki devor); burchak/qirra/teshik-chegarasi tegilmaydi
        var newV = V
        var moved = 0
        for i in 0..<V.count where vPlanes[i].count == 1 && !isBoundary[i] {
            let p = planes[Int(vPlanes[i].first!)]
            let dist = simd_dot(p.n, V[i]) - p.d
            if abs(dist) > 0.06 { continue }   // juda uzoq bo'lsa (noto'g'ri assignment) tegma
            newV[i] = V[i] - p.n * dist
            moved += 1
        }
        _ = moved
        return WeldedMesh(positions: newV, normals: [], indices: idx)
    }
}
