import Foundation
import CoreGraphics
import ImageIO
import simd

/// Ko'rilmagan atlas hududlarini atrofdagi yuza rangi bilan bo'yash (inpainting).
///
/// ILDIZ (haqiqiy skanda o'lchangan, skan 20260717-110900): texrecon BARCHA
/// ko'rilmagan yuzalarga BITTA 3x3 piksel patch beradi va hammasiga AYNAN bir xil
/// UV yozadi (generate_texture_patches.cpp: `projections[] = {{2,1},{1,1},{1,2}}`).
/// O'sha skanda 19416 yuza (7.5 m² — devor, pol va potolok BIRGA) bitta UV nuqtaga
/// ishora qilgan → hammasiga bitta rang: RGB(2,16,42), ekranda QORA. Ya'ni patch
/// ichida bo'yash printsipial befoyda — 3 tekselga qancha rang yozsang ham,
/// oxirgisi yutadi.
///
/// Shuning uchun yo'l ikki bosqichli:
///   1. `detectSharedPatch` — ko'rilmagan yuzalar STRUKTURA bo'yicha topiladi
///      (minglab yuza bitta UV uchligini ulashsa — o'sha patch). RANG bo'yicha
///      topib BO'LMAYDI: patch 140 kulrang bilan to'ldirilsa ham, seam-leveling
///      uni 140±3 oynasidan chiqarib yuboradi (o'lchandi: RGB(2,16,42)).
///   2. `megachartUnseen` — har klasterga YANGI sahifada (room_unseen.png) o'z
///      UV-charti; urug' aynan umumiy qirra bo'ylab qo'shnining atlasidan olinadi,
///      ustidan pull-push + Gauss. Natijada devor devor rangini, pol pol rangini
///      oladi va zona silliq "eriydi" (Polycam eksportidagidek).
/// Megachart ko'chirmagan qoldiq (haqiqiy 140-kulrang fill_hole yamoqlari) eski
/// yo'lda — mesh-qo'shnilardan IDW gradient bilan — bo'yaladi.
///
/// UV-Y konvensiyasi (flip) `decideFlipY`da STRUKTURA bo'yicha aniqlanadi.
enum AtlasInpainter {

    /// texrecon unseen fill: 0.55 * 255 = 140.25 → 140.
    private static let grayValue = 140
    private static let grayTol = 3

    // MARK: - Kirish nuqtasi

    static func run(objURL: URL, planes: [TSDFGeometry.WallPlane] = [],
                    log: (String) -> Void) {
        guard let model = parseOBJ(objURL: objURL) else {
            log("INPAINT skip: obj/mtl o'qilmadi"); return
        }
        var atlases: [Atlas] = []
        for texURL in model.textureURLs {
            guard let a = Atlas(url: texURL) else { log("INPAINT skip: atlas o'qilmadi \(texURL.lastPathComponent)"); return }
            atlases.append(a)
        }
        guard !atlases.isEmpty else { log("INPAINT skip: atlas yo'q"); return }

        // Ko'rinmagan yuzalar = STRUKTURA (ulashilgan UV uchligi — texrecon'ning
        // umumiy 3x3 patchi) ∪ eski RANG detektori (haqiqiy fill_hole kulrangi).
        let shared = detectSharedPatch(model: model)
        let flipY = decideFlipY(model: model, atlases: atlases, exclude: shared, log: log)
        let grayFaces = detectGray(model: model, atlases: atlases, flipY: flipY)
        var unseenSet = Set(grayFaces)
        unseenSet.formUnion(shared)
        let unseenFaces = unseenSet.sorted()
        guard !unseenFaces.isEmpty else { log("INPAINT: ko'rinmagan yuza topilmadi"); return }

        // Yuza normallari — klasterlash va urug'lash YO'NALISH bo'yicha ajralsin.
        var nrm = [SIMD3<Float>](repeating: SIMD3(0, 1, 0), count: model.faces.count)
        if !model.positions.isEmpty {
            for (fi, f) in model.faces.enumerated() {
                guard f.v.0 < model.positions.count, f.v.1 < model.positions.count,
                      f.v.2 < model.positions.count else { continue }
                let a = model.positions[f.v.0], b = model.positions[f.v.1], c = model.positions[f.v.2]
                let n = simd_cross(b - a, c - a)
                let l = simd_length(n)
                if l > 1e-9 { nrm[fi] = n / l }
            }
        }

        // Har ko'rinmagan yuzani RoomPlan TEKISLIGIGA bog'laymiz — klaster shu
        // yorliq bo'yicha ajraladi. Bu shovqinga chidamli: yuzaning MA'LUM
        // tekislikka nisbatan joyi ishlatiladi, lokal normal emas.
        // HAMMA yuzaga yorliq: ko'rinmaganlar klasterlash uchun, TEKSTURALILARI esa
        // "o'sha devordan urug' olish" uchun kerak (busiz seedFromPlane manbasiz qoladi).
        // `weakFaces` — tekislikka mos, lekin bo'lagi mayda bo'lganlar. Ular rang
        // QABUL QILADI (chart oladi), lekin cho'zish MANBAI bo'lolmaydi.
        var weakFaces = Set<Int>()
        let planeLabel = labelByPlane(model: model, faces: Array(0..<model.faces.count),
                                      nrm: nrm, planes: planes, weak: &weakFaces)
        if weakPlaneFill {
            var wa: Float = 0
            for f in weakFaces { wa += faceArea(model.faces[f], model: model) }
            log("ZAIF tekislik bo'lagi: yuza=\(weakFaces.count) "
                + "(\(String(format: "%.2f", wa)) m²) — chart oladi, manba bo'lmaydi")
        }

        // Ko'rinmagan hududlar (union-find, umumiy qirra bo'yicha).
        var parent = [Int](repeating: -1, count: model.faces.count)
        for f in unseenFaces { parent[f] = f }
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != r { let n = parent[c]; parent[c] = r; c = n }
            return r
        }
        var edgeMap = [Int64: (face: Int, a: Int, b: Int)]()   // qirra -> birinchi yuza
        // Ko'rinmagan yuza -> teksturali qo'shni + UMUMIY QIRRA cho'qqilari.
        // Qirra cho'qqilari megachart uchun shart: urug' aynan qirra bo'ylab
        // qo'shnining atlasidan olinadi ("obyekt davomi").
        var neighborsOf = [Int: [(tex: Int, a: Int, b: Int)]]()
        @inline(__always) func ekey(_ a: Int, _ b: Int) -> Int64 {
            a < b ? (Int64(a) << 32 | Int64(b)) : (Int64(b) << 32 | Int64(a))
        }
        let isUnseen = unseenSet
        for (fi, face) in model.faces.enumerated() {
            let pairs = [(face.v.0, face.v.1), (face.v.1, face.v.2), (face.v.2, face.v.0)]
            for (pa, pb) in pairs {
                let e = ekey(pa, pb)
                if let other = edgeMap[e] {
                    let og = isUnseen.contains(other.face), fg = isUnseen.contains(fi)
                    if og && fg {
                        // Bu yerda normal bo'yicha AJRATMAYMIZ. Sinab ko'rildi va
                        // o'lchov RAD ETDI: juftlik-normal darvozasi (hatto 0.8 da)
                        // qo'shnilik qirralarining 22% ini kesadi va graf perkolyatsiya
                        // chegarasida parchalanadi — klaster 1355 -> 12399 (o'rtacha 7
                        // feys), ulkan dog' esa 32.8 -> 11.9 m² gina kamayadi. Ya'ni
                        // narxi katta, foydasi kam. Ishlaydigan asbob — RoomPlan
                        // TEKISLIGI yorlig'i (o'lchandi: 6676 klaster, eng katta 6.1 m²).
                        let ro = find(other.face), rf = find(fi)
                        if ro != rf { parent[ro] = rf }
                    } else if og != fg {
                        let unseen = og ? other.face : fi
                        let tex = og ? fi : other.face
                        neighborsOf[unseen, default: []].append((tex, pa, pb))
                    }
                } else {
                    edgeMap[e] = (fi, pa, pb)
                }
            }
        }

        // ===== MEGACHART: ko'rinmagan klasterlarga O'Z UV-charti =====
        // Shusiz har qanday bo'yash BEFOYDA: 19416 yuza bitta 3x3 patchni ulashsa,
        // ularni qanday bo'yamaylik — hammasiga BITTA rang tushadi (oxirgi yozgan
        // yutadi). Chart bo'lgach, devor devor rangini, pol pol rangini oladi.
        // Klaster = bog'langan bo'lak; 3 m² dan kattasi tekislik bo'yicha bo'linadi.
        //
        // BIRLASHTIRISH SINALDI (foydalanuvchi taklifi: "uchburchak to'ldirishlar
        // kerak emas") va O'LCHOV IKKI SHAKLDA HAM RAD ETDI:
        //   - har yuzaga 1 chart (37 chart): lokallik 17.8 -> 34.6. Obyekt TEKIS
        //     EMAS, uni bitta tekislikka proyeksiya qilsa UV BUKLANADI.
        //   - faqat tekis yuzalar birlashsa (955 chart): 17.8 -> 20.3. Devordagi
        //     ko'rinmagan dog'lar TARQOQ — bitta ulkan siyrak chart yomon to'ladi.
        // Ya'ni chart chegaralari muammosi shu arxitekturada hal bo'lmaydi; to'g'ri
        // yechim — har zonaga HAQIQIY UV-unwrap (LSCM/SLIM), alohida ish.
        var clusterOf = [Int: [Int]]()
        for f in unseenFaces { clusterOf[find(f), default: []].append(f) }
        var clusters: [[Int]] = []
        for c in clusterOf.values {
            var a: Float = 0
            for f in c { a += faceArea(model.faces[f], model: model) }
            if a <= clusterSplitArea || planes.isEmpty { clusters.append(c); continue }
            var byLabel = [Int: [Int]]()
            for f in c { byLabel[planeLabel[f], default: []].append(f) }
            if byLabel.count <= 1 { clusters.append(c); continue }
            for (_, sub) in byLabel { clusters.append(contentsOf: splitConnected(sub, model: model)) }
        }

        // Kill-switch (qurilmada A/B uchun): UserDefaults "megachart" = false ->
        // eski xatti-harakat (hamma ko'rinmagan zona bitta rang).
        let megaON = UserDefaults.standard.object(forKey: "megachart") as? Bool ?? true
        let megaON2 = megaON && !model.positions.isEmpty
        // TEKIS yuzalar (devor/pol/shift) -> chart + real teksturani cho'zish.
        // OBYEKTLAR -> chart YO'Q, per-vertex silliq rang (pastdagi izohga qarang).
        let planarClusters = clusters.filter { planeLabel[$0[0]] >= 0 }
        let objectFaces = clusters.filter { planeLabel[$0[0]] < 0 }.flatMap { $0 }

