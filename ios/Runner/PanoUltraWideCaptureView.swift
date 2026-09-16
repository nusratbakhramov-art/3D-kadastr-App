import AVFoundation
import SwiftUI
import UIKit

/// Camera window for the ultra-wide (0.5×) path: hosts the controller's
/// `AVCaptureVideoPreviewLayer` directly (no ARKit / ARSCNView). The layer is sized to the
/// view bounds in `layoutSubviews` so it tracks rotation and safe-area changes. Unlike the
/// ARKit path this is NOT full-screen — it fills the portrait 3:4 viewfinder rectangle.
final class PanoUltraWidePreviewHostView: UIView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true            // aspect-fill must not bleed outside the white frame
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit animation on resize/rotation
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

@available(iOS 15.4, *)
struct PanoUltraWidePreviewContainer: UIViewRepresentable {
    let controller: PanoUltraWideCaptureController

    func makeUIView(context: Context) -> PanoUltraWidePreviewHostView {
        PanoUltraWidePreviewHostView(previewLayer: controller.previewLayer)
    }

    func updateUIView(_ uiView: PanoUltraWidePreviewHostView, context: Context) {}
}

/// Ultra-wide (Teleport-style) capture screen, laid out 1:1 with Teleport's capture UI:
/// black screen, white undo circle top-left, red close circle top-right, the live camera in a
/// portrait 3:4 rectangle with a hairline white border in the middle, the instruction line under
/// it and a rounded progress bar + "N / total" at the bottom.
///
/// The distinctive part: the preview rectangle, the target dots, the dwell reticle and the chevron
/// all live in ONE container that is rotated by −`ctrl.rollRadians`, so the scene inside stands
/// gravity-upright while the white frame tilts with the phone. The black page behind it never
/// rotates and the container is never clipped, so dots may overflow past the frame edges.
@available(iOS 15.4, *)
struct PanoUltraWideCaptureView: View {
    @StateObject var ctrl: PanoUltraWideCaptureController
    let onFinish: (Int) -> Void
    let strings: [String: String]
    let onError: (String, String) -> Void
    let onCancel: () -> Void

    @State private var showFinishConfirm = false

    init(dir: URL, strings: [String: String], onFinish: @escaping (Int) -> Void,
         onCancel: @escaping () -> Void, onError: @escaping (String, String) -> Void) {
        _ctrl = StateObject(wrappedValue: PanoUltraWideCaptureController(dir: dir, strings: strings))
        self.strings = strings
        self.onError = onError
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    private func s(_ key: String, _ fallback: String) -> String { strings[key] ?? fallback }

    // MARK: style constants (Teleport reference)

    /// Teleport's target green.
    private static let targetGreen = Color(red: 0x3D / 255, green: 0xDC / 255, blue: 0x5B / 255)
    private static let warnRed = Color(red: 1.0, green: 0.33, blue: 0.30)
    /// The viewfinder rectangle takes ~82% of the screen width, portrait 3:4 (= the 4:3 sensor
    /// image rotated upright, so `resizeAspectFill` crops nothing).
    private static let frameWidthFraction: CGFloat = 0.82
    private static let frameAspect: CGFloat = 3.0 / 4.0
    /// Vertical space the chrome above/below the viewfinder needs; the rectangle shrinks to fit
    /// on short screens. Constant (never depends on the finish button) so `ctrl.viewSize` — and
    /// with it the dot projection — never changes mid-capture.
    private static let chromeHeight: CGFloat = 312
    private static let dotSize: CGFloat = 56
    private static let reticleSize: CGFloat = 90

    private static let hintText =
        "0.5× obyektivni bir nuqtada ushlang; telefonni shu nuqta atrofida buring."

    private var total: Int { ctrl.requiredTotal }
    private var complete: Bool { ctrl.capturedCount >= ctrl.requiredTotal }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let err = ctrl.fatalError {
                errorView(err)
            } else {
                capturePage
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        // Hands-free capture: keep the screen awake while the user dwells on targets.
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            ctrl.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            ctrl.stop()
        }
        .onChange(of: showFinishConfirm) { ctrl.setConfirmationVisible($0) }
        .confirmationDialog(s("finish_title", "Tushirishni yakunlash?"), isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button(s("finish_yes", "Yakunlash va tikish")) { ctrl.finish(confirmedEarly: true, completion: onFinish) }
                .disabled(ctrl.isCapturing)
            Button(s("finish_no", "Davom etish"), role: .cancel) {}
        } message: {
            Text(s("finish_body", "%d / %t kadr olindi. Kam kadr — sferada bo'shliq bo'ladi.")
                .replacingOccurrences(of: "%d", with: "\(ctrl.capturedCount)")
                .replacingOccurrences(of: "%t", with: "\(total)"))
        }
    }

    // MARK: page

