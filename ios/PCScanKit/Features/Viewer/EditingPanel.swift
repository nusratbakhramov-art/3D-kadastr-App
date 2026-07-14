import SwiftUI
import RoomPlan

/// M3 — Tanlangan obyekt uchun tahrirlash paneli (o'chirish / qayta nomlash).
struct EditingPanel: View {
    let item: EditableRoom.Item
    let unit: MeasurementUnit
    let onRename: (CapturedRoom.Object.Category) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(item.category.displayName, systemImage: item.category.symbolName)
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Text(unit.formatDimensions(width: item.dimensions.x,
                                       height: item.dimensions.y,
                                       depth: item.dimensions.z))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Menu {
                    ForEach(CapturedRoom.Object.Category.selectable, id: \.self) { category in
                        Button {
                            onRename(category)
                        } label: {
                            Label(category.displayName, systemImage: category.symbolName)
                        }
                    }
                } label: {
                    Label("Qayta nomlash", systemImage: "tag")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                }

                Button(role: .destructive, action: onDelete) {
                    Label("O'chirish", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.danger.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
    }
}
