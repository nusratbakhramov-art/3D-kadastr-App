import Foundation
import RealityKit
import NSDK
import simd

/// Bitta mesh chunk'ning geometriyasi — render va OBJ eksport uchun umumiy format.
struct ChunkGeometry {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]?
    let indices: [UInt32]
}

extension MeshData {

    /// NSDK koordinatalarini RealityKit fazosiga o'girib (Y va Z teskari),
    /// geometriyani massivlarga ko'chiradi.
    func extractGeometry() -> ChunkGeometry? {
        let numVertices = verticesPtr.count / 3
        guard numVertices > 0 else { return nil }

        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(numVertices)
        for i in 0..<numVertices {
            let index = i * 3
            positions.append(SIMD3<Float>(
                verticesPtr[index],
                -verticesPtr[index + 1],
                -verticesPtr[index + 2]
            ))
        }

        var normals: [SIMD3<Float>]? = nil
        if let normalsPtr {
            var result = [SIMD3<Float>]()
            result.reserveCapacity(numVertices)
            for i in 0..<numVertices {
                let index = i * 3
                result.append(SIMD3<Float>(
                    normalsPtr[index],
                    -normalsPtr[index + 1],
                    -normalsPtr[index + 2]
                ))
            }
            normals = result
        }

        var indices = [UInt32](repeating: 0, count: indicesPtr.count)
        for i in 0..<indicesPtr.count {
            indices[i] = indicesPtr[i]
        }

        return ChunkGeometry(positions: positions, normals: normals, indices: indices)
    }
}

extension ChunkGeometry {

    func toMeshResource() -> MeshResource? {
        var descriptor = MeshDescriptor(name: "meshChunk")
        descriptor.positions = MeshBuffers.Positions(positions)
        if let normals {
            descriptor.normals = MeshBuffers.Normals(normals)
        }
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}

/// Chunk'lar to'plamini Wavefront OBJ matniga aylantiradi.
enum OBJExporter {

    static func makeOBJ(from geometries: [Int64: ChunkGeometry]) -> String {
        var lines: [String] = ["# ScansApp room mesh export", "# chunks: \(geometries.count)"]
        var vertexOffset: UInt32 = 1
        var normalOffset: UInt32 = 1

        for (id, geo) in geometries.sorted(by: { $0.key < $1.key }) {
            lines.append("o chunk_\(id)")
            for p in geo.positions {
                lines.append("v \(p.x) \(p.y) \(p.z)")
            }
            let hasNormals = geo.normals != nil
            if let normals = geo.normals {
                for n in normals {
                    lines.append("vn \(n.x) \(n.y) \(n.z)")
                }
            }
            var i = 0
            while i + 2 < geo.indices.count {
                let a = geo.indices[i] + vertexOffset
                let b = geo.indices[i + 1] + vertexOffset
                let c = geo.indices[i + 2] + vertexOffset
                if hasNormals {
                    let na = geo.indices[i] + normalOffset
                    let nb = geo.indices[i + 1] + normalOffset
                    let nc = geo.indices[i + 2] + normalOffset
                    lines.append("f \(a)//\(na) \(b)//\(nb) \(c)//\(nc)")
                } else {
                    lines.append("f \(a) \(b) \(c)")
                }
                i += 3
            }
            vertexOffset += UInt32(geo.positions.count)
            if let normals = geo.normals {
                normalOffset += UInt32(normals.count)
            }
        }
        return lines.joined(separator: "\n")
    }
}
