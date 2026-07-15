import SwiftUI

/// M3 — Tayyor model ekrani: 3D ko'rish, rejimlar, o'lchovlar, tahrirlash.
struct ViewerView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: ViewerViewModel
    @State private var showReprocessConfirm = false

    init(artifacts: ScanArtifacts) {
        _vm = StateObject(wrappedValue: ViewerViewModel(artifacts: artifacts))
    }

    var body: some View {
        ZStack {
            SceneViewContainer(controller: vm.controller)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if let item = vm.selectedItem {
                    EditingPanel(
                        item: item,
                        unit: vm.unit,
                        onRename: { vm.rename(to: $0) },
                        onDelete: { vm.deleteSelected() },
                        onClose: { vm.deselect() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !vm.hasTexture {
                    processCTA
                } else {
                    hintBar
                }
            }
            .padding(.top)
            .padding(.bottom, 12)
            .animation(.easeInOut, value: vm.selectedID)
        }
        .confirmationDialog(
            "Teksturани saqlangan kadrlardan qayta hisoblaymizmi? Bu bir necha daqiqa oladi (qayta skanerlash shart emas).",
            isPresented: $showReprocessConfirm,
            titleVisibility: .visible
        ) {
            Button("Qayta ishlash") { appState.reprocessCurrent() }
            Button("Bekor qilish", role: .cancel) {}
        }
    }

    // MARK: - Yuqori panel

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    appState.openLibrary()
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Button {
                    appState.startNewScan()
                } label: {
                    Label("Yangi", systemImage: "plus.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Button {
                    showReprocessConfirm = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                controlCluster
            }
            .padding(.horizontal)

            modePicker
                .padding(.horizontal)

            metricsChip

            if vm.mode == .textured && !vm.hasTexture {
                Text("Bu skanda real tekstura yo'q — parametrik model ko'rsatilmoqda.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metricsChip: some View {
        HStack(spacing: 14) {
            Label(String(format: "%.1f m²", vm.floorArea), systemImage: "square.dashed")
            Divider().frame(height: 14)
            Label(String(format: "%.1f m", vm.floorPerimeter), systemImage: "ruler")
        }
        .font(.footnote.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var modePicker: some View {
        Picker("Rejim", selection: Binding(
            get: { vm.mode },
            set: { vm.setMode($0) }
        )) {
            ForEach(ViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var controlCluster: some View {
        HStack(spacing: 8) {
            iconToggle(system: "ruler", active: vm.labelsVisible) { vm.toggleLabels() }
            iconButton(text: vm.unit.shortLabel) { vm.toggleUnit() }
            iconToggle(system: "figure.walk", active: vm.firstPerson) { vm.toggleFirstPerson() }
        }
    }

    private func iconToggle(system: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.headline)
                .foregroundStyle(active ? Color.black : Color.primary)
                .frame(width: 40, height: 40)
                .background(active ? Theme.accent : Color.clear, in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func iconButton(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.headline.monospaced())
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    /// Xom (hali qayta ishlanmagan) skan uchun — real teksturali modelni yaratish tugmasi.
    private var processCTA: some View {
        VStack(spacing: 8) {
            Text("Skan saqlandi. Real teksturali 3D model uchun ishga tushiring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PrimaryButton(title: "Natijani ishlash", systemImage: "wand.and.stars") {
                appState.reprocessCurrent()
            }
        }
        .padding(.horizontal)
    }

    private var hintBar: some View {
        Text(vm.firstPerson
             ? "Bir barmoq — qarash · Ikki barmoq — yurish"
             : "Obyektni tanlash uchun ustiga bosing · Aylantirish/zoom — barmoq bilan")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
