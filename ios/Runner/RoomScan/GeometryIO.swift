import Foundation
import simd

/// Compact binary read/write for meshes, used to reload a saved scan for the
/// texturing stage without re-scanning. Layout (little-endian):
///   uint32 vertexCount, uint32 indexCount, [uint32 flags]
///   vertexCount × SIMD3<Float> positions
///   vertexCount × SIMD3<Float> normals
///   indexCount  × UInt32 indices
///   (if flags & 1) vertexCount × SIMD3<Float> colors
enum GeometryIO {
    private static let colorFlag: UInt32 = 1

    static func write(_ mesh: ConsolidatedMesh, to url: URL) throws {
        try writeRaw(
            positions: mesh.positions, normals: mesh.normals,
            indices: mesh.indices, colors: nil, to: url
        )
    }

    static func writeTextured(_ mesh: TexturedMesh, to url: URL) throws {
        try writeRaw(
            positions: mesh.positions, normals: mesh.normals,
            indices: mesh.indices, colors: mesh.colors, to: url
        )
    }

    private static func writeRaw(
        positions: [SIMD3<Float>], normals: [SIMD3<Float>],
        indices: [UInt32], colors: [SIMD3<Float>]?, to url: URL
    ) throws {
        var data = Data()
        var vertexCount = UInt32(positions.count)
        var indexCount = UInt32(indices.count)
        var flags: UInt32 = colors != nil ? colorFlag : 0
        withUnsafeBytes(of: &vertexCount) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &indexCount) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &flags) { data.append(contentsOf: $0) }
        positions.withUnsafeBytes { data.append(contentsOf: $0) }
        normals.withUnsafeBytes { data.append(contentsOf: $0) }
        indices.withUnsafeBytes { data.append(contentsOf: $0) }
        if let colors { colors.withUnsafeBytes { data.append(contentsOf: $0) } }
        try data.write(to: url)
    }

    static func read(_ url: URL) throws -> TexturedMesh {
        let data = try Data(contentsOf: url)
        let vec3Stride = MemoryLayout<SIMD3<Float>>.stride

        return data.withUnsafeBytes { raw -> TexturedMesh in
            var offset = 0
            func nextU32() -> Int {
                let v = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                offset += 4
                return Int(v)
            }
            let vertexCount = nextU32()
            let indexCount = nextU32()
            let flags = UInt32(nextU32())

            func readVec3(_ count: Int) -> [SIMD3<Float>] {
                var out = [SIMD3<Float>](repeating: .zero, count: count)
                for i in 0..<count {
                    out[i] = raw.loadUnaligned(fromByteOffset: offset + i * vec3Stride, as: SIMD3<Float>.self)
                }
                offset += count * vec3Stride
                return out
            }

            let positions = readVec3(vertexCount)
            let normals = readVec3(vertexCount)

            var indices = [UInt32](repeating: 0, count: indexCount)
            for i in 0..<indexCount {
                indices[i] = raw.loadUnaligned(fromByteOffset: offset + i * 4, as: UInt32.self)
            }
            offset += indexCount * 4

            let colors: [SIMD3<Float>]
            if flags & colorFlag != 0 {
                colors = readVec3(vertexCount)
            } else {
                colors = Array(repeating: SIMD3<Float>(0.7, 0.7, 0.72), count: vertexCount)
            }

            return TexturedMesh(positions: positions, normals: normals, indices: indices, colors: colors)
        }
    }
}
