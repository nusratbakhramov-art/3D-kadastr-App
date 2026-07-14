import Foundation
import CoreImage
import UIKit
import simd

/// Mesh chunk'larni keyframe rasmlariga proyeksiya qilib, teksturali
/// OBJ + MTL + JPG to'plamini yaratadi va bitta ZIP faylga o'raydi.
///
/// Har bir chunk uchun eng yaxshi ko'rinishdagi bitta keyframe tanlanadi,
/// vertexlar o'sha kadr tekisligiga proyeksiya qilinib UV hisoblanadi.
enum TexturedOBJExporter {

    /// Mesh koordinatalari RealityKit fazosida (NSDK'dan Y/Z teskari o'girilgan).
    /// Keyframe pozalari esa ARKit fazosida — bu ikkalasi bir xil fazo, shuning
    /// uchun proyeksiyadan oldin vertexni ARKit fazosiga qaytarish SHART EMAS.
    static func export(
        geometries: [Int64: ChunkGeometry],
        keyframes: [KeyframeStore.Keyframe]
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "Xona-\(formatter.string(from: Date()))"

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Chunk → keyframe tayinlash
        let assignments = assignKeyframes(geometries: geometries, keyframes: keyframes)
        let usedKeyframes = Set(assignments.values)

        // Kadrlar orasidagi rang/ekspozitsiya farqini tekislash
        let gains = ColorHarmonizer.computeGains(
            geometries: geometries, keyframes: keyframes, assignments: assignments
        )

        // Ishlatilgan keyframe JPG'larini yozish (gain qo'llangan holda)
        let ciContext = CIContext()
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        for index in usedKeyframes {
            let url = folder.appendingPathComponent("kf_\(index).jpg")
            let data = keyframes[index].jpegData
            if let gain = gains[index], !gain.isNearIdentity,
               let ciImage = CIImage(data: data),
               let adjusted = try? ciContext.jpegRepresentation(
                of: ColorHarmonizer.apply(gain, to: ciImage),
                colorSpace: srgb,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8]
               ) {
                try adjusted.write(to: url)
            } else {
                try data.write(to: url)
            }
        }

        // MTL
        var mtl = "# ScansApp textured export\n"
        for index in usedKeyframes.sorted() {
            mtl += "newmtl kf_\(index)\nKd 1.0 1.0 1.0\nmap_Kd kf_\(index).jpg\n\n"
        }
        mtl += "newmtl untextured\nKd 0.6 0.6 0.6\n"
        try mtl.write(
            to: folder.appendingPathComponent("model.mtl"),
            atomically: true, encoding: .utf8
        )

        // OBJ
        var lines: [String] = [
            "# ScansApp textured room mesh",
            "mtllib model.mtl",
        ]
        var vOffset: UInt32 = 1
        var vtOffset: UInt32 = 1
        var vnOffset: UInt32 = 1

