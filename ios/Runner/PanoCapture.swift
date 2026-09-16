//
//  PanoCapture.swift — 360° panorama uchun ARKit bilan yo'naltirilgan suratga olish.
//
//  MANBA: `StudioProjects/360/ios/Uy360/` (CaptureController + CaptureView).
//  Mana shu farqlar bilan ko'chirilgan:
//
//   1. Matnlar Dart'dan keladi (`strings`) — ilova uch tilli, Swift'da i18n
//      takrorlanmasin.
//   2. Kadrlar TO'LIQ o'lchamda (4032×3024, JPEG q0.88) yoziladi — tikish
//      TELEFONNING O'ZIDA (`PanoStitch.swift` → `PanoCore/`), yuklash yo'q.
//      ⚠️ Ilgari 1280px ga kichraytirilardi (server tikishi uchun yuklash
//      hajmi). Endi bu MUMKIN EMAS: yadro (`uy360_types.hpp::imreadForWidth`)
//      DCT-reduce dekod darajasini `imageWidth` (ASL o'lcham) bo'yicha
//      tanlaydi — kichik JPEG bilan BA/MVS kadrlari 4× kichik dekodlanib,
//      keyin kattalashtirilardi va chuqurlik xira chiqardi. Kadrlar
//      `Application Support/pano/` da, yuklangach Dart o'chiradi.
//   3. LiDAR chuqurligi OLINMAYDI; yadro tasvirlardan chuqurlik hisoblaydi.
//   4. ARKit compatibility grid: 28 required targets + one optional zenith.
//      Supported devices prefer PanoUltraWideCapture's 17-target path.
//
//  Natija: `Application Support/pano/<uuid>/` ichida `frame_N.jpg` +
//  `meta.json` (DOIMIY — qoralamada `LocalPano` sifatida saqlanadi). Dart shu
//  katalogni `stitch` ga beradi (tikish shu qurilmada), tayyor `pano.jpg` ni
//  serverga yuklaydi va katalogni O'ZI o'chiradi.
//

import ARKit
import CoreImage
import SceneKit
import SwiftUI
import UIKit

// MARK: - Kontroller

