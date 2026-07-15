import Foundation
import simd

/// Nuqta buluti normal'larini PCA (Principal Component Analysis) bilan qayta
/// hisoblaydi — depth-gradient normal'lari implicit reconstruction (IMLS/Poisson)
/// uchun juda shovqinli. Har nuqta uchun k-qo'shni ustidan kovariatsiya
/// matritsasining eng kichik xos-vektori = normal. Orientatsiya mavjud
/// (kameraga qaragan) normal bo'yicha izchillashtiriladi.
enum NormalEstimator {

    /// k-qo'shni PCA normal. `points` normal'lari joyida yangilanadi.
    static func refine(_ points: inout [PointCloudBuilder.Point], neighborRadius: Float = 0.03) {
        let count = points.count
        guard count > 20 else { return }

        // Spatial hash (qidiruv radiusi = katak o'lchami)
        let cell = neighborRadius
        let inv = 1 / cell
        var grid: [SIMD3<Int32>: [Int32]] = [:]
        grid.reserveCapacity(count)
        for (i, p) in points.enumerated() {
            let key = SIMD3<Int32>(
                Int32((p.position.x * inv).rounded(.down)),
                Int32((p.position.y * inv).rounded(.down)),
                Int32((p.position.z * inv).rounded(.down))
            )
            grid[key, default: []].append(Int32(i))
        }

        let r2 = neighborRadius * neighborRadius
        let newNormals = UnsafeMutablePointer<SIMD3<Float>>.allocate(capacity: count)
        defer { newNormals.deallocate() }
        let pts = points

        DispatchQueue.concurrentPerform(iterations: count) { i in
            let p = pts[i].position
            let base = SIMD3<Int32>(
                Int32((p.x * inv).rounded(.down)),
                Int32((p.y * inv).rounded(.down)),
                Int32((p.z * inv).rounded(.down))
            )
            // Qo'shnilarni yig'amiz (3x3x3 katak)
            var mean = SIMD3<Float>.zero
            var neigh: [SIMD3<Float>] = []
            neigh.reserveCapacity(32)
            for dz in -1...1 {
                for dy in -1...1 {
                    for dx in -1...1 {
                        let key = SIMD3<Int32>(base.x + Int32(dx), base.y + Int32(dy), base.z + Int32(dz))
                        guard let bucket = grid[key] else { continue }
                        for idx in bucket {
                            let q = pts[Int(idx)].position
                            if simd_length_squared(q - p) <= r2 {
                                neigh.append(q); mean += q
                            }
                        }
                    }
                }
            }
            guard neigh.count >= 4 else { newNormals[i] = pts[i].normal; return }
            mean /= Float(neigh.count)

            // Kovariatsiya matritsasi (3x3, simmetrik)
            var c00: Float = 0, c01: Float = 0, c02: Float = 0
            var c11: Float = 0, c12: Float = 0, c22: Float = 0
            for q in neigh {
                let d = q - mean
                c00 += d.x * d.x; c01 += d.x * d.y; c02 += d.x * d.z
                c11 += d.y * d.y; c12 += d.y * d.z; c22 += d.z * d.z
            }
            let cov = simd_float3x3(
                SIMD3<Float>(c00, c01, c02),
                SIMD3<Float>(c01, c11, c12),
                SIMD3<Float>(c02, c12, c22)
            )
            var normal = smallestEigenvector(cov)
            // Orientatsiyani mavjud normal bilan izchillashtiramiz
            if simd_dot(normal, pts[i].normal) < 0 { normal = -normal }
            newNormals[i] = normal
        }

        for i in 0..<count { points[i].normal = newNormals[i] }
    }

    /// Simmetrik 3x3 kovariatsiyaning eng kichik xos-qiymatiga mos xos-vektor
    /// (= sirt normali). Teskari-iteratsiya (inverse power iteration) bilan.
    private static func smallestEigenvector(_ m: simd_float3x3) -> SIMD3<Float> {
        // Eng kichik xos-qiymatga yaqinlashish uchun (m - shift*I)^-1 bo'yicha
        // power iteration. Regularizatsiya bilan.
        let trace = m[0][0] + m[1][1] + m[2][2]
        let reg = max(trace, 1e-6) * 1e-4
        let a = simd_float3x3(
            SIMD3<Float>(m[0][0] + reg, m[0][1], m[0][2]),
            SIMD3<Float>(m[1][0], m[1][1] + reg, m[1][2]),
            SIMD3<Float>(m[2][0], m[2][1], m[2][2] + reg)
        )
        let inv = a.inverse
        var v = SIMD3<Float>(0.577, 0.577, 0.577)
        for _ in 0..<12 {
            v = inv * v
            let len = simd_length(v)
            if len < 1e-12 { return SIMD3<Float>(0, 1, 0) }
            v /= len
        }
        return v
    }
}
