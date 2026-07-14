import Foundation
import RealityKit
import simd
import UIKit

/// Skan-vaqti TEKSTURA QAMROVI indikatori (Scaniverse/Polycam uslubida).
/// Jonli mesh chunk'larini yarim-shaffof rang bilan sahnaga qo'yadi:
///   QIZIL  = hali kamera yaxshi (yaqin + frontal) olmagan → yaqinroq/yaxshiroq skan qiling
///   YASHIL = kamera yetarli olgan → tekstura toza chiqadi
/// Shu bilan foydalanuvchi qaysi joy hali "yopilmaganini" ko'radi va teshik qolmaydi.
final class CoverageOverlay {

    let anchor = AnchorEntity(world: .zero)
    private var entities: [Int64: ModelEntity] = [:]
    private var centroids: [Int64: SIMD3<Float>] = [:]
    private var covered = Set<Int64>()

    private(set) var isVisible = false

    // Qamrov mezoni (kamera keyframe chunk markazini yaxshi ko'rganmi)
    private let minDist: Float = 0.25
    private let maxDist: Float = 3.5
    private let minCos: Float = 0.5   // kamera yo'nalishi bilan burchak ~60°

    init() { anchor.isEnabled = false }

    /// Mesh yangilanishini qabul qiladi (id → entity, nil = o'chirish).
    /// Entity'ni QAYTA ISHLATADI (mesh qayta qurilmaydi) — faqat materialни qamrovga bog'laydi.
    func apply(_ changes: [Int64: ModelEntity?]) {
        for (id, entity) in changes {
            if let entity {
                // Yangilanishda ViewModel YANGI entity yaratadi — eskisini almashtiramiz
                if let old = entities[id], old !== entity { old.removeFromParent() }
                entity.model?.materials = [Self.material(covered: covered.contains(id))]
                anchor.addChild(entity)
                entities[id] = entity
                let b = entity.visualBounds(relativeTo: nil)
                centroids[id] = b.center
            } else {
                if let e = entities[id] { e.removeFromParent() }
                entities.removeValue(forKey: id)
                centroids.removeValue(forKey: id)
                covered.remove(id)
            }
        }
    }

    /// Yangi keyframe (kamera pozasi) — ko'rilgan chunk'larni "qamrab olingan" deb belgilaydi.
    /// Qamrov ulushini (0…1) qaytaradi.
    @discardableResult
    func addKeyframe(position: SIMD3<Float>, forward: SIMD3<Float>) -> Float {
        for (id, c) in centroids where !covered.contains(id) {
            let v = c - position
            let dist = simd_length(v)
            if dist < minDist || dist > maxDist { continue }
            let dir = v / max(dist, 1e-5)
            if simd_dot(dir, forward) < minCos { continue }
            covered.insert(id)
            entities[id]?.model?.materials = [Self.material(covered: true)]
        }
        return coverageFraction
    }

    var coverageFraction: Float {
        guard !entities.isEmpty else { return 0 }
        return Float(covered.count) / Float(entities.count)
    }

    func setVisible(_ v: Bool) {
        isVisible = v
        anchor.isEnabled = v
    }

    func reset() {
        for e in entities.values { e.removeFromParent() }
        entities.removeAll(); centroids.removeAll(); covered.removeAll()
    }

    // Yarim-shaffof unlit rang (kamera ustidan ko'rinsin)
    private static func material(covered: Bool) -> UnlitMaterial {
        let c: UIColor = covered
            ? UIColor(red: 0.20, green: 0.85, blue: 0.35, alpha: 0.45)   // yashil
            : UIColor(red: 0.95, green: 0.25, blue: 0.20, alpha: 0.45)   // qizil
        var m = UnlitMaterial()
        m.color = .init(tint: c)
        m.blending = .transparent(opacity: .init(floatLiteral: 1.0))
        return m
    }
}