        for (id, geo) in geometries.sorted(by: { $0.key < $1.key }) {
            lines.append("o chunk_\(id)")

            for p in geo.positions {
                lines.append("v \(p.x) \(p.y) \(p.z)")
            }

            let hasNormals = geo.normals != nil
            if let normals = geo.normals {
                for n in normals {
                    lines.append("vn \(n.x) \(n.y) \(n.z)")
                }
            }

            if let kfIndex = assignments[id] {
                let kf = keyframes[kfIndex]
                for p in geo.positions {
                    let uv = projectUV(point: p, keyframe: kf)
                    lines.append("vt \(uv.x) \(uv.y)")
                }
                lines.append("usemtl kf_\(kfIndex)")

                var i = 0
                while i + 2 < geo.indices.count {
                    let a = geo.indices[i], b = geo.indices[i + 1], c = geo.indices[i + 2]
                    if hasNormals {
                        lines.append(
                            "f \(a + vOffset)/\(a + vtOffset)/\(a + vnOffset)"
                            + " \(b + vOffset)/\(b + vtOffset)/\(b + vnOffset)"
                            + " \(c + vOffset)/\(c + vtOffset)/\(c + vnOffset)"
                        )
                    } else {
                        lines.append(
                            "f \(a + vOffset)/\(a + vtOffset)"
                            + " \(b + vOffset)/\(b + vtOffset)"
                            + " \(c + vOffset)/\(c + vtOffset)"
                        )
                    }
                    i += 3
                }
                vtOffset += UInt32(geo.positions.count)
            } else {
                lines.append("usemtl untextured")
                var i = 0
                while i + 2 < geo.indices.count {
                    let a = geo.indices[i], b = geo.indices[i + 1], c = geo.indices[i + 2]
                    if hasNormals {
                        lines.append(
                            "f \(a + vOffset)//\(a + vnOffset)"
                            + " \(b + vOffset)//\(b + vnOffset)"
                            + " \(c + vOffset)//\(c + vnOffset)"
                        )
                    } else {
                        lines.append("f \(a + vOffset) \(b + vOffset) \(c + vOffset)")
                    }
                    i += 3
                }
            }

            vOffset += UInt32(geo.positions.count)
            if hasNormals {
                vnOffset += UInt32(geo.positions.count)
            }
        }

        try lines.joined(separator: "\n").write(
            to: folder.appendingPathComponent("model.obj"),
            atomically: true, encoding: .utf8
        )

