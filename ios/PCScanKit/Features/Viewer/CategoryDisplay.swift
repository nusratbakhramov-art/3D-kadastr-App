import RoomPlan

/// RoomPlan obyekt kategoriyalari uchun ko'rsatish nomlari va tahrirlash ro'yxati.
extension CapturedRoom.Object.Category {

    /// Tahrirlashda tanlash mumkin bo'lgan kategoriyalar (iOS 17 to'plami).
    static var selectable: [CapturedRoom.Object.Category] {
        [.storage, .refrigerator, .stove, .bed, .sink, .washerDryer,
         .toilet, .bathtub, .oven, .dishwasher, .table, .sofa,
         .chair, .fireplace, .television, .stairs]
    }

    var displayName: String {
        switch self {
        case .storage:       return "Shkaf / Javon"
        case .refrigerator:  return "Muzlatgich"
        case .stove:         return "Plita"
        case .bed:           return "Karovot"
        case .sink:          return "Rakovina"
        case .washerDryer:   return "Kir yuvish mashinasi"
        case .toilet:        return "Unitaz"
        case .bathtub:       return "Vanna"
        case .oven:          return "Duxovka"
        case .dishwasher:    return "Idish yuvish mashinasi"
        case .table:         return "Stol"
        case .sofa:          return "Divan"
        case .chair:         return "Stul"
        case .fireplace:     return "Kamin"
        case .television:    return "Televizor"
        case .stairs:        return "Zina"
        @unknown default:    return "Obyekt"
        }
    }

    var symbolName: String {
        switch self {
        case .bed:           return "bed.double"
        case .chair:         return "chair"
        case .sofa:          return "sofa"
        case .table:         return "table.furniture"
        case .television:    return "tv"
        case .refrigerator:  return "refrigerator"
        case .oven, .stove:  return "oven"
        case .stairs:        return "stairs"
        default:             return "cube"
        }
    }
}
