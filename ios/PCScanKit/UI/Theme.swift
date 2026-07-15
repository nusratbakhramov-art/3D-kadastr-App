import SwiftUI

/// Ilova bo'ylab yagona dizayn tili.
enum Theme {
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.90)
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.35)
    static let surface = Color.black.opacity(0.55)
}

/// Asosiy harakat tugmasi (Start, Continue, ...).
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.accent
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .background(enabled ? tint : Color.gray.opacity(0.4))
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(!enabled)
    }
}

/// Yarim shaffof ustki panel uchun material fon.
struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func glassPanel() -> some View { modifier(GlassBackground()) }
}
