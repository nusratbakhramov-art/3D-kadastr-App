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
import ModelIO  // SCNScene → MDLAsset → USDZ export
import simd
import ImageIO
import CoreGraphics
import CoreImage
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
        vc.savingMode = true  // Phase 7: Done → save raw (default)
        vc.onSavedRaw = { [weak self] scanId in
            self?.handleSavedRaw(scanId: scanId)
        }
        vc.onFinished = { [weak self] (url, stats) in
            self?.handleFinish(url: url, stats: stats)
        }
        vc.onCancel = { [weak self] in self?.handleCancel() }
        vc.onError = { [weak self] err in self?.handleError(err) }
        controller.present(vc, animated: true)
        self.sessionVC = vc
    }

    /// Phase 7: Re-process saqlangan scan. UI = TexturedScanViewController
    /// offline mode'da, AR session ishga tushirilmaydi.
    func processSavedScan(
        scanId: Int,
        params: [String: String] = [:],
        from controller: UIViewController,
        result: @escaping FlutterResult,
    ) {
        DebugLog.log("COORD", "processSavedScan called scanId=\(scanId)")
        if pendingResult != nil {
            DebugLog.log("COORD", "FAIL: already processing")
            result(FlutterError(
                code: "ALREADY_PROCESSING",
                message: "Boshqa scan jarayoni ketmoqda",
                details: nil,
            ))
            return
        }
        guard SavedScanStorage.get(id: scanId) != nil else {
            DebugLog.log("COORD", "FAIL: scan not found in storage")
            result(FlutterError(
                code: "NOT_FOUND",
                message: "Scan #\(scanId) topilmadi",
                details: nil,
            ))
            return
        }

        self.presentingController = controller
        self.pendingResult = result

        let vc = TexturedScanViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.offlineScanId = scanId
        vc.offlineParams = params
        vc.onOfflineFinished = { [weak self] (url, version) in
            DebugLog.log("COORD", "onOfflineFinished v=\(version)")
            self?.handleOfflineFinished(url: url, version: version, scanId: scanId)
        }
        vc.onError = { [weak self] err in
            DebugLog.log("COORD", "onError: \(err.localizedDescription)")
            self?.handleError(err)
        }
        vc.onCancel = { [weak self] in
            DebugLog.log("COORD", "onCancel")
            self?.handleCancel()
        }
        DebugLog.log("COORD", "presenting VC offline")
        controller.present(vc, animated: true) {
            DebugLog.log("COORD", "VC presentation completed")
        }
        self.sessionVC = vc
    }

    private func handleSavedRaw(scanId: Int) {
        guard let result = pendingResult else { return }
        pendingResult = nil
        sessionVC?.dismiss(animated: true)
        sessionVC = nil
        result([
            "savedScanId": scanId,
            "mode": "saved_raw",
        ])
    }

    private func handleOfflineFinished(url: URL, version: Int, scanId: Int) {
        guard let result = pendingResult else { return }
        pendingResult = nil
        sessionVC?.dismiss(animated: true)
        sessionVC = nil
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs?[.size] as? Int) ?? 0
        result([
            "scanId": scanId,
            "version": version,
            "filePath": url.path,
            "fileSize": fileSize,
            "mode": "offline_processed",
        ])
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
    private var pauseBtn: UIButton!           // hidden, Polycam'da yo'q
    private var shutterBtn: UIButton!         // Polycam-style manual shutter
    private var modeBtn: UIButton!            // "Auto ⌃" dropdown — Manual/Auto menu
    private var shutterLabel: UILabel!        // "Shutter" matn modeBtn ostida
    private var bottomBar: UIView!            // dark bg bottom container
    private var flashlightBtn: UIButton!
    private var trackingLostBanner: UILabel!
    private var pauseOverlay: UIView!  // ko'k tint paused state'da
    private var pauseMessageLabel: UILabel!
    private var startOverBtn: UIButton!
    private var isPaused: Bool = false
    private var isFlashlightOn: Bool = false
    // Polycam-style overlays
    private var areaPill: UILabel!         // "est X m²" yuqori chapda (kichik)
    private var photoPill: UILabel!        // Polycam'da yo'q — yashirin
    private var hintPill: UILabel!         // "Tap record button once to begin"
    private var speedWarning: UILabel!     // "Sekinlash!" markazda
    // Processing UI
    private var processingOverlay: UIView!
    private var processingLabel: UILabel!
    private var progressView: UIProgressView!
    private var processingStatusLabel: UILabel!

    // Real-time scan metrics
    private var totalMeshAreaM2: Float = 0
    private var meshAreaByAnchor: [UUID: Float] = [:]
    // Per-anchor coverage tracking — har anchor uchun nechta photo ko'rgan.
    // Visualization rang-bo'yashda ishlatiladi (qizil → yashil).
    // Faqat main thread'da o'qish/yozish (SCN delegate callback'lar main'da).
    private var anchorCoverage: [UUID: Int] = [:]
    private var frameVisibilityTick: UInt64 = 0  // Frame-based coverage tracker

    // Variant A: Streaming TSDF — har frame'da depth voxel grid'ga integrate qilinadi.
    // Capture davomida tirik qoladi, oxirida mesh ekstraktsiya qilinadi.
    private var streamingTSDF: StreamingTSDF?
    private var tsdfFrameTick: UInt64 = 0  // har 5-chi frame'da integrate (12 fps)

    // RoomPlan integratsiya — devor/eshik/oyna detect qiladi (glass/metal'da
    // LiDAR yetmagan joylarni planar surface bilan to'ldirish uchun).
    // iOS 17+ uchun RoomCaptureSession(arSession:) bor.
    private var roomSession: Any?   // RoomCaptureSession? (iOS 17+)
    private var capturedRoomData: Any?  // CapturedRoom? (iOS 16+)
    /// Anchor birinchi marta ko'rilgandan keyin shuncha sekund o'tgach geometry
    /// yangilanishi to'xtaydi — ARKit drift'i visualizatsiyani buzmasligi uchun.
    /// Foto capture davom etadi, lekin ko'rgan mesh barqaror qoladi.
    private var lastFramePos: SIMD3<Float>?
    private var lastFrameTime: TimeInterval = 0
    private var lastSpeedSamples: [Float] = []  // moving avg, m/s
    private let maxSafeSpeedMps: Float = 0.5    // > 0.5 m/s → tez ketyapsiz

    // Haptic feedback — Polycam style "tick" on each photo capture.
    private let captureHaptic = UIImpactFeedbackGenerator(style: .light)

    // Hi-res capture (Polycam-style) — captureHighResolutionFrame() async 12 MP
    // photo'larni oladi. Async qaytgan ARFrame'ning O'Z transform'i ishlatiladi
    // (pose-image sinx muammosi yo'q). Memory peak ~3 ta concurrent (semaphore).
    private var pendingHiResCount = 0
    private let pendingHiResLock = NSLock()
    private let hiResSemaphore = DispatchSemaphore(value: 3)

    // Capture mode: .auto (movement-based) yoki .manual (shutter button only).
    // Polycam-style — foydalanuvchi rejim tanlaydi.
    enum CaptureMode { case auto, manual }
    private var captureMode: CaptureMode = .auto
    // isCapturing: Auto rejimda harakat-trigger faqat shutter (play) bosilgandan
    // keyin ishlaydi. Initial state false — capture boshlanmagan, shutter ▶ play.
    private var isCapturing: Bool = false

    // Phase 7: Save raw mode + offline reprocess.
    /// Default true: Done → save raw data → exit (no immediate texturing).
    /// Foydalanuvchi profile'da scan'ni ochib "Process" bosadi → texturing.
    var savingMode: Bool = true
    /// Set when VC opens to re-process an already-saved scan. No AR session
    /// is started; viewDidAppear loads data from SavedScanStorage and runs
    /// texturing pipeline. onOfflineFinished returns the output URL.
    var offlineScanId: Int?
    /// Re-process params (optional, future: Taubin/power/ESRGAN overrides).
    var offlineParams: [String: String] = [:]
    /// Called after raw data is saved (savingMode = true flow).
    var onSavedRaw: ((Int) -> Void)?
    /// Called after offline processing completes (offlineScanId set).
    /// Returns: output URL + version number registered in SavedScanStorage.
    var onOfflineFinished: ((URL, Int) -> Void)?

    // Capture state
    private var photoFolder: URL!
    private var captureCount = 0
    private var lastCapturePos: SIMD3<Float>?
    private var lastCaptureRot: simd_quatf?
    private var lastCaptureTime: TimeInterval = 0
    // Best-view + multi-band uchun: KAMROQ, lekin yaxshi joylashgan foto'lar.
    // Avval 5cm/5° edi → xona uchun ~400 foto (juda ko'p, ortiqcha+xira frame'lar
    // rekonstruksiyani chalkashtirardi). 15cm/~8.5° → ~3x kam (~130-150 foto),
    // best-view har yuza uchun yetarli sharp ko'rinish topadi.
    private let minPositionDelta: Float = 0.15    // 15 cm
    private let minRotationDelta: Float = 0.15    // ~8.5 degrees
    private let minTimeBetweenCaptures: TimeInterval = 0.35
    private let minRequiredPhotos = 30
    // Phase 9: silent capture (1920×1440) → har photo ~250 KB, 1000 photo ~250 MB.
    // Polycam-style continuous scanning uchun 400 → 2000.
    private let maxAllowedPhotos = 2000

    /// ARKit dan har frame uchun camera pose + intrinsics. Capture tugagach
    /// `poses.json` ga yoziladi va serverga foto'lar bilan birga yuboriladi.
    /// AWS GPU pipeline bu pose'lardan COLMAP SfM bosqichini o'tkazib yuborish
    /// uchun foydalanadi (~25 daq tejaladi va past sifatli foto'larda ham
    /// ishonchli ishlaydi).
    private var capturedPoses: [[String: Any]] = []

    // Processing state
    private var processingTask: Task<Void, Never>?
    private var isProcessing = false
    /// Phase 7: offline reprocess — runCustomMeshExport extractAnchorData
    /// o'rniga shu listni ishlatadi (arView yo'q).
    fileprivate var offlineAnchorOverride: [AnchorRaw]?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Phase 7: Offline reprocess mode — saved scan'ni qayta texturing.
        // AR session ishga tushirilmaydi, faqat processing overlay ko'rinadi.
        if let scanId = offlineScanId {
            DebugLog.log("VC", "viewDidLoad OFFLINE scanId=\(scanId)")
            setupProcessingOverlay()
            processingOverlay.isHidden = false
            processingStatusLabel.text = "Saqlangan ma'lumotlar yuklanmoqda…"
            return
        }

        DebugLog.log("VC", "viewDidLoad LIVE")
        setupPhotoFolder()
        setupARView()
        setupCoaching()
        setupOverlay()
        setupProcessingOverlay()
        captureHaptic.prepare()  // pre-warm so first tick has no latency
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let scanId = offlineScanId {
            DebugLog.log("VC", "viewDidAppear OFFLINE scanId=\(scanId), calling startOfflineProcessing")
            startOfflineProcessing(scanId: scanId)
            return
        }

        DebugLog.log("VC", "viewDidAppear LIVE")
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
        // Phase 7: arView offline reprocess mode'da nil — crashdan saqlanish.
        arView?.session.pause()
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
        // Polycam-style letterbox: ARSCNView 4:3 aspect ratio bilan markazda
        // joylashtiriladi. iPhone ekrani 19.5:9 (juda baland), kamera 4:3 →
        // full ekran qilsak, kesilib zoom in ko'rinadi. Letterbox bilan kamera'ning
        // to'liq FOV ko'rinadi, yuqorida + pastda qora bo'sh joylar bo'ladi.
        arView = ARSCNView()
        arView.translatesAutoresizingMaskIntoConstraints = false
        arView.session.delegate = self
        arView.delegate = self  // mesh visualization uchun
        arView.automaticallyUpdatesLighting = true
        view.backgroundColor = .black  // letterbox bars
        view.addSubview(arView)
        NSLayoutConstraint.activate([
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            // Camera 4:3 aspect → height = width × 4/3
            arView.heightAnchor.constraint(equalTo: arView.widthAnchor, multiplier: 4.0 / 3.0),
        ])
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
        // Polycam-style bottom container — fully transparent, kamera butun ekran
        // ko'rinadi. Tugmalar ustida o'z fon'lari (qora capsule) bor.
        bottomBar = UIView()
        bottomBar.backgroundColor = .clear
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        // Shutter button — markaz, katta oq dumaloq (Polycam-style).
        // Auto mode: ▶ play (boshlash) ↔ ⏸ pause (to'xtatish).
        // Manual mode: kichik nuqta (har bosish bitta foto).
        shutterBtn = UIButton(type: .system)
        shutterBtn.tintColor = .black
        shutterBtn.backgroundColor = .white
        shutterBtn.layer.borderWidth = 4
        shutterBtn.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        shutterBtn.layer.cornerRadius = 36
        shutterBtn.translatesAutoresizingMaskIntoConstraints = false
        shutterBtn.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        bottomBar.addSubview(shutterBtn)
        updateShutterIcon()

        // Polycam-style Manual/Auto dropdown — kichik pill button + chevron
        modeBtn = UIButton(type: .system)
        modeBtn.setTitle("Auto", for: .normal)
        modeBtn.setImage(UIImage(systemName: "chevron.up",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)), for: .normal)
        modeBtn.tintColor = .white
        modeBtn.setTitleColor(.white, for: .normal)
        modeBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        modeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        modeBtn.layer.cornerRadius = 18
        modeBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 12)
        modeBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 6)
        modeBtn.semanticContentAttribute = .forceRightToLeft  // chevron text dan keyin
        modeBtn.translatesAutoresizingMaskIntoConstraints = false
        // UIMenu — Manual / Auto items
        modeBtn.menu = UIMenu(title: "", children: [
            UIAction(title: "Manual", image: UIImage(systemName: "camera")) { [weak self] _ in
                self?.setCaptureMode(.manual)
            },
            UIAction(title: "Auto", image: UIImage(systemName: "video"), state: .on) { [weak self] _ in
                self?.setCaptureMode(.auto)
            },
        ])
        modeBtn.showsMenuAsPrimaryAction = true
        bottomBar.addSubview(modeBtn)

        // "Shutter" matn modeBtn ostida
        shutterLabel = UILabel()
        shutterLabel.text = "Shutter"
        shutterLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        shutterLabel.font = .systemFont(ofSize: 12, weight: .regular)
        shutterLabel.textAlignment = .center
        shutterLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(shutterLabel)

        // Pause — Polycam UI'da yo'q. Yashirin saqlanadi (kod backward-compat uchun)
        pauseBtn = UIButton(type: .system)
        pauseBtn.isHidden = true
        pauseBtn.translatesAutoresizingMaskIntoConstraints = false
        pauseBtn.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        view.addSubview(pauseBtn)

        // Done — o'ng tomonda, Polycam style outlined oval check pill
        doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Done", for: .normal)
        doneBtn.setImage(UIImage(systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
        doneBtn.tintColor = .white
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        doneBtn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        doneBtn.layer.cornerRadius = 18
        doneBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 16)
        doneBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: -6)
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        bottomBar.addSubview(doneBtn)

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

        // Photo count pill — Polycam'da yo'q, yashirilgan (kod compat uchun)
        photoPill = UILabel()
        photoPill.text = "0 foto"
        photoPill.isHidden = true
        photoPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(photoPill)

        // Polycam-style hint pill — "Tap record button once to begin"
        // Faqat capture boshlanmagunicha ko'rinadi. Bo'shliqlar text padding uchun.
        hintPill = UILabel()
        hintPill.text = "  Tap record button once to begin  "
        hintPill.textColor = .black
        hintPill.font = .systemFont(ofSize: 14, weight: .medium)
        hintPill.textAlignment = .center
        hintPill.backgroundColor = .white
        hintPill.layer.cornerRadius = 6
        hintPill.layer.masksToBounds = true
        hintPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintPill)

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
            // Bottom dark bar — capture controls container
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -130),

            // Shutter — markaz, katta oq dumaloq
            shutterBtn.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            shutterBtn.centerYAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 50),
            shutterBtn.widthAnchor.constraint(equalToConstant: 72),
            shutterBtn.heightAnchor.constraint(equalToConstant: 72),

            // Mode dropdown — bottomBar chapida, shutter bilan vertical bir xil
            modeBtn.centerYAnchor.constraint(equalTo: shutterBtn.centerYAnchor),
            modeBtn.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 24),
            modeBtn.heightAnchor.constraint(equalToConstant: 36),

            // "Shutter" label — modeBtn ostida (Polycam'dagi kabi)
            shutterLabel.topAnchor.constraint(equalTo: modeBtn.bottomAnchor, constant: 4),
            shutterLabel.centerXAnchor.constraint(equalTo: modeBtn.centerXAnchor),

            // Done — bottomBar o'ng tomonida
            doneBtn.centerYAnchor.constraint(equalTo: shutterBtn.centerYAnchor),
            doneBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),
            doneBtn.heightAnchor.constraint(equalToConstant: 36),

            // Pause yashirin (Polycam'da yo'q) — minimal constraint
            pauseBtn.widthAnchor.constraint(equalToConstant: 0),
            pauseBtn.heightAnchor.constraint(equalToConstant: 0),

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

            // Hint pill — shutter ustida (Polycam-style "Tap record button once to begin")
            hintPill.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),
            hintPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintPill.heightAnchor.constraint(equalToConstant: 36),
            hintPill.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            hintPill.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

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
        // Polycam-style: bottom bar overlay, clay mesh top'da ko'rinib turadi.
        // Full-screen black overlay yo'q — faqat pastki ~160 pt zonasi qoplanadi.
        processingOverlay = UIView()
        processingOverlay.backgroundColor = .clear
        processingOverlay.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.isHidden = true
        processingOverlay.isUserInteractionEnabled = true  // touch'larni mesh'gacha o'tkazmaslik
        view.addSubview(processingOverlay)

        // Bottom dark bar — UI elementlari shu yerda
        let bottomBar = UIView()
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(bottomBar)

        // Top "Processing" title bar
        let topBar = UIView()
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(topBar)

        processingLabel = UILabel()
        processingLabel.text = "Processing"
        processingLabel.textColor = .white
        processingLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        processingLabel.textAlignment = .center
        processingLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(processingLabel)

        // Bottom bar content
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.2)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(progressView)

        processingStatusLabel = UILabel()
        processingStatusLabel.text = "Preparing…"
        processingStatusLabel.textColor = .white
        processingStatusLabel.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        processingStatusLabel.textAlignment = .left
        processingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(processingStatusLabel)

        let infoLabel = UILabel()
        infoLabel.text = "Keep app open while processing"
        infoLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        infoLabel.font = .systemFont(ofSize: 12, weight: .regular)
        infoLabel.textAlignment = .center
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(infoLabel)

        NSLayoutConstraint.activate([
            processingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            processingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            processingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            processingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            topBar.topAnchor.constraint(equalTo: processingOverlay.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: processingOverlay.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: processingOverlay.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 88),  // safe area + title

            processingLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            processingLabel.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -12),

            bottomBar.leadingAnchor.constraint(equalTo: processingOverlay.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: processingOverlay.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: processingOverlay.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 130),

            progressView.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 0),
            progressView.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3),

            processingStatusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 20),
            processingStatusLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 24),
            processingStatusLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),

            infoLabel.topAnchor.constraint(equalTo: processingStatusLabel.bottomAnchor, constant: 12),
            infoLabel.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
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
        // Polycam-style: ultra-wide camera (0.5x) — kengroq FOV → kamera "uzoqroq"
        // ko'rinadi, foydalanuvchi ko'proq sahnani ko'radi. Mavjud bo'lmasa,
        // standart wide camera'ning eng yuqori rezolyusiyasi tanlanadi.
        let allFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        for f in allFormats {
            NSLog("KADASTR fmt: \(f.captureDeviceType.rawValue) \(Int(f.imageResolution.width))×\(Int(f.imageResolution.height)) @\(f.framesPerSecond)")
        }
        var picked: ARConfiguration.VideoFormat? = nil
        if #available(iOS 14.5, *) {
            // Try ultra-wide first
            picked = allFormats.first { $0.captureDeviceType == .builtInUltraWideCamera }
            if let p = picked {
                NSLog("KADASTR using ULTRA-WIDE: \(Int(p.imageResolution.width))×\(Int(p.imageResolution.height))")
            }
        }
        if picked == nil {
            // 4:3 aspect format — bizning arView ham 4:3 portrait, kesilmaydi.
            // 16:9 format'lar kesilib chiqib zoomed-in effekt beradi.
            let fourByThree = allFormats.filter { fmt in
                let w = fmt.imageResolution.width
                let h = fmt.imageResolution.height
                let ratio = w / h
                return abs(ratio - 4.0/3.0) < 0.02
            }
            picked = fourByThree.max(by: { $0.imageResolution.width < $1.imageResolution.width })
            if let p = picked {
                NSLog("KADASTR using 4:3 WIDE: \(Int(p.imageResolution.width))×\(Int(p.imageResolution.height))")
            }
        }
        if picked == nil {
            // Last fallback: max resolution (any aspect)
            picked = allFormats.max(by: { $0.imageResolution.width < $1.imageResolution.width })
            if let p = picked {
                NSLog("KADASTR using FALLBACK: \(Int(p.imageResolution.width))×\(Int(p.imageResolution.height))")
            }
        }
        if let p = picked {
            config.videoFormat = p
            let camType = p.captureDeviceType.rawValue
            let camLabel = camType.contains("UltraWide") ? "📷 0.5x ultra-wide"
                         : camType.contains("Telephoto") ? "📷 3x tele"
                         : "📷 1x wide"
            let res = "\(Int(p.imageResolution.width))×\(Int(p.imageResolution.height))"
            DispatchQueue.main.async { [weak self] in
                self?.statusLabel?.text = "\(camLabel) \(res)"
                self?.statusLabel?.alpha = 1
            }
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if #available(iOS 14.0, *) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Variant A: Streaming TSDF — initial bbox camera atrofida (8m × 4m × 8m).
        // Tracking initialize bo'lgach (1-2 sek), birinchi frame'da camera pose
        // bilan center'lanadi. Hozircha origin = world (0,0,0) atrofida.
        if streamingTSDF == nil {
            streamingTSDF = StreamingTSDF(
                centerWorld: SIMD3<Float>(0, 0, 0),
                extents: SIMD3<Float>(8, 4, 8),
                voxelSize: 0.05,
            )
        }

        // RoomPlan integratsiya o'chirildi — RoomCaptureSession.run() bizning
        // ARSession konfiguratsiyasini qayta yozar edi (mesh + depth o'chib
        // qolar edi). Plane fill keyinroq alohida usul bilan qo'shamiz.
        // startRoomCapture()
    }

    private func startRoomCapture() {
        #if canImport(RoomPlan)
        guard #available(iOS 17.0, *) else { return }
        guard RoomCaptureSession.isSupported else { return }
        let session = RoomCaptureSession(arSession: arView.session)
        session.delegate = self
        let config = RoomCaptureSession.Configuration()
        session.run(configuration: config)
        roomSession = session
        NSLog("KADASTR RoomCaptureSession started")
        #endif
    }

    private func stopRoomCapture() {
        #if canImport(RoomPlan)
        guard #available(iOS 17.0, *) else { return }
        (roomSession as? RoomCaptureSession)?.stop()
        #endif
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

        // Phase 9.2: Frame-based coverage O'CHIRILDI — faqat camera qarashidan
        // anchor "captured" bo'lardi, hatto sharp photo olinmasa ham. Endi
        // FAQAT sharp (sharpness > 0.2) photo coverage'ni qoplaydi → blue
        // joylar haqiqatan ham qayta scan kerakligini ko'rsatadi.
        let scanningActive = isCapturing || captureCount > 0
        if scanningActive {
            // frameVisibilityTick coverage uchun ishlatilmaydi — saqlab qolamiz
            // boshqa logic uchun (TSDF integration cadence ostida).
            frameVisibilityTick &+= 1
            if false {  // disabled — sharpness-only coverage
                let visIds = computeVisibleAnchorIds(in: frame)
                _ = visIds
            }

            // Phase 4.1: Streaming TSDF integration — har 2-chi frame (30 fps).
            // 3 → 2: 50% ko'proq sample/voxel, coverage hech bir region'da
            // o'tkazib yuborilmaydi. Metal kernel ~1.5M voxel × few ALU =
            // ~3 ms/frame, 30fps integration thermal headroom ichida.
            if #available(iOS 14.0, *) {
                tsdfFrameTick &+= 1
                if tsdfFrameTick % 2 == 0 {
                    streamingTSDF?.integrate(frame: frame)
                }
            }
        }

        if now - lastCaptureTime < minTimeBetweenCaptures { return }
        let rot3x3 = simd_float3x3(
            SIMD3<Float>(frame.camera.transform.columns.0.x, frame.camera.transform.columns.0.y, frame.camera.transform.columns.0.z),
            SIMD3<Float>(frame.camera.transform.columns.1.x, frame.camera.transform.columns.1.y, frame.camera.transform.columns.1.z),
            SIMD3<Float>(frame.camera.transform.columns.2.x, frame.camera.transform.columns.2.y, frame.camera.transform.columns.2.z),
        )
        let rot = simd_quatf(rot3x3)

        // Auto rejimda capture faqat shutter (▶ play) bosilgandan keyin boshlanadi.
        // Manual rejimda harakat-trigger umuman ishlatilmaydi.
        guard captureMode == .auto, isCapturing else { return }

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

    @objc private func shutterTapped() {
        guard !isProcessing, !isPaused else { return }
        if captureMode == .auto {
            // Auto: shutter = play/pause toggle
            isCapturing.toggle()
            updateShutterIcon()
            refreshAllAnchorVisualizations()  // mesh overlay paydo/yashirin
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            NSLog("KADASTR isCapturing=\(isCapturing)")
            return
        }
        // Manual: har bosish — 1 ta foto
        guard let frame = arView.session.currentFrame else { return }
        if captureCount >= maxAllowedPhotos {
            let alert = UIAlertController(
                title: "Limit", message: "\(maxAllowedPhotos) foto chegarasiga yetdingiz.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        capturePhoto(frame)
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
        lastCapturePos = pos
        lastCaptureRot = simd_quatf(rot3x3)
        lastCaptureTime = Date().timeIntervalSinceReferenceDate
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.08, animations: {
            self.shutterBtn.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        }, completion: { _ in
            UIView.animate(withDuration: 0.1) {
                self.shutterBtn.transform = .identity
            }
        })
    }

    private func updateShutterIcon() {
        let symbolName: String
        if captureMode == .auto {
            symbolName = isCapturing ? "pause.fill" : "play.fill"
        } else {
            // Manual mode — kichik dumaloq nuqta (har bosish bitta foto)
            symbolName = "circle.fill"
        }
        let cfg = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        shutterBtn.setImage(UIImage(systemName: symbolName, withConfiguration: cfg), for: .normal)
        updateHintVisibility()
    }

    private func updateHintVisibility() {
        // Hint faqat boshlang'ich holatda — capture boshlanmagan va hech foto yo'q.
        guard hintPill != nil else { return }
        let shouldShow = !isCapturing && captureCount == 0
        if shouldShow {
            if captureMode == .manual {
                hintPill.text = "  Tap shutter to take a photo  "
            } else {
                hintPill.text = "  Tap record button once to begin  "
            }
        }
        UIView.animate(withDuration: 0.2) {
            self.hintPill.alpha = shouldShow ? 1.0 : 0.0
        }
    }

    private func setCaptureMode(_ mode: CaptureMode) {
        captureMode = mode
        // Mode o'zgarganda auto-capture to'xtatiladi — yangi rejim ishlatiladi.
        isCapturing = false
        let title = (mode == .manual) ? "Manual" : "Auto"
        modeBtn.setTitle(title, for: .normal)
        // UIMenu selected state'ni yangilash
        modeBtn.menu = UIMenu(title: "", children: [
            UIAction(title: "Manual", image: UIImage(systemName: "camera"),
                     state: mode == .manual ? .on : .off) { [weak self] _ in
                self?.setCaptureMode(.manual)
            },
            UIAction(title: "Auto", image: UIImage(systemName: "video"),
                     state: mode == .auto ? .on : .off) { [weak self] _ in
                self?.setCaptureMode(.auto)
            },
        ])
        updateShutterIcon()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        NSLog("KADASTR captureMode: \(captureMode == .manual ? "manual" : "auto")")
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

        // Phase 9.1: Silent capture — captureHighResolutionFrame chaqirilmaydi
        // (system shutter sound chiqaradi). ARFrame.capturedImage 1920×1440 RGB
        // pose-accurate (T0 same frame), no async, no sound. Polycam style.
        let opts: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
        ]
        CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
        let ok = CGImageDestinationFinalize(dest)
        if !ok { return }

        // Phase 9.2: per-photo sharpness (silent capture'da ham). Atlas baker
        // view-dep blending + anchor coverage filter uchun.
        let sharpness = ImageQuality.sharpness(of: cgImage)

        // LiDAR depth ma'lumotini saqlash — photogrammetry sifatini keskin oshiradi.
        if let depth = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap {
            saveDepthMap(depth, idx: idx)
        }

        // Gravity vektori (kamera koordinatalarida) — to'g'ri orientatsiya uchun.
        saveGravity(camera: frame.camera, idx: idx)

        // ARKit camera pose + intrinsics — AWS GPU pipeline COLMAP'ni o'tkazib
        // yuboradi. Capture tugagach bitta `poses.json` faylga yoziladi.
        recordPose(camera: frame.camera, idx: idx, timestamp: frame.timestamp, sharpness: sharpness)

        captureCount += 1

        // Coverage update — qaysi anchor'lar ushbu photo'da ko'rinadi.
        // Math'ni sync hisoblaymiz, main thread'da mutation + refresh.
        let visibleIds = computeVisibleAnchorIds(in: frame)
        // Phase 9.2: faqat sharp photo'lar coverage'ga ko'shilsin (sharp > 0.2).
        // Blurry rasm anchor'ni green qilmasin — user shu joyni qayta scan qilishi kerak.
        let isSharp = sharpness > 0.20

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Phase 9.1: haptic chiqaramiz silent indicator sifatida (sound o'rniga).
            self.captureHaptic.impactOccurred(intensity: 0.55)
            self.captureHaptic.prepare()
            self.photoPill.text = "\(self.captureCount) foto"
            self.updateHintVisibility()
            if self.captureCount < self.minRequiredPhotos {
                let blurMark = isSharp ? "" : " ⚠️ xira"
                self.statusLabel.text = "Foto: \(self.captureCount) / \(self.minRequiredPhotos)\(blurMark)"
            } else {
                let blurMark = isSharp ? "" : " ⚠️ xira — sekinroq harakat"
                self.statusLabel.text = "Foto: \(self.captureCount)\(blurMark)"
            }

            // Coverage counters: faqat sharp photo'lar hisobga olinadi.
            if isSharp {
                for id in visibleIds {
                    self.anchorCoverage[id, default: 0] += 1
                }
            }
            self.refreshAnchorVisualizations(anchorIds: visibleIds)
        }
        // Phase 9.1: triggerHiResCapture chaqirilmaydi (sound + async drift).
    }

    private func triggerHiResCapture(idx: Int) {
        pendingHiResLock.lock()
        pendingHiResCount += 1
        pendingHiResLock.unlock()

        Task { [weak self] in
            guard let self = self else { return }
            // Semaphore: max 3 ta concurrent hi-res. CVPixelBuffer'lar memory'da
            // to'planib OOM bo'lmasligi uchun.
            self.hiResSemaphore.wait()
            defer {
                self.hiResSemaphore.signal()
                self.pendingHiResLock.lock()
                self.pendingHiResCount -= 1
                self.pendingHiResLock.unlock()
            }
            do {
                let hiResFrame = try await self.arView.session.captureHighResolutionFrame()
                guard let hiResImg = self.makeCGImage(from: hiResFrame.capturedImage) else { return }
                let url = self.photoFolder.appendingPathComponent(
                    String(format: "photo_%04d.jpg", idx),
                )
                if let dest = CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.jpeg.identifier as CFString, 1, nil,
                ) {
                    let opts: [CFString: Any] = [
                        kCGImageDestinationLossyCompressionQuality: 0.95,
                    ]
                    CGImageDestinationAddImage(dest, hiResImg, opts as CFDictionary)
                    CGImageDestinationFinalize(dest)
                }
                // Phase 3.3: per-photo sharpness (variance of Laplacian, downsampled
                // grayscale). Atlas baker view-dependent blending uchun ishlatadi —
                // blurry foto'lar weight kamayadi.
                let sharpness = ImageQuality.sharpness(of: hiResImg)
                NSLog("KADASTR hi-res #\(idx) sharpness=\(String(format: "%.3f", sharpness))")
                // CRITICAL: hi-res frame'ning O'Z depth'ini saqlash (overwrite
                // low-res depth). Aks holda depth (T0) va image (T0+200ms) turli
                // pose'larda olingan → atlas baker occlusion noto'g'ri ishlaydi
                // → ekran content qo'shni mesh'ga "oqib o'tadi".
                let hiResDepthOpt = hiResFrame.smoothedSceneDepth?.depthMap
                    ?? hiResFrame.sceneDepth?.depthMap
                if let hiResDepth = hiResDepthOpt {
                    await MainActor.run {
                        self.saveDepthMap(hiResDepth, idx: idx)
                    }
                    NSLog("KADASTR hi-res #\(idx) depth synced ✓")
                } else {
                    NSLog("KADASTR hi-res #\(idx) depth=nil (Apple API limit)")
                }
                // Pose entry'ni hi-res frame'ning O'Z pose + intrinsics +
                // resolution bilan yangilaymiz — bu image-pose mismatch'ni hal qiladi.
                let t = hiResFrame.camera.transform
                let transformRows: [[Float]] = [
                    [t.columns.0.x, t.columns.1.x, t.columns.2.x, t.columns.3.x],
                    [t.columns.0.y, t.columns.1.y, t.columns.2.y, t.columns.3.y],
                    [t.columns.0.z, t.columns.1.z, t.columns.2.z, t.columns.3.z],
                    [t.columns.0.w, t.columns.1.w, t.columns.2.w, t.columns.3.w],
                ]
                let k = hiResFrame.camera.intrinsics
                let intrinsicsRows: [[Float]] = [
                    [k.columns.0.x, k.columns.1.x, k.columns.2.x],
                    [k.columns.0.y, k.columns.1.y, k.columns.2.y],
                    [k.columns.0.z, k.columns.1.z, k.columns.2.z],
                ]
                let resolution = hiResFrame.camera.imageResolution
                let hiResTs = hiResFrame.timestamp
                await MainActor.run {
                    if let i = self.capturedPoses.firstIndex(
                        where: { ($0["index"] as? Int) == idx },
                    ) {
                        self.capturedPoses[i]["transform_matrix"] = transformRows
                        self.capturedPoses[i]["intrinsics"] = intrinsicsRows
                        self.capturedPoses[i]["image_width"] = Int(resolution.width)
                        self.capturedPoses[i]["image_height"] = Int(resolution.height)
                        self.capturedPoses[i]["timestamp"] = hiResTs
                        self.capturedPoses[i]["sharpness"] = sharpness
                    }
                }
                NSLog("KADASTR hi-res #\(idx) OK \(hiResImg.width)×\(hiResImg.height)")
            } catch {
                NSLog("KADASTR hi-res #\(idx) FAILED: \(error.localizedDescription)")
            }
        }
    }

    /// Done bosilganda chaqiriladi — barcha pending hi-res capturelarni kutadi.
    private func waitForPendingHiRes(timeoutSeconds: TimeInterval = 30) async {
        let start = Date()
        while true {
            pendingHiResLock.lock()
            let pending = pendingHiResCount
            pendingHiResLock.unlock()
            if pending == 0 { return }
            if Date().timeIntervalSince(start) > timeoutSeconds {
                NSLog("KADASTR hi-res wait TIMEOUT: \(pending) hali kutilmoqda")
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Ushbu frame'da ko'rinadigan ARMeshAnchor'lar id'larini topadi.
    /// Mezon: anchor markazi camera oldida va 4.5 m'gacha masofada.
    private func computeVisibleAnchorIds(in frame: ARFrame) -> [UUID] {
        let camPos = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z,
        )
        let camFwd = -simd_normalize(SIMD3<Float>(
            frame.camera.transform.columns.2.x,
            frame.camera.transform.columns.2.y,
            frame.camera.transform.columns.2.z,
        ))
        var visible: [UUID] = []
        for anchor in frame.anchors {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            let center = SIMD3<Float>(
                mesh.transform.columns.3.x,
                mesh.transform.columns.3.y,
                mesh.transform.columns.3.z,
            )
            let toAnchor = center - camPos
            let dist = simd_length(toAnchor)
            if dist < 0.05 || dist > 4.5 { continue }
            let dirN = toAnchor / dist
            let align = simd_dot(camFwd, dirN)
            if align > 0.35 {  // ~70° dan kichik burchak (frustum yarmidan ko'p)
                visible.append(mesh.identifier)
            }
        }
        return visible
    }

    /// Belgilangan anchor'lar uchun SCN node visualization'ini yangilash.
    /// `applyPolycamStyle` yangi coverage rang bilan qayta qo'llaniladi.
    private func refreshAnchorVisualizations(anchorIds: [UUID]) {
        guard !anchorIds.isEmpty else { return }
        guard let session = arView?.session else { return }
        guard let frame = session.currentFrame else { return }
        for id in anchorIds {
            if let anchor = frame.anchors.first(where: { $0.identifier == id }) as? ARMeshAnchor {
                if let node = arView.node(for: anchor) {
                    applyPolycamStyle(to: node, meshAnchor: anchor)
                }
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
        let srcRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        // BUG FIX: CVPixelBuffer odatda bytesPerRow padded bo'ladi (e.g., 1280 vs
        // width*4=1024). Avval butun buffer'ni saqlardik, lekin padding bytes
        // depth qiymatlariga aralashar edi → TSDF/occlusion garbled.
        // Endi row-by-row tightly-packed (width × 4 bytes har row) saqlaymiz.
        let dstRowBytes = width * 4
        var body = Data(count: dstRowBytes * height)
        body.withUnsafeMutableBytes { dstRaw in
            guard let dst = dstRaw.baseAddress else { return }
            for row in 0..<height {
                let src = baseAddress.advanced(by: row * srcRowBytes)
                memcpy(dst.advanced(by: row * dstRowBytes), src, dstRowBytes)
            }
        }

        var header = Data()
        var w = Int32(width).littleEndian
        var h = Int32(height).littleEndian
        withUnsafeBytes(of: &w) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { header.append(contentsOf: $0) }

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
    private func recordPose(camera: ARCamera, idx: Int, timestamp: TimeInterval, sharpness: Float = 0.5) {
        // 4x4 transform — ARKit kamerasi koordinatalarida (camera-to-world).
        // Row-major JSON ([4][4]). Frame-based capture'da image va depth
        // bir vaqtda olinadi — alohida `depth_transform_matrix` kerak emas.
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
            "sharpness": sharpness,  // Phase 9.2: capture-time sharpness
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
        // Local processing mode — Polycam-style clay review: foydalanuvchi
        // mesh'ni aylantirib LiDAR hamma joyni olganini tekshiradi, keyin
        // "Process" tugmasi bilan asosiy pipeline boshlanadi.
        //
        // Done bosilganda AR session pause qilinadi — kamera "yopiladi",
        // background'da resurs sarflamaydi. Faqat mesh ko'rinib turadi.
        let meshGeom = MeshSnapshot.combine(arView: arView)
        isCapturing = false
        arView.session.pause()
        let review = MeshReviewViewController()
        review.previewGeometry = meshGeom
        review.photoCount = captureCount
        review.areaM2 = totalMeshAreaM2
        review.localProcessingMode = true  // quality picker yashir, "Process" btn
        review.modalPresentationStyle = .overFullScreen
        review.onConfirm = { [weak self] _ in
            // Phase 7: savingMode true → raw data save + exit, texturing yo'q
            // (foydalanuvchi profilda Process bossa to'liq pipeline boshlanadi).
            // savingMode false → eski flow: startProcessing.
            guard let self = self else { return }
            if self.savingMode {
                self.saveRawDataAndExit()
            } else {
                self.startProcessing()
            }
        }
        review.onRetake = { [weak self] in
            self?.dismiss(animated: true)
            self?.cleanupTempFolder()
            self?.onCancel?()
        }
        review.onContinue = { [weak self] in
            // Davom etish — AR session'ni qaytadan ishga tushirib capture'ga qaytamiz.
            guard let self = self else { return }
            self.resumeARSession()
        }
        present(review, animated: true)
    }

    @objc private func cancelTapped() {
        if isProcessing {
            processingTask?.cancel()
        }
        // Phase 7: offline mode'da photoFolder = SavedScanStorage'dagi saqlangan
        // folder. cleanupTempFolder uni o'chirib yuboradi → data loss! Faqat
        // live capture flow'da tmp folder cleanup qilamiz.
        if offlineScanId == nil {
            cleanupTempFolder()
        }
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

    // Phase 7.6: Offline TSDF voxel color reconstruction.
    /// Saqlangan anchors+poses+photos+depths'dan streaming TSDF qurib qaytaradi.
    /// Atlas baker voxel color fallback uchun ishlatadi → gray patches yo'qoladi.
    private func buildOfflineVoxelTSDF(
        anchors: [AnchorRaw],
        poses: [[String: Any]],
        photoFolder: URL,
        progress: ((Float) -> Void)? = nil,
    ) -> StreamingTSDF? {
        // 1. Mesh bounding box hisoblash → voxel grid center+extents
        guard let firstAnchor = anchors.first, !firstAnchor.worldVertices.isEmpty else {
            return nil
        }
        var bMin = firstAnchor.worldVertices[0]
        var bMax = bMin
        for anchor in anchors {
            for v in anchor.worldVertices {
                bMin = simd_min(bMin, v)
                bMax = simd_max(bMax, v)
            }
        }
        let center = (bMin + bMax) * 0.5
        let size = bMax - bMin
        // Padding: 1m on each side so cameras outside mesh bbox can still see in
        let extents = SIMD3<Float>(
            max(4, size.x + 2),
            max(3, size.y + 2),
            max(4, size.z + 2),
        )

        // 2. StreamingTSDF init
        // Phase 11: voxelSize 0.05 → 0.025 (2x maydaroq). Divan kabi yumshoq/mayda
        // mebel qiya burchakdan olinganda 5cm voxel yupqa/chala yuza berardi.
        // 2.5cm voxel detail va hole-fill geometriyani yaxshilaydi (8x voxel,
        // ~120-190MB — offline reprocess'da xotira yetarli).
        guard let tsdf = StreamingTSDF(
            centerWorld: center,
            extents: extents,
            voxelSize: 0.025,
            truncation: 0.08,
            maxIntegrationDepth: 4.0,
        ) else {
            return nil
        }

        // 3. Iterate poses → integrate har photo
        let total = poses.count
        var skippedNoFields = 0
        for (i, pose) in poses.enumerated() {
            guard let idx = pose["index"] as? Int,
                  let tRows = Self.parseFloatMatrix(pose["transform_matrix"], rows: 4, cols: 4),
                  let kRows = Self.parseFloatMatrix(pose["intrinsics"], rows: 3, cols: 3)
            else { skippedNoFields += 1; continue }
            let imgW: Int
            let imgH: Int
            if let n = pose["image_width"] as? NSNumber { imgW = n.intValue }
            else if let i = pose["image_width"] as? Int { imgW = i } else { skippedNoFields += 1; continue }
            if let n = pose["image_height"] as? NSNumber { imgH = n.intValue }
            else if let i = pose["image_height"] as? Int { imgH = i } else { skippedNoFields += 1; continue }
            let imgURL = photoFolder.appendingPathComponent(String(format: "photo_%04d.jpg", idx))
            let depthURL = photoFolder.appendingPathComponent(String(format: "depth_%04d.bin", idx))
            guard FileManager.default.fileExists(atPath: imgURL.path),
                  FileManager.default.fileExists(atPath: depthURL.path)
            else { continue }

            // Load depth bin (header: Int32 w, Int32 h, then float32 array)
            guard let depthData = try? Data(contentsOf: depthURL), depthData.count >= 8 else { continue }
            let dw = Int(depthData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) })
            let dh = Int(depthData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) })
            let pixCount = dw * dh
            guard pixCount > 0, depthData.count >= 8 + pixCount * 4 else { continue }
            var depth = [Float](repeating: 0, count: pixCount)
            depth.withUnsafeMutableBufferPointer { buf in
                depthData.withUnsafeBytes { raw in
                    let src = raw.baseAddress!.advanced(by: 8).assumingMemoryBound(to: Float.self)
                    memcpy(buf.baseAddress, src, pixCount * 4)
                }
            }

            // Build matrices
            let t = simd_float4x4(rows: [
                SIMD4<Float>(tRows[0][0], tRows[0][1], tRows[0][2], tRows[0][3]),
                SIMD4<Float>(tRows[1][0], tRows[1][1], tRows[1][2], tRows[1][3]),
                SIMD4<Float>(tRows[2][0], tRows[2][1], tRows[2][2], tRows[2][3]),
                SIMD4<Float>(tRows[3][0], tRows[3][1], tRows[3][2], tRows[3][3]),
            ])
            let k = simd_float3x3(rows: [
                SIMD3<Float>(kRows[0][0], kRows[0][1], kRows[0][2]),
                SIMD3<Float>(kRows[1][0], kRows[1][1], kRows[1][2]),
                SIMD3<Float>(kRows[2][0], kRows[2][1], kRows[2][2]),
            ])

            tsdf.integrateOffline(
                depth: depth, depthW: dw, depthH: dh,
                imageURL: imgURL,
                cameraTransform: t,
                intrinsics: k,
                imageWidth: Float(imgW),
                imageHeight: Float(imgH),
            )
            // Progress har 10 photoda
            if i % 10 == 0 {
                progress?(Float(i) / Float(max(total, 1)))
            }
        }
        if skippedNoFields > 0 {
            NSLog("KADASTR buildOfflineVoxelTSDF: skipped \(skippedNoFields)/\(total) frames due to missing/invalid fields")
        }
        progress?(1.0)
        return tsdf
    }

    // Phase 7: Save raw data (Done bossa, texturing'siz exit).
    /// Hi-res photolarni kutadi → poses.json yozadi → anchor mesh'ni serialize
    /// qiladi → SavedScanStorage'ga ko'chiradi → onSavedRaw chaqiradi.
    private func saveRawDataAndExit() {
        if isProcessing { return }
        isProcessing = true
        processingOverlay.isHidden = false
        progressView.progress = 0
        processingStatusLabel.text = "Hi-res fotolarni saqlash…"
        DebugLog.log("SAVE", "saveRawDataAndExit started")

        processingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            // 1. Pending hi-res tugashini kutamiz (max 60s — Done bosildi, lekin
            //    asinx 12 MP captures hali ham tugamagan bo'lishi mumkin)
            DebugLog.log("SAVE", "waiting for pending hi-res")
            await self.waitForPendingHiRes(timeoutSeconds: 60)

            // 2. poses.json yozish (main thread'da capturedPoses access)
            await MainActor.run {
                self.writePosesJson()
                self.processingStatusLabel.text = "ARKit mesh saqlash…"
                self.progressView.setProgress(0.5, animated: true)
            }

            // 3. Anchor mesh serialize (main thread'da arView access)
            let anchorData: [AnchorRaw] = await MainActor.run {
                Self.extractAnchorData(arView: self.arView)
            }
            let serialized = anchorData.map { $0.toSerialized() }
            let anchorsBin = AnchorSerializer.serialize(serialized)
            DebugLog.log("SAVE", "anchors: \(anchorData.count), bin size: \(anchorsBin.count)")

            // 4. Photo'larni sanab ko'rish — qancha haqiqatda diskda bor
            let photoCount = await MainActor.run { self.captureCount }
            let area = await MainActor.run { self.totalMeshAreaM2 }
            let srcFolder = await MainActor.run { self.photoFolder! }
            let actualPhotos = (try? FileManager.default.contentsOfDirectory(
                at: srcFolder, includingPropertiesForKeys: nil,
            ))?.filter { $0.pathExtension == "jpg" }.count ?? 0
            DebugLog.log("SAVE", "photos: counter=\(photoCount), actual=\(actualPhotos), folder=\(srcFolder.path)")

            // 5. SavedScanStorage'ga ko'chirish — actualPhotos ishlatamiz
            let scanId = SavedScanStorage.saveScan(
                sourcePhotoFolder: srcFolder,
                anchorsData: anchorsBin,
                photoCount: actualPhotos,
                areaSqm: Double(area),
            )
            DebugLog.log("SAVE", "saved as scan #\(scanId)")

            // 6. Cleanup tmp + callback
            await MainActor.run {
                self.cleanupTempFolder()
                self.processingStatusLabel.text = "Saqlandi (#\(scanId))"
                self.progressView.setProgress(1.0, animated: true)
                self.onSavedRaw?(scanId)
            }
        }
    }

    // Phase 7: Offline reprocess — saqlangan scan'dan texturing.
    /// Loads anchors + poses + photos from SavedScanStorage, runs the same
    /// runCustomMeshExport pipeline, va outputni storage'ga ro'yxatdan
    /// o'tkazadi. onOfflineFinished(URL, version) chaqiriladi.
    private func startOfflineProcessing(scanId: Int) {
        DebugLog.log("OFFLINE", "START scanId=\(scanId), isProcessing=\(isProcessing)")
        if isProcessing { return }
        isProcessing = true
        processingOverlay.isHidden = false
        progressView.progress = 0
        processingStatusLabel.text = "Boshlanmoqda…"

        processingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                DebugLog.log("OFFLINE", "self deallocated")
                return
            }
            do {
                DebugLog.log("OFFLINE", "step 1: loading anchors")
                await MainActor.run {
                    self.processingStatusLabel.text = "Anchor mesh yuklanmoqda…"
                    self.progressView.setProgress(0.05, animated: true)
                }
                guard let anchorsData = SavedScanStorage.loadAnchorsData(id: scanId) else {
                    DebugLog.log("OFFLINE", "FAIL: anchors.bin not found for scanId=\(scanId)")
                    throw NSError(
                        domain: "OfflineProcess", code: 10,
                        userInfo: [NSLocalizedDescriptionKey: "Anchor mesh topilmadi"],
                    )
                }
                DebugLog.log("OFFLINE", "anchors.bin size: \(anchorsData.count) bytes")

                let serialized = AnchorSerializer.deserialize(anchorsData)
                DebugLog.log("OFFLINE", "deserialized \(serialized.count) anchors")
                let anchors: [AnchorRaw] = serialized.map { AnchorRaw.fromSerialized($0) }
                guard !anchors.isEmpty else {
                    DebugLog.log("OFFLINE", "FAIL: empty anchor array")
                    throw NSError(
                        domain: "OfflineProcess", code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "Anchor data bo'sh"],
                    )
                }
                let totalTri = anchors.reduce(0) { $0 + $1.indices.count / 3 }
                DebugLog.log("OFFLINE", "anchors: \(anchors.count) anchors, \(totalTri) tri")

                DebugLog.log("OFFLINE", "step 2: loading poses.json")
                let photoFolder = SavedScanStorage.photoFolder(id: scanId)
                let posesURL = photoFolder.appendingPathComponent("poses.json")
                guard let data = try? Data(contentsOf: posesURL) else {
                    DebugLog.log("OFFLINE", "FAIL: poses.json read at \(posesURL.path)")
                    throw NSError(
                        domain: "OfflineProcess", code: 12,
                        userInfo: [NSLocalizedDescriptionKey: "poses.json topilmadi"],
                    )
                }
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DebugLog.log("OFFLINE", "FAIL: poses.json JSON parse")
                    throw NSError(
                        domain: "OfflineProcess", code: 12,
                        userInfo: [NSLocalizedDescriptionKey: "poses.json noto'g'ri JSON"],
                    )
                }
                guard let poses = root["frames"] as? [[String: Any]] else {
                    DebugLog.log("OFFLINE", "FAIL: poses.json no 'frames' field")
                    throw NSError(
                        domain: "OfflineProcess", code: 12,
                        userInfo: [NSLocalizedDescriptionKey: "poses.json frames yo'q"],
                    )
                }
                DebugLog.log("OFFLINE", "poses loaded: \(poses.count) frames")

                // 3. State'ni inject
                DebugLog.log("OFFLINE", "step 3: injecting state")
                await MainActor.run {
                    self.photoFolder = photoFolder
                    self.capturedPoses = poses
                    self.captureCount = poses.count
                }

                // 3b. Phase 7.6: voxel color reconstruction from saved photos.
                // Live mode'da streamingTSDF capture vaqtida har frame'da rang
                // to'playdi. Offline mode'da uni saqlangan photo+depth+pose
                // dan re-build qilamiz → atlas baker'da voxel fallback ishlaydi
                // → gray patches yo'qoladi.
                DebugLog.log("OFFLINE", "step 3b: reconstructing voxel colors from \(poses.count) frames")
                await MainActor.run {
                    self.processingStatusLabel.text = "Voxel ranglar tiklanmoqda…"
                    self.progressView.setProgress(0.05, animated: true)
                }
                let tsdfStart = Date()
                if let voxelTSDF = self.buildOfflineVoxelTSDF(
                    anchors: anchors,
                    poses: poses,
                    photoFolder: photoFolder,
                    progress: { p in
                        Task { @MainActor in
                            self.progressView.setProgress(0.05 + p * 0.10, animated: false)
                            self.processingStatusLabel.text = "Voxel ranglar: \(Int(p * 100))%"
                        }
                    },
                ) {
                    let elapsed = Date().timeIntervalSince(tsdfStart)
                    DebugLog.log("OFFLINE", String(format: "voxel TSDF built in %.1fs (%d frames)", elapsed, voxelTSDF.integratedFrameCount))
                    await MainActor.run {
                        self.streamingTSDF = voxelTSDF
                    }
                } else {
                    DebugLog.log("OFFLINE", "voxel TSDF build SKIPPED")
                }

                let tmpOutput = FileManager.default.temporaryDirectory
                    .appendingPathComponent("offline_\(scanId)_\(UUID().uuidString).usdz")
                DebugLog.log("OFFLINE", "step 4: output URL = \(tmpOutput.lastPathComponent)")

                self.offlineAnchorOverride = anchors
                DebugLog.log("OFFLINE", "step 5: starting runCustomMeshExport")

                try await self.runCustomMeshExport(output: tmpOutput)
                DebugLog.log("OFFLINE", "step 6: mesh export ✓")

                let params = self.offlineParams
                guard let version = SavedScanStorage.addOutput(
                    scanId: scanId, sourceUsdzURL: tmpOutput, params: params,
                ) else {
                    DebugLog.log("OFFLINE", "FAIL: addOutput")
                    throw NSError(
                        domain: "OfflineProcess", code: 13,
                        userInfo: [NSLocalizedDescriptionKey: "Output saqlanmadi"],
                    )
                }
                guard let outURL = SavedScanStorage.outputURL(scanId: scanId, version: version) else {
                    DebugLog.log("OFFLINE", "FAIL: outputURL not found")
                    throw NSError(
                        domain: "OfflineProcess", code: 14,
                        userInfo: [NSLocalizedDescriptionKey: "Output URL topilmadi"],
                    )
                }
                DebugLog.log("OFFLINE", "DONE scanId=\(scanId), v=\(version)")
                await MainActor.run {
                    self.onOfflineFinished?(outURL, version)
                }
            } catch {
                if Task.isCancelled {
                    DebugLog.log("OFFLINE", "cancelled")
                    return
                }
                DebugLog.log("OFFLINE", "EXCEPTION: \(error.localizedDescription)")
                await MainActor.run {
                    self.onError?(error)
                }
            }
        }
    }

    private func startProcessing() {
        isProcessing = true
        arView.session.pause()
        processingOverlay.isHidden = false
        progressView.progress = 0
        processingStatusLabel.text = "Boshlanmoqda…"

        let folder = photoFolder!
        // Numbered local storage — LocalScanIndex.reserveNewScanURL() Documents/scans/
        // ichida scan_NNN.usdz tayyorlaydi. Saqlangach registerScan(...).
        let reserved = LocalScanIndex.reserveNewScanURL()
        let outputURL = reserved.url
        let scanId = reserved.id
        let scanFileName = reserved.fileName

        processingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            do {
                // Hi-res captures kutamiz — async 12 MP photo'lar tugashi kerak,
                // aks holda low-res ishlatamiz.
                await MainActor.run {
                    self.processingStatusLabel.text = "Hi-res photo'lar yakunlanmoqda…"
                }
                await self.waitForPendingHiRes(timeoutSeconds: 30)

                // Custom mesh export — Apple PhotogrammetrySession O'RNIGA
                // ARKit scene mesh anchorslarni to'g'ridan-to'g'ri USDZ qilamiz.
                // (PhotogrammetrySession iOS'da single-obyekt only, room scan'ga
                // yaramaydi. Bizning custom yo'l: LiDAR mesh real-time ARKit'da
                // qurilgan — uni shunchaki birlashtirib export qilamiz.)
                let totalArea = await MainActor.run { self.totalMeshAreaM2 }
                let photoCount = await MainActor.run { self.captureCount }
                try await self.runCustomMeshExport(output: outputURL)
                let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
                let fileSize = (attrs?[.size] as? Int) ?? 0
                // Register in local index — Skanlarim ekranida ko'rinadi
                LocalScanIndex.registerScan(
                    id: scanId, fileName: scanFileName,
                    areaSqm: Double(totalArea), photoCount: photoCount,
                )
                NSLog("KADASTR scan saved: id=\(scanId), file=\(scanFileName), size=\(fileSize)")
                await MainActor.run {
                    self.cleanupTempFolder()
                    self.onFinished?(outputURL, TexturedScanStats(
                        floorAreaSqm: Double(totalArea),
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

    /// Custom texture atlas pipeline — **Bosqich 1**: per-anchor single-camera
    /// UV projection.
    ///
    /// Algoritm:
    /// 1. ARKit'dan har ARMeshAnchor va capture vaqtidagi camera pose'larni olish
    /// 2. Har anchor uchun eng yaxshi camera tanlash (yaqin + perpendicular)
    /// 3. Anchor mesh vertex'larini shu camera'ga proyeksiya qilib UV hisoblash
    /// 4. SCNGeometry (vertex + normal + UV texcoord) yaratish
    /// 5. Material diffuse = camera JPG image
    /// 6. Har anchor uchun alohida SCNNode (multi-material USDZ)
    ///
    /// USDZ format vertex color qo'llab-quvvatlamaydi — texture image + UV
    /// majburiy. Shu sababli per-anchor texture mapping.
    private func runCustomMeshExport(output: URL) async throws {
        DebugLog.log("MESH", "runCustomMeshExport ENTER output=\(output.lastPathComponent)")
        await MainActor.run {
            self.processingStatusLabel.text = "Extracting mesh…"
            self.progressView.setProgress(0.10, animated: true)
        }

        // Phase 7: offline mode'da anchor data oldindan inject qilingan
        // (saqlangan binary fayldan). Aks holda live ARKit dan extract.
        DebugLog.log("MESH", "runCustomMeshExport: offlineAnchorOverride.isNil=\(offlineAnchorOverride == nil)")
        let anchorData: [AnchorRaw]
        if let injected = offlineAnchorOverride {
            anchorData = injected
            DebugLog.log("MESH", "using \(injected.count) injected anchors")
        } else {
            anchorData = await MainActor.run {
                Self.extractAnchorData(arView: self.arView)
            }
            DebugLog.log("MESH", "extracted \(anchorData.count) live anchors")
        }
        DebugLog.log("MESH", "step a: reading poses + folder")
        let poses: [[String: Any]] = await MainActor.run { self.capturedPoses }
        DebugLog.log("MESH", "poses array size = \(poses.count)")
        let folder: URL = await MainActor.run { self.photoFolder! }
        DebugLog.log("MESH", "photoFolder = \(folder.lastPathComponent)")

        guard !anchorData.isEmpty else {
            throw NSError(
                domain: "TexturedScan", code: 100,
                userInfo: [NSLocalizedDescriptionKey:
                    "LiDAR mesh topilmadi — yana skan qiling"],
            )
        }

        // Pose'larni structured form'da o'qish.
        DebugLog.log("MESH", "step b: parseCameras")
        let cameras = Self.parseCameras(poses: poses, folder: folder)
        DebugLog.log("MESH", "parseCameras → \(cameras.count) cameras")
        guard !cameras.isEmpty else {
            DebugLog.log("MESH", "FAIL: cameras empty")
            throw NSError(
                domain: "TexturedScan", code: 102,
                userInfo: [NSLocalizedDescriptionKey:
                    "Foto'lar topilmadi (pose metadata yo'q)"],
            )
        }

        // Phase 4.1: Loop closure detection OLIB TASHLANDI.
        // - Diagnostic only (pose'larni o'zgartirmaydi)
        // - 24+ photo bilan Vision framework memory'da 1+ GB egallaydi → crash
        // - Phase 3.2 (Light BA) drift kompensatsiyasi shu ish qilyapti
        DebugLog.log("MESH", "step c: skipping loop closure detection (was crashing)")
        await MainActor.run {
            self.processingStatusLabel.text = "Refining cameras…"
            self.progressView.setProgress(0.10, animated: true)
        }
        DebugLog.log("MESH", "step d: loop closure skipped")

        await MainActor.run {
            self.processingStatusLabel.text =
                "\(anchorData.count) mesh + \(cameras.count) foto qayta ishlanmoqda…"
            self.progressView.setProgress(0.35, animated: true)
        }

        // Per-triangle camera selection — har triangle uchun alohida eng
        // yaxshi camera tanlanadi (perpendicular alignment + close distance +
        // all 3 vertices visible). Triangle'lar best camera index bo'yicha
        // group'lanadi, har group alohida SCNGeometry + texture material.
        let scene = SCNScene()

        // 1. ARKit anchor mesh'larini birlashtirish (Phase 1 — sharp tekstura
        //    yaxshi ishladi). TSDF o'rniga **boundary hole filling** ishlatamiz —
        //    mavjud mesh saqlanadi, faqat hole'lar to'ldiriladi.
        var rawVerts: [SIMD3<Float>] = []
        var rawNormals: [SIMD3<Float>] = []
        var rawTris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        for anchor in anchorData {
            let base = UInt32(rawVerts.count)
            rawVerts.append(contentsOf: anchor.worldVertices)
            rawNormals.append(contentsOf: anchor.worldNormals)
            var i = 0
            while i + 2 < anchor.indices.count {
                rawTris.append((
                    anchor.indices[i] + base,
                    anchor.indices[i + 1] + base,
                    anchor.indices[i + 2] + base,
                ))
                i += 3
            }
        }
        guard !rawVerts.isEmpty else {
            throw NSError(
                domain: "TexturedScan", code: 105,
                userInfo: [NSLocalizedDescriptionKey: "ARKit mesh bo'sh"],
            )
        }
        NSLog("KADASTR ARKit raw: \(rawVerts.count) vert, \(rawTris.count) tri")

        // 1a-pre. RoomPlan surfaces — devor/eshik/oyna detect qilingan plane'lar.
        //         Glass eshik / silliq metal kabi LiDAR ko'rmagan yuzalarni
        //         to'liq plane bilan to'ldiradi. Ular Photo'lardan textur oladi
        //         (xatlas + Metal bake o'sha ishni qiladi).
        #if canImport(RoomPlan)
        if #available(iOS 16.0, *), let room = capturedRoomData as? CapturedRoom {
            let mesh = RoomPlanSurfaceMesher.surfaceMesh(from: room)
            let baseIdx = UInt32(rawVerts.count)
            rawVerts.append(contentsOf: mesh.verts)
            rawNormals.append(contentsOf: mesh.normals)
            for tri in mesh.tris {
                rawTris.append((
                    v0: tri.v0 + baseIdx,
                    v1: tri.v1 + baseIdx,
                    v2: tri.v2 + baseIdx,
                ))
            }
            NSLog("KADASTR RoomPlan added: \(room.walls.count) walls + \(room.doors.count) doors + \(room.windows.count) windows + \(room.openings.count) openings = \(mesh.tris.count) tri")
        } else {
            NSLog("KADASTR RoomPlan: capturedRoomData yo'q (RoomPlan ishlamadi yoki iOS < 16)")
        }
        #endif

        // 1a. Hybrid TSDF — ARKit ko'rmagan joylar uchun depth maps'dan TSDF
        //     hole fill quradi. ARKit triangle'lari saqlanadi (sharp texture),
        //     TSDF'dan faqat hole'da yotgan triangle'lar qo'shiladi.

        // BBox hisoblash (TSDF grid uchun)
        var bMin = rawVerts[0]
        var bMax = rawVerts[0]
        for v in rawVerts {
            bMin = simd_min(bMin, v)
            bMax = simd_max(bMax, v)
        }

        await MainActor.run {
            self.processingStatusLabel.text = "Refining depth maps…"
            self.progressView.setProgress(0.18, animated: true)
        }

        let tsdfCameras: [TSDFInputCamera] = cameras.compactMap { cam in
            let depthURL = cam.imageURL.deletingLastPathComponent()
                .appendingPathComponent(String(format: "depth_%04d.bin", cam.index))
            guard FileManager.default.fileExists(atPath: depthURL.path) else { return nil }
            // TSDF uchun depth pose ishlatiladi (depth low-res frame'da olingan,
            // image pose hi-res frame'da). Aks holda ~6 sm drift hole-fill mesh'da.
            return TSDFInputCamera(
                transform: cam.depthTransform,
                intrinsics: cam.intrinsics,
                imageWidth: cam.imageW,
                imageHeight: cam.imageH,
                depthURL: depthURL,
                depthWidth: cam.depthW > 0 ? cam.depthW : 256,
                depthHeight: cam.depthH > 0 ? cam.depthH : 192,
            )
        }

        // TSDF chiqarish — agar muvaffaqiyatsiz bo'lsa, ARKit mesh o'sha holicha
        // ishlatiladi (degrade gracefully).
        var hybridVerts = rawVerts
        var hybridNormals = rawNormals
        var hybridTris = rawTris

        // Variant A: streaming TSDF (capture davomida real-time accumulated) ni
        // ishlatamiz batch TSDF o'rniga. Capture davomida ~12 fps integration
        // bo'lib turgan, mesh kvalitati ARKit anchor mesh'idan ham yaxshi.
        // Fallback: streaming TSDF mavjud emas yoki bo'sh bo'lsa, batch TSDF.
        await MainActor.run {
            self.processingStatusLabel.text = "Refining depth maps…"
            self.progressView.setProgress(0.20, animated: true)
        }
        let streamFrames = streamingTSDF?.integratedFrameCount ?? 0
        NSLog("KADASTR StreamingTSDF: \(streamFrames) frames integrated during capture")

        if let streamMesh = streamingTSDF?.extractMesh(), streamMesh.vertices.count > 100 {
            NSLog("KADASTR StreamingTSDF mesh: \(streamMesh.vertices.count) vert, \(streamMesh.triangles.count) tri")
            if ProcessInfo.processInfo.environment["KADASTR_TSDF_ONLY"] == "1" {
                // DEBUG: ARKit'ni butunlay chetlab, faqat TSDF mesh — divan TSDF'da
                // yaxshiroqmi tekshirish uchun.
                hybridVerts = streamMesh.vertices
                hybridNormals = streamMesh.normals
                hybridTris = streamMesh.triangles
                NSLog("KADASTR TSDF-ONLY mode: \(streamMesh.triangles.count) tri (ARKit chetlandi)")
            } else {
                // Hybrid: ARKit + streaming TSDF (TSDF hole-fill rolida)
                let hybrid = HybridMeshBuilder.combine(
                    arkitVerts: rawVerts, arkitNormals: rawNormals, arkitTris: rawTris,
                    tsdfVerts: streamMesh.vertices, tsdfNormals: streamMesh.normals,
                    tsdfTris: streamMesh.triangles,
                    minDistanceFromArkit: 0.06,
                )
                hybridVerts = hybrid.vertices
                hybridNormals = hybrid.normals
                hybridTris = hybrid.triangles
                NSLog("KADASTR hybrid (streaming): \(hybrid.arkitCount) ARKit + \(hybrid.fillCount) stream = \(hybrid.triangles.count) total")
            }
        } else if !tsdfCameras.isEmpty {
            // Fallback: eski batch TSDF
            do {
                let tsdfResult = try TSDFReconstructor.reconstruct(
                    boundingMin: bMin, boundingMax: bMax, cameras: tsdfCameras,
                    voxelSize: 0.04,
                    truncation: 0.10,
                    maxIntegrationDepth: 4.0,
                    progress: { p, _ in
                        Task { @MainActor in
                            self.processingStatusLabel.text = "Refining depth maps…"
                            self.progressView.setProgress(0.18 + p * 0.12, animated: false)
                        }
                    },
                )
                NSLog("KADASTR batch TSDF: \(tsdfResult.vertices.count) vert, \(tsdfResult.triangles.count) tri")
                let hybrid = HybridMeshBuilder.combine(
                    arkitVerts: rawVerts, arkitNormals: rawNormals, arkitTris: rawTris,
                    tsdfVerts: tsdfResult.vertices, tsdfNormals: tsdfResult.normals,
                    tsdfTris: tsdfResult.triangles,
                    minDistanceFromArkit: 0.06,
                )
                hybridVerts = hybrid.vertices
                hybridNormals = hybrid.normals
                hybridTris = hybrid.triangles
                NSLog("KADASTR hybrid (batch): \(hybrid.arkitCount) ARKit + \(hybrid.fillCount) fill = \(hybrid.triangles.count) total")
            } catch {
                NSLog("KADASTR TSDF failed (skip hole fill): \(error.localizedDescription)")
            }
        }

        // 1b. Mesh boundary cleanup (Phase A) — anchor chegaralarini ulash,
        //     sliver tri'larni o'chirish, kichik fragmentlarni tashlash, kichik
        //     hole'larni ear-clipping bilan to'ldirish (fan spike yo'q).
        await MainActor.run {
            self.processingStatusLabel.text = "Extracting mesh…"
            self.progressView.setProgress(0.30, animated: true)
        }
        let cleaned = MeshCleaner.clean(
            vertices: hybridVerts, normals: hybridNormals, triangles: hybridTris,
            weldEpsilon: 0.025,          // 2.5 sm — yengilroq anchor merge
            minComponentTris: 12,        // 12 tri'dan kam fragment → tashlash (yumshoq)
            slimAspectThreshold: 0.005,  // juda thin triangle'larnigina (yumshoq)
            maxHoleBoundary: 16,         // ≤16 edge hole'lar (kengroq)
        )

        // 1c. Camera coverage filter — Polycam-style focus crop.
        //     Har triangle markazini camera frustum'iga proyeksiya qilib,
        //     necha cameradan ko'ringanini hisoblaydi. < 3 camera → drop.
        //     Periferyada brief ko'ringan devor/pol fragmentlari kesiladi.
        await MainActor.run {
            self.processingStatusLabel.text = "Focus crop (camera coverage)…"
            self.progressView.setProgress(0.32, animated: true)
        }
        let coverageCams = cameras.map { cam in
            MeshCleaner.CoverageCamera(
                position: cam.position,
                forward: cam.forward,
                invTransform: cam.transform.inverse,
                intrinsics: cam.intrinsics,
                imageW: cam.imageW,
                imageH: cam.imageH,
            )
        }
        let coverageFiltered = MeshCleaner.filterByCameraCoverage(
            vertices: cleaned.vertices,
            normals: cleaned.normals,
            triangles: cleaned.triangles,
            cameras: coverageCams,
            minCoverage: 1,     // 1+ camera — xona to'liq qoladi
            coneCosine: 0.3,    // ~73° — kengroq cone
            maxDistance: 8.0,   // atlas baker bilan mos
        )

        // 1d. Largest Connected Component filter — qolgan disconnected
        //     fragmentlarni tashlash. minSizeRatio 0.40 (eng katta'ning 40%'idan
        //     kichik component'lar drop).
        await MainActor.run {
            self.processingStatusLabel.text = "Cleaning floating fragments…"
            self.progressView.setProgress(0.34, animated: true)
        }
        let lccFiltered = MeshCleaner.keepLargestComponent(
            vertices: coverageFiltered.vertices,
            normals: coverageFiltered.normals,
            triangles: coverageFiltered.triangles,
            minSizeRatio: 0.10,   // 0.40 → 0.10: faqat juda kichik isolated parchalar drop
        )

        // Phase 11: Taubin smoothing 5 iter (λ=0.35 yengil, µ=-0.38 shrink-free band-pass).
        // Yuqori-chastotali ARKit LiDAR noise'ni tekislaydi; divan tufting kabi katta
        // xususiyatlar saqlanadi. Eslatma: devorning PAST-chastotali to'lqini (LiDAR
        // depth drift) Taubin bilan ketmaydi — buning uchun planar fit kerak (kelajak).
        // Sinaб ko'rildi: 10 iter ham past-chastota to'lqinni o'zgartirmadi → 5 yetarli.
        await MainActor.run {
            self.processingStatusLabel.text = "Smoothing mesh…"
            self.progressView.setProgress(0.35, animated: true)
        }
        let smoothed = MeshCleaner.taubinSmooth(
            vertices: lccFiltered.vertices,
            normals: lccFiltered.normals,
            triangles: lccFiltered.triangles,
            lambda: 0.35,
            mu: -0.38,
            iterations: 5,
        )
        let globalVerts = smoothed.vertices
        let globalNormals = smoothed.normals
        let globalTris = smoothed.triangles
        await MainActor.run {
            self.processingStatusLabel.text = "Extracting mesh… \(globalTris.count) tri"
            self.progressView.setProgress(0.34, animated: true)
        }

        // CLAY rejim: faqat geometriya (textura'siz). Atlas bake + ESRGAN
        // o'tkazib yuboriladi → tez. Foydalanuvchi mesh shaklini ko'rishi uchun.
        if self.offlineParams["clay"] == "1" {
            NSLog("KADASTR CLAY mode: atlas bake o'tkazildi, flat material")
            await MainActor.run {
                self.processingStatusLabel.text = "Clay mesh (geometriya)…"
                self.progressView.setProgress(0.6, animated: true)
            }
            var clayIdx: [UInt32] = []
            clayIdx.reserveCapacity(globalTris.count * 3)
            for t in globalTris { clayIdx.append(t.v0); clayIdx.append(t.v1); clayIdx.append(t.v2) }
            let clayUVs = [SIMD2<Float>](repeating: .zero, count: globalVerts.count)
            let clayGeom = Self.buildSubMeshGeometry(
                vertices: globalVerts, normals: globalNormals, uvs: clayUVs, indices: clayIdx,
            )
            let clayMat = SCNMaterial()
            clayMat.lightingModel = .physicallyBased
            clayMat.diffuse.contents = UIColor(white: 0.74, alpha: 1.0)
            clayMat.roughness.contents = 0.9
            clayMat.metalness.contents = 0.0
            clayMat.isDoubleSided = true
            clayGeom.materials = [clayMat]
            scene.rootNode.addChildNode(SCNNode(geometry: clayGeom))
            let okClay = scene.write(to: output, options: nil, delegate: nil, progressHandler: nil)
            if !okClay {
                throw NSError(
                    domain: "TexturedScan", code: 102,
                    userInfo: [NSLocalizedDescriptionKey: "Clay USDZ saqlash muvaffaqiyatsiz"],
                )
            }
            await MainActor.run { self.progressView.setProgress(1.0, animated: true) }
            return
        }

        await MainActor.run {
            self.processingStatusLabel.text = "Extracting mesh ✓"
            self.progressView.setProgress(0.38, animated: true)
        }
        NSLog("KADASTR Pre-atlas: \(globalVerts.count) vert, \(globalTris.count) tri")

        // Phase 3.2: light bundle adjustment via depth→mesh ICP. Har photo'ning
        // pose'ini cleaned mesh'ga moslaymiz, ARKit drift'ini kompensatsiya
        // qilamiz. Bu atlas seam'larni kamaytiradi.
        await MainActor.run {
            self.processingStatusLabel.text = "Refining poses (light BA)…"
            self.progressView.setProgress(0.36, animated: true)
        }
        let photoSamples: [PhotoDepthSample] = cameras.compactMap { cam in
            let depthURL = cam.imageURL.deletingLastPathComponent()
                .appendingPathComponent(String(format: "depth_%04d.bin", cam.index))
            guard FileManager.default.fileExists(atPath: depthURL.path) else { return nil }
            return PhotoDepthSample(
                index: cam.index,
                pose: cam.transform,
                intrinsics: cam.intrinsics,
                depthURL: depthURL,
                depthWidth: cam.depthW > 0 ? cam.depthW : 256,
                depthHeight: cam.depthH > 0 ? cam.depthH : 192,
                imageWidth: cam.imageW,
                imageHeight: cam.imageH,
            )
        }
        let refinedPoses: [simd_float4x4]
        if photoSamples.count >= 8 && globalVerts.count > 500 {
            // Phase 8: ICP progress range widened 0.36→0.55 (uzoq bosqich, 3% emas, 19%)
            refinedPoses = await PoseRefiner.refinePosesViaICP(
                photos: photoSamples,
                meshVertices: globalVerts,
                voxelSize: 0.05,
                iterations: 3,
                maxCorrespondenceDistance: 0.10,
                dampingFactor: 0.6,
                progress: { p, msg in
                    Task { @MainActor in
                        self.processingStatusLabel.text = msg
                        self.progressView.setProgress(0.36 + p * 0.19, animated: false)
                    }
                },
            )
            // Diagnostic: o'rtacha translation delta
            var totalDelta: Float = 0
            for (i, sample) in photoSamples.enumerated() {
                let oldT = SIMD3<Float>(sample.pose.columns.3.x, sample.pose.columns.3.y, sample.pose.columns.3.z)
                let newT = SIMD3<Float>(refinedPoses[i].columns.3.x, refinedPoses[i].columns.3.y, refinedPoses[i].columns.3.z)
                totalDelta += simd_distance(oldT, newT)
            }
            let avgDelta = totalDelta / Float(max(photoSamples.count, 1))
            NSLog("KADASTR PoseRefiner: \(photoSamples.count) photos, avg drift \(String(format: "%.1f", avgDelta * 1000)) mm")
        } else {
            refinedPoses = photoSamples.map { $0.pose }
            NSLog("KADASTR PoseRefiner: skipped (\(photoSamples.count) photos, \(globalVerts.count) vert)")
        }
        // Refined pose mapping by camera index → o'lcham/order o'zgarmaydi.
        var refinedByIndex: [Int: simd_float4x4] = [:]
        for (i, sample) in photoSamples.enumerated() {
            refinedByIndex[sample.index] = refinedPoses[i]
        }

        // 2-3. MetalAtlasBaker — xatlas UV unwrap + Metal compute per-pixel atlas baking.
        //      Patchwork va blur ikkalasini hal qiladi. Polycam darajasiga yaqin.
        await MainActor.run {
            self.processingStatusLabel.text = "Texturing — xatlas UV unwrap (uzoq bo'lishi mumkin)…"
            self.progressView.setProgress(0.55, animated: true)
        }

        // Phase 8 iter5: faqat hi-res cameralarni atlas baker'ga uzatamiz.
        // Low-res (1920×1440) cameralar `recordPose`'dan kelgan stale ARKit
        // pose bilan ishlaydi → atlas baker'da ghosting/transparency artifacts.
        // Hi-res (2016+ width) cameralar `triggerHiResCapture` ichida update
        // bo'lgan, pose accurate.
        let hiResThreshold: Float = 2000
        let hiResCameras = cameras.filter { $0.imageW >= hiResThreshold }
        let usedCameras = hiResCameras.count >= 30 ? hiResCameras : cameras
        NSLog("KADASTR atlas bake: \(usedCameras.count)/\(cameras.count) cameras (hi-res filter: w≥\(Int(hiResThreshold)))")

        // CameraView → AtlasBakeInputCamera. Depth URL = photo'ning yonida.
        // Phase 3.2: refined pose mavjud bo'lsa, original ARKit pose o'rniga.
        let bakeCameras: [AtlasBakeInputCamera] = usedCameras.map { cam in
            let depthURL = cam.imageURL.deletingLastPathComponent()
                .appendingPathComponent(String(format: "depth_%04d.bin", cam.index))
            let depthExists = FileManager.default.fileExists(atPath: depthURL.path)
            let pose = refinedByIndex[cam.index] ?? cam.transform
            return AtlasBakeInputCamera(
                transform: pose,
                intrinsics: cam.intrinsics,
                imageURL: cam.imageURL,
                imageWidth: cam.imageW,
                imageHeight: cam.imageH,
                depthURL: depthExists ? depthURL : nil,
                depthWidth: cam.depthW > 0 ? cam.depthW : 256,
                depthHeight: cam.depthH > 0 ? cam.depthH : 192,
                sharpness: cam.sharpness,  // Phase 3.3: view-dependent blending
            )
        }

        let bakeResult: AtlasBakeResult
        do {
            // Variant A Phase 2: voxel color fallback — capture davomida
            // accumulated voxel grid'dan rang olib, gray fallback'ni almashtiradi.
            let voxelVolume: MetalAtlasBaker.VoxelColorVolume? = streamingTSDF.flatMap { s in
                MetalAtlasBaker.VoxelColorVolume(
                    buffer: s.colorBuffer,
                    origin: s.origin,
                    voxelSize: s.voxelSize,
                    gridX: s.gridX,
                    gridY: s.gridY,
                    gridZ: s.gridZ,
                )
            }
            bakeResult = try MetalAtlasBaker.bake(
                positions: globalVerts,
                normals: globalNormals,
                triangles: globalTris,
                cameras: bakeCameras,
                atlasResolution: 4096,           // 4K atlas (memory safe; 6K → OOM crash)
                cameraBatchSize: 4,              // hi-res 12MP × 4 = ~196 MB per batch
                downsampleFactor: 1,             // full source (4032×3024 hi-res)
                voxelColor: voxelVolume,         // Phase 2: gray patches → voxel color
                useCubeProjectionUV: false,      // TEST: xatlas — oblik yuzalarni qoplaydimi?
                progress: { p, msg in
                    Task { @MainActor in
                        self.processingStatusLabel.text = msg
                        // Phase 8: atlas baking 0.55-0.90 (after ICP).
                        self.progressView.setProgress(0.55 + p * 0.35, animated: false)
                    }
                },
            )
        } catch let atlasErr as AtlasBakeError {
            let msg: String
            switch atlasErr {
            case .xatlasFailed(let s): msg = "xatlas: \(s)"
            case .metalSetup(let s): msg = "Metal: \(s)"
            case .imageLoad(let s): msg = "Image: \(s)"
            }
            NSLog("KADASTR Atlas FAILED: \(msg)")
            throw NSError(
                domain: "TexturedScan", code: 104,
                userInfo: [NSLocalizedDescriptionKey: "Atlas bake: \(msg)"],
            )
        } catch {
            NSLog("KADASTR Atlas FAILED (unknown): \(error)")
            throw NSError(
                domain: "TexturedScan", code: 104,
                userInfo: [NSLocalizedDescriptionKey: "Atlas bake unknown: \(error)"],
            )
        }

        await MainActor.run {
            self.processingStatusLabel.text = "Texturing mesh…"
            self.progressView.setProgress(0.90, animated: true)
        }

        // Post-bake filter o'chirildi — atlas baker ko'p triangle uchun gray fallback
        // qaytarayotgan, drop "moth-eaten" effekt berardi. To'liq mesh qoladi,
        // gray joylar bo'lishi mumkin (texture yo'q joylarda).
        let filteredResult = bakeResult

        // ESRGAN bypass (grain/sekin); o'rniga mild CIUnsharpMask. Manba 1920×1440
        // ultra-wide bo'lgani uchun haqiqiy detail qaytmaydi, lekin qirra/tugma
        // kontrasti aniqlashadi (halo/grain'siz, Mac'da 1.8/0.5 tasdiqlangan).
        let enhancedAtlas: UIImage = Self.sharpenAtlas(bakeResult.atlas)

        // Build SCNGeometry from xatlas-unwrapped mesh + atlas texture.
        let geom = Self.buildSubMeshGeometry(
            vertices: filteredResult.vertices,
            normals: filteredResult.normals,
            uvs: filteredResult.uvs,
            indices: filteredResult.indices,
        )
        NSLog("KADASTR atlas attached: \(bakeResult.atlasWidth)×\(bakeResult.atlasHeight) (enhanced: \(Int(enhancedAtlas.size.width))×\(Int(enhancedAtlas.size.height)))")
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = enhancedAtlas
        mat.diffuse.magnificationFilter = .nearest  // sharp pixels (no bilinear blur)
        mat.diffuse.minificationFilter = .linear    // smooth zoom-out
        mat.diffuse.mipFilter = .none
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        geom.materials = [mat]
        scene.rootNode.addChildNode(SCNNode(geometry: geom))

        await MainActor.run {
            self.processingStatusLabel.text = "Encoding textures…"
            self.progressView.setProgress(0.90, animated: true)
        }

        let ok = scene.write(to: output, options: nil, delegate: nil, progressHandler: nil)
        if !ok {
            throw NSError(
                domain: "TexturedScan", code: 101,
                userInfo: [NSLocalizedDescriptionKey: "USDZ saqlash muvaffaqiyatsiz"],
            )
        }

        await MainActor.run {
            self.progressView.setProgress(1.0, animated: true)
        }
    }

    // MARK: - Mesh Decimation (Quadric Error Metrics)

    /// 4x4 simmetrik kvadrik matritsa — yuza tenglamasi xato hisoblash uchun.
    /// Garland & Heckbert 1997: "Surface Simplification Using Quadric Error Metrics".
    /// Faqat 10 ta unique elementni saqlaymiz (simmetriya).
    fileprivate struct Quadric {
        var a: Float, b: Float, c: Float, d: Float
        var e: Float, f: Float, g: Float
        var h: Float, i: Float
        var j: Float

        static let zero = Quadric(
            a: 0, b: 0, c: 0, d: 0, e: 0, f: 0, g: 0, h: 0, i: 0, j: 0,
        )

        /// Plane (a, b, c, d) — normal (a,b,c) unit, ax+by+cz+d=0. K = p p^T.
        static func fromPlane(_ p: SIMD4<Float>) -> Quadric {
            let px = p.x, py = p.y, pz = p.z, pw = p.w
            return Quadric(
                a: px * px, b: px * py, c: px * pz, d: px * pw,
                e: py * py, f: py * pz, g: py * pw,
                h: pz * pz, i: pz * pw,
                j: pw * pw,
            )
        }

        /// Element-wise + (additivity).
        static func + (l: Quadric, r: Quadric) -> Quadric {
            return Quadric(
                a: l.a + r.a, b: l.b + r.b, c: l.c + r.c, d: l.d + r.d,
                e: l.e + r.e, f: l.f + r.f, g: l.g + r.g,
                h: l.h + r.h, i: l.i + r.i,
                j: l.j + r.j,
            )
        }

        /// Scalar multiplication (area weighting).
        static func * (q: Quadric, s: Float) -> Quadric {
            return Quadric(
                a: q.a * s, b: q.b * s, c: q.c * s, d: q.d * s,
                e: q.e * s, f: q.f * s, g: q.g * s,
                h: q.h * s, i: q.i * s,
                j: q.j * s,
            )
        }

        /// Quadric error at vertex v: [v 1]^T * M * [v 1].
        func error(at v: SIMD3<Float>) -> Float {
            let x = v.x, y = v.y, z = v.z
            return a * x * x + 2 * b * x * y + 2 * c * x * z + 2 * d * x
                + e * y * y + 2 * f * y * z + 2 * g * y
                + h * z * z + 2 * i * z
                + j
        }

        /// Optimal collapse position: minimize v^T Q v. Q[0:3, 0:3] * v = -[d, g, i].
        /// Singular bo'lsa fallback (odatda midpoint) ishlatiladi.
        func optimalPos(fallback: SIMD3<Float>) -> SIMD3<Float> {
            let A = simd_float3x3(rows: [
                SIMD3<Float>(a, b, c),
                SIMD3<Float>(b, e, f),
                SIMD3<Float>(c, f, h),
            ])
            let det = A.determinant
            if abs(det) < 1e-6 { return fallback }
            let rhs = SIMD3<Float>(-d, -g, -i)
            return A.inverse * rhs
        }
    }

    /// Min-heap entry — edge'ni cost bo'yicha tartiblash uchun.
    fileprivate struct EdgeCost {
        let v0: UInt32
        let v1: UInt32
        let cost: Float
        let pos: SIMD3<Float>
        let version: UInt32   // stale entry detection
    }

    /// Oddiy binary min-heap (Array tabanli).
    fileprivate struct EdgeHeap {
        var items: [EdgeCost] = []

        mutating func push(_ item: EdgeCost) {
            items.append(item)
            siftUp(items.count - 1)
        }

        mutating func pop() -> EdgeCost? {
            guard !items.isEmpty else { return nil }
            let r = items[0]
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                siftDown(0)
            }
            return r
        }

        private mutating func siftUp(_ idx: Int) {
            var i = idx
            while i > 0 {
                let p = (i - 1) / 2
                if items[i].cost < items[p].cost {
                    items.swapAt(i, p)
                    i = p
                } else { break }
            }
        }

        private mutating func siftDown(_ idx: Int) {
            var i = idx
            let n = items.count
            while true {
                let l = 2 * i + 1
                let r = 2 * i + 2
                var s = i
                if l < n && items[l].cost < items[s].cost { s = l }
                if r < n && items[r].cost < items[s].cost { s = r }
                if s == i { break }
                items.swapAt(i, s)
                i = s
            }
        }
    }

    /// QEM mesh decimation. ARKit'ning 60k triangle mesh'ini targetTriCount'gacha
    /// kamaytiradi (edge collapse). Tekis yuzalar (devor, pol) saqlanadi —
    /// kvadrik xato shu yuzalardagi collapse'larni "arzon" qiladi.
    @MainActor
    fileprivate static func decimateMesh(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        targetTriCount: Int,
        progressHandler: ((Float) -> Void)? = nil,
    ) -> (
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)]
    ) {
        var verts = vertices
        var norms = normals
        var tris = triangles
        let n = verts.count

        if tris.count <= targetTriCount {
            return (verts, norms, tris)
        }

        var quadrics = [Quadric](repeating: .zero, count: n)
        var vertActive = [Bool](repeating: true, count: n)
        var triActive = [Bool](repeating: true, count: tris.count)
        var vertVersion = [UInt32](repeating: 0, count: n)

        // Vertex → adjacent triangles (Set for dedup, will operate as Set)
        var vertTris: [Set<Int>] = Array(repeating: Set(), count: n)
        for (ti, t) in tris.enumerated() {
            vertTris[Int(t.v0)].insert(ti)
            vertTris[Int(t.v1)].insert(ti)
            vertTris[Int(t.v2)].insert(ti)
        }

        // Initial quadrics — har yuza tekisligini area bilan tortish.
        for t in tris {
            let v0 = verts[Int(t.v0)]
            let v1 = verts[Int(t.v1)]
            let v2 = verts[Int(t.v2)]
            let nx = simd_cross(v1 - v0, v2 - v0)
            let nlen = simd_length(nx)
            if nlen < 1e-9 { continue }
            let normal = nx / nlen
            let dval = -simd_dot(normal, v0)
            let plane = SIMD4<Float>(normal, dval)
            let q = Quadric.fromPlane(plane) * (nlen * 0.5)  // area-weighted
            quadrics[Int(t.v0)] = quadrics[Int(t.v0)] + q
            quadrics[Int(t.v1)] = quadrics[Int(t.v1)] + q
            quadrics[Int(t.v2)] = quadrics[Int(t.v2)] + q
        }

        // Helper: packed edge key (min, max) — duplicate'larni oldini olish.
        func edgeKey(_ x: UInt32, _ y: UInt32) -> UInt64 {
            let (mn, mx) = x < y ? (UInt64(x), UInt64(y)) : (UInt64(y), UInt64(x))
            return (mn << 32) | mx
        }

        func versionKey(_ x: Int, _ y: Int) -> UInt32 {
            return (vertVersion[x] &+ vertVersion[y]) &* 2654435761
        }

        func makeEdgeCost(_ x: UInt32, _ y: UInt32) -> EdgeCost {
            let q = quadrics[Int(x)] + quadrics[Int(y)]
            let mid = (verts[Int(x)] + verts[Int(y)]) * 0.5
            let optPos = q.optimalPos(fallback: mid)
            let cost = q.error(at: optPos)
            return EdgeCost(
                v0: x, v1: y, cost: max(cost, 0), pos: optPos,
                version: versionKey(Int(x), Int(y)),
            )
        }

        // Initial edges — har triangle 3 ta edge, dedup.
        var seenEdges = Set<UInt64>()
        seenEdges.reserveCapacity(tris.count * 3)
        var heap = EdgeHeap()
        heap.items.reserveCapacity(tris.count * 3)
        for t in tris {
            for (a, b) in [(t.v0, t.v1), (t.v1, t.v2), (t.v0, t.v2)] {
                let k = edgeKey(a, b)
                if !seenEdges.contains(k) {
                    seenEdges.insert(k)
                    heap.push(makeEdgeCost(a, b))
                }
            }
        }

        var currentTriCount = tris.count
        let startCount = currentTriCount
        var lastProgress: Float = 0

        while currentTriCount > targetTriCount, let entry = heap.pop() {
            let v0i = Int(entry.v0)
            let v1i = Int(entry.v1)

            if !vertActive[v0i] || !vertActive[v1i] { continue }
            if v0i == v1i { continue }
            if entry.version != versionKey(v0i, v1i) { continue }  // stale

            // Normal-flip check: hech bir qo'shni triangle teskari aylanmasligi kerak.
            //    Collapse'dan keyin v0 yangi pos'ga ko'chadi. Hozirgi va yangi face
            //    normallari taqqoslanadi. Agar burchak > 90° (dot < 0) — rad.
            var flipDetected = false
            let newPos = entry.pos
            for ti in vertTris[v0i] {
                if !triActive[ti] { continue }
                let t = tris[ti]
                // Bu triangle v1'ni o'z ichiga olsa, collapse'dan keyin u degenerate (skip)
                if t.v0 == entry.v1 || t.v1 == entry.v1 || t.v2 == entry.v1 { continue }
                let v0pos = (t.v0 == entry.v0) ? verts[v0i] : verts[Int(t.v0)]
                let v1pos = (t.v1 == entry.v0) ? verts[v0i] : verts[Int(t.v1)]
                let v2pos = (t.v2 == entry.v0) ? verts[v0i] : verts[Int(t.v2)]
                let oldN = simd_cross(v1pos - v0pos, v2pos - v0pos)
                let nv0 = (t.v0 == entry.v0) ? newPos : verts[Int(t.v0)]
                let nv1 = (t.v1 == entry.v0) ? newPos : verts[Int(t.v1)]
                let nv2 = (t.v2 == entry.v0) ? newPos : verts[Int(t.v2)]
                let newN = simd_cross(nv1 - nv0, nv2 - nv0)
                if simd_dot(oldN, newN) <= 0 { flipDetected = true; break }
            }
            if !flipDetected {
                for ti in vertTris[v1i] {
                    if !triActive[ti] { continue }
                    let t = tris[ti]
                    if t.v0 == entry.v0 || t.v1 == entry.v0 || t.v2 == entry.v0 { continue }
                    let v0pos = (t.v0 == entry.v1) ? verts[v1i] : verts[Int(t.v0)]
                    let v1pos = (t.v1 == entry.v1) ? verts[v1i] : verts[Int(t.v1)]
                    let v2pos = (t.v2 == entry.v1) ? verts[v1i] : verts[Int(t.v2)]
                    let oldN = simd_cross(v1pos - v0pos, v2pos - v0pos)
                    let nv0 = (t.v0 == entry.v1) ? newPos : verts[Int(t.v0)]
                    let nv1 = (t.v1 == entry.v1) ? newPos : verts[Int(t.v1)]
                    let nv2 = (t.v2 == entry.v1) ? newPos : verts[Int(t.v2)]
                    let newN = simd_cross(nv1 - nv0, nv2 - nv0)
                    if simd_dot(oldN, newN) <= 0 { flipDetected = true; break }
                }
            }
            if flipDetected { continue }

            // Collapse v1 → v0. v0 ga optimal pos.
            verts[v0i] = entry.pos
            quadrics[v0i] = quadrics[v0i] + quadrics[v1i]
            vertVersion[v0i] = vertVersion[v0i] &+ 1
            vertActive[v1i] = false

            // Triangle'larni qayta yo'naltirish.
            var v0AdjTris = vertTris[v0i]
            let v1AdjTris = vertTris[v1i]
            for ti in v1AdjTris {
                if !triActive[ti] { continue }
                var t = tris[ti]
                let containsV0 = (t.v0 == entry.v0 || t.v1 == entry.v0 || t.v2 == entry.v0)
                if containsV0 {
                    // Degenerate (line) — yo'q qilish.
                    triActive[ti] = false
                    currentTriCount -= 1
                    // v0 adjacency'dan ham olib tashlash
                    v0AdjTris.remove(ti)
                } else {
                    if t.v0 == entry.v1 { t.v0 = entry.v0 }
                    if t.v1 == entry.v1 { t.v1 = entry.v0 }
                    if t.v2 == entry.v1 { t.v2 = entry.v0 }
                    tris[ti] = t
                    v0AdjTris.insert(ti)
                }
            }
            vertTris[v0i] = v0AdjTris
            vertTris[v1i] = Set()

            // Recompute edges incident to v0.
            var neighbors = Set<UInt32>()
            for ti in v0AdjTris {
                let t = tris[ti]
                if t.v0 != entry.v0 { neighbors.insert(t.v0) }
                if t.v1 != entry.v0 { neighbors.insert(t.v1) }
                if t.v2 != entry.v0 { neighbors.insert(t.v2) }
            }
            for nb in neighbors {
                if vertActive[Int(nb)] {
                    heap.push(makeEdgeCost(entry.v0, nb))
                }
            }

            // Progress every ~2%
            let progress = Float(startCount - currentTriCount) / Float(startCount - targetTriCount)
            if progress - lastProgress > 0.02 {
                lastProgress = progress
                progressHandler?(min(progress, 1.0))
            }
        }

        // Output: renumber active vertices, filter active triangles.
        var newIdx = [Int](repeating: -1, count: n)
        var outVerts: [SIMD3<Float>] = []
        var outNorms: [SIMD3<Float>] = []
        outVerts.reserveCapacity(n)
        outNorms.reserveCapacity(n)
        for vi in 0..<n {
            if vertActive[vi] {
                newIdx[vi] = outVerts.count
                outVerts.append(verts[vi])
                outNorms.append(norms[vi])
            }
        }
        var outTris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        outTris.reserveCapacity(tris.count)
        for (ti, t) in tris.enumerated() {
            if !triActive[ti] { continue }
            let i0 = newIdx[Int(t.v0)]
            let i1 = newIdx[Int(t.v1)]
            let i2 = newIdx[Int(t.v2)]
            if i0 < 0 || i1 < 0 || i2 < 0 { continue }
            if i0 == i1 || i1 == i2 || i0 == i2 { continue }
            outTris.append((UInt32(i0), UInt32(i1), UInt32(i2)))
        }

        // Recompute vertex normals from output triangles (initial normals stale).
        var newNorms = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: outVerts.count)
        for t in outTris {
            let v0 = outVerts[Int(t.v0)]
            let v1 = outVerts[Int(t.v1)]
            let v2 = outVerts[Int(t.v2)]
            let n = simd_cross(v1 - v0, v2 - v0)
            newNorms[Int(t.v0)] += n
            newNorms[Int(t.v1)] += n
            newNorms[Int(t.v2)] += n
        }
        for i in 0..<newNorms.count {
            let len = simd_length(newNorms[i])
            if len > 1e-9 {
                newNorms[i] /= len
            } else {
                newNorms[i] = outNorms[i]  // fallback to original
            }
        }

        return (outVerts, newNorms, outTris)
    }

    // MARK: - UV Unwrap (Chart-based)

    /// Chart-based UV unwrap.
    /// Mesh triangle'larini normallari yaqin bo'lgan guruhlarga (charts) ajratadi,
    /// har chart'ni 2D'ga yoyadi va atlas'ga shelf-packing bilan joylashtiradi.
    /// Qo'shni triangle'lar bir xil chart'da → atlas'da ham qo'shni → ranglar
    /// uzluksiz, cell-boundary artifaktlari yo'qoladi.
    @MainActor
    fileprivate static func unwrapUVsByCharts(
        vertices: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        atlasSize: Int,
        chartNormalThreshold: Float = 0.80,  // cos(~37°) — flat-ish charts
    ) -> (uvs: [SIMD2<Float>], chartCount: Int) {
        let triCount = triangles.count

        // 1. Edge → triangles adjacency
        var edgeMap: [UInt64: [Int]] = [:]
        edgeMap.reserveCapacity(triCount * 3)
        func edgeKey(_ a: UInt32, _ b: UInt32) -> UInt64 {
            let (mn, mx) = a < b ? (UInt64(a), UInt64(b)) : (UInt64(b), UInt64(a))
            return (mn << 32) | mx
        }
        for (ti, t) in triangles.enumerated() {
            edgeMap[edgeKey(t.v0, t.v1), default: []].append(ti)
            edgeMap[edgeKey(t.v1, t.v2), default: []].append(ti)
            edgeMap[edgeKey(t.v0, t.v2), default: []].append(ti)
        }
        var triNeighbors: [[Int]] = Array(repeating: [], count: triCount)
        for (_, tlist) in edgeMap {
            if tlist.count == 2 {
                triNeighbors[tlist[0]].append(tlist[1])
                triNeighbors[tlist[1]].append(tlist[0])
            }
        }

        // 2. Triangle normallari
        var triNorms = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: triCount)
        var triAreas = [Float](repeating: 0, count: triCount)
        for ti in 0..<triCount {
            let t = triangles[ti]
            let v0 = vertices[Int(t.v0)]
            let v1 = vertices[Int(t.v1)]
            let v2 = vertices[Int(t.v2)]
            let n = simd_cross(v1 - v0, v2 - v0)
            let nlen = simd_length(n)
            triAreas[ti] = nlen * 0.5
            if nlen > 1e-9 { triNorms[ti] = n / nlen }
        }

        // 3. Flood-fill charts: o'xshash normallarga ega qo'shni triangle'lar.
        var chartId = [Int](repeating: -1, count: triCount)
        var chartTris: [[Int]] = []
        var chartNormals: [SIMD3<Float>] = []

        for startTi in 0..<triCount {
            if chartId[startTi] >= 0 { continue }
            let cid = chartTris.count
            var triIds: [Int] = [startTi]
            var avgN = triNorms[startTi]
            chartId[startTi] = cid
            var queue: [Int] = [startTi]
            var qi = 0
            while qi < queue.count {
                let ti = queue[qi]
                qi += 1
                let refN = simd_normalize(avgN)
                for nb in triNeighbors[ti] {
                    if chartId[nb] >= 0 { continue }
                    if simd_dot(refN, triNorms[nb]) >= chartNormalThreshold {
                        chartId[nb] = cid
                        triIds.append(nb)
                        queue.append(nb)
                        avgN += triNorms[nb]
                    }
                }
            }
            chartTris.append(triIds)
            chartNormals.append(simd_normalize(avgN))
        }

        // 4. Har chart'ni 2D'ga proyeksiya qilamiz va bounding box hisoblaymiz.
        struct ChartBBox {
            var triUVs: [SIMD2<Float>]  // 3 per triangle
            var minX: Float, minY: Float, maxX: Float, maxY: Float
        }
        var chartBBoxes: [ChartBBox] = []
        chartBBoxes.reserveCapacity(chartTris.count)

        for cid in 0..<chartTris.count {
            let avgN = chartNormals[cid]
            // Tangent basis (T, B) orthonormal to avgN
            var up = SIMD3<Float>(0, 1, 0)
            if abs(simd_dot(avgN, up)) > 0.9 {
                up = SIMD3<Float>(1, 0, 0)
            }
            let T = simd_normalize(simd_cross(up, avgN))
            let B = simd_normalize(simd_cross(avgN, T))

            var uvs: [SIMD2<Float>] = []
            uvs.reserveCapacity(chartTris[cid].count * 3)
            var minX: Float = .infinity, minY: Float = .infinity
            var maxX: Float = -.infinity, maxY: Float = -.infinity
            for ti in chartTris[cid] {
                let t = triangles[ti]
                for vIdx in [t.v0, t.v1, t.v2] {
                    let v = vertices[Int(vIdx)]
                    let x = simd_dot(v, T)
                    let y = simd_dot(v, B)
                    uvs.append(SIMD2<Float>(x, y))
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
            chartBBoxes.append(ChartBBox(
                triUVs: uvs, minX: minX, minY: minY, maxX: maxX, maxY: maxY,
            ))
        }

        // 5. Shelf packing: chart bounding box'larini atlas'ga joylash.
        //    Avval scaleFactor topamiz — barcha chartlarning umumiy maydoni atlas'ning
        //    70% qadar bo'lsin (utilization).
        var totalArea: Float = 0
        for bb in chartBBoxes {
            totalArea += (bb.maxX - bb.minX) * (bb.maxY - bb.minY)
        }
        let targetArea = Float(atlasSize * atlasSize) * 0.6
        var scaleFactor = sqrt(targetArea / max(totalArea, 1e-9))

        let padding: Float = 2.0
        var chartOffsets = [(x: Float, y: Float)](
            repeating: (0, 0), count: chartBBoxes.count,
        )

        // Sort by height descending
        let sortedCids = (0..<chartBBoxes.count).sorted { a, b in
            let ha = (chartBBoxes[a].maxY - chartBBoxes[a].minY) * scaleFactor
            let hb = (chartBBoxes[b].maxY - chartBBoxes[b].minY) * scaleFactor
            return ha > hb
        }

        struct Shelf { var y: Float; var height: Float; var x: Float }
        var shelves: [Shelf] = []
        var maxY: Float = padding

        for cid in sortedCids {
            let bb = chartBBoxes[cid]
            let w = (bb.maxX - bb.minX) * scaleFactor + padding
            let h = (bb.maxY - bb.minY) * scaleFactor + padding
            var placed = false
            for si in 0..<shelves.count {
                if shelves[si].x + w <= Float(atlasSize) && h <= shelves[si].height + 0.01 {
                    chartOffsets[cid] = (shelves[si].x, shelves[si].y)
                    shelves[si].x += w
                    placed = true
                    break
                }
            }
            if !placed {
                if maxY + h <= Float(atlasSize) {
                    shelves.append(Shelf(y: maxY, height: h, x: padding + w))
                    chartOffsets[cid] = (padding, maxY)
                    maxY += h
                } else {
                    // Atlas to'lib qoldi — kichik joyga siqamiz (overflow imkoniyati)
                    chartOffsets[cid] = (0, 0)
                }
            }
        }

        // 6. Output: per-triangle UVs (3 per tri), normalized [0, 1].
        var outUVs = [SIMD2<Float>](
            repeating: SIMD2<Float>(0, 0), count: triCount * 3,
        )
        let aSizeF = Float(atlasSize)
        for cid in 0..<chartTris.count {
            let bb = chartBBoxes[cid]
            let off = chartOffsets[cid]
            var uvIdx = 0
            for ti in chartTris[cid] {
                for j in 0..<3 {
                    let lv = bb.triUVs[uvIdx]
                    uvIdx += 1
                    let xAtlas = off.x + (lv.x - bb.minX) * scaleFactor
                    let yAtlas = off.y + (lv.y - bb.minY) * scaleFactor
                    outUVs[ti * 3 + j] = SIMD2<Float>(
                        xAtlas / aSizeF,
                        1.0 - yAtlas / aSizeF,  // SCN UV: Y bottom-left
                    )
                }
            }
        }
        return (outUVs, chartTris.count)
    }

    /// Atlas pixel'larini per-triangle rasterize qilib, vertex colors'ni
    /// barycentric interpolatsiya qilib pikselga yozadi. Chart-based UV bilan
    /// birgalikda ishlatiladi — har triangle atlas'da o'z hududiga ega.
    /// Output: UInt8 RGBA buffer (atlasSize × atlasSize × 4).
    @MainActor
    fileprivate static func bakeAtlasFromVertColors(
        vertices: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        vertColors: [SIMD3<Float>],
        uvs: [SIMD2<Float>],          // 3 per triangle, normalized [0,1] (Y bottom-left)
        atlasSize: Int,
    ) -> UnsafeMutablePointer<UInt8> {
        let bytesPerRow = atlasSize * 4
        let totalBytes = bytesPerRow * atlasSize
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)
        memset(ptr, 128, totalBytes)

        let aSizeF = Float(atlasSize)
        for (ti, tri) in triangles.enumerated() {
            // UVs in atlas pixel space (top-left origin for rasterization)
            let uv0n = uvs[ti * 3 + 0]
            let uv1n = uvs[ti * 3 + 1]
            let uv2n = uvs[ti * 3 + 2]
            // Flip Y back to top-left
            let p0 = SIMD2<Float>(uv0n.x * aSizeF, (1 - uv0n.y) * aSizeF)
            let p1 = SIMD2<Float>(uv1n.x * aSizeF, (1 - uv1n.y) * aSizeF)
            let p2 = SIMD2<Float>(uv2n.x * aSizeF, (1 - uv2n.y) * aSizeF)

            let c0 = vertColors[Int(tri.v0)]
            let c1 = vertColors[Int(tri.v1)]
            let c2 = vertColors[Int(tri.v2)]

            // Triangle bounding box (with 1 pixel padding)
            let xMin = max(0, Int(floor(min(p0.x, min(p1.x, p2.x))) - 1))
            let yMin = max(0, Int(floor(min(p0.y, min(p1.y, p2.y))) - 1))
            let xMax = min(atlasSize - 1, Int(ceil(max(p0.x, max(p1.x, p2.x))) + 1))
            let yMax = min(atlasSize - 1, Int(ceil(max(p0.y, max(p1.y, p2.y))) + 1))

            // Edge function denominators for barycentric
            let denom = (p1.y - p2.y) * (p0.x - p2.x) + (p2.x - p1.x) * (p0.y - p2.y)
            if abs(denom) < 1e-9 { continue }  // degenerate
            let invDenom: Float = 1.0 / denom

            for py in yMin...yMax {
                let pyF = Float(py) + 0.5
                let rowOff = py * bytesPerRow
                for px in xMin...xMax {
                    let pxF = Float(px) + 0.5
                    // Barycentric coords
                    let w0 = ((p1.y - p2.y) * (pxF - p2.x) + (p2.x - p1.x) * (pyF - p2.y)) * invDenom
                    let w1 = ((p2.y - p0.y) * (pxF - p2.x) + (p0.x - p2.x) * (pyF - p2.y)) * invDenom
                    let w2 = 1 - w0 - w1
                    // Allow slight overshoot for edge anti-bleeding
                    if w0 < -0.02 || w1 < -0.02 || w2 < -0.02 { continue }
                    // Clamp negative weights to 0 and renormalize
                    let cw0 = max(w0, 0.0)
                    let cw1 = max(w1, 0.0)
                    let cw2 = max(w2, 0.0)
                    let sumW = cw0 + cw1 + cw2
                    if sumW <= 0 { continue }
                    let nw0 = cw0 / sumW
                    let nw1 = cw1 / sumW
                    let nw2 = cw2 / sumW
                    let color = c0 * nw0 + c1 * nw1 + c2 * nw2

                    let off = rowOff + px * 4
                    ptr[off] = UInt8(max(0, min(255, Int(color.x * 255))))
                    ptr[off + 1] = UInt8(max(0, min(255, Int(color.y * 255))))
                    ptr[off + 2] = UInt8(max(0, min(255, Int(color.z * 255))))
                    ptr[off + 3] = 255
                }
            }
        }
        return ptr
    }

    // MARK: - Custom texture export helpers

    /// Bitta ARMeshAnchor'ning raw data'si (world-space conversion uchun).
    fileprivate struct AnchorRaw {
        let transform: simd_float4x4         // anchor → world
        let center: SIMD3<Float>             // world-space anchor center
        let vertices: [SIMD3<Float>]         // local-space (anchor frame)
        let normals: [SIMD3<Float>]          // local-space
        let worldVertices: [SIMD3<Float>]    // world-space (pre-computed)
        let worldNormals: [SIMD3<Float>]     // world-space
        let indices: [UInt32]

        // Phase 7: SerializedAnchor (Codable, SavedScanStorage uchun) konvertorlar.
        func toSerialized() -> SerializedAnchor {
            return SerializedAnchor(
                transform: transform, center: center,
                vertices: vertices, normals: normals,
                worldVertices: worldVertices, worldNormals: worldNormals,
                indices: indices,
            )
        }

        static func fromSerialized(_ s: SerializedAnchor) -> AnchorRaw {
            return AnchorRaw(
                transform: s.transform, center: s.center,
                vertices: s.vertices, normals: s.normals,
                worldVertices: s.worldVertices, worldNormals: s.worldNormals,
                indices: s.indices,
            )
        }
    }

    /// Camera frame metadata.
    fileprivate struct CameraView {
        let index: Int
        let transform: simd_float4x4   // IMAGE pose: camera → world (hi-res frame agar mavjud)
        let depthTransform: simd_float4x4  // DEPTH pose: low-res frame (depth bilan sinx)
        let intrinsics: simd_float3x3  // pixel intrinsics (image bilan birga scale qilingan)
        let imageW: Float
        let imageH: Float
        let imageURL: URL
        let position: SIMD3<Float>     // world-space camera origin (image pose)
        let forward: SIMD3<Float>      // world-space camera view direction (-Z, image pose)
        // LiDAR depth map (z-distance, meters). Occlusion testi uchun.
        let depthMap: [Float]?
        let depthW: Int
        let depthH: Int
        // Phase 3.3: variance-of-Laplacian sharpness [0..1], 0=blurry, 1=sharp.
        // Atlas baker view-dependent blending'da weight'ga ko'paytiriladi.
        let sharpness: Float
    }

    @MainActor
    fileprivate static func extractAnchorData(arView: ARSCNView) -> [AnchorRaw] {
        guard let frame = arView.session.currentFrame else { return [] }
        let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        var out: [AnchorRaw] = []
        out.reserveCapacity(anchors.count)
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

            var local: [SIMD3<Float>] = []
            var localN: [SIMD3<Float>] = []
            var world: [SIMD3<Float>] = []
            var worldN: [SIMD3<Float>] = []
            local.reserveCapacity(vCount)
            localN.reserveCapacity(vCount)
            world.reserveCapacity(vCount)
            worldN.reserveCapacity(vCount)
            var centerSum = SIMD3<Float>(0, 0, 0)
            for i in 0..<vCount {
                let v = vBuf.advanced(by: i * vStride).assumingMemoryBound(to: Float.self)
                let lp = SIMD3<Float>(v[0], v[1], v[2])
                let w4 = xform * SIMD4<Float>(lp, 1)
                let wp = SIMD3<Float>(w4.x, w4.y, w4.z)
                local.append(lp)
                world.append(wp)
                centerSum += wp

                let n = nBuf.advanced(by: i * nStride).assumingMemoryBound(to: Float.self)
                let lnv = SIMD3<Float>(n[0], n[1], n[2])
                localN.append(lnv)
                worldN.append(simd_normalize(normalXform * lnv))
            }
            let center = centerSum / Float(max(vCount, 1))

            let faces = g.faces
            let fBuf = faces.buffer.contents()
            let triCount = faces.count
            var indices: [UInt32] = []
            indices.reserveCapacity(triCount * 3)
            for i in 0..<triCount {
                if faces.bytesPerIndex == 4 {
                    let p = fBuf.advanced(by: i * 3 * 4).assumingMemoryBound(to: UInt32.self)
                    indices.append(p[0]); indices.append(p[1]); indices.append(p[2])
                } else {
                    let p = fBuf.advanced(by: i * 3 * 2).assumingMemoryBound(to: UInt16.self)
                    indices.append(UInt32(p[0])); indices.append(UInt32(p[1])); indices.append(UInt32(p[2]))
                }
            }

            out.append(AnchorRaw(
                transform: xform,
                center: center,
                vertices: local,
                normals: localN,
                worldVertices: world,
                worldNormals: worldN,
                indices: indices,
            ))
        }
        return out
    }

    /// Phase 7.6 bugfix: JSON dan re-parse qilinganda `[[Float]]` cast fail
    /// bo'ladi (JSONSerialization NSNumber+Double saqlaydi). NSNumber-tolerant
    /// helper.
    fileprivate static func parseFloatMatrix(_ any: Any?, rows: Int, cols: Int) -> [[Float]]? {
        guard let outerArr = any as? [Any], outerArr.count == rows else { return nil }
        var out: [[Float]] = []
        out.reserveCapacity(rows)
        for row in outerArr {
            guard let inner = row as? [Any], inner.count == cols else { return nil }
            var floatRow: [Float] = []
            floatRow.reserveCapacity(cols)
            for v in inner {
                if let n = v as? NSNumber {
                    floatRow.append(n.floatValue)
                } else if let d = v as? Double {
                    floatRow.append(Float(d))
                } else if let f = v as? Float {
                    floatRow.append(f)
                } else {
                    return nil
                }
            }
            out.append(floatRow)
        }
        return out
    }

    fileprivate static func parseCameras(poses: [[String: Any]], folder: URL) -> [CameraView] {
        var cams: [CameraView] = []
        var skipReasons: [String: Int] = [:]
        for entry in poses {
            guard let idx = entry["index"] as? Int else {
                skipReasons["no_idx", default: 0] += 1; continue
            }
            // Phase 7.6: NSNumber-tolerant matrix parsing
            guard let tRows = parseFloatMatrix(entry["transform_matrix"], rows: 4, cols: 4) else {
                skipReasons["bad_transform", default: 0] += 1; continue
            }
            guard let kRows = parseFloatMatrix(entry["intrinsics"], rows: 3, cols: 3) else {
                skipReasons["bad_intrinsics", default: 0] += 1; continue
            }
            // image_width/height ham NSNumber bo'lishi mumkin — tolerant cast
            let w: Int
            let h: Int
            if let n = entry["image_width"] as? NSNumber { w = n.intValue }
            else if let i = entry["image_width"] as? Int { w = i } else {
                skipReasons["no_width", default: 0] += 1; continue
            }
            if let n = entry["image_height"] as? NSNumber { h = n.intValue }
            else if let i = entry["image_height"] as? Int { h = i } else {
                skipReasons["no_height", default: 0] += 1; continue
            }
            let imgURL = folder.appendingPathComponent(String(format: "photo_%04d.jpg", idx))
            guard FileManager.default.fileExists(atPath: imgURL.path) else {
                skipReasons["no_photo_file", default: 0] += 1; continue
            }
            // recordPose row-major: rowI = [col0[I], col1[I], col2[I], col3[I]]
            // simd_float4x4 columns-major — har row mat'ning row sifatida ishlaydi.
            let t = simd_float4x4(rows: [
                SIMD4<Float>(tRows[0][0], tRows[0][1], tRows[0][2], tRows[0][3]),
                SIMD4<Float>(tRows[1][0], tRows[1][1], tRows[1][2], tRows[1][3]),
                SIMD4<Float>(tRows[2][0], tRows[2][1], tRows[2][2], tRows[2][3]),
                SIMD4<Float>(tRows[3][0], tRows[3][1], tRows[3][2], tRows[3][3]),
            ])
            // Depth uchun alohida pose (low-res frame'da olingan). Agar yo'q bo'lsa
            // (eski format) — image transform'ni ishlatamiz (backward compat).
            let depthT: simd_float4x4
            if let dRows = parseFloatMatrix(entry["depth_transform_matrix"], rows: 4, cols: 4) {
                depthT = simd_float4x4(rows: [
                    SIMD4<Float>(dRows[0][0], dRows[0][1], dRows[0][2], dRows[0][3]),
                    SIMD4<Float>(dRows[1][0], dRows[1][1], dRows[1][2], dRows[1][3]),
                    SIMD4<Float>(dRows[2][0], dRows[2][1], dRows[2][2], dRows[2][3]),
                    SIMD4<Float>(dRows[3][0], dRows[3][1], dRows[3][2], dRows[3][3]),
                ])
            } else {
                depthT = t
            }
            let k = simd_float3x3(rows: [
                SIMD3<Float>(kRows[0][0], kRows[0][1], kRows[0][2]),
                SIMD3<Float>(kRows[1][0], kRows[1][1], kRows[1][2]),
                SIMD3<Float>(kRows[2][0], kRows[2][1], kRows[2][2]),
            ])
            let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            // ARKit camera basis: +X right, +Y up, -Z forward.
            // forward direction (world space) = -Z column of camera transform.
            let fwd = -simd_normalize(SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z))

            // LiDAR depth map (256×192 odatda) — capturePhoto saqlagan format:
            // [Int32 W][Int32 H][Float32 pixels...]. Mavjud bo'lmasa nil.
            var depthMap: [Float]? = nil
            var depthW = 0
            var depthH = 0
            let depthURL = folder.appendingPathComponent(String(format: "depth_%04d.bin", idx))
            if let data = try? Data(contentsOf: depthURL), data.count >= 8 {
                let dw = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) }
                let dh = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) }
                let pixCount = Int(dw) * Int(dh)
                let expectedBytes = 8 + pixCount * 4
                if pixCount > 0, data.count >= expectedBytes {
                    var pixels = [Float](repeating: 0, count: pixCount)
                    pixels.withUnsafeMutableBufferPointer { buf in
                        data.withUnsafeBytes { raw in
                            let src = raw.baseAddress!.advanced(by: 8).assumingMemoryBound(to: Float.self)
                            memcpy(buf.baseAddress, src, pixCount * 4)
                        }
                    }
                    depthMap = pixels
                    depthW = Int(dw)
                    depthH = Int(dh)
                }
            }

            // Phase 3.3: sharpness — pose dict'dan o'qiladi. Eski photos uchun
            // (sharpness yo'q) → 0.5 neutral default (boshqa camera'larga nisbatan
            // bias bermaslik uchun).
            let sharp: Float
            if let s = entry["sharpness"] as? Double {
                sharp = Float(s)
            } else if let s = entry["sharpness"] as? Float {
                sharp = s
            } else {
                sharp = 0.5
            }

            cams.append(CameraView(
                index: idx, transform: t, depthTransform: depthT, intrinsics: k,
                imageW: Float(w), imageH: Float(h),
                imageURL: imgURL, position: pos, forward: fwd,
                depthMap: depthMap, depthW: depthW, depthH: depthH,
                sharpness: sharp,
            ))
        }
        // Phase 7.6: skip diagnostic
        if !skipReasons.isEmpty {
            NSLog("KADASTR parseCameras skipped: \(skipReasons), kept \(cams.count)/\(poses.count)")
        }
        return cams
    }

    /// Camera depth map'dan triangle markazi pikseli depth'ini olib, haqiqiy
    /// kamera-triangle masofasi bilan solishtiradi. Agar oradagi piksel
    /// kichikroq depth ko'rsatsa — orada boshqa devor bor → occluded.
    /// Margin: ARKit pose drift (15-25 sm) + LiDAR shovqini sababli 25 sm
    /// bag'rikenglik. Devor orqasidagi obyektlar 0.5-1 m farq beradi — to'g'ri
    /// rad etiladi, lekin pose drift sababli noto'g'ri rad etish kamayadi.
    fileprivate static func isOccluded(
        worldPoint: SIMD3<Float>,
        camera: CameraView,
        invTransform: simd_float4x4,
    ) -> Bool {
        guard let depths = camera.depthMap, camera.depthW > 0, camera.depthH > 0 else {
            return false  // depth yo'q — occlusion testi o'tkazib yuboriladi
        }
        let camSpace = invTransform * SIMD4<Float>(worldPoint, 1)
        let actualDepth = -camSpace.z
        if actualDepth <= 0.05 { return true }  // camera ortida
        // Pixel coords (landscape image basis)
        let proj = camera.intrinsics * SIMD3<Float>(camSpace.x, -camSpace.y, actualDepth)
        let pu = proj.x / proj.z
        let pv = proj.y / proj.z
        if pu < 0 || pv < 0 || pu >= camera.imageW || pv >= camera.imageH { return true }
        // Depth map (proportional resize)
        let dx = Int(pu / camera.imageW * Float(camera.depthW))
        let dy = Int(pv / camera.imageH * Float(camera.depthH))
        let dxC = min(max(dx, 0), camera.depthW - 1)
        let dyC = min(max(dy, 0), camera.depthH - 1)
        let sampled = depths[dyC * camera.depthW + dxC]
        if sampled <= 0.05 { return false }  // depth yo'q (NaN, hole) — qabul
        return actualDepth > sampled + 0.40
    }

    /// Anchor markazi'ga eng yaqin va perpendicular cameras'lardan birini tanlash.
    fileprivate static func pickBestCamera(
        for anchor: AnchorRaw, cameras: [CameraView],
    ) -> CameraView? {
        var best: CameraView? = nil
        var bestScore: Float = -.infinity
        for cam in cameras {
            // Anchor cam oldida'mi?
            let toAnchor = simd_normalize(anchor.center - cam.position)
            let dot = simd_dot(cam.forward, toAnchor)
            if dot <= 0.1 { continue }  // anchor camera orqasida yoki yon tomonda
            let dist = simd_distance(cam.position, anchor.center)
            if dist > 8.0 { continue }  // juda uzoq cameras
            // Score: yaxshi alignment (dot) + yaqin masofa
            let score = dot * 2.0 - dist * 0.3
            if score > bestScore {
                bestScore = score
                best = cam
            }
        }
        return best
    }

    /// Anchor vertex'larini camera'ga proyeksiya qilib UV (normalized 0-1).
    fileprivate static func projectUVs(
        anchor: AnchorRaw, camera: CameraView,
    ) -> [SIMD2<Float>] {
        let inv = camera.transform.inverse
        var uvs: [SIMD2<Float>] = []
        uvs.reserveCapacity(anchor.worldVertices.count)
        for wv in anchor.worldVertices {
            let camSpace = inv * SIMD4<Float>(wv, 1)
            let z = -camSpace.z  // ARKit: -Z forward, camera oldida z > 0
            if z <= 0.01 {
                // Vertex camera orqasida — UV degenerate, lekin SCN'da error
                // qilmaslik uchun (0, 0) qo'yamiz.
                uvs.append(SIMD2<Float>(0, 0))
                continue
            }
            // ARKit intrinsics standard pinhole. Camera frame: +X right, +Y up,
            // -Z forward. Image frame: +X right, +Y down. Y'ni teskari qilamiz.
            let proj = camera.intrinsics * SIMD3<Float>(camSpace.x, -camSpace.y, z)
            let pu = proj.x / proj.z
            let pv = proj.y / proj.z
            // SCN UV convention: (0,0) bottom-left, (1,1) top-right.
            // UIImage texture (SceneKit'da) origin top-left. Y'ni teskari qilamiz.
            let u = pu / camera.imageW
            let v = 1.0 - pv / camera.imageH
            uvs.append(SIMD2<Float>(u, v))
        }
        return uvs
    }

    /// Bitta world-space vertex'ni camera'ga proyeksiya qilib UV (0-1) qaytaradi.
    /// Camera orqasida yoki image tashqarisida bo'lsa nil.
    fileprivate static func projectOne(
        v: SIMD3<Float>,
        invTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        imageW: Float,
        imageH: Float,
    ) -> SIMD2<Float>? {
        let camSpace = invTransform * SIMD4<Float>(v, 1)
        let z = -camSpace.z
        if z <= 0.01 { return nil }
        // ARKit camera basis → image basis: y va z flip
        let proj = intrinsics * SIMD3<Float>(camSpace.x, -camSpace.y, z)
        let pu = proj.x / proj.z
        let pv = proj.y / proj.z
        // Image bounds margin (kichik chetdan tashlab)
        if pu < 4 || pu >= imageW - 4 || pv < 4 || pv >= imageH - 4 {
            return nil
        }
        // UV: x = pu/W, y = 1 - pv/H (SCN bottom-left convention)
        return SIMD2<Float>(pu / imageW, 1.0 - pv / imageH)
    }

    /// Sub-mesh SCNGeometry yaratish — per-triangle camera grouping uchun.
    /// Raw RGBA pixel buffer — vertex colors uchun image sampling'da ishlatiladi.
    /// `data` heap'da, ishlatishdan keyin `deallocate()` chaqiriladi.
    fileprivate struct ImagePixelBuffer {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let data: UnsafeMutablePointer<UInt8>

        func deallocate() {
            data.deallocate()
        }
    }

    /// JPEG fayldan RGBA pikselllarni yuklaydi (CoreGraphics orqali).
    /// Returns: width, height, bytesPerRow, allocated RGBA buffer.
    fileprivate static func loadImagePixels(url: URL) -> ImagePixelBuffer? {
        guard
            let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        let w = cg.width
        let h = cg.height
        let bytesPerRow = w * 4
        let totalBytes = bytesPerRow * h
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            | CGImageByteOrderInfo.order32Big.rawValue
        guard let ctx = CGContext(
            data: ptr, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: cs, bitmapInfo: bitmapInfo,
        ) else {
            ptr.deallocate()
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ImagePixelBuffer(width: w, height: h, bytesPerRow: bytesPerRow, data: ptr)
    }

    /// Vertex colors bilan SCNGeometry — texture yo'q, har vertex o'z rangiga ega.
    fileprivate static func buildVertexColoredGeometry(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        colors: [SIMD3<Float>],
        indices: [UInt32],
    ) -> SCNGeometry {
        let vData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let cData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }

        let vSrc = SCNGeometrySource(
            data: vData, semantic: .vertex,
            vectorCount: vertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let nSrc = SCNGeometrySource(
            data: nData, semantic: .normal,
            vectorCount: normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let cSrc = SCNGeometrySource(
            data: cData, semantic: .color,
            vectorCount: colors.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let elem = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size,
        )
        return SCNGeometry(sources: [vSrc, nSrc, cSrc], elements: [elem])
    }

    /// Atlas bake'dan keyin texture'siz (kulrang) triangle'larni tashlash.
    /// Har triangle uchun 4 ta sample point (centroid + edge midpoint'lar) atlas'da
    /// kulrang bo'lsa (RGB ≈ 128,128,128 — normalize kernel'ning fallback rangi),
    /// triangle texture'siz hisoblanadi va drop qilinadi.
    /// Polycam-style — texture'siz "clay" fragmentlar yo'qoladi.
    fileprivate static func dropUntexturedTriangles(
        bakeResult: AtlasBakeResult,
        grayTolerance: Int = 2,
        minGraySamples: Int = 4,
    ) -> AtlasBakeResult {
        guard let cgImage = bakeResult.atlas.cgImage else { return bakeResult }
        let atlasW = cgImage.width
        let atlasH = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bpp = cgImage.bitsPerPixel / 8
        guard let providerData = cgImage.dataProvider?.data else { return bakeResult }
        let bytes = CFDataGetBytePtr(providerData)!

        @inline(__always) func isGray(_ px: Int, _ py: Int) -> Bool {
            if px < 0 || px >= atlasW || py < 0 || py >= atlasH { return true }
            let offset = py * bytesPerRow + px * bpp
            let r = Int(bytes[offset])
            let g = Int(bytes[offset + 1])
            let b = Int(bytes[offset + 2])
            return abs(r - 128) <= grayTolerance &&
                   abs(g - 128) <= grayTolerance &&
                   abs(b - 128) <= grayTolerance
        }

        let triCount = bakeResult.indices.count / 3
        var newIndices: [UInt32] = []
        newIndices.reserveCapacity(bakeResult.indices.count)
        var droppedCount = 0
        for ti in 0..<triCount {
            let i0 = Int(bakeResult.indices[ti * 3 + 0])
            let i1 = Int(bakeResult.indices[ti * 3 + 1])
            let i2 = Int(bakeResult.indices[ti * 3 + 2])
            let uv0 = bakeResult.uvs[i0]
            let uv1 = bakeResult.uvs[i1]
            let uv2 = bakeResult.uvs[i2]
            let samples: [SIMD2<Float>] = [
                (uv0 + uv1 + uv2) / 3,
                (uv0 + uv1) / 2,
                (uv1 + uv2) / 2,
                (uv0 + uv2) / 2,
            ]
            var grayCount = 0
            for s in samples {
                let px = Int(s.x * Float(atlasW))
                let py = Int((1 - s.y) * Float(atlasH))
                if isGray(px, py) { grayCount += 1 }
            }
            if grayCount >= minGraySamples {
                droppedCount += 1
                continue
            }
            newIndices.append(bakeResult.indices[ti * 3 + 0])
            newIndices.append(bakeResult.indices[ti * 3 + 1])
            newIndices.append(bakeResult.indices[ti * 3 + 2])
        }
        NSLog("KADASTR untextured drop: \(droppedCount)/\(triCount) tri (gray atlas)")
        return AtlasBakeResult(
            atlas: bakeResult.atlas,
            vertices: bakeResult.vertices,
            normals: bakeResult.normals,
            uvs: bakeResult.uvs,
            indices: newIndices,
            atlasWidth: bakeResult.atlasWidth,
            atlasHeight: bakeResult.atlasHeight,
        )
    }

    fileprivate static func buildSubMeshGeometry(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        indices: [UInt32],
    ) -> SCNGeometry {
        let vData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }

        let vSrc = SCNGeometrySource(
            data: vData, semantic: .vertex,
            vectorCount: vertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let nSrc = SCNGeometrySource(
            data: nData, semantic: .normal,
            vectorCount: normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let uvSrc = SCNGeometrySource(
            data: uvData, semantic: .texcoord,
            vectorCount: uvs.count, usesFloatComponents: true,
            componentsPerVector: 2, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD2<Float>>.stride,
        )
        let elem = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size,
        )
        return SCNGeometry(sources: [vSrc, nSrc, uvSrc], elements: [elem])
    }

    /// Atlas mild sharpening. Manba rasmlar 1920×1440 ultra-wide (yumshoq optika) —
    /// yo'qolgan detail qaytmaydi, lekin CIUnsharpMask qirra/tugma kontrastini
    /// aniqlashtiradi. radius 1.8 / intensity 0.5: halo va grain'siz mild (Mac'da
    /// solishtirib tanlangan; 2.5/0.7 halo+grain, LUMIN deyarli ta'sirsiz).
    fileprivate static func sharpenAtlas(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let ci = CIImage(cgImage: cg)
        guard let f = CIFilter(name: "CIUnsharpMask") else { return image }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(1.8, forKey: kCIInputRadiusKey)
        f.setValue(0.5, forKey: kCIInputIntensityKey)
        guard let out = f.outputImage,
              let outCG = CIContext(options: nil).createCGImage(out, from: ci.extent)
        else { return image }
        return UIImage(cgImage: outCG)
    }

    /// AnchorRaw'dan SCNGeometry yaratish — vertex (world-space), normal, UV (optional).
    fileprivate static func buildAnchorGeometry(
        anchor: AnchorRaw, uvs: [SIMD2<Float>]?,
    ) -> SCNGeometry {
        let vData = anchor.worldVertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = anchor.worldNormals.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = anchor.indices.withUnsafeBufferPointer { Data(buffer: $0) }

        let vSrc = SCNGeometrySource(
            data: vData, semantic: .vertex,
            vectorCount: anchor.worldVertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let nSrc = SCNGeometrySource(
            data: nData, semantic: .normal,
            vectorCount: anchor.worldNormals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        var sources: [SCNGeometrySource] = [vSrc, nSrc]
        if let uvs = uvs {
            let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
            let uvSrc = SCNGeometrySource(
                data: uvData, semantic: .texcoord,
                vectorCount: uvs.count, usesFloatComponents: true,
                componentsPerVector: 2, bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0, dataStride: MemoryLayout<SIMD2<Float>>.stride,
            )
            sources.append(uvSrc)
        }
        let elem = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: anchor.indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size,
        )
        return SCNGeometry(sources: sources, elements: [elem])
    }

    // Legacy per-vertex color export — endi ishlatilmaydi (USDZ vertex color
    // qo'llab-quvvatlamaydi). Kelajakda multi-camera blending uchun reference
    // sifatida saqlanyapti. Hozirgi `runCustomMeshExport` per-anchor UV texture
    // mapping orqali ishlaydi.
    // ignore: unused
    private static func computePerVertexColors_unused(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        poses: [[String: Any]],
        folder: URL,
    ) -> [SIMD3<Float>] {
        // Default oranj (diagnostic — agar mesh oranj chiqsa color source ishlaydi).
        var colors = Array(repeating: SIMD3<Float>(1.0, 0.5, 0.0), count: vertices.count)

        // Pose'larni structured form'da yig'ish + camera image'ni yuklash.
        struct CamFrame {
            let transform: simd_float4x4
            let intrinsics: simd_float3x3
            let imageW: Float
            let imageH: Float
            let pixels: CGImage  // RGB pixel data
            let bitmap: (data: UnsafePointer<UInt8>, bytesPerRow: Int, width: Int, height: Int)
            let dataProvider: CFData  // pixels'ni saqlab turish uchun
        }
        var frames: [CamFrame] = []
        frames.reserveCapacity(poses.count)
        for entry in poses {
            guard
                let idx = entry["index"] as? Int,
                let tRows = entry["transform_matrix"] as? [[Float]],
                tRows.count == 4,
                let kRows = entry["intrinsics"] as? [[Float]],
                kRows.count == 3,
                let w = entry["image_width"] as? Int,
                let h = entry["image_height"] as? Int
            else { continue }
            // Image fayl: photo_NNNN.jpg
            let imgURL = folder.appendingPathComponent(String(format: "photo_%04d.jpg", idx))
            guard let cgImage = loadCGImage(from: imgURL) else { continue }
            // Bitmap data — pikselni tezda sample qilish uchun.
            guard let data = cgImage.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data)
            else { continue }
            let bpp = cgImage.bitsPerPixel
            // Faqat 32 bpp (RGBA) yoki 24 bpp (RGB) qo'llab-quvvatlanadi.
            guard bpp == 32 || bpp == 24 else { continue }

            // recordPose row-major saqlagan: rowI = [col0[I], col1[I], col2[I], col3[I]]
            // → matrix transpose qilish kerak (simd_float4x4 columns).
            let t = simd_float4x4(rows: [
                SIMD4<Float>(tRows[0][0], tRows[0][1], tRows[0][2], tRows[0][3]),
                SIMD4<Float>(tRows[1][0], tRows[1][1], tRows[1][2], tRows[1][3]),
                SIMD4<Float>(tRows[2][0], tRows[2][1], tRows[2][2], tRows[2][3]),
                SIMD4<Float>(tRows[3][0], tRows[3][1], tRows[3][2], tRows[3][3]),
            ])
            let k = simd_float3x3(rows: [
                SIMD3<Float>(kRows[0][0], kRows[0][1], kRows[0][2]),
                SIMD3<Float>(kRows[1][0], kRows[1][1], kRows[1][2]),
                SIMD3<Float>(kRows[2][0], kRows[2][1], kRows[2][2]),
            ])
            frames.append(CamFrame(
                transform: t,
                intrinsics: k,
                imageW: Float(w),
                imageH: Float(h),
                pixels: cgImage,
                bitmap: (bytes, cgImage.bytesPerRow, cgImage.width, cgImage.height),
                dataProvider: data,
            ))
        }

        guard !frames.isEmpty else { return colors }

        // Har vertex uchun eng yaxshi camera tanlash.
        for vi in 0..<vertices.count {
            let v = vertices[vi]
            let n = normals[vi]
            var bestColor: SIMD3<Float>? = nil
            var bestScore: Float = -.infinity
            for cam in frames {
                // World → camera frame
                let invT = cam.transform.inverse
                let camPos = invT * SIMD4<Float>(v, 1)
                // ARKit camera looks down -Z (camera'dan oldindagi nuqta z<0)
                let z = -camPos.z
                if z <= 0.05 { continue }  // juda yaqin yoki orqada
                // Image projection: u = fx*x/z + cx, v = fy*y/z + cy
                // ARKit camera image: y o'qi pastga (pixel), camera frame y yuqoriga
                let proj = cam.intrinsics * SIMD3<Float>(camPos.x, -camPos.y, z)
                let u = proj.x / proj.z
                let vImg = proj.y / proj.z
                if u < 1 || u >= cam.imageW - 1 || vImg < 1 || vImg >= cam.imageH - 1 {
                    continue
                }
                // Score: yaqin + perpendicular (vertex normal ↔ camera ray angle)
                // Camera ray: world space'dan vertex'gacha
                let camOrigin = SIMD3<Float>(
                    cam.transform.columns.3.x,
                    cam.transform.columns.3.y,
                    cam.transform.columns.3.z,
                )
                let viewDir = simd_normalize(camOrigin - v)
                let dot = max(0, simd_dot(viewDir, n))  // 1 = perpendicular, 0 = grazing
                let dist = simd_length(camOrigin - v)
                let score = dot * 2.0 - dist  // closer + perpendicular yaxshiroq
                if score > bestScore {
                    bestScore = score
                    // Pikselni o'qish — bitmap orientation hisobga olib.
                    // ARKit camera image orientation: landscape right (default).
                    let px = Int(u)
                    let py = Int(vImg)
                    let bpp = cam.pixels.bitsPerPixel / 8
                    let offset = py * cam.bitmap.bytesPerRow + px * bpp
                    let r = Float(cam.bitmap.data[offset]) / 255.0
                    let g = Float(cam.bitmap.data[offset + 1]) / 255.0
                    let b = Float(cam.bitmap.data[offset + 2]) / 255.0
                    bestColor = SIMD3<Float>(r, g, b)
                }
            }
            if let c = bestColor {
                colors[vi] = c
            }
        }

        return colors
    }

    /// JPG faylni CGImage'ga yuklaydi. ImageIO orqali.
    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// SCNGeometry yaratish — vertex, normal, color sources + triangle elements.
    private static func buildColoredGeometry(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        colors: [SIMD3<Float>],
        indices: [UInt32],
    ) -> SCNGeometry {
        let vData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let cData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }

        let vSrc = SCNGeometrySource(
            data: vData, semantic: .vertex,
            vectorCount: vertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let nSrc = SCNGeometrySource(
            data: nData, semantic: .normal,
            vectorCount: normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let cSrc = SCNGeometrySource(
            data: cData, semantic: .color,
            vectorCount: colors.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride,
        )
        let elem = SCNGeometryElement(
            data: iData, primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size,
        )
        return SCNGeometry(sources: [vSrc, nSrc, cSrc], elements: [elem])
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
        // Eslatma: `isObjectMaskingEnabled` faqat macOS PhotogrammetrySession'da
        // mavjud. iOS'da bu property yo'q. iOS'da PhotogrammetrySession har doim
        // single-obyekt mode'ida ishlaydi — shu sababli biz endi shu API'ni
        // ishlatmayapmiz. `runPhotogrammetry` legacy qoldirildi, lekin
        // `startProcessing` o'rniga `runCustomMeshExport` chaqirilyapti.

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
    //
    // Polycam-style: har ARMeshAnchor uchun 2 ta sub-node:
    //   - "fill"  = yarim shaffof ko'k overlay (capture qilinmagan joy belgisi)
    //   - "wire"  = oq triangle wireframe (LiDAR mesh ko'rinishi)
    // Capture coverage tracking keyingi versiyada — hozir hamma faces ko'k.

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        applyPolycamStyle(to: node, meshAnchor: meshAnchor)
        updateMeshArea(for: meshAnchor)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        applyPolycamStyle(to: node, meshAnchor: meshAnchor)
        updateMeshArea(for: meshAnchor)
    }

    private func applyPolycamStyle(to node: SCNNode, meshAnchor: ARMeshAnchor) {
        // Avvalgi child node'larni o'chiramiz (didUpdate har frame'da chaqirilishi mumkin).
        node.childNodes.forEach { $0.removeFromParentNode() }

        // Capture boshlanmagan bo'lsa — visualization yo'q. Foydalanuvchi avval
        // kameradan toza ko'rinish oladi. Mesh overlay quyidagi holatlarda ko'rinadi:
        //   • Auto rejimda Play bosilgan (isCapturing=true)
        //   • Manual rejimda kamida 1 ta foto olingan (captureCount>0)
        //   • Auto rejimda Pause bosilgan, lekin allaqachon skan boshlangan
        guard isCapturing || captureCount > 0 else { return }

        // Polycam-style coverage visualization:
        //   • Uncaptured (coverage=0) → ko'k yarim-shaffof fill
        //   • Captured (coverage≥1)   → oq wireframe (mesh strukturasi ko'rinadi)
        let coverage = anchorCoverage[meshAnchor.identifier] ?? 0
        let geom = SCNGeometry.fromARMesh(meshAnchor.geometry)
        if coverage == 0 {
            geom.materials = [Self.coverageMaterial(coverage: 0)]
        } else {
            geom.materials = [Self.meshMaterial()]
        }
        let visNode = SCNNode(geometry: geom)
        visNode.name = coverage == 0 ? "fill" : "wire"
        node.addChildNode(visNode)
    }

    /// isCapturing o'zgarganda barcha mavjud mesh anchor visualization'larni
    /// yangilash — Play bosilganda darrov ko'rsatish, Pause bosganda yashirish.
    private func refreshAllAnchorVisualizations() {
        guard let frame = arView.session.currentFrame else { return }
        for anchor in frame.anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor,
                  let node = arView.node(for: meshAnchor) else { continue }
            applyPolycamStyle(to: node, meshAnchor: meshAnchor)
        }
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

    private static func uncapturedMaterial() -> SCNMaterial {
        // Polycam-style: ko'k yarim shaffof overlay — "bu joy hali capture qilinmagan"
        // signali. Foydalanuvchi telefonni shu yo'nalishga qaratganda LiDAR mesh
        // anchor avtomatik yangilanadi va overlay ham ko'rinadi.
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.fillMode = .fill
        m.diffuse.contents = UIColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1.0)
        m.transparency = 0.35
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        return m
    }

    /// Coverage rangga aylantirish — capture sifati'ni vizualizatsiya qilish.
    /// 0 photo → qizil (yaxshi capture kerak), >12 photo → ko'k (yaxshi covered).
    private static func coverageMaterial(coverage: Int) -> SCNMaterial {
        // Polycam-style binary: faqat UNCAPTURED joylar ko'k.
        // 1 yoki ortiq foto'da ko'ringan joylar to'liq shaffof — kamera ko'rinadi.
        let alpha: CGFloat = (coverage == 0) ? 0.65 : 0.0
        let color = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1.0)  // Polycam blue
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.fillMode = .fill
        m.diffuse.contents = color
        m.transparency = alpha
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

// MARK: - RoomPlan integratsiya (iOS 17+ optional)

#if canImport(RoomPlan)
@available(iOS 17.0, *)
extension TexturedScanViewController: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        // Real-time room updates — har frame'da yangilangan room data.
        // Oxirgi versiya saqlanadi, Done bosilganda ishlatiladi.
        capturedRoomData = room
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        if let error = error {
            NSLog("KADASTR RoomCaptureSession ended with error: \(error)")
        } else {
            NSLog("KADASTR RoomCaptureSession ended normally")
        }
    }
}

