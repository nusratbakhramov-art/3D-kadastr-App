import SceneKit
import simd

/// Teksturali mesh'ning "robust" footprint'i (chetdagi outlier'larni rad etib).
struct MeshFootprint {
    let centerX: Float
    let centerZ: Float
    let width: Float
    let depth: Float
    let minY: Float
}

/// Object Capture mesh'ini xona chegarasiga moslash va eshik ortidagi
/// (tashqi) geometriyani kesib tashlash yordamchilari.
enum MeshClipping {

    /// Modeldan robust footprint hisoblaydi — eshik ortidagi "quyruq"larni
    /// 3–97% persentil oralig'i bilan rad etadi (masshtabni buzmaslik uchun).
    static func footprint(of node: SCNNode) -> MeshFootprint? {
        let verts = vertices(of: node)
        guard verts.count > 32 else { return nil }

        let xs = verts.map { $0.x }.sorted()
        let ys = verts.map { $0.y }.sorted()
        let zs = verts.map { $0.z }.sorted()

        func pct(_ a: [Float], _ p: Float) -> Float {
            let idx = Int(Float(a.count - 1) * p)
            return a[min(max(idx, 0), a.count - 1)]
        }

        let minX = pct(xs, 0.03), maxX = pct(xs, 0.97)
        let minZ = pct(zs, 0.03), maxZ = pct(zs, 0.97)
        let minY = pct(ys, 0.01)

        return MeshFootprint(
            centerX: (minX + maxX) / 2,
            centerZ: (minZ + maxZ) / 2,
            width: max(maxX - minX, 0.001),
            depth: max(maxZ - minZ, 0.001),
            minY: minY
        )
    }

    /// Mesh cho'qqilarini (vertex) o'qiydi (flatten qilib, float32 x/y/z sifatida).
    static func vertices(of node: SCNNode) -> [simd_float3] {
        let flat = node.flattenedClone()
        guard let geometry = flat.geometry,
              let source = geometry.sources(for: .vertex).first,
              source.bytesPerComponent == 4,
              source.componentsPerVector >= 3
        else { return [] }

        let count = source.vectorCount
        let stride = source.dataStride
        let offset = source.dataOffset
        var out = [simd_float3]()
        out.reserveCapacity(count)

        source.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            for i in 0..<count {
                let p = base + offset + i * stride
                let x = p.load(fromByteOffset: 0, as: Float.self)
                let y = p.load(fromByteOffset: 4, as: Float.self)
                let z = p.load(fromByteOffset: 8, as: Float.self)
                out.append(simd_float3(x, y, z))
            }
        }
        return out
    }

    /// World-space xona chegarasidan tashqaridagi fragmentlarni "discard" qiladi.
    /// Shu bilan eshik ortidagi tekstura ko'rinmaydi.
    static func applyClip(to node: SCNNode,
                          worldBounds b: RoomBounds,
                          marginXZ: Float = 0.20,
                          marginTop: Float = 0.25) {
        func f(_ v: Float) -> String { String(format: "%.4f", v) }

        let minX = f(b.minX - marginXZ), maxX = f(b.maxX + marginXZ)
        let minZ = f(b.minZ - marginXZ), maxZ = f(b.maxZ + marginXZ)
        let minY = f(b.floorY - 0.05), maxY = f(b.ceilingY + marginTop)

        let shader = """
        #pragma body
        float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        if (wp.x < \(minX) || wp.x > \(maxX) ||
            wp.z < \(minZ) || wp.z > \(maxZ) ||
            wp.y < \(minY) || wp.y > \(maxY)) {
            discard_fragment();
        }
        """

        node.enumerateHierarchy { n, _ in
            guard let materials = n.geometry?.materials else { return }
            for material in materials {
                var mods = material.shaderModifiers ?? [:]
                mods[.fragment] = shader
                material.shaderModifiers = mods
            }
        }
    }
}
