import SceneKit
import simd
import CoreGraphics

/// Builds the SceneKit node for an atlas-textured mesh. Shared by the in-app
/// viewer (`MeshSceneView`) and the headless `meshcheck` tool, so the tool can
/// render exactly what the app shows (e.g. to confirm texture V-orientation
/// without driving the Simulator).
enum AtlasSceneBuilder {
    static func makeNode(_ mesh: AtlasTexturedMesh) -> SCNNode {
        let positions = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let positionSource = SCNGeometrySource(vertices: positions)

        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let normalSource = SCNGeometrySource(normals: normals)

        // UVs and the atlas CGImage are both top-left origin, and SceneKit samples
        // a CGImage top-left here, so the coordinates map straight through. (A
        // global V-flip would scramble this per-triangle atlas, not just mirror it.)
        let uvPoints = mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        let uvSource = SCNGeometrySource(textureCoordinates: uvPoints)

        let indexData = mesh.indices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: mesh.indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [positionSource, normalSource, uvSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant          // show the baked texture as-is
        material.isDoubleSided = true
        if let image = AtlasIO.makeCGImage(rgba: mesh.atlas, width: mesh.atlasSize, height: mesh.atlasSize) {
            material.diffuse.contents = image
        }
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        geometry.firstMaterial = material

        return SCNNode(geometry: geometry)
    }
}
