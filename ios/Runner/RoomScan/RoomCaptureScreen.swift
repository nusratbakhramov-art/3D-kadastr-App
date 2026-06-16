import SwiftUI
import ARKit

/// Live capture: hosts an `ARSCNView` driven by `RoomScanRecorder`
/// (`.meshWithClassification`). The dense LiDAR mesh renders live as a white
/// wireframe (captured) / blue fill (to scan), with Apple's `ARCoachingOverlayView`
/// for tracking guidance — the Polycam-style experience. Auto-starts on appear; the
/// user taps "Tugatish" to finalize and save.
@available(iOS 17, *)
struct RoomCaptureScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = RoomScanRecorder()

    /// Called once when capture ends: the saved scan id on success, or nil if the
    /// user cancelled / it failed. When set (e.g. presented from the Flutter
    /// bridge) the host handles dismissal; otherwise we dismiss ourselves.
    var onFinished: ((String?) -> Void)? = nil

    private func finish(_ id: String?) {
        if let onFinished { onFinished(id) } else { dismiss() }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(arView: recorder.arView)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomControls
            }
        }
        .onAppear { recorder.start() }
        .onChange(of: recorder.phase) { _, phase in
            if case .saved(let id) = phase { finish(id) }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button {
                finish(nil)
            } label: {
                Image(systemName: "xmark")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            if recorder.phase == .scanning {
                VStack(alignment: .trailing, spacing: 8) {
                    areaPill
                    HStack(spacing: 14) {
                        counter("camera.fill", recorder.frameCount)
                        counter("square.stack.3d.up.fill", recorder.meshAnchorCount)
                        counter("ruler.fill", recorder.depthFrameCount)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .padding()
    }

    private var areaPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.dashed")
            Text(recorder.areaM2 > 0.1 ? String(format: "≈ %.0f m²", recorder.areaM2) : "skanlang…")
                .monospacedDigit()
        }
        .font(.subheadline.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func counter(_ icon: String, _ value: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption)
            Text("\(value)").font(.subheadline.monospacedDigit().bold())
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 10) {
            switch recorder.phase {
            case .scanning:
                Button {
                    recorder.stop()
                } label: {
                    Label("Tugatish va saqlash", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)

            case .processing, .saving:
                HStack(spacing: 12) {
                    ProgressView()
                    Text(recorder.phase == .saving ? "Saqlanmoqda…" : "Qayta ishlanmoqda…")
                }
                .frame(maxWidth: .infinity)
                .padding()

            case .failed(let message):
                Text(message)
                    .font(.callout).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Yopish") { finish(nil) }
                    .buttonStyle(.bordered)

            case .idle, .saved:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

/// Hosts the recorder's `ARSCNView` and overlays Apple's `ARCoachingOverlayView`
/// (the "Session tracking lost / Return to the previous area" coaching — pure
/// ARKit, the same UI Polycam shows).
@available(iOS 17, *)
private struct ARViewContainer: UIViewRepresentable {
    let arView: ARSCNView

    func makeUIView(context: Context) -> ARSCNView {
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .tracking
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coaching.translatesAutoresizingMaskIntoConstraints = true
        coaching.frame = arView.bounds
        arView.addSubview(coaching)
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
