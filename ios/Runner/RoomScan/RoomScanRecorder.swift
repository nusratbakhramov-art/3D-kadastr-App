import ARKit
import SceneKit
import UIKit
import simd

enum RecorderPhase: Equatable {
    case idle
    case scanning
    case processing
    case saving          // writing files to disk
    case saved(String)   // scan id
    case failed(String)
}

/// Polycam-style capture on a dedicated `ARSCNView` with
/// `sceneReconstruction = .meshWithClassification`. ARKit returns the dense LiDAR
/// mesh (+ per-face wall/floor/object classification), which we render live as a
/// WHITE wireframe (captured) / BLUE fill (still to scan) — plus RGB + depth
/// keyframes for the texturing pass. Apple RoomPlan can't run alongside scene-mesh
/// on one session (`RoomCaptureSession.run()` disables mesh+depth), so — like
/// Polycam — room structure (floor m²) is derived from the classified mesh.
///
/// The live viz is real 3D geometry IN the AR scene (perfectly aligned), unlike the
/// old 2D voxel overlay. Frame polling stays on a `CADisplayLink` (main) so we never
/// steal the session delegate from `ARSCNView`'s own renderer.
@available(iOS 17, *)
final class RoomScanRecorder: NSObject, ObservableObject {
    @Published var phase: RecorderPhase = .idle
    @Published var frameCount = 0
    @Published var depthFrameCount = 0
    @Published var meshAnchorCount = 0
    @Published var areaM2: Float = 0
    @Published var instruction = "Xonani aylanib skanlang"

    let arView = ARSCNView(frame: .zero)

    private var displayLink: CADisplayLink?
    private var lastCapturePosition: SIMD3<Float>?
    private var lastCaptureForward: SIMD3<Float>?
    private var pendingFrames: [PendingFrame] = []
    private var tickCount = 0

    // Coverage — anchors seen up close → captured (white wireframe), else blue fill.
    // Read on the render thread (renderer callbacks), written on the main polling
    // tick, so guard it with a lock.
    private let lock = NSLock()
    private var capturedAnchors = Set<UUID>()

    private let store = ScanStore.shared

    override init() {
        super.init()
        arView.delegate = self
        arView.automaticallyUpdatesLighting = true
        arView.backgroundColor = .black
    }

    // MARK: - Control

    func start() {
        guard phase == .idle || isTerminal else { return }
        pendingFrames.removeAll()
        lock.lock(); capturedAnchors.removeAll(); lock.unlock()
        frameCount = 0; depthFrameCount = 0; meshAnchorCount = 0; areaM2 = 0
        lastCapturePosition = nil; lastCaptureForward = nil; tickCount = 0

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        // Prefer a 4:3 video format (matches the LiDAR/depth aspect; no crop).
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        if let fmt = formats.first(where: {
            abs(Float($0.imageResolution.width / $0.imageResolution.height) - 4.0 / 3.0) < 0.02
        }) ?? formats.max(by: { $0.imageResolution.width < $1.imageResolution.width }) {
            config.videoFormat = fmt
        }

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        phase = .scanning
        startPolling()
    }

    func stop() {
        guard phase == .scanning else { return }
        stopPolling()

        // Snapshot the dense mesh + floor area while the anchors are still alive.
        let anchors = (arView.session.currentFrame?.anchors ?? []).compactMap { $0 as? ARMeshAnchor }
        let mesh = anchors.isEmpty ? nil : MeshConsolidator.consolidate(anchors)
        let area = anchors.isEmpty ? 0 : ClassifiedArea.floorArea(anchors)

        arView.session.pause()
        phase = .processing

        let frames = pendingFrames
        Task.detached(priority: .userInitiated) {
            await self.persist(frames: frames, mesh: mesh, floorArea: area)
        }
    }

    private var isTerminal: Bool {
        if case .saved = phase { return true }
        if case .failed = phase { return true }
        return false
    }

    // MARK: - Polling (main thread)

    private func startPolling() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 12
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopPolling() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let frame = arView.session.currentFrame else { return }
        tickCount += 1
        let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        meshAnchorCount = anchors.count

        // Floor area from classified faces — throttled (iterates many faces).
        if tickCount % 10 == 1 {
            areaM2 = ClassifiedArea.floorArea(anchors)
        }

        // Mark anchors the camera is pointed at (in front, within range) as captured
        // → they flip from blue fill to white wireframe on the next anchor update.
        markVisibleCaptured(anchors: anchors, camera: frame.camera)

