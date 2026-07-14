import ARKit
import SceneKit
import UIKit

/// ARKit LiDAR mesh (ARMeshGeometry)'dan jonli wireframe SCNGeometry quradi.
/// Skan paytida foydalanuvchi qaysi joyni qamraganini ko'rsatadi.
enum MeshWireframe {

    /// Yupqa, yarim shaffof wireframe (kamera ustida overlay).
    static func wireframe(from mesh: ARMeshGeometry) -> SCNGeometry {
        let geometry = makeGeometry(from: mesh)
        let material = SCNMaterial()
        material.fillMode = .lines
        material.diffuse.contents = UIColor(white: 1.0, alpha: 1.0)
        material.isDoubleSided = true
        material.lightingModel = .constant
        material.transparency = 0.6
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        return geometry
    }

    /// Yetuk (yaxshi skanerlangan) yuzalarni yashil rangga bo'yash — Scaniverse
    /// uslubidagi jonli qamrov: foydalanuvchi qaysi joy TAYYOR ekanini skan
    /// PAYTIDA ko'radi va teshiklarni o'zi to'ldiradi.
    static func coverageFill(from mesh: ARMeshGeometry) -> SCNGeometry {
        let geometry = makeGeometry(from: mesh)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.25, green: 0.85, blue: 0.45, alpha: 1.0)
        material.transparency = 0.22
        material.isDoubleSided = true
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        geometry.materials = [material]
        return geometry
    }

    /// Depth yozadigan, ammo ko'rinmas "to'ldiruvchi" — skan qilingan joyda
    /// orqadagi ko'k pardани to'sadi (Polycam uslubidagi effekt).
    static func occluder(from mesh: ARMeshGeometry) -> SCNGeometry {
        let geometry = makeGeometry(from: mesh)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.black
        material.colorBufferWriteMask = []       // ko'rinmas
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        material.lightingModel = .constant
        geometry.materials = [material]
        return geometry
    }

    /// Kamera atrofidagi ko'k "qamrov pardasi" (80% opacity). Depth o'qiydi —
    /// skan qilingan (occluder depth yozgan) joylarda to'siladi, faqat SKAN
    /// QILINMAGAN yo'nalishlarda ko'k bo'lib ko'rinadi (Polycam qamrov ko'rsatkichi).
    static func coverageSphere(radius: CGFloat = 8) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 24
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.15, green: 0.45, blue: 1.0, alpha: 1.0)
        material.transparency = 0.8                 // 80% opacity
        material.isDoubleSided = true               // ichkaridan ko'rinsin
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true        // skan qilingan joyda to'silsin
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.renderingOrder = 0                      // occluder (-10) dan keyin, wireframe (10) dan oldin
        node.name = "coverageSphere"
        return node
    }

    // MARK: - ARMeshGeometry -> SCNGeometry (buffer, nusxasiz)

    private static func makeGeometry(from mesh: ARMeshGeometry) -> SCNGeometry {
        let verts = mesh.vertices
        let vertexSource = SCNGeometrySource(
            buffer: verts.buffer,
            vertexFormat: verts.format,
            semantic: .vertex,
            vertexCount: verts.count,
            dataOffset: verts.offset,
            dataStride: verts.stride
        )
        let faces = mesh.faces
        let element = SCNGeometryElement(
            buffer: faces.buffer,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex
        )
        return SCNGeometry(sources: [vertexSource], elements: [element])
    }
}
