import Foundation
import simd

/// Yagona mesh'ni tekstura oldidan tozalaydi: yengil Laplacian silliqlash +
/// decimation (Scaniverse `MeshSimplifier` bosqichiga mos). Har qanday
/// geometriya manbaiga (NSDK TSDF weld yoki implicit mesh) qo'llanadi.
enum MeshPostProcess {

    static func cleanup(_ mesh: WeldedMesh, targetTriangles: Int) -> WeldedMesh {
        var positions = mesh.positions
        var indices = mesh.indices
        guard positions.count > 10, indices.count >= 3 else { return mesh }

        // 1) Yengil Laplacian silliqlash (TSDF marching-cubes zinapoyasini yumshatadi,
        // detalni yo'qotmaydi)
        laplacianSmooth(positions: &positions, indices: indices, iterations: 2, factor: 0.3)

        // 2) Decimation (Scaniverse "Simplification") — target uchburchak soniga
        if indices.count / 3 > targetTriangles {
            var flat = [Float](repeating: 0, count: positions.count * 3)
            for (i, p) in positions.enumerated() {
                flat[i * 3] = p.x; flat[i * 3 + 1] = p.y; flat[i * 3 + 2] = p.z
            }
            if let simplified = MeshOptBridge.simplifyIndices(
                indices, indexCount: UInt(indices.count),
                positions: flat, vertexCount: UInt(positions.count),
                targetTriangles: UInt(targetTriangles), targetError: 0.02
            ), simplified.count >= 12 {
                var newIndices = [UInt32](repeating: 0, count: simplified.count / 4)
                simplified.withUnsafeBytes { raw in
                    let ptr = raw.bindMemory(to: UInt32.self)
                    for i in 0..<newIndices.count { newIndices[i] = ptr[i] }
                }
                indices = newIndices
            }
        }

        let normals = computeNormals(positions: positions, indices: indices)
        return WeldedMesh(positions: positions, normals: normals, indices: indices)
    }

    // MARK: - Hole filling (chegara-halqalarini yopish)

    private static func fillHoles(
        positions: inout [SIMD3<Float>], indices: inout [UInt32],
        maxLoopVertices: Int, maxPerimeter: Float
    ) {
        // Yo'naltirilgan qirralar to'plami + har qirraning uchinchi vertexi (uchburchagi)
        var directed = Set<UInt64>()
        var edgeThird: [UInt64: UInt32] = [:]
        directed.reserveCapacity(indices.count)
        func key(_ a: UInt32, _ b: UInt32) -> UInt64 { (UInt64(a) << 32) | UInt64(b) }

        var t = 0
        while t + 2 < indices.count {
            let a = indices[t], b = indices[t + 1], c = indices[t + 2]
            t += 3
            directed.insert(key(a, b)); edgeThird[key(a, b)] = c
            directed.insert(key(b, c)); edgeThird[key(b, c)] = a
            directed.insert(key(c, a)); edgeThird[key(c, a)] = b
        }

        // Chegara yo'naltirilgan qirra: teskarisi yo'q. next[a] = b.
        var boundaryNext: [UInt32: UInt32] = [:]
        for e in directed {
            let a = UInt32(e >> 32), b = UInt32(e & 0xFFFFFFFF)
            if directed.contains(key(b, a)) == false {
                boundaryNext[a] = b
            }
        }
        guard !boundaryNext.isEmpty else { return }

        var visited = Set<UInt32>()
        var newVertices: [SIMD3<Float>] = []
        var newTriangles: [UInt32] = []
        let baseCount = UInt32(positions.count)

        for startV in boundaryNext.keys {
            if visited.contains(startV) { continue }
            // Halqani yig'amiz
            var loop: [UInt32] = []
            var cur = startV
            var ok = true
            while true {
                if visited.contains(cur) {
                    // startga qaytdimi?
                    ok = (cur == startV)
                    break
                }
                visited.insert(cur)
                loop.append(cur)
                guard let nxt = boundaryNext[cur] else { ok = false; break }
                cur = nxt
                if loop.count > maxLoopVertices + 2 { ok = false; break }
            }
            guard ok, loop.count >= 3, loop.count <= maxLoopVertices else { continue }

            // Perimetr
            var perim: Float = 0
            for i in 0..<loop.count {
                let p0 = positions[Int(loop[i])]
                let p1 = positions[Int(loop[(i + 1) % loop.count])]
                perim += simd_length(p1 - p0)
            }
            guard perim <= maxPerimeter else { continue }

            // Markaz vertexi
            var centroid = SIMD3<Float>.zero
            for v in loop { centroid += positions[Int(v)] }
            centroid /= Float(loop.count)
            let centroidIndex = baseCount + UInt32(newVertices.count)
            newVertices.append(centroid)

            // Fan uchburchaklari — chegara yo'nalishiga mos winding.
            // To'g'ri orientatsiya: qo'shni yuza normaliga solishtirib flip qilamiz.
            var refNormal = SIMD3<Float>(0, 1, 0)
            if let third = edgeThird[key(loop[0], loop[1])] {
                let n = simd_cross(
                    positions[Int(loop[1])] - positions[Int(loop[0])],
                    positions[Int(third)] - positions[Int(loop[0])]
                )
                if simd_length(n) > 1e-9 { refNormal = simd_normalize(n) }
            }
            // Fan normalини sinaymiz (bitta uchburchak orqali)
            let fanN = simd_cross(
                positions[Int(loop[1])] - positions[Int(loop[0])],
                centroid - positions[Int(loop[0])]
            )
            let flip = simd_dot(fanN, refNormal) < 0

            for i in 0..<loop.count {
                let v0 = loop[i]
                let v1 = loop[(i + 1) % loop.count]
                if flip {
                    newTriangles.append(v1); newTriangles.append(v0); newTriangles.append(centroidIndex)
                } else {
                    newTriangles.append(v0); newTriangles.append(v1); newTriangles.append(centroidIndex)
                }
            }
        }

        if !newVertices.isEmpty {
            positions.append(contentsOf: newVertices)
            indices.append(contentsOf: newTriangles)
        }
    }

    // MARK: - Helpers

    private static func computeNormals(
        positions: [SIMD3<Float>], indices: [UInt32]
    ) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var t = 0
        while t + 2 < indices.count {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            t += 3
            let fn = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            normals[a] += fn; normals[b] += fn; normals[c] += fn
        }
        for i in 0..<normals.count {
            let len = simd_length(normals[i])
            normals[i] = len > 1e-8 ? normals[i] / len : SIMD3<Float>(0, 1, 0)
        }
        return normals
    }

    private static func laplacianSmooth(
        positions: inout [SIMD3<Float>], indices: [UInt32],
        iterations: Int, factor: Float
    ) {
        var neighbors = [Set<UInt32>](repeating: [], count: positions.count)
        var t = 0
        while t + 2 < indices.count {
            let a = indices[t], b = indices[t + 1], c = indices[t + 2]
            t += 3
            neighbors[Int(a)].insert(b); neighbors[Int(a)].insert(c)
            neighbors[Int(b)].insert(a); neighbors[Int(b)].insert(c)
            neighbors[Int(c)].insert(a); neighbors[Int(c)].insert(b)
        }
        for _ in 0..<iterations {
            var next = positions
            for i in 0..<positions.count {
                let nb = neighbors[i]
                guard !nb.isEmpty else { continue }
                var avg = SIMD3<Float>.zero
                for n in nb { avg += positions[Int(n)] }
                avg /= Float(nb.count)
                next[i] = positions[i] + (avg - positions[i]) * factor
            }
            positions = next
        }
    }
}
