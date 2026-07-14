import Foundation
import simd

/// Mesh sirtidan zich nuqta buluti oladi (yuz maydoniga proporsional).
/// NSDK mesh QO'POL (17K vertex) — Hoppe uchun zich nuqta kerak; sirtni
/// sampling qilib olamiz (har nuqta: pozitsiya + yuz normali).
enum MeshSampler {

    static func sample(_ mesh: WeldedMesh, count: Int) -> [PointCloudBuilder.Point] {
        let V = mesh.positions
        let I = mesh.indices
        let fc = I.count / 3
        guard fc > 0 else { return [] }

        // Yuz maydonlari + kumulyativ (weighted sampling)
        var cum = [Float](repeating: 0, count: fc)
        var total: Float = 0
        var fnorm = [SIMD3<Float>](repeating: .zero, count: fc)
        for f in 0..<fc {
            let a = V[Int(I[f*3])], b = V[Int(I[f*3+1])], c = V[Int(I[f*3+2])]
            let cr = simd_cross(b - a, c - a)
            let area = simd_length(cr) * 0.5
            total += area
            cum[f] = total
            let l = simd_length(cr)
            fnorm[f] = l > 1e-9 ? cr / l : SIMD3<Float>(0, 1, 0)
        }
        guard total > 1e-6 else { return [] }

        var out = [PointCloudBuilder.Point]()
        out.reserveCapacity(count)
        var rng = SystemRandomNumberGenerator()
        let gray = SIMD3<UInt8>(140, 140, 140)
        for _ in 0..<count {
            // maydon bo'yicha yuz tanlash (binary search)
            let r = Float.random(in: 0..<total, using: &rng)
            var lo = 0, hi = fc - 1
            while lo < hi { let mid = (lo + hi) / 2; if cum[mid] < r { lo = mid + 1 } else { hi = mid } }
            let f = lo
            // random barycentric
            var u = Float.random(in: 0...1, using: &rng)
            var v = Float.random(in: 0...1, using: &rng)
            if u + v > 1 { u = 1 - u; v = 1 - v }
            let a = V[Int(I[f*3])], b = V[Int(I[f*3+1])], c = V[Int(I[f*3+2])]
            let p = a + u * (b - a) + v * (c - a)
            out.append(PointCloudBuilder.Point(position: p, normal: fnorm[f], color: gray))
        }
        return out
    }
}
