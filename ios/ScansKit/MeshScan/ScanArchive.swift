import Foundation
import simd

/// Skanlarni qurilmada doimiy saqlaydi (Documents/Scans/<id>/) — xom ma'lumot
/// (keyframe rasm + poza + intrinsics + depth) + ixtiyoriy natija (texout).
/// Shu bilan: oldingi natijalarni ko'rish + bug tuzatgandan keyin QAYTA ISHLASH.
enum ScanArchive {

    static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    struct Entry {
        let id: String
        let name: String
        let date: Date
        let folder: URL
        let keyframeCount: Int
        var hasResult: Bool { FileManager.default.fileExists(atPath: folder.appendingPathComponent("result/texout.obj").path) }
    }

    // MARK: - Saqlash

    /// Xom skan ma'lumotini saqlaydi (keyframes + NSDK mesh.ply). Qaytadi: scan folder.
    @discardableResult
    static func saveRaw(keyframes: [KeyframeStore.Keyframe],
                        geometries: [Int64: ChunkGeometry]) -> URL {
        let fm = FileManager.default
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let id = "Xona-\(f.string(from: Date()))"
        let folder = root.appendingPathComponent(id, isDirectory: true)
        let kfDir = folder.appendingPathComponent("keyframes", isDirectory: true)
        try? fm.createDirectory(at: kfDir, withIntermediateDirectories: true)

        // NSDK mesh.ply (geometriya manbai — qayta ishlash uchun)
        OnDeviceTexturing.writeWeldedPLY(geometries, to: folder.appendingPathComponent("mesh.ply"))

        var frames: [[String: Any]] = []
        for (i, kf) in keyframes.enumerated() {
            let name = String(format: "kf_%04d", i)
            try? kf.jpegData.write(to: kfDir.appendingPathComponent("\(name).jpg"))
            var depthRef = ""
            if let depth = kf.depthMap, kf.depthWidth > 0 {
                var d = depth
                let data = d.withUnsafeBytes { Data($0) }
                try? data.write(to: kfDir.appendingPathComponent("\(name).depth"))
                depthRef = "keyframes/\(name).depth"
            }
            let t = kf.transform
            let tm: [Float] = [
                t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
                t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
                t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
                t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w,
            ]
            let k = kf.intrinsics
            frames.append([
                "file": "keyframes/\(name).jpg",
                "w": kf.width, "h": kf.height,
                "fx": k[0][0], "fy": k[1][1], "cx": k[2][0], "cy": k[2][1],
                "transform": tm, "sharpness": kf.sharpness,
                "depth": depthRef, "dw": kf.depthWidth, "dh": kf.depthHeight,
            ])
        }
        let manifest: [String: Any] = ["version": 1, "id": id, "frameCount": frames.count, "frames": frames]
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("frames.json"))
        }
        let meta: [String: Any] = ["id": id, "date": Date().timeIntervalSince1970, "keyframeCount": frames.count]
        if let data = try? JSONSerialization.data(withJSONObject: meta) {
            try? data.write(to: folder.appendingPathComponent("meta.json"))
        }
        return folder
    }

    /// Yuqori sifat natijasini (texout*) scan folder'ga ko'chiradi.
    static func saveResult(from resultFolder: URL, into scanFolder: URL) {
        let fm = FileManager.default
        let dst = scanFolder.appendingPathComponent("result", isDirectory: true)
        try? fm.removeItem(at: dst)
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        if let items = try? fm.contentsOfDirectory(at: resultFolder, includingPropertiesForKeys: nil) {
            for u in items where u.lastPathComponent.hasPrefix("texout") {
                try? fm.copyItem(at: u, to: dst.appendingPathComponent(u.lastPathComponent))
            }
        }
    }

    // MARK: - Ro'yxat / yuklash

    static func list() -> [Entry] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [Entry] = []
        for d in dirs where (try? d.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let metaURL = d.appendingPathComponent("meta.json")
            var date = Date(); var count = 0
            if let data = try? Data(contentsOf: metaURL),
               let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let ts = m["date"] as? Double { date = Date(timeIntervalSince1970: ts) }
                if let c = m["keyframeCount"] as? Int { count = c }
            }
            out.append(Entry(id: d.lastPathComponent, name: d.lastPathComponent, date: date, folder: d, keyframeCount: count))
        }
        return out.sorted { $0.date > $1.date }
    }

    static func delete(_ entry: Entry) { try? FileManager.default.removeItem(at: entry.folder) }

    /// Saqlangan keyframe'larni qayta yuklaydi (QAYTA ISHLASH uchun).
    static func loadKeyframes(from folder: URL) -> [KeyframeStore.Keyframe] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("frames.json")),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frames = m["frames"] as? [[String: Any]] else { return [] }
        var out: [KeyframeStore.Keyframe] = []
        for fr in frames {
            guard let file = fr["file"] as? String,
                  let jpeg = try? Data(contentsOf: folder.appendingPathComponent(file)) else { continue }
            let w = (fr["w"] as? Int) ?? 0, h = (fr["h"] as? Int) ?? 0
            let fx = f(fr["fx"]), fy = f(fr["fy"]), cx = f(fr["cx"]), cy = f(fr["cy"])
            let tm = (fr["transform"] as? [Any])?.map { Float(($0 as? Double) ?? 0) } ?? []
            guard tm.count == 16 else { continue }
            let transform = simd_float4x4(columns: (
                SIMD4<Float>(tm[0], tm[1], tm[2], tm[3]),
                SIMD4<Float>(tm[4], tm[5], tm[6], tm[7]),
                SIMD4<Float>(tm[8], tm[9], tm[10], tm[11]),
                SIMD4<Float>(tm[12], tm[13], tm[14], tm[15])))
            var K = matrix_identity_float3x3
            K[0][0] = fx; K[1][1] = fy; K[2][0] = cx; K[2][1] = cy
            let dw = (fr["dw"] as? Int) ?? 0, dh = (fr["dh"] as? Int) ?? 0
            var depth: [Float32]? = nil
            if let dref = fr["depth"] as? String, !dref.isEmpty,
               let dd = try? Data(contentsOf: folder.appendingPathComponent(dref)) {
                depth = dd.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }
            }
            let pos = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let fwd = SIMD3<Float>(-transform.columns.2.x, -transform.columns.2.y, -transform.columns.2.z)
            out.append(KeyframeStore.Keyframe(
                jpegData: jpeg, transform: transform, intrinsics: K,
                width: w, height: h, position: pos, forward: fwd,
                depthMap: depth, depthWidth: dw, depthHeight: dh,
                sharpness: f(fr["sharpness"])))
        }
        return out
    }

    static func resultOBJ(in folder: URL) -> URL? {
        let obj = folder.appendingPathComponent("result/texout.obj")
        return FileManager.default.fileExists(atPath: obj.path) ? obj : nil
    }

    static func meshPLY(in folder: URL) -> URL? {
        let m = folder.appendingPathComponent("mesh.ply")
        return FileManager.default.fileExists(atPath: m.path) ? m : nil
    }

    private static func f(_ v: Any?) -> Float { Float((v as? Double) ?? 0) }
}
