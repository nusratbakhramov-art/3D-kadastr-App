/// RoomPlan scanner — Apple'ning iOS 16+ RoomPlan API'sini wrap qiladi.
///
/// Flutter'dan `kadastr/room_plan_scanner` MethodChannel orqali chaqiriladi:
///   - "isSupported"  → Bool (qurilma RoomPlan'ni qo'llaydimi)
///   - "startScan"    → modal RoomCaptureView ochadi, foydalanuvchi tugmasini
///                      bosgach `usdz` fayl yo'lini Map sifatida qaytaradi.
///                      Cancel bosilsa `null` qaytaradi.
///                      Xato bo'lsa FlutterError chaqiradi.
import Flutter
import UIKit
import ARKit
import QuickLook
import SceneKit
import simd
import VideoToolbox
import UniformTypeIdentifiers
import RealityKit
import CoreMotion
#if canImport(RoomPlan)
import RoomPlan
#endif


// USDZ faylini Apple QuickLook orqali ko'rsatish (rotate/zoom/AR mode native).
final class UsdzPreviewer: NSObject, QLPreviewControllerDataSource {
    static let shared = UsdzPreviewer()

    private var fileUrl: URL?

    func present(
        filePath: String,
        from controller: UIViewController,
        result: @escaping FlutterResult,
    ) {
        guard FileManager.default.fileExists(atPath: filePath) else {
            result(FlutterError(
                code: "NOT_FOUND",
                message: "3D fayl topilmadi: \(filePath)",
                details: nil,
            ))
            return
        }
        self.fileUrl = URL(fileURLWithPath: filePath)
        let preview = QLPreviewController()
        preview.dataSource = self
        preview.modalPresentationStyle = .fullScreen
        controller.present(preview, animated: true) {
            result(nil)
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return fileUrl != nil ? 1 : 0
    }

    func previewController(
        _ controller: QLPreviewController,
        previewItemAt index: Int,
    ) -> QLPreviewItem {
        return (fileUrl ?? URL(fileURLWithPath: "")) as QLPreviewItem
    }
}


@available(iOS 16.0, *)
final class RoomPlanScannerCoordinator: NSObject {
    static let shared = RoomPlanScannerCoordinator()

    private weak var presentingController: UIViewController?
    private var pendingResult: FlutterResult?
    private var sessionVC: RoomCaptureViewController?

    func start(from controller: UIViewController, result: @escaping FlutterResult) {
        // Concurrent invocation guard.
        if pendingResult != nil {
            result(FlutterError(
                code: "ALREADY_SCANNING",
                message: "Boshqa skan jarayoni hali tugamagan",
                details: nil,
            ))
            return
        }
        #if canImport(RoomPlan)
        guard RoomCaptureSession.isSupported else {
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Qurilmangiz RoomPlan'ni qo'llab-quvvatlamaydi",
                details: nil,
            ))
            return
        }

        self.presentingController = controller
        self.pendingResult = result

