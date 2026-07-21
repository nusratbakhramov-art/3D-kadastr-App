import Foundation
import RoomPlan
import simd

/// RoomPlan devor/pol/shift tekisliklarini TSDF'ga "struktura tekisliklari" sifatida
/// tayyorlaydi — ko'rilmagan joyda devor TEKIS davom etsin, teshik bo'lib qolmasin.
///
/// NEGA KERAK: TSDF halol — ko'rilmagan joy teshik bo'lib qoladi (`smallHoleFill`
/// faqat perimetri 4m dan kichik halqalarni yopadi). Yomon skanda divan ortidagi
/// devor, shift burchagi va pol bo'lagi umuman kuzatilmaydi va katta ochiq teshik
/// bo'lib qoladi (o'lchandi: 30 ta halqa > 0.05 m²). Lekin devor QAYERDA ekanini
/// biz BILAMIZ — RoomPlan aytadi.
///
/// NEGA BU HALOL (uydirma emas): `injectPlanes` faqat `wsum <= 0` — ya'ni birorta
/// kamera nuri UMUMAN tegmagan — voxellarga yozadi. Real o'lchov har doim ustun.
/// Ochiq eshik/o'tish joyi kamera tomonidan "teshib" ko'rilgan (TSDF integratsiyada
/// nur bo'sh fazoni `sdf = d - zc > 0`, `wsum > 0` qilib belgilaydi) → inject o'sha
/// voxellarni O'TKAZIB YUBORADI → o'tish joyi teshikligicha qoladi. 5.4.0'dagi
/// `seenThrough` evristikasi (ovoz berish, min-filtr) SHART EMAS: TSDF'ning o'zida
/// aniq okklyuziya maydoni bor.
///
/// Proyomlar (eshik/deraza) devor namunasidan KESIB tashlanadi (`cutouts`) — aks
/// holda ochiq eshik devor bo'lib to'lib qolardi. Ularning O'ZI esa `openings()`
/// orqali alohida tekislik bo'lib beriladi: SHISHA MUHRI (deraza doim, eshik faqat
/// yopiq bo'lsa) — LiDAR shishadan o'tib ketgani uchun u yerda yuza umuman
/// chiqmasdi; muhr nurni tekislikda kesib, shishani YUZAga aylantiradi.
enum StructurePlanes {

    /// Proyom kesigining minimal o'lchami (m) — mayda qoldiqlar rect yasamasin.
    private static let minOpeningCut: Float = 0.10
    /// Devor to'rtburchagi chetiga zaxira (m) — burchaklar va RoomPlan kalta
    /// o'lchagan devorlar uchun (RoomClipper'dagi `extentPad` bilan bir xil mantiq).
    private static let extentPad: Float = 0.20

    // MARK: - Sof yadro (RoomPlan'siz — macOS'da haqiqiy skanda test qilinadi)

    /// RoomPlan turlaridan xoli yuza tavsifi.
    struct SurfaceInput {
        var transform: simd_float4x4
        var dimensions: SIMD3<Float>
        var identifier: UUID
        var parentIdentifier: UUID?
        /// Eshik yopiqmi (RoomPlan `.door(isOpen:)`). Derazada ahamiyatsiz.
        var doorClosed: Bool = true
    }

