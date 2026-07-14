import Foundation

/// Bitta skanerlash sessiyasining fayl tizimidagi yo'llari.
struct ScanPaths {
    /// Sessiya ildiz papkasi (Documents/Scans/<id>).
    let root: URL

    /// Object Capture uchun RGB kadrlar papkasi.
    var imagesFolder: URL { root.appendingPathComponent("images", isDirectory: true) }
    /// LiDAR depth + confidence kadrlari (fusion uchun, Polycam formatiga o'xshash).
    var depthFolder: URL { root.appendingPathComponent("depth", isDirectory: true) }
    /// Zich depth-kesh (har tick, harakat shartisiz — Scaniverse uslubi).
    var denseFolder: URL { root.appendingPathComponent("dense", isDirectory: true) }
    /// Zich kesh kamera pozalari.
    var densePosesJSON: URL { root.appendingPathComponent("dense_poses.json") }
    /// Object Capture chiqishi (teksturali USDZ).
    var modelURL: URL { root.appendingPathComponent("model.usdz") }
    /// LiDAR scene-reconstruction mesh'i (world koordinatada, binary).
    var lidarMeshURL: URL { root.appendingPathComponent("mesh.bin") }
    /// ARKit'ning real-time meshi (ARMeshAnchor snapshot) — Polycam uslubidagi geometriya.
    var arkitMeshURL: URL { root.appendingPathComponent("arkit_mesh.bin") }
    /// Mesh cho'qqilari uchun ranglar (2-bosqich: tekstura proyeksiyasi).
    var meshColorsURL: URL { root.appendingPathComponent("colors.bin") }
    /// Keyframe kamera pozitsiyalari.
    var framesJSON: URL { root.appendingPathComponent("frames.json") }
    /// Projektiv teksturalar papkasi (devor/pol PNG'lari + surfaces.json).
    var texturesDir: URL { root.appendingPathComponent("textures", isDirectory: true) }
    var surfacesJSON: URL { texturesDir.appendingPathComponent("surfaces.json") }
    /// RoomPlan modeli (CapturedRoom) JSON ko'rinishida — qayta ochish/qayta ishlash uchun.
    var roomJSON: URL { root.appendingPathComponent("room.json") }
    /// Skan metadatasi (indeks, sana, o'lchamlar...).
    var metadataJSON: URL { root.appendingPathComponent("metadata.json") }
    /// Debug jurnali.
    var debugLog: URL { root.appendingPathComponent("debug.log") }

    var folderName: String { root.lastPathComponent }
}

/// On-device saqlash (backend yo'q). Barcha ma'lumot Documents/Scans ostida.
enum StorageService {

    static var scansRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Scans", isDirectory: true)
    }

    /// Yangi sessiya uchun papka tuzilmasini yaratadi.
    static func newSession() throws -> ScanPaths {
        let stamp = timestamp()
        let root = scansRoot.appendingPathComponent(stamp, isDirectory: true)
        let paths = ScanPaths(root: root)
        try FileManager.default.createDirectory(at: paths.imagesFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.depthFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.denseFolder, withIntermediateDirectories: true)
        return paths
    }

    /// Mavjud papkadan yo'llarni tiklaydi (saqlangan skanni ochish uchun).
    static func session(named folderName: String) -> ScanPaths {
        ScanPaths(root: scansRoot.appendingPathComponent(folderName, isDirectory: true))
    }

    /// Barcha sessiya papkalarini qaytaradi.
    static func sessionRoots() -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: scansRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Bitta sessiyani o'chiradi.
    static func delete(folderName: String) {
        let root = scansRoot.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
    }

    /// Barcha saqlangan sessiyalarni o'chiradi.
    static func deleteAll() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: scansRoot.path) {
            try fm.removeItem(at: scansRoot)
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
