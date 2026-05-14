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
import AVFoundation
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


// ────────────────────────────────────────────────────────────────────────
// Textured RoomPlan — RoomPlan + ARKit frame capture, keyin har devorga
// teleyaqin rasm projektsiya qilib textured USDZ chiqaramiz.
//
// Mantiq:
// 1. RoomCaptureSession ishlaydi (foydalanuvchi xona aylanib chiqadi)
// 2. `roomCaptureSession.arSession` orqali ARKit frame'lar parallel
//    olinadi (timer 0.5s, kamera transform + intrinsics + image)
// 3. RoomPlan tugagach — har devor uchun:
//    - Eng ko'p qaragan rasmni topish (dot product wall.normal vs cam.forward)
//    - Devor 4 burchakni 2D rasm koordinatasiga proyeksiya
//    - CIPerspectiveCorrection bilan rasmdan devor maydonini olish (UV texture)
// 4. SCNScene quramiz: floor + walls + textures → USDZ export
// ────────────────────────────────────────────────────────────────────────

@available(iOS 17.0, *)
final class TexturedRoomPlanCoordinator: NSObject {
    static let shared = TexturedRoomPlanCoordinator()

    private weak var presentingController: UIViewController?
    private var pendingResult: FlutterResult?
    private var sessionVC: TexturedRoomPlanViewController?

    func start(from controller: UIViewController, result: @escaping FlutterResult) {
        if pendingResult != nil {
            result(FlutterError(
                code: "ALREADY_SCANNING",
                message: "Boshqa skan jarayoni hali tugamagan",
                details: nil,
            ))
            return
        }
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

        let vc = TexturedRoomPlanViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.onFinished = { [weak self] usdzPath, error, stats in
            self?.handleResult(usdzPath: usdzPath, error: error, stats: stats)
        }
        vc.onCancel = { [weak self] in
            self?.handleCancel()
        }
        self.sessionVC = vc
        controller.present(vc, animated: true, completion: nil)
    }

    private func handleResult(usdzPath: String?, error: Error?, stats: (total: Int, textured: Int)? = nil) {
        let result = pendingResult
        pendingResult = nil
        let vc = sessionVC
        sessionVC = nil
        vc?.dismiss(animated: true) {
            if let err = error {
                result?(FlutterError(
                    code: "TEXTURED_ROOM_FAILED",
                    message: err.localizedDescription,
                    details: nil,
                ))
                return
            }
            guard let path = usdzPath else {
                result?(nil)
                return
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? Int) ?? 0
            result?([
                "filePath": path,
                "fileSize": size,
                "method": "textured_roomplan",
                "wallsTotal": stats?.total ?? 0,
                "wallsTextured": stats?.textured ?? 0,
            ] as [String: Any])
        }
    }

    private func handleCancel() {
        let result = pendingResult
        pendingResult = nil
        sessionVC?.dismiss(animated: true) { [weak self] in
            self?.sessionVC = nil
            result?(nil)
        }
    }
}


/// Frame capture metadata — har frame uchun saqlanadi.
@available(iOS 17.0, *)
fileprivate struct CapturedFrameMeta {
    let imageURL: URL
    let cameraTransform: simd_float4x4
    let intrinsics: simd_float3x3
    let imageWidth: Int
    let imageHeight: Int
    let timestamp: TimeInterval
}


@available(iOS 17.0, *)
final class TexturedRoomPlanViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {

    var onFinished: ((String?, Error?, (total: Int, textured: Int)?) -> Void)?
    var onCancel: (() -> Void)?

    private var roomCaptureView: RoomCaptureView!
    private var captureSessionConfig = RoomCaptureSession.Configuration()
    private var finalResults: CapturedRoom?

    // Frame capture
    private var frameTimer: Timer?
    private var captureFolder: URL!
    private var frames: [CapturedFrameMeta] = []
    private var lastFrameTimestamp: TimeInterval = 0
    private let minFrameInterval: TimeInterval = 0.4

    // Processing UI
    private var processingOverlay: UIView!
    private var processingLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // Capture folder
        let tmp = FileManager.default.temporaryDirectory
        captureFolder = tmp.appendingPathComponent(
            "textured_roomplan_\(UUID().uuidString)",
            isDirectory: true,
        )
        try? FileManager.default.createDirectory(
            at: captureFolder, withIntermediateDirectories: true,
        )

