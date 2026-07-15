import RoomPlan
import simd

/// Xonaning umumiy chegaralari (footprint + balandlik).
struct RoomBounds {
    var minX: Float
    var maxX: Float
    var minZ: Float
    var maxZ: Float
    var floorY: Float
    var ceilingY: Float

    var width: Float { max(maxX - minX, 0.01) }
    var depth: Float { max(maxZ - minZ, 0.01) }
    var height: Float { max(ceilingY - floorY, 0.01) }

    var centerX: Float { (minX + maxX) / 2 }
    var centerZ: Float { (minZ + maxZ) / 2 }
}

/// RoomPlan strukturasidan geometrik xulosalar (footprint, pol/shift balandligi).
enum RoomGeometry {

    static func bounds(of room: CapturedRoom) -> RoomBounds {
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        var floorY = Float.greatestFiniteMagnitude
        var ceilingY = -Float.greatestFiniteMagnitude

        func consume(_ x: Float, _ z: Float) {
            minX = min(minX, x); maxX = max(maxX, x)
            minZ = min(minZ, z); maxZ = max(maxZ, z)
        }

        for wall in room.walls {
            let t = wall.transform
            let pos = simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            let xAxis = simd_normalize(simd_float3(t.columns.0.x, t.columns.0.y, t.columns.0.z))
            let half = wall.dimensions.x / 2
            let e1 = pos + xAxis * half
            let e2 = pos - xAxis * half
            consume(e1.x, e1.z)
            consume(e2.x, e2.z)
            floorY = min(floorY, pos.y - wall.dimensions.y / 2)
            ceilingY = max(ceilingY, pos.y + wall.dimensions.y / 2)
        }

        // Devor topilmasa — obyektlar bo'yicha yoki standart qiymatlar bilan zaxira.
        if minX > maxX {
            for object in room.objects {
                let p = object.transform.columns.3
                consume(p.x, p.z)
            }
            if minX > maxX { minX = -2; maxX = 2; minZ = -2; maxZ = 2 }
            floorY = 0
            ceilingY = 2.6
        }
        if floorY > ceilingY { floorY = 0; ceilingY = 2.6 }

        return RoomBounds(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ,
                          floorY: floorY, ceilingY: ceilingY)
    }

    // MARK: - Maydon va perimetr

    /// Xona pol maydoni (m²).
    /// Aniq usul: pol yuzasi(lar)ining `polygonCorners` poligoni bo'yicha
    /// (L-shaped/nostandart xonalar uchun ham to'g'ri). Zaxira: footprint to'rtburchagi.
    static func floorArea(of room: CapturedRoom) -> Float {
        let polygonAreaSum = room.floors.reduce(Float(0)) { partial, floor in
            partial + polygonArea(floor.polygonCorners)
        }
        if polygonAreaSum > 0.01 {
            return polygonAreaSum
        }
        // Zaxira: devor footprint'idan to'rtburchak taxmin (yuqori chegara).
        let b = bounds(of: room)
        return b.width * b.depth
    }

    /// Xona perimetri (m) — pol poligoni bo'yicha.
    static func floorPerimeter(of room: CapturedRoom) -> Float {
        let perimeter = room.floors.reduce(Float(0)) { partial, floor in
            partial + polygonPerimeter(floor.polygonCorners)
        }
        if perimeter > 0.01 { return perimeter }
        let b = bounds(of: room)
        return 2 * (b.width + b.depth)
    }

    /// Fazoviy (3D) tekis poligon maydoni — Newell usuli (tekislik orientatsiyasiga bog'liq emas).
    static func polygonArea(_ corners: [simd_float3]) -> Float {
        guard corners.count >= 3 else { return 0 }
        var accumulator = simd_float3(repeating: 0)
        for i in corners.indices {
            let a = corners[i]
            let b = corners[(i + 1) % corners.count]
            accumulator += simd_cross(a, b)
        }
        return simd_length(accumulator) * 0.5
    }

    private static func polygonPerimeter(_ corners: [simd_float3]) -> Float {
        guard corners.count >= 2 else { return 0 }
        var total: Float = 0
        for i in corners.indices {
            total += simd_distance(corners[i], corners[(i + 1) % corners.count])
        }
        return total
    }
}
