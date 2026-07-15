import UIKit
import MetalKit
import simd

/// Gaussian splatni ko'rish ekrani (Metal). Pan — aylantirish, pinch — zoom.
final class SplatViewerViewController: UIViewController {

    private let model: GaussianSplatModel
    private var mtkView: MTKView!
    private var renderer: SplatRenderer!
    private var pinchStart: Float = 4

    init(model: GaussianSplatModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Splat"
        view.backgroundColor = .black

        guard let device = MTLCreateSystemDefaultDevice(),
              let r = SplatRenderer(device: device, model: model) else {
            let label = UILabel()
            label.text = "Splat render qilib bo'lmadi"
            label.textColor = .white
            label.textAlignment = .center
            label.frame = view.bounds
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(label)
            return
        }
        renderer = r

        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.delegate = renderer
        mtkView.preferredFramesPerSecond = 60
        mtkView.isOpaque = true
        view.addSubview(mtkView)

        mtkView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        mtkView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))

        let hint = UILabel()
        hint.text = "\(model.splats.count) splat • aylantirish — barmoq, zoom — pinch"
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

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: mtkView)
        g.setTranslation(.zero, in: mtkView)
        renderer.azimuth -= Float(t.x) * 0.008
        renderer.elevation = simd_clamp(renderer.elevation + Float(t.y) * 0.008, -1.4, 1.4)
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began: pinchStart = renderer.distance
        case .changed: renderer.distance = simd_clamp(pinchStart / Float(g.scale), 0.2, 60)
        default: break
        }
    }
}