        // Save an RGB+depth keyframe when the camera has moved OR rotated enough.
        // Rotation matters: surfaces scanned by turning in place (no translation)
        // would otherwise get no depth/RGB keyframe and drop out of the result.
        let position = frame.camera.transform.translation
        let c2 = frame.camera.transform.columns.2
        let forward = -simd_normalize(SIMD3<Float>(c2.x, c2.y, c2.z))   // ARKit camera looks down -Z
        let moved = lastCapturePosition.map { simd_distance($0, position) >= 0.2 } ?? true
        let turned = lastCaptureForward.map { simd_dot($0, forward) < 0.96 } ?? true   // ~16°
        guard moved || turned else { return }
        lastCapturePosition = position
        lastCaptureForward = forward
        guard let pending = PendingFrame(frame: frame) else { return }
        pendingFrames.append(pending)
        frameCount = pendingFrames.count
        if pending.depth != nil { depthFrameCount += 1 }
    }

    private func markVisibleCaptured(anchors: [ARMeshAnchor], camera: ARCamera) {
        let view = camera.viewMatrix(for: .portrait)
        lock.lock()
        for a in anchors where !capturedAnchors.contains(a.identifier) {
            let cam = view * SIMD4<Float>(a.transform.translation, 1)
            if cam.z < -0.1, cam.z > -3.5 { capturedAnchors.insert(a.identifier) }
        }
        lock.unlock()
    }

    private func isCaptured(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return capturedAnchors.contains(id)
    }

    // MARK: - Persistence

    private func persist(frames: [PendingFrame], mesh: ConsolidatedMesh?, floorArea: Float) async {
        await MainActor.run { phase = .saving }
        let id = store.nextScanID()
        do {
            let folder = try store.createFolder(for: id)
            var manifest = ScanManifest(id: id, createdAt: Date(), deviceModel: UIDevice.current.model)

            try writeFrames(frames, to: folder, manifest: &manifest)
            writeMesh(mesh, to: folder, manifest: &manifest)
            if floorArea > 0.05 { manifest.floorAreaM2 = floorArea }

            try store.saveManifest(manifest)
            await MainActor.run { phase = .saved(id) }
        } catch {
            await MainActor.run { phase = .failed("Saqlash xatosi: \(error.localizedDescription)") }
        }
    }

    private func writeFrames(_ frames: [PendingFrame], to folder: URL, manifest: inout ScanManifest) throws {
        var metas: [FrameMetadata] = []
        var depthCount = 0
        for (i, f) in frames.enumerated() {
            let imageName = String(format: "%03d.jpg", i)
            try f.jpeg.write(to: folder.appendingPathComponent("frames/\(imageName)"))

            var depthName: String?
            var confName: String?
            if let depth = f.depth {
                depthName = String(format: "%03d.depth", i)
                try depth.write(to: folder.appendingPathComponent("depth/\(depthName!)"))
                depthCount += 1
                if let conf = f.confidence {
                    confName = String(format: "%03d.conf", i)
                    try conf.write(to: folder.appendingPathComponent("depth/\(confName!)"))
                }
            }
            metas.append(FrameMetadata(
                index: i, timestamp: f.timestamp, image: imageName,
                imageWidth: f.imageWidth, imageHeight: f.imageHeight,
                transform: f.transform.flat, intrinsics: f.intrinsics.flat,
                depth: depthName, confidence: confName,
                depthWidth: f.depthWidth, depthHeight: f.depthHeight
            ))
        }
        try store.saveFrames(FramesIndex(frames: metas), id: manifest.id)
        manifest.framesJSON = "frames/frames.json"
        manifest.frameCount = metas.count
        manifest.depthCount = depthCount
    }

    private func writeMesh(_ mesh: ConsolidatedMesh?, to folder: URL, manifest: inout ScanManifest) {
        guard let mesh, mesh.vertexCount > 0 else { return }
        let plain = TexturedMesh(
            positions: mesh.positions, normals: mesh.normals, indices: mesh.indices,
            colors: Array(repeating: SIMD3<Float>(0.72, 0.72, 0.75), count: mesh.positions.count)
        )
        try? GeometryIO.write(mesh, to: folder.appendingPathComponent("geometry.bin"))
        try? MeshExporter.exportPLY(plain, to: folder.appendingPathComponent("mesh.ply"))
        manifest.hasMesh = true
        manifest.geometryBin = "geometry.bin"
        manifest.meshPLY = "mesh.ply"
        manifest.meshVertexCount = mesh.vertexCount
        manifest.meshTriangleCount = mesh.triangleCount

        // mesh.usdz of the dense ARKit mesh via SceneKit (lets the "raw LiDAR mesh"
        // preview work). Plain lit geometry — no texture.
        let meshUSDZ = folder.appendingPathComponent("mesh.usdz")
        if writeMeshUSDZ(mesh, to: meshUSDZ) { manifest.meshUSDZ = "mesh.usdz" }
    }

    /// Write a plain (untextured) mesh to USDZ via SceneKit. SceneKit's
    /// `SCNScene.write(to:)` is the reliable on-device USDZ path (ModelIO can't).
    private func writeMeshUSDZ(_ mesh: ConsolidatedMesh, to url: URL) -> Bool {
        let vertices = SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) })
        let normals = SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) })
        let indexData = mesh.indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(data: indexData, primitiveType: .triangles,
                                         primitiveCount: mesh.indices.count / 3,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)
        let geometry = SCNGeometry(sources: [vertices, normals], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.80, alpha: 1)
        material.roughness.contents = 0.95
        material.isDoubleSided = true
        geometry.firstMaterial = material

        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))
        try? FileManager.default.removeItem(at: url)
        return scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
    }
}

// MARK: - ARSCNViewDelegate (live mesh visualization, Polycam-style)

@available(iOS 17, *)
extension RoomScanRecorder: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        ARMeshViz.apply(to: node, mesh: mesh.geometry, captured: isCaptured(mesh.identifier))
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        ARMeshViz.apply(to: node, mesh: mesh.geometry, captured: isCaptured(mesh.identifier))
    }
}