        setupRoomCaptureView()
        setupButtons()
        setupProcessingOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        roomCaptureView.captureSession.run(configuration: captureSessionConfig)
        // ARKit frame capture timer'ni start qilamiz (RoomPlan ARSession'i ulushi).
        startFrameCapture()
    }

    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        stopFrameCapture()
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
        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Tugatish", for: .normal)
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneBtn.backgroundColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        doneBtn.layer.cornerRadius = 24
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)

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

    private func setupProcessingOverlay() {
        processingOverlay = UIView()
        processingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        processingOverlay.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.isHidden = true
        view.addSubview(processingOverlay)

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(spinner)

        processingLabel = UILabel()
        processingLabel.textColor = .white
        processingLabel.numberOfLines = 0
        processingLabel.textAlignment = .center
        processingLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        processingLabel.text = "Tekstura proyeksiyalanmoqda..."
        processingLabel.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(processingLabel)

        NSLayoutConstraint.activate([
            processingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            processingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            processingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            processingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            spinner.centerXAnchor.constraint(equalTo: processingOverlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: processingOverlay.centerYAnchor, constant: -30),

            processingLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            processingLabel.leadingAnchor.constraint(equalTo: processingOverlay.leadingAnchor, constant: 32),
            processingLabel.trailingAnchor.constraint(equalTo: processingOverlay.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Frame capture

    private func startFrameCapture() {
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.captureCurrentFrame()
        }
    }

    private func stopFrameCapture() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    private func captureCurrentFrame() {
        let arSession = roomCaptureView.captureSession.arSession
        guard let frame = arSession.currentFrame else { return }

        // Throttle — minFrameInterval kechikishni tekshiramiz
        if frame.timestamp - lastFrameTimestamp < minFrameInterval {
            return
        }
        // Tracking yaxshi bo'lsa-gina saqlaymiz
        guard case .normal = frame.camera.trackingState else { return }
        lastFrameTimestamp = frame.timestamp

        // Pixel buffer → JPEG
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpeg = uiImage.jpegData(compressionQuality: 0.85) else { return }

        let idx = frames.count
        let imageURL = captureFolder.appendingPathComponent("frame_\(String(format: "%04d", idx)).jpg")
        do {
            try jpeg.write(to: imageURL)
        } catch {
            return
        }

        let meta = CapturedFrameMeta(
            imageURL: imageURL,
            cameraTransform: frame.camera.transform,
            intrinsics: frame.camera.intrinsics,
            imageWidth: Int(ciImage.extent.width),
            imageHeight: Int(ciImage.extent.height),
            timestamp: frame.timestamp,
        )
        frames.append(meta)
    }

    // MARK: - Buttons

    @objc private func doneTapped() {
        // RoomPlan'ni to'xtatamiz, finalResults kelganda processing boshlaymiz.
        if #available(iOS 17, *) {
            roomCaptureView.captureSession.stop(pauseARSession: false)
        } else {
            roomCaptureView.captureSession.stop()
        }
        stopFrameCapture()
    }

    @objc private func cancelTapped() {
        stopFrameCapture()
        cleanupTempFolder()
        onCancel?()
    }

    private func cleanupTempFolder() {
        try? FileManager.default.removeItem(at: captureFolder)
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResults = processedResult
        if let err = error {
            cleanupTempFolder()
            onFinished?(nil, err, nil)
            return
        }
        // Processing UI'ni ko'rsatib, texture projektsiyani boshlaymiz.
        processingOverlay.isHidden = false
        processingLabel.text = "Tekstura proyeksiyalanmoqda...\n(\(frames.count) ta rasm, \(processedResult.walls.count) ta devor)"

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                let usdzURL = try await self.processAndExportUSDZ(
                    capturedRoom: processedResult,
                    frames: self.frames,
                )
                let stats = await self.lastStats
                await MainActor.run {
                    self.cleanupTempFolder()
                    self.onFinished?(
                        usdzURL.path, nil,
                        (total: stats.wallsTotal, textured: stats.wallsTextured),
                    )
                }
            } catch {
                await MainActor.run {
                    self.cleanupTempFolder()
                    self.onFinished?(nil, error, nil)
                }
            }
        }
    }

    // MARK: - Texture projection + USDZ export
    // Phase 2-3 keyingi commit'da

    /// Yakuniy hisobot — qaysi devorlar texturalandi.
    private struct ProjectionStats {
        var wallsTotal: Int = 0
        var wallsTextured: Int = 0
    }

    private var lastStats = ProjectionStats()

    private func processAndExportUSDZ(
        capturedRoom: CapturedRoom,
        frames: [CapturedFrameMeta],
    ) async throws -> URL {
        // Output USDZ
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let scansFolder = docs.appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: scansFolder, withIntermediateDirectories: true)
        let outputURL = scansFolder.appendingPathComponent("textured_room_\(UUID().uuidString).usdz")

        let scene = SCNScene()
        var stats = ProjectionStats()

        // Floor — texturasiz, kulrang
        for floor in capturedRoom.floors {
            let plane = SCNPlane(
                width: CGFloat(floor.dimensions.x),
                height: CGFloat(floor.dimensions.z),
            )
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(white: 0.92, alpha: 1.0)
            m.isDoubleSided = true
            plane.firstMaterial = m
            let node = SCNNode(geometry: plane)
            node.simdTransform = floor.transform
            scene.rootNode.addChildNode(node)
        }

        // Devorlar — har biri uchun texture topishga harakat
        for wall in capturedRoom.walls {
            stats.wallsTotal += 1
            let textured = projectTextureForWall(wall: wall, frames: frames)
            if textured != nil {
                stats.wallsTextured += 1
            }

            let plane = SCNPlane(
                width: CGFloat(wall.dimensions.x),
                height: CGFloat(wall.dimensions.y),
            )
            let m = SCNMaterial()
            // Tekstura topilmagan devorlarni och qizil-pushti rangda chiqaramiz
            // foydalanuvchi "bu yer rasmga olinmadi" deb darhol tushunsin.
            m.diffuse.contents = textured ?? UIColor(red: 1.0, green: 0.78, blue: 0.78, alpha: 1.0)
            m.isDoubleSided = true
            plane.firstMaterial = m
            let node = SCNNode(geometry: plane)
            node.simdTransform = wall.transform
            scene.rootNode.addChildNode(node)
        }

        lastStats = stats

        let success = scene.write(to: outputURL, options: nil, delegate: nil, progressHandler: nil)
        if !success {
            throw NSError(domain: "TexturedRoom", code: 1, userInfo: [NSLocalizedDescriptionKey: "USDZ yozib bo'lmadi"])
        }
        return outputURL
    }

    /// Devor uchun eng yaxshi rasmni topib, tekstura yaratish.
    /// Yumshoqroq mezonlar — ishonchliroq natija.
    private func projectTextureForWall(
        wall: CapturedRoom.Surface,
        frames: [CapturedFrameMeta],
    ) -> UIImage? {
        let transform = wall.transform
        let dimensions = wall.dimensions

        // Plane normal — local Z+ → world
        let worldNormal = simd_normalize(simd_make_float3(
            transform * simd_float4(0, 0, 1, 0),
        ))
        let planeCenter = simd_make_float3(transform.columns.3)

        // 4 burchak local space'da (X=width, Y=height plane)
        let halfW = dimensions.x * 0.5
        let halfH = dimensions.y * 0.5
        let localCorners: [simd_float4] = [
            simd_float4(-halfW, -halfH, 0, 1),  // BL
            simd_float4( halfW, -halfH, 0, 1),  // BR
            simd_float4( halfW,  halfH, 0, 1),  // TR
            simd_float4(-halfW,  halfH, 0, 1),  // TL
        ]
        let worldCorners = localCorners.map { transform * $0 }

        // Eng yaxshi frame'ni topish — yumshoqroq mezonlar
        var bestFrame: CapturedFrameMeta? = nil
        var bestScore: Float = 0

        for f in frames {
            let camForward = simd_normalize(simd_make_float3(
                f.cameraTransform * simd_float4(0, 0, -1, 0),
            ))
            // RoomPlan'ning normal yo'nalishi qaysi tomonga ekanini bilmaymiz —
            // shu sababli abs() ishlatamiz. Kamera ham ichkaridan ham
            // tashqaridan qarashi mumkin.
            let dot = abs(simd_dot(camForward, worldNormal))
            if dot < 0.30 { continue }  // ~70° gacha qabul

            let camPos = simd_make_float3(f.cameraTransform.columns.3)
            let dist = simd_distance(camPos, planeCenter)
            if dist > 8.0 { continue }  // 8 m gacha qabul (oldin 5 edi)

            // Hech bo'lmaganda 1 ta corner rasmda ko'rinishi shart
            var anyInBounds = false
            for c in worldCorners {
                let p = projectWorldPointToImage(
                    worldPoint: simd_make_float3(c),
                    cameraTransform: f.cameraTransform,
                    intrinsics: f.intrinsics,
                )
                if p.x >= 0 && p.x <= Float(f.imageWidth) &&
                   p.y >= 0 && p.y <= Float(f.imageHeight) {
                    anyInBounds = true
                    break
                }
            }
            if !anyInBounds { continue }

            let score = dot / max(dist, 0.5)
            if score > bestScore {
                bestScore = score
                bestFrame = f
            }
        }

        guard let frame = bestFrame else { return nil }

        // 4 burchakni rasmda topib, perspektiv warp orqali devor texturasi
        let imagePoints = worldCorners.map { c in
            projectWorldPointToImage(
                worldPoint: simd_make_float3(c),
                cameraTransform: frame.cameraTransform,
                intrinsics: frame.intrinsics,
            )
        }

        // Eng yomon (clamping bilan ham bo'lsa) warp ishlasin
        let clampedPoints = imagePoints.map { p -> simd_float2 in
            simd_float2(
                max(0, min(Float(frame.imageWidth - 1), p.x)),
                max(0, min(Float(frame.imageHeight - 1), p.y)),
            )
        }

        return perspectiveWarp(
            imageURL: frame.imageURL,
            imageWidth: frame.imageWidth,
            imageHeight: frame.imageHeight,
            corners: clampedPoints,
        )
    }

    /// 3D world point'ni kamera koordinata fazasi orqali 2D image koordinatga
    /// proyeksiyalash. ARKit camera matrix'i ishlatiladi.
    private func projectWorldPointToImage(
        worldPoint: simd_float3,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
    ) -> simd_float2 {
        // World → camera (camera_T_world = inverse(world_T_camera))
        let worldT = cameraTransform.inverse
        let camPoint4 = worldT * simd_float4(worldPoint, 1)
        // ARKit kamera Z- old tomonga qaragan, biz `-z` ni ishlatamiz
        let cx = camPoint4.x
        let cy = -camPoint4.y  // ARKit: Y up, image: Y down
        let cz = -camPoint4.z
        if cz <= 0.001 {
            return simd_float2(-1, -1)
        }
        // Pinhole projection
        let px = (intrinsics[0][0] * cx + intrinsics[2][0] * cz) / cz
        let py = (intrinsics[1][1] * cy + intrinsics[2][1] * cz) / cz
        return simd_float2(px, py)
    }

    /// CIPerspectiveCorrection orqali rasmdan to'rtburchak maydonni kesib
    /// olib, to'g'ri rectangle'ga aylantiradi.
    private func perspectiveWarp(
        imageURL: URL,
        imageWidth: Int,
        imageHeight: Int,
        corners: [simd_float2],  // BL, BR, TR, TL
    ) -> UIImage? {
        guard corners.count == 4 else { return nil }
        guard let inputImage = CIImage(contentsOf: imageURL) else { return nil }

        // CoreImage'da Y koordinata teskari (bottom-up). Bizning corners'larda
        // image space (top-down) — convert qilish kerak.
        let h = Float(imageHeight)
        func toCI(_ p: simd_float2) -> CIVector {
            return CIVector(x: CGFloat(p.x), y: CGFloat(h - p.y))
        }

        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(toCI(corners[0]), forKey: "inputBottomLeft")
        filter.setValue(toCI(corners[1]), forKey: "inputBottomRight")
        filter.setValue(toCI(corners[2]), forKey: "inputTopRight")
        filter.setValue(toCI(corners[3]), forKey: "inputTopLeft")
        guard let output = filter.outputImage else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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

    /// Hybrid upload mode — Done bossa, lokal PhotogrammetrySession ishga
    /// tushmaydi. O'rniga `onPhotosReady` chaqiriladi va foto'lar papkasi
    /// uzatiladi (server'ga upload qilish uchun).
    var uploadMode: Bool = false
    /// `quality` string: "fast" | "standard" | "high" — server'ga uzatiladi.
    var onPhotosReady: ((URL, Int, String) -> Void)?
    /// Upload mode'da ko'proq foto kerak (server-side processing — sifatga
    /// ta'sir qiladi). Default 500 — server-side max'ga teng.
    var uploadModeMaxPhotos: Int = 500


    // UI elementlari
    private var arView: ARSCNView!
    private var coachingOverlay: ARCoachingOverlayView!
    private var statusLabel: UILabel!
    private var doneBtn: UIButton!
    private var cancelBtn: UIButton!
    private var pauseBtn: UIButton!
    private var flashlightBtn: UIButton!
    private var trackingLostBanner: UILabel!
    private var pauseOverlay: UIView!  // ko'k tint paused state'da
    private var pauseMessageLabel: UILabel!
    private var startOverBtn: UIButton!
    private var isPaused: Bool = false
    private var isFlashlightOn: Bool = false
    // Polycam-style overlays
    private var areaPill: UILabel!         // "est X m²" yuqori chapda
    private var photoPill: UILabel!        // "Foto: N" yuqori o'ngda
    private var speedWarning: UILabel!     // "Sekinlash!" markazda
    // Processing UI
    private var processingOverlay: UIView!
    private var processingLabel: UILabel!
    private var progressView: UIProgressView!
    private var processingStatusLabel: UILabel!

    // Real-time scan metrics
    private var totalMeshAreaM2: Float = 0
    private var meshAreaByAnchor: [UUID: Float] = [:]
    /// Anchor birinchi marta ko'rilgandan keyin shuncha sekund o'tgach geometry
    /// yangilanishi to'xtaydi — ARKit drift'i visualizatsiyani buzmasligi uchun.
    /// Foto capture davom etadi, lekin ko'rgan mesh barqaror qoladi.
    private var lastFramePos: SIMD3<Float>?
    private var lastFrameTime: TimeInterval = 0
    private var lastSpeedSamples: [Float] = []  // moving avg, m/s
    private let maxSafeSpeedMps: Float = 0.5    // > 0.5 m/s → tez ketyapsiz

    // Haptic feedback — Polycam style "tick" on each photo capture.
    private let captureHaptic = UIImpactFeedbackGenerator(style: .light)

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

    /// ARKit dan har frame uchun camera pose + intrinsics. Capture tugagach
    /// `poses.json` ga yoziladi va serverga foto'lar bilan birga yuboriladi.
    /// AWS GPU pipeline bu pose'lardan COLMAP SfM bosqichini o'tkazib yuborish
    /// uchun foydalanadi (~25 daq tejaladi va past sifatli foto'larda ham
    /// ishonchli ishlaydi).
    private var capturedPoses: [[String: Any]] = []

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
        captureHaptic.prepare()  // pre-warm so first tick has no latency
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
        addBlueOverlayPlane()
    }

    /// Kameraga ulangan ko'k yarim shaffof plane — ekran bo'yicha skanlanmagan
    /// joylarni belgilash uchun. Mesh oldida ko'rinmaydi (depth bufferdan
    /// foydalanadi), shuning uchun capture qilingan joylar rangli mesh bilan
    /// "ochiladi", qolgani ko'k tint ostida kamera.
    private var blueOverlayAdded = false
    private func addBlueOverlayPlane() {
        if blueOverlayAdded { return }
        guard let cam = arView.pointOfView else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.addBlueOverlayPlane()
            }
            return
        }
        blueOverlayAdded = true
        let plane = SCNPlane(width: 200, height: 200)
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = UIColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 0.5)
        mat.writesToDepthBuffer = false  // mesh keyin renderda joyini yopib qolsin
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, 0, -10)  // kameradan oldinda
        node.renderingOrder = -100               // boshqalardan oldin chiziladi
        cam.addChildNode(node)
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
        // Polycam-style: katta dumaloq Pause/Resume tugmasi markaz-pastda
        pauseBtn = UIButton(type: .system)
        pauseBtn.tintColor = .white
        let pauseImage = UIImage(systemName: "pause.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .bold))
        pauseBtn.setImage(pauseImage, for: .normal)
        pauseBtn.backgroundColor = UIColor.clear
        pauseBtn.layer.borderWidth = 3
        pauseBtn.layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
        pauseBtn.layer.cornerRadius = 36
        pauseBtn.translatesAutoresizingMaskIntoConstraints = false
        pauseBtn.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        view.addSubview(pauseBtn)

        // Done — o'ng tomonda, Polycam style oval check tugmasi
        doneBtn = UIButton(type: .system)
        doneBtn.setTitle("  Done", for: .normal)
        doneBtn.setImage(UIImage(systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
        doneBtn.tintColor = .white
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        doneBtn.backgroundColor = UIColor.clear
        doneBtn.layer.borderWidth = 1.5
        doneBtn.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        doneBtn.layer.cornerRadius = 24
        doneBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 22)
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)

        // X close (cancelBtn) — top right (Polycam)
        cancelBtn = UIButton(type: .system)
        cancelBtn.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
        cancelBtn.tintColor = .white
        cancelBtn.backgroundColor = UIColor.clear
        cancelBtn.layer.borderWidth = 1.5
        cancelBtn.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        cancelBtn.layer.cornerRadius = 18
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelBtn)

        // Flashlight toggle — o'ng yon (Polycam)
        flashlightBtn = UIButton(type: .system)
        flashlightBtn.setImage(UIImage(systemName: "flashlight.off.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        flashlightBtn.tintColor = .white
        flashlightBtn.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        flashlightBtn.layer.cornerRadius = 22
        flashlightBtn.translatesAutoresizingMaskIntoConstraints = false
        flashlightBtn.addTarget(self, action: #selector(flashlightTapped), for: .touchUpInside)
        view.addSubview(flashlightBtn)

        // Tracking lost banner — Polycam style oq pill markaz-pastda
        trackingLostBanner = UILabel()
        trackingLostBanner.text = "Session tracking lost, trying to relocalize"
        trackingLostBanner.textColor = .black
        trackingLostBanner.textAlignment = .center
        trackingLostBanner.font = .systemFont(ofSize: 14, weight: .medium)
        trackingLostBanner.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        trackingLostBanner.layer.cornerRadius = 12
        trackingLostBanner.layer.masksToBounds = true
        trackingLostBanner.translatesAutoresizingMaskIntoConstraints = false
        trackingLostBanner.isHidden = true
        view.addSubview(trackingLostBanner)

        statusLabel = UILabel()
        statusLabel.text = ""
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.backgroundColor = .clear
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Area pill — Polycam style "est N m²" top-left
        areaPill = UILabel()
        areaPill.text = "est 0 m²"
        areaPill.textColor = .black
        areaPill.font = .systemFont(ofSize: 14, weight: .semibold)
        areaPill.textAlignment = .center
        areaPill.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        areaPill.layer.cornerRadius = 14
        areaPill.layer.masksToBounds = true
        areaPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(areaPill)

        // Photo count pill — top-right
        photoPill = UILabel()
        photoPill.text = "0 foto"
        photoPill.textColor = .white
        photoPill.font = .systemFont(ofSize: 14, weight: .semibold)
        photoPill.textAlignment = .center
        photoPill.backgroundColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        photoPill.layer.cornerRadius = 14
        photoPill.layer.masksToBounds = true
        photoPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(photoPill)

        // Speed warning — center, hidden by default
        speedWarning = UILabel()
        speedWarning.text = "⚠️ Sekinlash — tez harakat blur beradi"
        speedWarning.textColor = .white
        speedWarning.font = .systemFont(ofSize: 15, weight: .bold)
        speedWarning.textAlignment = .center
        speedWarning.numberOfLines = 0
        speedWarning.backgroundColor = UIColor.systemRed.withAlphaComponent(0.92)
        speedWarning.layer.cornerRadius = 12
        speedWarning.layer.masksToBounds = true
        speedWarning.translatesAutoresizingMaskIntoConstraints = false
        speedWarning.alpha = 0
        view.addSubview(speedWarning)

        NSLayoutConstraint.activate([
            // Pause — markaz-pastda katta dumaloq
            pauseBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            pauseBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pauseBtn.widthAnchor.constraint(equalToConstant: 72),
            pauseBtn.heightAnchor.constraint(equalToConstant: 72),

            // Done — o'ng tomonda, pause yonida
            doneBtn.centerYAnchor.constraint(equalTo: pauseBtn.centerYAnchor),
            doneBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            doneBtn.heightAnchor.constraint(equalToConstant: 48),

            // Cancel — top right (X)
            cancelBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            cancelBtn.heightAnchor.constraint(equalToConstant: 36),
            cancelBtn.widthAnchor.constraint(equalToConstant: 36),

            // Flashlight — o'ng yon, ekran o'rtasida
            flashlightBtn.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            flashlightBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flashlightBtn.widthAnchor.constraint(equalToConstant: 44),
            flashlightBtn.heightAnchor.constraint(equalToConstant: 44),

            // Tracking lost banner — markaz-pastda
            trackingLostBanner.bottomAnchor.constraint(equalTo: pauseBtn.topAnchor, constant: -24),
            trackingLostBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            trackingLostBanner.heightAnchor.constraint(equalToConstant: 36),
            trackingLostBanner.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            trackingLostBanner.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            statusLabel.bottomAnchor.constraint(equalTo: pauseBtn.topAnchor, constant: -8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // Area pill — top left (Polycam style)
            areaPill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            areaPill.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            areaPill.heightAnchor.constraint(equalToConstant: 32),
            areaPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),

            // Photo pill — areaPill ostida
            photoPill.topAnchor.constraint(equalTo: areaPill.bottomAnchor, constant: 8),
            photoPill.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            photoPill.heightAnchor.constraint(equalToConstant: 28),
            photoPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),

            speedWarning.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            speedWarning.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -120),
            speedWarning.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            speedWarning.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            speedWarning.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])

        for pill in [areaPill, photoPill] as [UILabel] {
            pill.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
            pill.layer.borderWidth = 0.5
        }

        setupPauseOverlay()
    }

    /// Pause holatida ko'k ramka + "Move iPhone to start" + Start Over tugmasi.
    /// Dastlab yashirilgan, pauseTapped'da ko'rsatiladi.
    private func setupPauseOverlay() {
        pauseOverlay = UIView()
        pauseOverlay.backgroundColor = UIColor(red: 0.05, green: 0.10, blue: 0.30, alpha: 0.55)
        pauseOverlay.translatesAutoresizingMaskIntoConstraints = false
        pauseOverlay.isHidden = true
        view.addSubview(pauseOverlay)

        // "Move iPhone to start" markazda
        pauseMessageLabel = UILabel()
        pauseMessageLabel.text = "iPhone'ni harakatlantiring"
        pauseMessageLabel.textColor = .white
        pauseMessageLabel.font = .systemFont(ofSize: 18, weight: .medium)
        pauseMessageLabel.textAlignment = .center
        pauseMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        pauseOverlay.addSubview(pauseMessageLabel)

        // Start Over tugmasi pause overlay ichida
        startOverBtn = UIButton(type: .system)
        startOverBtn.setTitle("Boshidan boshlash", for: .normal)
        startOverBtn.setTitleColor(.white, for: .normal)
        startOverBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        startOverBtn.backgroundColor = UIColor.clear
        startOverBtn.layer.borderWidth = 1.5
        startOverBtn.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        startOverBtn.layer.cornerRadius = 22
        startOverBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        startOverBtn.translatesAutoresizingMaskIntoConstraints = false
        startOverBtn.addTarget(self, action: #selector(startOverTapped), for: .touchUpInside)
        pauseOverlay.addSubview(startOverBtn)

        NSLayoutConstraint.activate([
            // Pause overlay — pause/done tugmalarini ochiq qoldirgan holda
            // qolgan ekranni qoplaydi.
            pauseOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            pauseOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pauseOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pauseOverlay.bottomAnchor.constraint(equalTo: pauseBtn.topAnchor, constant: -16),

            pauseMessageLabel.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            pauseMessageLabel.centerYAnchor.constraint(equalTo: pauseOverlay.centerYAnchor),

            startOverBtn.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            startOverBtn.topAnchor.constraint(equalTo: pauseMessageLabel.bottomAnchor, constant: 24),
            startOverBtn.heightAnchor.constraint(equalToConstant: 44),
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

    /// MeshReview'dan "Davom etish" bilan qaytganda chaqiriladi. Eski ARMeshAnchor'lar
    /// va captureCount/photoFolder saqlanadi — session'ni reset qilmasdan davom ettiramiz.
    private func resumeARSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
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
        // Bo'sh options — anchor'lar va tracking saqlanadi.
        arView.session.run(config, options: [])
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
        let now = frame.timestamp
        let pos = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z,
        )

        // Speed tracking — moving avg of last ~10 frames so brief jitters don't
        // flash the warning. Above 0.5 m/s capture quality drops fast (motion blur).
        if let last = lastFramePos, lastFrameTime > 0 {
            let dt = Float(max(now - lastFrameTime, 0.001))
            let dPos = simd_distance(pos, last)
            let speed = dPos / dt
            lastSpeedSamples.append(speed)
            if lastSpeedSamples.count > 10 { lastSpeedSamples.removeFirst() }
            let avg = lastSpeedSamples.reduce(0, +) / Float(lastSpeedSamples.count)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let target: CGFloat = avg > self.maxSafeSpeedMps ? 1 : 0
                if abs(self.speedWarning.alpha - target) > 0.01 {
                    UIView.animate(withDuration: 0.2) { self.speedWarning.alpha = target }
                }
            }
        }
        lastFramePos = pos
        lastFrameTime = now

        // Polycam-style tracking lost banner — `.limited(.relocalizing)` yoki
        // `.notAvailable` holatda ko'rsatiladi.
        let trackingOK: Bool
        switch frame.camera.trackingState {
        case .normal:
            trackingOK = true
        case .limited(let reason):
            trackingOK = false
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let msg: String
                switch reason {
                case .relocalizing: msg = "Tracking yo'qoldi, qayta lokallashtirilmoqda"
                case .initializing: msg = "Tracking ishga tushmoqda — iPhone'ni harakatlantiring"
                case .excessiveMotion: msg = "Sekinroq harakatlaning"
                case .insufficientFeatures: msg = "Yorug'roq joyda harakatlaning"
                @unknown default: msg = "Tracking cheklangan"
                }
                self.trackingLostBanner.text = msg
                self.trackingLostBanner.isHidden = false
            }
        case .notAvailable:
            trackingOK = false
            DispatchQueue.main.async { [weak self] in
                self?.trackingLostBanner.text = "Tracking mavjud emas"
                self?.trackingLostBanner.isHidden = false
            }
        }
        if trackingOK {
            DispatchQueue.main.async { [weak self] in
                self?.trackingLostBanner.isHidden = true
            }
        }
        guard trackingOK else { return }

        let limit = uploadMode ? uploadModeMaxPhotos : maxAllowedPhotos
        if captureCount >= limit { return }

        if now - lastCaptureTime < minTimeBetweenCaptures { return }
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

    // MARK: - RoomPlan wireframe helpers (MeshReview uchun static)

    /// Devor/eshik/oyna uchun yassi to'rtburchak chegarasi.
    static func makeWireframeRect(surface: CapturedRoom.Surface, color: UIColor) -> SCNNode {
        let w = CGFloat(surface.dimensions.x)
        let h = CGFloat(surface.dimensions.y)
        let hw = Float(w / 2)
        let hh = Float(h / 2)
        // Rect surface'ning lokal koordinatalarida — Z=0 plane.
        let corners: [SCNVector3] = [
            SCNVector3(-hw, -hh, 0),
            SCNVector3( hw, -hh, 0),
            SCNVector3( hw,  hh, 0),
            SCNVector3(-hw,  hh, 0),
        ]
        let indices: [Int32] = [0,1, 1,2, 2,3, 3,0]
        let geom = makeLineGeometry(vertices: corners, indices: indices, color: color)
        let node = SCNNode(geometry: geom)
        node.simdTransform = surface.transform
        return node
    }

    /// Stol/stul/karavot va boshqa obyektlar uchun 3D bounding box.
    static func makeWireframeBox(object: CapturedRoom.Object, color: UIColor) -> SCNNode {
        let hx = Float(object.dimensions.x / 2)
        let hy = Float(object.dimensions.y / 2)
        let hz = Float(object.dimensions.z / 2)
        let v: [SCNVector3] = [
            SCNVector3(-hx, -hy, -hz), SCNVector3( hx, -hy, -hz),
            SCNVector3( hx,  hy, -hz), SCNVector3(-hx,  hy, -hz),
            SCNVector3(-hx, -hy,  hz), SCNVector3( hx, -hy,  hz),
            SCNVector3( hx,  hy,  hz), SCNVector3(-hx,  hy,  hz),
        ]
        let i: [Int32] = [
            0,1, 1,2, 2,3, 3,0,        // back face
            4,5, 5,6, 6,7, 7,4,        // front face
            0,4, 1,5, 2,6, 3,7,        // connectors
        ]
        let geom = makeLineGeometry(vertices: v, indices: i, color: color)
        let node = SCNNode(geometry: geom)
        node.simdTransform = object.transform
        return node
    }

    static func makeLineGeometry(vertices: [SCNVector3], indices: [Int32], color: UIColor) -> SCNGeometry {
        let src = SCNGeometrySource(vertices: vertices)
        let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let elem = SCNGeometryElement(
            data: data,
            primitiveType: .line,
            primitiveCount: indices.count / 2,
            bytesPerIndex: MemoryLayout<Int32>.size,
        )
        let geom = SCNGeometry(sources: [src], elements: [elem])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = color
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false  // overlay — meshdan oldin chizilsin
        mat.readsFromDepthBuffer = false
        geom.materials = [mat]
        return geom
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

        // ARKit camera pose + intrinsics — AWS GPU pipeline COLMAP'ni o'tkazib
        // yuboradi. Capture tugagach bitta `poses.json` faylga yoziladi.
        recordPose(camera: frame.camera, idx: idx, timestamp: frame.timestamp)

        captureCount += 1
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.captureHaptic.impactOccurred(intensity: 0.55)  // Polycam-style light tick
            self.captureHaptic.prepare()
            self.photoPill.text = "\(self.captureCount) foto"
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

    /// ARKit kamera pose + intrinsics + image resolution'ni xotirada to'playdi.
    /// Capture tugagach `writePosesJson()` chaqiriladi va bitta JSON faylga
    /// dump qilinadi. Format AWS GPU pipeline `pose_relay`'iga mos.
    private func recordPose(camera: ARCamera, idx: Int, timestamp: TimeInterval) {
        // 4x4 transform — ARKit kamerasi koordinatalarida (camera-to-world).
        // Row-major JSON ([4][4]). Server tomondan ARKit→COLMAP konvertatsiyasi
        // qilinadi (Y va Z o'qlarini almashtirib).
        let t = camera.transform
        let transformRows: [[Float]] = [
            [t.columns.0.x, t.columns.1.x, t.columns.2.x, t.columns.3.x],
            [t.columns.0.y, t.columns.1.y, t.columns.2.y, t.columns.3.y],
            [t.columns.0.z, t.columns.1.z, t.columns.2.z, t.columns.3.z],
            [t.columns.0.w, t.columns.1.w, t.columns.2.w, t.columns.3.w],
        ]
        let k = camera.intrinsics
        let intrinsicsRows: [[Float]] = [
            [k.columns.0.x, k.columns.1.x, k.columns.2.x],
            [k.columns.0.y, k.columns.1.y, k.columns.2.y],
            [k.columns.0.z, k.columns.1.z, k.columns.2.z],
        ]
        let resolution = camera.imageResolution
        let entry: [String: Any] = [
            "index": idx,
            "transform_matrix": transformRows,
            "intrinsics": intrinsicsRows,
            "image_width": Int(resolution.width),
            "image_height": Int(resolution.height),
            "timestamp": timestamp,
        ]
        capturedPoses.append(entry)
    }

    /// Yig'ilgan pose'larni `poses.json` ga yozadi. Coordinator'ga uzatishdan
    /// oldin chaqirilishi kerak.
    fileprivate func writePosesJson() {
        guard !capturedPoses.isEmpty else { return }
        let payload: [String: Any] = [
            "version": 1,
            "coordinate_system": "ARKit",
            "device_model": UIDevice.current.model,
            "system_version": UIDevice.current.systemVersion,
            "frame_count": capturedPoses.count,
            "frames": capturedPoses,
        ]
        let url = photoFolder.appendingPathComponent("poses.json")
        do {
            let data = try JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted],
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Pose JSON yozilmasa ham photogrammetry pipeline ishlay oladi
            // (faqat sekinroq COLMAP ishlatadi). Shu sababli warning'gina.
            NSLog("[RoomPlanScanner] poses.json yozilmadi: \(error)")
        }
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
        if uploadMode {
            // Upload mode — lokal processing'ni o'tkazib yuboramiz.
            // photoFolder iPhone tmp ichida, coordinator uni serverga yuklaydi.
            //
            // AR session'ni pause QILMAYMIZ va `.overFullScreen` ishlatamiz —
            // bu orqali ARSCNView ierarxiyada qoladi va mesh node'lari saqlanadi.
            // Foydalanuvchi "Davom etish" bossa, dismiss orqali to'g'ridan-to'g'ri
            // capture'ga qaytadi va eski rangli mesh joyida turadi.
            let meshGeom = MeshSnapshot.combine(arView: arView)
            let review = MeshReviewViewController()
            review.previewGeometry = meshGeom
            review.photoCount = captureCount
            review.areaM2 = totalMeshAreaM2
            review.modalPresentationStyle = .overFullScreen
            review.onConfirm = { [weak self] quality in
                guard let self = self else { return }
                self.arView.session.pause()  // foto capture'ni to'xtatish
                // Pose'larni JSON'ga yozish — coordinator uni multipart bilan
                // foto'lar bilan birga serverga yuklaydi (skip-COLMAP uchun).
                self.writePosesJson()
                self.onPhotosReady?(self.photoFolder, self.captureCount, quality)
            }
            review.onRetake = { [weak self] in
                // User wants to scan again — discard photos, restart session.
                self?.dismiss(animated: true)
                self?.cleanupTempFolder()
                self?.onCancel?()
            }
            review.onContinue = { [weak self] in
                // Hech narsa qilmaymiz — session davom etmoqda, mesh joyida.
                _ = self
            }
            present(review, animated: true)
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

    @objc private func pauseTapped() {
        isPaused.toggle()
        if isPaused {
            arView.session.pause()
            pauseOverlay.isHidden = false
            let symbol = UIImage(systemName: "play.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .bold))
            pauseBtn.setImage(symbol, for: .normal)
        } else {
            // Resume — ARSession qaytadan boshlanadi (relocalize bilan)
            let configuration = ARWorldTrackingConfiguration()
            configuration.sceneReconstruction = .meshWithClassification
            configuration.frameSemantics = .smoothedSceneDepth
            arView.session.run(configuration, options: [])
            pauseOverlay.isHidden = true
            let symbol = UIImage(systemName: "pause.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .bold))
            pauseBtn.setImage(symbol, for: .normal)
        }
        captureHaptic.impactOccurred(intensity: 0.7)
    }

    @objc private func flashlightTapped() {
        isFlashlightOn.toggle()
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = isFlashlightOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            isFlashlightOn = false
            return
        }
        let iconName = isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill"
        flashlightBtn.setImage(UIImage(systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        flashlightBtn.backgroundColor = isFlashlightOn
            ? UIColor.systemYellow.withAlphaComponent(0.85)
            : UIColor.black.withAlphaComponent(0.35)
        flashlightBtn.tintColor = isFlashlightOn ? .black : .white
    }

    @objc private func startOverTapped() {
        // Hozirgi sessiyani tashlab, foto va mesh state'ni boshidan boshlash
        captureCount = 0
        capturedPoses.removeAll()
        meshAreaByAnchor.removeAll()
        totalMeshAreaM2 = 0
        cleanupTempFolder()
        setupPhotoFolder()
        // Mesh anchor'larni tozalash
        arView.scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        // ARSession qayta ishga tushirish (anchor'lar reset)
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        configuration.frameSemantics = .smoothedSceneDepth
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        // Pause overlay yopib, capture'ga qaytamiz
        isPaused = false
        pauseOverlay.isHidden = true
        let symbol = UIImage(systemName: "pause.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .bold))
        pauseBtn.setImage(symbol, for: .normal)
        photoPill.text = "0 foto"
        areaPill.text = "est 0 m²"
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
        updateMeshArea(for: meshAnchor)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        let geometry = SCNGeometry.fromARMesh(meshAnchor.geometry)
        geometry.materials = [Self.meshMaterial()]
        node.geometry = geometry
        updateMeshArea(for: meshAnchor)
    }

    /// Compute approximate horizontal-floor area covered by mesh anchors.
    /// We sum each anchor's projected XZ-plane footprint (faces flagged as
    /// `floor` in ARMeshClassification, otherwise all near-horizontal faces).
    private func updateMeshArea(for meshAnchor: ARMeshAnchor) {
        let area = approxFloorArea(of: meshAnchor)
        meshAreaByAnchor[meshAnchor.identifier] = area
        let total = meshAreaByAnchor.values.reduce(0, +)
        totalMeshAreaM2 = total
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.areaPill.text = "est \(Int(total.rounded())) m²"
        }
    }

    private func approxFloorArea(of anchor: ARMeshAnchor) -> Float {
        let g = anchor.geometry
        let faces = g.faces
        let vertices = g.vertices
        guard faces.bytesPerIndex == 4 || faces.bytesPerIndex == 2 else { return 0 }

        let vBuf = vertices.buffer.contents()
        let fBuf = faces.buffer.contents()
        let stride = vertices.stride

        var total: Float = 0
        let xform = anchor.transform

        for i in 0..<faces.count {
            // 3 indices per triangle face (faces.indexCountPerPrimitive == 3).
            let i0: Int
            let i1: Int
            let i2: Int
            if faces.bytesPerIndex == 4 {
                let p = fBuf.advanced(by: i * 3 * 4).assumingMemoryBound(to: UInt32.self)
                i0 = Int(p[0]); i1 = Int(p[1]); i2 = Int(p[2])
            } else {
                let p = fBuf.advanced(by: i * 3 * 2).assumingMemoryBound(to: UInt16.self)
                i0 = Int(p[0]); i1 = Int(p[1]); i2 = Int(p[2])
            }

            let a = readVertex(vBuf, idx: i0, stride: stride)
            let b = readVertex(vBuf, idx: i1, stride: stride)
            let c = readVertex(vBuf, idx: i2, stride: stride)

            // Transform to world space.
            let aw = xform * SIMD4<Float>(a, 1)
            let bw = xform * SIMD4<Float>(b, 1)
            let cw = xform * SIMD4<Float>(c, 1)

            // Triangle normal.
            let e1 = SIMD3<Float>(bw.x - aw.x, bw.y - aw.y, bw.z - aw.z)
            let e2 = SIMD3<Float>(cw.x - aw.x, cw.y - aw.y, cw.z - aw.z)
            let n = simd_cross(e1, e2)
            let triArea = 0.5 * simd_length(n)

            // Only count near-horizontal faces (|n.y| / |n| > 0.85 ≈ < 30° tilt).
            // This gives a rough floor footprint, similar to Polycam's m² estimate.
            let nLen = simd_length(n)
            if nLen > 1e-6 && abs(n.y) / nLen > 0.85 {
                total += triArea
            }
        }
        return total
    }

    private func readVertex(_ buf: UnsafeMutableRawPointer, idx: Int, stride: Int) -> SIMD3<Float> {
        let p = buf.advanced(by: idx * stride).assumingMemoryBound(to: Float.self)
        return SIMD3<Float>(p[0], p[1], p[2])
    }

    private static func meshMaterial() -> SCNMaterial {
        // Polycam-style: kamera feed ustiga oq wireframe.
        // fillMode = .lines bilan har triangle edge sifatida render bo'ladi.
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.fillMode = .lines
        m.diffuse.contents = UIColor(white: 1.0, alpha: 0.85)
        m.transparency = 0.85
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
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


// ────────────────────────────────────────────────────────────────────────
// Apple Object Capture (iOS 17+) — Polycam-style guided capture.
//
// Apple'ning rasmiy yo'naltirilgan (guided) capture API'si. Custom heuristic
// o'rniga Apple'ning UX'i ishlaydi:
//   - Object detection bounding box
//   - "yaqinroq turing", "shu burchakdan oling" feedback
//   - Avtomatik foto olish (~50-200 foto, qoplama bo'yicha)
//   - PhotogrammetrySession bilan reconstruct qilish (ham iPhone'da .reduced)
//
// `iOS 17.0+` ObjectCaptureSession; ba'zi feedback lar `iOS 18+` da yaxshiroq.
// ────────────────────────────────────────────────────────────────────────

import SwiftUI

@available(iOS 17.0, *)
@MainActor
final class ObjectCaptureCoordinator: NSObject {
    static let shared = ObjectCaptureCoordinator()

    private weak var presentingController: UIViewController?
    private var pendingResult: FlutterResult?
    private var hostingController: UIHostingController<ObjectCaptureContainerView>?
    private var session: ObjectCaptureSession?
    private var captureFolder: URL?
    private var processingTask: Task<Void, Never>?

    func start(from controller: UIViewController, result: @escaping FlutterResult) {
        if pendingResult != nil {
            result(FlutterError(
                code: "ALREADY_SCANNING",
                message: "Boshqa skan jarayoni hali tugamagan",
                details: nil,
            ))
            return
        }

        guard ObjectCaptureSession.isSupported else {
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Bu qurilmada Object Capture qo'llab-quvvatlanmaydi (iPhone Pro / iPad Pro + iOS 17+ kerak)",
                details: nil,
            ))
            return
        }

        // Capture folder — tmp ichida UUID nomli papka. Sample papka.
        let tmp = FileManager.default.temporaryDirectory
        let folder = tmp.appendingPathComponent("oc_\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            result(FlutterError(
                code: "FS_ERROR",
                message: "Capture papkasini yaratib bo'lmadi: \(error)",
                details: nil,
            ))
            return
        }

        let captureSession = ObjectCaptureSession()
        let configuration = ObjectCaptureSession.Configuration()
        captureSession.start(imagesDirectory: folder, configuration: configuration)

        self.captureFolder = folder
        self.session = captureSession
        self.pendingResult = result
        self.presentingController = controller

        let container = ObjectCaptureContainerView(
            session: captureSession,
            onCancel: { [weak self] in
                self?.handleCancel()
            },
            onCaptureComplete: { [weak self] in
                self?.handleCaptureComplete()
            },
        )
        let host = UIHostingController(rootView: container)
        host.modalPresentationStyle = .fullScreen
        self.hostingController = host
        controller.present(host, animated: true, completion: nil)
    }

    private func handleCancel() {
        cleanup()
        DispatchQueue.main.async { [weak self] in
            self?.hostingController?.dismiss(animated: true) {
                let result = self?.pendingResult
                self?.pendingResult = nil
                self?.hostingController = nil
                result?(nil)
            }
        }
    }

    private func handleCaptureComplete() {
        guard let session = session, let folder = captureFolder else {
            handleCancel()
            return
        }

        Task { @MainActor in
            await session.finish()
            self.startReconstruction(imagesFolder: folder)
        }
    }

    @MainActor
    private func startReconstruction(imagesFolder: URL) {
        // Output URL — Documents/scans/.usdz
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

        // SwiftUI'da loading'ga o'tamiz
        if let host = hostingController {
            let processingView = ObjectCaptureProcessingView(onCancel: { [weak self] in
                self?.processingTask?.cancel()
                self?.handleCancel()
            })
            host.rootView = ObjectCaptureContainerView.processing(processingView)
        }

        processingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                let configuration = PhotogrammetrySession.Configuration()
                let pgSession = try PhotogrammetrySession(
                    input: imagesFolder,
                    configuration: configuration,
                )
                let request = PhotogrammetrySession.Request.modelFile(
                    url: outputURL,
                    detail: .reduced,
                )
                try pgSession.process(requests: [request])
                for try await output in pgSession.outputs {
                    if Task.isCancelled { return }
                    switch output {
                    case .processingComplete:
                        await self.finishWithFile(outputURL)
                        return
                    case .requestError(_, let error):
                        await self.failWithError(error)
                        return
                    case .requestComplete:
                        await self.finishWithFile(outputURL)
                        return
                    default:
                        continue
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await self.failWithError(error)
            }
        }
    }

    @MainActor
    private func finishWithFile(_ url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs?[.size] as? Int) ?? 0
        cleanup()
        hostingController?.dismiss(animated: true) { [weak self] in
            let result = self?.pendingResult
            self?.pendingResult = nil
            self?.hostingController = nil
            result?([
                "filePath": url.path,
                "fileSize": fileSize,
                "method": "object_capture",
            ] as [String: Any])
        }
    }

    @MainActor
    private func failWithError(_ error: Error) {
        cleanup()
        hostingController?.dismiss(animated: true) { [weak self] in
            let result = self?.pendingResult
            self?.pendingResult = nil
            self?.hostingController = nil
            result?(FlutterError(
                code: "OBJECT_CAPTURE_FAILED",
                message: "Object Capture xatosi: \(error.localizedDescription)",
                details: nil,
            ))
        }
    }

    private func cleanup() {
        processingTask?.cancel()
        processingTask = nil
        if let folder = captureFolder {
            try? FileManager.default.removeItem(at: folder)
        }
        captureFolder = nil
        session = nil
    }
}


// SwiftUI container — Object Capture session davomida foydalanuvchiga
// turli view'larni ko'rsatadi (detection → capturing → finishing).
//
// `ObjectCaptureSession` `@Observable` (yangi Observation framework) — SwiftUI
// uning property'larini avtomatik tracking qiladi. `@ObservedObject` kerak
// emas; oddiy `let` yetarli.
@available(iOS 17.0, *)
struct ObjectCaptureContainerView: View {
    let session: ObjectCaptureSession
    let onCancel: () -> Void
    let onCaptureComplete: () -> Void

    // Processing state — reconstruction paytida ko'rsatiladi (alohida konstruktor)
    private let processingView: ObjectCaptureProcessingView?

    init(
        session: ObjectCaptureSession,
        onCancel: @escaping () -> Void,
        onCaptureComplete: @escaping () -> Void,
    ) {
        self.session = session
        self.onCancel = onCancel
        self.onCaptureComplete = onCaptureComplete
        self.processingView = nil
    }

    private init(processing: ObjectCaptureProcessingView) {
        // Dummy session — bu konstruktor faqat processing fazasi uchun
        self.session = ObjectCaptureSession()
        self.onCancel = {}
        self.onCaptureComplete = {}
        self.processingView = processing
    }

    static func processing(_ view: ObjectCaptureProcessingView) -> ObjectCaptureContainerView {
        return ObjectCaptureContainerView(processing: view)
    }

    var body: some View {
        if let pv = processingView {
            pv
        } else {
            captureBody
        }
    }

    @ViewBuilder
    private var captureBody: some View {
        ZStack(alignment: .top) {
            ObjectCaptureView(session: session)
                .ignoresSafeArea()

            // Top bar — cancel + state hint
            VStack(spacing: 8) {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.4)))
                    }
                    Spacer()
                    Text(stateLabel)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                    Spacer()
                    Color.clear.frame(width: 28, height: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if let feedback = primaryFeedback {
                    Text(feedback)
                        .font(.callout)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)

            // Bottom bar — primary action
            VStack {
                Spacer()
                primaryActionButton
                    .padding(.bottom, 36)
            }
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch session.state {
        case .ready:
            Button(action: { _ = try? session.startDetecting() }) {
                Label("Obyektni aniqlash", systemImage: "viewfinder")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.green))
            }

        case .detecting:
            Button(action: { session.startCapturing() }) {
                Label("Tasvirlashni boshlash", systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.green))
            }

        case .capturing:
            VStack(spacing: 6) {
                Text("\(session.userCompletedScanPass ? "Pass tugadi" : "Aylanib tasvir oling")")
                    .font(.caption)
                    .foregroundColor(.white)
                Button(action: {
                    if session.userCompletedScanPass {
                        Task { @MainActor in
                            await session.finish()
                            onCaptureComplete()
                        }
                    } else {
                        Task { @MainActor in
                            await session.beginNewScanPass()
                        }
                    }
                }) {
                    Label(
                        session.userCompletedScanPass ? "Yakunlash" : "Keyingi pass",
                        systemImage: session.userCompletedScanPass ? "checkmark" : "arrow.triangle.2.circlepath",
                    )
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.green))
                }
            }

        case .finishing, .completed:
            ProgressView("Yakunlanmoqda...")
                .padding()
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .foregroundColor(.white)

        case .failed(let error):
            VStack(spacing: 8) {
                Text("Xato: \(error.localizedDescription)")
                    .font(.callout)
                    .foregroundColor(.white)
                Button(action: onCancel) {
                    Text("Yopish")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.red))
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.7)))

        @unknown default:
            EmptyView()
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .ready: return "Tayyor"
        case .detecting: return "Aniqlash"
        case .capturing: return "Tasvirlash"
        case .finishing: return "Yakunlanmoqda"
        case .completed: return "Tugadi"
        case .failed: return "Xato"
        @unknown default: return ""
        }
    }

    private var primaryFeedback: String? {
        // Feedback set'idan eng muhim xabarni tanlash
        for fb in session.feedback {
            switch fb {
            case .environmentLowLight: return "Yorug'lik kam — yorqinroq joyga o'ting"
            case .objectTooClose: return "Obyektdan biroz uzoqroq turing"
            case .objectTooFar: return "Obyektga yaqinroq turing"
            case .movingTooFast: return "Sekinroq harakatlaning"
            case .outOfFieldOfView: return "Obyektni kameraga to'g'rilang"
            default: continue
            }
        }
        return nil
    }
}


