import Foundation
import simd

/// On-device to'liq-sifat teksturalash — Mac'dagi mvs-texturing (texrecon) pipeline'ining
/// AYNAN o'zi, iOS arm64 static kutubxona (`libtexios.a`) orqali.
///   nuqta buluti → Hoppe implicit sirt → mesh.ply
///   keyframe'lar → scene (kf_*.jpg + kf_*.cam, MVE koordinatasi)
///   ios_texture() → view selection + global/local seam leveling + atlas
/// Natija: OBJ + MTL + material****_map_Kd.png (folder'da).
enum OnDeviceTexturing {

    struct Result {
        let objURL: URL          // texout.obj
        let folder: URL          // barcha fayllar shu yerda
        let seconds: Double      // umumiy vaqt
        let faces: Int           // yakuniy mesh uchburchaklari
    }

    /// Butun pipeline. Fon oqimida chaqiring. `onStage` UI progressi uchun.
    /// Geometriya sifatida BERILGAN mesh.ply ishlatiladi (NSDK mesh — "Model" ko'rinishidagi
    /// bilan bir xil sifatli geometriya). Shu bilan saqlangan skandan QAYTA ISHLASH mumkin.
    static func run(
        meshPLY: URL?,
        keyframes: [KeyframeStore.Keyframe],
        onStage: ((String) -> Void)? = nil
    ) -> Result? {
        let t0 = CFAbsoluteTimeGetCurrent()
        // Bosqich vaqtlarini NSLog'ga yozamiz — qurilmadagi sekin bosqichni ANIQ topish uchun.
        var tStage = t0
        func mark(_ s: String) {
            let now = CFAbsoluteTimeGetCurrent()
            NSLog("ODT[+%06.1fs] %@ (bosqich: %.1fs)", now - t0, s, now - tStage)
            tStage = now
        }
        func stage(_ s: String) { mark(s); onStage?(s) }
        let fm = FileManager.default
        guard keyframes.count >= 2 else { return nil }
        let root = fm.temporaryDirectory.appendingPathComponent("odtex-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let scene = root.appendingPathComponent("scene", isDirectory: true)
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: scene, withIntermediateDirectories: true)
        let meshURL = root.appendingPathComponent("mesh.ply")

        // Bog'langan UNIFORM mesh olamiz (Hoppe). NSDK mesh QO'POL/fragmentlangan bo'lgani
        // uchun to'g'ridan-to'g'ri trim TESHIK yasaydi — avval Hoppe bilan qayta quramiz.
        var connected: WeldedMesh?
        if let meshPLY, fm.fileExists(atPath: meshPLY.path), let nsdk = readPLY(meshPLY) {
            // NSDK mesh sirtidan zich sampling -> Hoppe -> bog'langan uniform
            stage("Sirt qayta qurilmoqda…")
            let pts = MeshSampler.sample(nsdk, count: 200_000)
            if pts.count > 500 {
                // simplify: false — soddalashtirish TRIM'DAN KEYIN (zich mesh'ni trim toza qiladi).
                connected = ImplicitMesher.reconstruct(points: pts, voxelSize: 0.028, simplify: false) { s, p in onStage?("\(s) \(p)%") }
            }
        } else {
            // FALLBACK (eski skanlar): keyframe depth'dan Hoppe
            stage("Sirt qurilmoqda…")
            var cloud = PointCloudBuilder.build(keyframes: keyframes, needColor: false)
            if cloud.count > 300_000 {
                let step = cloud.count / 300_000 + 1
                cloud = stride(from: 0, to: cloud.count, by: step).map { cloud[$0] }
            }
            if cloud.count > 500 {
                NormalEstimator.refine(&cloud, neighborRadius: 0.035)
                connected = ImplicitMesher.reconstruct(points: cloud, voxelSize: 0.028, simplify: false) { s, p in onStage?("\(s) \(p)%") }
            }
        }
        guard var mesh0 = connected, mesh0.indices.count > 300 else { return nil }
        mark("rekonstruksiya: \(mesh0.indices.count / 3) yuz")

        // WINDING FLIP — ImplicitMesher (marching cubes) TESKARI winding beradi.
        // Bu tuzatilmasa: (1) trim normal'lari teskari -> 98% o'chadi; (2) texrecon
        // yuzlarni back-facing deb QORONG'I tekstura beradi. Mac'da tasdiqlandi.
        var flipped = mesh0.indices
        var fk = 0
        while fk + 2 < flipped.count { flipped.swapAt(fk + 1, fk + 2); fk += 3 }
        mesh0 = WeldedMesh(positions: mesh0.positions, normals: mesh0.normals, indices: flipped)

        // VISIBILITY TRIM — endi mesh UNIFORM + winding to'g'ri, trim toza ishlaydi.
        // MUHIM: trim ZICH mesh'da (soddalashtirilmagan) — qo'pol mesh'ni trim 90% o'chiradi.
        stage("Chegara tozalanmoqda…")
        let trimmed = MeshTrimmer.trim(mesh0, keyframes: keyframes) { p in onStage?("Tozalash \(p)%") }
        if trimmed.indices.count > 1000 { mesh0 = trimmed }
        mark("trim: \(mesh0.indices.count / 3) yuz")

        // FREE-SPACE CULL — havoda osilgan floating yuzlarni (va ghost-dublikat geometriyani)
        // depth-map bilan o'chiradi (CHISEL/ReFusion post-hoc). Ghosting'ning katta qismi
        // shu floating dublikatlardan — ularni olib tashlash ghost'ni ham yo'qotadi.
        stage("Osilgan geometriya tozalanmoqda…")
        let culled = MeshTrimmer.freeSpaceCull(mesh0, keyframes: keyframes) { _ in }
        if culled.indices.count > 1000 { mesh0 = culled }
        mark("freeSpaceCull: \(mesh0.indices.count / 3) yuz")

        // KICHIK TESHIKLARNI TO'LDIRISH — trim'dan keyin, ZICH mesh'da (mayda uchburchak).
        // Hoppe bo'shliqlari + trim qoldirgan kichik-o'rta teshiklarni yopadi (ear-clipping).
        // MUHIM: destretch/despike'DAN OLDIN — deraza qirrasidagi mayda fill flaplari keyin
        // removeStretchedFaces bilan tozalanadi (aks holda deraza atrofida qora flap qoladi).
        stage("Teshiklar to'ldirilmoqda…")
        mesh0 = MeshHoleFiller.fill(mesh0, maxHoleEdges: 150, maxFloorCeilEdges: 150)
        mark("teshik-fill")

        // PLANE-SNAP — katta tekis sohalarni (devor/pol/shift) fitlangan tekislikка yopishtirib
        // "to'lqinli/eritilgan" devorlarni MUKAMMAL TEKIS qiladi (burchaklar saqlanadi).
        stage("Devorlar tekislanmoqda…")
        mesh0 = MeshPlaneSnap.snap(mesh0)
        mark("PlaneSnap")

        // CHO'ZILGAN FLAP tozalash — chegaradagi ragged/stretched uchburchaklarni o'chiradi.
        mesh0 = MeshTrimmer.removeStretchedFaces(mesh0, maxEdge: 0.15)
        mark("destretch")

        // CHEGARA TIKAN/FLAP tozalash — chiqib turgan tent-pole spike va needle flaplar.
        mesh0 = MeshTrimmer.removeBoundarySpikes(mesh0, iterations: 3)
        mark("despike")

        // CHEGARA FLAP-SHAVER — teksturalashда QORA chiqadigan ingichka/mayda chegara flaplarини
        // (deraza silueti, shift burchagi) iterativ o'chiradi + floating fragmentni. Mac'да
        // tasdiqlandi: deraza atrofidagi qora bloklar YO'QOLDI, chegara toza.
        mesh0 = MeshTrimmer.shaveBoundaryFlaps(mesh0, iterations: 4)
        mark("flap-shave")

        // POL/SHIFT TESHIK TO'LDIRISH (occupancy-grid) — despike'DAN KEYIN. Yaltiroq plitka
        // LiDAR bo'shligi / shift chiroq-beam oralig'idagi KATTA teshiklarni tekis yopadi
        // (chegara-halqasiga tayanmaydi). Faqat O'RALGAN teshik + ingichka bo'shliq;
        // skanlanmagan ochiq soha va eshik OCHIQ qoladi. Tekis fill RGB'dan teksturalanadi.
        stage("Pol/shift teshiklari to'ldirilmoqda…")
        mesh0 = MeshPlaneFill.fill(mesh0)
        mark("PlaneFill")

        // SKAN QILINMAGAN INTERIOR TESHIK — SILLIQ to'ldirish (Liepa uslubida: ear-clip →
        // sentroid-refine → membrane fairing). Stol tagi / stullar orasi / okklyuziya
        // crevice'larидаги ragged QORA teshiklarni silliq sirt bilan yopadi → RGB'dan
        // teksturalanadi. Tashqi chegara va TEKIS ochiqlik (deraza/eshik) OCHIQ qoladi.
        // Mac'да office skanda tasdiqlandi: stol/stul teshiklari to'ldi, deraza ochiq qoldi.
        stage("Skanlanmagan joylar to'ldirilmoqda…")
        mesh0 = MeshSmoothFill.fill(mesh0, refineLevels: 2, fairIterations: 40)
        mark("SmoothFill")

        // XONADAN TASHQARIDAGI FLOATING MESH KESISH — devor/pol/shift chetlaridan bo'sh fazoga
        // cho'zilgan ingichka tendril/flaplarни oladi (deep-research: footprint envelope clip —
        // pol∪shift XZ-occupancy → close+OPEN (ingichka tendril ket) → margin → tashqari KESISH).
        // Fill'lardan KEYIN (footprint to'liq). Mac'да lastroom skanда tasdiqlandi.
        stage("Tashqi floating tozalanmoqda…")
        mesh0 = MeshEnvelopeClip.clip(mesh0)
        mark("EnvelopeClip")

        // SODDALASHTIRISH — barcha tozalashdan KEYIN (xatlas/texrecon tezligi uchun, ~150K).
        // Endi mesh zich va to'liq, meshopt topologiyani saqlab kamaytiradi (teshik ochmaydi).
        stage("Soddalashtirilmoqda…")
        mesh0 = ImplicitMesher.simplifyMesh(mesh0, targetTriangles: 150_000)
        mark("simplify: \(mesh0.indices.count / 3) yuz")

        // CHEGARA SILLIQLASH — ochiq chegara (siluet + qolgan teshik chetlari) "burchak-burchak"
        // qirralarини halqa bo'ylab Laplacian bilan TEKIS egri qiladi (foydalanuvchi so'radi).
        mesh0 = MeshTrimmer.smoothBoundary(mesh0, iterations: 8, alpha: 0.5)
        mark("smoothBoundary")

        guard writePLY(mesh0, to: meshURL) else { return nil }
        let faceCount = mesh0.indices.count / 3

        // scene: har keyframe -> kf_NNNN.jpg + kf_NNNN.cam (MVE)
        stage("Kadrlar tayyorlanmoqda…")
        writeScene(keyframes, to: scene)
        mark("writeScene: \(keyframes.count) kadr")

        // 4) ios_texture() — desktop-sifat seam-leveled teksturalash
        stage("Teksturalash (seam leveling)…")
        let outPrefix = root.appendingPathComponent("texout")
        #if targetEnvironment(simulator)
        // texios (libtexios.a) faqat arm64 DEVICE uchun buildlangan — simulatorda
        // link YO'Q. HQ teksturalash faqat qurilmada ishlaydi.
        NSLog("OnDeviceTexturing: HQ texturing simulatorda mavjud emas (LiDAR qurilma kerak)")
        let rc: Int32 = -1
        #else
        let rc = scene.withUnsafeFileSystemRepresentation { sp in
            meshURL.withUnsafeFileSystemRepresentation { mp in
                outPrefix.withUnsafeFileSystemRepresentation { op in
                    ios_texture(sp, mp, op, 1, 1)   // keepUnseen=1 (yuz O'CHIRMAYDI → katta teshik
                    // yo'q) + oshirilgan MAX_HOLE_NUM_FACES (libtexios) → ko'rilmagan yuzlar mvs
                    // fill_hole bilan CHEGARA RANGIDAN to'ladi (speckle KAMAYADI). keep_unseen=0
                    // yuzlarni o'chirib katta burchak-teshik ochardi — SHUNDAN VOZ KECHILDI.
                    // outlier=gauss_damping.
                }
            }
        }
        #endif
        mark("ios_texture")
        let objURL = root.appendingPathComponent("texout.obj")
        guard rc == 0, fm.fileExists(atPath: objURL.path) else {
            NSLog("ios_texture failed rc=\(rc)")
            return nil
        }
        let secs = CFAbsoluteTimeGetCurrent() - t0
        NSLog("OnDeviceTexturing: %.1fs, %d faces", secs, faceCount)
        return Result(objURL: objURL, folder: root, seconds: secs, faces: faceCount)
    }

