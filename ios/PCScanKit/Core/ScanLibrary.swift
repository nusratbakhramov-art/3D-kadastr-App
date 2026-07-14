import Foundation
import RoomPlan

/// Saqlangan skanlar kutubxonasi (on-device). Ro'yxatni yuklaydi, saqlaydi, o'chiradi.
@MainActor
final class ScanLibrary: ObservableObject {
    /// Indeks bo'yicha kamayish tartibida (eng yangisi birinchi).
    @Published private(set) var records: [ScanRecord] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    init() {
        reload()
    }

    func reload() {
        var loaded: [ScanRecord] = []
        for root in StorageService.sessionRoots() {
            let metaURL = ScanPaths(root: root).metadataJSON
            if let data = try? Data(contentsOf: metaURL),
               let record = try? decoder.decode(ScanRecord.self, from: data) {
                loaded.append(record)
            }
        }
        records = loaded.sorted { $0.index > $1.index }
    }

    private func nextIndex() -> Int {
        (records.map(\.index).max() ?? 0) + 1
    }

    /// Skan artefaktlarini metadata + room.json bilan diskka saqlaydi.
    @discardableResult
    func save(artifacts: ScanArtifacts) -> ScanRecord {
        let room = artifacts.capturedRoom
        let bounds = RoomGeometry.bounds(of: room)
        let frameCount = (try? FileManager.default.contentsOfDirectory(
            at: artifacts.imagesFolder, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "jpg" }.count) ?? 0
        let fm = FileManager.default
        let objURL = artifacts.paths.texturesDir.appendingPathComponent("room.obj")
        let hasMesh = fm.fileExists(atPath: artifacts.paths.arkitMeshURL.path)
            || fm.fileExists(atPath: artifacts.paths.lidarMeshURL.path)
        let hasTexture = fm.fileExists(atPath: objURL.path)
            || fm.fileExists(atPath: artifacts.paths.modelURL.path)

        let record = ScanRecord(
            id: UUID(),
            index: nextIndex(),
            folderName: artifacts.paths.folderName,
            createdAt: Date(),
            floorArea: RoomGeometry.floorArea(of: room),
            floorPerimeter: RoomGeometry.floorPerimeter(of: room),
            width: bounds.width,
            depth: bounds.depth,
            height: bounds.height,
            wallCount: room.walls.count,
            objectCount: room.objects.count,
            frameCount: frameCount,
            hasTexture: hasTexture,
            hasMesh: hasMesh
        )

        // RoomPlan modelini saqlaymiz (qayta ochish/qayta ishlash uchun).
        if let roomData = try? encoder.encode(room) {
            try? roomData.write(to: artifacts.paths.roomJSON)
        }
        if let metaData = try? encoder.encode(record) {
            try? metaData.write(to: artifacts.paths.metadataJSON)
        }

        DebugLog(url: artifacts.paths.debugLog).log(
            "SAVED index=\(record.index) area=\(record.floorArea)m² frames=\(frameCount) texture=\(hasTexture)"
        )

        reload()
        return record
    }

    /// Qayta ishlashdan so'ng mavjud yozuvni yangilaydi (indeks/sanани saqlab).
    func updateAfterReprocess(folderName: String, artifacts: ScanArtifacts) {
        let paths = StorageService.session(named: folderName)
        guard let data = try? Data(contentsOf: paths.metadataJSON),
              var record = try? decoder.decode(ScanRecord.self, from: data) else {
            save(artifacts: artifacts)
            return
        }
        let fm = FileManager.default
        let objURL = paths.texturesDir.appendingPathComponent("room.obj")
        record.hasTexture = fm.fileExists(atPath: objURL.path)
            || fm.fileExists(atPath: paths.modelURL.path)
        record.hasMesh = fm.fileExists(atPath: paths.arkitMeshURL.path)
            || fm.fileExists(atPath: paths.lidarMeshURL.path)
        if let metaData = try? encoder.encode(record) {
            try? metaData.write(to: paths.metadataJSON)
        }
        DebugLog(url: paths.debugLog).log("REPROCESSED texture=\(record.hasTexture)")
        reload()
    }

    /// Saqlangan skandan ScanArtifacts tiklaydi (viewer uchun).
    func loadArtifacts(_ record: ScanRecord) -> ScanArtifacts? {
        let paths = StorageService.session(named: record.folderName)
        guard let data = try? Data(contentsOf: paths.roomJSON),
              let room = try? decoder.decode(CapturedRoom.self, from: data) else {
            return nil
        }
        // Ustuvorlik: texrecon OBJ (sanoat teksturasi) → Object Capture USDZ.
        let objURL = paths.texturesDir.appendingPathComponent("room.obj")
        let texturedURL: URL?
        if FileManager.default.fileExists(atPath: objURL.path) {
            texturedURL = objURL
        } else if FileManager.default.fileExists(atPath: paths.modelURL.path) {
            texturedURL = paths.modelURL
        } else {
            texturedURL = nil
        }
        return ScanArtifacts(
            capturedRoom: room,
            imagesFolder: paths.imagesFolder,
            texturedModelURL: texturedURL,
            paths: paths
        )
    }

    func delete(_ record: ScanRecord) {
        StorageService.delete(folderName: record.folderName)
        reload()
    }
}
