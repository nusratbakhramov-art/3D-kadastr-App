import SceneKit

/// M2/M3 — Object Capture teksturali mesh'ini RoomPlan strukturasiga tekislaydi.
///
/// MVP yondashuvi: bounding-box asosidagi o'xshashlik (similarity) transform.
/// Ikkala model ham bir ARSession koordinatasida bo'lgani uchun asosiy tekislash
/// footprint markazi + pol balandligi + gorizontal masshtab bo'yicha bajariladi.
/// (TZ §11 R2 zaxira rejasi.)
enum FusionService {

    /// Teksturali model tugunini xona chegaralariga moslab konteynerga joylaydi.
    /// `footprint` berilsa (robust, outlier'lardan tozalangan) — undan foydalanadi;
    /// aks holda mesh bounding-box'idan hisoblaydi.
    static func alignedContainer(for modelNode: SCNNode,
                                 footprint: MeshFootprint?,
                                 to bounds: RoomBounds) -> SCNNode {
        let fp: MeshFootprint
        if let footprint {
            fp = footprint
        } else {
            let (minB, maxB) = modelNode.boundingBox
            fp = MeshFootprint(
                centerX: (minB.x + maxB.x) / 2,
                centerZ: (minB.z + maxB.z) / 2,
                width: max(maxB.x - minB.x, 0.001),
                depth: max(maxB.z - minB.z, 0.001),
                minY: minB.y
            )
        }

        // Footprint bo'yicha masshtab (X va Z o'rtacha).
        let scaleX = bounds.width / fp.width
        let scaleZ = bounds.depth / fp.depth
        let scale = Swift.min(Swift.max((scaleX + scaleZ) / 2, 0.01), 100)

        // Modelni: footprint markazi origin'da, pastki qismi y=0 da bo'ladigan qilib siljitamiz.
        modelNode.position = SCNVector3(-fp.centerX, -fp.minY, -fp.centerZ)

        let scaleNode = SCNNode()
        scaleNode.scale = SCNVector3(scale, scale, scale)
        scaleNode.addChildNode(modelNode)

        let container = SCNNode()
        container.name = "texturedModel"
        container.addChildNode(scaleNode)
        // Xona footprint markazi + pol balandligiga joylaymiz.
        container.position = SCNVector3(bounds.centerX, bounds.floorY, bounds.centerZ)
        return container
    }
}