        let vc = RoomCaptureViewController()
        vc.onFinished = { [weak self] capturedRoom, error in
            self?.handleFinish(capturedRoom: capturedRoom, error: error)
        }
        vc.onCancel = { [weak self] in
            self?.handleCancel()
        }
        vc.modalPresentationStyle = .fullScreen
        controller.present(vc, animated: true)
        self.sessionVC = vc
        #else
        result(FlutterError(
            code: "UNSUPPORTED",
            message: "RoomPlan iOS 16+ ga muhtoj",
            details: nil,
        ))
        #endif
    }

    #if canImport(RoomPlan)
    private func handleFinish(capturedRoom: CapturedRoom?, error: Error?) {
        guard let result = pendingResult else { return }
        pendingResult = nil

        sessionVC?.dismiss(animated: true)
        sessionVC = nil

        if let error = error {
            result(FlutterError(
                code: "SCAN_FAILED",
                message: error.localizedDescription,
                details: nil,
            ))
            return
        }
        guard let room = capturedRoom else {
            result(nil)  // cancelled
            return
        }

        // USDZ ni Documents/scans/<uuid>.usdz ga eksport qilamiz.
        do {
            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask,
            ).first!
            let folder = documents.appendingPathComponent("scans", isDirectory: true)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
            )
            let id = UUID().uuidString
            let url = folder.appendingPathComponent("\(id).usdz")
            try room.export(to: url, exportOptions: .parametric)

            // Tahlil uchun statistika.
            let walls = room.walls.count
            let doors = room.doors.count
            let windows = room.windows.count
            let openings = room.openings.count
            let objects = room.objects.count

            // Floor area (parametric'dan oddiy hisoblash).
            let floorArea = estimateFloorArea(from: room)

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attrs?[.size] as? Int) ?? 0

            result([
                "filePath": url.path,
                "fileSize": fileSize,
                "walls": walls,
                "doors": doors,
                "windows": windows,
                "openings": openings,
                "objects": objects,
                "floorAreaSqm": floorArea,
            ])
        } catch {
            result(FlutterError(
                code: "EXPORT_FAILED",
                message: "USDZ saqlash xatoligi: \(error.localizedDescription)",
                details: nil,
            ))
        }
    }

    private func estimateFloorArea(from room: CapturedRoom) -> Double {
        // CapturedRoom.walls dan polning x-z prokeksiyasi orqali baholash.
        // Aniq hisoblash uchun keyinroq Polygon clipping ishlatamiz; hozir
        // bouncing box approximation.
        guard !room.walls.isEmpty else { return 0 }
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        for wall in room.walls {
            let pos = wall.transform.columns.3
            minX = min(minX, pos.x)
            maxX = max(maxX, pos.x)
            minZ = min(minZ, pos.z)
            maxZ = max(maxZ, pos.z)
        }
        let w = Double(maxX - minX)
        let h = Double(maxZ - minZ)
        return (w * h * 100).rounded() / 100  // 2 decimal places
    }
    #endif

    private func handleCancel() {
        guard let result = pendingResult else { return }
        pendingResult = nil
        sessionVC?.dismiss(animated: true)
        sessionVC = nil
        result(nil)
    }
}


// ────────────────────────────────────────────────────────────────────────
// RoomCaptureView'ni hosting qiladigan UIViewController.
// ────────────────────────────────────────────────────────────────────────

#if canImport(RoomPlan)
@available(iOS 16.0, *)
final class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {

    var onFinished: ((CapturedRoom?, Error?) -> Void)?
    var onCancel: (() -> Void)?

    private var roomCaptureView: RoomCaptureView!
    private var captureSessionConfig = RoomCaptureSession.Configuration()
    private var finalResults: CapturedRoom?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupRoomCaptureView()
        setupButtons()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        roomCaptureView.captureSession.run(configuration: captureSessionConfig)
    }

    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        roomCaptureView.captureSession.stop()
    }

    private func setupRoomCaptureView() {
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(roomCaptureView)
    }

    private func setupButtons() {
        // Done (yopish) tugmasi — pastda o'ng tomonda.
        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Tugatish", for: .normal)
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneBtn.backgroundColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)  // splashGreen
        doneBtn.layer.cornerRadius = 24
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)

        // Cancel (yopib bekor qilish) tugmasi — yuqorida chap tomonda.
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Bekor qilish", for: .normal)
        cancelBtn.setTitleColor(.white, for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cancelBtn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        cancelBtn.layer.cornerRadius = 18
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            doneBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            doneBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneBtn.widthAnchor.constraint(equalToConstant: 200),
            doneBtn.heightAnchor.constraint(equalToConstant: 48),

            cancelBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelBtn.heightAnchor.constraint(equalToConstant: 36),
            cancelBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])
    }

    @objc private func doneTapped() {
        // Skanni to'xtatish — `captureView(shouldPresent:error:)` da finalResults
        // saqlanadi va biz keyin onFinished ni chaqiramiz.
        // iOS 17+ da `pauseARSession:` parametri bor, iOS 16'da yo'q.
        if #available(iOS 17, *) {
            roomCaptureView.captureSession.stop(pauseARSession: false)
        } else {
            roomCaptureView.captureSession.stop()
        }
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResults = processedResult
        onFinished?(processedResult, error)
    }
}
#endif


