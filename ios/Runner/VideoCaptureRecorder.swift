// VideoCaptureRecorder — video yozib olish: qurilmadagi ENG PAST zoom
// (0.5x ultra-wide; ultra-wide yo'q bo'lsa 1x) + 60 fps + qurilma
// qo'llaydigan eng yuqori rezolutsiya (4K gacha, `activeFormat` orqali).
//
// 60 fps QAT'IY talab (3DGS quvuri uchun): ko'proq xom kadr — kadr tanlash
// bosqichi o'tkirroqlarini topadi. Shu sababli format tanlashda fps
// rezolutsiyadan USTUN: avval 60 fps beradigan formatlar ko'riladi, ular
// bo'lmasagina 30 fps ga tushiladi.
//
// Flutter "kadastr/video_capture" kanali orqali chaqiriladi: modal recorder
// ochiladi, foydalanuvchi yozib tugatgach fayl yo'li Flutter'ga qaytadi.
// Bekor qilinsa — nil.
//
// Android egizagi: android/.../VideoCaptureActivity.kt (CameraX).
//
// Lens tanlash tartibi (eng keng kadr — eng past zoom):
//   1. .builtInUltraWideCamera  — fizik 0.5x lens, kadr o'rtasida almashmaydi
//   2. .builtInDualWideCamera   — virtual qurilma, zoom 1.0 = ultra-wide (0.5x)
//   3. .builtInWideAngleCamera  — 0.5x yo'q qurilmalar uchun fallback (1x)
//
// Ovoz yozilmaydi — Info.plist'da NSMicrophoneUsageDescription yo'q, va bu
// capture 3D quvuri uchun (ovoz kerak emas).
//
// YUK BUDJETI (o'lchangan, iPhone 13 Pro Max):
// 4K60 ultra-wide — kameraning eng og'ir rejimi. Uzoq yozuvda ISP kadr
// tashlaydi: 215 s da 60 fps so'ralib faylga 9974 kadr, ya'ni 46.4 fps
// tushgan (23% yo'qolgan); 4 s da esa aniq 60.0 fps. Shu sababli bu yerda
// yukni oshiradigan HAR NARSA olib tashlangan yoki chegaralangan:
//   - `cinematicExtended` EIS faqat <=30 fps da (60 fps da `.standard`);
//   - HDR (10-bit) qat'iy o'chirilgan — quvur baribir SDR ga tushiradi;
//   - qizigan telefonda rezolutsiya pasayadi (linza va fps tegilmaydi).
// Yozuvdan keyin haqiqiy fps fayldan o'qiladi — yorliq taxmin qilmaydi.

import AVFoundation
import Flutter
import UIKit

/// Method-channel tomoni: recorder'ni modal ko'rsatadi va natijani bir marta
/// (finish/cancel/error) Flutter'ga uzatadi.
final class VideoCaptureCoordinator: NSObject {
    static let shared = VideoCaptureCoordinator()

    private var pendingResult: FlutterResult?
    private weak var recorderVC: VideoCaptureViewController?

    /// Qurilmada orqa kamera bormi (simulyatorda — yo'q).
    static var isSupported: Bool {
        VideoCaptureViewController.bestBackCamera() != nil
    }

    func start(from controller: UIViewController, result: @escaping FlutterResult) {
        if pendingResult != nil {
            result(FlutterError(
                code: "ALREADY_RECORDING",
                message: "Oldingi video yozuv hali tugamagan",
                details: nil,
            ))
            return
        }
        guard VideoCaptureCoordinator.isSupported else {
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Qurilmada orqa kamera topilmadi",
                details: nil,
            ))
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard granted else {
                    result(FlutterError(
                        code: "PERMISSION",
                        message: "Kameraga ruxsat berilmagan",
                        details: nil,
                    ))
                    return
                }
                self.present(from: controller, result: result)
            }
        }
    }

    private func present(from controller: UIViewController, result: @escaping FlutterResult) {
        pendingResult = result

        let vc = VideoCaptureViewController()
        vc.onFinished = { [weak self] payload in self?.deliver(payload) }
        vc.onCancel = { [weak self] in self?.deliver(nil) }
        vc.onFailed = { [weak self] message in
            self?.deliver(error: FlutterError(
                code: "RECORD_FAILED",
                message: message,
                details: nil,
            ))
        }
        vc.modalPresentationStyle = .fullScreen
        recorderVC = vc
        controller.present(vc, animated: true)
    }

    private func deliver(_ payload: [String: Any]?) {
        deliver(error: nil, payload: payload)
    }

    private func deliver(error: FlutterError?, payload: [String: Any]? = nil) {
        guard let result = pendingResult else { return }
        pendingResult = nil
        recorderVC?.dismiss(animated: true)
        recorderVC = nil
        result(error ?? payload)
    }
}

