import Foundation
import RoomPlan
import simd
import ImageIO
import CoreGraphics

/// On-device sanoat teksturalash (texrecon iOS porti).
/// Fusion mesh'ini (mesh.bin) + kamera pozalarini MVE sahnasiga aylantirib,
/// C++ `pcscan_texture` (graph-cut view tanlash + seam leveling + atlas) ni chaqiradi.
/// Natija: teksturali OBJ + MTL + atlas PNG'lar.
enum TexReconService {

    enum TexError: LocalizedError {
        case noMesh
        case cppFailed(Int32)
        case noOutput
        var errorDescription: String? {
            switch self {
            case .noMesh: return "Mesh topilmadi."
            case .cppFailed(let c): return "Teksturalash muvaffaqiyatsiz (kod \(c))."
            case .noOutput: return "Teksturalash natija bermadi."
            }
        }
    }

    /// Natija OBJ fayl URL manzili.
    /// Geometriya: ARKit real-time mesh (arkit_mesh.bin) — tozalanadi (MeshPrep).
    /// Eski skanlar uchun zaxira: TSDF fusion meshi (mesh.bin).
    static func run(paths: ScanPaths, room: CapturedRoom,
                    progress: @escaping (Double, String) -> Void) throws -> URL {
        progress(0.05, "Mesh tayyorlanmoqda…")
        let log = DebugLog(url: paths.debugLog)
        let rawMesh: LiDARMeshData
        if let arkit = try? LiDARMesh.read(from: paths.arkitMeshURL), !arkit.isEmpty {
            rawMesh = arkit
            log.log("TEXRECON source=arkit_mesh verts=\(arkit.vertexCount)")
        } else {
            rawMesh = try LiDARMesh.read(from: paths.lidarMeshURL)
            log.log("TEXRECON source=tsdf_mesh verts=\(rawMesh.vertexCount)")
        }
        guard !rawMesh.isEmpty else { throw TexError.noMesh }

        try FileManager.default.createDirectory(at: paths.texturesDir, withIntermediateDirectories: true)

        // Geometriya tanlash (3.0.6 eksperiment):
        //   1. TSDF (Polycam uslubi) — bo'sh fazo integratsiya paytida o'yiladi,
        //      "parda"/halo UMUMAN paydo bo'lmaydi; mayda teshiklar lokal yopiladi.
        //   2. Poisson (avvalgi asosiy) — TSDF qurolmasa.
        //   3. MeshPrep + FillColorizer — oxirgi zaxira.
        progress(0.08, "Xona qurilmoqda…")
        let camPositions = loadCameraPositions(paths: paths)
        let meshForTexrecon: LiDARMeshData
        var fillMesh: LiDARMeshData? = nil
        // Struktura tekisliklari (RoomPlan devor/pol/shift) — ko'rilmagan joyda
        // devor TEKIS davom etsin.
        //
        // Kalit nomi "strukturaToldirish" EMAS: o'sha nom 5.4.0 liniyasida ishlatilgan
        // va u yerda default O'CHIQ edi. Bundle id bir xil (com.pcscan.app) → eski
        // `false` qiymati qurilmada SAQLANIB QOLADI va yangi kodni jimgina o'chirib
        // qo'yadi (aynan shu bo'ldi: 14:44 dagi runda tekislik to'ldirish ishlamadi,
        // chunki qurilmada strukturaToldirish=False yotardi). Yangi nom — toza holat.
        let strukturaON = UserDefaults.standard.object(forKey: "strukturaFill") as? Bool ?? true
        // Shisha muhri (deraza doim, eshik faqat yopiq bo'lsa) — LiDAR shishadan
        // o'tib ketadi, muhrsiz u yerda yuza umuman chiqmaydi. Alohida tumbler:
        // struktura to'ldirishdan MUSTAQIL (u to'g'rilik masalasi, bu — halollik).
        let glassON = UserDefaults.standard.object(forKey: "glassSeal") as? Bool ?? true
        // Ekran tekisligi (televizor) — qora yaltiroq ekran LiDARga qaytish bermaydi
        // va o'sha teshikka ortdagi DEVOR yozilib qolardi (chetlar bo'rtib ko'rinardi).
        let ekranON = UserDefaults.standard.object(forKey: "ekranPlane") as? Bool ?? true
        let screens = ekranON ? StructurePlanes.objectPlanes(room: room) : []
        // Ekran ortidagi devor bo'lagi kesiladi — ikki qavat yuza qolmasin.
        let structure = strukturaON ? StructurePlanes.planes(room: room, screens: screens) : []
        let openings = glassON ? StructurePlanes.openings(room: room) : []
        // Ekran devordan OLDIN — devor inject qilingan voxel snap qidiruviga tushmasin.
        let planes = screens + structure + openings
        // Har doim log — "jimgina o'chiq" holat qaytarilmasin.
        log.log("EKRAN on=\(ekranON) tekislik=\(screens.count) "
                + "tv=\(room.objects.filter { $0.category == .television }.count) "
                + "devorKesigi=\(structure.reduce(0) { $0 + $1.cutouts.count })")
        log.log("STRUKTURA on=\(strukturaON) tekislik=\(structure.count) devor=\(room.walls.count)")
        log.log("GLASS on=\(glassON) proyom=\(openings.count) muhrlangan=\(openings.filter { $0.seal }.count) "
                + "(" + openings.map { $0.label }.joined(separator: ",") + ")")
        if let tsdf = TSDFGeometry.build(paths: paths, planes: planes, log: { log.log($0) }) {
            // DIAGNOSTIKA (UserDefaults "dumpMesh"): detsimatsiyadan OLDIN va KEYIN
            // geometriyani diskka yozamiz. Tekshirilayotgan savol sof geometrik —
            // eshik zonasidagi ignabargli uchburchaklar (67% maydon, sifat 0.21)
            // SurfaceNets chiqishidami yoki qisqartirish hosil qiladimi. Texturing
            // bosqichiga tegmaydi (450k bilan A/B aynan o'sha yerda crash bergan:
            // geometriya 342186 tris'gacha yetgan, nativ texrecon esa sig'magan).
            let dumpMesh = UserDefaults.standard.bool(forKey: "dumpMesh")
            if dumpMesh {
                let u = paths.root.appendingPathComponent("mesh_raw.ply")
                try? writePLY(tsdf, to: u)
                log.log("DUMP xom mesh -> mesh_raw.ply tris=\(tsdf.indices.count / 3)")
            }
            var decimated = PoissonService.decimate(tsdf, targetTris: 180_000)
            // Qisqartirish g'ijimlikni qaytaradi (o'lchandi: rough p90 0.044 -> 0.218),
            // shuning uchun ishonch bo'yicha silliqlashni SHU YERDA takrorlaymiz.
            decimated = TSDFGeometry.smoothLowConfidenceAfterDecimation(decimated,
                                                                        log: { log.log($0) })
            if dumpMesh {
                try? writePLY(decimated, to: paths.root.appendingPathComponent("mesh_dec.ply"))
                log.log("DUMP detsimatsiyadan keyin -> mesh_dec.ply tris=\(decimated.indices.count / 3)")
            }
            // Devor ortiga chiqib ketgan geometriya kesiladi — teshik-to'ldirish
            // KEYIN ishlaydi (kesish hosil qilgan mayda teshiklarni ham yopadi).
            decimated = RoomClipper.clip(decimated, room: room, log: { log.log($0) })
            // Yakuniy silliqlash: decimation qirralarni qaytadan burchakli
            // qiladi — 3 Taubin jufti ularni roundlashtiradi.
            decimated = TSDFGeometry.taubinSmooth(decimated, pairs: 3)
            // Ochiq chegara arra-tishlarini silliqlash (teshik-fill'dan OLDIN —
            // fill halqalari silliqlangan pozitsiyalarga mos bo'lsin).
            decimated = TSDFGeometry.smoothBoundary(decimated, log: { log.log($0) })
            if dumpMesh {
                try? writePLY(decimated, to: paths.root.appendingPathComponent("mesh_final.ply"))
                log.log("DUMP yakuniy mesh -> mesh_final.ply tris=\(decimated.indices.count / 3)")
            }
            meshForTexrecon = decimated
            fillMesh = TSDFGeometry.smallHoleFill(decimated, log: { log.log($0) })
            log.log("GEOMETRY=tsdf verts=\(decimated.vertexCount) tris=\(decimated.indices.count/3)")
        } else if !camPositions.isEmpty,
           let poisson = PoissonService.reconstruct(mesh: rawMesh, cameraPositions: camPositions,
                                                     paths: paths, depth: 9, log: { log.log($0) }) {
            let clipped = RoomClipper.clip(poisson, room: room, log: { log.log($0) })
            let rounded = TSDFGeometry.taubinSmooth(clipped, pairs: 3)
            meshForTexrecon = TSDFGeometry.smoothBoundary(rounded, log: { log.log($0) })
            log.log("GEOMETRY=poisson verts=\(meshForTexrecon.vertexCount)")
        } else {
            let (holed, fill) = MeshPrep.clean(rawMesh, room: room) { log.log($0) }
            meshForTexrecon = RoomClipper.clip(holed, room: room, log: { log.log($0) })
            fillMesh = fill
            log.log("GEOMETRY=meshprep (poisson/tsdf fallback)")
        }
        guard !meshForTexrecon.isEmpty else { throw TexError.noMesh }

        // Silliqlashdan qolgan nol-yuzali sliver'lar texrecon seam-leveling'ni
        // assert bilan o'ldiradi — PLY'dan oldin tozalaymiz.
        let texMesh = TSDFGeometry.dropDegenerate(meshForTexrecon, log: { log.log($0) })
        guard !texMesh.isEmpty else { throw TexError.noMesh }

        // 1. PLY (binary little-endian) yozamiz.
        let plyURL = paths.texturesDir.appendingPathComponent("mesh.ply")
        try writePLY(texMesh, to: plyURL)

        // 2. MVE sahnasi (5.0.0 — TEZLIK, 4.0.9 porti): vaqtinchalik scene papka:
        //    kadrlar 2048px gacha KICHRAYTIRILADI va 150 tadan ortiq bo'lsa
        //    pozalar bo'ylab tekis tanlanadi. .cam/.depth/.exp normalizatsiya-
        //    langan — kichraytirish ta'sir qilmaydi.
        // Native texrecon ~350MB fixed + ko'rinishlar oladi. Qurilmada shuncha xotira
        // qolmasa (juda band) — native'ni ISHLATMAYMIZ, throw qilamiz: ReconstructionViewModel
        // YENGIL fallback'ga (runFusion / FusionEngine — rangli mesh, native texrecon YO'Q,
        // ancha kam xotira) o'tadi. Crash o'rniga past-sifat lekin ISHLAYDIGAN natija.
        guard MemoryBudget.current().canRunNativeTexrecon else {
            log.log("TEXRECON LOW-MEMORY: native o'tkazib yuborildi -> yengil fallback")
            throw TexError.cppFailed(-98)
        }

        progress(0.12, "Kadrlar tayyorlanmoqda…")
        let sceneDir = try writeScene(paths: paths, log: { log.log($0) })
        defer { try? FileManager.default.removeItem(at: sceneDir) }

        // 3. C++ texrecon (graph-cut + seam leveling + atlas).
        progress(0.2, "Sanoat teksturalash (graph-cut)…")
        let outPrefix = paths.texturesDir.appendingPathComponent("room")
        let tmpDir = paths.texturesDir.appendingPathComponent("tmp")

        #if targetEnvironment(simulator)
        // Native texrecon faqat qurilmada mavjud (kutubxonalar simulyatorга linklanmaydi).
        throw TexError.cppFailed(-99)
        #else
        let rc = sceneDir.path.withCString { scene in
            plyURL.path.withCString { ply in
                outPrefix.path.withCString { out in
                    tmpDir.path.withCString { tmp in
                        pcscan_texture(scene, ply, out, tmp)
                    }
                }
            }
        }
        guard rc == 0 else { throw TexError.cppFailed(rc) }
        #endif

        let objURL = paths.texturesDir.appendingPathComponent("room.obj")
        guard FileManager.default.fileExists(atPath: objURL.path) else { throw TexError.noOutput }

        // 4a. Inpainting: ko'rilmagan (0.55 kulrang) atlas hududlarini atrofdagi
        //     yuza rangi bilan bo'yaymiz. FillColorizer'dan OLDIN — u atlas
        //     chegara ranglarini o'qiydi, bo'yalgan rangni ko'rsin.
        progress(0.85, "Ko'rinmas zonalar bo'yalmoqda…")
        AtlasInpainter.run(objURL: objURL, planes: planes) { log.log($0) }

        // 4. MeshPrep zaxira ishlatilgan bo'lsa — teshiklarga atlas chegara rangi.
        // (Poisson yo'lida teshik yo'q — bu qadam o'tkaziladi.)
        if let fillMesh {
            progress(0.9, "Teshiklar to'ldirilmoqda…")
            FillColorizer.appendFill(fill: fillMesh, objURL: objURL) { log.log($0) }
        }

        // 5. O'tkirlashtirish (unsharp-mask) — yorug' tekis devorlar "sutdek"
        //    chiqmasin. Faqat real tekstura atlaslari; unseen/fill silliqligicha.
        progress(0.97, "O'tkirlashtirilmoqda…")
        AtlasSharpen.run(objURL: objURL) { log.log($0) }
        // Gutter to'ldirish — SHARPEN'dan KEYIN: o'tkirlash halo bermaslik uchun
        // qora fonga tayanadi, dilatatsiya esa o'sha fonni yo'q qiladi.
        AtlasDilate.run(objURL: objURL) { log.log($0) }

        progress(1, "Tayyor")
        return objURL
    }

