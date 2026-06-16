import ARKit
import simd

/// Merges `ARMeshAnchor`s into one world-space mesh. Reads the shared Metal
/// buffers ARKit owns — call on the main actor while the anchors are stable.
enum MeshConsolidator {
    static func consolidate(_ anchors: [ARMeshAnchor]) -> ConsolidatedMesh {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let normalMatrix = transform.rotation
            let baseIndex = UInt32(positions.count)

            let verts = geometry.vertices
            let norms = geometry.normals
            let vBuffer = verts.buffer.contents()
            let nBuffer = norms.buffer.contents()

            for i in 0..<verts.count {
                let vPtr = vBuffer
                    .advanced(by: verts.offset + verts.stride * i)
                    .assumingMemoryBound(to: (Float, Float, Float).self)
                let v = vPtr.pointee
                let world = transform * SIMD4<Float>(v.0, v.1, v.2, 1)
                positions.append(world.xyz)

                let nPtr = nBuffer
                    .advanced(by: norms.offset + norms.stride * i)
                    .assumingMemoryBound(to: (Float, Float, Float).self)
                let n = nPtr.pointee
                normals.append(simd_normalize(normalMatrix * SIMD3<Float>(n.0, n.1, n.2)))
            }

            let faces = geometry.faces
            let totalIndices = faces.count * faces.indexCountPerPrimitive
            let fBuffer = faces.buffer.contents()
            let bytesPerIndex = faces.bytesPerIndex

            for k in 0..<totalIndices {
                let raw = fBuffer.advanced(by: k * bytesPerIndex)
                let value: UInt32
                if bytesPerIndex == 2 {
                    value = UInt32(raw.assumingMemoryBound(to: UInt16.self).pointee)
                } else {
                    value = raw.assumingMemoryBound(to: UInt32.self).pointee
                }
                indices.append(baseIndex + value)
            }
        }

        return ConsolidatedMesh(positions: positions, normals: normals, indices: indices)
    }
}

/// Approximate room floor area (m²) from the classified scene mesh — the Polycam
/// way (no RoomPlan). Sums the world-space area of every face ARKit tagged
/// `.floor`; if classification is unavailable, falls back to near-horizontal faces.
enum ClassifiedArea {
    static func floorArea(_ anchors: [ARMeshAnchor]) -> Float {
        var total: Float = 0
        for anchor in anchors {
            let g = anchor.geometry
            let verts = g.vertices
            let faces = g.faces
            let vBuf = verts.buffer.contents()
            let fBuf = faces.buffer.contents()
            let bpi = faces.bytesPerIndex
            let xform = anchor.transform
            let clsBuf = g.classification?.buffer.contents()

            func world(_ i: Int) -> SIMD3<Float> {
                let p = vBuf.advanced(by: verts.offset + verts.stride * i)
                    .assumingMemoryBound(to: (Float, Float, Float).self).pointee
                let w = xform * SIMD4<Float>(p.0, p.1, p.2, 1)
                return SIMD3(w.x, w.y, w.z)
            }
            func index(_ k: Int) -> Int {
                let raw = fBuf.advanced(by: k * bpi)
                return bpi == 2 ? Int(raw.assumingMemoryBound(to: UInt16.self).pointee)
                                : Int(raw.assumingMemoryBound(to: UInt32.self).pointee)
            }

            for f in 0..<faces.count {
                if let clsBuf {
                    let c = clsBuf.advanced(by: f).assumingMemoryBound(to: UInt8.self).pointee
                    guard c == ARMeshClassification.floor.rawValue else { continue }
                }
                let a = world(index(f * 3)), b = world(index(f * 3 + 1)), c = world(index(f * 3 + 2))
                let n = simd_cross(b - a, c - a)
                let len = simd_length(n)
                if clsBuf == nil {
                    // No classification: keep only near-horizontal faces (floor-ish).
                    guard len > 1e-7, abs(n.y) / len > 0.85 else { continue }
                }
                total += 0.5 * len
            }
        }
        return total
    }
}