        var movedFaces = Set<Int>()
        var appendBlock = ""
        var removedLines = Set<Int>()
        if megaON2, !planarClusters.isEmpty,
           let mega = megachartUnseen(objURL: objURL, model: model, atlases: atlases,
                                      flipY: flipY, clusters: planarClusters,
                                      neighborsOf: neighborsOf, nrm: nrm,
                                      planeLabel: planeLabel, unseenSet: unseenSet,
                                      weakFaces: weakFaces, log: log) {
            movedFaces.formUnion(mega.movedFaces)
            removedLines.formUnion(mega.movedLines)
            appendBlock += mega.objAppend
        }
        // OBYEKTLARNING ko'rinmagan yuzasi — ikki variant (tumbler `dropObjectFill`):
        //   true  -> BUTUNLAY o'chiriladi (havoda osilgan yuza, halol teshik);
        //   false -> per-vertex silliq rang (chartsiz).
        //
        // Foydalanuvchi qarori: hozircha per-vertex (default false). O'chirish
        // varianti kod sifatida qoladi — render'da tekshirilgan: `unseen_mat` ni
        // olib tashlaganda kuller/stol atrofidagi uchburchak parchalar yo'qoladi.
        // Tekis yuzalar (devor/pol/shift) BOSHQA gap: u yerda cho'zish ishlaydi
        // (foydalanuvchi: "devor zo'r chiqibti, sezilmagan ham").
        let dropObjects = UserDefaults.standard.object(forKey: "dropObjectFill") as? Bool ?? false
        if megaON2, !objectFaces.isEmpty, dropObjects {
            var area: Float = 0
            for f in objectFaces {
                removedLines.insert(model.faces[f].line)
                movedFaces.insert(f)
                area += faceArea(model.faces[f], model: model)
            }
            log("OBYEKT to'ldirish O'CHIRILDI: yuza=\(objectFaces.count) "
                + "(\(String(format: "%.2f", area)) m²) — tekislikda emas, halol teshik")
        } else if megaON2, !objectFaces.isEmpty,
           let vc = vertexColorUnseen(model: model, atlases: atlases, flipY: flipY,
                                      faces: objectFaces, neighborsOf: neighborsOf, nrm: nrm,
                                      vtLineBase: model.vtLineCount, vBase: model.vLineCount,
                                      log: log) {
            movedFaces.formUnion(vc.movedFaces)
            removedLines.formUnion(vc.movedLines)
            appendBlock += vc.objAppend
        }
        if !removedLines.isEmpty {
            rewriteOBJ(objURL: objURL, model: model,
                       removedLines: removedLines, append: appendBlock, log: log)
        }

        // Megachart ko'chirmagan ko'rinmagan yuzalar — eski joyida bo'yaladi.
        let leftover = unseenFaces.filter { !movedFaces.contains($0) }

        // Har hudud chegarasidagi teksturali yuzalardan namunalar:
        // 3D pozitsiya (gradient uchun) + median rang.
        let hasPositions = !model.positions.isEmpty
        var regionSamples = [Int: [(pos: SIMD3<Float>, color: SIMD3<Float>)]]()
        for f in leftover {
            guard let texNbrs = neighborsOf[f] else { continue }
            let root = find(f)
            for (tn, _, _) in texNbrs {
                let face = model.faces[tn]
                let atlas = atlases[face.mat]
                var cols: [(UInt8, UInt8, UInt8)] = []
                for s in samplePoints(face: face, model: model) {
                    if let c = atlas.sample(uv: s, flipY: flipY), !isGrayColor(c) {
                        cols.append(c)
                    }
                }
                guard !cols.isEmpty else { continue }
                let m = medianColor(cols)
                var pos = SIMD3<Float>(repeating: 0)
                if hasPositions,
                   face.v.0 < model.positions.count, face.v.1 < model.positions.count,
                   face.v.2 < model.positions.count {
                    pos = (model.positions[face.v.0] + model.positions[face.v.1]
                           + model.positions[face.v.2]) / 3
                }
                regionSamples[root, default: []].append(
                    (pos, SIMD3(Float(m.0), Float(m.1), Float(m.2)) / 255))
            }
        }
        // Zaxira tekis rang (kanal bo'yicha median) — yakka namunali hududlar uchun.
        var regionColor = [Int: SIMD3<Float>]()
        for (root, samples) in regionSamples where !samples.isEmpty {
            let r = samples.map { $0.color.x }.sorted()
            let g = samples.map { $0.color.y }.sorted()
            let b = samples.map { $0.color.z }.sorted()
            regionColor[root] = SIMD3(r[r.count / 2], g[g.count / 2], b[b.count / 2])
        }
        guard !regionColor.isEmpty else {
            // Megachart ishlagan bo'lsa bu normal: ko'rinmagan yuzalar allaqachon
            // yangi sahifaga ko'chgan, eski joyda bo'yashga narsa qolmagan.
            log("INPAINT: eski yo'lda bo'yaladigan hudud yo'q " +
                "(ko'chgan=\(movedFaces.count), qolgan=\(leftover.count))")
            return
        }

        // Qayta bo'yash — per-vertex IDW gradient ("cho'zilgan/blurry" effekt).
        var painted = 0
        var vCache = [Int64: SIMD3<Float>]()
        func vertexColor(root: Int, v: Int,
                         samples: [(pos: SIMD3<Float>, color: SIMD3<Float>)],
                         flat: SIMD3<Float>) -> SIMD3<Float> {
            guard hasPositions, samples.count > 1, v < model.positions.count else { return flat }
            let key = Int64(root) << 32 | Int64(v)
            if let c = vCache[key] { return c }
            let p = model.positions[v]
            var acc = SIMD3<Float>(repeating: 0); var wsum: Float = 0
            for s in samples {
                let w = 1 / (simd_distance_squared(p, s.pos) + 1e-3)
                acc += s.color * w; wsum += w
            }
            let c = wsum > 0 ? acc / wsum : flat
            vCache[key] = c
            return c
        }
        // Hudud kattaligi — katta yamoqlar kuchliroq blur oladi (2c).
        var regionFaceCount = [Int: Int]()
        for f in leftover { regionFaceCount[find(f), default: 0] += 1 }
        let largeRegionFaces = 60

        for f in leftover {
            let root = find(f)
            guard let flat = regionColor[root], let samples = regionSamples[root] else { continue }
            let face = model.faces[f]
            let colors = (vertexColor(root: root, v: face.v.0, samples: samples, flat: flat),
                          vertexColor(root: root, v: face.v.1, samples: samples, flat: flat),
                          vertexColor(root: root, v: face.v.2, samples: samples, flat: flat))
            atlases[face.mat].rasterize(face: face, model: model, flipY: flipY, colors: colors,
                                        large: (regionFaceCount[root] ?? 0) > largeRegionFaces)
            painted += 1
        }
        // "Fokusdan chiqqan" yumshoqlik: bo'yalgan piksellar blur qilinadi —
        // o'qishda atrofdagi o'tkir tekstura ham qatnashadi (chegara silliq
        // quyiladi), yozish faqat maska ichida. Katta yamoqlar qo'shimcha
        // kuchliroq eriydi.
        for a in atlases where a.dirty { a.blurPainted(radius: 2, passes: 2, onlyLarge: false) }
        for a in atlases where a.dirty { a.blurPainted(radius: 4, passes: 1, onlyLarge: true) }
        // Kengayish: bo'yalganlar atrofidagi qolgan SOF kulrang piksellarga 2px
        // (UV chegara seam'lari uchun padding).
        for a in atlases where a.dirty { a.dilateIntoGray(passes: 2) }

