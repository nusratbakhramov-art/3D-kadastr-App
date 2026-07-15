import SceneKit
import UIKit
import RoomPlan
import simd

/// Parametrik SceneKit tugunlarini (devor, pol, shift, eshik, deraza, obyekt) quruvchi.
enum RoomSceneBuilder {

    // MARK: - Materiallar

    static func material(_ color: UIColor, transparency: CGFloat = 1, doubleSided: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.transparency = transparency
        m.isDoubleSided = doubleSided
        m.lightingModel = .physicallyBased
        return m
    }

    private static let wallColor = UIColor(white: 0.82, alpha: 1)
    private static let floorColor = UIColor(white: 0.35, alpha: 1)
    private static let ceilingColor = UIColor(white: 0.55, alpha: 1)
    private static let doorColor = UIColor(red: 0.55, green: 0.36, blue: 0.22, alpha: 1)
    private static let windowColor = UIColor(red: 0.35, green: 0.72, blue: 0.85, alpha: 1)
    static let objectColor = UIColor(red: 0.20, green: 0.78, blue: 0.90, alpha: 1)
    static let selectedColor = UIColor(red: 1.0, green: 0.78, blue: 0.20, alpha: 1)

    // MARK: - Umumiy quti tuguni

    static func boxNode(dimensions: simd_float3,
                        transform: simd_float4x4,
                        material: SCNMaterial,
                        minThickness: Float = 0.02,
                        name: String) -> SCNNode {
        let w = CGFloat(max(dimensions.x, minThickness))
        let h = CGFloat(max(dimensions.y, minThickness))
        let l = CGFloat(max(dimensions.z, minThickness))
        let box = SCNBox(width: w, height: h, length: l, chamferRadius: 0)
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.simdTransform = transform
        node.name = name
        return node
    }

    // MARK: - Struktura (devor/eshik/deraza/pol/shift)

    static func structureRoot(room: CapturedRoom, bounds: RoomBounds) -> SCNNode {
        let root = SCNNode()
        root.name = "structure"

        for (i, wall) in room.walls.enumerated() {
            root.addChildNode(boxNode(dimensions: wall.dimensions, transform: wall.transform,
                                      material: material(wallColor, transparency: 0.55),
                                      name: "wall_\(i)"))
        }
        for (i, door) in room.doors.enumerated() {
            root.addChildNode(boxNode(dimensions: door.dimensions, transform: door.transform,
                                      material: material(doorColor, transparency: 0.85),
                                      name: "door_\(i)"))
        }
        for (i, window) in room.windows.enumerated() {
            root.addChildNode(boxNode(dimensions: window.dimensions, transform: window.transform,
                                      material: material(windowColor, transparency: 0.5),
                                      name: "window_\(i)"))
        }

        // Pol va shift — footprint bo'yicha qurilib joylashtiriladi.
        let floorDims = simd_float3(bounds.width, 0.02, bounds.depth)
        var floorTransform = matrix_identity_float4x4
        floorTransform.columns.3 = simd_float4(bounds.centerX, bounds.floorY, bounds.centerZ, 1)
        root.addChildNode(boxNode(dimensions: floorDims, transform: floorTransform,
                                  material: material(floorColor), name: "floor"))

        var ceilingTransform = matrix_identity_float4x4
        ceilingTransform.columns.3 = simd_float4(bounds.centerX, bounds.ceilingY, bounds.centerZ, 1)
        let ceiling = boxNode(dimensions: floorDims, transform: ceilingTransform,
                              material: material(ceilingColor, transparency: 0.4), name: "ceiling")
        root.addChildNode(ceiling)

        return root
    }

    // MARK: - Obyekt tuguni

    static func objectNode(id: UUID, dimensions: simd_float3, transform: simd_float4x4) -> SCNNode {
        let node = boxNode(dimensions: dimensions, transform: transform,
                           material: material(objectColor, transparency: 0.65),
                           name: id.uuidString)
        return node
    }

    // MARK: - O'lchov yorliqlari

    static func textNode(_ text: String, at position: simd_float3, color: UIColor = .white) -> SCNNode {
        let scnText = SCNText(string: text, extrusionDepth: 0)
        scnText.font = UIFont.systemFont(ofSize: 8, weight: .semibold)
        scnText.flatness = 0.2
        scnText.firstMaterial?.diffuse.contents = color
        scnText.firstMaterial?.isDoubleSided = true
        scnText.firstMaterial?.lightingModel = .constant

        let textNode = SCNNode(geometry: scnText)
        // SCNText juda katta — kichraytiramiz va markazlashtiramiz.
        let (minB, maxB) = textNode.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2,
                                                   (minB.y + maxB.y) / 2, 0)
        let scale: Float = 0.004
        textNode.scale = SCNVector3(scale, scale, scale)

        let container = SCNNode()
        container.addChildNode(textNode)
        container.simdPosition = position
        // Har doim kameraga qaragan holda (billboard).
        container.constraints = [SCNBillboardConstraint()]

        // Orqa fon plastinkasi o'qishni osonlashtiradi.
        let plane = SCNPlane(width: CGFloat(maxB.x - minB.x) * CGFloat(scale) + 0.06,
                             height: CGFloat(maxB.y - minB.y) * CGFloat(scale) + 0.03)
        plane.cornerRadius = 0.02
        plane.firstMaterial?.diffuse.contents = UIColor.black.withAlphaComponent(0.6)
        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.lightingModel = .constant
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(0, 0, -0.001)
        container.insertChildNode(planeNode, at: 0)

        return container
    }
}
