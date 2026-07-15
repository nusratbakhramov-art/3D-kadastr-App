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
        if let tsdf = TSDFGeometry.build(paths: paths, log: { log.log($0) }) {
            var decimated = PoissonService.decimate(tsdf, targetTris: 180_000)
            // Devor ortiga chiqib ketgan geometriya kesiladi — teshik-to'ldirish
            // KEYIN ishlaydi (kesish hosil qilgan mayda teshiklarni ham yopadi).
            decimated = RoomClipper.clip(decimated, room: room, log: { log.log($0) })
            // Yakuniy silliqlash: decimation qirralarni qaytadan burchakli
            // qiladi — 3 Taubin jufti ularni roundlashtiradi.
            decimated = TSDFGeometry.taubinSmooth(decimated, pairs: 3)
            // Ochiq chegara arra-tishlarini silliqlash (teshik-fill'dan OLDIN —
            // fill halqalari silliqlangan pozitsiyalarga mos bo'lsin).
            decimated = TSDFGeometry.smoothBoundary(decimated, log: { log.log($0) })
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
        AtlasInpainter.run(objURL: objURL) { log.log($0) }

        // 4. MeshPrep zaxira ishlatilgan bo'lsa — teshiklarga atlas chegara rangi.
        // (Poisson yo'lida teshik yo'q — bu qadam o'tkaziladi.)
        if let fillMesh {
            progress(0.9, "Teshiklar to'ldirilmoqda…")
            FillColorizer.appendFill(fill: fillMesh, objURL: objURL) { log.log($0) }
        }

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

    /// Texrecon uchun ko'rish soni qopqog'i: qamrov uchun ~150 kadr yetarli.
    private static let maxTexViews = 150
    /// Data-costs uchun maksimal tomon (px).
    private static let texImageMaxDim = 2048

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
        var poses = withImage
        if withImage.count > maxTexViews {
            let step = Float(withImage.count) / Float(maxTexViews)
            var sel: [KeyframePose] = []
            var acc: Float = 0
            while Int(acc) < withImage.count && sel.count < maxTexViews {
                sel.append(withImage[Int(acc)])
                acc += step
            }
            poses = sel
        }

        var downscaled = 0
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: poses.count) { i in
            let idx = poses[i].index
            let src = paths.imagesFolder.appendingPathComponent(String(format: "frame_%04d.jpg", idx))
            let dst = sceneDir.appendingPathComponent(String(format: "frame_%04d.jpg", idx))
            if downscaleJPEG(from: src, to: dst, maxDim: texImageMaxDim) {
                lock.lock(); downscaled += 1; lock.unlock()
            } else {
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }
        log("TEXSCENE views=\(poses.count)/\(withImage.count) downscaled=\(downscaled) -> \(texImageMaxDim)px")

        try writeCameras(paths: paths, poses: poses, sceneDir: sceneDir)
        writeExposureSidecars(poses: poses, sceneDir: sceneDir, log: log)
        return sceneDir
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
