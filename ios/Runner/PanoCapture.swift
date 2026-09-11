//
//  PanoCapture.swift — 360° panorama uchun ARKit bilan yo'naltirilgan suratga olish.
//
//  MANBA: `StudioProjects/360/ios/Uy360/` (CaptureController + CaptureView).
//  Mana shu farqlar bilan ko'chirilgan:
//
//   1. Matnlar Dart'dan keladi (`strings`) — ilova uch tilli, Swift'da i18n
//      takrorlanmasin.
//   2. Kadrlar 1280px ga KICHRAYTIRILIB yoziladi. O'lchangan: 28 kadr
//      79 MB → 6.2 MB, tikish sifati amalda o'zgarmaydi (qoplama 0.874 →
//      0.870). Foydalanuvchi natijani EKRANDA kutgani uchun yuklash vaqti
//      to'g'ridan-to'g'ri sanaladi.
//      ⚠️ `imageWidth/imageHeight` meta'da ASL o'lchamda qoladi — server
//      `intrinsics` ni haqiqiy JPEG o'lchamiga o'zi qayta masshtablaydi
//      (`pano_stitch._intrinsics`). Ularni kichraytirilgan o'lchamga
//      yozsak panorama butunlay noto'g'ri chiqardi.
//   3. LiDAR chuqurligi OLINMAYDI: server uni sukut bo'yicha ishlatmaydi
//      (`use_depth=False`), lekin u yuklashga ~5.5 MB qo'shardi.
//
//  Natija: `tmp/pano/<uuid>/` ichida `frame_N.jpg` + `meta.json`. Dart shu
//  katalogni o'qib serverga yuklaydi va yuklagach O'ZI o'chiradi.
//

import ARKit
import CoreImage
import SceneKit
import SwiftUI
import UIKit

// MARK: - Nishonlar

/// Sferadagi bitta nishon. Burchaklar radianda; yaw 0 = dunyo −Z (ARKit'ning
/// boshlang'ich oldi), pitch + = yuqori.
struct PanoTarget: Identifiable, Hashable {
    let id: Int
    let yaw: Float
    let pitch: Float
    let optional: Bool

    var direction: SIMD3<Float> {
        SIMD3(cos(pitch) * sin(yaw), sin(pitch), -cos(pitch) * cos(yaw))
    }
}

enum PanoTargetGrid {
    /// Gorizontda 12 (30°), +45° da 8, −45° da 8, zenit va nadir ixtiyoriy.
    /// Portret asosiy linza ≈ 55°×69° FOV → hamma joyda ≥30% ustma-ustlik.
    static func build() -> [PanoTarget] {
        var out: [PanoTarget] = []
        func add(_ yawDeg: Float, _ pitchDeg: Float, optional: Bool = false) {
            out.append(PanoTarget(
                id: out.count,
                yaw: yawDeg * .pi / 180,
                pitch: pitchDeg * .pi / 180,
                optional: optional
            ))
        }
        for k in 0..<12 { add(Float(k) * 30, 0) }
        for k in 0..<8 { add(Float(k) * 45 + 22.5, 45) }
        for k in 0..<8 { add(Float(k) * 45 + 22.5, -45) }
        add(0, 89, optional: true)
        add(0, -89, optional: true)
        return out
    }
}

/// Har kadr bilan serverga ketadigan meta.
///
/// ⚠️ Nomlar `app/services/pano_stitch.py` KUTGANI bilan aynan bir xil
/// bo'lishi shart. `transform` — camera→world 4×4, COLUMN-MAJOR.
struct PanoFrameMeta: Codable {
    var index: Int
    var targetId: Int
    var targetYaw: Float
    var targetPitch: Float
    var transform: [Float]
    var intrinsics: [Float]      // fx, fy, cx, cy — `imageWidth×imageHeight` uchun
    var imageWidth: Int          // ASL o'lcham (intrinsics shunga tegishli)
    var imageHeight: Int
    var pixelWidth: Int          // yozilgan JPEG'ning haqiqiy o'lchami
    var pixelHeight: Int
    var timestamp: Double
    var highRes: Bool
    var file: String
}

