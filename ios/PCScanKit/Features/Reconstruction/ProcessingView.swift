import SwiftUI

/// M2 — Qayta ishlash (Processing) ekrani. Object Capture tugagach viewer'ga o'tadi.
struct ProcessingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ReconstructionViewModel()
    @State private var started = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0.02, viewModel.progress))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: viewModel.progress)
                Text("\(Int(viewModel.progress * 100))%")
                    .font(.title2.monospacedDigit().bold())
            }
            .frame(width: 160, height: 160)

            VStack(spacing: 8) {
                Text("Real teksturali model tayyorlanmoqda")
                    .font(.headline)
                Text(viewModel.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Text("Object Capture yuqori sifat uchun bir necha daqiqa ishlashi mumkin. Ilovadan chiqmang.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .task {
            guard !started, let artifacts = appState.artifacts else { return }
            started = true
            let url = await viewModel.run(paths: artifacts.paths, room: artifacts.capturedRoom)
            // Tekstura bo'lsa u bilan, bo'lmasa parametrik model bilan viewer'ga o'tamiz.
            appState.processingFinished(texturedModelURL: url)
        }
    }
}
