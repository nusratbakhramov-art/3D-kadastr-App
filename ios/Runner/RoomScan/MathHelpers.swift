import simd

extension SIMD4 where Scalar == Float {
    /// First three components as a `SIMD3<Float>`.
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

extension simd_float4x4 {
    /// Upper-left 3x3 (rotation part). Valid for the rigid transforms ARKit
    /// hands us — no non-uniform scale, so it doubles as the normal matrix.
    var rotation: simd_float3x3 {
        simd_float3x3(columns.0.xyz, columns.1.xyz, columns.2.xyz)
    }

    /// World-space translation (the 4th column).
    var translation: SIMD3<Float> { columns.3.xyz }

    /// Column-major flatten for JSON persistence.
    var flat: [Float] {
        [columns.0.x, columns.0.y, columns.0.z, columns.0.w,
         columns.1.x, columns.1.y, columns.1.z, columns.1.w,
         columns.2.x, columns.2.y, columns.2.z, columns.2.w,
         columns.3.x, columns.3.y, columns.3.z, columns.3.w]
    }

    init(flat f: [Float]) {
        self.init(
            SIMD4<Float>(f[0], f[1], f[2], f[3]),
            SIMD4<Float>(f[4], f[5], f[6], f[7]),
            SIMD4<Float>(f[8], f[9], f[10], f[11]),
            SIMD4<Float>(f[12], f[13], f[14], f[15])
        )
    }
}

extension simd_float3x3 {
    /// Column-major flatten for JSON persistence.
    var flat: [Float] {
        [columns.0.x, columns.0.y, columns.0.z,
         columns.1.x, columns.1.y, columns.1.z,
         columns.2.x, columns.2.y, columns.2.z]
    }

    init(flat f: [Float]) {
        self.init(
            SIMD3<Float>(f[0], f[1], f[2]),
            SIMD3<Float>(f[3], f[4], f[5]),
            SIMD3<Float>(f[6], f[7], f[8])
        )
    }
}
