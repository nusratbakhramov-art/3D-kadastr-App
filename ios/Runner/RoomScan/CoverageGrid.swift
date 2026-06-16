import simd

/// Live 3D coverage map built during a scan. Each captured keyframe's LiDAR depth
/// points are voxelised; a voxel's view count rises every time it's seen. The scan
/// UI projects these voxels back onto the live camera view so the user sees, right
/// on the surfaces, which areas are well captured (green) vs only lightly seen
/// (orange) — and where nothing has been captured yet (no overlay).
///
/// Pure value logic (no ARKit) so it's unit-testable. Touched only on the main
/// actor (fed from the recorder's display-link tick).
final class CoverageGrid {
    let voxelSize: Float
    private(set) var voxels: [Int64: UInt16] = [:]

    init(voxelSize: Float = 0.05) {   // finer ⇒ denser, more mesh-like overlay
        self.voxelSize = voxelSize
    }

    var voxelCount: Int { voxels.count }

    func reset() { voxels.removeAll(keepingCapacity: true) }

    /// Drop one keyframe's depth samples into the voxel grid. `step` subsamples
    /// the depth map for speed.
    func ingest(
        depth: [Float], confidence: [UInt8]?, width: Int, height: Int,
        fx: Float, fy: Float, cx: Float, cy: Float,
        transform: simd_float4x4, step: Int = 8
    ) {
        guard width > 0, height > 0, depth.count >= width * height else { return }
        let inv = 1 / voxelSize

        var py = 0
        while py < height {
            var px = 0
            while px < width {
                defer { px += step }
                let z = depth[py * width + px]
                guard z.isFinite, z >= 0.3, z <= 5.0 else { continue }
                if let confidence, py * width + px < confidence.count,
                   confidence[py * width + px] < 2 { continue }   // high-confidence only

                let xCV = (Float(px) - cx) / fx * z
                let yCV = (Float(py) - cy) / fy * z
                let world = transform * SIMD4<Float>(xCV, -yCV, -z, 1)

                let key = Self.key(
                    Int32((world.x * inv).rounded(.down)),
                    Int32((world.y * inv).rounded(.down)),
                    Int32((world.z * inv).rounded(.down))
                )
                let c = voxels[key] ?? 0
                if c < .max { voxels[key] = c + 1 }
            }
            py += step
        }
    }

    /// Voxel centres (world space) + their view counts, for projection/rendering.
    func centers() -> [(center: SIMD3<Float>, count: UInt16)] {
        voxels.map { (Self.center($0.key, voxelSize), $0.value) }
    }

    // MARK: - Voxel key packing (21 bits / axis, biased to non-negative)

    static func key(_ x: Int32, _ y: Int32, _ z: Int32) -> Int64 {
        let bias: Int64 = 1 << 20
        let mask: Int64 = (1 << 21) - 1
        let bx = (Int64(x) + bias) & mask
        let by = (Int64(y) + bias) & mask
        let bz = (Int64(z) + bias) & mask
        return (bx << 42) | (by << 21) | bz
    }

    static func center(_ key: Int64, _ size: Float) -> SIMD3<Float> {
        let bias: Int64 = 1 << 20
        let mask: Int64 = (1 << 21) - 1
        let ix = Float(((key >> 42) & mask) - bias)
        let iy = Float(((key >> 21) & mask) - bias)
        let iz = Float((key & mask) - bias)
        return SIMD3((ix + 0.5) * size, (iy + 0.5) * size, (iz + 0.5) * size)
    }

    /// Decode a packed key back to integer voxel coordinates (for neighbour lookup).
    static func decode(_ key: Int64) -> SIMD3<Int32> {
        let bias: Int64 = 1 << 20
        let mask: Int64 = (1 << 21) - 1
        return SIMD3(
            Int32(((key >> 42) & mask) - bias),
            Int32(((key >> 21) & mask) - bias),
            Int32((key & mask) - bias)
        )
    }
}
