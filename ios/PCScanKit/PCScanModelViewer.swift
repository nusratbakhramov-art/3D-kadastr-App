import UIKit
import SceneKit

/// AI Baholash "3D modelni ko'rish" uchun minimal SceneKit viewer (orbit/zoom).
/// GLB'ni SceneKit yuklolmaydi, shuning uchun `previewModel` yonidagi `room.obj`'ni
/// `TexturedOBJLoader` orqali ko'rsatadi (teksturali). USDZ/SCN url ham qabul qilinadi
/// (OC zaxira). RoomScan'ning `SceneKitModelViewerController`'iga o'xshash, kit-ichida.
@available(iOS 17, *)
final class PCScanModelViewerController: UIViewController {
    private let contentNode: SCNNode?
    private let fileURL: URL?

    /// texrecon `room.obj` → TexturedOBJLoader (teksturali SCNNode).
    init(objURL: URL) {
        self.contentNode = TexturedOBJLoader.load(objURL: objURL)
        self.fileURL = nil
        super.init(nibName: nil, bundle: nil)
    }

    /// USDZ/SCN faylini to'g'ridan yuklash (OC zaxira).
    init(fileURL: URL) {
        self.contentNode = nil
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) ishlatilmaydi") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let bg = UIColor(white: 0.13, alpha: 1)
        view.backgroundColor = bg

        let scn = SCNView(frame: view.bounds)
        scn.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scn.allowsCameraControl = true
        scn.autoenablesDefaultLighting = false   // materiallar .constant/unlit
        scn.antialiasingMode = .multisampling4X
        scn.backgroundColor = bg

        let scene: SCNScene
        if let n = contentNode {
            scene = SCNScene()
            n.childNodes.forEach { $0.isHidden = false }   // parcha qatlamni ham ko'rsatamiz
            scene.rootNode.addChildNode(n)
        } else if let url = fileURL,
                  let s = try? SCNScene(url: url, options: [.checkConsistency: false]) {
            scene = s
        } else {
            scene = SCNScene()
        }
        scn.scene = scene

        // Kamerani mesh bounding box markaziga qaratamiz.
        let (minV, maxV) = scene.rootNode.boundingBox
        let cx = (minV.x + maxV.x) / 2, cy = (minV.y + maxV.y) / 2, cz = (minV.z + maxV.z) / 2
        let radius = max(maxV.x - minV.x, max(maxV.y - minV.y, maxV.z - minV.z))
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.zNear = 0.01
        cam.camera!.zFar = Double(radius) * 12 + 20
        let d = max(radius, 0.5) * 1.8
        cam.position = SCNVector3(cx + d * 0.6, cy + d * 0.5, cz + d * 0.9)
        cam.look(at: SCNVector3(cx, cy, cz))
        scene.rootNode.addChildNode(cam)
        scn.pointOfView = cam
        scn.defaultCameraController.automaticTarget = false
        scn.defaultCameraController.target = SCNVector3(cx, cy, cz)
        scn.defaultCameraController.interactionMode = .orbitTurntable
        view.addSubview(scn)

        let close = UIButton(type: .system)
        close.setTitle("✕", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 26, weight: .bold)
        close.backgroundColor = UIColor(white: 0, alpha: 0.35)
        close.layer.cornerRadius = 22
        close.frame = CGRect(x: view.bounds.width - 60, y: 52, width: 44, height: 44)
        close.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(close)
    }

    @objc private func closeTapped() { dismiss(animated: true) }
}