@available(iOS 16.0, *)
enum RoomPlanSurfaceMesher {
    /// CapturedRoom surfaces'larini (walls, doors, windows, openings) planar
    /// triangle mesh'ga aylantiradi. Glass eshik / silliq metal kabi LiDAR
    /// ko'rmagan yuzalar uchun fill mesh.
    static func surfaceMesh(from room: CapturedRoom) -> (verts: [SIMD3<Float>], normals: [SIMD3<Float>], tris: [(v0: UInt32, v1: UInt32, v2: UInt32)]) {
        var verts: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []

        func add(_ surface: CapturedRoom.Surface) {
            let w = surface.dimensions.x
            let h = surface.dimensions.y
            let hw = w / 2
            let hh = h / 2
            // Local-space 4 corners on Z=0 plane (surface normal = +Z)
            let corners: [SIMD3<Float>] = [
                SIMD3(-hw, -hh, 0),
                SIMD3(hw, -hh, 0),
                SIMD3(hw, hh, 0),
                SIMD3(-hw, hh, 0),
            ]
            let xform = surface.transform
            let worldCorners = corners.map { c -> SIMD3<Float> in
                let w4 = xform * SIMD4(c.x, c.y, c.z, 1)
                return SIMD3(w4.x, w4.y, w4.z)
            }
            // World-space normal: transform local +Z via upper 3x3
            let n = simd_normalize(SIMD3<Float>(
                xform.columns.2.x, xform.columns.2.y, xform.columns.2.z,
            ))
            let base = UInt32(verts.count)
            verts.append(contentsOf: worldCorners)
            normals.append(contentsOf: [n, n, n, n])
            // 2 triangles: (0,1,2) va (0,2,3) — CCW from +Z
            tris.append((v0: base, v1: base + 1, v2: base + 2))
            tris.append((v0: base, v1: base + 2, v2: base + 3))
        }

        for wall in room.walls { add(wall) }
        for door in room.doors { add(door) }
        for window in room.windows { add(window) }
        for opening in room.openings { add(opening) }
        // NOTE: room.objects (mebellar) skip — ular box, surface emas.
        //       Kerak bo'lsa keyinroq object-as-box geometry qo'shamiz.

        return (verts, normals, tris)
    }
}
#endif


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
        quality: String = "balanced",
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
        // Quality default'i yangilanadi — TexturedScanViewController photo
        // qabul qilgach `onPhotosReady` orqali handlePhotosReady'ga uzatadi.
        self.selectedQuality = quality

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
        // Capture VC ni yopib, upload progress ekraniga o'tamiz.
        // Eslatma: `quality` — bu capture VC'ning ichki quality field'i
        // (eski "standard"/"high" capture preset'lari). Flutter'dan kelgan
        // training quality preset (draft/balanced/max) ustuvor — start()'da
        // o'rnatilgan `self.selectedQuality` ni saqlaymiz.
        guard let presenter = presentingController else { return }
        // Eski capture quality faqat agar Flutter explicit quality bermagan
        // bo'lsa ishlatamiz. Hozir Flutter doim default "balanced" yuboradi,
        // shuning uchun bu nadeshda no-op:
        if self.selectedQuality == "standard" {
            self.selectedQuality = quality
        }
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
        // GPU pipeline buni topganda COLMAP SfM bosqichini butunlay o'tkazib
        // yuboradi va ARKit pose'laridan to'g'ridan-to'g'ri foydalanadi
        // (yangi pipeline'da COLMAP umuman ishlatilmaydi).
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

        // LiDAR depth fayllar (depth_NNNN.bin) — splatfacto uchun OLTIN.
        // Pipeline ulardan sparse_pc.ply yaratadi (random init dan 5-10× yaxshi)
        // va depth supervision aktivlashtiradi (floaters keskin kamayadi).
        // Har depth fayl ~150-500 KB, jami ~100 MB qo'shimcha 300 kadr uchun.
        let depthFiles = files.filter {
            $0.lastPathComponent.hasPrefix("depth_") && $0.pathExtension.lowercased() == "bin"
        }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        for url in depthFiles {
            writeStr("--\(boundary)\r\n")
            writeStr("Content-Disposition: form-data; name=\"depths\"; filename=\"\(url.lastPathComponent)\"\r\n")
            writeStr("Content-Type: application/octet-stream\r\n\r\n")
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

        // Gravity vektorlari (gravity_NNNN.json) — har biri ~50 bayt.
        // Kelajakdagi PhotogrammetrySession integratsiyasi va to'g'ri
        // orientatsiya validatsiyasi uchun zaxirada saqlanadi.
        let gravityFiles = files.filter {
            $0.lastPathComponent.hasPrefix("gravity_") && $0.pathExtension.lowercased() == "json"
        }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        for url in gravityFiles {
            writeStr("--\(boundary)\r\n")
            writeStr("Content-Disposition: form-data; name=\"gravities\"; filename=\"\(url.lastPathComponent)\"\r\n")
            writeStr("Content-Type: application/json\r\n\r\n")
            if let data = try? Data(contentsOf: url) {
                bodyHandle.write(data)
            }
            writeStr("\r\n")
        }

        writeStr("--\(boundary)--\r\n")
        try? bodyHandle.synchronize()
        try? bodyHandle.close()

        request.timeoutInterval = 600  // 10 daqiqa

        // Realtime upload progress — har `didSendBodyData` chaqirig'ida
        // UI'ga "X / Y ta · pct%" yetkaziladi (taxminiy foto soni bytes nisbatidan).
        let photoCount = jpegs.count
        let progressDelegate = HybridUploadProgressDelegate { [weak self] sent, total in
            Task { @MainActor [weak self] in
                self?.uploadVC?.setProgress(uploaded: sent, total: total, photoCount: photoCount)
            }
        }
        let session = URLSession(
            configuration: .default,
            delegate: progressDelegate,
            delegateQueue: nil,
        )
        defer { session.finishTasksAndInvalidate() }

        // uploadTask(fromFile:) — disk'dan tarmoqqa stream, xotira yuklanmaydi
        let (data, response) = try await session.upload(for: request, fromFile: tmpBody)
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


/// Upload progress UI — spinner + status + realtime progress (foto soni + foiz + MB).
@available(iOS 17.0, *)
final class HybridUploadViewController: UIViewController {
    var onCancel: (() -> Void)?

    private let statusLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let accent = UIColor(red: 0/255, green: 225/255, blue: 53/255, alpha: 1)

        spinner.color = accent
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

        progressBar.progressTintColor = accent
        progressBar.trackTintColor = .white.withAlphaComponent(0.15)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        view.addSubview(progressBar)

        progressLabel.text = ""
        progressLabel.numberOfLines = 0
        progressLabel.textAlignment = .center
        progressLabel.textColor = .white.withAlphaComponent(0.75)
        progressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.isHidden = true
        view.addSubview(progressLabel)

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Bekor qilish", for: .normal)
        cancelBtn.setTitleColor(.white.withAlphaComponent(0.7), for: .normal)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            progressBar.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -48),
            progressBar.heightAnchor.constraint(equalToConstant: 4),
            progressLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 12),
            progressLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            cancelBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            cancelBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    func setStatus(_ text: String) {
        statusLabel.text = text
        // Polling/processing fazasida progress bar'ni yashir.
        progressBar.isHidden = true
        progressLabel.isHidden = true
    }

    /// Realtime upload progress: `uploaded`/`total` baytlar va `photoCount` —
    /// taxminiy foto soni `uploaded / total * photoCount` orqali hisoblanadi.
    func setProgress(uploaded: Int64, total: Int64, photoCount: Int) {
        guard total > 0 else { return }
        let fraction = Double(uploaded) / Double(total)
        let pct = Int(fraction * 100)
        let estPhotos = min(photoCount, Int(fraction * Double(photoCount)))
        let mbUp = Double(uploaded) / 1_048_576.0
        let mbTot = Double(total) / 1_048_576.0

        statusLabel.text = "Foto'lar yuklanmoqda"
        progressBar.isHidden = false
        progressLabel.isHidden = false
        progressBar.setProgress(Float(fraction), animated: true)
        progressLabel.text = "\(estPhotos) / \(photoCount) ta · \(pct)%\n\(String(format: "%.1f", mbUp)) / \(String(format: "%.1f", mbTot)) MB"
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}