    /// PLY header'dan face sonini o'qiydi (statistika uchun).
    private static func plyFaceCount(_ url: URL) -> Int {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? fh.close() }
        let head = fh.readData(ofLength: 2048)
        guard let s = String(data: head, encoding: .ascii) ?? String(data: head, encoding: .utf8) else { return 0 }
        for line in s.split(separator: "\n") where line.hasPrefix("element face ") {
            return Int(line.dropFirst("element face ".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    /// Binary PLY (x y z + face list) -> WeldedMesh.
    static func readPLY(_ url: URL) -> WeldedMesh? {
        guard let data = try? Data(contentsOf: url),
              let he = data.range(of: Data("end_header\n".utf8)),
              let header = String(data: data.subdata(in: data.startIndex..<he.upperBound), encoding: .ascii)
        else { return nil }
        var vn = 0, fn = 0
        for line in header.split(separator: "\n") {
            if line.hasPrefix("element vertex ") { vn = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0 }
            else if line.hasPrefix("element face ") { fn = Int(line.dropFirst(13).trimmingCharacters(in: .whitespaces)) ?? 0 }
        }
        guard vn > 0, fn > 0 else { return nil }
        let body = data.subdata(in: he.upperBound..<data.endIndex)
        var positions = [SIMD3<Float>](); positions.reserveCapacity(vn)
        var indices = [UInt32](); indices.reserveCapacity(fn * 3)
        body.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            var cur = 0
            for _ in 0..<vn {
                let x = p.loadUnaligned(fromByteOffset: cur, as: Float32.self); cur += 4
                let y = p.loadUnaligned(fromByteOffset: cur, as: Float32.self); cur += 4
                let z = p.loadUnaligned(fromByteOffset: cur, as: Float32.self); cur += 4
                positions.append(SIMD3<Float>(x, y, z))
            }
            for _ in 0..<fn {
                let cnt = p.load(fromByteOffset: cur, as: UInt8.self); cur += 1
                guard cnt == 3, cur + 12 <= p.count else { break }
                let a = p.loadUnaligned(fromByteOffset: cur, as: Int32.self); cur += 4
                let b = p.loadUnaligned(fromByteOffset: cur, as: Int32.self); cur += 4
                let c = p.loadUnaligned(fromByteOffset: cur, as: Int32.self); cur += 4
                indices.append(UInt32(a)); indices.append(UInt32(b)); indices.append(UInt32(c))
            }
        }
        guard positions.count == vn, !indices.isEmpty else { return nil }
        return WeldedMesh(positions: positions, normals: [], indices: indices)
    }

    // MARK: - NSDK mesh -> PLY (binary_little_endian: x y z + faces)

    /// NSDK chunk'larni bitta mesh'ga payvandlab PLY yozadi (geometriya manbai).
    @discardableResult
    static func writeWeldedPLY(_ geometries: [Int64: ChunkGeometry], to url: URL) -> Bool {
        let mesh = MeshWelder.weld(geometries)
        guard mesh.positions.count > 100, mesh.indices.count > 300 else { return false }
        return writePLY(mesh, to: url)
    }

    private static func writePLY(_ mesh: WeldedMesh, to url: URL) -> Bool {
        let vn = mesh.positions.count
        let fn = mesh.indices.count / 3
        var header = "ply\nformat binary_little_endian 1.0\n"
        header += "element vertex \(vn)\n"
        header += "property float x\nproperty float y\nproperty float z\n"
        header += "element face \(fn)\n"
        header += "property list uchar int vertex_indices\n"
        header += "end_header\n"
        var data = Data(header.utf8)
        data.reserveCapacity(header.count + vn * 12 + fn * 13)
        for p in mesh.positions {
            var x = p.x, y = p.y, z = p.z
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { data.append(contentsOf: $0) }
        }
        var i = 0
        while i + 2 < mesh.indices.count {
            var c: UInt8 = 3
            var a = Int32(mesh.indices[i]), b = Int32(mesh.indices[i + 1]), cc = Int32(mesh.indices[i + 2])
            withUnsafeBytes(of: &c) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &a) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &b) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &cc) { data.append(contentsOf: $0) }
            i += 3
        }
        do { try data.write(to: url); return true } catch { NSLog("PLY write: \(error)"); return false }
    }

    // MARK: - Scene (.cam MVE format)
    // MVE kamera: +Z forward, y-DOWN ; ARKit: -Z, y-UP -> o'girish.

    private static func writeScene(_ keyframes: [KeyframeStore.Keyframe], to dir: URL) {
        for (i, kf) in keyframes.enumerated() {
            let name = String(format: "kf_%04d", i)
            try? kf.jpegData.write(to: dir.appendingPathComponent("\(name).jpg"))

            let m = kf.transform
            // ARKit camera->world ustunlari
            let rightX = m.columns.0.x, rightY = m.columns.0.y, rightZ = m.columns.0.z
            let upX = m.columns.1.x, upY = m.columns.1.y, upZ = m.columns.1.z
            let backX = m.columns.2.x, backY = m.columns.2.y, backZ = m.columns.2.z
            let px = m.columns.3.x, py = m.columns.3.y, pz = m.columns.3.z
            // MVE camera->world bazis USTUNLARI: right, -up, -back.
            // .cam world->camera rotatsiyani (Rw2c = transpose) row-major kutadi.
            // Rw2c QATORLARI = [right, -up, -back] (har qator — bitta dunyo o'qi).
            let r00: Float = rightX, r01: Float = rightY, r02: Float = rightZ   // row0 = right
            let r10: Float = -upX,   r11: Float = -upY,   r12: Float = -upZ     // row1 = -up
            let r20: Float = -backX, r21: Float = -backY, r22: Float = -backZ   // row2 = -back
            let tx: Float = -(r00 * px + r01 * py + r02 * pz)
            let ty: Float = -(r10 * px + r11 * py + r12 * pz)
            let tz: Float = -(r20 * px + r21 * py + r22 * pz)

            let k = kf.intrinsics
            let fx: Float = k[0][0], cx: Float = k[2][0], cy: Float = k[2][1]
            let dim = Float(max(kf.width, kf.height))
            let flen: Float = fx / dim
            let ppx: Float = cx / Float(kf.width), ppy: Float = cy / Float(kf.height)

            let line1: [Float] = [tx, ty, tz, r00, r01, r02, r10, r11, r12, r20, r21, r22]
            let line2: [Float] = [flen, 0, 0, 1, ppx, ppy]
            let s1 = line1.map { String($0) }.joined(separator: " ")
            let s2 = line2.map { String($0) }.joined(separator: " ")
            let s = s1 + "\n" + s2 + "\n"
            try? s.write(to: dir.appendingPathComponent("\(name).cam"), atomically: true, encoding: .utf8)

            // LiDAR depth (.dpt: [i32 w][i32 h][f32...]) — teksturalashda OKKLYUZIYA testi
            // uchun (kabel/stul/odam ortidagi devorga "arvoh" proyeksiya bo'lmasin).
            if let dm = kf.depthMap, kf.depthWidth > 0, kf.depthHeight > 0,
               dm.count >= kf.depthWidth * kf.depthHeight {
                var d = Data(capacity: 8 + dm.count * 4)
                var w32 = Int32(kf.depthWidth), h32 = Int32(kf.depthHeight)
                withUnsafeBytes(of: &w32) { d.append(contentsOf: $0) }
                withUnsafeBytes(of: &h32) { d.append(contentsOf: $0) }
                dm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
                try? d.write(to: dir.appendingPathComponent("\(name).dpt"))
            }
        }
    }
}