        var saved = 0
        for a in atlases where a.dirty { if a.save() { saved += 1 } }
        log("INPAINT unseen=\(unseenFaces.count) (struktura=\(shared.count) kulrang=\(grayFaces.count)) " +
            "megachart=\(movedFaces.count) painted=\(painted) regions=\(regionColor.count) " +
            "flipY=\(flipY) atlas=\(saved)")
    }

    // MARK: - Kulrang aniqlash

    private static func isGrayColor(_ c: (UInt8, UInt8, UInt8)) -> Bool {
        abs(Int(c.0) - grayValue) <= grayTol &&
        abs(Int(c.1) - grayValue) <= grayTol &&
        abs(Int(c.2) - grayValue) <= grayTol
    }

    /// Yuzaning UV namuna nuqtalari: markaz + 3 qirra o'rtasi.
    private static func samplePoints(face: Face, model: Model) -> [SIMD2<Float>] {
        let a = model.uvs[face.t.0], b = model.uvs[face.t.1], c = model.uvs[face.t.2]
        return [(a + b + c) / 3, (a + b) / 2, (b + c) / 2, (c + a) / 2]
    }

    private static func detectGray(model: Model, atlases: [Atlas], flipY: Bool) -> [Int] {
        var gray: [Int] = []
        for (fi, face) in model.faces.enumerated() {
            let atlas = atlases[face.mat]
            var all = true
            for s in samplePoints(face: face, model: model) {
                guard let c = atlas.sample(uv: s, flipY: flipY), isGrayColor(c) else { all = false; break }
            }
            if all { gray.append(fi) }
        }
        return gray
    }

    /// Atlas FONI (chartlar orasidagi bo'sh joy) — urug' qilinmaydi.
    ///
    /// Chegara 8, 40 EMAS: donor 40 ni "qora loskut tarqalmasin" deb qo'ygan edi,
    /// lekin bu xonaning potologi HAQIQATAN to'q siyoh (o'lchandi: RGB(26,35,32))
    /// — 40 bilan uning urug'lari rad etilib, ko'rinmagan potolok qo'shnisidan
    /// ~50-80 birlik OCHROQ chiqardi (o'lchandi). Fon esa aynan (0,0,0), shuning
    /// uchun 8 uni ham ushlaydi, haqiqiy to'q yuzani ham saqlaydi.
    private static func isAtlasBackground(_ c: (UInt8, UInt8, UInt8)) -> Bool {
        c.0 < 8 && c.1 < 8 && c.2 < 8
    }

    /// Berilgan pozitsiya indeksiga mos UV indeksi (yuza ichida).
    private static func uvIndex(of vertexIdx: Int, in face: Face) -> Int? {
        if face.v.0 == vertexIdx { return face.t.0 }
        if face.v.1 == vertexIdx { return face.t.1 }
        if face.v.2 == vertexIdx { return face.t.2 }
        return nil
    }

    // MARK: - Ko'rinmagan yuzalarni STRUKTURA bo'yicha aniqlash

    /// texrecon BARCHA ko'rinmagan yuzalarga BITTA 3x3px patch beradi va ularning
    /// hammasiga AYNAN bir xil UV uchligini yozadi (generate_texture_patches.cpp:
    /// `projections[] = {{2,1},{1,1},{1,2}}`). Ya'ni "minglab yuza bitta UV
    /// uchligini ulashsa — bu o'sha patch".
    ///
    /// Nega RANG bo'yicha topib bo'lmaydi: patch 0.55 kulrang (140) bilan
    /// to'ldiriladi, lekin keyin seam-leveling o'sha 3 tekselga minglab yuzaning
    /// qarama-qarshi tuzatishini qo'shadi va rang 140 dan chiqib ketadi (haqiqiy
    /// skanda o'lchandi: RGB(2,16,42) — 140±3 oynasidan uzoq). Shuning uchun
    /// detektor rangga UMUMAN qaramaydi.
    private static let sharedPatchMinFaces = 200

    /// Tekislik bo'yicha bo'linadigan minimal klaster yuzasi (m²). Kichigini
    /// bo'lish ZARARLI — o'lchandi: bo'laklarning urug' qamrovi kamayadi va
    /// lokallik xatosi 18.8 -> 25.1 bo'ladi. Katta klaster esa aynan muammo:
    /// tekislik to'ldirishdan keyin devor+pol+shift bitta 32.8 m² qobiqqa slipadi.
    private static let clusterSplitArea: Float = 3.0

    /// Urug' olinadigan teksturali qo'shni normali mosligi (cos). 0.8 ≈ 37°.
    /// Devor burchakda shift/pol bilan qirra ulashadi — busiz shift rangi devorga
    /// oqib o'tadi. Bu FAQAT urug' manbaini filtrlaydi, klasterlashga tegmaydi
    /// (klasterni normal bo'yicha kesish o'lchovda rad etilgan — pastga qarang).
    private static let seedNormalDot: Float = 0.8

    private static func detectSharedPatch(model: Model) -> Set<Int> {
        var groups = [SIMD3<Int32>: [Int]]()
        for (fi, face) in model.faces.enumerated() {
            let key = SIMD3(Int32(face.t.0), Int32(face.t.1), Int32(face.t.2))
            groups[key, default: []].append(fi)
        }
        var out = Set<Int>()
        for (_, faces) in groups where faces.count >= sharedPatchMinFaces {
            out.formUnion(faces)
        }
        return out
    }

    /// UV-Y konvensiyasini (flip) ANIQLAYDI — rangdan mustaqil, strukturaga tayangan.
    ///
    /// Ilgari bu "qaysi variant ko'proq kulrang topsa" bo'yicha tanlanardi; kulrang
    /// yuzalar bir necha o'nta bo'lgani uchun tanlov SHOVQINGA qolgan edi (haqiqiy
    /// skanda noto'g'ri `false` tanlagan). To'g'ri mezon: TEKSTURALI yuzalar
    /// to'g'ri konvensiyada chart ICHIGA, noto'g'risida atlas FONIGA (qora) tushadi.
    /// O'lchov: to'g'risida qora 5.4%, teskarisida 30.9% — ishonchli farq.
    private static func decideFlipY(model: Model, atlases: [Atlas], exclude: Set<Int>,
                                    log: (String) -> Void) -> Bool {
        var blackTrue = 0, blackFalse = 0, n = 0
        let step = max(1, model.faces.count / 20_000)
        for fi in stride(from: 0, to: model.faces.count, by: step) where !exclude.contains(fi) {
            let face = model.faces[fi]
            let uv = (model.uvs[face.t.0] + model.uvs[face.t.1] + model.uvs[face.t.2]) / 3
            let a = atlases[face.mat]
            if let c = a.sample(uv: uv, flipY: true), isAtlasBackground(c) { blackTrue += 1 }
            if let c = a.sample(uv: uv, flipY: false), isAtlasBackground(c) { blackFalse += 1 }
            n += 1
        }
        // Aniq farq bo'lsa — strukturaga ishonamiz.
        let lo = min(blackTrue, blackFalse), hi = max(blackTrue, blackFalse)
        if n > 0, hi > 0, Float(lo) < Float(hi) * 0.8 {
            let f = blackTrue < blackFalse
            log("INPAINT flipY=\(f) (fon namunasi: true=\(blackTrue) false=\(blackFalse) / \(n))")
            return f
        }
        // Farq yo'q — eski kulrang evristikasi (zaxira).
        let gt = detectGray(model: model, atlases: atlases, flipY: true).count
        let gf = detectGray(model: model, atlases: atlases, flipY: false).count
        log("INPAINT flipY zaxira: kulrang true=\(gt) false=\(gf)")
        return gt >= gf
    }

    // MARK: - Obyekt: per-vertex rang (chartsiz)

    /// Diffuziya iteratsiyalari — obyekt yuzasi bo'ylab rang tarqalishi.
    private static let vcIterations = 200

    /// OBYEKTLARNI chartsiz bo'yaydi: har cho'qqiga rang, mesh bo'ylab silliq.
    ///
    /// NEGA CHARTSIZ: obyekt TEKIS EMAS. Uni tekislikka proyeksiya qilsak UV
    /// buklanadi (o'lchandi: bitta chartga solganda lokallik 17.8 -> 34.6), mayda
    /// chartlarga bo'lsak — har chart bitta DOG' bo'lib ko'rinadi va ular orasida
    /// rang sakraydi (o'lchandi: chart ichida 2.9, chartlar orasida 29-86). Ya'ni
    /// "klasterni tekislikka proyeksiya qilish" arxitekturasi obyektga printsipial
    /// yaramaydi. Cho'qqi rangida esa chart YO'Q -> chegara yo'q -> chok yo'q ->
    /// faset yo'q; render uchburchak ichida rangni o'zi interpolyatsiya qiladi.
    /// Mesh zich (~3sm uchburchak), shuning uchun natija silliq bo'ladi.
    /// Naqsh yo'qoladi — obyektga u kerak emas, "hira va uyg'un" kerak.
    private static func vertexColorUnseen(model: Model, atlases: [Atlas], flipY: Bool,
                                          faces: [Int],
                                          neighborsOf: [Int: [(tex: Int, a: Int, b: Int)]],
                                          nrm: [SIMD3<Float>],
                                          vtLineBase: Int, vBase: Int,
                                          log: (String) -> Void)
        -> (movedFaces: Set<Int>, movedLines: Set<Int>, objAppend: String, vAdded: Int)? {
        guard !faces.isEmpty else { return nil }
        let faceSet = Set(faces)

        // 1) Urug': ko'rinmagan yuza va TEKSTURALI qo'shni umumiy qirrasi.
        var acc = [Int: SIMD3<Float>](), wgt = [Int: Float]()
        for f in faces {
            guard let edges = neighborsOf[f] else { continue }
            for (tn, va, vb) in edges where simd_dot(nrm[f], nrm[tn]) > seedNormalDot {
                let tface = model.faces[tn]
                for v in [va, vb] {
                    guard let ti = uvIndex(of: v, in: tface),
                          let cs = atlases[tface.mat].sample(uv: model.uvs[ti], flipY: flipY),
                          !isGrayColor(cs), !isAtlasBackground(cs) else { continue }
                    let lin = srgbToLinear(SIMD3(Float(cs.0), Float(cs.1), Float(cs.2)) / 255)
                    acc[v, default: .zero] += lin
                    wgt[v, default: 0] += 1
                }
            }
        }
        guard !acc.isEmpty else { log("VC skip: urug' yo'q"); return nil }

        // 2) Mesh grafi (faqat shu yuzalar) + diffuziya (urug'lar qotgan).
        var adj = [Int: Set<Int>]()
        var verts = Set<Int>()
        for f in faces {
            let v = model.faces[f].v
            verts.insert(v.0); verts.insert(v.1); verts.insert(v.2)
            for (a, b) in [(v.0, v.1), (v.1, v.2), (v.2, v.0)] {
                adj[a, default: []].insert(b); adj[b, default: []].insert(a)
            }
        }
        var col = [Int: SIMD3<Float>]()
        var fixed = Set<Int>()
        for (v, w) in wgt where w > 0 { col[v] = acc[v]! / w; fixed.insert(v) }
        var mean = SIMD3<Float>.zero
        for (_, c) in col { mean += c }
        mean /= Float(max(col.count, 1))
        for v in verts where col[v] == nil { col[v] = mean }
        for _ in 0..<vcIterations {
            var next = col
            for v in verts where !fixed.contains(v) {
                guard let ns = adj[v], !ns.isEmpty else { continue }
                var a = SIMD3<Float>.zero
                for u in ns { a += col[u] ?? mean }
                next[v] = a / Float(ns.count)
            }
            col = next
        }

        // 3) OBJ: cho'qqilar RANG bilan qayta yoziladi (v x y z r g b), yuzalar
        //    yangi indekslarga ko'chadi. vt YO'Q — tekstura ishlatilmaydi.
        var vLines = "", fLines = ""
        var newIdx = [Int: Int]()
        var nextV = vBase
        for v in verts.sorted() {
            let p = model.positions[v]
            let c = linearToSrgb(col[v] ?? mean)
            nextV += 1
            newIdx[v] = nextV
            vLines += "v \(p.x) \(p.y) \(p.z) \(max(0, min(1, c.x))) \(max(0, min(1, c.y))) \(max(0, min(1, c.z)))\n"
        }
        var movedFaces = Set<Int>(), movedLines = Set<Int>()
        for f in faces {
            let v = model.faces[f].v
            guard let a = newIdx[v.0], let b = newIdx[v.1], let c = newIdx[v.2] else { continue }
            fLines += "f \(a) \(b) \(c)\n"
            movedFaces.insert(f); movedLines.insert(model.faces[f].line)
        }
        guard !movedFaces.isEmpty else { return nil }
        _ = vtLineBase
        _ = faceSet
        log("VC obyekt: yuza=\(movedFaces.count) cho'qqi=\(verts.count) urug'=\(fixed.count)")
        return (movedFaces, movedLines,
                vLines + "usemtl \(unseenVCMatName)\n" + fLines, verts.count)
    }

    // MARK: - Cho'zish (real teksturani teshik ichiga)

    /// Chart atrofidagi collar (px) — real qo'shni tekstura shu zonaga rasterizatsiya
    /// qilinadi. 15mm/px da 24px ≈ 36sm.
    private static let collarPx = 24
    /// Eritish radiusi (px) — chegaradan uzoqlashgan sari kuchayadi ("hira").
    private static let meltRadius = 3
    /// Obyekt uchun eritish radiusi — kuchliroq: keskin rang butunlay yo'qolsin.
    private static let meltObjectRadius = 5
    /// Chart choki tuzatishini atrofga yoyish iteratsiyasi.
    private static let seamFeatherPasses = 4

    /// Manba yuzasini (real, suratga tushgan) chartning O'Z tekisligiga rasterizatsiya
    /// qiladi: har pikselga uning ATLASDAGI haqiqiy rangi tushadi.
    ///
    /// Nega: chekkaning faqat RANGINI olib, o'rtasini interpolyatsiya qilish naqsh
    /// bera olmaydi — foydalanuvchi aynan shuni ko'rdi ("dog'"). Real tekstura chart
    /// tekisligiga tushirilsa, keyin uni teshik ichiga CHO'ZISH mumkin — devor naqshi,
    /// pol rangi, obyektning o'z rangi bilan.
    private static func rasterizeSource(face: Face, chart: UnseenChart, model: Model,
                                        atlas: Atlas, flipY: Bool, collar: Int,
                                        ew: Int, eh: Int,
                                        col: inout [SIMD3<Float>], has: inout [Bool]) {
        func toPx(_ v: Int) -> SIMD2<Float> {
            let p = model.positions[v]
            return SIMD2((simd_dot(p, chart.uAx) - chart.lo.x) / chart.texel + 3 + Float(collar),
                         (simd_dot(p, chart.vAx) - chart.lo.y) / chart.texel + 3 + Float(collar))
        }
        guard face.v.0 < model.positions.count, face.v.1 < model.positions.count,
              face.v.2 < model.positions.count else { return }
        let a = toPx(face.v.0), b = toPx(face.v.1), c = toPx(face.v.2)
        let minX = max(Int(min(a.x, b.x, c.x)) - 1, 0), maxX = min(Int(max(a.x, b.x, c.x)) + 1, ew - 1)
        let minY = max(Int(min(a.y, b.y, c.y)) - 1, 0), maxY = min(Int(max(a.y, b.y, c.y)) + 1, eh - 1)
        guard minX <= maxX, minY <= maxY else { return }
        let det = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        guard abs(det) > 1e-6 else { return }
        let ta = model.uvs[face.t.0], tb = model.uvs[face.t.1], tc = model.uvs[face.t.2]
        for y in minY...maxY {
            for x in minX...maxX {
                let px = Float(x), py = Float(y)
                let w0 = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / det
                let w1 = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / det
                let w2 = 1 - w0 - w1
                guard w0 >= -0.02, w1 >= -0.02, w2 >= -0.02 else { continue }
                let uv = ta * w0 + tb * w1 + tc * w2
                guard let cs = atlas.sample(uv: uv, flipY: flipY),
                      !isGrayColor(cs), !isAtlasBackground(cs) else { continue }
                let i = y * ew + x
                col[i] = srgbToLinear(SIMD3(Float(cs.0), Float(cs.1), Float(cs.2)) / 255)
                has[i] = true
            }
        }
    }

    /// Bo'sh piksellarni ENG YAQIN real pikseldan ko'chirib to'ldiradi ("cho'zish").
    /// Interpolyatsiya EMAS — ko'chirish: shuning uchun naqsh/mikrokontrast saqlanadi.
    /// Qaytadi: har pikselning chegaradan uzoqligi (eritish kuchi uchun).
    private static func stretchFill(col: inout [SIMD3<Float>], has: inout [Bool],
                                    w: Int, h: Int) -> [Int] {
        var dist = [Int](repeating: 0, count: w * h)
        var frontier: [Int] = []
        for i in 0..<(w * h) where has[i] { frontier.append(i) }
        guard !frontier.isEmpty, frontier.count < w * h else { return dist }
        var step = 0
        while !frontier.isEmpty {
            step += 1
            var next: [Int] = []
            for i in frontier {
                let x = i % w, y = i / w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let n = ny * w + nx
                    guard !has[n] else { continue }
                    has[n] = true            // yozildi
                    col[n] = col[i]          // KO'CHIRILDI (o'rtacha emas)
                    dist[n] = step
                    next.append(n)
                }
            }
            frontier = next
        }
        return dist
    }

    /// Obyekt klasteri: 3D YAQINLIK bo'yicha (bog'langanlik EMAS). Obyektning
    /// ko'rinmagan qismi mayda uzuq bo'laklarga parchalanadi — ularni bitta chartga
    /// yig'amiz, aks holda har bo'lak alohida dog' bo'lib chiqadi.
    private static let objectClusterCell: Float = 0.35

    private static func spatialClusters(_ faces: [Int], model: Model) -> [[Int]] {
        guard faces.count > 1 else { return [faces] }
        var cellOf = [Int: SIMD3<Int32>]()
        var byCell = [SIMD3<Int32>: [Int]]()
        for f in faces {
            let face = model.faces[f]
            guard face.v.0 < model.positions.count, face.v.1 < model.positions.count,
                  face.v.2 < model.positions.count else { continue }
            let c = (model.positions[face.v.0] + model.positions[face.v.1]
                     + model.positions[face.v.2]) / 3
            let k = SIMD3<Int32>(Int32(floor(c.x / objectClusterCell)),
                                 Int32(floor(c.y / objectClusterCell)),
                                 Int32(floor(c.z / objectClusterCell)))
            cellOf[f] = k
            byCell[k, default: []].append(f)
        }
        // Qo'shni kataklarni birlashtiramiz (26-qo'shni).
        var parent = [SIMD3<Int32>: SIMD3<Int32>]()
        func find(_ x: SIMD3<Int32>) -> SIMD3<Int32> {
            var r = x
            while let p = parent[r], p != r { r = p }
            return r
        }
        for k in byCell.keys { parent[k] = k }
        for k in byCell.keys {
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                let n = SIMD3<Int32>(k.x + Int32(dx), k.y + Int32(dy), k.z + Int32(dz))
                guard byCell[n] != nil else { continue }
                let a = find(k), b = find(n)
                if a != b { parent[a] = b }
            } } }
        }
        var out = [SIMD3<Int32>: [Int]]()
        for (k, fs) in byCell { out[find(k), default: []].append(contentsOf: fs) }
        return Array(out.values)
    }

    /// Yuza to'plamini qirra-bog'langanligi bo'yicha bo'laklarga ajratadi.
    private static func splitConnected(_ faces: [Int], model: Model) -> [[Int]] {
        guard faces.count > 1 else { return [faces] }
        let set = Set(faces)
        var emap = [Int64: Int]()
        var adj = [Int: [Int]]()
        for f in faces {
            let v = model.faces[f].v
            for (a, b) in [(v.0, v.1), (v.1, v.2), (v.2, v.0)] {
                let k = a < b ? (Int64(a) << 32 | Int64(b)) : (Int64(b) << 32 | Int64(a))
                if let o = emap[k], set.contains(o) {
                    adj[f, default: []].append(o); adj[o, default: []].append(f)
                } else { emap[k] = f }
            }
        }
        var seen = Set<Int>(), out: [[Int]] = []
        for s in faces where !seen.contains(s) {
            var comp = [s]; seen.insert(s); var st = [s]
            while let x = st.popLast() {
                for y in adj[x] ?? [] where !seen.contains(y) {
                    seen.insert(y); comp.append(y); st.append(y)
                }
            }
            out.append(comp)
        }
        return out
    }

    /// Yuzaning 3D maydoni (m²).
    private static func faceArea(_ face: Face, model: Model) -> Float {
        guard face.v.0 < model.positions.count, face.v.1 < model.positions.count,
              face.v.2 < model.positions.count else { return 0 }
        let a = model.positions[face.v.0], b = model.positions[face.v.1], c = model.positions[face.v.2]
        return simd_length(simd_cross(b - a, c - a)) / 2
    }

    /// Ko'rinmagan yuzani eng mos RoomPlan tekisligiga bog'laydi (-1 = hech qaysi).
    ///
    /// NEGA TEKISLIK, NORMAL EMAS: tekislik to'ldirishdan keyin ko'rinmagan zonalar
    /// bitta uzluksiz qobiqqa qo'shiladi (o'lchandi: 32.8 m², 45691 yuza — devor+
    /// pol+shift birga). Uni bitta chartga solsak, ko'p yuzali zonaning proyeksiyasi
    /// UV'da ustma-ust tushadi va 33 m² faqat chekkasidan interpolyatsiya qilinib
    /// ulkan kulrang dog' chiqadi. Normal bo'yicha kesish SINALDI va RAD ETILDI
    /// (qirralarning 22% i kesiladi -> graf parchalanadi: 12399 klaster). Tekislik
    /// yorlig'i esa: 6676 klaster, eng katta 6.1 m² — dog' yo'q.
    private static let planeDistMax: Float = 0.20
    private static let planeNormalDot: Float = 0.7
    /// Tekislik yorlig'ining minimal bo'lak yuzasi (m²) — bundan kichik yakka
    /// bo'lak devor emas (masalan devorga tiralgan balonning orqa yamog'i).
    private static let minPlaneComponentArea: Float = 0.25

    /// Mayda bo'lakni yorliqdan CHIQARISH o'rniga "zaif" deb belgilash (tumbler
    /// `weakPlaneFill`, default yoniq).
    ///
    /// NEGA: mayda bo'lak yorliqdan chiqarilsa, u chart olmaydi va chartsiz
    /// per-vertex kulrang yo'liga tushadi — o'lchandi (skan #26): 14322 yuza,
    /// 18.2 m², 1117 ta ajralgan dog'. Foydalanuvchi ekranida aynan shu "kulrang
    /// parcha shovqini". Holbuki ularning 51.3% i (9.33 m²) bevosita HAQIQIY
    /// devor teksturasiga, yana 27.9% i esa `unseen_mat` ga tegib turadi — ya'ni
    /// cho'zish uchun manba yonginasida.
    ///
    /// XAVFSIZLIK: mayda bo'lak MANBA bo'lolmaydi. Aynan shu narsa balon
    /// muammosini bergan edi (devorga tiralgan ko'k balonning yamog'i "devor" deb
    /// qabul qilinib, uning KO'K rangi devorga cho'zilgan — 735 yuza). Endi ajratamiz:
    /// zaif bo'lak rangni QABUL QILADI, lekin `observedFacesOnPlane` ga KIRMAYDI.
    private static let weakPlaneFill: Bool = {
        UserDefaults.standard.object(forKey: "weakPlaneFill") as? Bool ?? true
    }()

    private static func labelByPlane(model: Model, faces: [Int], nrm: [SIMD3<Float>],
                                     planes: [TSDFGeometry.WallPlane],
                                     weak: inout Set<Int>) -> [Int] {
        var lab = [Int](repeating: -1, count: model.faces.count)
        guard !planes.isEmpty, !model.positions.isEmpty else { return lab }
        for f in faces {
            let face = model.faces[f]
            guard face.v.0 < model.positions.count, face.v.1 < model.positions.count,
                  face.v.2 < model.positions.count else { continue }
            let c = (model.positions[face.v.0] + model.positions[face.v.1]
                     + model.positions[face.v.2]) / 3
            var best = -1
            var bestD = planeDistMax
            for (pi, pl) in planes.enumerated() {
                let d = abs(simd_dot(c - pl.center, pl.normalOut))
                guard d < bestD, abs(simd_dot(nrm[f], pl.normalOut)) > planeNormalDot
                else { continue }
                bestD = d; best = pi
            }
            lab[f] = best
        }
        // MUHIM: tekislikka YAQIN va PARALLEL bo'lgan hamma narsa devor emas.
        // Dumaloq ko'k balon devorga tiralib turibdi — uning devorga qaragan
        // qismining normali devorga parallel va masofasi 20sm ichida, ya'ni
        // yuqoridagi test uni "devor" deb o'tkazadi. Keyin uning KO'K teksturasi
        // devor teshigiga cho'zish MANBAI bo'lib qoladi — foydalanuvchi ekranida
        // devordagi keskin ko'k parchalar aynan shundan (o'lchandi: kuller
        // zonasida 735 ta KO'K to'ldirish feysi).
        //
        // Farq: haqiqiy devor — KATTA va uzluksiz; balonning yamog'i — kichik va
        // yakka. Shuning uchun yorliqni bog'langan bo'laklarga ajratib, mayda
        // bo'laklarni yorliqdan chiqaramiz.
        var byLabel = [Int: [Int]]()
        for f in faces where lab[f] >= 0 { byLabel[lab[f], default: []].append(f) }
        for (_, group) in byLabel {
            for comp in splitConnected(group, model: model) {
                var a: Float = 0
                for f in comp { a += faceArea(model.faces[f], model: model) }
                guard a < minPlaneComponentArea else { continue }
                if weakPlaneFill {
                    // Yorliq SAQLANADI (chart olsin, devordan rang cho'zilsin),
                    // lekin "zaif" — manba sifatida ishlatilmaydi.
                    for f in comp { weak.insert(f) }
                } else {
                    for f in comp { lab[f] = -1 }
                }
            }
        }
        return lab
    }

    // MARK: - sRGB <-> Linear

    static func srgbToLinear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    static func linearToSrgb(_ c: Float) -> Float {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
    static func srgbToLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(srgbToLinear(c.x), srgbToLinear(c.y), srgbToLinear(c.z))
    }
    static func linearToSrgb(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(linearToSrgb(c.x), linearToSrgb(c.y), linearToSrgb(c.z))
    }

    private static func medianColor(_ samples: [(UInt8, UInt8, UInt8)]) -> (UInt8, UInt8, UInt8) {
        let r = samples.map { $0.0 }.sorted()
        let g = samples.map { $0.1 }.sorted()
        let b = samples.map { $0.2 }.sorted()
        return (r[r.count / 2], g[g.count / 2], b[b.count / 2])
    }

    // MARK: - Unseen-megachart (5.0.20 dan port)

    static let unseenPageSize = 2048
    /// Chart teksel zichligi (m/px) — 1.5sm/px.
    private static let unseenTexel: Float = 0.015
    static let unseenPageName = "room_unseen.png"
    static let unseenMatName = "unseen_mat"
    /// Obyektlar uchun material — TEKSTURASIZ, rang har cho'qqida (per-vertex).
    static let unseenVCMatName = "unseen_vc"

    private struct UnseenChart {
        var faces: [Int]
        var uvOf: [Int: SIMD2<Float>]   // vertexId -> chart-lokal px
        var w: Int, h: Int
        var x = 0, y = 0                // sahifadagi joy (packing'dan keyin)
        // Proyeksiya bazisi — 3D nuqtani chart-lokal px ga o'tkazish uchun
        // (o'sha tekislikdagi HAQIQIY devordan urug' olishda kerak).
        var uAx = SIMD3<Float>(1, 0, 0)
        var vAx = SIMD3<Float>(0, 1, 0)
        var lo = SIMD2<Float>.zero
        var texel: Float = 0.015
        var label = -1
    }

    /// Ko'rinmagan klasterlarga YANGI sahifada haqiqiy UV-chart quradi, qo'shni
    /// teksturadan "davomi + blyur" bilan bo'yaydi, sahifa PNG'sini yozadi.
    private static func megachartUnseen(objURL: URL, model: Model, atlases: [Atlas],
                                        flipY: Bool, clusters: [[Int]],
                                        neighborsOf: [Int: [(tex: Int, a: Int, b: Int)]],
                                        nrm: [SIMD3<Float>], planeLabel: [Int],
                                        unseenSet: Set<Int>, weakFaces: Set<Int>,
                                        log: (String) -> Void)
        -> (movedFaces: Set<Int>, movedLines: Set<Int>, objAppend: String)? {
        guard !clusters.isEmpty else { return nil }
        // Xavfsizlik: parse bironta `vt` qatorini tashlagan bo'lsa, f-indekslari
        // allaqachon surilgan — bunday holatda OBJ'ga yozish faylni buzadi.
        guard model.uvs.count == model.vtLineCount else {
            log("MEGACHART skip: vt sanog'i mos emas (\(model.uvs.count) vs \(model.vtLineCount))")
            return nil
        }
        let page = unseenPageSize
        let pad = 3

        // 1) Chartlar: klaster tekisligi (maydon-vaznli normal) + proyeksiya.
        var charts: [UnseenChart] = []
        var texel = unseenTexel
        var packed = false
        for _ in 0..<5 {   // sig'masa teksel yiriklashadi
            charts.removeAll()
            var tooBig = false
            for cluster in clusters {
                var nSum = SIMD3<Float>.zero
                for f in cluster {
                    let face = model.faces[f]
                    let a = model.positions[face.v.0], b = model.positions[face.v.1]
                    let c = model.positions[face.v.2]
                    nSum += simd_cross(b - a, c - a)   // maydon-vaznli
                }
                let n = simd_length(nSum) > 1e-9 ? simd_normalize(nSum) : SIMD3<Float>(0, 1, 0)
                let seed = abs(n.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
                let uAx = simd_normalize(simd_cross(n, seed))
                let vAx = simd_normalize(simd_cross(n, uAx))
                var uvOf = [Int: SIMD2<Float>]()
                var lo = SIMD2<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
                var hi = -lo
                for f in cluster {
                    let face = model.faces[f]
                    for v in [face.v.0, face.v.1, face.v.2] where uvOf[v] == nil {
                        let p = model.positions[v]
                        let uv = SIMD2(simd_dot(p, uAx), simd_dot(p, vAx))
                        uvOf[v] = uv
                        lo = simd_min(lo, uv); hi = simd_max(hi, uv)
                    }
                }
                let wPx = Int(((hi.x - lo.x) / texel).rounded(.up)) + 2 * pad + 1
                let hPx = Int(((hi.y - lo.y) / texel).rounded(.up)) + 2 * pad + 1
                // Chart sahifaga sig'masa — teksel yiriklashishi kerak. Donor bu
                // yerda min(wPx, page) bilan KESIB qo'yardi: UV chart rect'idan
                // chiqib ketib, qo'shni chartning urug'iga aralashardi.
                if wPx > page || hPx > page { tooBig = true; break }
                for (v, uv) in uvOf {
                    uvOf[v] = SIMD2((uv.x - lo.x) / texel + Float(pad),
                                    (uv.y - lo.y) / texel + Float(pad))
                }
                var ch = UnseenChart(faces: cluster, uvOf: uvOf, w: wPx, h: hPx)
                ch.uAx = uAx; ch.vAx = vAx; ch.lo = lo; ch.texel = texel
                ch.label = planeLabel[cluster[0]]
                charts.append(ch)
            }
            if tooBig { texel *= 1.6; continue }
            // 2) Shelf-packing (balandlik bo'yicha kamayish tartibida).
            let order = charts.indices.sorted { charts[$0].h > charts[$1].h }
            var cx = 0, cy = 0, rowH = 0
            var ok = true
            for i in order {
                if cx + charts[i].w > page { cx = 0; cy += rowH + 2; rowH = 0 }
                if cy + charts[i].h > page { ok = false; break }
                charts[i].x = cx; charts[i].y = cy
                cx += charts[i].w + 2
                rowH = max(rowH, charts[i].h)
            }
            if ok { packed = true; break }
            texel *= 1.6
        }
        // Donor bu yerda tekshirmasdan davom etardi: sig'masa chartlar (0,0) da
        // ustma-ust tushib, sahifa buzilardi. Sig'masa — umuman qilmaymiz.
        guard packed else { log("MEGACHART skip: sahifaga sig'madi (\(clusters.count) klaster)"); return nil }

        // 3) Urug'lash: qo'shni teksturali rang AYNAN umumiy qirra bo'ylab.
        var A = [Float](repeating: 0, count: page * page)
        var C = [SIMD3<Float>](repeating: .zero, count: page * page)
        @inline(__always) func seed(_ x: Int, _ y: Int, _ col: SIMD3<Float>, _ w: Float) {
            guard x >= 0, y >= 0, x < page, y < page else { return }
            let i = y * page + x
            C[i] += col * w
            A[i] += w
        }
        // Urug'lash: har chart AVVAL faqat BIR YO'NALISHDAGI qo'shnilardan urug'
        // oladi (devor devordan rang olsin, shiftdan emas — burchakda ular qirra
        // ulashadi va shift rangi devorga oqib ketardi). Chart urug'siz qolsa —
        // o'sha chart uchun cheklov olib tashlanadi (kulrang o'rtachadan yaxshi).
        @discardableResult
        func seedChart(_ chart: UnseenChart, strict: Bool) -> Int {
            var placed = 0
            for f in chart.faces {
                guard let edges = neighborsOf[f] else { continue }
                for (tn, va, vb) in edges {
                    if strict {
                        // Normal YETARLI EMAS: devorga PARALLEL turgan obyekt
                        // (kullerning oldi) dot≈1 beradi va uning ko'k rangi devor
                        // teshigiga oqib o'tadi — foydalanuvchi skrinshotida devorda
                        // ko'k parchalar aynan shundan. Shuning uchun chart tekislik
                        // yorlig'iga ega bo'lsa, manba ham AYNI tekislikda bo'lsin
                        // (kuller devordan 45sm narida -> yorlig'i boshqa -> rad).
                        if simd_dot(nrm[f], nrm[tn]) <= seedNormalDot { continue }
                        if chart.label >= 0, planeLabel[tn] != chart.label { continue }
                    }
                    let tface = model.faces[tn]
                    guard let ga = chart.uvOf[va], let gb = chart.uvOf[vb],
                          let ta = uvIndex(of: va, in: tface), let tb = uvIndex(of: vb, in: tface)
                    else { continue }
                    let steps = max(Int(simd_length(gb - ga)), 2)
                    for si in 0...steps {
                        let t = Float(si) / Float(steps)
                        let texUV = model.uvs[ta] + (model.uvs[tb] - model.uvs[ta]) * t
                        guard let cs = atlases[tface.mat].sample(uv: texUV, flipY: flipY),
                              !isGrayColor(cs), !isAtlasBackground(cs) else { continue }
                        let lin = srgbToLinear(SIMD3(Float(cs.0), Float(cs.1), Float(cs.2)) / 255)
                        let g = ga + (gb - ga) * t
                        seed(chart.x + Int(g.x), chart.y + Int(g.y), lin, 2.0)
                        placed += 1
                    }
                }
            }
            return placed
        }
        // O'SHA TEKISLIKDAGI haqiqiy (suratga tushgan) yuzalar — tekislik bo'yicha
        // guruhlab qo'yamiz. Ular chartning qirra qo'shnisi bo'lmasligi mumkin,
        // lekin AYNI devorning o'zi — undan urug' olish "bor devorni tortib kelish".
        var observedOnPlane = [Int: [(pos: SIMD3<Float>, col: SIMD3<Float>)]]()
        for (fi, face) in model.faces.enumerated() {
            let lb = planeLabel[fi]
            guard lb >= 0, !unseenSet.contains(fi) else { continue }
            guard face.v.0 < model.positions.count, face.v.1 < model.positions.count,
                  face.v.2 < model.positions.count else { continue }
            var cols: [(UInt8, UInt8, UInt8)] = []
            for sp in samplePoints(face: face, model: model) {
                if let c = atlases[face.mat].sample(uv: sp, flipY: flipY),
                   !isGrayColor(c), !isAtlasBackground(c) { cols.append(c) }
            }
            guard !cols.isEmpty else { continue }
            let m = medianColor(cols)
            let p = (model.positions[face.v.0] + model.positions[face.v.1]
                     + model.positions[face.v.2]) / 3
            observedOnPlane[lb, default: []].append(
                (p, srgbToLinear(SIMD3(Float(m.0), Float(m.1), Float(m.2)) / 255)))
        }

        /// Chartni O'SHA TEKISLIKDAGI haqiqiy devordan urug'laydi: devor yuzalarini
        /// chartning O'Z bazisiga proyeksiya qilamiz — teshik atrofidagi (va hatto
        /// undan narida turgan) real piksellar chart rect'i chetiga tushadi va
        /// pull-push ularni IKKI TARAFDAN teshik ichiga tortadi.
        @discardableResult
        func seedFromPlane(_ chart: UnseenChart) -> Int {
            guard chart.label >= 0, let obs = observedOnPlane[chart.label] else { return 0 }
            var placed = 0
            for (p, col) in obs {
                let u = (simd_dot(p, chart.uAx) - chart.lo.x) / chart.texel + 3
                let v = (simd_dot(p, chart.vAx) - chart.lo.y) / chart.texel + 3
                // Chart rect'idan uzoqdagilar keraksiz (boshqa devor bo'lagi).
                guard u > -8, v > -8, u < Float(chart.w) + 8, v < Float(chart.h) + 8 else { continue }
                seed(chart.x + Int(u), chart.y + Int(v), col, 1.0)
                placed += 1
            }
            return placed
        }

        var lenient = 0, fromPlane = 0
        for chart in charts {
            var n = seedChart(chart, strict: true)
            if n == 0 {
                n = seedChart(chart, strict: false)
                if n > 0 { lenient += 1 }
            }
            // FAQAT butunlay urug'siz chartga — o'sha devorning o'zidan tortamiz.
            // (`n < 8` da sinaldi va O'LCHOV RAD ETDI: yaxshi qirra urug'i bor
            //  chartlarga ham aralashib, lokallik xatosi 18.8 -> 29.2 bo'lgan —
            //  devorga suyalgan shkaf ham "devor tekisligida" turadi va uning rangi
            //  devor teshigiga oqib o'tadi. Urug'siz chartda esa muqobili — global
            //  kulrang o'rtacha, ya'ni yo'qotadigan narsa yo'q.)
            if n == 0, seedFromPlane(chart) > 0 { fromPlane += 1 }
        }

        // 4) Har chart: to'ldirish. Natija LINEAR page buferiga — chok tekislash
        //    undan keyin, sRGB'ga o'tishdan OLDIN bajariladi.
        var pagePx = [UInt8](repeating: 0, count: page * page * 4)
        var pageLin = [SIMD3<Float>](repeating: .zero, count: page * page)
        var pageHas = [Bool](repeating: false, count: page * page)
        var globalAcc = SIMD3<Float>.zero
        var globalW: Float = 0
        for i in 0..<(page * page) where A[i] > 0 { globalAcc += C[i]; globalW += A[i] }
        let globalMean = globalW > 0 ? globalAcc / globalW : srgbToLinear(SIMD3(repeating: 0.55))
        // Tekislik bo'yicha real (suratga tushgan) yuzalar — cho'zish manbai.
        var observedFacesOnPlane = [Int: [Int]]()
        for (fi, _) in model.faces.enumerated() {
            let lb = planeLabel[fi]
            // ZAIF (mayda bo'lakdagi) yuza manba bo'lolmaydi — balon muammosi.
            if lb >= 0, !unseenSet.contains(fi), !weakFaces.contains(fi) {
                observedFacesOnPlane[lb, default: []].append(fi)
            }
        }
        var seeded = 0, stretched = 0, melted = 0
        for chart in charts {
            let cw = chart.w, ch = chart.h
            var a0 = [Float](repeating: 0, count: cw * ch)
            var c0 = [SIMD3<Float>](repeating: .zero, count: cw * ch)
            var any = false
            for y in 0..<ch {
                for x in 0..<cw {
                    let pi = (chart.y + y) * page + (chart.x + x)
                    if A[pi] > 0 {
                        a0[y * cw + x] = min(A[pi], 1)
                        c0[y * cw + x] = C[pi] / A[pi]
                        any = true
                    }
                }
            }
            var result: [SIMD3<Float>]
            // ===== CHO'ZISH: real teksturani chart tekisligiga tushirib, teshikka =====
            // Manba: chartning qirra qo'shnilari + O'SHA TEKISLIKDAGI real yuzalar.
            let collar = collarPx
            let ew = cw + 2 * collar, eh = ch + 2 * collar
            var ecol = [SIMD3<Float>](repeating: .zero, count: ew * eh)
            var ehas = [Bool](repeating: false, count: ew * eh)
            // Manba FAQAT bir yo'nalishdagi real yuzalar: devor chartiga pol
            // piksellari tushmasin (o'lchov ilgari aynan shu ifloslanishni tutgan:
            // devorga suyalgan narsa rangi devor teshigiga oqardi).
            var srcFaces = Set<Int>()
            for f in chart.faces {
                for (tn, _, _) in neighborsOf[f] ?? []
                where simd_dot(nrm[f], nrm[tn]) > seedNormalDot { srcFaces.insert(tn) }
            }
            if chart.label >= 0, let same = observedFacesOnPlane[chart.label] {
                for tn in same { srcFaces.insert(tn) }
            }
            if srcFaces.isEmpty {
                // Bir yo'nalishda hech kim yo'q — cheklovsiz (kulrang o'rtachadan yaxshi).
                for f in chart.faces {
                    for (tn, _, _) in neighborsOf[f] ?? [] { srcFaces.insert(tn) }
                }
            }
            for tn in srcFaces where chart.label < 0 || planeLabel[tn] == chart.label
                                     || planeLabel[tn] < 0 && chart.label < 0 {
                rasterizeSource(face: model.faces[tn], chart: chart, model: model,
                                atlas: atlases[model.faces[tn].mat], flipY: flipY,
                                collar: collar, ew: ew, eh: eh, col: &ecol, has: &ehas)
            }
            let realPx = ehas.reduce(0) { $0 + ($1 ? 1 : 0) }
            // CHO'ZISH faqat TEKIS yuzaga (devor/pol/shift — `label >= 0`).
            //
            // Nega obyektga YARAMAYDI: cho'zish eng yaqin real pikselni KO'CHIRADI,
            // ya'ni Voronoi chegaralarini yasaydi. Bir xil rangli devorda ular
            // ko'rinmaydi (shuning uchun devor "sezilmaydigan" chiqdi), lekin
            // ko'p rangli obyektda (ko'k balon + qora korpus + kulrang devor)
            // o'sha chegaralar KESKIN RANG SAKRASHI bo'lib chiqadi — kuller aynan
            // shundan "sinib ketgan" ko'rindi. Obyekt uchun to'g'ri yo'l — silliq
            // eritish (pull-push + kuchli blur), Polycam ham shunday qiladi.
            if chart.label >= 0, realPx > 32 {
                stretched += 1
                let dist = stretchFill(col: &ecol, has: &ehas, w: ew, h: eh)
                // ERITISH ("plavno"): chegaradan uzoqlashgan sari kuchli blur —
                // real tekstura chetda o'tkir qoladi, ichkarida asta hiralashadi.
                // Polycam eksporti aynan shunday ko'rinadi (keskin chegara YO'Q).
                var soft = ecol
                gaussianBlur(&soft, w: ew, h: eh, radius: meltRadius)
                for i in 0..<(ew * eh) {
                    let t = min(Float(dist[i]) / 12, 1)      // 12px ≈ 18sm da to'liq
                    ecol[i] = ecol[i] * (1 - t) + soft[i] * t
                }
                result = [SIMD3<Float>](repeating: globalMean, count: cw * ch)
                for y in 0..<ch {
                    for x in 0..<cw { result[y * cw + x] = ecol[(y + collar) * ew + (x + collar)] }
                }
            } else if any {
                // OBYEKT (yoki manbasiz tekislik) — ERITISH: silliq interpolyatsiya
                // + kuchli blur. Keskin rang chegarasi yo'q, forma yumshoq tugaydi.
                seeded += 1
                melted += 1
                result = pullPushRect(a: a0, c: c0, w: cw, h: ch)
                gaussianBlur(&result, w: cw, h: ch, radius: meltObjectRadius)
            } else {
                // Urug'siz chart (butunlay yakkalangan) — global o'rtacha, QORA emas.
                result = [SIMD3<Float>](repeating: globalMean, count: cw * ch)
            }
            for y in 0..<ch {
                for x in 0..<cw {
                    let pi = (chart.y + y) * page + (chart.x + x)
                    pageLin[pi] = result[y * cw + x]
                    pageHas[pi] = true
                }
            }
        }

        // 4b) CHART CHOKLARINI TEKISLASH.
        //
        // Har chart o'z rect'ida MUSTAQIL to'ldiriladi — qo'shni chartdan bexabar.
        // O'lchandi (skan 20260717-110900, qurilma natijasi): qo'shni ko'rinmagan
        // feyslar orasidagi rang sakrashi — bir chart ICHIDA 5.6 (>40: 3%), chartlar
        // ORASIDA 86.6 (>40: 66%), ya'ni 15×. Aynan shu — foydalanuvchi ko'rgan
        // "keskin qirralar"; Polycam'da ular yo'q, chunki u bitta maydon quyadi.
        //
        // Bu yerda: 3D'da qo'shni, lekin BOSHQA chartdagi yuzalarning umumiy qirrasi
        // bo'ylab ikkala chartning piksellari o'rtachalanadi, keyin tuzatish chok
        // atrofiga yumshoq yoyiladi. Chart ICHIGA tegilmaydi (global maydon sinaldi
        // va u aynan ichni buzgan edi: 6.7 -> 15.9).
        var faceChart = [Int: Int]()
        for (ci, c) in charts.enumerated() { for f in c.faces { faceChart[f] = ci } }
        var seamMask = [Bool](repeating: false, count: page * page)
        var emap2 = [Int64: (ci: Int, f: Int)]()
        var seamCount = 0
        @inline(__always) func ekey2(_ a: Int, _ b: Int) -> Int64 {
            a < b ? (Int64(a) << 32 | Int64(b)) : (Int64(b) << 32 | Int64(a))
        }
        @inline(__always) func pagePt(_ c: UnseenChart, _ v: Int) -> SIMD2<Float>? {
            guard let uv = c.uvOf[v] else { return nil }
            return SIMD2(Float(c.x) + uv.x, Float(c.y) + uv.y)
        }
        for (ci, c) in charts.enumerated() {
            for f in c.faces {
                let v = model.faces[f].v
                for (a, b) in [(v.0, v.1), (v.1, v.2), (v.2, v.0)] {
                    let k = ekey2(a, b)
                    guard let o = emap2[k] else { emap2[k] = (ci, f); continue }
                    guard o.ci != ci else { continue }              // bir chart — chok yo'q
                    guard let pa = pagePt(charts[o.ci], a), let pb = pagePt(charts[o.ci], b),
                          let qa = pagePt(c, a), let qb = pagePt(c, b) else { continue }
                    let steps = max(Int(max(simd_length(pb - pa), simd_length(qb - qa))), 2)
                    for si in 0...steps {
                        let t = Float(si) / Float(steps)
                        let p = pa + (pb - pa) * t, q = qa + (qb - qa) * t
                        let pi = Int(p.y) * page + Int(p.x), qi = Int(q.y) * page + Int(q.x)
                        guard pi >= 0, qi >= 0, pi < page * page, qi < page * page,
                              pageHas[pi], pageHas[qi] else { continue }
                        let avg = (pageLin[pi] + pageLin[qi]) / 2
                        pageLin[pi] = avg; pageLin[qi] = avg
                        seamMask[pi] = true; seamMask[qi] = true
                    }
                    seamCount += 1
                }
            }
        }
        // Tuzatishni chok ATROFIGA yumshoq yoyamiz (faqat maska ichida yozamiz).
        if seamCount > 0 {
            for _ in 0..<seamFeatherPasses {
                var grow = seamMask
                for i in 0..<(page * page) where seamMask[i] {
                    let x = i % page, y = i / page
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < page, ny < page else { continue }
                        if pageHas[ny * page + nx] { grow[ny * page + nx] = true }
                    }
                }
                seamMask = grow
                var out = pageLin
                for i in 0..<(page * page) where seamMask[i] {
                    let x = i % page, y = i / page
                    var acc = SIMD3<Float>.zero; var n: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < page, ny < page else { continue }
                            let j = ny * page + nx
                            if pageHas[j] { acc += pageLin[j]; n += 1 }
                        }
                    }
                    if n > 0 { out[i] = acc / n }
                }
                pageLin = out
            }
        }

        // 4c) LINEAR -> sRGB.
        for i in 0..<(page * page) where pageHas[i] {
            var lin = pageLin[i]
            // Sof-qora himoyasi. Pol 0.005 (~sRGB 20), donordagi 0.02 EMAS:
            // 0.02 ≈ sRGB 39, ya'ni bu xonaning haqiqiy siyoh potologini
            // (26,35,32) sun'iy ravishda yoritib yuborardi.
            let l = simd_dot(lin, SIMD3<Float>(0.2126, 0.7152, 0.0722))
            if l < 0.005 { lin = l <= 0 ? SIMD3(repeating: 0.005) : lin * (0.005 / l) }
            let srgb = linearToSrgb(lin) * 255
            let pi = i * 4
            pagePx[pi] = UInt8(min(max(srgb.x, 0), 255))
            pagePx[pi + 1] = UInt8(min(max(srgb.y, 0), 255))
            pagePx[pi + 2] = UInt8(min(max(srgb.z, 0), 255))
            pagePx[pi + 3] = 255
        }
        // Sahifa fonini global o'rtacha bilan (mip/filtr qonashi qora bermasin).
        let bgS = linearToSrgb(globalMean) * 255
        let bg = (UInt8(min(max(bgS.x, 0), 255)), UInt8(min(max(bgS.y, 0), 255)),
                  UInt8(min(max(bgS.z, 0), 255)))
        for i in 0..<(page * page) where pagePx[i * 4 + 3] == 0 {
            pagePx[i * 4] = bg.0; pagePx[i * 4 + 1] = bg.1; pagePx[i * 4 + 2] = bg.2
            pagePx[i * 4 + 3] = 255
        }

        // 5) PNG.
        let pageURL = objURL.deletingLastPathComponent().appendingPathComponent(unseenPageName)
        guard writePagePNG(px: &pagePx, size: page, to: pageURL) else {
            log("MEGACHART: sahifa yozilmadi"); return nil
        }

        // 6) OBJ blok: vt + usemtl + f (v-indekslar O'ZGARMAYDI).
        var vtBase = model.vtLineCount
        var vtLines = ""
        var fLines = ""
        var movedLines = Set<Int>()
        var movedFaces = Set<Int>()
        var vtIndexOf = [Int: Int]()
        for chart in charts {
            vtIndexOf.removeAll(keepingCapacity: true)
            for f in chart.faces {
                let face = model.faces[f]
                var idx = [Int](repeating: 0, count: 3)
                var okFace = true
                for (k, v) in [face.v.0, face.v.1, face.v.2].enumerated() {
                    if let e = vtIndexOf[v] { idx[k] = e; continue }
                    guard let uv = chart.uvOf[v] else { okFace = false; break }
                    let u = (Float(chart.x) + uv.x + 0.5) / Float(page)
                    let vv = 1 - (Float(chart.y) + uv.y + 0.5) / Float(page)
                    vtLines += "vt \(u) \(vv)\n"
                    vtBase += 1
                    vtIndexOf[v] = vtBase
                    idx[k] = vtBase
                }
                // Donor bu yerda `continue` qilib idx[k]=0 qoldirardi — OBJ 1-indeksli,
                // `f v/0` NOTO'G'RI fayl. Bunday yuzani umuman ko'chirmaymiz.
                guard okFace, idx.allSatisfy({ $0 > 0 }) else { continue }
                movedLines.insert(face.line)
                movedFaces.insert(f)
                fLines += "f \(face.v.0 + 1)/\(idx[0]) \(face.v.1 + 1)/\(idx[1]) \(face.v.2 + 1)/\(idx[2])\n"
            }
        }
        guard !movedFaces.isEmpty else { log("MEGACHART skip: ko'chadigan yuza yo'q"); return nil }
        let objAppend = vtLines + "usemtl \(unseenMatName)\n" + fLines
        log("MEGACHART klaster=\(charts.count) (urug'li=\(seeded) yumshoq=\(lenient) devordan=\(fromPlane) cho'zilgan=\(stretched) eritilgan=\(melted) chok=\(seamCount)) yuza=\(movedFaces.count) " +
            "teksel=\(String(format: "%.1f", texel * 1000))mm sahifa=\(page)")
        return (movedFaces, movedLines, objAppend)
    }

    /// OBJ'ni qayta yozadi: ko'chgan f-qatorlari o'chiriladi, blok oxiriga qo'shiladi.
    /// MTL'ga `unseen_mat` qo'shiladi. v-indekslari o'zgarmaydi — boshqa hech narsa buzilmaydi.
    private static func rewriteOBJ(objURL: URL, model: Model, removedLines: Set<Int>,
                                   append: String, log: (String) -> Void) {
        var out = ""
        out.reserveCapacity(model.sourceLines.reduce(0) { $0 + $1.count + 1 } + append.count)
        for (i, line) in model.sourceLines.enumerated() where !removedLines.contains(i) {
            out += line
            out += "\n"
        }
        out += append
        do {
            try out.write(to: objURL, atomically: true, encoding: .utf8)
        } catch {
            log("MEGACHART: obj yozilmadi (\(error.localizedDescription))"); return
        }
        // MTL — material allaqachon bo'lsa (qayta ishlash) takrorlamaymiz.
        let mtlURL = objURL.deletingLastPathComponent().appendingPathComponent("room.mtl")
        guard let mtl = try? String(contentsOf: mtlURL, encoding: .utf8) else {
            log("MEGACHART: mtl o'qilmadi"); return
        }
        var add = ""
        if !mtl.contains("newmtl \(unseenMatName)") {
            add += "\nnewmtl \(unseenMatName)\nKa 1 1 1\nKd 1 1 1\nmap_Kd \(unseenPageName)\n"
        }
        // Obyekt materiali — map_Kd YO'Q: rang har cho'qqida (v x y z r g b).
        if !mtl.contains("newmtl \(unseenVCMatName)") {
            add += "\nnewmtl \(unseenVCMatName)\nKa 1 1 1\nKd 1 1 1\n"
        }
        guard !add.isEmpty else { return }
        try? (mtl + add).write(to: mtlURL, atomically: true, encoding: .utf8)
    }

    /// Rect ichida pull-push (mip-piramida diffuziyasi) — ko'p masshtabli silliq davomiya.
    private static func pullPushRect(a: [Float], c: [SIMD3<Float>], w: Int, h: Int) -> [SIMD3<Float>] {
        var levels: [(a: [Float], c: [SIMD3<Float>], w: Int, h: Int)] = [(a, c, w, h)]
        while levels[levels.count - 1].w > 1 || levels[levels.count - 1].h > 1 {
            let (pa, pc, pw, ph) = levels[levels.count - 1]
            let nw = (pw + 1) / 2, nh = (ph + 1) / 2
            var na = [Float](repeating: 0, count: nw * nh)
            var nc = [SIMD3<Float>](repeating: .zero, count: nw * nh)
            for y in 0..<ph {
                for x in 0..<pw {
                    let al = pa[y * pw + x]
                    guard al > 0 else { continue }
                    let ni = (y / 2) * nw + (x / 2)
                    nc[ni] += pc[y * pw + x] * al
                    na[ni] += al
                }
            }
            for i in 0..<(nw * nh) where na[i] > 0 {
                nc[i] /= na[i]
                na[i] = min(na[i] / 4, 1)
            }
            levels.append((na, nc, nw, nh))
        }
        var result = levels[levels.count - 1].c
        for li in stride(from: levels.count - 2, through: 0, by: -1) {
            let (la, lc, lw, lh) = levels[li]
            let (_, _, uw, uh) = levels[li + 1]
            var out = [SIMD3<Float>](repeating: .zero, count: lw * lh)
            let parent = result
            for y in 0..<lh {
                let fy = (Float(y) + 0.5) / 2 - 0.5
                let y0 = min(max(Int(fy.rounded(.down)), 0), uh - 1)
                let y1 = min(y0 + 1, uh - 1)
                let ty = min(max(fy - Float(y0), 0), 1)
                for x in 0..<lw {
                    let fx = (Float(x) + 0.5) / 2 - 0.5
                    let x0 = min(max(Int(fx.rounded(.down)), 0), uw - 1)
                    let x1 = min(x0 + 1, uw - 1)
                    let tx = min(max(fx - Float(x0), 0), 1)
                    let p00: SIMD3<Float> = parent[y0 * uw + x0]
                    let p01: SIMD3<Float> = parent[y0 * uw + x1]
                    let p10: SIMD3<Float> = parent[y1 * uw + x0]
                    let p11: SIMD3<Float> = parent[y1 * uw + x1]
                    let top: SIMD3<Float> = p00 + (p01 - p00) * tx
                    let bot: SIMD3<Float> = p10 + (p11 - p10) * tx
                    let up: SIMD3<Float> = top + (bot - top) * ty
                    let al = la[y * lw + x]
                    let own: SIMD3<Float> = lc[y * lw + x] * al
                    out[y * lw + x] = own + up * (1 - al)
                }
            }
            result = out
        }
        return result
    }

    /// Ajratiladigan quti-blyur x3 ~ Gauss (sigma ~ radius).
    private static func gaussianBlur(_ img: inout [SIMD3<Float>], w: Int, h: Int, radius: Int) {
        guard radius > 0, w > 2 * radius, h > 2 * radius else { return }
        for _ in 0..<3 {
            var tmp = img
            for y in 0..<h {
                var acc = SIMD3<Float>.zero
                for x in 0..<min(2 * radius + 1, w) { acc += img[y * w + x] }
                let cnt = Float(min(2 * radius + 1, w))
                for x in 0..<w {
                    if x > radius && x + radius < w {
                        acc += img[y * w + x + radius] - img[y * w + x - radius - 1]
                    }
                    tmp[y * w + x] = acc / cnt
                }
            }
            for x in 0..<w {
                var acc = SIMD3<Float>.zero
                for y in 0..<min(2 * radius + 1, h) { acc += tmp[y * w + x] }
                let cnt = Float(min(2 * radius + 1, h))
                for y in 0..<h {
                    if y > radius && y + radius < h {
                        acc += tmp[(y + radius) * w + x] - tmp[(y - radius - 1) * w + x]
                    }
                    img[y * w + x] = acc / cnt
                }
            }
        }
    }

    private static func writePagePNG(px: inout [UInt8], size: Int, to url: URL) -> Bool {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: - Model (OBJ + MTL)

    struct Face {
        var v: (Int, Int, Int)   // pozitsiya indekslari (qo'shnilik uchun)
        var t: (Int, Int, Int)   // UV indekslari
        var mat: Int             // atlas indeksi
        var line: Int = -1       // OBJ'dagi qator indeksi (megachart ko'chirishi uchun)
    }
    struct Model {
        var positions: [SIMD3<Float>] = []   // gradient (IDW) uchun 3D joylar
        var uvs: [SIMD2<Float>] = []
        var faces: [Face] = []
        var textureURLs: [URL] = []
        var sourceLines: [Substring] = []    // OBJ qatorlari (qayta yozish uchun)
        /// Fayldagi HAQIQIY `vt` qatorlari soni. `uvs.count` EMAS: parse buzuq
        /// qatorni tashlab ketishi mumkin, u holda qo'shilgan f-indekslari surilib
        /// butun blok buziladi.
        var vtLineCount = 0
        /// Fayldagi HAQIQIY `v` qatorlari soni (per-vertex blok indekslari uchun).
        var vLineCount = 0
    }

    private static func parseOBJ(objURL: URL) -> Model? {
        guard let text = try? String(contentsOf: objURL, encoding: .utf8) else { return nil }
        var model = Model()

        // MTL: material nomi -> tekstura fayli.
        var mtlTextures = [String: String]()
        if let mtlLine = text.split(separator: "\n").first(where: { $0.hasPrefix("mtllib ") }) {
            let mtlName = mtlLine.dropFirst(7).trimmingCharacters(in: .whitespaces)
            let mtlURL = objURL.deletingLastPathComponent().appendingPathComponent(mtlName)
            if let mtlText = try? String(contentsOf: mtlURL, encoding: .utf8) {
                var current = ""
                for line in mtlText.split(separator: "\n") {
                    if line.hasPrefix("newmtl ") { current = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
                    else if line.hasPrefix("map_Kd "), !current.isEmpty {
                        mtlTextures[current] = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        var matIndex = [String: Int]()   // tekstura fayli -> atlas indeksi
        var currentMat = -1
        model.sourceLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (li, line) in model.sourceLines.enumerated() {
            if line.hasPrefix("vt ") {
                model.vtLineCount += 1
                let p = line.split(separator: " ")
                guard p.count >= 3, let u = Float(p[1]), let v = Float(p[2]) else { continue }
                model.uvs.append(SIMD2(u, v))
            } else if line.hasPrefix("v ") {
                model.vLineCount += 1
                let p = line.split(separator: " ")
                guard p.count >= 4, let x = Float(p[1]), let y = Float(p[2]), let z = Float(p[3]) else { continue }
                model.positions.append(SIMD3(x, y, z))
            } else if line.hasPrefix("usemtl ") {
                let name = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                guard let tex = mtlTextures[name] else { currentMat = -1; continue }
                if let idx = matIndex[tex] { currentMat = idx }
                else {
                    let url = objURL.deletingLastPathComponent().appendingPathComponent(tex)
                    matIndex[tex] = model.textureURLs.count
                    currentMat = model.textureURLs.count
                    model.textureURLs.append(url)
                }
            } else if line.hasPrefix("f "), currentMat >= 0 {
                let p = line.split(separator: " ")
                guard p.count >= 4 else { continue }
                var vs: [Int] = []; var ts: [Int] = []
                for k in 1...3 {
                    let comps = p[k].split(separator: "/", omittingEmptySubsequences: false)
                    guard let vi = Int(comps[0]), comps.count >= 2, let ti = Int(comps[1]) else { break }
                    vs.append(vi - 1); ts.append(ti - 1)   // OBJ 1-indeks
                }
                guard vs.count == 3 else { continue }
                model.faces.append(Face(v: (vs[0], vs[1], vs[2]), t: (ts[0], ts[1], ts[2]),
                                        mat: currentMat, line: li))
            }
        }
        guard !model.faces.isEmpty, !model.textureURLs.isEmpty else { return nil }
        return model
    }

    // MARK: - Atlas (RGBA8 bitmap)

    final class Atlas {
        let url: URL
        let w: Int, h: Int
        var px: [UInt8]           // RGBA
        var dirty = false
        private var paintedMask: [Bool]
        private var largeMask: [Bool]   // katta hudud piksellari — kuchliroq blur

        init?(url: URL) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            w = img.width; h = img.height
            px = [UInt8](repeating: 0, count: w * h * 4)
            paintedMask = [Bool](repeating: false, count: w * h)
            largeMask = [Bool](repeating: false, count: w * h)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            self.url = url
        }

        func pixelXY(uv: SIMD2<Float>, flipY: Bool) -> (Int, Int) {
            let x = min(max(Int(uv.x * Float(w - 1) + 0.5), 0), w - 1)
            let yRaw = flipY ? (1 - uv.y) : uv.y
            let y = min(max(Int(yRaw * Float(h - 1) + 0.5), 0), h - 1)
            return (x, y)
        }

        func sample(uv: SIMD2<Float>, flipY: Bool) -> (UInt8, UInt8, UInt8)? {
            let (x, y) = pixelXY(uv: uv, flipY: flipY)
            let i = (y * w + x) * 4
            return (px[i], px[i + 1], px[i + 2])
        }

        /// UV uchburchakni 3 cho'qqi rangi bilan gradient bo'yaydi (barycentric
        /// interpolyatsiya) — hudud bo'ylab rang silliq "cho'ziladi".
        func rasterize(face: Face, model: Model, flipY: Bool,
                       colors: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>),
                       large: Bool = false) {
            let pa = pixelXY(uv: model.uvs[face.t.0], flipY: flipY)
            let pb = pixelXY(uv: model.uvs[face.t.1], flipY: flipY)
            let pc = pixelXY(uv: model.uvs[face.t.2], flipY: flipY)
            let minX = max(min(pa.0, pb.0, pc.0) - 1, 0), maxX = min(max(pa.0, pb.0, pc.0) + 1, w - 1)
            let minY = max(min(pa.1, pb.1, pc.1) - 1, 0), maxY = min(max(pa.1, pb.1, pc.1) + 1, h - 1)
            let ax = Float(pa.0), ay = Float(pa.1)
            let bx = Float(pb.0), by = Float(pb.1)
            let cx = Float(pc.0), cy = Float(pc.1)
            let avg = (colors.0 + colors.1 + colors.2) / 3
            let area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
            guard abs(area) > 1e-6 else {
                // Degenerativ (juda kichik) — bbox'ni o'rtacha rang bilan bo'yaymiz.
                for y in minY...maxY { for x in minX...maxX { put(x, y, avg, large) } }
                return
            }
            // -0.15 barycentric margin: chekka piksellar qamrab olinadi. Ortiqcha
            // bo'yash faqat o'sha unseen patch ichida qoladi (texrecon ko'rilmagan
            // yuzalarni alohida patchga joylaydi) — xavfsiz.
            for y in minY...maxY {
                for x in minX...maxX {
                    let pxf = Float(x), pyf = Float(y)
                    let w0 = ((bx - pxf) * (cy - pyf) - (by - pyf) * (cx - pxf)) / area
                    let w1 = ((cx - pxf) * (ay - pyf) - (cy - pyf) * (ax - pxf)) / area
                    let w2 = 1 - w0 - w1
                    if w0 >= -0.15 && w1 >= -0.15 && w2 >= -0.15 {
                        let c0 = max(w0, 0), c1 = max(w1, 0), c2 = max(w2, 0)
                        let s = c0 + c1 + c2
                        let col = s > 1e-6 ? (colors.0 * c0 + colors.1 * c1 + colors.2 * c2) / s : avg
                        put(x, y, col, large)
                    }
                }
            }
        }

        private func put(_ x: Int, _ y: Int, _ c: SIMD3<Float>, _ large: Bool) {
            let i = (y * w + x) * 4
            px[i]     = UInt8(max(0, min(255, Int(c.x * 255))))
            px[i + 1] = UInt8(max(0, min(255, Int(c.y * 255))))
            px[i + 2] = UInt8(max(0, min(255, Int(c.z * 255))))
            px[i + 3] = 255
            paintedMask[y * w + x] = true
            if large { largeMask[y * w + x] = true }
            dirty = true
        }

        /// Bo'yalgan piksellarni yumshatish (box blur ≈ Gauss). O'qish butun
        /// atlasdan (chegara ranglari qatnashadi — silliq quyilish), yozish
        /// faqat maska ichida — haqiqiy tekstura o'tkirligicha qoladi.
        /// onlyLarge=true — faqat katta hududlar (qo'shimcha kuchli erish).
        func blurPainted(radius: Int, passes: Int, onlyLarge: Bool) {
            var idxs: [Int32] = []
            for i in 0..<paintedMask.count where paintedMask[i] && (!onlyLarge || largeMask[i]) {
                idxs.append(Int32(i))
            }
            guard !idxs.isEmpty else { return }
            var out = [UInt8](repeating: 0, count: idxs.count * 3)
            for _ in 0..<passes {
                for (n, ii) in idxs.enumerated() {
                    let i = Int(ii)
                    let x0 = i % w, y0 = i / w
                    var sr = 0, sg = 0, sb = 0, cnt = 0
                    var dy = -radius
                    while dy <= radius {
                        let y = y0 + dy
                        dy += 1
                        if y < 0 || y >= h { continue }
                        var dx = -radius
                        while dx <= radius {
                            let x = x0 + dx
                            dx += 1
                            if x < 0 || x >= w { continue }
                            let o = (y * w + x) * 4
                            sr += Int(px[o]); sg += Int(px[o + 1]); sb += Int(px[o + 2])
                            cnt += 1
                        }
                    }
                    out[n * 3] = UInt8(sr / cnt)
                    out[n * 3 + 1] = UInt8(sg / cnt)
                    out[n * 3 + 2] = UInt8(sb / cnt)
                }
                for (n, ii) in idxs.enumerated() {
                    let o = Int(ii) * 4
                    px[o] = out[n * 3]; px[o + 1] = out[n * 3 + 1]; px[o + 2] = out[n * 3 + 2]
                }
            }
        }

        /// Bo'yalgan piksellardan qo'shni SOF KULRANG piksellarga kengayish (padding).
        func dilateIntoGray(passes: Int) {
            for _ in 0..<passes {
                var additions: [(Int, (UInt8, UInt8, UInt8))] = []
                for y in 0..<h {
                    for x in 0..<w {
                        let i = y * w + x
                        if paintedMask[i] { continue }
                        let pi = i * 4
                        let isGray = abs(Int(px[pi]) - 140) <= 3 && abs(Int(px[pi+1]) - 140) <= 3 && abs(Int(px[pi+2]) - 140) <= 3
                        guard isGray else { continue }
                        // Bo'yalgan qo'shni bormi?
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < w, ny < h, paintedMask[ny * w + nx] else { continue }
                            let ni = (ny * w + nx) * 4
                            additions.append((i, (px[ni], px[ni + 1], px[ni + 2])))
                            break
                        }
                    }
                }
                for (i, c) in additions {
                    let pi = i * 4
                    px[pi] = c.0; px[pi + 1] = c.1; px[pi + 2] = c.2
                    paintedMask[i] = true
                }
                if additions.isEmpty { break }
            }
        }

        func save() -> Bool {
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let img = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
            CGImageDestinationAddImage(dest, img, nil)
            return CGImageDestinationFinalize(dest)
        }
    }
}