/// ARKit sessiyasini boshqaradi: nishonlarni ekranga proyeksiya qiladi,
/// telefon nishonda "ushlab turilganda" avtomatik surat oladi, har olingan
/// kadrni dunyoga bog'langan sferaga chizadi (foydalanuvchi nima qoplanganini
/// ko'radi), joy qulfini yuritadi va kadrni pozasi bilan diskka yozadi.
///
/// MANBA: Uy360 `CaptureController` (`360/ios/Uy360/CaptureController.swift`)
/// — farqlar: matnlar `strings` dan, LiDAR yo'q, roll talabi yo'q,
/// joy chegarasi sozlamasiz 6 sm.
final class PanoCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    struct Dot: Identifiable {
        let id: Int
        var point: CGPoint
        var visible: Bool
        var captured: Bool
        var optional: Bool
        /// Ixtiyoriy nishon tepada (zenit) — strelka yo'nalishi uchun.
        var up: Bool
        var angle: Float
        var isNext: Bool
    }

    @Published var dots: [Dot] = []
    @Published var capturedCount = 0
    @Published var nearestAngle: Float = 999
    @Published var dwellProgress: Double = 0
    @Published var message = ""
    @Published var moved = false
    @Published var isCapturing = false
    @Published var trackingOK = false
    @Published var lastThumb: UIImage?
    /// Keyingi nishon tomon strelka (ekran burchagi, radian); yaqin bo'lsa nil.
    @Published var chevronAngle: Double?
    @Published var canUndo = false

    // Joy qulfi: birinchi kadr olingan joydan masofa. Telefon `blockCm` dan
    // uzoqlashsa surat olinmaydi — parallaks tikishni buzadi.
    @Published var offsetCm: Float = 0
    @Published var offsetRightCm: Float = 0     // + = telefon ankerdan o'ngda
    @Published var offsetForwardCm: Float = 0   // + = telefon ankerdan oldinda
    @Published var offsetUpCm: Float = 0
    @Published var positionOK = true
    /// "O'ngga 7 sm" — qaytish yo'li.
    @Published var moveHint: String?
    /// Uy360'da sozlama (3/6/10 sm); bu yerda tavsiya qilingan 6 sm.
    let blockCm: Float = 6

    let targets: [PanoTarget]
    let requiredTotal: Int
    let session = ARSession()
    let dir: URL
    var viewSize: CGSize = .zero

    // Jonli sfera preview (AR view sahnasidagi SceneKit tugunlari).
    private var previewRoot: SCNNode?
    private var maskNode: SCNNode?
    static let previewRadius: Float = 10
    static let maskDistance: Float = 40
    /// Jonli kamera oynasi — ekranning shuncha qismi (kenglik × balandlik).
    static let viewfinderFraction = CGSize(width: 0.86, height: 0.72)

    private let strings: [String: String]
    private let arQueue = DispatchQueue(label: "kadastr.pano.ar", qos: .userInteractive)
    private let ioQueue = DispatchQueue(label: "kadastr.pano.io", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    // Faqat arQueue'da tegiladi.
    private var captured: Set<Int> = []
    private var capturing = false
    private var lastForward: SIMD3<Float>?
    private var lastTime: TimeInterval = 0
    private var dwellStart: TimeInterval?
    private var dwellTarget: Int?
    private var anchorPosition: SIMD3<Float>?
    private var exposureLocked = false
    private var frameIndex = 0
    private struct Shot { let targetId: Int; let index: Int; let file: String; weak var node: SCNNode? }
    private var shots: [Shot] = []

    // Faqat ioQueue'da tegiladi.
    private var metas: [PanoFrameMeta] = []

    /// Nishonda shuncha turilsa surat olinadi.
    private let dwellSeconds: TimeInterval = 0.35
    /// Nishonga shuncha yaqin bo'lishi kerak.
    private let angleThreshold: Float = 4.0 * .pi / 180
    /// Shundan tez burilayotganda olinmaydi — surat xira chiqardi.
    private let maxAngularSpeed: Float = 12 * .pi / 180

    init(dir: URL, strings: [String: String]) {
        self.dir = dir
        self.strings = strings
        self.targets = PanoTargetGrid.build()
        self.requiredTotal = targets.filter { !$0.optional }.count
        super.init()
        session.delegate = self
        session.delegateQueue = arQueue
    }

    private func s(_ key: String, _ fallback: String) -> String {
        strings[key] ?? fallback
    }

    // MARK: sessiya

    func run() {
        let cfg = ARWorldTrackingConfiguration()
        // Dunyo +Y = tortishishga qarama-qarshi. Yadro gorizontni shunga
        // qarab tekislaydi — busiz panorama qiyshiq chiqardi.
        cfg.worldAlignment = .gravity
        cfg.isAutoFocusEnabled = true
        if #available(iOS 16.0, *),
           let fmt = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            cfg.videoFormat = fmt
        }
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() { session.pause() }

    /// Zenit va nadirni "olingan" deb belgilaydi — ularsiz yakunlash uchun.
    func skipOptional() {
        arQueue.async {
            for t in self.targets where t.optional { self.captured.insert(t.id) }
        }
    }

    /// `meta.json` ni yozadi va olingan kadrlar sonini qaytaradi.
    @discardableResult
    func finish() -> Int {
        let list = ioQueue.sync { metas }
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        }
        return list.count
    }

    // MARK: jonli preview sahnasi

    /// AR view sahnasi tayyor bo'lganda chaqiriladi: qora qobiq (o'rtasida
    /// jonli kamera oynasi) va olingan kadrlar tekisliklari uchun ildiz.
    func attachPreview(to scene: SCNScene) {
        let root = SCNNode()
        root.name = "previewRoot"
        scene.rootNode.addChildNode(root)
        previewRoot = root

        // Tashqi kvadrat ±3 (ko'rish maydonini zaxira bilan qoplaydi), ichida
        // ±fraction teshik ("ekran yarim-kengligi" birligida); tugun har kadrda
        // D·tan(fov/2) ga masshtablanadi — teshik ekranning doimiy ulushi.
        let path = UIBezierPath(rect: CGRect(x: -3, y: -3, width: 6, height: 6))
        let f = Self.viewfinderFraction
        path.append(UIBezierPath(rect: CGRect(x: -f.width, y: -f.height, width: 2 * f.width, height: 2 * f.height)))
        path.usesEvenOddFillRule = true
        let shape = SCNShape(path: path, extrusionDepth: 0)
        let black = SCNMaterial()
        black.diffuse.contents = UIColor.black
        black.lightingModel = .constant
        black.isDoubleSided = true
        shape.materials = [black]
        let mask = SCNNode(geometry: shape)
        mask.name = "viewfinderMask"
        mask.renderingOrder = -10
        scene.rootNode.addChildNode(mask)
        maskNode = mask
    }

    private func updateMask(camera: ARCamera) {
        guard let mask = maskNode, viewSize.width > 0 else { return }
        let proj = camera.projectionMatrix(for: .portrait, viewportSize: viewSize, zNear: 0.1, zFar: 100)
        let tanHalfH = 1 / proj.columns.0.x
        let tanHalfV = 1 / proj.columns.1.y
        let d = Self.maskDistance
        var local = matrix_identity_float4x4
        local.columns.3 = SIMD4(0, 0, -d, 1)
        let transform = camera.transform * local
        DispatchQueue.main.async {
            mask.simdTransform = transform
            mask.simdScale = SIMD3(d * tanHalfH, d * tanHalfV, 1)
        }
    }

    private func addPreviewPlane(image: UIImage, transform: simd_float4x4, fx: Float, fy: Float, w: Int, h: Int) -> SCNNode {
        let d = Self.previewRadius
        let plane = SCNPlane(width: CGFloat(2 * d * Float(w) / (2 * fx)), height: CGFloat(2 * d * Float(h) / (2 * fy)))
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .constant
        m.isDoubleSided = true
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        var local = matrix_identity_float4x4
        local.columns.3 = SIMD4(0, 0, -d, 1)
        node.simdTransform = transform * local
        return node
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let cam = frame.camera
        let T = cam.transform
        let forward = -SIMD3(T.columns.2.x, T.columns.2.y, T.columns.2.z)
        let pos = SIMD3(T.columns.3.x, T.columns.3.y, T.columns.3.z)
        let now = frame.timestamp

        var angSpeed: Float = 0
        if let lf = lastForward, now > lastTime {
            let d = max(-1, min(1, simd_dot(lf, forward)))
            angSpeed = acos(d) / Float(now - lastTime)
        }
        lastForward = forward
        lastTime = now

        var ok = false
        if case .normal = cam.trackingState { ok = true }
        updateMask(camera: cam)

        let size = viewSize
        var newDots: [Dot] = []
        newDots.reserveCapacity(targets.count)
        var nearest: (id: Int, angle: Float)?
        for t in targets {
            let dir = t.direction
            let cosA = simd_dot(dir, forward)
            let ang = acos(max(-1, min(1, cosA)))
            let inFront = cosA > 0.05
            var pt = CGPoint(x: -1000, y: -1000)
            if inFront, size.width > 0 {
                // Nishon "3 metr naridagi" nuqta sifatida proyeksiya qilinadi —
                // masofa ahamiyatsiz, faqat yo'nalish muhim.
                pt = cam.projectPoint(pos + dir * 3, orientation: .portrait, viewportSize: size)
            }
            let isCap = captured.contains(t.id)
            newDots.append(Dot(id: t.id, point: pt, visible: inFront, captured: isCap, optional: t.optional,
                               up: t.pitch > 0, angle: ang, isNext: false))
            if !isCap, nearest == nil || ang < nearest!.angle { nearest = (t.id, ang) }
        }
        if let n = nearest, let i = newDots.firstIndex(where: { $0.id == n.id }) { newDots[i].isNext = true }

        // Keyingi nishon tomon strelka (ekran burchagi), yaqin bo'lsa yashirin.
        var chevron: Double?
        if let n = nearest, n.angle > 8 * .pi / 180 {
            let t = targets[n.id]
            let yaw = atan2(forward.x, -forward.z)
            let pitch = asin(max(-1, min(1, forward.y)))
            var dyaw = t.yaw - yaw
            while dyaw > .pi { dyaw -= 2 * .pi }
            while dyaw < -.pi { dyaw += 2 * .pi }
            let dpitch = t.pitch - pitch
            chevron = Double(atan2(-dpitch, dyaw))
        }

        // Joy qulfi — birinchi kadr joyiga nisbatan.
        var posOK = true
        var offCm: Float = 0, offR: Float = 0, offF: Float = 0, offU: Float = 0
        var hint: String?
        if let a = anchorPosition {
            let delta = a - pos                      // qaytish uchun yurish kerak bo'lgan vektor
            offCm = simd_length(delta) * 100
            var fwdH = SIMD3(forward.x, 0, forward.z)
            if simd_length(fwdH) < 1e-3 { fwdH = SIMD3(0, 0, -1) }
            fwdH = simd_normalize(fwdH)
            let rightH = simd_normalize(simd_cross(fwdH, SIMD3(0, 1, 0)))
            offR = simd_dot(delta, rightH) * 100
            offF = simd_dot(delta, fwdH) * 100
            offU = delta.y * 100
            posOK = offCm <= blockCm
            if !posOK {
                let comps: [(Float, String, String)] = [
                    (offR, s("dir_right", "O'ngga"), s("dir_left", "Chapga")),
                    (offF, s("dir_forward", "Oldinga"), s("dir_back", "Orqaga")),
                    (offU, s("dir_up", "Yuqoriga"), s("dir_down", "Pastga")),
                ]
                if let big = comps.max(by: { abs($0.0) < abs($1.0) }) {
                    hint = "\(big.0 >= 0 ? big.1 : big.2) \(Int(abs(big.0).rounded())) sm"
                }
            }
        }

        var dwell: Double = 0
        if ok, !capturing, posOK, let n = nearest, n.angle < angleThreshold, angSpeed < maxAngularSpeed {
            if dwellTarget != n.id { dwellTarget = n.id; dwellStart = now }
            let elapsed = now - (dwellStart ?? now)
            dwell = min(1, elapsed / dwellSeconds)
            if elapsed >= dwellSeconds { trigger(targetId: n.id, frame: frame) }
        } else {
            dwellTarget = nil
            dwellStart = nil
        }

        let movedNow = !posOK
        let msg: String
        if !ok {
            msg = s("tracking", "Telefonni sekin harakatlantiring…")
        } else if movedNow, let h = hint {
            msg = s("return_to", "Boshlang'ich joyga qayting:") + " " + h
        } else {
            msg = ""
        }

        let nearestAng = nearest?.angle ?? 999
        DispatchQueue.main.async {
            self.dots = newDots
            self.nearestAngle = nearestAng
            self.trackingOK = ok
            self.dwellProgress = dwell
            self.moved = movedNow
            self.chevronAngle = chevron
            self.offsetCm = offCm
            self.offsetRightCm = offR
            self.offsetForwardCm = offF
            self.offsetUpCm = offU
            self.positionOK = posOK
            self.moveHint = hint
            if self.message != msg { self.message = msg }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.message = self.s("ar_error", "AR xatosi") + ": " + error.localizedDescription
        }
    }

    // MARK: surat olish

    private func trigger(targetId: Int, frame: ARFrame) {
        guard !capturing, !captured.contains(targetId) else { return }
        capturing = true
        captured.insert(targetId)
        dwellTarget = nil
        dwellStart = nil
        if anchorPosition == nil {
            let T = frame.camera.transform
            anchorPosition = SIMD3(T.columns.3.x, T.columns.3.y, T.columns.3.z)
        }
        let target = targets[targetId]
        let index = frameIndex
        frameIndex += 1
        DispatchQueue.main.async { self.isCapturing = true }

        if #available(iOS 16.0, *) {
            // Yuqori aniqlikdagi alohida kadr (AR oqimining past aniqlikdagi
            // kadri emas) — u ~100 ms keyin keladi, telefon hali nishonda.
            session.captureHighResolutionFrame { [weak self] hi, _ in
                guard let self else { return }
                self.save(frame: hi ?? frame, target: target, index: index, highRes: hi != nil)
            }
        } else {
            save(frame: frame, target: target, index: index, highRes: false)
        }
    }

    private func save(frame: ARFrame, target: PanoTarget, index: Int, highRes: Bool) {
        let pb = frame.capturedImage
        let cam = frame.camera
        let pw = CVPixelBufferGetWidth(pb)
        let ph = CVPixelBufferGetHeight(pb)
        let K = cam.intrinsics
        let res = cam.imageResolution
        let T = cam.transform
        let tf: [Float] = [
            T.columns.0.x, T.columns.0.y, T.columns.0.z, T.columns.0.w,
            T.columns.1.x, T.columns.1.y, T.columns.1.z, T.columns.1.w,
            T.columns.2.x, T.columns.2.y, T.columns.2.z, T.columns.2.w,
            T.columns.3.x, T.columns.3.y, T.columns.3.z, T.columns.3.w,
        ]
        let name = "frame_\(index).jpg"
        // CIImage bufer'ni ushlab turadi — ARFrame'ni tezroq qo'yib yuboramiz.
        let ci = CIImage(cvPixelBuffer: pb)
        // Preview tekisligi uchun intrinsics haqiqiy piksel buferga masshtablanadi
        // (yuqori aniqlikdagi kadr o'zinikini beradi).
        let fx = K[0][0] * Float(pw) / Float(res.width)
        let fy = K[1][1] * Float(ph) / Float(res.height)

        ioQueue.async { [self] in
            // TO'LIQ o'lcham — fayl sarlavhasidagi 2-izohga qarang.
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let opts: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(
                    rawValue: kCGImageDestinationLossyCompressionQuality as String
                ): 0.88,
            ]
            if let data = ciContext.jpegRepresentation(of: ci, colorSpace: cs, options: opts) {
                try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
            }

            metas.append(PanoFrameMeta(
                index: index,
                targetId: target.id,
                targetYaw: target.yaw,
                targetPitch: target.pitch,
                transform: tf,
                intrinsics: [K[0][0], K[1][1], K[2][0], K[2][1]],
                // ASL o'lcham — intrinsics shunga tegishli.
                imageWidth: Int(res.width),
                imageHeight: Int(res.height),
                pixelWidth: pw,
                pixelHeight: ph,
                timestamp: frame.timestamp,
                highRes: highRes,
                file: name
            ))

            // Jonli sfera uchun tekstura (~1000 px) va kichik eskiz.
            let small = ci.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
            let previewImage = ciContext.createCGImage(small, from: small.extent).map { UIImage(cgImage: $0) }
            let thumb = previewImage.map { UIImage(cgImage: $0.cgImage!, scale: 2.5, orientation: .right) }
            DispatchQueue.main.async {
                var node: SCNNode?
                if let img = previewImage, let root = self.previewRoot {
                    let n = self.addPreviewPlane(image: img, transform: T, fx: fx, fy: fy, w: pw, h: ph)
                    root.addChildNode(n)
                    node = n
                }
                self.capturedCount += 1
                self.isCapturing = false
                self.lastThumb = thumb
                self.canUndo = true
                self.haptic.impactOccurred()
                self.arQueue.async {
                    self.shots.append(Shot(targetId: target.id, index: index, file: name, node: node))
                    self.capturing = false
                    self.lockExposureIfNeeded()
                }
            }
        }
    }

    /// Oxirgi kadrni (fayl, meta, preview tekisligi) olib tashlaydi va uning
    /// nishonini qayta ochadi.
    func undoLast() {
        arQueue.async { [self] in
            guard !capturing, let shot = shots.popLast() else { return }
            captured.remove(shot.targetId)
            let dir = self.dir
            ioQueue.async { [self] in
                metas.removeAll { $0.index == shot.index }
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(shot.file))
            }
            let hasMore = !shots.isEmpty
            if !hasMore { anchorPosition = nil }  // birinchi kadr bekor qilindi → anker keyingisi bilan
            DispatchQueue.main.async {
                shot.node?.removeFromParentNode()
                self.capturedCount = max(0, self.capturedCount - 1)
                self.canUndo = hasMore
                self.haptic.impactOccurred()
            }
        }
    }

    /// Birinchi kadrdan keyin ekspozitsiya va oq balansni QULFLAYMIZ —
    /// aks holda kadrlar orasida yorqinlik sakraydi va chok ko'rinib qoladi.
    private func lockExposureIfNeeded() {
        guard !exposureLocked else { return }
        exposureLocked = true
        if #available(iOS 16.0, *),
           let dev = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera {
            do {
                try dev.lockForConfiguration()
                if dev.isExposureModeSupported(.locked) { dev.exposureMode = .locked }
                if dev.isWhiteBalanceModeSupported(.locked) { dev.whiteBalanceMode = .locked }
                dev.unlockForConfiguration()
            } catch {
                // Qulflanmasa ham tushirish davom etadi — faqat sifat pastroq.
            }
        }
    }
}

