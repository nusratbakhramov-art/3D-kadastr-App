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

    // MARK: - Struktura tekisligi (RoomPlan devor/pol/shift)

    /// RoomPlan tekisligi — RoomPlan'siz struct (macOS runner mos).
    /// `normalOut` xonadan TASHQARIGA qaraydi (TSDF ishorasi bilan mos: xona ichi musbat).
    struct WallPlane {
        /// `snapToMeasured` tekislikni o'lchangan yuzaga suradi — shuning uchun var.
        var center: SIMD3<Float>
        let normalOut: SIMD3<Float>
        let xAxis: SIMD3<Float>
        let yAxis: SIMD3<Float>
        let halfW: Float
        let halfH: Float
        /// Proyomlar (eshik/deraza) tekislik-lokal (x,y) da — bu joylar to'ldirilmaydi.
        var cutouts: [(min: SIMD2<Float>, max: SIMD2<Float>)] = []
        /// Pol/shift uchun world-XZ konturi (L-shaklli xona). Devorda nil.
        var polygonXZ: [SIMD2<Float>]? = nil
        /// SHISHA MUHRI (5.4.0.1 porti): LiDAR shishadan O'TIB ketadi, shuning uchun
        /// carving shisha ortini "bo'sh" deb belgilaydi va yuza umuman chiqmaydi.
        /// `seal=true` bo'lsa integratsiyada nur shu tekislikda KESILADI (virtual
        /// qaytish) — shisha bo'shliq emas, YUZA bo'ladi.
        /// Semantika: deraza — DOIM; eshik — faqat YOPIQ bo'lsa. Ochiq o'tish joyi
        /// muhrlanmaydi (halol teshik bo'lib qoladi).
        var seal: Bool = false
        /// Bu tekislik PROYOM (eshik/deraza) mi yoki struktura (devor/pol/shift) mi.
        /// Proyom muhrlanmagan bo'lsa — to'ldirilmaydi (ochiq o'tish joyi).
        var isOpening: Bool = false
        /// Tekislikni O'LCHANGAN yuzaga surish — RoomPlan joylashuvi taxminiy.
        ///
        /// Ikki o'lchangan holat (skan 20260713-192242):
        ///  • EKRAN: quti oldi +0.050, haqiqiy ramka +0.015 — 3.5sm farq, `trunc`
        ///    ichida ikki yuza aralashib ketardi.
        ///  • SHISHA: RoomPlan shisha to'siqni 8sm TASHQARIDA deb hisoblaydi
        ///    (devor[1] +0.087, devor[9] +0.081; eshik tekisliklari +0.083/+0.087).
        ///    Pol esa haqiqiy joyida tugaydi — natijada shisha tagida ~8sm ochiq
        ///    lenta qolib, qora chiziq bo'lib ko'rinadi. Qolgan 8 devorda siljish
        ///    ≤0.030 m, ya'ni snap ularga deyarli tegmaydi.
        ///
        /// Namuna yetmasa (masalan deraza — 1 ta namuna) tekislik QIMIRLAMAYDI.
        var snapToMeasured: Bool = false
        var label: String = "tekislik"
    }

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
    static func build(paths: ScanPaths, planes: [WallPlane] = [],
                      log: ((String) -> Void)? = nil) -> LiDARMeshData? {
        let dense = DenseDepthStore.loadFrames(posesJSON: paths.densePosesJSON,
                                               folder: paths.denseFolder,
                                               maxFrames: maxDenseFrames)
        if dense.count >= 50 {
            log?("TSDF manba=DENSE kadrlar=\(dense.count)")
            return integrate(frames: dense, planes: planes, log: log)
        }
        let frames = FreeSpaceCarver.loadFrames(framesJSON: paths.framesJSON,
                                                depthFolder: paths.depthFolder,
                                                maxFrames: maxFrames)
        guard frames.count >= 10 else {
            log?("TSDF skip: depth kadrlari yetarli emas (\(frames.count))")
            return nil
        }
        log?("TSDF manba=keyframe kadrlar=\(frames.count)")
        return integrate(frames: frames, planes: planes, log: log)
    }

    // MARK: - Vazn gisterezisi (Canny uslubi)

    /// Zaif vazn CHEGARASI o'rniga IKKI chegara + bog'lanish (Canny gisterezisi).
    ///
    /// Muammo: yakka `extractMinWeight = 0.45` chegarasi rangni emas, ISHONCHNI
    /// kesadi — o'lchandi (skan 20260717-110900): u ARKit tasdiqlagan 8.3 m² real
    /// yuzani ham yeydi, evaziga ~13 m² "konfetti" (yakka-o'qish qobig'i) ni kesadi.
    /// Ikkalasi ham kerak edi.
    ///
    /// Yechim: `high` dan kuchli voxellar URUG', ulardan `low` dan kuchli voxellar
    /// bo'ylab BFS tarqaladi. Kuchli o'lchangan devorga ULANGAN zaif voxel qoladi
    /// (devorning davomi — real), yakka miltillagan qobiq esa hech qayerga ulanmaydi
    /// va tashlanadi. Qabul qilinmagan voxel `wsum = 0` bo'ladi → SurfaceNets uni
    /// ko'rmaydi (extract `minWeight: 0` bilan chaqiriladi).
    /// Qurilmada A/B uchun sozlanadi (UserDefaults "hysteresisLow"). O'lchangan
    /// muvozanat (skan 20260717-110900, ARKit tasdiqlagan yuza / uydirma):
    ///   0.15 -> yo'qolgan 19.6 m²   0.25 -> 22.1 m²   0.35 -> 24.1 m²
    ///   (eski yakka chegara 0.45 -> 25.9 m²)
    /// Konfetti qaytsa — 0.25/0.35 ga ko'taring.
    private static var hysteresisLow: Float {
        let v = UserDefaults.standard.float(forKey: "hysteresisLow")
        return v > 0 ? v : 0.15
    }
    private static let hysteresisHigh: Float = 0.45

    static func applyHysteresis(_ wsum: inout [Float], dims: SIMD3<Int>,
                                low: Float, high: Float, log: ((String) -> Void)? = nil) {
        let nx = dims.x, ny = dims.y, nz = dims.z
        var accepted = [Bool](repeating: false, count: wsum.count)
        var queue = [Int32]()
        queue.reserveCapacity(1 << 20)
        var weak = 0
        for i in 0..<wsum.count {
            let w = wsum[i]
            if w > high { accepted[i] = true; queue.append(Int32(i)) }
            else if w > low { weak += 1 }
        }
        let strong = queue.count
        // BFS: urug'lardan zaif voxellar bo'ylab (6-qo'shni).
        var head = 0
        while head < queue.count {
            let idx = Int(queue[head]); head += 1
            let k = idx % nz
            let j = (idx / nz) % ny
            let i = idx / (nz * ny)
            @inline(__always) func visit(_ ni: Int, _ nj: Int, _ nk: Int) {
                guard ni >= 0, nj >= 0, nk >= 0, ni < nx, nj < ny, nk < nz else { return }
                let n = (ni * ny + nj) * nz + nk
                guard !accepted[n], wsum[n] > low else { return }
                accepted[n] = true
                queue.append(Int32(n))
            }
            visit(i-1, j, k); visit(i+1, j, k)
            visit(i, j-1, k); visit(i, j+1, k)
            visit(i, j, k-1); visit(i, j, k+1)
        }
        var dropped = 0
        for i in 0..<wsum.count where !accepted[i] && wsum[i] > 0 {
            wsum[i] = 0; dropped += 1
        }
        log?("HYSTERESIS kuchli=\(strong) zaif=\(weak) qutqarildi=\(queue.count - strong) "
             + "tashlandi=\(dropped)")
    }

    // MARK: - Autlayerga chidamli chegara

    /// Bo'shliq bo'yicha autlayer rad etish: qiymatlar saralanadi va MEDIANANI
    /// o'z ichiga olgan uzluksiz to'da qaytariladi (qo'shni namunalar orasi
    /// `maxGap` dan katta bo'lsa — uzilish).
    ///
    /// Nega bu kerak edi: ilgari `maxs = min(maxs, mins + 12)` — ya'ni panjara
    /// `mins` dan 12m dan narisiga UMUMAN chiqmasdi. Bu "yakka buzuq o'qish
    /// hajmni portlatmasin" uchun qo'yilgan, lekin ko'r-ko'rona quti edi: bitta
    /// autlayer `mins` ni surса, u XONANING NARIGI YARMINI kesardi. Haqiqiy
    /// skanda o'lchandi (20260717-110900, xona 13.0×13.4m): qopqoq x bo'yicha
    /// 1.21m, z bo'yicha 1.62m kesgan — skan qilingan 30.2 m² yuza yo'qolgan.
    ///
    /// Xotira uchun bu qopqoq KERAK EMAS — `maxVoxels` allaqachon voxelni
    /// yiriklashtirib xotirani cheklaydi. Kerak bo'lgani faqat autlayer edi,
    /// bu yerda esa u aynan autlayer sifatida (uzilish bo'yicha) rad etiladi:
    /// xonaning haqiqiy cheti to'da bilan tutash, yakka shovqin esa metrlab
    /// narida — uzilib qoladi.
    static func robustRange(_ v: inout [Float], maxGap: Float = 1.0) -> (lo: Float, hi: Float) {
        v.sort()
        guard let first = v.first, let last = v.last else { return (0, 0) }
        guard v.count >= 8 else { return (first, last) }
        let medIdx = v.count / 2
        var lo = medIdx, hi = medIdx
        while lo > 0, v[lo] - v[lo - 1] <= maxGap { lo -= 1 }
        while hi < v.count - 1, v[hi + 1] - v[hi] <= maxGap { hi += 1 }
        return (v[lo], v[hi])
    }

    // MARK: - Struktura tekisliklarini quyish

    /// Kuzatilmagan (`wsum <= 0`) voxellarga analitik tekislik SDF quyadi — devor/pol/
    /// shift ko'rilmagan joyda ham TEKIS davom etadi, teshik bo'lib qolmaydi.
    ///
    /// Halollik shu yerda: real o'lchov HAR DOIM ustun (`wsum > 0` bo'lsa tegilmaydi).
    /// Ochiq eshikni kamera "teshib" ko'rgan → o'sha voxellar bo'sh deb belgilangan
    /// (`wsum > 0`) → bu yerda o'tkazib yuboriladi → o'tish joyi teshikligicha qoladi.
    private static func injectPlanes(_ planes: [WallPlane],
                                     tsdf: inout [Float], wsum: inout [Float],
                                     dims: SIMD3<Int>, mins: SIMD3<Float>,
                                     vox: Float, trunc: Float,
                                     log: ((String) -> Void)?) {
        let ny = dims.y, nz = dims.z
        let pad: Float = 0.10
        // Yuza chiqishi uchun vazn extractMinWeight dan KATTA bo'lishi SHART.
        // Literal 0.6 xavfli: extractMinWeight tarixda 1.05 bo'lgan (5.2.0-e da
        // 0.45 ga tushirilgan) — o'shanda inject JIMGINA hech narsa bermasdi.
        let planeW: Float = max(0.6, extractMinWeight * 1.5)
        var totalInjected = 0, clipped = 0

        for plane in planes {
            // Muhrlanmagan PROYOM (ochiq eshik) — to'ldirilmaydi, halol teshik.
            // Struktura tekisliklari (devor/pol/shift) `seal` dan qat'i nazar
            // to'ldiriladi — ular proyom emas.
            if plane.isOpening, !plane.seal {
                log?("PLANE[\(plane.label)] SKIP: ochiq proyom")
                continue
            }
            // Pol/shift — yassi tekislik EMAS, o'lchangan balandlik xaritasi.
            if plane.polygonXZ != nil {
                totalInjected += injectHeightMap(plane, tsdf: &tsdf, wsum: &wsum, dims: dims,
                                                 mins: mins, vox: vox, trunc: trunc,
                                                 planeW: planeW, log: log)
                continue
            }
            // Ekran tekisligini O'LCHANGAN ramkaga suramiz (RoomPlan gabariti taxminiy).
            var plane = plane
            if plane.snapToMeasured {
                if let off = measuredOffset(plane, tsdf: &tsdf, wsum: &wsum, dims: dims,
                                            mins: mins, vox: vox, planeW: planeW) {
                    plane.center += plane.normalOut * off
                    log?("PLANE[\(plane.label)] snap=\(String(format: "%+.3f", off)) m")
                } else {
                    log?("PLANE[\(plane.label)] snap: namuna yetmadi → quti oldi")
                }
            }
            // Muhrlangan proyom (shisha) — o'yilgan voxelni ham to'ldiramiz.
            let forceSeal = plane.isOpening && plane.seal
            let hw = plane.halfW + pad, hh = plane.halfH + pad
            // Tekislik plitasining world-AABB'i.
            var bmin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var bmax = -bmin
            for su in [-hw, hw] {
                for sv in [-hh, hh] {
                    for sn in [-(trunc + 0.02), trunc + 0.02] {
                        let corner = plane.center + plane.xAxis * su + plane.yAxis * sv
                            + plane.normalOut * sn
                        bmin = simd_min(bmin, corner)
                        bmax = simd_max(bmax, corner)
                    }
                }
            }
            let i0 = max(Int((bmin.x - mins.x) / vox) - 1, 0)
            let i1 = min(Int((bmax.x - mins.x) / vox) + 1, dims.x - 1)
            let j0 = max(Int((bmin.y - mins.y) / vox) - 1, 0)
            let j1 = min(Int((bmax.y - mins.y) / vox) + 1, ny - 1)
            let k0 = max(Int((bmin.z - mins.z) / vox) - 1, 0)
            let k1 = min(Int((bmax.z - mins.z) / vox) + 1, nz - 1)
            guard i0 <= i1, j0 <= j1, k0 <= k1 else { continue }
            // Tekislik gridga to'liq sig'maganini bilib turaylik (chegara depth
            // namunalaridan olinadi — RoomPlan undan chetga chiqishi mumkin).
            if bmin.x < mins.x || bmin.y < mins.y || bmin.z < mins.z
                || bmax.x > mins.x + Float(dims.x) * vox
                || bmax.y > mins.y + Float(ny) * vox
                || bmax.z > mins.z + Float(nz) * vox { clipped += 1 }

            var perSlab = [Int](repeating: 0, count: i1 - i0 + 1)
            perSlab.withUnsafeMutableBufferPointer { slab in
            tsdf.withUnsafeMutableBufferPointer { tPtr in
                wsum.withUnsafeMutableBufferPointer { wPtr in
                    // i-slablar bir-biriga yozmaydi — parallel xavfsiz.
                    DispatchQueue.concurrentPerform(iterations: i1 - i0 + 1) { di in
                        let i = i0 + di
                        var local = 0
                        for j in j0...j1 {
                            for k in k0...k1 {
                                let p = mins + SIMD3(Float(i) + 0.5, Float(j) + 0.5,
                                                     Float(k) + 0.5) * vox
                                let d = p - plane.center
                                let u = simd_dot(d, plane.xAxis)
                                let v = simd_dot(d, plane.yAxis)
                                guard abs(u) <= hw, abs(v) <= hh else { continue }
                                let t = simd_dot(d, plane.normalOut)
                                guard abs(t) <= trunc else { continue }
                                // Proyom (eshik/deraza) — to'ldirilmaydi.
                                if !plane.cutouts.isEmpty, insideCutout(u, v, plane.cutouts) { continue }
                                // Pol/shift konturidan tashqarisi.
                                if let poly = plane.polygonXZ,
                                   !pointInPolygon(SIMD2(p.x, p.z), poly) { continue }
                                let idx = (i * ny + j) * nz + k
                                // Odatda: real o'lchov USTUN — faqat hech qanday nur
                                // tegmagan (`wsum <= 0`) voxelga yozamiz.
                                //
                                // MUHRLANGAN PROYOM (shisha) — ISTISNO: LiDAR shishadan
                                // O'TIB ketadi va narigi tomonni o'lchaydi, ya'ni voxel
                                // "bo'sh" deb belgilanadi. Bu o'lchov shishaning
                                // shaffofligidan kelib chiqqan YOLG'ON — u yerda yuza
                                // BOR. Ray-clamp buni ko'p joyda oldini oladi, lekin
                                // qiya burchakdan kelgan nurlar rect testidan chetda
                                // qolib o'yib ketadi (o'lchandi, skan 20260713-192242:
                                // shishada 8 ta teshik, 0.05-0.27 m², jami ~1 m²).
                                // Shuning uchun muhrlangan tekislikda o'yilganini ham
                                // to'ldiramiz. Bu FAQAT `seal` ga tegishli — ochiq
                                // proyom yuqorida allaqachon chetlab o'tilgan.
                                guard forceSeal || wPtr[idx] <= 0 else { continue }
                                tPtr[idx] = min(max(-t / trunc, -1), 1)
                                wPtr[idx] = planeW
                                local += 1
                            }
                        }
                        slab[di] = local
                    }
                }
            }
            }
            totalInjected += perSlab.reduce(0, +)
        }
        log?("PLANE inject=\(totalInjected) voxel (\(planes.count) tekislik, "
             + "grid'ga sig'magan=\(clipped), w=\(String(format: "%.2f", planeW)))")
    }

    /// Ekran tekisligi uchun O'LCHANGAN chuqurlik ofseti (m, `normalOut` bo'ylab).
    ///
    /// Televizor ramkasi/chetlari LiDAR tomonidan KO'RILADI (o'lchandi: chetlarda
    /// 1364 ta yuza, ichki shovqin 5.7mm — real o'lchov), faqat qora yaltiroq
    /// EKRANNING o'zi qaytish bermaydi. Ya'ni to'g'ri chuqurlikni obyektning O'Z
    /// o'lchangan qismidan olsak bo'ladi — RoomPlan qutisiga ishonish shart emas.
    ///
    /// Qidiruv oralig'i ±12sm: ortdagi devor (o'lchandi: 22sm orqada) va uning
    /// INJECT qilingan tekisligi qidiruvga tushmasin. Qo'shimcha himoya sifatida
    /// vazni aynan `planeW` bo'lgan (ya'ni inject qilingan) voxel hisobga olinmaydi.
    private static func measuredOffset(_ plane: WallPlane,
                                       tsdf: inout [Float], wsum: inout [Float],
                                       dims: SIMD3<Int>, mins: SIMD3<Float>,
                                       vox: Float, planeW: Float) -> Float? {
        let ny = dims.y, nz = dims.z
        let range: Float = 0.12
        let nu = 48, nv = 28
        var hits: [Float] = []
        for a in 0..<nu {
            let u = plane.halfW * (2 * (Float(a) + 0.5) / Float(nu) - 1)
            for b in 0..<nv {
                let v = plane.halfH * (2 * (Float(b) + 0.5) / Float(nv) - 1)
                let base = plane.center + plane.xAxis * u + plane.yAxis * v
                // Ustun bo'ylab nolga eng yaqin (ya'ni yuzaga eng yaqin) o'lchov.
                var best: Float?
                var bestAbs: Float = .greatestFiniteMagnitude
                var t = -range
                while t <= range {
                    let p = base + plane.normalOut * t
                    let i = Int((p.x - mins.x) / vox)
                    let j = Int((p.y - mins.y) / vox)
                    let k = Int((p.z - mins.z) / vox)
                    if i >= 0, i < dims.x, j >= 0, j < ny, k >= 0, k < nz {
                        let idx = (i * ny + j) * nz + k
                        let w = wsum[idx]
                        if w > 0, w != planeW, abs(tsdf[idx]) < bestAbs {
                            bestAbs = abs(tsdf[idx])
                            best = t
                        }
                    }
                    t += vox
                }
                if let bt = best, bestAbs < 0.5 { hits.append(bt) }
            }
        }
        // Kam namuna — ishonchsiz, quti oldida qolaveradi.
        guard hits.count >= 40 else { return nil }
        hits.sort()
        return hits[hits.count / 2]
    }

    /// Pol/shift to'ldirish — RoomPlan balandligiga EMAS, O'LCHANGAN yuzaga bog'liq.
    ///
    /// Nega yassi tekislik yaramaydi (o'lchandi, skan 20260717-110900): RoomPlan
    /// bitta balandlik beradi — devor tepalarining MAKSIMUMI (y=1.96). Haqiqiy
    /// asosiy shift esa 1.85 da (11sm past — `trunc` dan katta, ya'ni o'lchangan
    /// shift USTIGA ikkinchi soxta shift chiqadi), va xonada 1.45 da beton karniz
    /// bor (6.1 m²) — RoomPlan uni umuman bilmaydi. Yassi tekislik o'lchangan
    /// shiftning 24.2 m² ini soxta parda ostida qoldirardi.
    ///
    /// Shuning uchun: har XZ ustunida O'LCHANGAN balandlik topiladi; faqat HECH
    /// NARSA o'lchanmagan ustunlar (haqiqiy teshik) to'ldiriladi, balandligi esa
    /// qo'shnilardan tarqatiladi. Ko'p pog'onali shift va karniz saqlanadi.
    private static func injectHeightMap(_ plane: WallPlane,
                                        tsdf: inout [Float], wsum: inout [Float],
                                        dims: SIMD3<Int>, mins: SIMD3<Float>,
                                        vox: Float, trunc: Float, planeW: Float,
                                        log: ((String) -> Void)?) -> Int {
        guard let poly = plane.polygonXZ else { return 0 }
        let nx = dims.x, ny = dims.y, nz = dims.z
        let up = plane.normalOut.y > 0            // shift: normal tepaga; pol: pastga
        let unknown: Float = .greatestFiniteMagnitude
        let planeY = plane.center.y
        let heightBand: Float = 0.6

        // 1) Har (i,k) ustunida o'lchangan balandlik (eng chekka sign-change).
        var hmap = [Float](repeating: unknown, count: nx * nz)
        var inPoly = [Bool](repeating: false, count: nx * nz)
        for i in 0..<nx {
            for k in 0..<nz {
                let p = SIMD2(mins.x + (Float(i) + 0.5) * vox, mins.z + (Float(k) + 0.5) * vox)
                guard pointInPolygon(p, poly) else { continue }
                inPoly[i * nz + k] = true
                // Shift: tepadan pastga; pol: pastdan tepaga.
                let range = up ? Array((0..<(ny - 1)).reversed()) : Array(0..<(ny - 1))
                for j in range {
                    let a = (i * ny + j) * nz + k
                    let b = (i * ny + j + 1) * nz + k
                    guard wsum[a] > 0, wsum[b] > 0 else { continue }
                    let ta = tsdf[a], tb = tsdf[b]
                    guard ta * tb < 0 else { continue }
                    let f = ta / (ta - tb)         // chiziqli interpolyatsiya
                    let y = mins.y + (Float(j) + 0.5 + f) * vox
                    // MUHIM: shu yuza SHIFT/POL bo'lishi kerak, MEBEL emas.
                    // Busiz ustundagi shkaf usti (y≈1.2) "shift o'lchangan" deb
                    // hisoblanardi va 1.85 dagi HAQIQIY shift teshigi to'ldirilmasdan
                    // qorayib qolardi — foydalanuvchi aynan shuni ko'rdi. Tasma 0.6m:
                    // ko'p pog'onali shiftni (1.45 karniz + 1.85 asosiy, RoomPlan 1.96)
                    // qamraydi, lekin mebelni rad etadi.
                    guard abs(y - planeY) <= heightBand else { continue }
                    hmap[i * nz + k] = y
                    break
                }
            }
        }
        let measured = hmap.enumerated().filter { inPoly[$0.offset] && $0.element != unknown }.count
        let holes = hmap.enumerated().filter { inPoly[$0.offset] && $0.element == unknown }.count
        guard measured > 0 else {
            log?("PLANE[\(plane.label)] skip: o'lchangan yuza yo'q (bog'lanadigan narsa yo'q)")
            return 0
        }

        // 2) Teshik ustunlariga balandlikni qo'shnilardan tarqatamiz (dilatatsiya).
        var filled = hmap
        for _ in 0..<400 {
            var changed = false
            var next = filled
            for i in 0..<nx {
                for k in 0..<nz {
                    let idx = i * nz + k
                    guard inPoly[idx], filled[idx] == unknown else { continue }
                    var acc: Float = 0, n = 0
                    for (di, dk) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let ni = i + di, nk = k + dk
                        guard ni >= 0, nk >= 0, ni < nx, nk < nz else { continue }
                        let v = filled[ni * nz + nk]
                        if v != unknown { acc += v; n += 1 }
                    }
                    if n > 0 { next[idx] = acc / Float(n); changed = true }
                }
            }
            filled = next
            if !changed { break }
        }

        // 3) Faqat TESHIK ustunlarini quyamiz — o'lchangan ustunga TEGILMAYDI.
        var injected = 0
        for i in 0..<nx {
            for k in 0..<nz {
                let idx = i * nz + k
                guard inPoly[idx], hmap[idx] == unknown else { continue }   // teshik edi
                let h = filled[idx]
                guard h != unknown else { continue }
                let j0 = max(Int((h - trunc - mins.y) / vox) - 1, 0)
                let j1 = min(Int((h + trunc - mins.y) / vox) + 1, ny - 1)
                guard j0 <= j1 else { continue }
                for j in j0...j1 {
                    let y = mins.y + (Float(j) + 0.5) * vox
                    let t = (y - h) * (up ? 1 : -1)
                    guard abs(t) <= trunc else { continue }
                    let vi = (i * ny + j) * nz + k
                    guard wsum[vi] <= 0 else { continue }
                    tsdf[vi] = min(max(-t / trunc, -1), 1)
                    wsum[vi] = planeW
                    injected += 1
                }
            }
        }
        log?("PLANE[\(plane.label)] o'lchangan ustun=\(measured) teshik=\(holes) "
             + "inject=\(injected) voxel")
        return injected
    }

    private static func insideCutout(_ x: Float, _ y: Float,
                                     _ rects: [(min: SIMD2<Float>, max: SIMD2<Float>)]) -> Bool {
        for r in rects where x > r.min.x && x < r.max.x && y > r.min.y && y < r.max.y { return true }
        return false
    }

    /// Nuqta poligon ichidami (ray-casting, XZ tekisligida).
    private static func pointInPolygon(_ p: SIMD2<Float>, _ poly: [SIMD2<Float>]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xCross = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    // MARK: - Sof yadro (macOS'da test qilinadi)

    static func integrate(frames: [FreeSpaceCarver.DepthFrame],
                          planes: [WallPlane] = [],
                          log: ((String) -> Void)? = nil) -> LiDARMeshData? {
        // ===== 1. Chegara (depth namunalaridan) =====
        var sx: [Float] = [], sy: [Float] = [], sz: [Float] = []
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
                    sx.append(world.x); sy.append(world.y); sz.append(world.z)
                }
            }
        }
        guard sx.count >= 8 else { return nil }
        let rx = robustRange(&sx), ry = robustRange(&sy), rz = robustRange(&sz)
        var mins = SIMD3(rx.lo, ry.lo, rz.lo)
        var maxs = SIMD3(rx.hi, ry.hi, rz.hi)
        guard mins.x < maxs.x else { return nil }
        mins -= SIMD3(repeating: 0.12)
        maxs += SIMD3(repeating: 0.12)

        // ===== 2. Voxel o'lchami (xotira qopqog'i ostida eng mayda) =====
        // Voxel qopqog'i qurilma xotirasiga MOSLASHADI (jetsam OOM'ni oldini olish):
        // kam xotirali qurilma yirikroq voxel oladi (kamroq detal, lekin crash yo'q).
        let voxelCap = min(maxVoxels, MemoryBudget.current().maxVoxels)
        var vox = voxelStart
        var dims = SIMD3<Int>(0, 0, 0)
        while true {
            dims = SIMD3(Int(ceil((maxs.x - mins.x) / vox)),
                         Int(ceil((maxs.y - mins.y) / vox)),
                         Int(ceil((maxs.z - mins.z) / vox)))
            if dims.x * dims.y * dims.z <= voxelCap { break }
            vox *= 1.15
        }
        let total = dims.x * dims.y * dims.z
        let trunc: Float = max(0.045, vox * 3)
        log?("TSDF vox=\(String(format: "%.0f", vox * 1000))mm dims=\(dims.x)x\(dims.y)x\(dims.z) frames=\(frames.count)")

        // ===== 3. VAZNLI integratsiya (kadr ichida slab-parallel) =====
        var tsdf = [Float](repeating: 1, count: total)
        var wsum = [Float](repeating: 0, count: total)

        let sealedPlanes = planes.filter { $0.seal }
        tsdf.withUnsafeMutableBufferPointer { tPtr in
            wsum.withUnsafeMutableBufferPointer { wPtr in
                for f in frames {
                    let RT = f.R.transpose
                    let colX = RT * SIMD3<Float>(vox, 0, 0)
                    let colY = RT * SIMD3<Float>(0, vox, 0)
                    let colZ = RT * SIMD3<Float>(0, 0, vox)
                    let base0 = RT * (mins + SIMD3(repeating: vox / 2) - f.t)
                    let ny = dims.y, nz = dims.z
                    // Muhrlangan tekisliklar KAMERA fazosida (nurni kesish uchun).
                    let planesCam: [(n: SIMD3<Float>, c: SIMD3<Float>,
                                     x: SIMD3<Float>, y: SIMD3<Float>,
                                     hw: Float, hh: Float)] =
                        sealedPlanes.map { pl in
                            (RT * pl.normalOut, RT * (pl.center - f.t),
                             RT * pl.xAxis, RT * pl.yAxis,
                             pl.halfW + 0.10, pl.halfH + 0.10)
                        }

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
                                    // Muhrlangan tekislik ORTIdan kelgan o'qish —
                                    // tekislikda kesamiz (shisha = virtual qaytish).
                                    var dm = d
                                    for pc in planesCam {
                                        let denom = simd_dot(lc, pc.n)
                                        guard abs(denom) > 1e-6 else { continue }
                                        let sHit = simd_dot(pc.c, pc.n) / denom
                                        guard sHit > 0 else { continue }
                                        let zPlane = sHit * zc
                                        guard zPlane > minZ, dm > zPlane + trunc else { continue }
                                        let hit = lc * sHit - pc.c
                                        guard abs(simd_dot(hit, pc.x)) <= pc.hw,
                                              abs(simd_dot(hit, pc.y)) <= pc.hh else { continue }
                                        dm = zPlane
                                    }
                                    let sdf = dm - zc
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

        // ===== 3b. Struktura tekisliklari — faqat KUZATILMAGAN voxellarga =====
        if !planes.isEmpty {
            injectPlanes(planes, tsdf: &tsdf, wsum: &wsum, dims: dims, mins: mins,
                         vox: vox, trunc: trunc, log: log)
        }

        // ===== 4. Yuza + orientatsiya + silliqlash =====
        // weights=wsum: yuza faqat IKKALA vokseli ISHONCHLI kuzatilgan
        // (w>extractMinWeight) qirralarda — devor ortidagi soxta "orqa qobiq",
        // kuzatuv chegarasidagi "parda" va yakka-o'qish "konfetti" qobiqlari
        // chiqmaydi (Open3D valid-voxel extraction uslubi + vazn chegarasi).
        // Gisterezis: qabul qilinmagan voxellar wsum=0 bo'ladi, shuning uchun
        // extract endi chegarasiz (minWeight: 0) — filtr yuqorida bajarilgan.
        applyHysteresis(&wsum, dims: dims, low: hysteresisLow, high: hysteresisHigh, log: log)
        var mesh = SurfaceNets.extract(tsdf: tsdf, dims: dims, mins: mins, vox: vox,
                                       weights: wsum, minWeight: 0)
        // ISHONCH: har cho'qqi ostidagi TSDF vazni. Kam kuzatilgan joy g'ijim
        // chiqadi va ekranda "parcha" bo'lib ko'rinadi — o'lchandi (skan #26,
        // yakuniy mesh): haqiqiy yuzada qo'shni bilan normal farqi 0.002, ko'rilmagan
        // to'ldirishda 0.435 (~62°). Rangi aybdor emas (devor bilan RGB masofa 12) —
        // ular SHAKLI bilan ajralib turadi.
        //
        // NEGA VAZN ISHONCHLI MEZON (o'lchandi, 401 kadr bo'yicha kuzatuv sanog'i):
        // haqiqiy yuzani median 17 ta kamera ko'rgan, parchalarni 0-1 ta.
        // "3 tadan kam" chegarasi parchalarning 55.8% ini tutadi va haqiqiy yuzaning
        // atigi 1.6% iga tegadi.
        //
        // O'CHIRISH EMAS, SILLIQLASH: o'chirish teshik qoldiradi (sinab ko'rilgan —
        // ekranda qora nuqta bo'lib chiqdi). Silliqlash esa parchani devorga singdiradi.
        let conf = vertexConfidence(mesh: mesh, wsum: wsum, dims: dims, mins: mins, vox: vox)
        tsdf = []; wsum = []
        mesh = smoothLowConfidence(mesh, conf: conf, log: log)
        // Qisqartirishdan keyin takrorlash uchun saqlab qo'yamiz.
        confSamples = (pos: mesh.positions, conf: conf)
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
    /// Ishonch chegarasi (TSDF vazni ≈ kuzatuv soni). Bundan past — g'ijim zona.
    private static let lowConfWeight: Float = 3.0

    /// Xom meshning cho'qqi ishonchi — DETSIMATSIYADAN KEYIN qayta silliqlash uchun.
    ///
    /// NEGA KERAK (o'lchandi, skan #26): silliqlash xom meshda zo'r ishlaydi
    /// (rough p90 0.082 -> 0.044), lekin `decimate` uni buzadi: p50 0.0002 -> 0.0061
    /// (30x), p90 0.044 -> 0.218 (5x). Ya'ni g'ijimlikning asosiy manbai —
    /// qisqartirish, va u silliqlashdan KEYIN ishlaydi. Shuning uchun ishonchni
    /// saqlab qo'yamiz va qisqartirilgan meshda takrorlaymiz.
    private static var confSamples: (pos: [SIMD3<Float>], conf: [Float])?

    /// Qisqartirilgan meshni ishonch bo'yicha qayta silliqlaydi (xom mesh ishonchini
    /// eng yaqin cho'qqidan oladi). `build` chaqirilmagan bo'lsa — tegilmaydi.
    static func smoothLowConfidenceAfterDecimation(_ mesh: LiDARMeshData,
                                                   log: ((String) -> Void)?) -> LiDARMeshData {
        guard lowConfPasses > 0, let s = confSamples, !s.pos.isEmpty,
              !mesh.positions.isEmpty else { return mesh }
        // Fazoviy hash: xom cho'qqilarni 10sm katakka joylaymiz.
        let cell: Float = 0.10
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> {
            SIMD3(Int32((p.x / cell).rounded(.down)),
                  Int32((p.y / cell).rounded(.down)),
                  Int32((p.z / cell).rounded(.down)))
        }
        var grid = [SIMD3<Int32>: [Int]]()
        for (i, p) in s.pos.enumerated() { grid[key(p), default: []].append(i) }
        let n = mesh.vertexCount
        var conf = [Float](repeating: lowConfWeight, count: n)
        for i in 0..<n {
            let p = SIMD3(mesh.positions[i * 3], mesh.positions[i * 3 + 1], mesh.positions[i * 3 + 2])
            let k = key(p)
            var best = Float.greatestFiniteMagnitude
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        guard let bucket = grid[SIMD3(k.x + Int32(dx), k.y + Int32(dy),
                                                      k.z + Int32(dz))] else { continue }
                        for j in bucket {
                            let d = simd_length_squared(s.pos[j] - p)
                            if d < best { best = d; conf[i] = s.conf[j] }
                        }
                    }
                }
            }
        }
        var alpha = [Float](repeating: 0, count: n)
        var touched = 0
        for i in 0..<n {
            let t = max(0, min(1, (lowConfWeight - conf[i]) / lowConfWeight))
            alpha[i] = t * lowConfAlpha
            if t > 0 { touched += 1 }
        }
        guard touched > 0 else { return mesh }
        var nbr = [[Int]](repeating: [], count: n)
        var f = 0
        while f + 2 < mesh.indices.count {
            let a = Int(mesh.indices[f]), b = Int(mesh.indices[f + 1]), c = Int(mesh.indices[f + 2])
            nbr[a].append(b); nbr[a].append(c)
            nbr[b].append(a); nbr[b].append(c)
            nbr[c].append(a); nbr[c].append(b)
            f += 3
        }
        var pos = mesh.positions
        for _ in 0..<lowConfPasses {
            var next = pos
            for i in 0..<n where alpha[i] > 0.001 {
                let ns = nbr[i]
                guard !ns.isEmpty else { continue }
                var ax: Float = 0, ay: Float = 0, az: Float = 0
                for j in ns { ax += pos[j * 3]; ay += pos[j * 3 + 1]; az += pos[j * 3 + 2] }
                let c = Float(ns.count)
                next[i * 3]     = pos[i * 3]     + (ax / c - pos[i * 3]) * alpha[i]
                next[i * 3 + 1] = pos[i * 3 + 1] + (ay / c - pos[i * 3 + 1]) * alpha[i]
                next[i * 3 + 2] = pos[i * 3 + 2] + (az / c - pos[i * 3 + 2]) * alpha[i]
            }
            pos = next
        }
        var out = mesh
        out.positions = pos
        log?("PASTISHONCH (detsimatsiyadan keyin): cho'qqi=\(touched)/\(n) "
             + "(\(String(format: "%.1f", Float(touched) / Float(n) * 100))%)")
        return out
    }
    /// Silliqlash kuchi va takrorlar soni (UserDefaults "lowConfSmooth", 0 -> o'chiq).
    private static var lowConfPasses: Int {
        if UserDefaults.standard.object(forKey: "lowConfSmooth") == nil { return 8 }
        return UserDefaults.standard.integer(forKey: "lowConfSmooth")
    }
    private static let lowConfAlpha: Float = 0.6

    /// Har cho'qqi ostidagi TSDF vaznini o'qiydi (ishonch).
    private static func vertexConfidence(mesh: SurfaceNets.Mesh, wsum: [Float],
                                         dims: SIMD3<Int>, mins: SIMD3<Float>,
                                         vox: Float) -> [Float] {
        let ny = dims.y, nz = dims.z
        var out = [Float](repeating: 0, count: mesh.positions.count)
        for (k, p) in mesh.positions.enumerated() {
            let i = Int((p.x - mins.x) / vox), j = Int((p.y - mins.y) / vox)
            let l = Int((p.z - mins.z) / vox)
            guard i >= 0, i < dims.x, j >= 0, j < ny, l >= 0, l < nz else { continue }
            out[k] = wsum[(i * ny + j) * nz + l]
        }
        return out
    }

    /// Ishonchi past cho'qqilarni qo'shnilariga tortadi (Laplas), ishonchlisiga tegmaydi.
    private static func smoothLowConfidence(_ mesh: SurfaceNets.Mesh, conf: [Float],
                                            log: ((String) -> Void)?) -> SurfaceNets.Mesh {
        let passes = lowConfPasses
        guard passes > 0, !mesh.positions.isEmpty, conf.count == mesh.positions.count
        else { log?("PASTISHONCH silliqlash o'chiq"); return mesh }
        // Har cho'qqi uchun kuch: ishonch 0 -> to'liq, lowConfWeight -> 0.
        var alpha = [Float](repeating: 0, count: mesh.positions.count)
        var touched = 0
        for i in 0..<alpha.count {
            let t = max(0, min(1, (lowConfWeight - conf[i]) / lowConfWeight))
            alpha[i] = t * lowConfAlpha
            if t > 0 { touched += 1 }
        }
        guard touched > 0 else { return mesh }
        // Qo'shnilar (qirra bo'yicha).
        var nbr = [[Int]](repeating: [], count: mesh.positions.count)
        var f = 0
        while f + 2 < mesh.faces.count {
            let a = Int(mesh.faces[f]), b = Int(mesh.faces[f + 1]), c = Int(mesh.faces[f + 2])
            nbr[a].append(b); nbr[a].append(c)
            nbr[b].append(a); nbr[b].append(c)
            nbr[c].append(a); nbr[c].append(b)
            f += 3
        }
        var pos = mesh.positions
        for _ in 0..<passes {
            var next = pos
            for i in 0..<pos.count where alpha[i] > 0.001 {
                let ns = nbr[i]
                guard !ns.isEmpty else { continue }
                var acc = SIMD3<Float>.zero
                for j in ns { acc += pos[j] }
                let mean = acc / Float(ns.count)
                next[i] = pos[i] + (mean - pos[i]) * alpha[i]
            }
            pos = next
        }
        var out = mesh
        out.positions = pos
        log?("PASTISHONCH silliqlash: cho'qqi=\(touched)/\(mesh.positions.count) "
             + "(\(String(format: "%.1f", Float(touched) / Float(mesh.positions.count) * 100))%) "
             + "passes=\(passes)")
        return out
    }

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
