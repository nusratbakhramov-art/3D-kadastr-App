import SceneKit
import UIKit
import RoomPlan
import ModelIO
import SceneKit.ModelIO
import simd

/// Ko'rish rejimi.
enum ViewMode: String, CaseIterable, Identifiable {
    case textured   // Real teksturali (Object Capture)
    case solid      // Parametrik to'ldirilgan
    case wireframe  // Karkas

    var id: String { rawValue }
    var title: String {
        switch self {
        case .textured:  return "Tekstura"
        case .solid:     return "Parametrik"
        case .wireframe: return "Karkas"
        }
    }
}

/// M3 — SceneKit ko'rinishini boshqaruvchi: qatlamlar, kameralar, rejim, tanlash.
@MainActor
final class RoomSceneController: NSObject {

    let scnView = SCNView(frame: .zero)
    private let scene = SCNScene()

    private let room: CapturedRoom
    private let bounds: RoomBounds
    private let texturedModelURL: URL?
    private let lidarMeshURL: URL?
    private let meshColorsURL: URL?
    private let texturedRoomDir: URL?

    private let structureRoot = SCNNode()
    private let objectsRoot = SCNNode()
    private let labelsRoot = SCNNode()
    private var texturedRoot: SCNNode?

    private let orbitCameraNode = SCNNode()
    private let fpCameraNode = SCNNode()
    private var fpYaw: Float = 0
    private var fpPitch: Float = 0

    private(set) var mode: ViewMode = .solid
    private(set) var unit: MeasurementUnit = .meters
    private(set) var labelsVisible = true
    private(set) var firstPerson = false
    private(set) var selectedID: UUID?

    /// Obyekt tanlanganda/bekor qilinganda chaqiriladi.
    var onSelectionChange: ((UUID?) -> Void)?

    private var lookPan: UIPanGestureRecognizer!
    private var movePan: UIPanGestureRecognizer!

    init(room: CapturedRoom, editableRoom: EditableRoom,
         texturedModelURL: URL?, lidarMeshURL: URL?, meshColorsURL: URL?,
         texturedRoomDir: URL?) {
        self.room = room
        self.bounds = RoomGeometry.bounds(of: room)
        self.texturedModelURL = texturedModelURL
        self.lidarMeshURL = lidarMeshURL
        self.meshColorsURL = meshColorsURL
        self.texturedRoomDir = texturedRoomDir
        super.init()
        buildScene(editableRoom: editableRoom)
        configureView()
        configureCameras()
        configureGestures()
        applyMode()
        rebuildLabels(objects: editableRoom.objects)
    }

    // MARK: - Qurilish

    private func buildScene(editableRoom: EditableRoom) {
        scene.background.contents = UIColor(white: 0.06, alpha: 1)

        let structure = RoomSceneBuilder.structureRoot(room: room, bounds: bounds)
        structureRoot.addChildNode(structure)
        scene.rootNode.addChildNode(structureRoot)

        for item in editableRoom.objects {
            objectsRoot.addChildNode(
                RoomSceneBuilder.objectNode(id: item.id, dimensions: item.dimensions, transform: item.transform)
            )
        }
        scene.rootNode.addChildNode(objectsRoot)
        scene.rootNode.addChildNode(labelsRoot)

        buildTexturedLayer()
    }

    /// Teksturali qatlam. Ustuvorlik: texrecon OBJ → OC USDZ → fusion mesh → projektiv.
    private func buildTexturedLayer() {
        // 1-ustuvor: texrecon OBJ (world-aligned, sanoat teksturasi).
        // OBJ+MTL'ni qo'lda parse qilamiz — MDLAsset UV↔tekstura bog'lanishini
        // ishonchli o'rnatmaydi (hammasi oq chiqadi).
        if let url = texturedModelURL, url.pathExtension.lowercased() == "obj",
           let node = TexturedOBJLoader.load(objURL: url) {
            let container = SCNNode()
            container.name = "texreconRoom"
            container.addChildNode(node)
            scene.rootNode.addChildNode(container)   // identity: world koordinatada
            texturedRoot = container
            return
        }

        // 2: Apple photogrammetriya modeli (USDZ) — RoomPlan'ga tekislab.
        if let url = texturedModelURL,
           let loaded = try? SCNScene(url: url, options: [.checkConsistency: false]) {
            let modelNode = SCNNode()
            for child in loaded.rootNode.childNodes {
                modelNode.addChildNode(child)
            }
            let footprint = MeshClipping.footprint(of: modelNode)
            let container = FusionService.alignedContainer(for: modelNode,
                                                           footprint: footprint,
                                                           to: bounds)
            scene.rootNode.addChildNode(container)
            texturedRoot = container
            return
        }

        // 2: on-device fusion mesh (world koordinatada).
        if let lidarURL = lidarMeshURL,
           let mesh = try? LiDARMesh.read(from: lidarURL), !mesh.isEmpty {
            let colors = meshColorsURL.flatMap { LiDARMesh.readColors(from: $0) }
            let node = SCNNode(geometry: LiDARMesh.makeGeometry(mesh, colors: colors))
            let container = SCNNode()
            container.name = "lidarMesh"
            container.addChildNode(node)
            scene.rootNode.addChildNode(container)
            texturedRoot = container
            return
        }

        // 3: projektiv panellar (o'chirilgan bo'lishi mumkin).
        if let dir = texturedRoomDir {
            _ = buildProjectiveRoom(dir: dir)
        }
    }

