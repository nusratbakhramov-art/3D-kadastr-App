import Foundation
import RoomPlan
import simd

/// M3 — Tahrirlanadigan xona modeli. CapturedRoom'dan mustaqil nusxa saqlaydi,
/// shunda foydalanuvchi obyektlarni o'chirishi/qayta nomlashi mumkin.
@MainActor
final class EditableRoom: ObservableObject {

    struct Item: Identifiable {
        let id: UUID
        var category: CapturedRoom.Object.Category
        let dimensions: simd_float3
        let transform: simd_float4x4
    }

    let room: CapturedRoom
    @Published private(set) var objects: [Item]

    init(room: CapturedRoom) {
        self.room = room
        self.objects = room.objects.map {
            Item(id: $0.identifier,
                 category: $0.category,
                 dimensions: $0.dimensions,
                 transform: $0.transform)
        }
    }

    func item(id: UUID) -> Item? {
        objects.first { $0.id == id }
    }

    func rename(id: UUID, to category: CapturedRoom.Object.Category) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].category = category
    }

    func delete(id: UUID) {
        objects.removeAll { $0.id == id }
    }
}
