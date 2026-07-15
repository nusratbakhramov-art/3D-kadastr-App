import ARKit
import SceneKit
import UIKit
import simd

/// LiDAR scene-reconstruction mesh'i (world koordinatada, tekis massivlar).
struct LiDARMeshData {
    var positions: [Float]   // x,y,z,...
    var normals: [Float]     // x,y,z,...
    var indices: [UInt32]

    var vertexCount: Int { positions.count / 3 }
    var isEmpty: Bool { positions.isEmpty || indices.isEmpty }
}

enum LiDARMesh {

    // MARK: - Snapshot (ARMeshAnchor -> world mesh)

    /// Kadrdagi barcha ARMeshAnchor'larni bitta world-space meshga yig'adi.
    static func snapshot(from frame: ARFrame) -> LiDARMeshData {
        var positions: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []

        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let vertexCount = geometry.vertices.count
            let baseIndex = UInt32(positions.count / 3)

            let vBuf = geometry.vertices.buffer.contents()
            let vOffset = geometry.vertices.offset
            let vStride = geometry.vertices.stride
            let nBuf = geometry.normals.buffer.contents()
            let nOffset = geometry.normals.offset
            let nStride = geometry.normals.stride

            let t = anchor.transform
            let rot = simd_float3x3(
                SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z)
            )

            for i in 0..<vertexCount {
                let vp = vBuf + vOffset + i * vStride
                let lx = vp.load(fromByteOffset: 0, as: Float.self)
                let ly = vp.load(fromByteOffset: 4, as: Float.self)
                let lz = vp.load(fromByteOffset: 8, as: Float.self)
                let world = t * SIMD4<Float>(lx, ly, lz, 1)
                positions.append(world.x); positions.append(world.y); positions.append(world.z)

                let np = nBuf + nOffset + i * nStride
                let nx = np.load(fromByteOffset: 0, as: Float.self)
                let ny = np.load(fromByteOffset: 4, as: Float.self)
                let nz = np.load(fromByteOffset: 8, as: Float.self)
                let wn = simd_normalize(rot * SIMD3(nx, ny, nz))
                normals.append(wn.x); normals.append(wn.y); normals.append(wn.z)
            }

            let faces = geometry.faces
            let totalIndices = faces.count * faces.indexCountPerPrimitive
            let fBuf = faces.buffer.contents()
            let bytesPerIndex = faces.bytesPerIndex
            for j in 0..<totalIndices {
                let localIndex: UInt32
                if bytesPerIndex == 4 {
                    localIndex = fBuf.load(fromByteOffset: j * 4, as: UInt32.self)
                } else {
                    localIndex = UInt32(fBuf.load(fromByteOffset: j * 2, as: UInt16.self))
                }
                indices.append(baseIndex + localIndex)
            }
        }

        return LiDARMeshData(positions: positions, normals: normals, indices: indices)
    }

    // MARK: - SceneKit geometriya

    static func makeGeometry(_ mesh: LiDARMeshData, colors: [Float]? = nil) -> SCNGeometry {
        let posData = mesh.positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let normData = mesh.normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let idxData = mesh.indices.withUnsafeBufferPointer { Data(buffer: $0) }

        let posSource = SCNGeometrySource(
            data: posData, semantic: .vertex, vectorCount: mesh.vertexCount,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        let normSource = SCNGeometrySource(
            data: normData, semantic: .normal, vectorCount: mesh.vertexCount,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 12
        )
        var sources = [posSource, normSource]

        if let colors, colors.count == mesh.vertexCount * 3 {
            let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let colorSource = SCNGeometrySource(
                data: colorData, semantic: .color, vectorCount: mesh.vertexCount,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            )
            sources.append(colorSource)
        }

        let element = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: mesh.indices.count / 3, bytesPerIndex: 4
        )

        let geometry = SCNGeometry(sources: sources, elements: [element])
        let material = SCNMaterial()
        // Single-sided: qarab turgan devor kesiladi (dollhouse effekti).
        material.isDoubleSided = false
        if colors == nil {
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(white: 0.75, alpha: 1)
        } else {
            // Rang kadrlar yorug'ligini o'zida saqlaydi — qo'shimcha yoritish kerak emas.
            material.lightingModel = .constant
        }
        geometry.materials = [material]
        return geometry
    }

    // MARK: - Diskda saqlash (mesh.bin)

    static func write(_ mesh: LiDARMeshData, to url: URL) throws {
        var data = Data()
        var vc = UInt32(mesh.vertexCount)
        var ic = UInt32(mesh.indices.count)
        withUnsafeBytes(of: &vc) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &ic) { data.append(contentsOf: $0) }
        mesh.positions.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        mesh.normals.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        mesh.indices.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        try data.write(to: url)
    }

    // MARK: - Ranglar (2-bosqich: per-vertex tekstura)

    static func writeColors(_ colors: [Float], to url: URL) throws {
        let data = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: url)
    }

    static func readColors(from url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    static func read(from url: URL) throws -> LiDARMeshData {
        let data = try Data(contentsOf: url)
        var offset = 0
        func readU32() -> Int {
            let v = data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4
            return Int(v)
        }
        func readFloats(_ count: Int) -> [Float] {
            let bytes = count * 4
            let slice = data.subdata(in: offset..<offset + bytes)
            offset += bytes
            return slice.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        func readU32s(_ count: Int) -> [UInt32] {
            let bytes = count * 4
            let slice = data.subdata(in: offset..<offset + bytes)
            offset += bytes
            return slice.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        }
        let vc = readU32()
        let ic = readU32()
        let positions = readFloats(vc * 3)
        let normals = readFloats(vc * 3)
        let indices = readU32s(ic)
        return LiDARMeshData(positions: positions, normals: normals, indices: indices)
    }
}