    /// surfaces.json'dan teksturali tekis panellar (devor/pol) quradi (world-aligned).
    private func buildProjectiveRoom(dir: URL) -> Bool {
        let surfacesURL = dir.appendingPathComponent("surfaces.json")
        guard let data = try? Data(contentsOf: surfacesURL),
              let defs = try? JSONDecoder().decode([SurfaceDef].self, from: data),
              !defs.isEmpty else { return false }

        let container = SCNNode()
        container.name = "projectiveRoom"
        for def in defs {
            let plane = SCNPlane(width: CGFloat(def.width), height: CGFloat(def.height))
            let material = SCNMaterial()
            if let image = UIImage(contentsOfFile: dir.appendingPathComponent(def.texture).path) {
                material.diffuse.contents = image
            } else {
                material.diffuse.contents = UIColor(white: 0.75, alpha: 1)
            }
            material.isDoubleSided = true
            material.lightingModel = .constant   // tekstura o'z yorug'ligida
            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            node.simdTransform = simd_float4x4(
                simd_float4(def.transform[0], def.transform[1], def.transform[2], def.transform[3]),
                simd_float4(def.transform[4], def.transform[5], def.transform[6], def.transform[7]),
                simd_float4(def.transform[8], def.transform[9], def.transform[10], def.transform[11]),
                simd_float4(def.transform[12], def.transform[13], def.transform[14], def.transform[15])
            )
            container.addChildNode(node)
        }
        scene.rootNode.addChildNode(container)
        texturedRoot = container
        return true
    }

    private func configureView() {
        scnView.scene = scene
        scnView.backgroundColor = UIColor(white: 0.06, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        scene.rootNode.addChildNode(ambient)
    }

    private func configureCameras() {
        orbitCameraNode.camera = SCNCamera()
        orbitCameraNode.camera?.zNear = 0.01
        orbitCameraNode.camera?.zFar = 200
        let dist = max(bounds.width, bounds.depth) * 1.4 + 1
        orbitCameraNode.position = SCNVector3(bounds.centerX,
                                              bounds.ceilingY + 1.0,
                                              bounds.centerZ + dist)
        orbitCameraNode.look(at: SCNVector3(bounds.centerX, bounds.floorY, bounds.centerZ))
        scene.rootNode.addChildNode(orbitCameraNode)

        fpCameraNode.camera = SCNCamera()
        fpCameraNode.camera?.zNear = 0.01
        fpCameraNode.camera?.zFar = 200
        fpCameraNode.camera?.fieldOfView = 70
        scene.rootNode.addChildNode(fpCameraNode)

        scnView.pointOfView = orbitCameraNode
    }

    private func configureGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        lookPan = UIPanGestureRecognizer(target: self, action: #selector(handleLookPan(_:)))
        lookPan.maximumNumberOfTouches = 1
        lookPan.isEnabled = false
        scnView.addGestureRecognizer(lookPan)

        movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        movePan.minimumNumberOfTouches = 2
        movePan.isEnabled = false
        scnView.addGestureRecognizer(movePan)
    }

    // MARK: - Rejim / birlik / yorliqlar

    func setMode(_ newMode: ViewMode) {
        mode = newMode
        applyMode()
    }

    private func applyMode() {
        let hasTexture = texturedRoot != nil
        let effective: ViewMode = (mode == .textured && !hasTexture) ? .solid : mode

        switch effective {
        case .textured:
            texturedRoot?.isHidden = false
            structureRoot.isHidden = true
            objectsRoot.isHidden = true
        case .solid:
            texturedRoot?.isHidden = true
            structureRoot.isHidden = false
            objectsRoot.isHidden = false
            setFillMode(.fill)
        case .wireframe:
            texturedRoot?.isHidden = true
            structureRoot.isHidden = false
            objectsRoot.isHidden = false
            setFillMode(.lines)
        }
    }

    private func setFillMode(_ fill: SCNFillMode) {
        for root in [structureRoot, objectsRoot] {
            root.enumerateHierarchy { node, _ in
                node.geometry?.materials.forEach { $0.fillMode = fill }
            }
        }
    }

    func setUnit(_ newUnit: MeasurementUnit, objects: [EditableRoom.Item]) {
        unit = newUnit
        rebuildLabels(objects: objects)
    }

    func setLabelsVisible(_ visible: Bool) {
        labelsVisible = visible
        labelsRoot.isHidden = !visible
    }

    func rebuildLabels(objects: [EditableRoom.Item]) {
        labelsRoot.childNodes.forEach { $0.removeFromParentNode() }

        for wall in room.walls {
            let p = wall.transform.columns.3
            let text = "\(unit.format(wall.dimensions.x)) × \(unit.format(wall.dimensions.y))"
            labelsRoot.addChildNode(
                RoomSceneBuilder.textNode(text, at: simd_float3(p.x, p.y, p.z))
            )
        }

        for item in objects {
            let p = item.transform.columns.3
            let pos = simd_float3(p.x, p.y + item.dimensions.y / 2 + 0.12, p.z)
            let text = unit.formatDimensions(width: item.dimensions.x,
                                             height: item.dimensions.y,
                                             depth: item.dimensions.z)
            labelsRoot.addChildNode(
                RoomSceneBuilder.textNode(text, at: pos, color: RoomSceneBuilder.objectColor)
            )
        }
        labelsRoot.isHidden = !labelsVisible
    }

    // MARK: - First-person

    func setFirstPerson(_ enabled: Bool) {
        firstPerson = enabled
        // Parcha qatlami (unseen_vc + fillmat) faqat XONA ICHIDAN ko'rinadi.
        // Winding'ni to'g'rilash ularni orqadan kesadi, lekin qiya burchakda
        // normal hali kameraga qaragan bo'lib qolaveradi — shuning uchun
        // tashqaridan (orbita) butun qatlam yashiriladi.
        texturedRoot?.enumerateHierarchy { node, _ in
            if node.name == TexturedOBJLoader.fragmentNodeName { node.isHidden = !enabled }
        }
        if enabled {
            fpYaw = 0
            fpPitch = 0
            fpCameraNode.position = SCNVector3(bounds.centerX, bounds.floorY + 1.6, bounds.centerZ)
            fpCameraNode.eulerAngles = SCNVector3(0, 0, 0)
            scnView.pointOfView = fpCameraNode
            scnView.allowsCameraControl = false
            lookPan.isEnabled = true
            movePan.isEnabled = true
        } else {
            scnView.pointOfView = orbitCameraNode
            scnView.allowsCameraControl = true
            lookPan.isEnabled = false
            movePan.isEnabled = false
        }
    }

    // MARK: - Tanlash / tahrirlash aksi

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        let point = gr.location(in: scnView)
        let hits = scnView.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
        for hit in hits {
            if let id = objectID(for: hit.node) {
                select(id: id)
                return
            }
        }
        select(id: nil)
    }

