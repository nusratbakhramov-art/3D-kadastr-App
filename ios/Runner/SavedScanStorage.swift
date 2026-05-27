// SavedScanStorage — raw scan data'larni telefonga saqlaydi.
//
// Format:
//   Documents/saved_scans/
//       index.json              ← [{id, name, photoCount, areaSqm, outputs[]}]
//       scan_001/
//           photos/             ← photo_*.jpg, depth_*.bin
//           poses.json          ← har photo uchun pose+intrinsics+sharpness
//           anchors.bin         ← ARKit anchor mesh dump
//           outputs/
//               manifest.json   ← [{version, file, params, createdAt}]
//               v1_*.usdz
//               v2_*.usdz
//
// Maqsad: bir marta scan qilib, ko'p marta atlas pipeline'ni qayta ishlash —
// har test uchun 2-3 daqiqalik scan'ni o'tkazib yuboradi.
//
// Anchor serialization: AnchorRaw fileprivate, shuning uchun binary format:
//   [Int32 anchorCount]
//   foreach anchor:
//     [16 floats transform]  (column-major)
//     [3 floats center]
//     [Int32 vertCount] [vertCount × 6 floats (local vert xyz + normal xyz)]
//     [Int32 worldCount] [worldCount × 6 floats (world vert + world normal)]
//     [Int32 idxCount] [idxCount × UInt32 indices]

import Foundation
import simd

// MARK: - Codable models (JSON)

struct SavedScanOutput: Codable {
    let version: Int
    let fileName: String
    let createdAt: TimeInterval
    let sizeBytes: Int
    let params: [String: String]   // taubin_iter, power, esrgan, etc.
}

struct SavedScanEntry: Codable {
    let id: Int
    var name: String
    let createdAt: TimeInterval
    let photoCount: Int
    let areaSqm: Double
    var outputs: [SavedScanOutput]
}

struct SavedScanIndexFile: Codable {
    var nextId: Int
    var entries: [SavedScanEntry]
}

// MARK: - Anchor codable (for binary serialization)

struct SerializedAnchor {
    let transform: simd_float4x4
    let center: SIMD3<Float>
    let vertices: [SIMD3<Float>]        // local-space
    let normals: [SIMD3<Float>]         // local-space
    let worldVertices: [SIMD3<Float>]   // world-space
    let worldNormals: [SIMD3<Float>]    // world-space
    let indices: [UInt32]
}

// MARK: - Storage

enum SavedScanStorage {

    // MARK: Folders

