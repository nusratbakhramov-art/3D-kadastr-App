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

    /// Saqlangan xom skanni (id = 1_000_000 + index) HEADLESS teksturalaydi
    /// (`ReconstructionViewModel.run` — UI shart emas) va asosiy model yo'lини
    /// qaytaradi. P2: `filePath` = texrecon `room.obj` (aks holda `run()` qaytargani
    /// yoki `model.usdz`). GLB+USDZ eksporti P3/P4 da qo'shiladi.
    public func processScan(_ savedScanId: Int,
                            completion: @escaping ([String: Any]?, NSError?) -> Void) {
        guard #available(iOS 17, *) else {
            completion(nil, pcscanError("iOS 17+ kerak")); return
        }
        let index = savedScanId - 1_000_000
        Task { @MainActor in
            let library = ScanLibrary()   // init reload qiladi
            guard let record = library.records.first(where: { $0.index == index }),
                  let artifacts = library.loadArtifacts(record) else {
                completion(nil, pcscanError("skan topilmadi: #\(index)"))
                return
            }
            // Headless rekonstruksiya (texrecon → OBJ; zaxira: fusion/OC).
            let modelURL = await ReconstructionViewModel().run(
                paths: artifacts.paths, room: artifacts.capturedRoom
            )
            // Ro'yxat yozuvini yangilaymiz (hasTexture/hasMesh).
            var arts = artifacts
            arts.texturedModelURL = modelURL
            library.updateAfterReprocess(folderName: record.folderName, artifacts: arts)

            // P3: texrecon room.obj → atlas.glb (backend'ga yuklanadigan asosiy model).
            // GLB export xato bo'lsa OBJ'ga qaytamiz; texrecon umuman ishlamasa (eski
            // skan / OC zaxira) model.usdz.
            let fm = FileManager.default
            let objURL = artifacts.paths.texturesDir.appendingPathComponent("room.obj")
            var primary: URL?
            if fm.fileExists(atPath: objURL.path) {
                let glbURL = artifacts.paths.texturesDir.appendingPathComponent("atlas.glb")
                do {
                    try PCScanGLBExport.export(objURL: objURL, to: glbURL)
                    primary = glbURL
                } catch {
                    DebugLog(url: artifacts.paths.debugLog)
                        .log("GLB export xato: \(error.localizedDescription) — OBJ'ga qaytildi")
                    primary = objURL
                }
                // P4: room.obj → atlas.usdz (backend'ga GLB bilan birga; QuickLook/AR).
                // Ikkilamchi — xato bo'lsa faqat log, GLB asosiy bo'lib qolaveradi.
                let usdzURL = artifacts.paths.texturesDir.appendingPathComponent("atlas.usdz")
                do {
                    try PCScanUSDZExport.export(objURL: objURL, to: usdzURL)
                } catch {
                    DebugLog(url: artifacts.paths.debugLog)
                        .log("USDZ export xato: \(error.localizedDescription)")
                }
            } else if let modelURL, fm.fileExists(atPath: modelURL.path) {
                primary = modelURL
            } else if fm.fileExists(atPath: artifacts.paths.modelURL.path) {
                primary = artifacts.paths.modelURL
            }
            guard let primary else {
                completion(nil, pcscanError("model yaratilmadi"))
                return
            }
            let size = ((try? fm.attributesOfItem(atPath: primary.path))?[.size] as? Int) ?? 0
            completion([
                "scanId": savedScanId,
                "version": 1,
                "filePath": primary.path,   // P3/P4: bu GLB'ga almashtiriladi
                "fileSize": size,
                "mode": "offline_processed",
            ], nil)
        }
    }

    /// Yuklanadigan artefaktlar: `atlas.glb` + `atlas.usdz` (`[{path,rel,type,sizeBytes}]`).
    /// AI Baholash happy-path faqat `glb`+`usdz`'ni yuklaydi (Flutter filtri).
    public func listScanFiles(_ savedScanId: Int) -> [[String: Any]] {
        guard let paths = Self.resolvePaths(savedScanId) else { return [] }
        let fm = FileManager.default
        let rootPath = paths.root.path
        var out: [[String: Any]] = []
        func add(_ url: URL, _ type: String) {
            guard fm.fileExists(atPath: url.path) else { return }
            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
            let rel = url.path.replacingOccurrences(of: rootPath + "/", with: "")
            out.append(["path": url.path, "rel": rel, "type": type, "sizeBytes": size])
        }
        add(paths.texturesDir.appendingPathComponent("atlas.glb"), "glb")
        add(paths.texturesDir.appendingPathComponent("atlas.usdz"), "usdz")
        return out
    }

    /// 3D modelni ko'rsatadi. `path` = asosiy model (GLB); GLB SceneKit'da render
    /// bo'lmaydi → yonidagi `room.obj`'ni ko'rsatamiz (u yo'q bo'lsa berilgan faylni).
    public func presentViewer(from presenter: UIViewController, path: String) {
        guard #available(iOS 17, *) else { return }
        MainActor.assumeIsolated {
            let dir = (path as NSString).deletingLastPathComponent
            let objURL = URL(fileURLWithPath: dir).appendingPathComponent("room.obj")
            let viewer: PCScanModelViewerController
            if FileManager.default.fileExists(atPath: objURL.path) {
                viewer = PCScanModelViewerController(objURL: objURL)
            } else {
                viewer = PCScanModelViewerController(fileURL: URL(fileURLWithPath: path))
            }
            viewer.modalPresentationStyle = .fullScreen
            presenter.present(viewer, animated: true)
        }
    }

    /// Barcha PCScan skanlar (scanMap) — "Skanlarim" ro'yxati.
    public func listScans() -> [[String: Any]] {
        MainActor.assumeIsolated {
            let lib = ScanLibrary()
            return lib.records.map { rec in
                Self.scanMap(record: rec, paths: StorageService.session(named: rec.folderName))
            }
        }
    }

    /// Bitta skan xulosasi.
    public func scanSummary(_ savedScanId: Int) -> [String: Any]? {
        MainActor.assumeIsolated {
            let index = savedScanId - 1_000_000
            let lib = ScanLibrary()
            guard let rec = lib.records.first(where: { $0.index == index }) else { return nil }
            return Self.scanMap(record: rec, paths: StorageService.session(named: rec.folderName))
        }
    }

    /// Skanni butunlay o'chiradi (papka bilan).
    public func deleteScan(_ savedScanId: Int) -> Bool {
        MainActor.assumeIsolated {
            let index = savedScanId - 1_000_000
            let lib = ScanLibrary()
            guard let rec = lib.records.first(where: { $0.index == index }) else { return false }
            lib.delete(rec)
            return true
        }
    }

    /// Chiqish modellarini (atlas.glb/atlas.usdz) o'chiradi (skan/xom ma'lumot qoladi).
    public func deleteOutput(_ savedScanId: Int) -> Bool {
        guard let paths = Self.resolvePaths(savedScanId) else { return false }
        let fm = FileManager.default
        var any = false
        for name in ["atlas.glb", "atlas.usdz"] {
            let u = paths.texturesDir.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) { try? fm.removeItem(at: u); any = true }
        }
        return any
    }

    /// `RoomScanBridge.scanMap` shakliga mos skan xulosasi (Flutter SavedScanService o'qiydi).
    private static func scanMap(record: ScanRecord, paths: ScanPaths) -> [String: Any] {
        let fm = FileManager.default
        var outputs: [[String: Any]] = []
        let glb = paths.texturesDir.appendingPathComponent("atlas.glb")
        if fm.fileExists(atPath: glb.path) {
            let size = ((try? fm.attributesOfItem(atPath: glb.path))?[.size] as? Int) ?? 0
            outputs.append([
                "version": 1,
                "fileName": "atlas.glb",
                "createdAt": record.createdAt.timeIntervalSince1970,
                "sizeBytes": size,
                "params": [String: String](),
            ])
        }
        return [
            "id": 1_000_000 + record.index,
            "name": record.title,
            "createdAt": record.createdAt.timeIntervalSince1970,
            "photoCount": record.frameCount,
            "areaSqm": Double(record.floorArea),
            "outputs": outputs,
        ]
    }

    /// Asosiy model yo'li (GLB ustuvor, aks holda USDZ).
    public func outputPath(_ savedScanId: Int) -> String? {
        guard let paths = Self.resolvePaths(savedScanId) else { return nil }
        let fm = FileManager.default
        let glb = paths.texturesDir.appendingPathComponent("atlas.glb")
        if fm.fileExists(atPath: glb.path) { return glb.path }
        let usdz = paths.texturesDir.appendingPathComponent("atlas.usdz")
        return fm.fileExists(atPath: usdz.path) ? usdz.path : nil
    }

    /// `savedScanId` (1_000_000 + index) → PCScan scan papkasi yo'llari.
    /// Main-thread'da chaqiriladi (Flutter kanal handleri) — `ScanLibrary` @MainActor.
    static func resolvePaths(_ savedScanId: Int) -> ScanPaths? {
        MainActor.assumeIsolated {
            let index = savedScanId - 1_000_000
            let lib = ScanLibrary()
            guard let rec = lib.records.first(where: { $0.index == index }) else { return nil }
            return StorageService.session(named: rec.folderName)
        }
    }
}

/// Facade uchun qisqa NSError yordamchisi (dlopen chegarasidan o'tadi).
private func pcscanError(_ message: String) -> NSError {
    NSError(domain: "PCScanKit", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
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
