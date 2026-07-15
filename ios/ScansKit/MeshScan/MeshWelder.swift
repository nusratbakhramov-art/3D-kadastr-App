import Foundation
import simd

/// Payvandlangan yaxlit mesh — chunk chegaralari yo'q qilingan.
struct WeldedMesh {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]
}

/// NSDK chunk'larini bitta yaxlit meshga payvandlaydi: chunk chegaralaridagi
/// takroriy vertexlar kvantlangan pozitsiya bo'yicha birlashtiriladi.
enum MeshWelder {

    /// 0.25 mm kvantlash paneli — TSDF grid vertexlari chegarada aynan
    /// bir xil koordinatada bo'ladi, shu panjara ularni ishonchli tutadi.
    private static let quantScale: Float = 4000

    static func weld(_ geometries: [Int64: ChunkGeometry]) -> WeldedMesh {
        var keyToIndex: [SIMD3<Int32>: UInt32] = [:]
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        var totalVerts = 0
        for (_, geo) in geometries { totalVerts += geo.positions.count }
        keyToIndex.reserveCapacity(totalVerts)
        positions.reserveCapacity(totalVerts)

        for (_, geo) in geometries.sorted(by: { $0.key < $1.key }) {
            // Har chunk'ning lokal→global indeks xaritasi
            var remap = [UInt32](repeating: 0, count: geo.positions.count)
            for (i, p) in geo.positions.enumerated() {
                let key = SIMD3<Int32>(
                    Int32((p.x * quantScale).rounded()),
                    Int32((p.y * quantScale).rounded()),
                    Int32((p.z * quantScale).rounded())
                )
                if let existing = keyToIndex[key] {
                    remap[i] = existing
                } else {
                    let newIndex = UInt32(positions.count)
                    keyToIndex[key] = newIndex
                    positions.append(p)
                    remap[i] = newIndex
                }
            }

            var t = 0
            while t + 2 < geo.indices.count {
                let a = remap[Int(geo.indices[t])]
                let b = remap[Int(geo.indices[t + 1])]
                let c = remap[Int(geo.indices[t + 2])]
                t += 3
                // Payvandlashdan keyin degeneratsiyalangan uchburchaklar chiqishi mumkin
                if a == b || b == c || a == c { continue }
                indices.append(a)
                indices.append(b)
                indices.append(c)
            }
        }

        // Normalarni yaxlit mesh bo'yicha qayta hisoblaymiz (maydon-og'irlikli)
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var t = 0
        while t + 2 < indices.count {
            let ia = Int(indices[t]), ib = Int(indices[t + 1]), ic = Int(indices[t + 2])
            t += 3
            let faceNormal = simd_cross(
                positions[ib] - positions[ia],
                positions[ic] - positions[ia]
            )
            normals[ia] += faceNormal
            normals[ib] += faceNormal
            normals[ic] += faceNormal
        }
        for i in 0..<normals.count {
            let len = simd_length(normals[i])
            normals[i] = len > 1e-8 ? normals[i] / len : SIMD3<Float>(0, 1, 0)
        }

        return WeldedMesh(positions: positions, normals: normals, indices: indices)
    }
}
