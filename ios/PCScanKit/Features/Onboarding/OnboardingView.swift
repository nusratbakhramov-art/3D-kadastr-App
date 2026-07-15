import SwiftUI

/// M0 — Kirish ekrani: qurilma mosligi + kamera ruxsati + skanerlashni boshlash.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var requestingPermission = false

    private var supported: Bool { DeviceCapability.meetsMinimumRequirements }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 68, weight: .thin))
                    .foregroundStyle(Theme.accent)
                Text("PCScan")
                    .font(.largeTitle.bold())
                Text("Xonani LiDAR bilan skanerlab, real teksturali 3D modelga aylantiring.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Qurilma imkoniyatlari", systemImage: "checklist")
                    .font(.headline)
                Text(DeviceCapability.summary)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                if supported {
                    PrimaryButton(
                        title: "Skanerlashni boshlash",
                        systemImage: "viewfinder",
                        enabled: !requestingPermission
                    ) {
                        Task { await startFlow() }
                    }

                    if appState.permissions.camera == .denied {
                        Text("Kamera ruxsati rad etilgan. Sozlamalar → PCScan orqali yoqing.")
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("Bu qurilmada LiDAR skaneri yo'q. Ilova iPhone Pro / iPad Pro modellarini talab qiladi.")
                        .font(.callout)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }

                // Saqlangan skanlarni ko'rish LiDAR talab qilmaydi (viewer + simulyator).
                if !appState.library.records.isEmpty {
                    Button {
                        appState.openLibrary()
                    } label: {
                        Label("Saqlangan skanlar (\(appState.library.records.count))",
                              systemImage: "square.stack.3d.up")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private func startFlow() async {
        requestingPermission = true
        defer { requestingPermission = false }
        let granted = await appState.permissions.requestCamera()
        if granted {
            appState.beginScanning()
        }
    }
}