    // MARK: - PLY (binary little-endian)

    private static func writePLY(_ mesh: LiDARMeshData, to url: URL) throws {
        let vertexCount = mesh.vertexCount
        let faceCount = mesh.indices.count / 3
        var header = "ply\n"
        header += "format binary_little_endian 1.0\n"
        header += "element vertex \(vertexCount)\n"
        header += "property float x\nproperty float y\nproperty float z\n"
        header += "element face \(faceCount)\n"
        header += "property list uchar int vertex_indices\n"
        header += "end_header\n"

        var data = Data(header.utf8)
        // Cho'qqilar (x,y,z float32)
        mesh.positions.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        // Yuzalar (uchar 3 + 3× int32)
        data.reserveCapacity(data.count + faceCount * 13)
        var faceBuf = Data(capacity: faceCount * 13)
        for f in 0..<faceCount {
            faceBuf.append(3)
            for k in 0..<3 {
                var idx = Int32(mesh.indices[f * 3 + k])
                withUnsafeBytes(of: &idx) { faceBuf.append(contentsOf: $0) }
            }
        }
        data.append(faceBuf)
        try data.write(to: url)
    }

    // MARK: - Kamera pozitsiyalari (Poisson normal oriyentatsiyasi uchun)

    private static func loadCameraPositions(paths: ScanPaths) -> [SIMD3<Float>] {
        guard let data = try? Data(contentsOf: paths.framesJSON),
              let poses = try? JSONDecoder().decode([KeyframePose].self, from: data) else { return [] }
        return poses.map { SIMD3($0.transform[12], $0.transform[13], $0.transform[14]) }
    }