// ────────────────────────────────────────────────────────────────────────
// Hybrid Photogrammetry — iPhone capture + macOS server processing
//
// 1. TexturedScanViewController capture mode'da ishlaydi (uploadMode=true)
// 2. Foydalanuvchi xona aylanib chiqadi, ~150-250 foto saqlanadi
// 3. Done bossa, foto'lar serverga multipart sifatida upload qilinadi
// 4. Server PENDING job yaratadi → macOS Python worker ko'rib chiqadi
// 5. Mobile poll qiladi, COMPLETED bo'lsa USDZ'ni yuklab oladi
// ────────────────────────────────────────────────────────────────────────

@available(iOS 17.0, *)
final class HybridUploadCoordinator: NSObject {
    static let shared = HybridUploadCoordinator()

    private weak var presentingController: UIViewController?
    private var pendingResult: FlutterResult?
    private var captureVC: TexturedScanViewController?
    private var uploadVC: HybridUploadViewController?

    /// Backend base URL (ApiConfig) — Flutter uzatadi.
    private var baseUrl: String = ""
    /// JWT access token — Flutter uzatadi.
    private var authToken: String = ""
    /// Provider — 'local_mac' yoki 'kiri_engine'
    private var provider: String = "local_mac"
    /// Mesh review screen'da tanlangan quality: "fast" | "standard" | "high".
    private var selectedQuality: String = "standard"
    /// Algorithm — Kiri uchun: 'photo' | 'featureless' | '3dgs'
    private var algorithm: String = "3dgs"

