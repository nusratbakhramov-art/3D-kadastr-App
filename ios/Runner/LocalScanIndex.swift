// LocalScanIndex — Documents/scans/ folder ichidagi USDZ skanlarni boshqaradi.
//
// Format:
//   Documents/scans/
//       scan_001.usdz
//       scan_002.usdz
//       ...
//       index.json    ← metadata: [{id, name, file, date, sizeBytes, areaSqm}]
//
// Auth talab qilmaydi — to'liq local storage.

import Foundation

struct LocalScanEntry: Codable {
    let id: Int                   // sequential, 1-based
    var name: String              // "Scan 001" yoki user-edited
    let fileName: String          // "scan_001.usdz"
    let createdAt: TimeInterval   // Unix time
    var sizeBytes: Int
    var areaSqm: Double           // floor area (RoomPlan/ARKit hisoblagani)
    var photoCount: Int
}

struct ScanIndexFile: Codable {
    var nextId: Int               // birorta yangi scan uchun keyingi id
    var entries: [LocalScanEntry]
}

enum LocalScanIndex {
    private static var scansFolder: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask,
        ).first!
        let folder = docs.appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
        )
        return folder
    }

    private static var indexURL: URL {
        return scansFolder.appendingPathComponent("index.json")
    }

    static func loadIndex() -> ScanIndexFile {
        guard let data = try? Data(contentsOf: indexURL) else {
            return ScanIndexFile(nextId: 1, entries: [])
        }
        return (try? JSONDecoder().decode(ScanIndexFile.self, from: data))
            ?? ScanIndexFile(nextId: 1, entries: [])
    }

    private static func saveIndex(_ idx: ScanIndexFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(idx) {
            try? data.write(to: indexURL)
        }
    }

    /// Yangi scan uchun USDZ fayl URL'ni tayyorlaydi (lekin saqlamaydi).
    /// Pipeline shu URL'ga USDZ yozadi, keyin `registerScan(...)` chaqiriladi.
    static func reserveNewScanURL() -> (url: URL, id: Int, fileName: String) {
        var idx = loadIndex()
        let id = idx.nextId
        idx.nextId = id + 1
        saveIndex(idx)
        let fileName = String(format: "scan_%03d.usdz", id)
        let url = scansFolder.appendingPathComponent(fileName)
        return (url, id, fileName)
    }

    /// Saqlangan scan'ni index'ga ro'yxatdan o'tkazadi.
    static func registerScan(
        id: Int, fileName: String, areaSqm: Double, photoCount: Int,
    ) {
        var idx = loadIndex()
        let url = scansFolder.appendingPathComponent(fileName)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let name = String(format: "Skan %03d", id)
        let entry = LocalScanEntry(
            id: id, name: name, fileName: fileName,
            createdAt: Date().timeIntervalSince1970,
            sizeBytes: size, areaSqm: areaSqm, photoCount: photoCount,
        )
        // Dedupe — agar shu id allaqachon mavjud, almashtir
        idx.entries.removeAll { $0.id == id }
        idx.entries.append(entry)
        saveIndex(idx)
    }

    /// Hamma local skanlar ro'yxati (newest first).
    static func listScans() -> [LocalScanEntry] {
        return loadIndex().entries.sorted { $0.createdAt > $1.createdAt }
    }

    /// Belgilangan id bo'yicha scan faylining to'liq yo'li (yo'q bo'lsa nil).
    static func scanURL(forId id: Int) -> URL? {
        let entries = loadIndex().entries
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        let url = scansFolder.appendingPathComponent(entry.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Scan'ni o'chiradi (fayl + index).
    static func deleteScan(id: Int) -> Bool {
        var idx = loadIndex()
        guard let entry = idx.entries.first(where: { $0.id == id }) else { return false }
        let url = scansFolder.appendingPathComponent(entry.fileName)
        try? FileManager.default.removeItem(at: url)
        idx.entries.removeAll { $0.id == id }
        saveIndex(idx)
        return true
    }

    /// Scan nomini o'zgartiradi.
    static func renameScan(id: Int, newName: String) -> Bool {
        var idx = loadIndex()
        guard let i = idx.entries.firstIndex(where: { $0.id == id }) else { return false }
        idx.entries[i].name = newName
        saveIndex(idx)
        return true
    }
}