    // MARK: - MVE sahnasi (5.0.0: tanlash + kichraytirish + sidecar'lar)

    /// Texrecon uchun ko'rish soni qopqog'i.
    ///
    /// 150 "qamrov uchun yetarli" degan TAXMIN edi — o'lchov uni RAD ETDI.
    /// Skan 20260713-192242 (34 m² ofis, 17 stul + 5 stol + shisha to'siq,
    /// 260 kadr): texrecon yuzalarning 41% iga tekstura bera olmagan, VA
    /// o'sha teksturasiz yuzalarning 81% i O'LCHANGAN yuzadan 8sm ichida
    /// (46% i 3sm ichida) — ya'ni ular uydirma emas, kamera KO'RGAN joy.
    /// Sabab: `views=150/260` — kadrlarning 42% i texrecon'ga berilmagan.
    /// To'la mebelli xonada har yuza 1-2 kadrdagina ko'rinadi; o'sha yagona
    /// kadr tashlansa — yuza teksturasiz qoladi.
    ///
    /// UserDefaults "texMaxViews" bilan sozlanadi (0/yo'q -> default).
    /// Narxi: texrecon vaqti va xotirasi kadr soniga proporsional.
    private static var maxTexViews: Int {
        let v = UserDefaults.standard.integer(forKey: "texMaxViews")
        return v > 0 ? v : 300
    }
    /// Data-costs uchun maksimal tomon (px).
    ///
    /// Yuqori-rezolyutsiya rejimi (UserDefaults "texHiRes", default YOQ):
    ///   - qopqoq 4096 (kelajakda hi-res kadr kelsa saqlanadi);
    ///   - kadr qopqoqdan KICHIK bo'lsa QAYTA SIQILMAYDI — asl JPEG ko'chiriladi.
    ///     O'lchandi (frame_0163, 1920x1440): pipeline uni 0.85 da qayta siqib
    ///     ~4.6% detal yeydi (fayl 482->244 KB). Asl saqlansa — o'sha detal qaytadi.
    /// O'chiq bo'lsa — eski xatti-harakat (qopqoq 2048, doim qayta siqish).
    ///
    /// DIQQAT: ARKit kadri odatda 1920x1440 (`frame.camera.imageResolution`) —
    /// qopqoqni 2048 dan oshirish O'ZI detal bermaydi, chunki manba 1920. Asosiy
    /// yutuq — qayta-siqishni o'tkazib yuborish. Chinakam ko'proq detal faqat
    /// SURATGA OLISH rezolyutsiyasini oshirish bilan (alohida, katta o'zgarish).
    private static var texHiRes: Bool {
        UserDefaults.standard.object(forKey: "texHiRes") as? Bool ?? false
    }
    private static var texImageMaxDim: Int { texHiRes ? 4096 : 2048 }