// ────────────────────────────────────────────────────────────────────────
// Photogrammetry scanner — Apple PhotogrammetrySession orqali fotorealistik
// 3D model yaratish. Foydalanuvchi xona bo'ylab yurganda avtomatik foto
// olinadi, keyin Apple'ning algoritmlari texture bilan USDZ generatsiya qiladi.
// ────────────────────────────────────────────────────────────────────────

@available(iOS 17.0, *)
final class TexturedScanCoordinator: NSObject {
    static let shared = TexturedScanCoordinator()

    private weak var presentingController: UIViewController?
    private var pendingResult: FlutterResult?
    private var sessionVC: TexturedScanViewController?

    func start(from controller: UIViewController, result: @escaping FlutterResult) {
        if pendingResult != nil {
            result(FlutterError(
                code: "ALREADY_SCANNING",
                message: "Boshqa skan jarayoni hali tugamagan",
                details: nil,
            ))
            return
        }
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Qurilmangizda LiDAR yo'q (iPhone Pro / iPad Pro kerak)",
                details: nil,
            ))
            return
        }

        self.presentingController = controller
        self.pendingResult = result

        let vc = TexturedScanViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.onFinished = { [weak self] (url, stats) in
            self?.handleFinish(url: url, stats: stats)
        }
        vc.onCancel = { [weak self] in self?.handleCancel() }
        vc.onError = { [weak self] err in self?.handleError(err) }
        controller.present(vc, animated: true)
        self.sessionVC = vc
    }

    private func handleFinish(url: URL, stats: TexturedScanStats) {
        guard let result = pendingResult else { return }
        pendingResult = nil
        sessionVC?.dismiss(animated: true)
        sessionVC = nil

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs?[.size] as? Int) ?? 0
        result([
            "filePath": url.path,
            "fileSize": fileSize,
            "walls": 0,
            "doors": 0,
            "windows": 0,
            "openings": 0,
            "objects": 0,
            "floorAreaSqm": stats.floorAreaSqm,
        ])
    }

    private func handleCancel() {
        guard let result = pendingResult else { return }
        pendingResult = nil
        sessionVC?.dismiss(animated: true)
        sessionVC = nil
        result(nil)
    }

    private func handleError(_ err: Error) {
        guard let result = pendingResult else { return }
        pendingResult = nil
        sessionVC?.dismiss(animated: true)
        sessionVC = nil
        result(FlutterError(
            code: "SCAN_FAILED",
            message: err.localizedDescription,
            details: nil,
        ))
    }
}

struct TexturedScanStats {
    var floorAreaSqm: Double
    var vertexCount: Int
    var faceCount: Int
}


// ────────────────────────────────────────────────────────────────────────
// Photogrammetry capture + processing UIViewController.
// Capture fazasi: ARSession bilan harakat heuristikasi, avtomatik foto.
// Processing fazasi: PhotogrammetrySession async, progress UI bilan.
// ────────────────────────────────────────────────────────────────────────

@available(iOS 17.0, *)
final class TexturedScanViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {
    var onFinished: ((URL, TexturedScanStats) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((Error) -> Void)?

    // UI elementlari
    private var arView: ARSCNView!
    private var coachingOverlay: ARCoachingOverlayView!
    private var statusLabel: UILabel!
    private var doneBtn: UIButton!
    private var cancelBtn: UIButton!
    // Processing UI
    private var processingOverlay: UIView!
    private var processingLabel: UILabel!
    private var progressView: UIProgressView!
    private var processingStatusLabel: UILabel!

    // Capture state
    private var photoFolder: URL!
    private var captureCount = 0
    private var lastCapturePos: SIMD3<Float>?
    private var lastCaptureRot: simd_quatf?
    private var lastCaptureTime: TimeInterval = 0
    private let minPositionDelta: Float = 0.20    // 20 cm
    private let minRotationDelta: Float = 0.26    // ~15 degrees
    private let minTimeBetweenCaptures: TimeInterval = 0.35
    private let minRequiredPhotos = 20
    private let maxAllowedPhotos = 120

    // Processing state
    private var processingTask: Task<Void, Never>?
    private var isProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPhotoFolder()
        setupARView()
        setupCoaching()
        setupOverlay()
        setupProcessingOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
        processingTask?.cancel()
    }

