import SwiftUI

/// M1 — Skanerlash ekrani. Minimalistik: RoomPlan AR ko'rinishi + Start/Stop + coaching.
struct ScanningView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var controller = ScanController()
    @State private var errorMessage: String?
    /// KADASTR-LOCAL: capture-only avto-startni aynan bir marta ishga tushirish uchun.
    @State private var didAutoStart = false

    /// KADASTR-LOCAL: AI Baholash "capture-only" rejimi (onboarding/X/Boshlash YO'Q,
    /// darhol skanerlash boshlanadi). `presentCapture` `captureOnlyCompletion` o'rnatadi.
    private var isCaptureOnly: Bool { appState.captureOnlyCompletion != nil }

    var body: some View {
        ZStack {
            ARSceneContainer(arView: controller.arView)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if controller.isFinalizing {
                    finalizingOverlay
                }
                Spacer()
                bottomControls
            }
            .padding()
        }
        .onAppear(perform: configure)
        .alert("Xatolik", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Bo'laklar

    private var topBar: some View {
        HStack {
            // KADASTR-LOCAL: capture-only rejimda "X" YO'Q (Flutter modal boshqaradi,
            // bekor yo'li kamera rad etilsa avtomatik ishlaydi).
            if !isCaptureOnly {
                Button {
                    controller.stop()
                    appState.backToOnboarding()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            Spacer()
            if controller.isScanning {
                Label("\(controller.wallCount) devor · \(controller.capturedFrames) kadr · \(controller.meshChunks) mesh",
                      systemImage: "grid")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var finalizingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Model yakunlanmoqda…")
                .font(.callout)
        }
        .glassPanel()
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if controller.isScanning {
                Text(controller.instructionText.isEmpty
                     ? "Sekin aylaning · pol, devor va burchaklarni to'liq qamrang"
                     : controller.instructionText)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())

                if controller.capturedFrames < 120 {
                    Text("Ko'proq qamrov uchun harakatda davom eting (\(controller.capturedFrames) kadr)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if controller.isScanning {
                PrimaryButton(title: "Skanerlashni tugatish", systemImage: "stop.fill", tint: Theme.danger) {
                    controller.stop()
                }
            } else if !controller.isFinalizing && !isCaptureOnly {
                // KADASTR-LOCAL: capture-only rejimda avto-start bo'ladi — qo'lda
                // "Boshlash" tugmasi ko'rsatilmaydi.
                PrimaryButton(title: "Boshlash", systemImage: "record.circle") {
                    controller.start()
                }
            }
        }
    }

    private func configure() {
        controller.onFinished = { room, paths in
            appState.scanningFinished(room: room, imagesFolder: paths.imagesFolder, paths: paths)
        }
        controller.onError = { error in
            errorMessage = error.localizedDescription
        }
        // KADASTR-LOCAL: capture-only rejimda onboarding/"Boshlash" YO'Q — kamera
        // ruxsatini so'rab, darhol skanerlashni boshlaymiz (aynan bir marta).
        if isCaptureOnly, !didAutoStart {
            didAutoStart = true
            Task {
                let granted = await appState.permissions.requestCamera()
                if granted {
                    controller.start()
                } else {
                    // Ruxsat yo'q va X tugmasi ham yo'q — Flutter modal'iga bekor bilan qaytamiz.
                    appState.captureCancelled?()
                }
            }
        }
    }
}