    static var rootFolder: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask,
        ).first!
        let folder = docs.appendingPathComponent("saved_scans", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
        )
        return folder
    }

    static func scanFolder(id: Int) -> URL {
        let url = rootFolder.appendingPathComponent("scan_\(String(format: "%03d", id))", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func photoFolder(id: Int) -> URL {
        let url = scanFolder(id: id).appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func outputsFolder(id: Int) -> URL {
        let url = scanFolder(id: id).appendingPathComponent("outputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func anchorsURL(id: Int) -> URL {
        return scanFolder(id: id).appendingPathComponent("anchors.bin")
    }

    static func posesURL(id: Int) -> URL {
        return photoFolder(id: id).appendingPathComponent("poses.json")
    }

    static func outputManifestURL(id: Int) -> URL {
        return outputsFolder(id: id).appendingPathComponent("manifest.json")
    }

    private static var indexURL: URL {
        return rootFolder.appendingPathComponent("index.json")
    }

    // MARK: Index I/O

    static func loadIndex() -> SavedScanIndexFile {
        guard let data = try? Data(contentsOf: indexURL) else {
            return SavedScanIndexFile(nextId: 1, entries: [])
        }
        return (try? JSONDecoder().decode(SavedScanIndexFile.self, from: data))
            ?? SavedScanIndexFile(nextId: 1, entries: [])
    }

    private static func saveIndex(_ idx: SavedScanIndexFile) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(idx) {
            try? data.write(to: indexURL)
        }
    }

    // MARK: Public API

    /// Yangi scan saqlash. Photos + poses + anchors ko'chiriladi.
    /// - Parameter sourcePhotoFolder: capture vaqtidagi tmp folder (poses.json bilan)
    /// - Parameter anchorsData: serialize qilingan ARKit anchor mesh ma'lumotlari
    /// - Parameter photoCount, areaSqm: metadata
    /// - Returns: yangi scan ID
    static func saveScan(
        sourcePhotoFolder: URL,
        anchorsData: Data,
        photoCount: Int,
        areaSqm: Double,
    ) -> Int {
        var idx = loadIndex()
        let id = idx.nextId
        idx.nextId = id + 1

        // 1. Create scan folder + copy photos
        let destPhotoFolder = photoFolder(id: id)
        copyFolderContents(from: sourcePhotoFolder, to: destPhotoFolder)

        // 2. Save anchors
        let anchorsURL = anchorsURL(id: id)
        try? anchorsData.write(to: anchorsURL)

        // 3. Index entry
        let entry = SavedScanEntry(
            id: id,
            name: String(format: "Skan %03d", id),
            createdAt: Date().timeIntervalSince1970,
            photoCount: photoCount,
            areaSqm: areaSqm,
            outputs: [],
        )
        idx.entries.append(entry)
        saveIndex(idx)

        // 4. Empty outputs manifest
        let manifest = ScanOutputManifest(outputs: [])
        saveOutputManifest(manifest, scanId: id)

        NSLog("KADASTR SavedScan saved id=\(id), photos=\(photoCount), anchors=\(anchorsData.count)B")
        return id
    }

    /// Skanlar ro'yxati (eng yangi birinchi).
    static func list() -> [SavedScanEntry] {
        return loadIndex().entries.sorted { $0.createdAt > $1.createdAt }
    }

    /// Belgilangan ID bo'yicha scan.
    static func get(id: Int) -> SavedScanEntry? {
        return loadIndex().entries.first(where: { $0.id == id })
    }

    /// Scan'ni o'chiradi (raw data + outputs).
    static func delete(id: Int) -> Bool {
        var idx = loadIndex()
        guard idx.entries.contains(where: { $0.id == id }) else { return false }
        let folder = scanFolder(id: id)
        try? FileManager.default.removeItem(at: folder)
        idx.entries.removeAll { $0.id == id }
        saveIndex(idx)
        NSLog("KADASTR SavedScan deleted id=\(id)")
        return true
    }

    /// Scan nomini o'zgartirish.
    static func rename(id: Int, newName: String) -> Bool {
        var idx = loadIndex()
        guard let i = idx.entries.firstIndex(where: { $0.id == id }) else { return false }
        idx.entries[i].name = newName
        saveIndex(idx)
        return true
    }

    /// Anchors binary dump — re-process uchun yuklash.
    static func loadAnchorsData(id: Int) -> Data? {
        return try? Data(contentsOf: anchorsURL(id: id))
    }

    // MARK: Outputs

    /// Yangi USDZ output qo'shish (texturing yakunlangach).
    /// Returns: assigned version number (1-based).
    static func addOutput(scanId: Int, sourceUsdzURL: URL, params: [String: String]) -> Int? {
        var idx = loadIndex()
        guard let entryIdx = idx.entries.firstIndex(where: { $0.id == scanId }) else { return nil }
        let entry = idx.entries[entryIdx]
        let nextVersion = (entry.outputs.map { $0.version }.max() ?? 0) + 1

        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "v\(nextVersion)_\(timestamp).usdz"
        let destURL = outputsFolder(id: scanId).appendingPathComponent(fileName)
        // Move (not copy) — sourceUsdzURL odatda tmp'da
        try? FileManager.default.removeItem(at: destURL)  // Just in case
        do {
            try FileManager.default.moveItem(at: sourceUsdzURL, to: destURL)
        } catch {
            // Fallback: copy
            try? FileManager.default.copyItem(at: sourceUsdzURL, to: destURL)
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let output = SavedScanOutput(
            version: nextVersion,
            fileName: fileName,
            createdAt: Date().timeIntervalSince1970,
            sizeBytes: size,
            params: params,
        )
        idx.entries[entryIdx].outputs.append(output)
        saveIndex(idx)
        NSLog("KADASTR SavedScan output added scan=\(scanId), v=\(nextVersion), file=\(fileName), size=\(size)")
        return nextVersion
    }

    /// Belgilangan output USDZ to'liq URL.
    static func outputURL(scanId: Int, version: Int) -> URL? {
        guard let entry = get(id: scanId) else { return nil }
        guard let output = entry.outputs.first(where: { $0.version == version }) else { return nil }
        return outputsFolder(id: scanId).appendingPathComponent(output.fileName)
    }

    /// Output o'chirish.
    static func deleteOutput(scanId: Int, version: Int) -> Bool {
        var idx = loadIndex()
        guard let entryIdx = idx.entries.firstIndex(where: { $0.id == scanId }) else { return false }
        guard let outIdx = idx.entries[entryIdx].outputs.firstIndex(where: { $0.version == version }) else { return false }
        let output = idx.entries[entryIdx].outputs[outIdx]
        let url = outputsFolder(id: scanId).appendingPathComponent(output.fileName)
        try? FileManager.default.removeItem(at: url)
        idx.entries[entryIdx].outputs.remove(at: outIdx)
        saveIndex(idx)
        return true
    }

    // MARK: Helpers

    struct ScanOutputManifest: Codable {
        var outputs: [SavedScanOutput]
    }

    private static func saveOutputManifest(_ manifest: ScanOutputManifest, scanId: Int) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(manifest) {
            try? data.write(to: outputManifestURL(id: scanId))
        }
    }

    private static func copyFolderContents(from src: URL, to dst: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else {
            return
        }
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for item in items {
            let dstItem = dst.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: dstItem)
            try? fm.copyItem(at: item, to: dstItem)
        }
    }
}

// MARK: - Anchor binary serialization

/// AnchorRaw'ni binary buffer'ga aylantiradi (fileprivate scope tashqarisida ham
/// ishlatish mumkin bo'lishi uchun SerializedAnchor orqali).
enum AnchorSerializer {
    /// SerializedAnchor[] → Data (binary format yuqorida)
    static func serialize(_ anchors: [SerializedAnchor]) -> Data {
        var buf = Data()
        appendInt32(&buf, Int32(anchors.count))
        for a in anchors {
            // transform (16 floats column-major)
            let cols = [a.transform.columns.0, a.transform.columns.1,
                        a.transform.columns.2, a.transform.columns.3]
            for c in cols {
                appendFloat(&buf, c.x); appendFloat(&buf, c.y)
                appendFloat(&buf, c.z); appendFloat(&buf, c.w)
            }
            // center
            appendFloat(&buf, a.center.x)
            appendFloat(&buf, a.center.y)
            appendFloat(&buf, a.center.z)

            // local vertices + normals interleaved
            appendInt32(&buf, Int32(a.vertices.count))
            for i in 0..<a.vertices.count {
                let v = a.vertices[i]; let n = a.normals[i]
                appendFloat(&buf, v.x); appendFloat(&buf, v.y); appendFloat(&buf, v.z)
                appendFloat(&buf, n.x); appendFloat(&buf, n.y); appendFloat(&buf, n.z)
            }
            // world vertices + normals
            appendInt32(&buf, Int32(a.worldVertices.count))
            for i in 0..<a.worldVertices.count {
                let v = a.worldVertices[i]; let n = a.worldNormals[i]
                appendFloat(&buf, v.x); appendFloat(&buf, v.y); appendFloat(&buf, v.z)
                appendFloat(&buf, n.x); appendFloat(&buf, n.y); appendFloat(&buf, n.z)
            }
            // indices
            appendInt32(&buf, Int32(a.indices.count))
            for idx in a.indices {
                appendUInt32(&buf, idx)
            }
        }
        return buf
    }

    static func deserialize(_ data: Data) -> [SerializedAnchor] {
        var offset = 0
        var anchors: [SerializedAnchor] = []
        guard let anchorCount = readInt32(data, &offset) else { return [] }
        anchors.reserveCapacity(Int(anchorCount))
        for _ in 0..<anchorCount {
            // transform
            var cols: [SIMD4<Float>] = []
            for _ in 0..<4 {
                guard let x = readFloat(data, &offset),
                      let y = readFloat(data, &offset),
                      let z = readFloat(data, &offset),
                      let w = readFloat(data, &offset)
                else { return anchors }
                cols.append(SIMD4<Float>(x, y, z, w))
            }
            let transform = simd_float4x4(cols[0], cols[1], cols[2], cols[3])

            // center
            guard let cx = readFloat(data, &offset),
                  let cy = readFloat(data, &offset),
                  let cz = readFloat(data, &offset)
            else { return anchors }
            let center = SIMD3<Float>(cx, cy, cz)

            // local verts+normals
            guard let lvCount = readInt32(data, &offset) else { return anchors }
            var verts: [SIMD3<Float>] = []; verts.reserveCapacity(Int(lvCount))
            var normals: [SIMD3<Float>] = []; normals.reserveCapacity(Int(lvCount))
            for _ in 0..<lvCount {
                guard let x = readFloat(data, &offset), let y = readFloat(data, &offset),
                      let z = readFloat(data, &offset), let nx = readFloat(data, &offset),
                      let ny = readFloat(data, &offset), let nz = readFloat(data, &offset)
                else { return anchors }
                verts.append(SIMD3<Float>(x, y, z))
                normals.append(SIMD3<Float>(nx, ny, nz))
            }

            // world verts+normals
            guard let wvCount = readInt32(data, &offset) else { return anchors }
            var wVerts: [SIMD3<Float>] = []; wVerts.reserveCapacity(Int(wvCount))
            var wNormals: [SIMD3<Float>] = []; wNormals.reserveCapacity(Int(wvCount))
            for _ in 0..<wvCount {
                guard let x = readFloat(data, &offset), let y = readFloat(data, &offset),
                      let z = readFloat(data, &offset), let nx = readFloat(data, &offset),
                      let ny = readFloat(data, &offset), let nz = readFloat(data, &offset)
                else { return anchors }
                wVerts.append(SIMD3<Float>(x, y, z))
                wNormals.append(SIMD3<Float>(nx, ny, nz))
            }

            // indices
            guard let iCount = readInt32(data, &offset) else { return anchors }
            var indices: [UInt32] = []; indices.reserveCapacity(Int(iCount))
            for _ in 0..<iCount {
                guard let v = readUInt32(data, &offset) else { return anchors }
                indices.append(v)
            }

            anchors.append(SerializedAnchor(
                transform: transform, center: center,
                vertices: verts, normals: normals,
                worldVertices: wVerts, worldNormals: wNormals,
                indices: indices,
            ))
        }
        return anchors
    }

    // Binary helpers
    private static func appendInt32(_ buf: inout Data, _ v: Int32) {
        var x = v.littleEndian
        withUnsafeBytes(of: &x) { buf.append(contentsOf: $0) }
    }
    private static func appendUInt32(_ buf: inout Data, _ v: UInt32) {
        var x = v.littleEndian
        withUnsafeBytes(of: &x) { buf.append(contentsOf: $0) }
    }
    private static func appendFloat(_ buf: inout Data, _ v: Float) {
        var x = v
        withUnsafeBytes(of: &x) { buf.append(contentsOf: $0) }
    }
    private static func readInt32(_ data: Data, _ offset: inout Int) -> Int32? {
        if offset + 4 > data.count { return nil }
        let v = data.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: Int32.self)
        }
        offset += 4
        return Int32(littleEndian: v)
    }
    private static func readUInt32(_ data: Data, _ offset: inout Int) -> UInt32? {
        if offset + 4 > data.count { return nil }
        let v = data.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: v)
    }
    private static func readFloat(_ data: Data, _ offset: inout Int) -> Float? {
        if offset + 4 > data.count { return nil }
        let v = data.withUnsafeBytes {
            $0.load(fromByteOffset: offset, as: Float.self)
        }
        offset += 4
        return v
    }
}