    /// Devor + pol + shift tekisliklari. `floorPolygon` — world XZ konturi.
    /// `screens` — ekran tekisliklari (`objectPlanes`): ular ortidagi devor bo'lagi
    /// KESIB tashlanadi, aks holda TV ortida ikkinchi qavat yuza qolib ketadi
    /// (o'lchandi: 626 ta yuza devor tekisligida, ekran paneli oldida turgani holda).
    static func planes(walls: [SurfaceInput], openings: [SurfaceInput],
                       floorPolygon: [SIMD2<Float>],
                       floorY: Float, ceilingY: Float,
                       screens: [TSDFGeometry.WallPlane] = [],
                       cameras: [SIMD3<Float>] = []) -> [TSDFGeometry.WallPlane] {
        guard !walls.isEmpty else { return [] }

        // Xona markazi — devorning qaysi tomoni "ichkari" ekanini aniqlash uchun.
        var center = SIMD3<Float>.zero
        for w in walls {
            let t = w.transform
            center += SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        }
        center /= Float(walls.count)

        var out: [TSDFGeometry.WallPlane] = []
        for w in walls {
            let t = w.transform
            var nIn = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
            let l = simd_length(nIn)
            guard l > 1e-6 else { continue }
            nIn /= l
            let c = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            // ICHKARI TOMON — skan KAMERA YO'LI bo'yicha, devorlar markazi bo'yicha EMAS.
            //
            // NEGA (o'lchandi, skan #26 devor[8] markaz=(4.17,-0.14,0.46)): 15 devor
            // markazi (3.77,-0.14,0.90) shu devor uchun NOTO'G'RI tomonda qoladi —
            // koridor uzun va L-shaklli. Holbuki unga qaragan kameralar 0.90 m da,
            // qarama-qarshi tomonda. Markazga qarab yo'naltirilganda tekislik TESKARI
            // inject qilinadi, yuza koridordan teskari qaraydi va `cullMode = .back`
            // uni kesib tashlaydi -> devor QORA ko'rinadi.
            //
            // O'lchangan natija (ko'rinadigan yuza ulushi): devor[8] 45%->89%,
            // devor[1] 60%->98%, [11] 24%->92%, [12] 21%->88%. Maydon shishishi ham
            // tuzaldi: [1] 111.9->69.5 m2 (nazariy 63.5) — oldin ikkala varaq chiqardi.
            //
            // Kamera yo'q bo'lsa (eski skan) — eski xatti-harakat, markaz bo'yicha.
            if let near = nearestCamera(to: c, cameras: cameras) {
                if simd_dot(near - c, nIn) < 0 { nIn = -nIn }
            } else if simd_dot(center - c, nIn) < 0 {
                nIn = -nIn
            }
            out.append(TSDFGeometry.WallPlane(
                center: c,
                normalOut: -nIn,                               // TSDF: xonadan TASHQARIGA
                xAxis: simd_normalize(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z)),
                yAxis: simd_normalize(SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z)),
                halfW: w.dimensions.x / 2 + extentPad,
                halfH: w.dimensions.y / 2 + extentPad,
                cutouts: cutoutRects(for: w, openings: openings)
                    + screenCutRects(for: w, screens: screens),
                polygonXZ: nil,
                snapToMeasured: true,
                label: "devor"))
        }

        // Pol va shift — footprint poligoni bo'yicha (L-shaklli xona ham to'g'ri).
        if floorPolygon.count >= 3, ceilingY > floorY {
            var lo = floorPolygon[0], hi = floorPolygon[0]
            for p in floorPolygon { lo = simd_min(lo, p); hi = simd_max(hi, p) }
            let cx = (lo.x + hi.x) / 2, cz = (lo.y + hi.y) / 2
            let hw = (hi.x - lo.x) / 2 + extentPad, hh = (hi.y - lo.y) / 2 + extentPad
            // Pol: normal PASTGA (xonadan tashqariga) — xona ichi musbat bo'lsin.
            out.append(TSDFGeometry.WallPlane(
                center: SIMD3(cx, floorY, cz), normalOut: SIMD3(0, -1, 0),
                xAxis: SIMD3(1, 0, 0), yAxis: SIMD3(0, 0, 1),
                halfW: hw, halfH: hh, cutouts: [], polygonXZ: floorPolygon, label: "pol"))
            // Shift: normal TEPAGA.
            out.append(TSDFGeometry.WallPlane(
                center: SIMD3(cx, ceilingY, cz), normalOut: SIMD3(0, 1, 0),
                xAxis: SIMD3(1, 0, 0), yAxis: SIMD3(0, 0, 1),
                halfW: hw, halfH: hh, cutouts: [], polygonXZ: floorPolygon, label: "shift"))
        }
        return out
    }

    /// Devor markaziga eng yaqin skan kamerasi (2.5 m radius; topilmasa nil).
    /// Radius cheklovi: uzoqdagi kamera boshqa xonada bo'lishi mumkin.
    private static func nearestCamera(to p: SIMD3<Float>,
                                      cameras: [SIMD3<Float>]) -> SIMD3<Float>? {
        var best: SIMD3<Float>?
        var bestD = Float(2.5 * 2.5)
        for cam in cameras {
            let d = simd_length_squared(cam - p)
            if d < bestD { bestD = d; best = cam }
        }
        return best
    }

    // MARK: - Proyom tekisliklari (SHISHA MUHRI, 5.4.0.1 porti)

    /// Eshik/deraza tekisliklari — LiDAR qaytarmagan shisha zonasi TESHIK emas,
    /// YUZA bo'lsin.
    ///
    /// Semantika: deraza — DOIM muhrlanadi; eshik — YOPIQ bo'lsa muhrlanadi.
    ///
    /// 6.1.2 ning 70% "shisha to'siq" mezoni OLIB TASHLANDI (foydalanuvchi bisekti:
    /// 6.1.1 da #28 zo'r, 6.1.2 da devor muammosi). O'lchandi: #28 eshigi
    /// ota-devorining 28.2% ini egallaydi (1.33/4.72 m2) -> 70% dan past ->
    /// muhrlanmasdi -> nurlar eshikdan o'tib qo'shni devor[6] burchagini
    /// `wsum > 0` qilib qo'yardi, lekin kuzatuv sifatsiz bo'lgani uchun yuza
    /// chiqmasdi. Natija: 0.40 x 2.60 m tik qora tasma.
    ///
    /// NEGA `isOpen` GA ISHONMAYMIZ (o'lchandi, skan 20260720-194938 #26): RoomPlan
    /// ochiq turgan oddiy eshikni ham `isOpen=false` deb beradi. O'sha eshikni
    /// muhrlaganda teshik ustiga sun'iy tekislik yozilgan (1.65 m², shovqin 2.3mm),
    /// HOLBUKI skaner eshikdan 4.0 m ichkarini haqiqatan ko'rgan (3.66 m² geometriya,
    /// shovqin 42–96mm). Ikki yuza bir joyda turib, eshik yirtilgan ko'rinishga kelgan.
    ///
    /// MUHR NIMA UCHUN KERAK: faqat LiDAR O'TIB KETADIGAN yuza uchun. Shaffof bo'lmagan
    /// eshik — yopiq bo'lsa ham, ochiq bo'lsa ham — o'lchanadi, muhr kerak emas.
    ///
    /// SHISHANI AJRATISH MEZONI: RoomPlan katta shisha to'siqni "yopiq eshik" deb
    /// beradi, lekin bunday "eshik" OTA-DEVORNING DEYARLI HAMMASINI egallaydi.
    /// O'lchandi (2 skan, 4 ta eshik): shisha 98.5% / 99.2% / 98.9%, haqiqiy eshik
    /// 14.4%. Oradagi bo'shliq ulkan — chegara 70% xavfsiz.
    static func openings(doors: [SurfaceInput], windows: [SurfaceInput],
                         roomCenter: SIMD3<Float>) -> [TSDFGeometry.WallPlane] {
        var out: [TSDFGeometry.WallPlane] = []
        for (s, isWindow) in windows.map({ ($0, true) }) + doors.map({ ($0, false) }) {
            let t = s.transform
            var nIn = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
            let l = simd_length(nIn)
            guard l > 1e-6 else { continue }
            nIn /= l
            let c = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            if simd_dot(roomCenter - c, nIn) < 0 { nIn = -nIn }
            out.append(TSDFGeometry.WallPlane(
                center: c, normalOut: -nIn,
                xAxis: simd_normalize(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z)),
                yAxis: simd_normalize(SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z)),
                halfW: s.dimensions.x / 2, halfH: s.dimensions.y / 2,
                cutouts: [], polygonXZ: nil,
                seal: isWindow || s.doorClosed,
                isOpening: true,
                snapToMeasured: true,
                label: isWindow ? "deraza" : (s.doorClosed ? "eshik(yopiq)" : "eshik(ochiq)")))
        }
        return out
    }

    // MARK: - Ekran tekisliklari (televizor)

    /// Yassi ekranli obyekt tavsifi (RoomPlan'siz).
    struct ObjectInput {
        var transform: simd_float4x4
        var dimensions: SIMD3<Float>
        var label: String
    }

    /// Televizor/monitor OLD yuzasi tekislik sifatida.
    ///
    /// MUAMMO (o'lchandi, skan 20260713-192242): qora yaltiroq ekran LiDARga qaytish
    /// BERMAYDI → TSDF'da ekran o'rtasidagi ustunlar `wsum <= 0` bo'lib qoladi va
    /// `injectPlanes` u yerga ORTDAGI DEVOR tekisligini yozib yuboradi. Natijada
    /// ekran markazi devor chuqurligiga (17sm ortga) tushadi, skanlangan ramka esa
    /// joyida qoladi → "televizorning 2 tomoni bo'rtib chiqqan" ko'rinishi.
    /// Dalil: markazdagi 781 yuza aynan devor tekisligida (-0.173 m, devor ofseti
    /// bilan mm-ga mos) va ichki deviatsiyasi 0.0 mm — analitik tekislik, o'lchov
    /// emas (real yuzalarda 4-8 mm shovqin).
    ///
    /// YECHIM: ekranning o'z old tekisligini ham inject qilamiz. U devordan oldinroq
    /// bo'lgani uchun yuza sifatida u chiqadi, devor esa uning ORTIDA ko'rinmay
    /// qoladi (ikkisi orasi ~22sm — `trunc` dan ancha katta, aralashmaydi).
    /// Chuqurlik `snapToMeasured` orqali o'lchangan ramkadan olinadi.
    static func objectPlanes(objects: [ObjectInput],
                             roomCenter: SIMD3<Float>) -> [TSDFGeometry.WallPlane] {
        var out: [TSDFGeometry.WallPlane] = []
        for o in objects {
            let t = o.transform
            var fwd = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
            let l = simd_length(fwd)
            guard l > 1e-6 else { continue }
            fwd /= l
            let c = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            if simd_dot(roomCenter - c, fwd) < 0 { fwd = -fwd }   // xona ichiga
            // Old yuza markazi. Chetiga zaxira BERILMAYDI — ekran gabaritdan
            // chiqib ketmasin (devordan farqli, bu yerda ortiqcha kenglik zarar).
            out.append(TSDFGeometry.WallPlane(
                center: c + fwd * (o.dimensions.z / 2),
                normalOut: -fwd,                                   // xonadan tashqariga
                xAxis: simd_normalize(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z)),
                yAxis: simd_normalize(SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z)),
                halfW: o.dimensions.x / 2, halfH: o.dimensions.y / 2,
                cutouts: [], polygonXZ: nil,
                snapToMeasured: true,
                label: o.label))
        }
        return out
    }

    /// Xonadagi televizorlar uchun ekran tekisliklari.
    static func objectPlanes(room: CapturedRoom) -> [TSDFGeometry.WallPlane] {
        guard !room.walls.isEmpty else { return [] }
        var c = SIMD3<Float>.zero
        for w in room.walls {
            let t = w.transform
            c += SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        }
        c /= Float(room.walls.count)
        let screens = room.objects.filter { $0.category == .television }
        return objectPlanes(objects: screens.map {
            ObjectInput(transform: $0.transform, dimensions: $0.dimensions, label: "ekran")
        }, roomCenter: c)
    }

    // MARK: - RoomPlan adapteri

    /// RoomPlan yuzasini yadro turiga o'giradi (eshik yopiqligi bilan).
    private static func input(_ s: CapturedRoom.Surface) -> SurfaceInput {
        var closed = true
        if case .door(let isOpen) = s.category { closed = !isOpen }
        return SurfaceInput(transform: s.transform, dimensions: s.dimensions,
                            identifier: s.identifier, parentIdentifier: s.parentIdentifier,
                            doorClosed: closed)
    }

    /// Xonaning devor + pol + shift tekisliklari.
    static func planes(room: CapturedRoom,
                       screens: [TSDFGeometry.WallPlane] = [],
                       cameras: [SIMD3<Float>] = []) -> [TSDFGeometry.WallPlane] {
        let b = RoomGeometry.bounds(of: room)
        return planes(walls: room.walls.map(input),
                      openings: (room.doors + room.windows).map(input),
                      floorPolygon: floorPolygonXZ(of: room, bounds: b),
                      floorY: b.floorY, ceilingY: b.ceilingY,
                      screens: screens, cameras: cameras)
    }

    /// Proyom (eshik/deraza) tekisliklari — shisha muhri uchun.
    static func openings(room: CapturedRoom) -> [TSDFGeometry.WallPlane] {
        guard !room.walls.isEmpty else { return [] }
        var c = SIMD3<Float>.zero
        for w in room.walls {
            let t = w.transform
            c += SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        }
        c /= Float(room.walls.count)
        return openings(doors: room.doors.map(input), windows: room.windows.map(input),
                        roomCenter: c)
    }

    // MARK: - Proyomlar (5.4.0 PlaneOcclusionFiller dan)

    /// Eshik/deraza to'rtburchaklari devor-lokal (x,y) da.
    private static func cutoutRects(for wall: SurfaceInput, openings: [SurfaceInput])
        -> [(min: SIMD2<Float>, max: SIMD2<Float>)] {
        let inv = wall.transform.inverse
        let halfW = wall.dimensions.x / 2
        let halfH = wall.dimensions.y / 2
        var rects: [(min: SIMD2<Float>, max: SIMD2<Float>)] = []
        for opening in openings {
            let local = inv * opening.transform
            let c = SIMD2<Float>(local.columns.3.x, local.columns.3.y)
            // parentIdentifier ISHONCHSIZ (RoomPlan ba'zan nil yoki merge'dan keyin
            // eskirgan qoldiradi) — mos kelmasa GEOMETRIK tekshiramiz. Aks holda
            // ochiq eshik devor bo'lib to'lib qolardi.
            if opening.parentIdentifier != wall.identifier {
                guard abs(local.columns.3.z) < 0.15, abs(c.x) < halfW, abs(c.y) < halfH
                else { continue }
            }
            let half = SIMD2<Float>(opening.dimensions.x / 2, opening.dimensions.y / 2)
            let lo = simd_max(c - half, SIMD2(-halfW, -halfH))
            let hi = simd_min(c + half, SIMD2(halfW, halfH))
            if hi.x - lo.x > minOpeningCut, hi.y - lo.y > minOpeningCut {
                rects.append((min: lo, max: hi))
            }
        }
        return rects
    }

    /// Ekran ortidagi devor bo'lagi — devor-lokal (x,y) kesigi.
    ///
    /// Ekran paneli inject qilingandan keyin devor u yerda KERAK EMAS: ikkalasi ham
    /// yuza bo'lib chiqadi va TV ortida ko'rinib turgan ikkinchi qavat hosil bo'ladi.
    /// Kesik ekrandan 5sm KICHIK — panel (`injectPlanes` da +10sm pad) kesikni
    /// ustma-ust yopadi, halqa shaklidagi teshik qolmaydi.
    private static func screenCutRects(for wall: SurfaceInput,
                                       screens: [TSDFGeometry.WallPlane])
        -> [(min: SIMD2<Float>, max: SIMD2<Float>)] {
        guard !screens.isEmpty else { return [] }
        let t = wall.transform
        var nW = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let lw = simd_length(nW)
        guard lw > 1e-6 else { return [] }
        nW /= lw
        let cW = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let halfW = wall.dimensions.x / 2, halfH = wall.dimensions.y / 2
        let inv = t.inverse
        var rects: [(min: SIMD2<Float>, max: SIMD2<Float>)] = []
        for s in screens {
            // Faqat PARALLEL devor.
            guard abs(simd_dot(nW, s.normalOut)) > 0.7 else { continue }
            // Faqat ekran ORTIDAGI (yoki ust-ust) devor: +10sm dan oldinda bo'lsa
            // tegmaymiz, 45sm dan uzoqda bo'lsa u boshqa devor.
            let along = simd_dot(cW - s.center, s.normalOut)   // + = ekran ortida
            guard along > -0.10, along < 0.45 else { continue }
            let local = inv * SIMD4<Float>(s.center.x, s.center.y, s.center.z, 1)
            let c = SIMD2<Float>(local.x, local.y)
            let half = SIMD2<Float>(max(s.halfW - 0.05, minOpeningCut),
                                    max(s.halfH - 0.05, minOpeningCut))
            let lo = simd_max(c - half, SIMD2(-halfW, -halfH))
            let hi = simd_min(c + half, SIMD2(halfW, halfH))
            if hi.x - lo.x > minOpeningCut, hi.y - lo.y > minOpeningCut {
                rects.append((min: lo, max: hi))
            }
        }
        return rects
    }

    /// Pol konturi world XZ da. `polygonCorners` surface-lokal — floor.transform
    /// bilan world'ga o'tkaziladi. Zaxira: footprint to'rtburchagi.
    private static func floorPolygonXZ(of room: CapturedRoom, bounds: RoomBounds) -> [SIMD2<Float>] {
        func centroidNear(_ poly: [SIMD2<Float>]) -> Bool {
            guard poly.count >= 3 else { return false }
            var c = SIMD2<Float>.zero
            for p in poly { c += p }
            c /= Float(poly.count)
            return c.x > bounds.minX - 1 && c.x < bounds.maxX + 1 &&
                   c.y > bounds.minZ - 1 && c.y < bounds.maxZ + 1
        }
        if let floor = room.floors.max(by: {
            RoomGeometry.polygonArea($0.polygonCorners) < RoomGeometry.polygonArea($1.polygonCorners)
        }), floor.polygonCorners.count >= 3 {
            let t = floor.transform
            let world = floor.polygonCorners.map { c -> SIMD2<Float> in
                let w = t * SIMD4<Float>(c.x, c.y, c.z, 1)
                return SIMD2(w.x, w.z)
            }
            if centroidNear(world) { return world }
        }
        return [SIMD2(bounds.minX, bounds.minZ), SIMD2(bounds.maxX, bounds.minZ),
                SIMD2(bounds.maxX, bounds.maxZ), SIMD2(bounds.minX, bounds.maxZ)]
    }
}
