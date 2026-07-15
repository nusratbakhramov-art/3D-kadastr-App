import Foundation
import simd

/// Bitta RGB keyframe'ning kamera pozitsiyasi (2-bosqich: tekstura proyeksiyasi uchun).
struct KeyframePose: Codable {
    let index: Int
    /// 16 — kamera->world (column-major). PoseRefiner (ICP) aniqlashtirгач
    /// qayta yozilishi mumkin — shuning uchun var.
    var transform: [Float]
    let intrinsics: [Float]  // 9  — piksel proyeksiyasi (column-major)
    let width: Int
    let height: Int
    /// LiDAR depth mavjudmi va uning o'lchamlari (eski yozuvlar uchun optional).
    var depthWidth: Int? = nil
    var depthHeight: Int? = nil
    /// ARKit avto-ekspozitsiya siljishi (EV birligida) — teksturalashda kadr
    /// yorqinligini tenglashtirish uchun (eski yozuvlar uchun optional).
    var exposureOffset: Float? = nil

    init(index: Int, transform t: simd_float4x4, intrinsics k: simd_float3x3, width: Int, height: Int) {
        self.index = index
        self.transform = [
            t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
            t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
            t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
            t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
        ]
        self.intrinsics = [
            k.columns.0.x, k.columns.0.y, k.columns.0.z,
            k.columns.1.x, k.columns.1.y, k.columns.1.z,
            k.columns.2.x, k.columns.2.y, k.columns.2.z
        ]
        self.width = width
        self.height = height
    }
}
