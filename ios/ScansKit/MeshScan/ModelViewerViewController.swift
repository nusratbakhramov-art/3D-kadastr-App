import UIKit
import RealityKit
import simd

/// Skan qilingan teksturali modelni appning o'zida ko'rish ekrani.
/// Pan — modelni aylantirish, pinch — zoom.
final class ModelViewerViewController: UIViewController {

    private let entities: [ModelEntity]

    private var arView: ARView!
    private let cameraEntity = PerspectiveCamera()

    // Orbit holati
    private var azimuth: Float = .pi / 4
    private var elevation: Float = 0.5
    private var distance: Float = 4.0
    private var minDistance: Float = 0.5
    private var maxDistance: Float = 30.0
    private var pinchStartDistance: Float = 4.0

    init(entities: [ModelEntity]) {
        self.entities = entities
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Model"
        view.backgroundColor = .black

        arView = ARView(frame: view.bounds, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.black)
        arView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arView)
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Modelni markazga keltirish: umumiy bounds hisoblab, root'ni -center ga suramiz
        let root = Entity()
        for entity in entities {
            root.addChild(entity)
        }
        let rootAnchor = AnchorEntity(world: .zero)
        rootAnchor.addChild(root)
        arView.scene.addAnchor(rootAnchor)

        var bounds = BoundingBox()
        for entity in entities {
            bounds = bounds.union(entity.visualBounds(relativeTo: nil))
        }
        let center = bounds.center
        root.position = -center

        let radius = max(0.5, simd_length(bounds.extents) * 0.5)
        distance = radius * 1.8
        minDistance = radius * 0.15
        maxDistance = radius * 6.0

        // Kamera
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(cameraEntity)
        arView.scene.addAnchor(cameraAnchor)
        updateCamera()

        // Gestures
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pan)
        arView.addGestureRecognizer(pinch)

        let hint = UILabel()
        hint.text = "Aylantirish — barmoq, zoom — pinch"
        hint.textColor = .secondaryLabel
        hint.font = .systemFont(ofSize: 13)
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Gestures

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: arView)
        gesture.setTranslation(.zero, in: arView)

        azimuth -= Float(translation.x) * 0.008
        elevation += Float(translation.y) * 0.008
        elevation = simd_clamp(elevation, -1.4, 1.4)
        updateCamera()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartDistance = distance
        case .changed:
            distance = simd_clamp(
                pinchStartDistance / Float(gesture.scale),
                minDistance, maxDistance
            )
            updateCamera()
        default:
            break
        }
    }

    // MARK: - Camera

    private func updateCamera() {
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        let position = SIMD3<Float>(x, y, z)
        cameraEntity.position = position
        cameraEntity.look(at: .zero, from: position, relativeTo: nil)
    }
}