    private var capturePage: some View {
        GeometryReader { screen in
            let frameWidth = min(screen.size.width * Self.frameWidthFraction,
                                 max(120, (screen.size.height - Self.chromeHeight) * Self.frameAspect))
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 52)
                    .zIndex(1)              // dots may overflow upward — keep the buttons visible
                Spacer(minLength: 0)
                viewfinder(width: frameWidth)
                instruction
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                Spacer(minLength: 0)
                bottomBar
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
            }
            .frame(width: screen.size.width, height: screen.size.height)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { ctrl.undoLast() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(ctrl.canUndo ? 1 : 0.3), in: Circle())
            }
            .disabled(!ctrl.canUndo)
            Spacer()
            Button { ctrl.cancel(completion: onCancel) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.red, in: Circle())
            }
        }
    }

    // MARK: the tilted viewfinder (preview + border + dots + reticle + chevron)

    /// Everything the world-stabilised scene owns sits in this one container, rotated by −roll:
    /// the frame tilts with the phone while the scene inside stays gravity-upright (Teleport).
    /// No `.clipped()` anywhere on it — the dots must be free to overflow the frame edges.
    private func viewfinder(width w: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                PanoUltraWidePreviewContainer(controller: ctrl)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 1))
                dotsLayer(in: geo.size)
                reticle(center: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // The controller projects the dots into a space of exactly this size (centre at
            // viewSize/2, focal length from viewSize.height) — so it must be the RECT's size.
            .onAppear { ctrl.viewSize = geo.size }
            .onChange(of: geo.size) { newSize in ctrl.viewSize = newSize }
        }
        .frame(width: w, height: w / Self.frameAspect)
        .rotationEffect(.radians(-ctrl.rollRadians))
        .allowsHitTesting(false)
    }

    /// Target dots in the preview rectangle's coordinate space. Positions are applied directly —
    /// deliberately NO animation on `point`, otherwise the dots lag and jitter behind the gyro.
    private func dotsLayer(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(ctrl.dots) { d in
                if d.visible {
                    dot(d).position(x: d.point.x, y: d.point.y)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func dot(_ d: PanoUltraWideCaptureController.Dot) -> some View {
        let live = d.captured || d.isNext
        let core: Color = live ? Self.targetGreen : Color.white.opacity(0.45)
        let halo: CGFloat = d.isNext ? Self.dotSize * 1.8 : Self.dotSize * 1.35
        return ZStack {
            Circle()
                .fill(live ? Self.targetGreen.opacity(0.22) : Color.white.opacity(0.12))
                .frame(width: halo, height: halo)
            Circle()
                .fill(core)
                .frame(width: Self.dotSize, height: Self.dotSize)
            if d.captured {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 4)
    }

    /// Centre ring that fills as the user dwells, plus the chevron toward the next target.
    private func reticle(center: CGPoint) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 2.5)
                .frame(width: Self.reticleSize, height: Self.reticleSize)
            Circle()
                .trim(from: 0, to: ctrl.dwellProgress)
                .stroke(Self.targetGreen, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: Self.reticleSize, height: Self.reticleSize)
                .animation(.linear(duration: 0.08), value: ctrl.dwellProgress)
            if let a = ctrl.chevronAngle {
                Image(systemName: "chevron.right")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .offset(x: Self.reticleSize / 2 + 26)
                    .rotationEffect(.radians(a))
            }
        }
        .position(center)
        .allowsHitTesting(false)
    }

    // MARK: instruction + bottom bar

    private var instruction: some View {
        let warn = !ctrl.message.isEmpty
        return Text(warn ? ctrl.message : s("uw_hint", Self.hintText))
            .font(.system(size: 17, weight: warn ? .semibold : .regular))
            .foregroundStyle(warn ? Self.warnRed : Color.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if complete {
                // All targets are in — nothing to warn about, so finish straight away.
                Button { ctrl.finish(completion: onFinish) } label: {
                    Label(s("finish", "Yakunlash"), systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Self.targetGreen)
                .disabled(ctrl.isCapturing)
            } else if ctrl.capturedCount >= 4 {
                Button { showFinishConfirm = true } label: {
                    Text(s("early_finish", "Erta yakunlash"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .disabled(ctrl.isCapturing)
            }
            HStack(spacing: 14) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule()
                            .fill(Self.targetGreen)
                            .frame(width: g.size.width * progressFraction)
                    }
                }
                .frame(height: 10)
                Text("\(ctrl.capturedCount) / \(total)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }

    private var progressFraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(ctrl.capturedCount) / CGFloat(total))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 52)).foregroundStyle(.orange)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
            Button { ctrl.cancel { onError(ctrl.failureCode, message) } } label: {
                Label(s("close", "Yopish"), systemImage: "xmark")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(Color.white, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