    func start(
        from controller: UIViewController,
        baseUrl: String,
        authToken: String,
        provider: String = "local_mac",
        algorithm: String = "3dgs",
        result: @escaping FlutterResult,
    ) {
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
                message: "Bu qurilmada LiDAR scan qo'llab-quvvatlanmaydi",
                details: nil,
            ))
            return
        }

        self.presentingController = controller
        self.pendingResult = result
        self.baseUrl = baseUrl
        self.authToken = authToken
        self.provider = provider
        self.algorithm = algorithm

        let vc = TexturedScanViewController()
        vc.uploadMode = true
        // Provider-specific caps; default 1500 (aws_gpu).
        //   - aws_gpu: 1500 — server-side pipeline avtomatik sequential matching
        //     ishlatadi >150 foto'da; sifat ko'p foto bilan yaxshilanadi.
        //   - kiri_engine: 300 — Kiri API hard limit.
        if provider == "kiri_engine" {
            vc.uploadModeMaxPhotos = 300
        }
        // aws_gpu va boshqalar default 1500
        vc.onPhotosReady = { [weak self] folder, count, quality in
            self?.handlePhotosReady(folder: folder, count: count, quality: quality)
        }
        vc.onCancel = { [weak self] in self?.handleCancel() }
        vc.onError = { [weak self] err in self?.handleError(err) }
        vc.modalPresentationStyle = .fullScreen
        self.captureVC = vc
        controller.present(vc, animated: true, completion: nil)
    }

    private func handleCancel() {
        let result = pendingResult
        pendingResult = nil
        captureVC?.dismiss(animated: true) { [weak self] in
            self?.captureVC = nil
            result?(nil)
        }
    }

    private func handleError(_ error: Error) {
        let result = pendingResult
        pendingResult = nil
        captureVC?.dismiss(animated: true) { [weak self] in
            self?.captureVC = nil
            result?(FlutterError(
                code: "CAPTURE_ERROR",
                message: error.localizedDescription,
                details: nil,
            ))
        }
    }

    private func handlePhotosReady(folder: URL, count: Int, quality: String) {
        // Capture VC ni yopib, upload progress ekraniga o'tamiz
        guard let presenter = presentingController else { return }
        self.selectedQuality = quality
        captureVC?.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.captureVC = nil

            let upload = HybridUploadViewController()
            upload.modalPresentationStyle = .fullScreen
            upload.onCancel = { [weak self] in
                self?.cleanup(folder: folder)
                let result = self?.pendingResult
                self?.pendingResult = nil
                self?.uploadVC?.dismiss(animated: true) {
                    self?.uploadVC = nil
                    result?(nil)
                }
            }
            self.uploadVC = upload
            presenter.present(upload, animated: true) {
                self.startUploadAndPoll(folder: folder, count: count)
            }
        }
    }

    private func cleanup(folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    private func startUploadAndPoll(folder: URL, count: Int) {
        // Background mode: foto'lar serverga yuklanadi va job_id qaytariladi.
        // Polling/download QILINMAYDI — server processing uzoq (5-30 daqiqa).
        // Foydalanuvchi Arizalar ekranida status'ni kuzatadi.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                await MainActor.run { self.uploadVC?.setStatus("Foto'lar yuklanmoqda... (\(count) ta)") }
                let jobId = try await self.uploadPhotos(folder: folder)
                self.cleanup(folder: folder)

                await MainActor.run {
                    let result = self.pendingResult
                    self.pendingResult = nil
                    self.uploadVC?.dismiss(animated: true) {
                        self.uploadVC = nil
                        // Yakuniy USDZ yo'li null — server hali ishlamoqda.
                        // Mobile bu job_id'ni Arizalar ekranida ko'rsatadi.
                        result?([
                            "method": "hybrid_photogrammetry",
                            "jobId": jobId,
                            "status": "pending",
                        ] as [String: Any])
                    }
                }
            } catch {
                self.cleanup(folder: folder)
                await MainActor.run {
                    let result = self.pendingResult
                    self.pendingResult = nil
                    self.uploadVC?.dismiss(animated: true) {
                        self.uploadVC = nil
                        result?(FlutterError(
                            code: "HYBRID_FAILED",
                            message: error.localizedDescription,
                            details: nil,
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Networking

    private func uploadPhotos(folder: URL) async throws -> Int {
        let url = URL(string: "\(baseUrl)/api/v1/photogrammetry/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let boundary = "boundary_\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let jpegs = files.filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
        if jpegs.isEmpty {
            throw NSError(domain: "Hybrid", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foto'lar topilmadi"])
        }

        // Multipart body'ni temp faylga stream qilib yozamiz — 100+ MB upload
        // uchun butun body'ni xotirada to'plash iOS URLSession'ni qotirib qo'yadi
        // (httpBody = Data orqali). uploadTask(fromFile:) bilan disk → tarmoq
        // chunked uzatiladi.
        let tmpBody = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload_\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: tmpBody.path, contents: nil)
        guard let bodyHandle = try? FileHandle(forWritingTo: tmpBody) else {
            throw NSError(domain: "Hybrid", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Temp body fayl ochilmadi"])
        }
        defer {
            try? bodyHandle.close()
            try? FileManager.default.removeItem(at: tmpBody)
        }

        func writeStr(_ s: String) {
            if let d = s.data(using: .utf8) { bodyHandle.write(d) }
        }
        func writeField(_ name: String, _ value: String) {
            writeStr("--\(boundary)\r\n")
            writeStr("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            writeStr(value)
            writeStr("\r\n")
        }
        writeField("provider", provider)
        writeField("algorithm", algorithm)
        writeField("quality", selectedQuality)

        // Foto'lar — har birini chunked o'qib yozamiz, butunni xotiraga
        // yuklamasdan (4K JPEG ~1-2 MB, 100+ ta bo'lishi mumkin).
        for url in jpegs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            writeStr("--\(boundary)\r\n")
            writeStr("Content-Disposition: form-data; name=\"photos\"; filename=\"\(url.lastPathComponent)\"\r\n")
            writeStr("Content-Type: image/jpeg\r\n\r\n")
            guard let inFh = try? FileHandle(forReadingFrom: url) else { continue }
            while autoreleasepool(invoking: {
                let chunk = inFh.readData(ofLength: 256 * 1024)  // 256 KB
                if chunk.isEmpty { return false }
                bodyHandle.write(chunk)
                return true
            }) {}
            try? inFh.close()
            writeStr("\r\n")
        }

        // poses.json (ARKit camera transforms) — agar mavjud bo'lsa qo'shamiz.
        // AWS GPU pipeline buni topganda COLMAP SfM bosqichini o'tkazib
        // yuboradi va ARKit pose'laridan to'g'ridan-to'g'ri foydalanadi.
        let posesURL = folder.appendingPathComponent("poses.json")
        if FileManager.default.fileExists(atPath: posesURL.path) {
            writeStr("--\(boundary)\r\n")
            writeStr("Content-Disposition: form-data; name=\"poses\"; filename=\"poses.json\"\r\n")
            writeStr("Content-Type: application/json\r\n\r\n")
            if let posesData = try? Data(contentsOf: posesURL) {
                bodyHandle.write(posesData)  // poses.json odatda <100 KB
            }
            writeStr("\r\n")
        }
        writeStr("--\(boundary)--\r\n")
        try? bodyHandle.synchronize()
        try? bodyHandle.close()

        request.timeoutInterval = 600  // 10 daqiqa

        // uploadTask(fromFile:) — disk'dan tarmoqqa stream, xotira yuklanmaydi
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: tmpBody)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Hybrid", code: code, userInfo: [NSLocalizedDescriptionKey: "Upload xato (\(code)): \(body)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobId = json["job_id"] as? Int else {
            throw NSError(domain: "Hybrid", code: 2, userInfo: [NSLocalizedDescriptionKey: "Server javobi noto'g'ri"])
        }
        return jobId
    }

    private func pollAndDownload(jobId: Int) async throws -> String {
        let statusUrl = URL(string: "\(baseUrl)/api/v1/photogrammetry/jobs/\(jobId)")!
        let pollInterval: UInt64 = 8 * 1_000_000_000  // 8s
        let maxIterations = 450  // ~1 soat

        var lastStatus = ""
        for _ in 0..<maxIterations {
            try await Task.sleep(nanoseconds: pollInterval)

            var req = URLRequest(url: statusUrl)
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let status = (json["status"] as? String) ?? ""

            if status != lastStatus {
                lastStatus = status
                await MainActor.run { [weak self] in
                    let label = (status == "processing") ? "Server tahlil qilmoqda..." : "Holat: \(status)"
                    self?.uploadVC?.setStatus(label + "\nBu 5-30 daqiqa olishi mumkin")
                }
            }

            if status == "completed" {
                guard let downloadUrl = json["download_url"] as? String else {
                    throw NSError(domain: "Hybrid", code: 3, userInfo: [NSLocalizedDescriptionKey: "Download URL kelmadi"])
                }
                return try await downloadUsdz(url: downloadUrl, jobId: jobId)
            }
            if status == "failed" {
                let msg = (json["error_message"] as? String) ?? "Server xatosi"
                throw NSError(domain: "Hybrid", code: 4, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            if status == "cancelled" {
                throw NSError(domain: "Hybrid", code: 5, userInfo: [NSLocalizedDescriptionKey: "Bekor qilingan"])
            }
        }
        throw NSError(domain: "Hybrid", code: 6, userInfo: [NSLocalizedDescriptionKey: "Timeout — server javob bermadi"])
    }

    private func downloadUsdz(url: String, jobId: Int) async throws -> String {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let (tempUrl, _) = try await URLSession.shared.download(for: req)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let scansFolder = docs.appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: scansFolder, withIntermediateDirectories: true)
        let destUrl = scansFolder.appendingPathComponent("hybrid_\(jobId).usdz")
        try? FileManager.default.removeItem(at: destUrl)
        try FileManager.default.moveItem(at: tempUrl, to: destUrl)
        return destUrl.path
    }
}


/// Upload progress UI — oddiy spinner + status matn.
@available(iOS 17.0, *)
final class HybridUploadViewController: UIViewController {
    var onCancel: (() -> Void)?

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        spinner.color = UIColor(red: 0/255, green: 225/255, blue: 53/255, alpha: 1)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        statusLabel.text = "Tayyorlanmoqda..."
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Bekor qilish", for: .normal)
        cancelBtn.setTitleColor(.white.withAlphaComponent(0.7), for: .normal)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            cancelBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            cancelBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    func setStatus(_ text: String) {
        statusLabel.text = text
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}


@available(iOS 17.0, *)
struct ObjectCaptureProcessingView: View {
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView()
                    .scaleEffect(1.6)
                    .tint(.green)
                Text("3D model qurilmoqda")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text("Photogrammetry hisoblanmoqda — bu 1-3 daqiqa olishi mumkin")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: onCancel) {
                    Text("Bekor qilish")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                        .foregroundColor(.white)
                }
                .padding(.top, 24)
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────────
// MARK: - Mesh review (Polycam-style preview before backend submit)
// ────────────────────────────────────────────────────────────────────────

/// Snapshots all `ARMeshAnchor` geometries currently in an `ARSCNView` and
/// combines them into one `SCNGeometry` ready for SCNView display. Vertices
/// are baked into world-space; per-vertex normals are filled in from the
/// ARMeshGeometry so a normal-based shader can colour the mesh.
@available(iOS 13.4, *)
enum MeshSnapshot {
    static func combine(arView: ARSCNView) -> SCNGeometry? {
        let frame = arView.session.currentFrame
        let anchors: [ARMeshAnchor] = (frame?.anchors ?? []).compactMap { $0 as? ARMeshAnchor }
        guard !anchors.isEmpty else { return nil }

        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var indexBase: UInt32 = 0

        for anchor in anchors {
            let g = anchor.geometry
            let xform = anchor.transform
            let normalXform = simd_float3x3(
                SIMD3<Float>(xform.columns.0.x, xform.columns.0.y, xform.columns.0.z),
                SIMD3<Float>(xform.columns.1.x, xform.columns.1.y, xform.columns.1.z),
                SIMD3<Float>(xform.columns.2.x, xform.columns.2.y, xform.columns.2.z),
            )
            let vBuf = g.vertices.buffer.contents()
            let vStride = g.vertices.stride
            let vCount = g.vertices.count

            let nBuf = g.normals.buffer.contents()
            let nStride = g.normals.stride

            // Pre-size to limit reallocations.
            vertices.reserveCapacity(vertices.count + vCount)
            normals.reserveCapacity(normals.count + vCount)

            for i in 0..<vCount {
                let v = vBuf.advanced(by: i * vStride).assumingMemoryBound(to: Float.self)
                let local = SIMD3<Float>(v[0], v[1], v[2])
                let world4 = xform * SIMD4<Float>(local, 1)
                vertices.append(SIMD3<Float>(world4.x, world4.y, world4.z))

                let n = nBuf.advanced(by: i * nStride).assumingMemoryBound(to: Float.self)
                let nLocal = SIMD3<Float>(n[0], n[1], n[2])
                normals.append(simd_normalize(normalXform * nLocal))
            }

            // Faces — convert to UInt32 indices, offset by indexBase.
            let faces = g.faces
            let fBuf = faces.buffer.contents()
            let triCount = faces.count
            indices.reserveCapacity(indices.count + triCount * 3)
            for i in 0..<triCount {
                if faces.bytesPerIndex == 4 {
                    let p = fBuf.advanced(by: i * 3 * 4).assumingMemoryBound(to: UInt32.self)
                    indices.append(p[0] + indexBase)
                    indices.append(p[1] + indexBase)
                    indices.append(p[2] + indexBase)
                } else {
                    let p = fBuf.advanced(by: i * 3 * 2).assumingMemoryBound(to: UInt16.self)
                    indices.append(UInt32(p[0]) + indexBase)
                    indices.append(UInt32(p[1]) + indexBase)
                    indices.append(UInt32(p[2]) + indexBase)
                }
            }
            indexBase += UInt32(vCount)
        }

        guard !vertices.isEmpty, !indices.isEmpty else { return nil }

        let vertexData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let normalData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }

        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size,
        )

        let geom = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        // Polycam-style normal-based colouring: |n.xyz| → RGB.
        // Implemented via shader modifier — runs on Metal, no extra geometry.
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = UIColor.white
        mat.shaderModifiers = [
            .fragment: """
            #pragma transparent
            float3 n = normalize(_surface.normal);
            float3 a = abs(n);
            // Saturated primary palette per axis. The previous additive blend
            // washed out diagonal surfaces (sum > 1 → clamps to white). We
            // weight-average by axis dominance so any normal direction stays
            // within [0..1] and keeps its hue.
            float3 colX = float3(0.95, 0.10, 0.55); // X → pink
            float3 colY = float3(0.10, 0.85, 0.95); // Y → cyan
            float3 colZ = float3(0.98, 0.78, 0.20); // Z → yellow
            float w = a.x + a.y + a.z + 1e-4;
            float3 col = (a.x * colX + a.y * colY + a.z * colZ) / w;
            // Slight ambient lift so back-facing triangles never read pure black.
            col = mix(col * 0.55, col, max(a.y, 0.4));
            _output.color = float4(col, 1.0);
            """
        ]
        geom.materials = [mat]
        return geom
    }
}

@available(iOS 17.0, *)
final class MeshReviewViewController: UIViewController {
    /// Combined mesh from MeshSnapshot. May be nil if device had no LiDAR
    /// frames yet (degenerate scan); we still show the screen with a hint.
    var previewGeometry: SCNGeometry?
    var photoCount: Int = 0
    var areaM2: Float = 0
    /// Confirmed quality string: "fast" | "standard" | "high".
    var onConfirm: ((String) -> Void)?
    /// Re-take = discard photos and start scan again.
    var onRetake: (() -> Void)?
    /// Continue = scan davom — eski foto'lar va anchor'lar saqlanadi, AR session
    /// qayta ishga tushiriladi (resetTracking BERILMAYDI).
    var onContinue: (() -> Void)?
    /// RoomPlan natijasi — devor/eshik/oyna/obyekt'lar dim wireframe sifatida
    /// mesh ustiga chiziladi. Foydalanuvchi qaysi joylar mesh'ga kirmaganini
    /// ko'radi (Polycam-style hint).
    var capturedRoom: CapturedRoom?

    private var scnView: SCNView!
    private var qualitySegment: UISegmentedControl!
    private var statsLabel: UILabel!
    private var estLabel: UILabel!

    private let qualityOptions: [(label: String, value: String, etaSec: Int)] = [
        ("Tez",       "fast",     900),   // sequential, 100k face cap
        ("Standard",  "standard", 1800),  // current default — 500k faces
        ("Sifatli",   "high",     3600),  // exhaustive matching, 1M faces
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.inertiaEnabled = true
        scnView.antialiasingMode = .multisampling4X
        view.addSubview(scnView)

        let scene = SCNScene()
        scnView.scene = scene

        // Mesh va RoomPlan overlay'larini bitta parent ichiga qo'yamiz, so'ng
        // butun guruhni center qilamiz — mesh va wireframe ham bir xil
        // koordinatalarda qoladi.
        let group = SCNNode()
        scene.rootNode.addChildNode(group)

        if let geom = previewGeometry {
            group.addChildNode(SCNNode(geometry: geom))
        }
        if #available(iOS 17, *), let room = capturedRoom {
            addRoomWireframe(to: group, room: room)
        }

        let (minV, maxV) = group.boundingBox
        let centerVec = SCNVector3(
            (minV.x + maxV.x) / 2,
            (minV.y + maxV.y) / 2,
            (minV.z + maxV.z) / 2,
        )
        group.position = SCNVector3(-centerVec.x, -centerVec.y, -centerVec.z)

        let extentX = maxV.x - minV.x
        let extentY = maxV.y - minV.y
        let extentZ = maxV.z - minV.z
        let radius = max(max(extentX, extentY, extentZ), 1.0)
        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = Double(radius * 10 + 50)
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, radius * 0.3, radius * 1.6)
        camNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camNode)
        scnView.pointOfView = camNode

        setupOverlay()
    }

    @available(iOS 17, *)
    private func addRoomWireframe(to parent: SCNNode, room: CapturedRoom) {
        let wallColor = UIColor.white.withAlphaComponent(0.45)
        let openingColor = UIColor.cyan.withAlphaComponent(0.55)
        let objectColor = UIColor.green.withAlphaComponent(0.5)
        for s in room.walls {
            parent.addChildNode(TexturedScanViewController.makeWireframeRect(surface: s, color: wallColor))
        }
        for s in room.doors {
            parent.addChildNode(TexturedScanViewController.makeWireframeRect(surface: s, color: openingColor))
        }
        for s in room.windows {
            parent.addChildNode(TexturedScanViewController.makeWireframeRect(surface: s, color: openingColor))
        }
        for s in room.openings {
            parent.addChildNode(TexturedScanViewController.makeWireframeRect(surface: s, color: openingColor))
        }
        for o in room.objects {
            parent.addChildNode(TexturedScanViewController.makeWireframeBox(object: o, color: objectColor))
        }
    }

    private func setupOverlay() {
        // Top: stats label
        statsLabel = UILabel()
        statsLabel.text = formatStats()
        statsLabel.textColor = .white
        statsLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statsLabel.textAlignment = .center
        statsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statsLabel.layer.cornerRadius = 14
        statsLabel.layer.masksToBounds = true
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsLabel)

        // Bottom panel: quality selector + buttons
        let panel = UIView()
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        panel.layer.cornerRadius = 18
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        qualitySegment = UISegmentedControl(items: qualityOptions.map(\.label))
        qualitySegment.selectedSegmentIndex = 1  // Standard default
        qualitySegment.selectedSegmentTintColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        qualitySegment.setTitleTextAttributes(
            [.foregroundColor: UIColor.white], for: .normal,
        )
        qualitySegment.setTitleTextAttributes(
            [.foregroundColor: UIColor.white], for: .selected,
        )
        qualitySegment.translatesAutoresizingMaskIntoConstraints = false
        qualitySegment.addTarget(self, action: #selector(qualityChanged), for: .valueChanged)
        panel.addSubview(qualitySegment)

        estLabel = UILabel()
        estLabel.text = formatEta()
        estLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        estLabel.font = .systemFont(ofSize: 12, weight: .regular)
        estLabel.textAlignment = .center
        estLabel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(estLabel)

        let continueBtn = UIButton(type: .system)
        continueBtn.setTitle("Davom etish", for: .normal)
        continueBtn.setTitleColor(.white, for: .normal)
        continueBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        continueBtn.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        continueBtn.layer.cornerRadius = 22
        continueBtn.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
        continueBtn.layer.borderWidth = 1
        continueBtn.translatesAutoresizingMaskIntoConstraints = false
        continueBtn.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        panel.addSubview(continueBtn)

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Qayta scan", for: .normal)
        cancelBtn.setTitleColor(.white, for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cancelBtn.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        cancelBtn.layer.cornerRadius = 22
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
        panel.addSubview(cancelBtn)

        let confirmBtn = UIButton(type: .system)
        confirmBtn.setTitle("Yuborish", for: .normal)
        confirmBtn.setTitleColor(.white, for: .normal)
        confirmBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        confirmBtn.backgroundColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        confirmBtn.layer.cornerRadius = 22
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false
        confirmBtn.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        panel.addSubview(confirmBtn)

        NSLayoutConstraint.activate([
            statsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statsLabel.heightAnchor.constraint(equalToConstant: 32),
            statsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            qualitySegment.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            qualitySegment.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            qualitySegment.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            qualitySegment.heightAnchor.constraint(equalToConstant: 32),

            estLabel.topAnchor.constraint(equalTo: qualitySegment.bottomAnchor, constant: 6),
            estLabel.centerXAnchor.constraint(equalTo: panel.centerXAnchor),

            continueBtn.topAnchor.constraint(equalTo: estLabel.bottomAnchor, constant: 14),
            continueBtn.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            continueBtn.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            continueBtn.heightAnchor.constraint(equalToConstant: 44),

            cancelBtn.topAnchor.constraint(equalTo: continueBtn.bottomAnchor, constant: 10),
            cancelBtn.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            cancelBtn.heightAnchor.constraint(equalToConstant: 44),
            cancelBtn.widthAnchor.constraint(equalToConstant: 120),
            cancelBtn.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),

            confirmBtn.topAnchor.constraint(equalTo: cancelBtn.topAnchor),
            confirmBtn.leadingAnchor.constraint(equalTo: cancelBtn.trailingAnchor, constant: 10),
            confirmBtn.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            confirmBtn.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func formatStats() -> String {
        return "\(photoCount) foto • \(Int(areaM2.rounded())) m²"
    }

    private func formatEta() -> String {
        let q = qualityOptions[qualitySegment?.selectedSegmentIndex ?? 1]
        let mins = q.etaSec / 60
        return "Taxminiy ishlash vaqti: ~\(mins) daq"
    }

    @objc private func qualityChanged() {
        estLabel.text = formatEta()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func confirmTapped() {
        let q = qualityOptions[qualitySegment.selectedSegmentIndex].value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true) { [weak self] in
            self?.onConfirm?(q)
        }
    }

    @objc private func retakeTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let alert = UIAlertController(
            title: "Qayta scan?",
            message: "Hozirgi foto'lar va mesh o'chiriladi.",
            preferredStyle: .alert,
        )
        alert.addAction(UIAlertAction(title: "Bekor qilish", style: .cancel))
        alert.addAction(UIAlertAction(title: "Ha, qayta", style: .destructive) { [weak self] _ in
            self?.onRetake?()
        })
        present(alert, animated: true)
    }

    @objc private func continueTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss(animated: true) { [weak self] in
            self?.onContinue?()
        }
    }
}
