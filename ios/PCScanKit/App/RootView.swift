import SwiftUI

/// Bosqichga qarab tegishli ekranni ko'rsatuvchi ildiz ko'rinish.
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .onboarding:
                OnboardingView()
            case .library:
                LibraryView()
            case .scanning:
                ScanningView()
            case .processing:
                ProcessingView()
            case .viewer:
                if let artifacts = appState.artifacts {
                    ViewerView(artifacts: artifacts)
                } else {
                    OnboardingView()
                }
            }
        }
        .animation(.easeInOut, value: appState.phase)
    }
}
