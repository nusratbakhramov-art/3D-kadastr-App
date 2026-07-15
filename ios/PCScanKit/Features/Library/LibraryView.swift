import SwiftUI

/// Saqlangan skanlar ro'yxati. Eskilarini ochib davom ettirish mumkin.
struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    private var library: ScanLibrary { appState.library }

    var body: some View {
        VStack(spacing: 0) {
            header

            if library.records.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(library.records) { record in
                        ScanRow(
                            record: record,
                            onOpen: { appState.openSaved(record) },
                            onReprocess: { appState.reprocess(record) }
                        )
                        .listRowBackground(Color.white.opacity(0.04))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                library.delete(record)
                            } label: {
                                Label("O'chirish", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                appState.backToOnboarding()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            Text("Saqlangan skanlar")
                .font(.headline)
            Spacer()
            Button {
                appState.startNewScan()
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .padding(10)
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(.black)
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Hali saqlangan skan yo'q")
                .foregroundStyle(.secondary)
            PrimaryButton(title: "Birinchi skanni boshlash", systemImage: "viewfinder") {
                appState.startNewScan()
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
            Spacer()
        }
    }
}

/// Ro'yxatdagi bitta skan qatori.
struct ScanRow: View {
    let record: ScanRecord
    let onOpen: () -> Void
    let onReprocess: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.accent.opacity(0.18))
                        Text("#\(record.index)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(record.title).font(.headline)
                            if record.hasTexture {
                                Image(systemName: "photo.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        Text(record.dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f m² · %.1f×%.1f m · %d obyekt · %d kadr",
                                    record.floorArea, record.width, record.depth,
                                    record.objectCount, record.frameCount))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onReprocess) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.15), in: Circle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }
}