/// URLSession delegate — upload bytes progress callback.
@available(iOS 17.0, *)
final class HybridUploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Int64, Int64) -> Void
    init(onProgress: @escaping (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
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
    /// `combine` ning quyi versiyasi — SCNGeometry o'rniga raw arrays qaytaradi
    /// (per-vertex color hisoblash uchun). Vertex'lar world-space'da.
    static func combineRaw(arView: ARSCNView) -> (vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32])? {
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
        return (vertices, normals, indices)
    }

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
    /// Local processing rejimi (uploadMode=false) — quality picker yashiriladi,
    /// confirm tugmasi "Process" deb yozilib, lokal pipeline boshlaydi.
    var localProcessingMode: Bool = false
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
        // Local processing'da quality picker yashiriladi — sifat doim "standard".
        qualitySegment.isHidden = localProcessingMode
        panel.addSubview(qualitySegment)

        estLabel = UILabel()
        estLabel.text = formatEta()
        estLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        estLabel.font = .systemFont(ofSize: 12, weight: .regular)
        estLabel.textAlignment = .center
        estLabel.translatesAutoresizingMaskIntoConstraints = false
        estLabel.isHidden = localProcessingMode
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
        confirmBtn.setTitle(localProcessingMode ? "Process" : "Yuborish", for: .normal)
        confirmBtn.setTitleColor(.white, for: .normal)
        confirmBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        confirmBtn.backgroundColor = UIColor(red: 0, green: 0.88, blue: 0.21, alpha: 1)
        confirmBtn.layer.cornerRadius = 22
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false
        confirmBtn.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        panel.addSubview(confirmBtn)

        // Continue button top anchor — local mode'da quality picker yashirin,
        // shuning uchun continueBtn'ni panel topiga yaqinlashtiramiz.
        let continueBtnTop: NSLayoutConstraint = localProcessingMode
            ? continueBtn.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14)
            : continueBtn.topAnchor.constraint(equalTo: estLabel.bottomAnchor, constant: 14)

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
            qualitySegment.heightAnchor.constraint(equalToConstant: localProcessingMode ? 0 : 32),

            estLabel.topAnchor.constraint(equalTo: qualitySegment.bottomAnchor, constant: localProcessingMode ? 0 : 6),
            estLabel.centerXAnchor.constraint(equalTo: panel.centerXAnchor),

            continueBtnTop,
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