    /// Vaqtinchalik scene papkani quradi: tanlangan kadrlar (kichraytirilgan
    /// JPEG) + .cam + .depth + .exp. Qaytadi: papka URL.
    private static func writeScene(paths: ScanPaths, log: (String) -> Void) throws -> URL {
        let sceneDir = paths.texturesDir.appendingPathComponent("scene")
        try? FileManager.default.removeItem(at: sceneDir)
        try FileManager.default.createDirectory(at: sceneDir, withIntermediateDirectories: true)

        let posesData = try Data(contentsOf: paths.framesJSON)
        let allPoses = try JSONDecoder().decode([KeyframePose].self, from: posesData)
        let withImage = allPoses.filter { pose in
            FileManager.default.fileExists(
                atPath: paths.imagesFolder.appendingPathComponent(String(format: "frame_%04d.jpg", pose.index)).path)
        }
        // Ko'rinish soni va kadr o'lchami QURILMA XOTIRASIGA moslashadi (native
        // texrecon peak'i ≈ views·dim² — ASOSIY jetsam OOM manbai). Byudjet UserDefaults
        // qiymatini CHEGARALAydi (foydalanuvchi ko'proq so'rasa ham, qurilma ko'targancha).
        let budget = MemoryBudget.current()
        let effViews = min(maxTexViews, budget.maxTexViews)
        let maxDim = min(texImageMaxDim, budget.texImageMaxDim)
        var poses = withImage
        if withImage.count > effViews {
            let step = Float(withImage.count) / Float(effViews)
            var sel: [KeyframePose] = []
            var acc: Float = 0
            while Int(acc) < withImage.count && sel.count < effViews {
                sel.append(withImage[Int(acc)])
                acc += step
            }
            poses = sel
        }

        var downscaled = 0
        var copied = 0
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: poses.count) { i in
            // autoreleasepool: dekodlangan bitmap (~11MB/kadr) har iteratsiyada
            // DARHOL bo'shatilsin — aks holda GCD worker'larda yig'ilib (300 kadr ×
            // 11MB ≈ 3.3GB spike) jetsam beradi.
            autoreleasepool {
                let idx = poses[i].index
                let src = paths.imagesFolder.appendingPathComponent(String(format: "frame_%04d.jpg", idx))
                let dst = sceneDir.appendingPathComponent(String(format: "frame_%04d.jpg", idx))
                // Hi-res YOQ va kadr qopqoqdan KICHIK bo'lsa — qayta siqmasdan asl JPEG
                // ni ko'chiramiz (detal yo'qolmasin).
                if texHiRes, imageLongestSide(src) <= maxDim {
                    try? FileManager.default.removeItem(at: dst)
                    if (try? FileManager.default.copyItem(at: src, to: dst)) != nil {
                        lock.lock(); copied += 1; lock.unlock()
                        return
                    }
                }
                if downscaleJPEG(from: src, to: dst, maxDim: maxDim) {
                    lock.lock(); downscaled += 1; lock.unlock()
                } else {
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }
        log("TEXSCENE views=\(poses.count)/\(withImage.count) hiRes=\(texHiRes) "
            + "copied=\(copied) downscaled=\(downscaled) -> \(maxDim)px "
            + "(byudjet: views≤\(budget.maxTexViews) dim≤\(budget.texImageMaxDim))")

        try writeCameras(paths: paths, poses: poses, sceneDir: sceneDir)
        writeExposureSidecars(poses: poses, sceneDir: sceneDir, log: log)
        return sceneDir
    }

    /// JPEG'ning eng uzun tomonini (px) — dekodlamasdan (faqat metadata).
    private static func imageLongestSide(_ url: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return .max }
        return max(w, h)
    }

