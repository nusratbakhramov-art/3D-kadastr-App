import Foundation
import RoomPlan
import ARKit
import SceneKit
import UIKit

/// M1 — Skanerlash kontrolleri.
/// ARSCNView orqali kamerani ko'rsatadi + LiDAR mesh'ni jonli wireframe qilib chizadi
/// (qamrov ko'rsatkichi). RoomPlan xuddi shu ARSession ustida ishlaydi (o'lchov/obyekt).
/// Bir vaqtda Object Capture uchun RGB + depth kadrlar yig'iladi.
@MainActor
final class ScanController: NSObject, ObservableObject {

    let arView = ARSCNView(frame: .zero)
    private let roomSession: RoomCaptureSession

    @Published private(set) var isScanning = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var instructionText: String = ""
    @Published private(set) var wallCount = 0
    @Published private(set) var objectCount = 0
    @Published private(set) var capturedFrames = 0
    @Published private(set) var meshChunks = 0

    /// Skanerlash muvaffaqiyatli yakunlanganda chaqiriladi.
    var onFinished: ((CapturedRoom, ScanPaths) -> Void)?
    /// Xatolik yuz berganda chaqiriladi.
    var onError: ((Error) -> Void)?

    private var sampler: FrameSampler?
    private var paths: ScanPaths?
    private var debugLog: DebugLog?
    private var frameCountTimer: Timer?
    private var didFinish = false

    override init() {
        roomSession = RoomCaptureSession(arSession: arView.session)
        super.init()
        arView.delegate = self
        arView.automaticallyUpdatesLighting = true
        arView.scene = SCNScene()
        arView.rendersContinuously = true
        roomSession.delegate = self
    }

    // MARK: - Boshqaruv

    func start() {
        guard !isScanning else { return }
        do {
            let paths = try StorageService.newSession()
            self.paths = paths
            didFinish = false
            let debugLog = DebugLog(url: paths.debugLog)
            self.debugLog = debugLog
            debugLog.log("SCAN START folder=\(paths.folderName) objectCaptureSupported=\(DeviceCapability.supportsObjectCapture)")

            let sampler = FrameSampler(
                session: arView.session,
                outputFolder: paths.imagesFolder,
                depthFolder: paths.depthFolder,
                denseFolder: paths.denseFolder
            )
            self.sampler = sampler

            roomSession.run(configuration: RoomCaptureSession.Configuration())
            sampler.start()

            // RoomPlan sessiyani ishga tushirgach, unga LiDAR mesh + depth qo'shamiz
            // (mesh — wireframe qamrov ko'rsatkichi uchun; depth — fusion uchun).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.enableMeshAndDepth()
            }

            isScanning = true
            startFrameCounter()
        } catch {
            onError?(error)
        }
    }

    func stop() {
        guard isScanning else { return }
        isScanning = false
        isFinalizing = true
        sampler?.stop()
        frameCountTimer?.invalidate()
        debugLog?.log("SCAN STOP frames=\(sampler?.savedCount ?? 0) depthFrames=\(sampler?.depthSavedCount ?? 0) dense=\(sampler?.densePoses.count ?? 0) meshChunks=\(meshChunks)")
        capturePoses()
        captureDensePoses()
        captureARKitMesh()   // sessiya to'xtashidan OLDIN — ARMeshAnchor buferlaridan
        roomSession.stop()
    }

    /// RoomPlan konfiguratsiyasiga sceneReconstruction (mesh) + sceneDepth qo'shadi.
    /// Sessiya/tracking saqlanadi — RoomPlan ishlashda davom etadi.
    private func enableMeshAndDepth() {
        guard isScanning else { return }
        guard let config = arView.session.configuration as? ARWorldTrackingConfiguration else {
            debugLog?.log("MESH+DEPTH: config worldtracking emas")
            return
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        arView.session.run(config)
        debugLog?.log("MESH+DEPTH enabled (sceneReconstruction=\(config.sceneReconstruction == .mesh), sceneDepth=\(config.frameSemantics.contains(.sceneDepth)))")

        // Yashil qamrov pardasi — kamerага ulanadi (u bilan harakatlanadi).
        // Skan qilinmagan yo'nalishlarda yashil, skan qilinganda occluder to'sadi.
        if let pov = arView.pointOfView, pov.childNode(withName: "coverageSphere", recursively: false) == nil {
            pov.addChildNode(MeshWireframe.coverageSphere())
        }
    }

    /// ARKit real-time meshini (barcha ARMeshAnchor) world koordinatada saqlaydi.
    private func captureARKitMesh() {
        guard let paths, let frame = arView.session.currentFrame else { return }
        let mesh = LiDARMesh.snapshot(from: frame)
        if !mesh.isEmpty {
            try? LiDARMesh.write(mesh, to: paths.arkitMeshURL)
            debugLog?.log("ARKIT MESH verts=\(mesh.vertexCount) tris=\(mesh.indices.count / 3)")
        } else {
            debugLog?.log("ARKIT MESH empty")
        }
    }

    /// Keyframe pozitsiyalarini (transform+intrinsics+depth belgilari) diskka yozadi.
    private func capturePoses() {
        guard let paths, let poses = sampler?.poses, !poses.isEmpty,
              let data = try? JSONEncoder().encode(poses) else { return }
        try? data.write(to: paths.framesJSON)
        debugLog?.log("POSES saved=\(poses.count)")
    }

    /// Zich depth-kesh pozalarini yozadi (TSDF qayta-fusion uchun).
    private func captureDensePoses() {
        guard let paths, let poses = sampler?.densePoses, !poses.isEmpty,
              let data = try? JSONEncoder().encode(poses) else { return }
        try? data.write(to: paths.densePosesJSON)
        debugLog?.log("DENSE POSES saved=\(poses.count)")
    }

    private func startFrameCounter() {
        frameCountTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.capturedFrames = self.sampler?.savedCount ?? 0
            }
        }
    }
}

