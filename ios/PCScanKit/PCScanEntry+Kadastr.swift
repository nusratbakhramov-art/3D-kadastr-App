import UIKit
import SwiftUI

/// `PCScanEntry`'ning Kadastr AI Baholash uchun natija-qaytaruvchi yuzasi
/// (`PCScanFacade` muvofiqligi). Runner PCScanKit'ni link qilmagani uchun bu
/// kit-ichidagi conformance dlopen'dan keyin `as? PCScanFacade` bilan topiladi.
///
/// Holat: P1 presentCapture BAJARILDI. Qolgani stub — P2 processScan, P3 GLB,
/// P4 USDZ, P5 listScanFiles/viewer, P7 list/delete.
extension PCScanEntry: PCScanFacade {

    /// AI Baholash uchun **capture-only** oqim: PCScan'ni present qiladi va
    /// foydalanuvchi xom skanni saqlagach (`AppState.scanningFinished`) `saved_raw`
    /// map bilan qaytadi; bekor qilinsa (modal yopilsa) aynan bir marta `nil`.
    /// Viewer/processing'ga O'TMAYDI — AI Baholash oqimida keyingi qadam Flutter
    /// tomonda (`process`) chaqiriladi. Natija shakli `RoomScanBridge.startCapture`
    /// ga aynan mos; `savedScanId = 1_000_000 + record.index` (RoomScan id'laridan
    /// ajratish uchun).
    public func presentCapture(from presenter: UIViewController,
                               onFinished: @escaping ([String: Any]?) -> Void) {
        guard #available(iOS 17, *) else { onFinished(nil); return }
        MainActor.assumeIsolated {
            var didFinish = false
            weak var containerRef: UIViewController?
            // Finish + BARCHA bekor yo'llari shu guard'dan o'tadi — aynan bir marta
            // (aks holda Flutter `await` osilib qolishi yoki ikki marta chaqirilishi mumkin).
            let finish: ([String: Any]?) -> Void = { map in
                guard !didFinish else { return }
                didFinish = true
                containerRef?.dismiss(animated: true)
                onFinished(map)
            }

            let appState = AppState()
            appState.captureOnlyCompletion = { record in
                finish([
                    "savedScanId": 1_000_000 + record.index,
                    "mode": "saved_raw",
                    "walls": record.wallCount,
                    "doors": 0,
                    "windows": 0,
                    "objects": record.objectCount,
                    "floorAreaSqm": Double(record.floorArea),
                    "fileSize": 0,
                ])
            }

            let root = RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
            let host = UIHostingController(rootView: root)
            let container = PCScanCaptureContainer(child: host, onClose: { finish(nil) })
            container.modalPresentationStyle = .fullScreen
            containerRef = container
            presenter.present(container, animated: true)
        }
    }

    public func processScan(_ savedScanId: Int,
                            completion: @escaping ([String: Any]?, NSError?) -> Void) {
        // TODO(P2): headless texturing → GLB path.
        completion(nil, NSError(domain: "PCScanKit", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "processScan not implemented (P2)"]))
    }

    public func listScanFiles(_ savedScanId: Int) -> [[String: Any]] { [] }   // TODO(P5)

    public func presentViewer(from presenter: UIViewController, path: String) {}  // TODO(P5)

    public func availableScanIds() -> [NSNumber] { [] }   // TODO(P7)

    public func deleteScan(_ savedScanId: Int) -> Bool { false }   // TODO(P7)

    public func outputPath(_ savedScanId: Int) -> String? { nil }   // TODO(P7)
}

/// Capture-only modal konteyneri — `PCScanContainerViewController` ga o'xshash, lekin
/// "Yopish" tugmasi `onClose` ni chaqiradi (Flutter'ga BEKOR signal + dismiss), shunchaki
/// dismiss qilib qo'ymaydi (aks holda Flutter `startTexturedScan` future'i osilib qolardi).
@available(iOS 17, *)
final class PCScanCaptureContainer: UIViewController {
    private let child: UIViewController
    private let onClose: () -> Void

    init(child: UIViewController, onClose: @escaping () -> Void) {
        self.child = child
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) ishlatilmaydi") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        child.didMove(toParent: self)

        let close = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: "xmark")
        cfg.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        close.configuration = cfg
        close.addAction(UIAction { [weak self] _ in self?.onClose() }, for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }
}