    // MARK: - Setup

    private func setupPhotoFolder() {
        let temp = FileManager.default.temporaryDirectory
        photoFolder = temp.appendingPathComponent("photogrammetry_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: photoFolder,
            withIntermediateDirectories: true,
        )
    }

    private func setupARView() {
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.session.delegate = self
        arView.delegate = self  // mesh visualization uchun
        arView.automaticallyUpdatesLighting = true
        view.addSubview(arView)
    }

    private func setupCoaching() {
        coachingOverlay = ARCoachingOverlayView(frame: view.bounds)
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .tracking
        coachingOverlay.activatesAutomatically = true
        view.addSubview(coachingOverlay)
    }

    private func setupOverlay() {
        doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Tugatish", for: .normal)
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneBtn.backgroundColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        doneBtn.layer.cornerRadius = 24
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)

        cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Bekor qilish", for: .normal)
        cancelBtn.setTitleColor(.white, for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cancelBtn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        cancelBtn.layer.cornerRadius = 18
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelBtn)

        statusLabel = UILabel()
        statusLabel.text = "Sekin yurib, xona bo'ylab kameragayni aylantiring (kamida 20 ta foto)"
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 12
        statusLabel.layer.masksToBounds = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            doneBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            doneBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneBtn.widthAnchor.constraint(equalToConstant: 200),
            doneBtn.heightAnchor.constraint(equalToConstant: 48),

            cancelBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelBtn.heightAnchor.constraint(equalToConstant: 36),
            cancelBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),

            statusLabel.bottomAnchor.constraint(equalTo: doneBtn.topAnchor, constant: -16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func setupProcessingOverlay() {
        processingOverlay = UIView()
        processingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        processingOverlay.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.isHidden = true
        view.addSubview(processingOverlay)

        processingLabel = UILabel()
        processingLabel.text = "3D model yaratilmoqda…"
        processingLabel.textColor = .white
        processingLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        processingLabel.textAlignment = .center
        processingLabel.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(processingLabel)

        let infoLabel = UILabel()
        infoLabel.text = "Bu 3-8 daqiqa olishi mumkin, \nilovani yopmang."
        infoLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        infoLabel.font = .systemFont(ofSize: 13, weight: .regular)
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(infoLabel)

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.2)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(progressView)

        processingStatusLabel = UILabel()
        processingStatusLabel.text = "Tayyorlanmoqda…"
        processingStatusLabel.textColor = .white
        processingStatusLabel.font = .systemFont(ofSize: 14, weight: .regular)
        processingStatusLabel.textAlignment = .center
        processingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(processingStatusLabel)

        NSLayoutConstraint.activate([
            processingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            processingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            processingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            processingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            processingLabel.centerXAnchor.constraint(equalTo: processingOverlay.centerXAnchor),
            processingLabel.centerYAnchor.constraint(equalTo: processingOverlay.centerYAnchor, constant: -50),

            infoLabel.topAnchor.constraint(equalTo: processingLabel.bottomAnchor, constant: 8),
            infoLabel.centerXAnchor.constraint(equalTo: processingOverlay.centerXAnchor),
            infoLabel.leadingAnchor.constraint(greaterThanOrEqualTo: processingOverlay.leadingAnchor, constant: 24),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: processingOverlay.trailingAnchor, constant: -24),

            progressView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 32),
            progressView.leadingAnchor.constraint(equalTo: processingOverlay.leadingAnchor, constant: 48),
            progressView.trailingAnchor.constraint(equalTo: processingOverlay.trailingAnchor, constant: -48),
            progressView.heightAnchor.constraint(equalToConstant: 4),

            processingStatusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            processingStatusLabel.centerXAnchor.constraint(equalTo: processingOverlay.centerXAnchor),
        ])
    }

    private func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        // Ko'proq detail uchun yuqori sifatli video format.
        if let bestFormat = ARWorldTrackingConfiguration.supportedVideoFormats
            .max(by: { $0.imageResolution.width < $1.imageResolution.width }) {
            config.videoFormat = bestFormat
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if #available(iOS 14.0, *) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if isProcessing { return }
        guard case .normal = frame.camera.trackingState else { return }
        if captureCount >= maxAllowedPhotos { return }

        let now = frame.timestamp
        if now - lastCaptureTime < minTimeBetweenCaptures { return }

        let pos = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z,
        )
        let rot3x3 = simd_float3x3(
            SIMD3<Float>(frame.camera.transform.columns.0.x, frame.camera.transform.columns.0.y, frame.camera.transform.columns.0.z),
            SIMD3<Float>(frame.camera.transform.columns.1.x, frame.camera.transform.columns.1.y, frame.camera.transform.columns.1.z),
            SIMD3<Float>(frame.camera.transform.columns.2.x, frame.camera.transform.columns.2.y, frame.camera.transform.columns.2.z),
        )
        let rot = simd_quatf(rot3x3)

        var shouldCapture = false
        if let lastPos = lastCapturePos, let lastRot = lastCaptureRot {
            let posDelta = simd_distance(pos, lastPos)
            let dotQ = abs(simd_dot(lastRot.vector, rot.vector))
            let rotDelta = 2 * acos(min(1, dotQ))
            shouldCapture = (posDelta > minPositionDelta || rotDelta > minRotationDelta)
        } else {
            shouldCapture = true
        }

        if shouldCapture {
            capturePhoto(frame)
            lastCapturePos = pos
            lastCaptureRot = rot
            lastCaptureTime = now
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        if !isProcessing {
            onError?(error)
        }
    }

    // MARK: - Photo capture

    private func capturePhoto(_ frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        guard let cgImage = makeCGImage(from: pixelBuffer) else { return }

        let idx = captureCount
        let url = photoFolder.appendingPathComponent(
            String(format: "photo_%04d.jpg", idx),
        )

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { return }

        let opts: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ]
        CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
        let ok = CGImageDestinationFinalize(dest)
        if !ok { return }

        // LiDAR depth ma'lumotini saqlash — photogrammetry sifatini keskin oshiradi.
        if let depth = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap {
            saveDepthMap(depth, idx: idx)
        }

        // Gravity vektori (kamera koordinatalarida) — to'g'ri orientatsiya uchun.
        saveGravity(camera: frame.camera, idx: idx)

        captureCount += 1
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.captureCount < self.minRequiredPhotos {
                self.statusLabel.text = "Foto: \(self.captureCount) / \(self.minRequiredPhotos) (kamida)"
            } else {
                self.statusLabel.text = "Foto: \(self.captureCount) — Tugatishni bosing yoki davom eting"
            }
        }
    }

    /// LiDAR depth map'ni binary fayl sifatida saqlaydi.
    /// Format: [Int32 width][Int32 height][Float32 raw pixels...]
    private func saveDepthMap(_ pixelBuffer: CVPixelBuffer, idx: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let totalBytes = bytesPerRow * height

        var header = Data()
        var w = Int32(width).littleEndian
        var h = Int32(height).littleEndian
        withUnsafeBytes(of: &w) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { header.append(contentsOf: $0) }

        let body = Data(bytes: baseAddress, count: totalBytes)
        let depthURL = photoFolder.appendingPathComponent(
            String(format: "depth_%04d.bin", idx),
        )
        try? (header + body).write(to: depthURL)
    }

    /// Gravity vektori — kamera koordinatalarida (PhotogrammetrySession kutadi).
    /// World gravity (0, -1, 0) ni kamera basis'iga proyektsiya qilamiz.
    private func saveGravity(camera: ARCamera, idx: Int) {
        let g = SIMD3<Float>(
            -camera.transform.columns.0.y,
            -camera.transform.columns.1.y,
            -camera.transform.columns.2.y,
        )
        let json = "[\(g.x),\(g.y),\(g.z)]"
        let url = photoFolder.appendingPathComponent(
            String(format: "gravity_%04d.json", idx),
        )
        try? json.data(using: .utf8)?.write(to: url)
    }

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        if isProcessing { return }
        if captureCount < minRequiredPhotos {
            let alert = UIAlertController(
                title: "Yetarli foto yo'q",
                message: "Kamida \(minRequiredPhotos) ta foto kerak. Hozir: \(captureCount)",
                preferredStyle: .alert,
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        startProcessing()
    }

    @objc private func cancelTapped() {
        if isProcessing {
            processingTask?.cancel()
        }
        cleanupTempFolder()
        onCancel?()
    }

    private func cleanupTempFolder() {
        try? FileManager.default.removeItem(at: photoFolder)
    }

    // MARK: - Processing

    private func startProcessing() {
        isProcessing = true
        arView.session.pause()
        processingOverlay.isHidden = false
        progressView.progress = 0
        processingStatusLabel.text = "Boshlanmoqda…"

        let folder = photoFolder!
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask,
        ).first!
        let scansFolder = docs.appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: scansFolder,
            withIntermediateDirectories: true,
        )
        let outputURL = scansFolder.appendingPathComponent("\(UUID().uuidString).usdz")

        processingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                try await self.runPhotogrammetry(input: folder, output: outputURL)
                let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                let fileSize = (attrs?[.size] as? Int) ?? 0
                await MainActor.run {
                    self.cleanupTempFolder()
                    self.onFinished?(outputURL, TexturedScanStats(
                        floorAreaSqm: 0,
                        vertexCount: 0,
                        faceCount: fileSize,
                    ))
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.cleanupTempFolder()
                    self.onError?(error)
                }
            }
        }
    }

    private func runPhotogrammetry(input: URL, output: URL) async throws {
        // Lazy Sequence orqali har bir rasmga LiDAR depth + gravity ilova
        // qilamiz. Bu Polycam'dagidek aniqlik beradi (mesh fragmentatsiyasini
        // keskin kamaytiradi). Memory bounded — bir vaqtda 1 sample yuklanadi.
        let lazySamples = LazyPhotogrammetrySamples(
            folder: input,
            count: self.captureCount,
        )

        var configuration = PhotogrammetrySession.Configuration()
        configuration.featureSensitivity = .high
        configuration.sampleOrdering = .sequential

        let session = try PhotogrammetrySession(
            input: lazySamples,
            configuration: configuration,
        )

        // iPhone'da faqat .preview va .reduced mavjud (Apple cheklovi).
        // .reduced — yaxshiroq sifat, .preview — tezroq.
        let request = PhotogrammetrySession.Request.modelFile(
            url: output,
            detail: .reduced,
        )
        try session.process(requests: [request])

        for try await output in session.outputs {
            switch output {
            case .processingComplete:
                return
            case .requestComplete:
                return
            case .requestProgress(_, let fractionComplete):
                await MainActor.run {
                    self.progressView.setProgress(Float(fractionComplete), animated: true)
                    let pct = Int(fractionComplete * 100)
                    self.processingStatusLabel.text = "Qayta ishlash: \(pct)%"
                }
            case .requestError(_, let error):
                throw error
            case .processingCancelled:
                throw NSError(
                    domain: "Photogrammetry",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Bekor qilindi"],
                )
            case .inputComplete:
                await MainActor.run {
                    self.processingStatusLabel.text = "Modelni qurish..."
                }
            case .invalidSample(_, let reason):
                // Yagona namuna noto'g'ri — davom etamiz.
                print("Invalid sample: \(reason)")
            case .skippedSample(_):
                continue
            case .automaticDownsampling:
                continue
            case .stitchingIncomplete:
                continue
            @unknown default:
                continue
            }
        }
    }

    // MARK: - ARSCNViewDelegate (real-time LiDAR mesh visualization)

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        let geometry = SCNGeometry.fromARMesh(meshAnchor.geometry)
        geometry.materials = [Self.meshMaterial()]
        node.geometry = geometry
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        let geometry = SCNGeometry.fromARMesh(meshAnchor.geometry)
        geometry.materials = [Self.meshMaterial()]
        node.geometry = geometry
    }

    private static func meshMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor.white.withAlphaComponent(0.55)
        m.isDoubleSided = true
        m.lightingModel = .constant
        m.writesToDepthBuffer = true
        return m
    }

    // MARK: - Sample loading (image + depth + gravity → PhotogrammetrySample)

    fileprivate static func makeSample(folder: URL, idx: Int) -> PhotogrammetrySample? {
        let imageURL = folder.appendingPathComponent(String(format: "photo_%04d.jpg", idx))
        guard let pixelBuffer = loadPixelBuffer(from: imageURL) else { return nil }

        var sample = PhotogrammetrySample(id: idx, image: pixelBuffer)

        let depthURL = folder.appendingPathComponent(String(format: "depth_%04d.bin", idx))
        if let depthMap = loadDepthMap(from: depthURL) {
            sample.depthDataMap = depthMap
        }

        let gravityURL = folder.appendingPathComponent(String(format: "gravity_%04d.json", idx))
        if let g = loadGravity(from: gravityURL) {
            sample.gravity = CMAcceleration(x: Double(g.x), y: Double(g.y), z: Double(g.z))
        }

        return sample
    }

    /// JPEG → CVPixelBuffer (BGRA). PhotogrammetrySample CVPixelBuffer kutadi.
    private static func loadPixelBuffer(from url: URL) -> CVPixelBuffer? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer,
        )
        guard status == kCVReturnSuccess, let buf = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue,
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buf
    }

    private static func loadDepthMap(from url: URL) -> CVPixelBuffer? {
        guard let data = try? Data(contentsOf: url), data.count >= 8 else { return nil }

        let width = Int(data.withUnsafeBytes { ptr in
            Int32(littleEndian: ptr.load(fromByteOffset: 0, as: Int32.self))
        })
        let height = Int(data.withUnsafeBytes { ptr in
            Int32(littleEndian: ptr.load(fromByteOffset: 4, as: Int32.self))
        })
        guard width > 0, height > 0 else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            attrs as CFDictionary,
            &pixelBuffer,
        )
        guard status == kCVReturnSuccess, let buf = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let dest = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buf)
        let totalBytes = bytesPerRow * height
        let payloadBytes = data.count - 8
        let copyBytes = min(totalBytes, payloadBytes)

        data.withUnsafeBytes { srcBuffer in
            guard let src = srcBuffer.baseAddress else { return }
            memcpy(dest, src.advanced(by: 8), copyBytes)
        }
        return buf
    }

    private static func loadGravity(from url: URL) -> SIMD3<Float>? {
        guard let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = str.trimmingCharacters(in: CharacterSet(charactersIn: "[] \n\r\t"))
        let parts = trimmed.split(separator: ",")
            .compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3 else { return nil }
        return SIMD3<Float>(parts[0], parts[1], parts[2])
    }
}