    /// Tugun ierarxiyasidan obyekt UUID'sini topadi.
    private func objectID(for node: SCNNode) -> UUID? {
        var current: SCNNode? = node
        while let n = current {
            if let name = n.name, let uuid = UUID(uuidString: name),
               objectsRoot.childNode(withName: name, recursively: false) != nil {
                return uuid
            }
            current = n.parent
        }
        return nil
    }

    func select(id: UUID?) {
        if let previous = selectedID {
            setHighlight(id: previous, on: false)
        }
        selectedID = id
        if let id {
            setHighlight(id: id, on: true)
        }
        onSelectionChange?(id)
    }

    private func setHighlight(id: UUID, on: Bool) {
        guard let node = objectsRoot.childNode(withName: id.uuidString, recursively: false) else { return }
        let color = on ? RoomSceneBuilder.selectedColor : RoomSceneBuilder.objectColor
        node.geometry?.materials.forEach { $0.diffuse.contents = color }
    }

    func removeObject(id: UUID, remainingObjects: [EditableRoom.Item]) {
        objectsRoot.childNode(withName: id.uuidString, recursively: false)?.removeFromParentNode()
        if selectedID == id { selectedID = nil }
        rebuildLabels(objects: remainingObjects)
        onSelectionChange?(nil)
    }

    func updateLabelsAfterRename(objects: [EditableRoom.Item]) {
        rebuildLabels(objects: objects)
    }

    // MARK: - First-person gesture handlerlari

    @objc private func handleLookPan(_ gr: UIPanGestureRecognizer) {
        let t = gr.translation(in: scnView)
        gr.setTranslation(.zero, in: scnView)
        let sensitivity: Float = 0.005
        fpYaw -= Float(t.x) * sensitivity
        fpPitch -= Float(t.y) * sensitivity
        fpPitch = max(-Float.pi / 2 + 0.1, min(Float.pi / 2 - 0.1, fpPitch))
        fpCameraNode.eulerAngles = SCNVector3(fpPitch, fpYaw, 0)
    }

    @objc private func handleMovePan(_ gr: UIPanGestureRecognizer) {
        let t = gr.translation(in: scnView)
        gr.setTranslation(.zero, in: scnView)
        let speed: Float = 0.01
        // Kamera yo'nalishi bo'yicha oldinga/orqaga va yon harakat.
        let forward = simd_float3(-sin(fpYaw), 0, -cos(fpYaw))
        let right = simd_float3(cos(fpYaw), 0, -sin(fpYaw))
        var pos = fpCameraNode.simdPosition
        pos += forward * (Float(-t.y) * speed)
        pos += right * (Float(t.x) * speed)
        fpCameraNode.simdPosition = pos
    }
}
