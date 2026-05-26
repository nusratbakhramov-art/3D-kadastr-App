// MeshHoleFiller — ARKit mesh anchor'lar orasidagi gap'larni to'ldirish.
//
// Algoritm:
//   1. Vertex dedupe — anchor'lar boundary'da bir xil pozitsiyadagi vertex'lar
//      birlashtiriladi (anchor'lar bir-biriga ulanadi)
//   2. Boundary edge detection — faqat bitta triangle bilan birlashgan edge'lar
//   3. Boundary edge'larni closed loop'larga group'lash
//   4. Har loop uchun ear-clipping triangulation
//   5. Yangi triangle'lar mesh'ga qo'shiladi
//
// ARKit anchor mesh'idagi vertex'lar dedupe qilinmagan — har anchor o'zining
// boundary'sini saqlaydi. Birlashtirgandan keyin haqiqiy hole'lar qoladi.

import Foundation
import simd

struct MeshHoleFillResult {
    var vertices: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)]
}

enum MeshHoleFiller {
    static func fillHoles(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        triangles: [(v0: UInt32, v1: UInt32, v2: UInt32)],
        weldEpsilon: Float = 0.01,         // 1 cm — anchor boundary uchun yetarli
        maxHoleEdgeCount: Int = 200,       // bundan kattaroq hole'lar skip
    ) -> MeshHoleFillResult {
        // 1. Vertex dedupe (weld). Position 1cm aniqlikgacha yaxlitlanadi.
        let scale: Float = 1.0 / weldEpsilon
        var weldMap: [SIMD3<Int32>: UInt32] = [:]
        weldMap.reserveCapacity(vertices.count)
        var remap = [UInt32](repeating: 0, count: vertices.count)
        var newVerts: [SIMD3<Float>] = []
        var normalAcc: [SIMD3<Float>] = []
        var normalCnt: [Int] = []
        newVerts.reserveCapacity(vertices.count)
        normalAcc.reserveCapacity(vertices.count)
        normalCnt.reserveCapacity(vertices.count)

        for (oldIdx, v) in vertices.enumerated() {
            let key = SIMD3<Int32>(
                Int32((v.x * scale).rounded()),
                Int32((v.y * scale).rounded()),
                Int32((v.z * scale).rounded()),
            )
            if let existing = weldMap[key] {
                remap[oldIdx] = existing
                normalAcc[Int(existing)] += normals[oldIdx]
                normalCnt[Int(existing)] += 1
            } else {
                let newIdx = UInt32(newVerts.count)
                weldMap[key] = newIdx
                remap[oldIdx] = newIdx
                newVerts.append(v)
                normalAcc.append(normals[oldIdx])
                normalCnt.append(1)
            }
        }

        // Average normals
        var newNormals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: newVerts.count)
        for i in 0..<newVerts.count {
            let n = normalAcc[i] / Float(max(normalCnt[i], 1))
            let len = simd_length(n)
            newNormals[i] = len > 1e-6 ? n / len : SIMD3<Float>(0, 1, 0)
        }

        // Remap triangles; drop degenerate
        var newTris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        newTris.reserveCapacity(triangles.count)
        for t in triangles {
            let i0 = remap[Int(t.v0)]
            let i1 = remap[Int(t.v1)]
            let i2 = remap[Int(t.v2)]
            if i0 != i1 && i1 != i2 && i0 != i2 {
                newTris.append((v0: i0, v1: i1, v2: i2))
            }
        }

        // 2. Build edge → triangle count map. Boundary = count 1.
        struct EdgeKey: Hashable { let a: UInt32; let b: UInt32 }
        @inline(__always) func makeKey(_ x: UInt32, _ y: UInt32) -> EdgeKey {
            return x < y ? EdgeKey(a: x, b: y) : EdgeKey(a: y, b: x)
        }
        var edgeCount: [EdgeKey: Int] = [:]
        edgeCount.reserveCapacity(newTris.count * 3)
        // Also track directed edge ownership: for boundary loop tracing we need
        // a directed edge map from each boundary vertex.
        for t in newTris {
            let e0 = makeKey(t.v0, t.v1)
            let e1 = makeKey(t.v1, t.v2)
            let e2 = makeKey(t.v2, t.v0)
            edgeCount[e0, default: 0] += 1
            edgeCount[e1, default: 0] += 1
            edgeCount[e2, default: 0] += 1
        }

        // For each boundary edge, store directed orientation (from triangle).
        // Directed boundary edges form closed loops.
        var directedEdges: [UInt32: UInt32] = [:]   // from → to (one per boundary vertex)
        for t in newTris {
            let pairs: [(UInt32, UInt32)] = [
                (t.v0, t.v1), (t.v1, t.v2), (t.v2, t.v0),
            ]
            for (a, b) in pairs {
                if edgeCount[makeKey(a, b)] == 1 {
                    directedEdges[a] = b
                }
            }
        }

        // 3. Trace closed loops by following directed edges.
        var visited = Set<UInt32>()
        var holeLoops: [[UInt32]] = []
        for startVertex in directedEdges.keys {
            if visited.contains(startVertex) { continue }
            var loop: [UInt32] = []
            var current = startVertex
            var stepCount = 0
            let maxSteps = maxHoleEdgeCount + 1
            while !visited.contains(current) && stepCount < maxSteps {
                visited.insert(current)
                loop.append(current)
                guard let next = directedEdges[current] else { break }
                current = next
                stepCount += 1
            }
            // Check if it's a valid closed loop
            if loop.count >= 3 && current == startVertex && loop.count <= maxHoleEdgeCount {
                holeLoops.append(loop)
            }
        }

        NSLog("KADASTR hole fill: \(holeLoops.count) closed loops, edges: \(directedEdges.count)")

        // 4. For each hole loop, triangulate using fan from centroid (simple,
        //    works for star-shaped holes). For complex holes, ear-clipping
        //    would be better, but fan is faster and sufficient for room scan
        //    anchor gaps which are mostly convex.
        var addedTris: [(v0: UInt32, v1: UInt32, v2: UInt32)] = []
        var addedCount = 0
        for loop in holeLoops {
            guard loop.count >= 3 else { continue }

            // Compute centroid
            var c = SIMD3<Float>(0, 0, 0)
            var nSum = SIMD3<Float>(0, 0, 0)
            for vi in loop {
                c += newVerts[Int(vi)]
                nSum += newNormals[Int(vi)]
            }
            c /= Float(loop.count)
            let nLen = simd_length(nSum)
            let n = nLen > 1e-6 ? nSum / nLen : SIMD3<Float>(0, 1, 0)

            // Add centroid as new vertex
            let centroidIdx = UInt32(newVerts.count)
            newVerts.append(c)
            newNormals.append(n)

            // Fan triangulation. Winding: boundary directed edges go a→b,
            // surface is on the LEFT of the edge. To fill hole on the same
            // side, triangle (centroid, a, b) — check winding via normal.
            for i in 0..<loop.count {
                let a = loop[i]
                let b = loop[(i + 1) % loop.count]
                addedTris.append((v0: centroidIdx, v1: a, v2: b))
                addedCount += 1
            }
        }

        newTris.append(contentsOf: addedTris)
        NSLog("KADASTR hole fill: added \(addedCount) tri")

        return MeshHoleFillResult(vertices: newVerts, normals: newNormals, triangles: newTris)
    }
}