// MARK: - Ekran

private struct PanoARViewContainer: UIViewRepresentable {
    let controller: PanoCaptureController

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.session = controller.session
        v.scene = SCNScene()
        v.automaticallyUpdatesLighting = false
        v.rendersCameraGrain = false
        v.antialiasingMode = .none
        controller.attachPreview(to: v.scene)
        return v
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

/// MANBA: Uy360 `CaptureView`. Oq to'rtburchak = jonli kamera oynasi; undan
/// tashqarida — hozirgacha olingan kadrlar bilan bo'yalgan sfera.
struct PanoCaptureView: View {
    @StateObject var ctrl: PanoCaptureController
    let strings: [String: String]
    let onFinish: (Int) -> Void
    let onCancel: () -> Void

    @State private var confirmFinish = false

    init(
        dir: URL,
        strings: [String: String],
        onFinish: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _ctrl = StateObject(wrappedValue: PanoCaptureController(dir: dir, strings: strings))
        self.strings = strings
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    private func s(_ key: String, _ fallback: String) -> String {
        strings[key] ?? fallback
    }

    private var total: Int { ctrl.targets.count }
    private var complete: Bool { ctrl.capturedCount >= ctrl.requiredTotal }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PanoARViewContainer(controller: ctrl)
                    .onAppear {
                        ctrl.viewSize = geo.size
                        ctrl.run()
                    }
                    .onChange(of: geo.size) { newSize in ctrl.viewSize = newSize }
                    .onDisappear { ctrl.pause() }

                viewfinderFrame(size: geo.size)
                dotsLayer
                reticle(center: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                hud(size: geo.size)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .confirmationDialog(
            s("finish_title", "Tushirishni yakunlash?"),
            isPresented: $confirmFinish,
            titleVisibility: .visible
        ) {
            Button(s("finish_yes", "Yakunlash va tikish")) { onFinish(ctrl.finish()) }
            Button(s("finish_no", "Davom etish"), role: .cancel) {}
        } message: {
            Text(
                s("finish_body", "%d / %t kadr olindi. Kam kadr — sferada boʻshliq boʻladi.")
                    .replacingOccurrences(of: "%d", with: "\(ctrl.capturedCount)")
                    .replacingOccurrences(of: "%t", with: "\(total)")
            )
        }
    }

    // MARK: qatlamlar

    /// Oq to'rtburchak = jonli kamera oynasi; tashqarisi — olingan kadrlar
    /// bilan bo'yalgan sfera.
    private func viewfinderFrame(size: CGSize) -> some View {
        let f = PanoCaptureController.viewfinderFraction
        return RoundedRectangle(cornerRadius: 2)
            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            .frame(width: size.width * f.width, height: size.height * f.height)
            .position(x: size.width / 2, y: size.height / 2)
            .allowsHitTesting(false)
    }

    private var dotsLayer: some View {
        ForEach(ctrl.dots) { d in
            if d.visible {
                ZStack {
                    if d.captured {
                        Circle().fill(Color.orange.opacity(0.35)).frame(width: 30, height: 30)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    } else {
                        let color: Color = ctrl.positionOK ? .green : .red
                        Circle().fill(color.opacity(0.28)).frame(width: d.isNext ? 72 : 54, height: d.isNext ? 72 : 54)
                        Circle().fill(color.opacity(0.95)).frame(width: 40, height: 40)
                        if d.optional {
                            Image(systemName: d.up ? "arrow.up" : "arrow.down")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 4)
                .position(d.point)
                .animation(.linear(duration: 0.05), value: d.point)
                .allowsHitTesting(false)
            }
        }
    }

    private func reticle(center: CGPoint) -> some View {
        let near = ctrl.nearestAngle < 4 * .pi / 180
        return ZStack {
            Circle()
                .stroke(near ? Color.green : Color.white.opacity(0.9), lineWidth: 4)
                .frame(width: 96, height: 96)
            Circle()
                .trim(from: 0, to: ctrl.dwellProgress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 96, height: 96)
            if let a = ctrl.chevronAngle {
                Image(systemName: "chevron.right")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .offset(x: 78)
                    .rotationEffect(.radians(a))
            }
        }
        .position(center)
        .allowsHitTesting(false)
    }

    /// Yuqoridan qarab "pufakcha": halqa — birinchi kadr joyi atrofidagi
    /// ruxsat etilgan radius, nuqta — telefon hozir qayerda (o'ng/oldin).
    /// Ichida yashil, tashqarida qizil.
    private var positionIndicator: some View {
        let limit = CGFloat(ctrl.blockCm)
        let r: CGFloat = 26
        let scale = r / limit
        // Offset vektori ankerga qaytishni ko'rsatadi → teskari.
        let dx = min(max(CGFloat(ctrl.offsetRightCm) * -scale, -r * 1.6), r * 1.6)
        let dy = min(max(CGFloat(ctrl.offsetForwardCm) * scale, -r * 1.6), r * 1.6)
        let ok = ctrl.positionOK
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(ok ? Color.green : Color.red, lineWidth: 2).frame(width: r * 2, height: r * 2)
                Circle().fill(Color.white.opacity(0.25)).frame(width: 4, height: 4)
                Circle().fill(ok ? Color.green : Color.red).frame(width: 12, height: 12).offset(x: dx, y: dy)
            }
            .frame(width: r * 3.4, height: r * 3.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ok ? s("in_place", "Joyda") : s("off_place", "Joydan chiqdi")).font(.caption.weight(.bold))
                Text(String(format: "%.0f sm / %.0f sm", ctrl.offsetCm, ctrl.blockCm)).font(.caption2).monospacedDigit()
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func hud(size: CGSize) -> some View {
        VStack(spacing: 0) {
            // Yuqori qator: undo · hisob · yopish
            HStack(alignment: .top) {
                Button { ctrl.undoLast() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title2.weight(.semibold))
                        .padding(12)
                        .background(.white.opacity(ctrl.canUndo ? 0.9 : 0.35), in: Circle())
                        .foregroundStyle(.black)
                }
                .disabled(!ctrl.canUndo)
                Spacer()
                Text("\(ctrl.capturedCount) / \(total)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .padding(12)
                        .background(.red, in: Circle())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18).padding(.top, 56)

            if ctrl.capturedCount > 0 {
                positionIndicator
                    .padding(.top, 10)
            }
            if !ctrl.message.isEmpty {
                Text(ctrl.message)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(ctrl.moved ? Color.red.opacity(0.85) : Color.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 8)
            } else if ctrl.capturedCount == 0 {
                Text(s("hint", "Xona markazida turing · telefonni koʻkrak balandligida tuting · nuqtaga toʻgʻrilab bir lahza ushlang"))
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 28).padding(.top, 10)
            }

            Spacer()

            // Pastki qism: oxirgi eskiz · tugmalar · progress
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    if let t = ctrl.lastThumb {
                        Image(uiImage: t)
                            .resizable().scaledToFill()
                            .frame(width: 48, height: 64).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.7)))
                    }
                    Spacer()
                    if complete {
                        Button {
                            confirmFinish = true
                        } label: {
                            Label(s("finish", "Yakunlash"), systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .padding(.horizontal, 26).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        HStack(spacing: 10) {
                            Button(s("skip_poles", "Zenitni oʻtkazish")) { ctrl.skipOptional() }
                                .font(.footnote)
                                .buttonStyle(.bordered)
                                .tint(.white)
                            // 4 kadrdan kam bo'lsa tikishning ma'nosi yo'q.
                            if ctrl.capturedCount >= 4 {
                                Button(s("early_finish", "Erta yakunlash")) { confirmFinish = true }
                                    .font(.footnote)
                                    .buttonStyle(.bordered)
                                    .tint(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                HStack(spacing: 10) {
                    ProgressView(value: Double(ctrl.capturedCount), total: Double(total))
                        .tint(.green)
                        .scaleEffect(x: 1, y: 2.2, anchor: .center)
                    Text("\(ctrl.capturedCount) / \(total)")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 22)
            }
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Koordinator (Flutter kanali)

/// Nativ ekranni ochadi va natijani Flutter'ga qaytaradi.
///
/// `RoomPlanScannerCoordinator` bilan bir xil naqsh: singleton, `start(from:)`,
/// natija bir marta qaytariladi.
@available(iOS 15.0, *)
final class PanoCaptureCoordinator: NSObject {
    static let shared = PanoCaptureCoordinator()

    private var host: UIViewController?
    private var pending: FlutterResult?

    var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    static func canCapture(trackingSupported: Bool, authorization: AVAuthorizationStatus) -> Bool {
        trackingSupported && authorization != .denied && authorization != .restricted
    }

    var isAvailable: Bool {
        Self.canCapture(trackingSupported: isSupported, authorization: AVCaptureDevice.authorizationStatus(for: .video))
    }

    /// Tushirishlar ildizi (zaxiradan chiqarilgan).
    static var panoRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var root = base.appendingPathComponent("pano", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? root.setResourceValues(rv)
        }
        return root
    }

    func start(from presenter: UIViewController, strings: [String: String], result: @escaping FlutterResult) {
        guard pending == nil else {
            result(FlutterError(code: "BUSY", message: "Suratga olish allaqachon ochiq", details: nil))
            return
        }
        guard isSupported else {
            result(FlutterError(code: "UNSUPPORTED", message: "Qurilma ARKit'ni qoʻllamaydi", details: nil))
            return
        }
        guard isAvailable else {
            result(FlutterError(code: "CAMERA_PERMISSION", message: "Kameraga ruxsat berilmadi", details: nil))
            return
        }
        // `Application Support/pano/<uuid>` — DOIMIY. Ilgari `tmp/` edi; endi
        // tushirish qoralamada saqlanadi (`LocalPano`) va tikish/yuklash keyin
        // ham davom ettiriladi — `tmp/` ni iOS ilova yopiq paytda tozalab
        // yuborishi mumkin edi. iCloud zaxirasidan chiqariladi (75 MB kadr).
        // Dart yuklagach katalogni o'zi o'chiradi.
        let dir = Self.panoRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            result(FlutterError(code: "IO", message: "Katalog yaratilmadi: \(error.localizedDescription)", details: nil))
            return
        }

        pending = result
        let view = PanoCaptureView(
            dir: dir,
            strings: strings,
            onFinish: { [weak self] count in
                self?.finish(with: ["dir": dir.path, "frames": count])
            },
            onCancel: { [weak self] in
                try? FileManager.default.removeItem(at: dir)
                self?.finish(with: nil)
            }
        )
        let vc = UIHostingController(rootView: view)
        vc.modalPresentationStyle = .fullScreen
        host = vc
        presenter.present(vc, animated: true)
    }

    private func finish(with value: Any?) {
        let cb = pending
        pending = nil
        host?.dismiss(animated: true) { [weak self] in
            self?.host = nil
            cb?(value)
        }
    }
}
