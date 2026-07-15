import Foundation
import Combine
import NSDK
import simd

/// Device-mapping va VPS oqimlarini UI uchun tayyor holatga aylantiradi.
///
/// Obunalar:
/// - `mappingSession.$latestMapUpdate` — inkremental xarita bufferlari
/// - `vps2Session.anchorUpdated` — har freymdagi anchor pozasi va tracking holati
///
/// Publish qilinadi:
/// - `rootAnchorPayload` — xarita origin'ining base64 anchor payload'i
/// - `anchorTransform` — anchor→ARKit transform (kontent shu yerga bog'lanadi)
/// - `points` — anchor-lokal fazodagi yig'ilgan feature nuqtalar
/// - `anchorStateText` — anchor tracking holati (UI status uchun)
final class RoomScanViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var anchorTransform: simd_float4x4?
    @Published private(set) var points: [SIMD3<Float>] = []
    @Published private(set) var rootAnchorPayload: String?
    @Published private(set) var anchorStateText: String = "—"

    // MARK: - Private

    private let mapStorage: NSDKMapStorage
    private var pendingMaps: [NSDKBuffer] = []
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        mappingSession: NSDKDeviceMappingSession,
        mapStorage: NSDKMapStorage,
        vps2Session: NSDKVps2Session
    ) {
        self.mapStorage = mapStorage

        // Agar storage'da xarita bo'lsa (diskdan yuklangan) — undan bootstrap qilamiz.
        if let mapBuffer = mapStorage.mapData(), let anchor = mapStorage.createRootAnchor() {
            rootAnchorPayload = anchor
            pendingMaps = [mapBuffer]
        }

        mappingSession.$latestMapUpdate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer in
                self?.handleMapUpdate(buffer)
            }
            .store(in: &cancellables)

        vps2Session.anchorUpdated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, update in
                self?.handleAnchorUpdate(update)
            }
            .store(in: &cancellables)
    }

    // MARK: - Mapping Lifecycle

    /// Yangi skan boshlashdan oldin eski holatni tozalaydi.
    func resetForNewMapping() {
        rootAnchorPayload = nil
        pendingMaps.removeAll()
        points.removeAll()
        anchorTransform = nil
        anchorStateText = "—"
    }

    // MARK: - Private Handlers

    private func handleMapUpdate(_ buffer: NSDKBuffer) {
        if rootAnchorPayload == nil, let anchor = mapStorage.createRootAnchor() {
            rootAnchorPayload = anchor
        }
        guard rootAnchorPayload != nil else { return }
        pendingMaps.append(buffer)
    }

    private func handleAnchorUpdate(_ update: VpsAnchorUpdate) {
        anchorStateText = String(describing: update.trackingState)

        guard let trackingData = update.trackingData,
              let anchorPayload = rootAnchorPayload else { return }

        anchorTransform = trackingData.targetAnchorTransform

        guard !pendingMaps.isEmpty else { return }

        var newPoints: [SIMD3<Float>] = []
        for mapBuffer in pendingMaps {
            do {
                guard let metadata = try mapStorage.extractMapMetadata(
                    anchorPayload: anchorPayload, map: mapBuffer
                ) else { continue }
                let flat = metadata.points
                newPoints.reserveCapacity(newPoints.count + Int(metadata.pointsCount))
                stride(from: 0, to: flat.count - 2, by: 3).forEach { i in
                    newPoints.append(SIMD3<Float>(flat[i], flat[i + 1], flat[i + 2]))
                }
            } catch {
                print("[RoomScanViewModel] Metadata extraction failed: \(error)")
            }
        }

        if !newPoints.isEmpty {
            points.append(contentsOf: newPoints)
        }
        pendingMaps.removeAll()
    }
}
