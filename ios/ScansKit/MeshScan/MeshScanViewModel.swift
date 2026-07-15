import Foundation
import RealityKit
import UIKit
import NSDK
import Combine

/// NSDKMeshingSession mesh yangilanishlarini RealityKit chunk'lariga aylantiradi
/// va OBJ eksport uchun geometriyani saqlab boradi.
final class MeshScanViewModel {

    /// Har bir meshUpdates emissiyasi uchun bitta lug'at: id → entity (nil = o'chirish).
    let updatedMeshChunks = PassthroughSubject<[Int64: ModelEntity?], Never>()

    private var geometries: [Int64: ChunkGeometry] = [:]
    private let geometriesLock = NSLock()
    private var cancellables = Set<AnyCancellable>()

    init(meshingSession: NSDKMeshingSession) {
        meshingSession.meshUpdates
            .sink { [weak self] updates in
                guard let self else { return }
                var chunkChanges: [Int64: ModelEntity?] = [:]
                for chunkUpdate in updates {
                    switch chunkUpdate {
                    case .insert(let id, let data), .update(let id, let data):
                        guard let geo = data.extractGeometry(),
                              let mesh = geo.toMeshResource() else { continue }
                        geometriesLock.lock()
                        geometries[id] = geo
                        geometriesLock.unlock()
                        let material = Self.chunkMaterial(for: id)
                        chunkChanges[id] = ModelEntity(mesh: mesh, materials: [material])
                    case .remove(let id):
                        geometriesLock.lock()
                        geometries.removeValue(forKey: id)
                        geometriesLock.unlock()
                        chunkChanges[id] = nil
                    }
                }
                updatedMeshChunks.send(chunkChanges)
            }
            .store(in: &cancellables)
    }

    // MARK: - Export

    var hasGeometry: Bool {
        geometriesLock.lock()
        defer { geometriesLock.unlock() }
        return !geometries.isEmpty
    }

    var totalVertexCount: Int {
        geometriesLock.lock()
        defer { geometriesLock.unlock() }
        return geometries.values.reduce(0) { $0 + $1.positions.count }
    }

    func snapshotGeometries() -> [Int64: ChunkGeometry] {
        geometriesLock.lock()
        defer { geometriesLock.unlock() }
        return geometries
    }

    func clear() {
        geometriesLock.lock()
        geometries.removeAll()
        geometriesLock.unlock()
    }

    // MARK: - Material

    /// Chunk id'dan deterministik rang — qamrov ko'rinishi uchun rangli plitkalar.
    private static func chunkMaterial(for id: Int64) -> UnlitMaterial {
        let hue = CGFloat((id % 12 + 12) % 12) / 12.0
        let color = UIColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1.0)
        return UnlitMaterial(color: color)
    }
}