// MARK: - ARSCNViewDelegate (jonli wireframe qamrov)

extension ScanController: ARSCNViewDelegate {

    /// Joy "yaxshi skan qilindi" deb hisoblanishi uchun anchor shuncha marta
    /// yangilanishi kerak. Shundagina occluder qo'yiladi (ko'k tozalanadi).
    /// Bir marta ko'z tashlaganда ko'k qoladi — foydalanuvchi yaxshilab skan qiladi.
    private static let coverageMaturity = 6

    nonisolated func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        // Oq wireframe (skan qilinayotgan joy) — ko'rinadi. Occluder HALI YO'Q → ko'k qoladi.
        node.geometry = MeshWireframe.wireframe(from: meshAnchor.geometry)
        node.renderingOrder = 10
        node.setValue(1, forKey: "updates")
        Task { @MainActor in self.meshChunks += 1 }
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        node.geometry = MeshWireframe.wireframe(from: meshAnchor.geometry)
        node.renderingOrder = 10

        let count = ((node.value(forKey: "updates") as? Int) ?? 0) + 1
        node.setValue(count, forKey: "updates")

        if let occ = node.childNode(withName: "occluder", recursively: false) {
            occ.geometry = MeshWireframe.occluder(from: meshAnchor.geometry)
        } else if count >= Self.coverageMaturity {
            // Yetarlicha skan qilindi — endi occluder qo'yamiz (ko'k tozalanadi).
            let occ = SCNNode(geometry: MeshWireframe.occluder(from: meshAnchor.geometry))
            occ.renderingOrder = -10
            occ.name = "occluder"
            node.addChildNode(occ)
        }

        // Yashil qamrov bo'yash (Scaniverse uslubi): yetuk yuza yashil tus
        // oladi — foydalanuvchi tayyor joyni skan paytida ko'radi.
        if let fill = node.childNode(withName: "covfill", recursively: false) {
            fill.geometry = MeshWireframe.coverageFill(from: meshAnchor.geometry)
        } else if count >= Self.coverageMaturity {
            let fill = SCNNode(geometry: MeshWireframe.coverageFill(from: meshAnchor.geometry))
            fill.renderingOrder = 5
            fill.name = "covfill"
            node.addChildNode(fill)
        }
    }
}

// MARK: - RoomCaptureSessionDelegate

extension ScanController: RoomCaptureSessionDelegate {

    nonisolated func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        let text = Self.text(for: instruction)
        Task { @MainActor in self.instructionText = text }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let walls = room.walls.count
        let objects = room.objects.count
        Task { @MainActor in
            self.wallCount = walls
            self.objectCount = objects
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        Task { [weak self] in
            if let error {
                await self?.finish(room: nil, error: error)
                return
            }
            do {
                let builder = RoomBuilder(options: [.beautifyObjects])
                let room = try await builder.capturedRoom(from: data)
                await self?.finish(room: room, error: nil)
            } catch {
                await self?.finish(room: nil, error: error)
            }
        }
    }

    private func finish(room: CapturedRoom?, error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        isFinalizing = false
        if let error {
            debugLog?.log("SCAN ERROR \(error.localizedDescription)")
            onError?(error)
            return
        }
        guard let room, let paths else { return }
        debugLog?.log("SCAN FINISHED walls=\(room.walls.count) doors=\(room.doors.count) windows=\(room.windows.count) objects=\(room.objects.count)")
        onFinished?(room, paths)
    }

    nonisolated private static func text(for instruction: RoomCaptureSession.Instruction) -> String {
        switch instruction {
        case .moveCloseToWall:  return "Devorga yaqinroq keling"
        case .moveAwayFromWall: return "Devordan biroz uzoqlashing"
        case .slowDown:         return "Sekinroq harakatlaning"
        case .turnOnLight:      return "Yorug'likni yoqing"
        case .lowTexture:       return "Yuza teksturasi past — boshqa burchakdan sinang"
        case .normal:           return "Yaxshi — davom eting"
        @unknown default:       return ""
        }
    }
}
