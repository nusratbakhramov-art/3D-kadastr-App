import Foundation

/// O'lchov birligi (metr / santimetr) va formatlash.
enum MeasurementUnit: String, CaseIterable, Identifiable {
    case meters
    case centimeters

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .meters: return "m"
        case .centimeters: return "cm"
        }
    }

    /// Metrdagi qiymatni tanlangan birlikda formatlaydi.
    func format(_ meters: Float) -> String {
        switch self {
        case .meters:
            return String(format: "%.2f m", meters)
        case .centimeters:
            return String(format: "%.0f cm", meters * 100)
        }
    }

    /// "L × W × H" ko'rinishida uch o'lchamni formatlaydi.
    func formatDimensions(width: Float, height: Float, depth: Float) -> String {
        "\(format(width)) × \(format(depth)) × \(format(height))"
    }
}
