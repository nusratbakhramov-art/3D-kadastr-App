import Foundation

/// Saqlangan skan haqidagi metadata (metadata.json).
struct ScanRecord: Codable, Identifiable, Equatable {
    let id: UUID
    /// Foydalanuvchiga ko'rinadigan tartib raqami (1, 2, 3...).
    var index: Int
    /// Sessiya papkasi nomi (Documents/Scans/<folderName>).
    let folderName: String
    let createdAt: Date

    // O'lchov ma'lumotlari
    var floorArea: Float
    var floorPerimeter: Float
    var width: Float
    var depth: Float
    var height: Float

    // Statistika
    var wallCount: Int
    var objectCount: Int
    var frameCount: Int
    var hasTexture: Bool
    /// LiDAR mesh olinganmi (ixtiyoriy — eski yozuvlar uchun nil bo'lishi mumkin).
    var hasMesh: Bool?

    var title: String { "Skan #\(index)" }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uz")
        formatter.dateFormat = "d-MMM, HH:mm"
        return formatter.string(from: createdAt)
    }
}