    /// JPEG'ni maxDim gacha kichraytirib yozadi (EXIF transformsiz).
    private static func downscaleJPEG(from src: URL, to dst: URL, maxDim: Int) -> Bool {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: false,
                  kCGImageSourceThumbnailMaxPixelSize: maxDim,
              ] as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(dst as CFURL, "public.jpeg" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: - MVE kamera fayllari (.cam)

    private static func writeCameras(paths: ScanPaths, poses: [KeyframePose], sceneDir: URL) throws {
        // ARKit (-Z oldinga, Y yuqori) -> CV (+Z oldinga, Y past): Y,Z belgisini almashtirish.
        let flip = simd_float3x3(diagonal: SIMD3(1, -1, -1))

        for pose in poses {

            let t = pose.transform
            let rC2W = simd_float3x3(
                SIMD3(t[0], t[1], t[2]),
                SIMD3(t[4], t[5], t[6]),
                SIMD3(t[8], t[9], t[10]))
            let center = SIMD3<Float>(t[12], t[13], t[14])
            let rcv = flip * rC2W.transpose        // world->camera (CV)
            let tcv = -(rcv * center)

            let k = pose.intrinsics
            let fx = k[0], cx = k[6], cy = k[7]
            let W = Float(pose.width), H = Float(pose.height)
            let focal = fx / max(W, H)

            // MVE .cam: tx ty tz  R(row-major 9)\n  focal 0 0 1 ppx ppy
            var s = ""
            s += "\(tcv.x) \(tcv.y) \(tcv.z) "
            s += "\(rcv[0][0]) \(rcv[1][0]) \(rcv[2][0]) "
            s += "\(rcv[0][1]) \(rcv[1][1]) \(rcv[2][1]) "
            s += "\(rcv[0][2]) \(rcv[1][2]) \(rcv[2][2])\n"
            s += "\(focal) 0 0 1 \(cx / W) \(cy / H)\n"

            let camURL = sceneDir.appendingPathComponent(String(format: "frame_%04d.cam", pose.index))
            try s.write(to: camURL, atomically: true, encoding: .utf8)

            // LiDAR depth sidecar: "PCDP" | u32 dw | u32 dh | u32 flags(bit0=conf) |
            // dw*dh u16 mm | [dw*dh u8 conf]. C++ pcscan_depth_gate.h o'qiydi.
            if let dw = pose.depthWidth, let dh = pose.depthHeight, dw > 0, dh > 0 {
                let dURL = paths.depthFolder.appendingPathComponent(String(format: "depth_%04d.bin", pose.index))
                guard let dData = try? Data(contentsOf: dURL), dData.count == dw * dh * 2 else { continue }
                let cURL = paths.depthFolder.appendingPathComponent(String(format: "conf_%04d.bin", pose.index))
                let cData = (try? Data(contentsOf: cURL)).flatMap { $0.count == dw * dh ? $0 : nil }

                var out = Data("PCDP".utf8)
                var w32 = UInt32(dw), h32 = UInt32(dh)
                var flags = UInt32(cData != nil ? 1 : 0)
                withUnsafeBytes(of: &w32) { out.append(contentsOf: $0) }
                withUnsafeBytes(of: &h32) { out.append(contentsOf: $0) }
                withUnsafeBytes(of: &flags) { out.append(contentsOf: $0) }
                out.append(dData)
                if let cData { out.append(cData) }
                let sURL = sceneDir.appendingPathComponent(String(format: "frame_%04d.depth", pose.index))
                try? out.write(to: sURL)
            }
        }
    }

    // MARK: - Ekspozitsiya sidecar'lari (.exp)

    /// Har kadr uchun encoded-domen gain hisoblab, frame_NNNN.exp (float32 LE)
    /// sifatida yozadi. C++ (pcscan_exposure.h) load_image'да qo'llaydi.
    private static func writeExposureSidecars(poses: [KeyframePose], sceneDir: URL,
                                              log: (String) -> Void) {
        var valid: [(pose: KeyframePose, url: URL)] = []
        for pose in poses {
            let url = sceneDir.appendingPathComponent(String(format: "frame_%04d.jpg", pose.index))
            if FileManager.default.fileExists(atPath: url.path) { valid.append((pose, url)) }
        }
        guard valid.count >= 3 else { return }

        // O'rtacha yorqinlik (encoded) — kichik thumbnail orqali (tez).
        var lumas = [Float](repeating: 0, count: valid.count)
        for (i, item) in valid.enumerated() {
            lumas[i] = Self.meanLuma(url: item.url) ?? 128
        }
        let gains = ExposureNormalizer.computeGains(lumas: lumas, evs: valid.map { $0.pose.exposureOffset })

        var written = 0
        for (i, item) in valid.enumerated() {
            var g = gains[i]
            guard abs(g - 1) > 0.005 else { continue }   // deyarli 1 — sidecar shart emas
            var out = Data()
            withUnsafeBytes(of: &g) { out.append(contentsOf: $0) }
            let url = sceneDir.appendingPathComponent(String(format: "frame_%04d.exp", item.pose.index))
            if (try? out.write(to: url)) != nil { written += 1 }
        }
        let hasEV = valid.contains { $0.pose.exposureOffset != nil }
        log("EXPOSURE frames=\(valid.count) ev=\(hasEV) sidecars=\(written) " +
            String(format: "gains=[%.2f..%.2f]", gains.min() ?? 1, gains.max() ?? 1))
    }

    /// Kadr o'rtacha yorqinligi (encoded RGB o'rtachasi, 0..255) — 64px thumbnail.
    private static func meanLuma(url: URL) -> Float? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
              ] as CFDictionary) else { return nil }
        let w = 32, h = 24
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0
        var i = 0
        while i < px.count { sum += Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]); i += 4 }
        return Float(sum) / Float(w * h * 3)
    }
}
