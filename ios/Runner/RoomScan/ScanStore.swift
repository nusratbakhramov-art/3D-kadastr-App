import Foundation

/// Owns the on-disk `Documents/Scans/` directory: enumerates saved scans,
/// allocates the next `scanNNN` id, and reads/writes manifests and frame indexes.
final class ScanStore {
    static let shared = ScanStore()

    let root: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Enumeration

    func listScanIDs() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return items.filter { $0.hasPrefix("scan") }.sorted()
    }

    func nextScanID() -> String {
        let numbers = listScanIDs().compactMap { Int($0.dropFirst(4)) }
        return String(format: "scan%03d", (numbers.max() ?? 0) + 1)
    }

    func folder(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    /// Create a scan folder with its `frames/`, `depth/`, `result/` subdirs.
    @discardableResult
    func createFolder(for id: String) throws -> URL {
        let f = folder(for: id)
        for sub in ["frames", "depth", "result"] {
            try FileManager.default.createDirectory(
                at: f.appendingPathComponent(sub, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return f
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    // MARK: - Manifest

    func loadManifest(_ id: String) -> ScanManifest? {
        let url = folder(for: id).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.scan.decode(ScanManifest.self, from: data)
    }

    func saveManifest(_ manifest: ScanManifest) throws {
        let url = folder(for: manifest.id).appendingPathComponent("manifest.json")
        try JSONEncoder.scan.encode(manifest).write(to: url)
    }

    // MARK: - Frame index

    func loadFrames(_ id: String) -> FramesIndex? {
        guard let manifest = loadManifest(id), let rel = manifest.framesJSON else { return nil }
        let url = folder(for: id).appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.scan.decode(FramesIndex.self, from: data)
    }

    func saveFrames(_ index: FramesIndex, id: String) throws {
        let url = folder(for: id).appendingPathComponent("frames/frames.json")
        try JSONEncoder.scan.encode(index).write(to: url)
    }
}
