import ARKit
import SceneKit
import UIKit

/// Live LiDAR-mesh visualization, Polycam-style. Renders each `ARMeshAnchor` as a
/// SceneKit child node IN the AR scene (so ARKit positions it perfectly — no manual
/// 2D projection, unlike the old voxel overlay). Captured surfaces show a white
/// triangle wireframe; surfaces not yet captured show a translucent blue fill.
enum ARMeshViz {
    /// Zero-copy `SCNGeometry` straight from ARKit's mesh buffers.
    static func geometry(from mesh: ARMeshGeometry) -> SCNGeometry {
        let vertices = mesh.vertices
        let vertexSource = SCNGeometrySource(
            buffer: vertices.buffer,
            vertexFormat: vertices.format,
            semantic: .vertex,
            vertexCount: vertices.count,
            dataOffset: vertices.offset,
            dataStride: vertices.stride
        )

        let faces = mesh.faces
        let indexData = Data(
            bytesNoCopy: faces.buffer.contents(),
            count: faces.count * faces.indexCountPerPrimitive * faces.bytesPerIndex,
            deallocator: .none
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex
        )

        return SCNGeometry(sources: [vertexSource], elements: [element])
    }

    /// White triangle wireframe — a captured surface (see-through, over the camera).
    static func capturedMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.fillMode = .lines
        m.diffuse.contents = UIColor(white: 1.0, alpha: 0.9)
        m.transparency = 0.9
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        return m
    }

    /// Translucent blue fill — a surface the LiDAR sees but hasn't captured yet.
    static func uncapturedMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.fillMode = .fill
        m.diffuse.contents = UIColor(red: 0.20, green: 0.50, blue: 1.0, alpha: 1.0)
        m.transparency = 0.30
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        return m
    }

    /// Rebuild an anchor node's visualization child to match its capture state.
    static func apply(to node: SCNNode, mesh: ARMeshGeometry, captured: Bool) {
        node.childNodes.forEach { $0.removeFromParentNode() }
        let geom = geometry(from: mesh)
        geom.materials = [captured ? capturedMaterial() : uncapturedMaterial()]
        let child = SCNNode(geometry: geom)
        child.name = captured ? "wire" : "fill"
        node.addChildNode(child)
    }
}