// MARK: - Kontroller

/// ARKit sessiyasini boshqaradi: nishonlarni ekranga proyeksiya qiladi,
/// telefon nishonda "ushlab turilganda" avtomatik surat oladi va kadrni
/// pozasi bilan diskka yozadi.
final class PanoCaptureController: NSObject, ObservableObject, ARSessionDelegate {
    struct Dot: Identifiable {
        let id: Int
        var point: CGPoint
        var visible: Bool
        var captured: Bool
        var optional: Bool
    }

    @Published var dots: [Dot] = []
    @Published var capturedCount = 0
    @Published var nearestAngle: Float = 999
    @Published var dwellProgress: Double = 0
    @Published var message = ""
    @Published var moved = false
    @Published var trackingOK = false
    @Published var lastThumb: UIImage?

    let targets: [PanoTarget]
    let requiredTotal: Int
    let session = ARSession()
    let dir: URL
    var viewSize: CGSize = .zero

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

    // Faqat ioQueue'da tegiladi.
    private var metas: [PanoFrameMeta] = []

    /// Nishonda shuncha turilsa surat olinadi.
    private let dwellSeconds: TimeInterval = 0.35
    /// Nishonga shuncha yaqin bo'lishi kerak.
    private let angleThreshold: Float = 3.5 * .pi / 180
    /// Shundan tez burilayotganda olinmaydi — surat xira chiqardi.
    private let maxAngularSpeed: Float = 12 * .pi / 180

    /// Yozilayotgan JPEG'ning uzun tomoni. Fayl sarlavhasidagi izohga qarang.
    private let maxEdge: CGFloat = 1280

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
        // Dunyo +Y = tortishishga qarama-qarshi. Server gorizontni shunga
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
        DispatchQueue.main.async {
            self.dots = self.dots.map {
                $0.optional ? Dot(id: $0.id, point: $0.point, visible: $0.visible,
                                  captured: true, optional: true) : $0
            }
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
            newDots.append(Dot(id: t.id, point: pt, visible: inFront, captured: isCap, optional: t.optional))
            if !isCap, nearest == nil || ang < nearest!.angle { nearest = (t.id, ang) }
        }

        var dwell: Double = 0
        if ok, !capturing, let n = nearest, n.angle < angleThreshold, angSpeed < maxAngularSpeed {
            if dwellTarget != n.id { dwellTarget = n.id; dwellStart = now }
            let elapsed = now - (dwellStart ?? now)
            dwell = min(1, elapsed / dwellSeconds)
            if elapsed >= dwellSeconds { trigger(targetId: n.id, frame: frame) }
        } else {
            dwellTarget = nil
            dwellStart = nil
        }