        // Papkani ZIP'ga o'rash (NSFileCoordinator .forUploading zip yaratadi)
        let zipDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName).zip")
        try? FileManager.default.removeItem(at: zipDestination)

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: folder, options: .forUploading, error: &coordinatorError
        ) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: zipDestination)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }

        try? FileManager.default.removeItem(at: folder)
        return zipDestination
    }

    // MARK: - Oddiy mesh eksport (teksturasiz, faqat geometriya)

    static func exportPlainMesh(_ mesh: WeldedMesh) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "Xona-\(formatter.string(from: Date()))"

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var lines: [String] = ["# ScansApp mesh (geometriya)", "o room"]
        lines.reserveCapacity(mesh.positions.count * 2 + mesh.indices.count / 3 + 4)
        for p in mesh.positions {
            lines.append("v \(p.x) \(p.y) \(p.z)")
        }
        for n in mesh.normals {
            lines.append("vn \(n.x) \(n.y) \(n.z)")
        }
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.indices[i] + 1, b = mesh.indices[i + 1] + 1, c = mesh.indices[i + 2] + 1
            lines.append("f \(a)//\(a) \(b)//\(b) \(c)//\(c)")
            i += 3
        }
        try lines.joined(separator: "\n").write(
            to: folder.appendingPathComponent("model.obj"),
            atomically: true, encoding: .utf8
        )

        let zipDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName).zip")
        try? FileManager.default.removeItem(at: zipDestination)
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: folder, options: .forUploading, error: &coordinatorError
        ) { zippedURL in
            do { try FileManager.default.copyItem(at: zippedURL, to: zipDestination) }
            catch { copyError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        try? FileManager.default.removeItem(at: folder)
        return zipDestination
    }

    // MARK: - Atlas eksport (yagona mesh + yagona tekstura — Scaniverse formatiga o'xshash)

    static func exportAtlas(_ model: AtlasModel, pointCloudPLY: Data? = nil) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "Xona-\(formatter.string(from: Date()))"

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let jpeg = UIImage(cgImage: model.atlasImage).jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "ScansApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Atlas JPEG encode failed"])
        }
        try jpeg.write(to: folder.appendingPathComponent("texture.jpg"))

        if let pointCloudPLY {
            try pointCloudPLY.write(to: folder.appendingPathComponent("point_cloud.ply"))
        }

        let mtl = "# ScansApp atlas export\nnewmtl main\nKd 1.0 1.0 1.0\nmap_Kd texture.jpg\n"
        try mtl.write(
            to: folder.appendingPathComponent("model.mtl"),
            atomically: true, encoding: .utf8
        )

        var lines: [String] = ["# ScansApp room mesh (single atlas)", "mtllib model.mtl", "o room", "usemtl main"]
        lines.reserveCapacity(model.positions.count * 3 + model.indices.count / 3 + 8)
        for p in model.positions {
            lines.append("v \(p.x) \(p.y) \(p.z)")
        }
        for uv in model.uvs {
            lines.append("vt \(uv.x) \(uv.y)")
        }
        for n in model.normals {
            lines.append("vn \(n.x) \(n.y) \(n.z)")
        }
        var i = 0
        while i + 2 < model.indices.count {
            let a = model.indices[i] + 1, b = model.indices[i + 1] + 1, c = model.indices[i + 2] + 1
            lines.append("f \(a)/\(a)/\(a) \(b)/\(b)/\(b) \(c)/\(c)/\(c)")
            i += 3
        }
        try lines.joined(separator: "\n").write(
            to: folder.appendingPathComponent("model.obj"),
            atomically: true, encoding: .utf8
        )

        let zipDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName).zip")
        try? FileManager.default.removeItem(at: zipDestination)

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: folder, options: .forUploading, error: &coordinatorError
        ) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: zipDestination)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }

        try? FileManager.default.removeItem(at: folder)
        return zipDestination
    }

    // MARK: - Baked eksport

    /// Qayta ishlangan (bake qilingan) modelni OBJ + MTL + chunk teksturalari
    /// sifatida ZIP'ga eksport qiladi.
    static func exportBaked(_ baked: [Int64: TextureBaker.BakedChunk]) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "Xona-\(formatter.string(from: Date()))"

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Teksturalar
        var mtl = "# ScansApp baked export\n"
        for (id, chunk) in baked.sorted(by: { $0.key < $1.key }) {
            guard let image = chunk.image,
                  let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.9)
            else { continue }
            try jpeg.write(to: folder.appendingPathComponent("chunk_\(id).jpg"))
            mtl += "newmtl chunk_\(id)\nKd 1.0 1.0 1.0\nmap_Kd chunk_\(id).jpg\n\n"
        }
        mtl += "newmtl untextured\nKd 0.6 0.6 0.6\n"
        try mtl.write(
            to: folder.appendingPathComponent("model.mtl"),
            atomically: true, encoding: .utf8
        )

        // OBJ
        var lines: [String] = ["# ScansApp baked room mesh", "mtllib model.mtl"]
        var vOffset: UInt32 = 1
        var vtOffset: UInt32 = 1
        var vnOffset: UInt32 = 1

        for (id, chunk) in baked.sorted(by: { $0.key < $1.key }) {
            let geo = chunk.geometry
            lines.append("o chunk_\(id)")

            for p in geo.positions {
                lines.append("v \(p.x) \(p.y) \(p.z)")
            }
            for uv in chunk.uvs {
                lines.append("vt \(uv.x) \(uv.y)")
            }
            let hasNormals = geo.normals != nil
            if let normals = geo.normals {
                for nrm in normals {
                    lines.append("vn \(nrm.x) \(nrm.y) \(nrm.z)")
                }
            }

            lines.append(chunk.image != nil ? "usemtl chunk_\(id)" : "usemtl untextured")

            var i = 0
            while i + 2 < geo.indices.count {
                let a = geo.indices[i], b = geo.indices[i + 1], c = geo.indices[i + 2]
                if hasNormals {
                    lines.append(
                        "f \(a + vOffset)/\(a + vtOffset)/\(a + vnOffset)"
                        + " \(b + vOffset)/\(b + vtOffset)/\(b + vnOffset)"
                        + " \(c + vOffset)/\(c + vtOffset)/\(c + vnOffset)"
                    )
                } else {
                    lines.append(
                        "f \(a + vOffset)/\(a + vtOffset)"
                        + " \(b + vOffset)/\(b + vtOffset)"
                        + " \(c + vOffset)/\(c + vtOffset)"
                    )
                }
                i += 3
            }

            vOffset += UInt32(geo.positions.count)
            vtOffset += UInt32(geo.positions.count)
            if hasNormals { vnOffset += UInt32(geo.positions.count) }
        }

        try lines.joined(separator: "\n").write(
            to: folder.appendingPathComponent("model.obj"),
            atomically: true, encoding: .utf8
        )

        let zipDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName).zip")
        try? FileManager.default.removeItem(at: zipDestination)

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: folder, options: .forUploading, error: &coordinatorError
        ) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: zipDestination)
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }

        try? FileManager.default.removeItem(at: folder)
        return zipDestination
    }

    // MARK: - HQ xom eksport (offline Mac qayta ishlash uchun)

    /// Xom keyframe rasmlar (to'liq res) + kamera poza/intrinsics + depth + mesh'ni
    /// bitta ZIP'ga eksport qiladi. Bu — offline (Mac) TO'LIQ-SIFAT teksturalash uchun:
    /// har bir to'liq-res foto meshga proyeksiya qilinib, yuqori-res atlas bake qilinadi.
    /// On-device 256² chunk teksturalari o'rniga asl kamera piksellari ishlatiladi.
    ///
    /// Proyeksiya konvensiyasi (offline kod shuni takrorlashi kerak):
    ///   p_cam = inverse(transform) * [x,y,z,1]   // transform = camera→world
    ///   depth = -p_cam.z                          // kamera -Z ga qaraydi
    ///   u = fx * p_cam.x / depth + cx
    ///   v = cy - fy * p_cam.y / depth             // v yuqoridan
    /// Mesh koordinatalari keyframe transform bilan bir xil fazoda (ARKit/RealityKit).
    static func exportRawCapture(
        geometries: [Int64: ChunkGeometry],
        keyframes: [KeyframeStore.Keyframe]
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "XonaHQ-\(formatter.string(from: Date()))"

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let kfDir = folder.appendingPathComponent("keyframes", isDirectory: true)
        try FileManager.default.createDirectory(at: kfDir, withIntermediateDirectories: true)

        // 1) Keyframe'lar: to'liq-res JPEG + depth binary + manifest yozuvlari
        var frameEntries: [[String: Any]] = []
        for (i, kf) in keyframes.enumerated() {
            let name = String(format: "kf_%04d", i)
            try kf.jpegData.write(to: kfDir.appendingPathComponent("\(name).jpg"))

            var depthRef = ""
            if let depth = kf.depthMap, kf.depthWidth > 0, kf.depthHeight > 0 {
                var d = depth
                let depthData = d.withUnsafeBytes { Data($0) }
                try depthData.write(to: kfDir.appendingPathComponent("\(name).depth"))
                depthRef = "keyframes/\(name).depth"
            }

            let t = kf.transform
            let transformColMajor: [Float] = [
                t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
                t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
                t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
                t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w,
            ]
            let k = kf.intrinsics
            frameEntries.append([
                "file": "keyframes/\(name).jpg",
                "w": kf.width, "h": kf.height,
                "fx": k[0][0], "fy": k[1][1], "cx": k[2][0], "cy": k[2][1],
                "transform": transformColMajor,   // column-major camera→world
                "sharpness": kf.sharpness,
                "depth": depthRef, "dw": kf.depthWidth, "dh": kf.depthHeight,
            ])
        }

        let manifest: [String: Any] = [
            "version": 1,
            "space": "ARKit/RealityKit (Y-up, -Z forward)",
            "projection": "p_cam = inv(transform)*p_world; depth=-p_cam.z; u=fx*x/depth+cx; v=cy-fy*y/depth",
            "mesh": "model.obj",
            "frameCount": frameEntries.count,
            "frames": frameEntries,
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: folder.appendingPathComponent("frames.json"))

        // 2) Mesh (barcha chunk'lar bitta OBJ'da, RealityKit fazosida)
        var lines: [String] = ["# ScansApp HQ raw mesh"]
        var vOffset: UInt32 = 1
        var vnOffset: UInt32 = 1
        for (id, geo) in geometries.sorted(by: { $0.key < $1.key }) {
            lines.append("o chunk_\(id)")
            for p in geo.positions { lines.append("v \(p.x) \(p.y) \(p.z)") }
            let hasNormals = geo.normals != nil
            if let normals = geo.normals {
                for nrm in normals { lines.append("vn \(nrm.x) \(nrm.y) \(nrm.z)") }
            }
            var i = 0
            while i + 2 < geo.indices.count {
                let a = geo.indices[i], b = geo.indices[i + 1], c = geo.indices[i + 2]
                if hasNormals {
                    lines.append("f \(a + vOffset)//\(a + vnOffset) \(b + vOffset)//\(b + vnOffset) \(c + vOffset)//\(c + vnOffset)")
                } else {
                    lines.append("f \(a + vOffset) \(b + vOffset) \(c + vOffset)")
                }
                i += 3
            }
            vOffset += UInt32(geo.positions.count)
            if hasNormals { vnOffset += UInt32(geo.positions.count) }
        }
        try lines.joined(separator: "\n").write(
            to: folder.appendingPathComponent("model.obj"),
            atomically: true, encoding: .utf8
        )

        // 3) ZIP
        let zipDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName).zip")
        try? FileManager.default.removeItem(at: zipDestination)
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: folder, options: .forUploading, error: &coordinatorError
        ) { zippedURL in
            do { try FileManager.default.copyItem(at: zippedURL, to: zipDestination) }
            catch { copyError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }

        try? FileManager.default.removeItem(at: folder)
        return zipDestination
    }

    // MARK: - Keyframe tanlash

    /// Barcha chunk'larga keyframe tayinlaydi. Qo'shni chunk'lar (2 m radiusda)
    /// ishlatgan kadrga ustunlik beriladi — choklar va rang farqlari kamayadi.
    static func assignKeyframes(
        geometries: [Int64: ChunkGeometry],
        keyframes: [KeyframeStore.Keyframe]
    ) -> [Int64: Int] {
        var assignments: [Int64: Int] = [:]

        for (id, geo) in geometries.sorted(by: { $0.key < $1.key }) {
            guard let (samples, centroid) = chunkSamples(geo) else { continue }

            if let best = bestKeyframe(
                samples: samples, centroid: centroid,
                keyframes: keyframes, preferred: []
            ) {
                assignments[id] = best
            }
        }
        return assignments
    }

    /// Chunk uchun eng yaxshi `top` ta kadrni ball bo'yicha tartiblab qaytaradi.
    /// Birinchisi assignKeyframes natijasi bilan bir xil.
    static func rankedKeyframes(
        for geo: ChunkGeometry,
        keyframes: [KeyframeStore.Keyframe],
        top: Int
    ) -> [Int] {
        guard let (samples, centroid) = chunkSamples(geo) else { return [] }

        var scored: [(index: Int, score: Float)] = []
        for (index, kf) in keyframes.enumerated() {
            let toChunk = simd_normalize(centroid - kf.position)
            let facing = simd_dot(toChunk, kf.forward)
            guard facing > 0.2 else { continue }

            var insideCount = 0
            for s in samples where isInside(point: s, keyframe: kf) {
                insideCount += 1
            }
            let insideFraction = Float(insideCount) / Float(samples.count)
            guard insideFraction > 0.3 else { continue }

            let distance = simd_distance(centroid, kf.position)
            let score = insideFraction * facing / (1.0 + distance * 0.15)
            if score > 0.15 {
                scored.append((index, score))
            }
        }
        return scored.sorted { $0.score > $1.score }.prefix(top).map { $0.index }
    }

    private static func chunkSamples(
        _ geo: ChunkGeometry
    ) -> (samples: [SIMD3<Float>], centroid: SIMD3<Float>)? {
        guard !geo.positions.isEmpty else { return nil }

        // Tezlik uchun vertexlarning bir qismini tekshiramiz
        let sampleTarget = 120
        let step = max(1, geo.positions.count / sampleTarget)
        var samples: [SIMD3<Float>] = []
        var i = 0
        while i < geo.positions.count {
            samples.append(geo.positions[i])
            i += step
        }

        var centroid = SIMD3<Float>.zero
        for s in samples { centroid += s }
        centroid /= Float(samples.count)
        return (samples, centroid)
    }

    /// Chunk vertexlari eng ko'p va eng to'g'ri ko'ringan keyframe'ni tanlaydi.
    /// `preferred` to'plamdagi kadrlar bonus oladi (fazoviy izchillik).
    private static func bestKeyframe(
        samples: [SIMD3<Float>],
        centroid: SIMD3<Float>,
        keyframes: [KeyframeStore.Keyframe],
        preferred: Set<Int>
    ) -> Int? {
        guard !keyframes.isEmpty, !samples.isEmpty else { return nil }

        var bestIndex: Int?
        var bestScore: Float = 0.15  // minimal sifat chegarasi

        for (index, kf) in keyframes.enumerated() {
            let toChunk = simd_normalize(centroid - kf.position)
            let facing = simd_dot(toChunk, kf.forward)
            guard facing > 0.2 else { continue }

            var insideCount = 0
            for s in samples where isInside(point: s, keyframe: kf) {
                insideCount += 1
            }
            let insideFraction = Float(insideCount) / Float(samples.count)
            guard insideFraction > 0.3 else { continue }

            let distance = simd_distance(centroid, kf.position)
            var score = insideFraction * facing / (1.0 + distance * 0.15)
            if preferred.contains(index) {
                score *= 1.35
            }
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }

    // MARK: - Proyeksiya

    private static func cameraSpace(
        point: SIMD3<Float>, keyframe: KeyframeStore.Keyframe
    ) -> SIMD3<Float> {
        let world = SIMD4<Float>(point.x, point.y, point.z, 1)
        let p = keyframe.transform.inverse * world
        return SIMD3<Float>(p.x, p.y, p.z)
    }

    private static func isInside(
        point: SIMD3<Float>, keyframe: KeyframeStore.Keyframe
    ) -> Bool {
        let p = cameraSpace(point: point, keyframe: keyframe)
        let depth = -p.z
        guard depth > 0.05 else { return false }
        let k = keyframe.intrinsics
        let fx: Float = k[0][0]
        let fy: Float = k[1][1]
        let cx: Float = k[2][0]
        let cy: Float = k[2][1]
        let u: Float = fx * p.x / depth + cx
        let v: Float = cy - fy * p.y / depth
        guard u >= 0, u <= Float(keyframe.width),
              v >= 0, v <= Float(keyframe.height) else { return false }
        // To'silgan nuqta bu kadrda "ko'rinmaydi" deb hisoblanadi
        return !keyframe.isOccluded(u: u, v: v, expectedDepth: depth)
    }

    /// OBJ vt: gorizontal 0..1, vertikal pastdan yuqoriga (rasm esa yuqoridan past).
    static func projectUV(
        point: SIMD3<Float>, keyframe: KeyframeStore.Keyframe
    ) -> SIMD2<Float> {
        let p = cameraSpace(point: point, keyframe: keyframe)
        let depth = max(0.05, -p.z)
        let k = keyframe.intrinsics
        let fx: Float = k[0][0]
        let fy: Float = k[1][1]
        let cx: Float = k[2][0]
        let cy: Float = k[2][1]
        let u: Float = fx * p.x / depth + cx
        let v: Float = cy - fy * p.y / depth
        let s: Float = simd_clamp(u / Float(keyframe.width), 0, 1)
        let t: Float = simd_clamp(1 - v / Float(keyframe.height), 0, 1)
        return SIMD2<Float>(s, t)
    }
}