// ────────────────────────────────────────────────────────────────────────
// ARMeshGeometry → SCNGeometry conversion utility.
// ────────────────────────────────────────────────────────────────────────

@available(iOS 13.4, *)
extension SCNGeometry {
    static func fromARMesh(_ mesh: ARMeshGeometry) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(
            buffer: mesh.vertices.buffer,
            vertexFormat: mesh.vertices.format,
            semantic: .vertex,
            vertexCount: mesh.vertices.count,
            dataOffset: mesh.vertices.offset,
            dataStride: mesh.vertices.stride,
        )

        let faces = mesh.faces
        let byteCount = faces.count * faces.indexCountPerPrimitive * faces.bytesPerIndex
        let indexData = Data(
            bytesNoCopy: faces.buffer.contents(),
            count: byteCount,
            deallocator: .none,
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex,
        )

        return SCNGeometry(sources: [vertexSource], elements: [element])
    }
}


// ────────────────────────────────────────────────────────────────────────
// Lazy Sequence — diskdan birma-bir sample yuklaydi (memory bounded).
// PhotogrammetrySession.init(input:configuration:) Sequence kutadi.
// ────────────────────────────────────────────────────────────────────────

@available(iOS 17.0, *)
fileprivate struct LazyPhotogrammetrySamples: Sequence {
    let folder: URL
    let count: Int

    struct Iterator: IteratorProtocol {
        let folder: URL
        let total: Int
        var idx: Int = 0

        mutating func next() -> PhotogrammetrySample? {
            while idx < total {
                let i = idx
                idx += 1
                if let s = TexturedScanViewController.makeSample(folder: folder, idx: i) {
                    return s
                }
            }
            return nil
        }
    }

    func makeIterator() -> Iterator {
        Iterator(folder: folder, total: count)
    }
}