/// To'liq ekranli recorder: preview + yozish tugmasi + taymer.
final class VideoCaptureViewController: UIViewController,
                                        AVCaptureFileOutputRecordingDelegate {
    var onFinished: (([String: Any]) -> Void)?
    var onCancel: (() -> Void)?
    var onFailed: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "kadastr.video.capture")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var device: AVCaptureDevice?
    private var zoomLabelText = "1x"
    private var sizeLabelText = "1080p"
    private var videoFps = 0
    private var videoWidth = 0
    private var videoHeight = 0

    /// EIS — sifat uchun eng katta yutuq, LEKIN kadrni ~10% qirqadi, ya'ni
    /// 0.5x ning keng ko'rish burchagidan biroz yo'qotadi. Fotogrammetriya
    /// uchun xom kadr kerak bo'lsa `false` qiling (Android'dagi
    /// `STABILIZATION` bilan juft).
    private static let stabilization = true

    private var isRecording = false
    private var startedAt: Date?
    private var tickTimer: Timer?
    private var stabilizationName = "off"
    private var thermalAtStart = "?"

    /// Foydalanuvchi tugmani bosdimi. Bu bo'lmasa yozuvning tugashi —
    /// tizim to'xtatgani, ya'ni buni YASHIRMASLIK kerak.
    private var stoppedByUser = false

    /// Yozuv paytida sessiya uzilgan bo'lsa — sababi.
    private var interruptionReason: String?

    /// Xotira tugashiga qancha qoldi: yozuvni to'xtatishga majbur qiladigan
    /// asosiy sabab shu. 4K60 ≈ 62 Mbit/s ≈ 7.8 MB/s, ya'ni daqiqasiga
    /// ~465 MB. Uch daqiqalik xona ~1.4 GB joy talab qiladi.
    private static let bytesPerSecondEstimate: Int64 = 7_800_000

    /// AVFoundation yozuvni shu chegaradan oldin to'xtatadi — diskni to'la
    /// to'ldirib qo'yishdan ko'ra, aniq `diskFull` xatosi bilan tugash
    /// yaxshi (tizim o'zi to'xtatganda sabab noma'lum qolardi).
    private static let freeSpaceFloor: Int64 = 300 * 1024 * 1024

    private let recordButton = UIButton(type: .custom)
    private let recordInner = UIView()
    private let timerLabel = UILabel()
    private let badgeLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    // MARK: - Lens

    /// 0.5x ni beradigan eng yaxshi orqa kamera. Ultra-wide yo'q bo'lsa —
    /// oddiy wide (u holda kadr 1x bo'ladi va badge shuni ko'rsatadi).
    static func bestBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera,
        ]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    /// Kamera ilovasidagidek yorliq: "0.5x" | "0.6x" | "1x". Hech qachon
    /// taxmin qilmaydi — virtual qurilmada switch-over faktoridan, fizik
    /// ultra-wide'da asosiy (wide) kamera bilan FOV nisbatidan hisoblanadi.
    static func displayZoomLabel(for device: AVCaptureDevice) -> String {
        let factor: Double
        if let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue,
           switchOver > 1 {
            // Masalan dual-wide: 2.0 → ultra-wide 0.5x.
            factor = 1 / switchOver
        } else if device.deviceType == .builtInUltraWideCamera,
                  let wide = AVCaptureDevice.default(
                      .builtInWideAngleCamera, for: .video, position: device.position),
                  wide.uniqueID != device.uniqueID {
            let ultraHalf = Double(device.activeFormat.videoFieldOfView) / 2 * .pi / 180
            let wideHalf = Double(wide.activeFormat.videoFieldOfView) / 2 * .pi / 180
            factor = ultraHalf > 0 ? tan(wideHalf) / tan(ultraHalf) : 1
        } else {
            factor = 1  // qurilmada ultra-wide yo'q
        }
        let rounded = (factor * 10).rounded() / 10
        return rounded >= 1
            ? String(format: "%.0fx", rounded)
            : String(format: "%.1fx", rounded)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
        sessionQueue.async { [weak self] in self?.configureSession() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTicker()
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    override var prefersStatusBarHidden: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Session

    private func configureSession() {
        guard let device = VideoCaptureViewController.bestBackCamera() else {
            DispatchQueue.main.async { [weak self] in
                self?.onFailed?("Orqa kamera topilmadi")
            }
            return
        }
        self.device = device

        session.beginConfiguration()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw NSError(domain: "kadastr.video", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Kamera input qo'shilmadi",
                ])
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.onFailed?(error.localizedDescription)
            }
            return
        }

        guard session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.onFailed?("Video output qo'shilmadi")
            }
            return
        }
        session.addOutput(movieOutput)
        // Fragment yozmasin — moov atomi oxirida bir marta yoziladi.
        movieOutput.movieFragmentInterval = .invalid
        // Virtual qurilma (dual-wide) yozuv o'rtasida linzani almashtirib
        // yuborishi mumkin — 0.5x da boshlangan klip 1x ga sakraydi.
        movieOutput.isPrimaryConstituentDeviceSwitchingBehaviorForRecordingEnabled = false
        applyBestQuality(to: device)
        // Aylantirish va stabilizatsiya — AYNAN shu yerda, begin/commit
        // ichida. Ilgari `commitConfiguration()` dan keyin qo'yilgan edi va
        // `preferredVideoStabilizationMode` ni tirik ulanishga berish sessiyani
        // yashirincha qayta sozlashga majbur qilardi (yozuv boshida sakrash).
        applyConnectionSettings()
        session.commitConfiguration()

        // 0.5x: ultra-wide fizik lensda ham, dual-wide virtual qurilmada ham
        // minimal zoom (1.0) aynan ultra-wide kadrni beradi.
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(1.0, device.minAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {
            // Zoom o'rnatilmasa ham yozuv davom etadi.
        }

        zoomLabelText = VideoCaptureViewController.displayZoomLabel(for: device)

        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        videoWidth = Int(dims.width)
        videoHeight = Int(dims.height)

        // Bo'sh joyni AVFoundation ham biladi: shu chegaraga yetganda yozuvni
        // o'zi to'xtatadi va bizga `diskFull` xatosini beradi. Aks holda
        // to'xtash sababi noma'lum qoladi.
        movieOutput.minFreeDiskSpaceLimit = Self.freeSpaceFloor

        observeSystemEvents()

        DebugLog.log("VIDEO", "session \(videoWidth)x\(videoHeight)@\(videoFps) "
            + "lens=\(device.localizedName) thermal=\(Self.thermalName) "
            + "free=\(Self.freeSpaceLabel) eis=\(stabilizationName)")
        session.startRunning()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.attachPreview()
            // Yorliqda joy bo'yicha cheklov ham ko'rinadi: 4K60 daqiqasiga
            // ~465 MB yeydi, shuning uchun "qancha yozish mumkin" yozuvni
            // boshlashdan oldin bilinishi kerak.
            let minutes = Self.recordableSeconds / 60
            let room = minutes < 15 ? " · ~\(minutes) daq" : ""
            self.badgeLabel.text =
                "  \(self.zoomLabelText) · \(self.sizeLabelText)\(room)  "
            self.recordButton.isEnabled = true
        }
    }

    /// Eng yuqori sifat: `sessionPreset` EMAS, `activeFormat`. Ikkalasini
    /// birga ishlatib bo'lmaydi — preset qo'yilsa sessiya formatni o'zi
    /// boshqaradi va bizni 1080p'ga qamab qo'yadi (eski xatti-harakat).
    private func applyBestQuality(to device: AVCaptureDevice) {
        guard let format = VideoCaptureViewController.bestFormat(
            for: device, maxHeight: Self.resolutionCeiling()) else {
            // Mos format topilmadi — eski preset yo'li.
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
                sizeLabelText = "1080p"
            } else {
                session.sessionPreset = .high
                sizeLabelText = "HD"
            }
            return
        }
        do {
            try device.lockForConfiguration()
            session.sessionPreset = .inputPriority
            device.activeFormat = format
            // Format 60 ni qo'llasa — 60, aks holda 30. min va max bir xil:
            // o'zgaruvchan kadr tezligi kadrlar orasidagi vaqtni buzadi va
            // cinematicExtended ham qat'iy oraliqni so'raydi. Format'ni
            // o'rnatgach frame duration reset bo'ladi — shu sababli shu yerda.
            let fps = VideoCaptureViewController.supports(format, fps: 60) ? 60 : 30
            if VideoCaptureViewController.supports(format, fps: Double(fps)) {
                let step = CMTime(value: 1, timescale: CMTimeScale(fps))
                device.activeVideoMinFrameDuration = step
                device.activeVideoMaxFrameDuration = step
                videoFps = fps
            }

            // HDR ni QAT'IY o'chiramiz. Ikki sabab: (1) 3DGS quvuri HDR ni
            // baribir SDR ga tone-map qiladi, ya'ni 10-bit foyda bermaydi;
            // (2) 4K60 da HDR ISP ga qo'shimcha yuk — aynan shu yuk kadr
            // tashlashni keltirib chiqaradi. Avtomatik rejim qoldirilsa iOS
            // formatga qarab o'zi yoqib qo'yadi.
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = false
            }

            // Fokus "sakramasin": tekis (smooth) avtofokus video uchun aynan
            // shu maqsadda bor — usiz ultra-wide har harakatda qayta fokus
            // qilib, o'nlab kadrni xiralashtiradi.
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.isSubjectAreaChangeMonitoringEnabled = false

            device.unlockForConfiguration()
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            sizeLabelText = "\(min(dims.width, dims.height))p\(videoFps)"
        } catch {
            session.sessionPreset = .high
            sizeLabelText = "HD"
        }
    }

    /// Format shu kadr tezligini beradimi.
    static func supports(_ format: AVCaptureDevice.Format, fps: Double) -> Bool {
        format.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= fps && $0.maxFrameRate >= fps
        }
    }

    /// Qurilma hozir qanchalik qizigan. 4K60 ultra-wide — kameraning eng og'ir
    /// rejimi; issiq telefonda ISP kadrlarni tashlab yuboradi. O'lchangan:
    /// 215 soniyalik yozuvda 60 fps so'ralgan, faylga 46.4 fps tushgan
    /// (9974 kadr / 215 s), 4 soniyalik yozuvda esa aniq 60.0 fps. Ya'ni
    /// muammo davomli yuk, bir martalik xato emas.
    ///
    /// Linza (0.5x) va fps (60) — qat'iy talab, shuning uchun bosim tushirish
    /// uchun yagona o'zgaruvchi rezolutsiya.
    static func resolutionCeiling() -> Int32 {
        switch ProcessInfo.processInfo.thermalState {
        case .critical: return 1080
        case .serious: return 1440
        default: return 2160
        }
    }

    /// AVFoundation xato kodi → foydalanuvchiga aytiladigan sabab.
    /// `nil` — kod tanish emas (chaqiruvchi boshqa manbaga o'tadi).
    static func reasonText(for error: NSError?) -> String? {
        guard let error = error, error.domain == AVFoundationErrorDomain else {
            return nil
        }
        switch error.code {
        case AVError.diskFull.rawValue:
            return "telefon xotirasi to'lib qoldi"
        case AVError.maximumDurationReached.rawValue:
            return "maksimal davomiylikka yetildi"
        case AVError.maximumFileSizeReached.rawValue:
            return "maksimal fayl hajmiga yetildi"
        case AVError.sessionWasInterrupted.rawValue:
            return "kamera ishi uzildi"
        // `deviceIsNotAvailableInBackground` bu yerda tekshirilmaydi — iOS 9
        // dan beri u xato sifatida kelmaydi, uzilish sababi sifatida keladi
        // va `sessionInterrupted(_:)` da ushlanadi.
        case AVError.mediaServicesWereReset.rawValue:
            return "kamera xizmati qayta ishga tushdi"
        case AVError.deviceWasDisconnected.rawValue:
            return "kamera uzildi"
        default:
            return error.localizedDescription
        }
    }

    static func name(of mode: AVCaptureVideoStabilizationMode) -> String {
        switch mode {
        case .off: return "off"
        case .standard: return "standard"
        case .cinematic: return "cinematic"
        case .cinematicExtended: return "cinematicExtended"
        default: return "mode\(mode.rawValue)"
        }
    }

    static var thermalName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "?"
        }
    }

    /// Eng katta 16:9, binned bo'lmagan format — LEKIN avval 60 fps
    /// beradiganlari orasidan. 60 fps'li format umuman bo'lmasa (eski
    /// qurilma yoki 4K60 yo'q ultra-wide), 30 fps'ga tushamiz.
    ///
    /// Stabilizatsiyani qo'llashi uchun BONUS BERILMAYDI: `cinematicExtended`
    /// ni qo'llaydigan format og'irroq bo'lishi mumkin, ya'ni o'sha bonus
    /// bizni aynan kadr tashlaydigan formatga olib borardi.
    static func bestFormat(
        for device: AVCaptureDevice,
        maxHeight: Int32 = 2160
    ) -> AVCaptureDevice.Format? {
        for target in [60.0, 30.0] {
            var best: AVCaptureDevice.Format?
            var bestScore = 0.0
            for format in device.formats {
                if format.isVideoBinned { continue }
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                if dims.width > 3840 || dims.height > 2160 { continue }
                if min(dims.width, dims.height) > maxHeight { continue }
                let ratio = Double(dims.width) / Double(max(dims.height, 1))
                if abs(ratio - 16.0 / 9.0) > 0.12 { continue }
                guard supports(format, fps: target) else { continue }
                var score = Double(dims.width) * Double(dims.height)
                // Teng o'lchamda 8-bit afzal: 10-bit (x420) format ISP va
                // koderga ko'proq yuk beradi, quvur esa baribir SDR ga
                // tushiradi.
                if isTenBit(format) { score *= 0.9 }
                if score > bestScore {
                    bestScore = score
                    best = format
                }
            }
            if let best { return best }
        }
        return nil
    }

    static func isTenBit(_ format: AVCaptureDevice.Format) -> Bool {
        let sub = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        // 'x420' — 10-bit bi-planar video range (HDR formatlar).
        return sub == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            || sub == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
    }

    private func applyConnectionSettings() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        // EIS — ultra-wide'da OIS YO'Q (13 Pro Max'da optik stabilizatsiya
        // faqat wide va tele linzalarda), shuning uchun 0.5x qo'lda olinganda
        // stabilizatsiya kerak.
        //
        // LEKIN 60 fps'da faqat `.standard`: `cinematicExtended` 4K60 da
        // ISP/GPU ni to'ldiradi va kadr tashlanadi. Apple'ning o'z Kamera
        // ilovasi ham kinematik EIS ni yuqori kadr tezligida ishlatmaydi.
        guard Self.stabilization, let device = device else { return }
        let modes: [AVCaptureVideoStabilizationMode] = videoFps > 30
            ? [.standard]
            : [.cinematicExtended, .cinematic, .standard]
        for mode in modes
        where device.activeFormat.isVideoStabilizationModeSupported(mode) {
            connection.preferredVideoStabilizationMode = mode
            stabilizationName = Self.name(of: mode)
            break
        }
    }

    // MARK: - Bo'sh joy va tizim hodisalari

    /// Yozuv boradigan tomdagi bo'sh joy. `forImportantUsage` — iOS o'chirsa
    /// bo'ladigan keshlarni hisobga oladi, ya'ni haqiqatda yozish mumkin
    /// bo'lgan miqdor.
    static var freeBytes: Int64 {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static var freeSpaceLabel: String {
        let gb = Double(freeBytes) / 1_073_741_824
        return gb >= 1
            ? String(format: "%.1f GB", gb)
            : String(format: "%.0f MB", Double(freeBytes) / 1_048_576)
    }

    /// Bo'sh joy tugashiga qancha soniya yozuv qoldi.
    static var recordableSeconds: Int {
        let usable = freeBytes - freeSpaceFloor
        guard usable > 0 else { return 0 }
        return Int(usable / bytesPerSecondEstimate)
    }

    /// Sessiya uzilishi va tizim bosimi — yozuv o'zidan-o'zi to'xtashining
    /// asosiy tizim sabablari. Ilgari kuzatilmagan edi, shuning uchun sabab
    /// hech qayerda ko'rinmasdi.
    private func observeSystemEvents() {
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(sessionInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted, object: session)
        center.addObserver(
            self, selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded, object: session)
        center.addObserver(
            self, selector: #selector(sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError, object: session)
    }

    @objc private func sessionInterrupted(_ note: Notification) {
        let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        let reason = AVCaptureSession.InterruptionReason(
            rawValue: raw ?? -1)
        let text: String
        switch reason {
        case .videoDeviceNotAvailableDueToSystemPressure:
            text = "telefon qizib ketdi"
        case .videoDeviceNotAvailableInBackground:
            text = "ilova fonga o'tdi"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            text = "kamerani boshqa ilova oldi"
        case .videoDeviceInUseByAnotherClient:
            text = "kamera band"
        case .audioDeviceInUseByAnotherClient:
            text = "mikrofon band"
        default:
            text = "tizim to'xtatdi (kod \(raw ?? -1))"
        }
        interruptionReason = text
        DebugLog.log("VIDEO", "session interrupted: \(text) "
            + "recording=\(isRecording) thermal=\(Self.thermalName) "
            + "free=\(Self.freeSpaceLabel)")
    }

    @objc private func sessionInterruptionEnded(_ note: Notification) {
        DebugLog.log("VIDEO", "session interruption ended")
    }

    @objc private func sessionRuntimeError(_ note: Notification) {
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        interruptionReason = error?.localizedDescription ?? "kamera xatosi"
        DebugLog.log("VIDEO", "session runtime error: "
            + "\(error?.code ?? 0) \(error?.localizedDescription ?? "?") "
            + "free=\(Self.freeSpaceLabel)")
    }

    private func attachPreview() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    // MARK: - UI

    private func buildUI() {
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.text = "  …  "
        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        badgeLabel.layer.cornerRadius = 13
        badgeLabel.clipsToBounds = true
        view.addSubview(badgeLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 20
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        view.addSubview(closeButton)

        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.text = "00:00"
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timerLabel.alpha = 0
        view.addSubview(timerLabel)

        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.layer.cornerRadius = 36
        recordButton.layer.borderWidth = 4
        recordButton.layer.borderColor = UIColor.white.cgColor
        recordButton.isEnabled = false
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        view.addSubview(recordButton)

        recordInner.translatesAutoresizingMaskIntoConstraints = false
        recordInner.backgroundColor = .systemRed
        recordInner.layer.cornerRadius = 28
        recordInner.isUserInteractionEnabled = false
        recordButton.addSubview(recordInner)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),

            badgeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            badgeLabel.heightAnchor.constraint(equalToConstant: 26),

            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -18),

            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            recordButton.widthAnchor.constraint(equalToConstant: 72),
            recordButton.heightAnchor.constraint(equalToConstant: 72),

            recordInner.centerXAnchor.constraint(equalTo: recordButton.centerXAnchor),
            recordInner.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            recordInner.widthAnchor.constraint(equalToConstant: 56),
            recordInner.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    // MARK: - Actions

    @objc private func handleClose() {
        if isRecording {
            // Yozuv ketayotgan bo'lsa avval to'xtatamiz; fayl baribir qaytadi.
            toggleRecording()
            return
        }
        onCancel?()
    }

    /// Recorder ichida ko'rsatiladigan ogohlantirish. Flutter'ga qaytib
    /// ko'rsatish mumkin emas — recorder modal, foydalanuvchi hozir shu
    /// yerda va javobni shu yerda berishi kerak.
    private func showBlockingNotice(
        title: String,
        message: String,
        continueTitle: String? = nil,
        onContinue: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(
            title: title, message: message, preferredStyle: .alert)
        if let continueTitle = continueTitle {
            alert.addAction(UIAlertAction(title: continueTitle, style: .default) { _ in
                onContinue?()
            })
            alert.addAction(UIAlertAction(title: "Bekor qilish", style: .cancel))
        } else {
            alert.addAction(UIAlertAction(title: "Yopish", style: .cancel))
        }
        present(alert, animated: true)
    }

    @objc private func toggleRecording() {
        if isRecording {
            stoppedByUser = true
            isRecording = false
            stopTicker()
            sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
            recordButton.isEnabled = false
            return
        }

        // Yozuvni boshlashdan OLDIN joy yetadimi. Ilgari tekshirilmasdi:
        // xotira tugaganda AVFoundation yozuvni o'zi to'xtatardi, biz esa
        // buni oddiy tugash deb qabul qilib videoni yuklab yuborardik.
        let seconds = Self.recordableSeconds
        if seconds < 30 {
            showBlockingNotice(
                title: "Xotirada joy yo'q",
                message: "Bo'sh joy: \(Self.freeSpaceLabel). Video yozish uchun "
                    + "kamida 1 GB kerak. Telefondan joy bo'shatib qayta urinib "
                    + "ko'ring.")
            return
        }
        if seconds < 180 {
            showBlockingNotice(
                title: "Xotira kam qoldi",
                message: "Bo'sh joy: \(Self.freeSpaceLabel) — bu ~"
                    + "\(seconds / 60) daqiqa \(seconds % 60) soniyalik videoga "
                    + "yetadi. Xona kattaroq bo'lsa yozuv yarim yo'lda "
                    + "to'xtaydi.",
                continueTitle: "Baribir yozish",
                onContinue: { [weak self] in self?.beginRecording() })
            return
        }
        beginRecording()
    }

    private func beginRecording() {
        let name = "kadastr_video_\(Int(Date().timeIntervalSince1970 * 1000)).mov"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        stoppedByUser = false
        interruptionReason = nil
        isRecording = true
        startedAt = Date()
        setRecordingUI(true)
        startTicker()
        thermalAtStart = Self.thermalName
        DebugLog.log("VIDEO", "start free=\(Self.freeSpaceLabel) "
            + "recordable=\(Self.recordableSeconds)s thermal=\(thermalAtStart)")
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            // Bu yerda ulanish sozlamalariga TEGILMAYDI. Ilgari shu joyda
            // `applyPortraitOrientation()` chaqirilardi va tirik sessiyaga
            // stabilizatsiya rejimini qayta berish yozuv boshida sakrash
            // hosil qilardi. Sozlamalar bir marta, sessiya qurilganda.
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func setRecordingUI(_ recording: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.recordInner.layer.cornerRadius = recording ? 6 : 28
            self.recordInner.transform = recording
                ? CGAffineTransform(scaleX: 0.55, y: 0.55)
                : .identity
            self.timerLabel.alpha = recording ? 1 : 0
        }
    }

    private func startTicker() {
        timerLabel.text = "00:00"
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, let started = self.startedAt else { return }
            let elapsed = Int(Date().timeIntervalSince(started))
            let clock = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
            // Telefon qizib ketsa foydalanuvchi buni BILISHI kerak: shu
            // holatda kadrlar tashlanadi va model sifati tushadi. Jimgina
            // yozib ketishdan ko'ra ogohlantirish to'g'ri.
            let hot = ProcessInfo.processInfo.thermalState == .serious
                || ProcessInfo.processInfo.thermalState == .critical
            // Xotira tugashi yaqin bo'lsa — hisoblab turamiz. Yozuv birdan
            // uzilib qolgandan ko'ra, oldindan ko'rinishi kerak.
            let left = Self.recordableSeconds
            if left <= 60 {
                self.timerLabel.textColor = .systemRed
                self.timerLabel.text = "\(clock)  ·  xotira: \(left) s qoldi"
            } else if hot {
                self.timerLabel.textColor = .systemOrange
                self.timerLabel.text = "\(clock)  ·  telefon qizidi"
            } else {
                self.timerLabel.textColor = .white
                self.timerLabel.text = clock
            }
        }
    }

    private func stopTicker() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Xatolik bo'lsa ham, "successfully finished" flag'i bilan kelgan fayl
        // to'liq — uni saqlab qolamiz.
        let nsError = error as NSError?
        let salvaged = nsError?
            .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
        if let error = error, !salvaged {
            try? FileManager.default.removeItem(at: outputFileURL)
            DebugLog.log("VIDEO", "record FAILED "
                + "\(nsError?.code ?? 0) \(error.localizedDescription) "
                + "free=\(Self.freeSpaceLabel)")
            DispatchQueue.main.async { [weak self] in
                self?.onFailed?(error.localizedDescription)
            }
            return
        }

        // ENG MUHIMI: yozuv o'zidan-o'zi tugagan bo'lsa buni yashirmaymiz.
        // Ilgari `salvaged` fayl oddiy tugash sifatida qaytarilardi va ilova
        // videoni darhol yuklab yuborardi — foydalanuvchi esa yozuvni hali
        // tugatmagan bo'lardi. Endi sabab birga qaytadi.
        var endReason: String?
        if !stoppedByUser {
            endReason = Self.reasonText(for: nsError)
                ?? interruptionReason
                ?? "yozuv tizim tomonidan to'xtatildi"
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        // Taxminiy bitrate (konteyner qo'shimchasi bilan) — Android tomonda
        // haqiqiy METADATA_KEY_BITRATE o'qiladi; solishtirish uchun yetarli.
        let bitrate = elapsed > 0.1 ? Int(Double(size) * 8 / elapsed) : 0

        // HAQIQIY kadr tezligi — faylning o'zidan. So'ralgan 60 fps bilan
        // faylga tushgan fps orasidagi farq kadr tashlanganini ko'rsatadi.
        // Buni o'lchamasak "60 fps" degan yorliq yolg'on gapiradi: bir
        // o'lchovda 60 so'ralib 46.4 fps yozilgan edi.
        let track = AVURLAsset(url: outputFileURL)
            .tracks(withMediaType: .video).first
        let realFps = Double(track?.nominalFrameRate ?? 0)
        let dropPercent = videoFps > 0 && realFps > 1
            ? Int(((Double(videoFps) - realFps) / Double(videoFps) * 100).rounded())
            : 0

        let payload: [String: Any] = [
            "path": outputFileURL.path,
            "sizeBytes": size,
            "durationMs": Int(elapsed * 1000),
            "bitrate": bitrate,
            "width": videoWidth,
            "height": videoHeight,
            "zoom": zoomLabelText,
            "quality": sizeLabelText,
            "fps": videoFps,
            "realFps": (realFps * 10).rounded() / 10,
            "droppedPercent": dropPercent,
            "lens": device?.localizedName ?? "",
            "endedEarly": endReason != nil,
            "endReason": endReason ?? "",
            "freeSpaceBytes": Self.freeBytes,
        ]
        DebugLog.log("VIDEO", "captured \(outputFileURL.lastPathComponent) "
            + "\(size) bytes \(zoomLabelText) \(sizeLabelText) "
            + "realFps=\(String(format: "%.1f", realFps)) drop=\(dropPercent)% "
            + "eis=\(stabilizationName) thermal=\(thermalAtStart)→\(Self.thermalName) "
            + "free=\(Self.freeSpaceLabel) "
            + "byUser=\(stoppedByUser) end=\(endReason ?? "-") "
            + "avErr=\(nsError?.code ?? 0)")
        DispatchQueue.main.async { [weak self] in
            self?.onFinished?(payload)
        }
    }
}