        // Foydalanuvchi O'ZI atrofida emas, TELEFON atrofida aylanishi kerak:
        // tana atrofida aylansa 30–40 sm richag paydo bo'ladi va yaqin
        // obyektlar chokda siljiydi (parallaks).
        var movedNow = false
        if let a = anchorPosition { movedNow = simd_distance(a, pos) > 0.2 }
        let msg: String
        if !ok {
            msg = s("tracking", "Telefonni sekin harakatlantiring…")
        } else if movedNow {
            msg = s("moved", "Joyingizda turing — telefon atrofida aylaning")
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
        let full = ci.extent.size

        ioQueue.async { [self] in
            // Kichraytirish — fayl sarlavhasidagi izohga qarang.
            let scale = min(1.0, maxEdge / max(full.width, full.height))
            let out = scale < 1.0
                ? ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                : ci
            let pw = Int((full.width * scale).rounded())
            let ph = Int((full.height * scale).rounded())

            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let opts: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(
                    rawValue: kCGImageDestinationLossyCompressionQuality as String
                ): 0.88,
            ]
            if let data = ciContext.jpegRepresentation(of: out, colorSpace: cs, options: opts) {
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

            let small = out.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
            let thumb = ciContext.createCGImage(small, from: small.extent).map {
                UIImage(cgImage: $0, scale: 1, orientation: .right)
            }
            DispatchQueue.main.async {
                self.capturedCount += 1
                self.lastThumb = thumb
                self.haptic.impactOccurred()
            }
            arQueue.async {
                capturing = false
                lockExposureIfNeeded()
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
        return v
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

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

                dots
                reticle(center: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                hud
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .confirmationDialog(
            s("finish_title", "Tushirishni yakunlash?"),
            isPresented: $confirmFinish,
            titleVisibility: .visible
        ) {
            Button(s("finish_yes", "Yakunlash")) { onFinish(ctrl.finish()) }
            Button(s("finish_no", "Davom etish"), role: .cancel) {}
        } message: {
            Text(
                s("finish_body", "%d kadr olindi. Kam kadr — sferada boʻshliq boʻladi.")
                    .replacingOccurrences(of: "%d", with: "\(ctrl.capturedCount)")
            )
        }
    }

    private var dots: some View {
        ForEach(ctrl.dots) { d in
            if d.visible {
                ZStack {
                    Circle()
                        .fill(d.captured
                              ? Color.green.opacity(0.35)
                              : (d.optional ? Color.orange.opacity(0.6) : Color.white.opacity(0.85)))
                        .frame(width: d.captured ? 18 : 26, height: d.captured ? 18 : 26)
                    if d.captured {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(radius: 3)
                .position(d.point)
                .animation(.linear(duration: 0.05), value: d.point)
            }
        }
    }

    private func reticle(center: CGPoint) -> some View {
        let near = ctrl.nearestAngle < 3.5 * .pi / 180
        return ZStack {
            Circle()
                .stroke(near ? Color.green : Color.white.opacity(0.8), lineWidth: 3)
                .frame(width: 64, height: 64)
            Circle()
                .trim(from: 0, to: ctrl.dwellProgress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 64, height: 64)
            Circle().fill(near ? Color.green : Color.white).frame(width: 6, height: 6)
        }
        .position(center)
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                Button { onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .padding(12)
                        .background(.black.opacity(0.4), in: Circle())
                }
                Spacer()
                Text("\(ctrl.capturedCount) / \(ctrl.requiredTotal)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.top, 56)

            if !ctrl.message.isEmpty {
                Text(ctrl.message)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(
                        ctrl.moved ? Color.orange.opacity(0.9) : Color.black.opacity(0.5),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .padding(.top, 8)
            }

            Spacer()

            HStack(alignment: .bottom) {
                if let t = ctrl.lastThumb {
                    Image(uiImage: t)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 74).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.7)))
                }
                Spacer()
                VStack(spacing: 10) {
                    Button(s("skip_poles", "Zenit/nadirni oʻtkazish")) { ctrl.skipOptional() }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button {
                        confirmFinish = true
                    } label: {
                        Label(s("finish", "Yakunlash"), systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ctrl.capturedCount >= ctrl.requiredTotal ? .green : .gray)
                    // 4 kadrdan kam bo'lsa tikishning ma'nosi yo'q.
                    .disabled(ctrl.capturedCount < 4)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 44)

            Text(s("hint", "Xona markazida turing · telefonni koʻkrak balandligida tuting · nuqtaga toʻgʻrilab bir lahza ushlang"))
                .font(.caption2).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24).padding(.bottom, 14)
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

    func start(from presenter: UIViewController, strings: [String: String], result: @escaping FlutterResult) {
        guard pending == nil else {
            result(FlutterError(code: "BUSY", message: "Suratga olish allaqachon ochiq", details: nil))
            return
        }
        guard isSupported else {
            result(FlutterError(code: "UNSUPPORTED", message: "Qurilma ARKit'ni qoʻllamaydi", details: nil))
            return
        }
        // `tmp/` — kadrlar vaqtinchalik: Dart ularni yuklaydi va o'chiradi.
        // iCloud'ga zaxiralanmaydi va ilova ishlab turganda tozalanmaydi.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pano", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
