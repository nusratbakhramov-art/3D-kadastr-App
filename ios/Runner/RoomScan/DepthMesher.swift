import Foundation
import simd

/// Builds a dense mesh from the saved LiDAR depth frames. RoomPlan's session does
/// not expose `ARMeshAnchor`s, so this is how we recover dense geometry: each
/// depth map is an organized grid — we unproject its samples to world space and
/// triangulate neighbours, skipping depth discontinuities. Runs entirely off the
/// persisted scan (no re-scan needed).
///
/// Per-frame patches overlap heavily, so after concatenating every frame we
/// fuse them on a voxel grid (`VoxelWelder`) and drop tiny floating islands
/// (`MeshCleanup`). The weld collapses duplicated/z-fighting layers into one
/// surface; cleanup removes the speckle the LiDAR leaves at depth edges.
enum DepthMesher {
    static let step = 3                 // subsample stride over the depth grid (denser than 4)
    static let maxFrames = 80           // cap to bound memory before welding
    static let minDepth: Float = 0.2
    static let maxDepth: Float = 5.0
    static let minConfidence: UInt8 = 2 // ARConfidenceLevel: 0 low, 1 medium, 2 high

    // Depth-adaptive discontinuity threshold. Two grid neighbours sit `step`
    // pixels apart, which projects to ~`step * z / focal` metres of real spacing
    // at depth `z`. A continuous surface keeps edges near that spacing (allowing a
    // little for diagonals and grazing angles); a real discontinuity jumps far
    // beyond it. So we cap an edge at `edgeSlack * step * z / focal + edgeFloor`
    // instead of a single flat distance, so near and far surfaces both mesh.
    static let edgeSlack: Float = 4.0   // multiples of nominal grid spacing allowed
    static let edgeFloor: Float = 0.04  // metres; floor so near surfaces still mesh
    // Hard cap so far noise can't bridge a discontinuity. Also the legacy flat
    // discontinuity threshold the offline tests assert against — keep this name.
    static let maxEdge: Float = 0.15    // metres; hard ceiling on any meshed edge

    static func buildMesh(scanID: String) -> ConsolidatedMesh {
        let store = ScanStore.shared
        guard let index = store.loadFrames(scanID) else {
            return ConsolidatedMesh(positions: [], normals: [], indices: [])
        }
        return buildMesh(folder: store.folder(for: scanID), frames: index)
    }

    /// Folder-based builder shared by the app and the headless `meshcheck` tool.
    static func buildMesh(folder: URL, frames index: FramesIndex) -> ConsolidatedMesh {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let frames = index.frames.filter { $0.depth != nil }.prefix(maxFrames)
        for meta in frames {
            guard let dw = meta.depthWidth, let dh = meta.depthHeight,
                  let depthName = meta.depth,
                  let depthData = try? Data(contentsOf: folder.appendingPathComponent("depth/\(depthName)"))
            else { continue }

            let depth: [Float] = depthData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            guard depth.count >= dw * dh else { continue }

            let confidence: [UInt8]? = meta.confidence.flatMap { name in
                (try? Data(contentsOf: folder.appendingPathComponent("depth/\(name)"))).map { Array($0) }
            }

            // Depth intrinsics = RGB intrinsics scaled to depth resolution.
            let kRGB = simd_float3x3(flat: meta.intrinsics)
            let s = Float(dw) / Float(meta.imageWidth)
            let (p, n, idx) = meshFromDepthFrame(
                depth: depth, conf: confidence, width: dw, height: dh,
                fx: kRGB.columns.0.x * s, fy: kRGB.columns.1.y * s,
                cx: kRGB.columns.2.x * s, cy: kRGB.columns.2.y * s,
                transform: simd_float4x4(flat: meta.transform), step: step
            )

            let base = UInt32(positions.count)
            positions.append(contentsOf: p)
            normals.append(contentsOf: n)
            indices.append(contentsOf: idx.map { base + $0 })
        }

        let merged = ConsolidatedMesh(positions: positions, normals: normals, indices: indices)

        // Fuse overlapping per-frame layers into a single surface, then strip the
        // small disconnected speckle the depth edges leave behind.
        let welded = VoxelWelder.weld(merged, cell: 0.012)
        return MeshCleanup.removeSmallComponents(welded, minComponentTriangles: 80)
    }

    /// Mesh one organized depth frame. Returns world-space positions, normalized
    /// vertex normals, and 0-based indices. Pure — unit-testable without disk.
    static func meshFromDepthFrame(
        depth: [Float], conf: [UInt8]?, width: Int, height: Int,
        fx: Float, fy: Float, cx: Float, cy: Float,
        transform: simd_float4x4, step: Int
    ) -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) {
        let cols = width / step
        let rows = height / step
        guard cols > 1, rows > 1 else { return ([], [], []) }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var grid = [Int](repeating: -1, count: cols * rows)
        // Camera-space depth (z) of each placed vertex, used for the depth-adaptive
        // discontinuity test. Parallel to `positions`.
        var depthAt: [Float] = []

        for gy in 0..<rows {
            for gx in 0..<cols {
                let px = min(width - 1, gx * step)
                let py = min(height - 1, gy * step)
                let z = depth[py * width + px]
                guard z.isFinite, z >= minDepth, z <= maxDepth else { continue }
                if let conf, py * width + px < conf.count, conf[py * width + px] < minConfidence { continue }

                let xCV = (Float(px) - cx) / fx * z
                let yCV = (Float(py) - cy) / fy * z
                // CV (x right, y down, +z fwd) → ARKit camera (x right, y up, -z fwd)
                let world = transform * SIMD4<Float>(xCV, -yCV, -z, 1)
                grid[gy * cols + gx] = positions.count
                positions.append(world.xyz)
                normals.append(.zero)
                depthAt.append(z)
            }
        }

        // Nominal world-space spacing between two grid neighbours per metre of
        // depth: `step` pixels divided by the (smaller, i.e. coarser) focal length.
        // Multiplying by a vertex's depth gives the expected continuous-surface
        // edge length there. `focal` guards against degenerate intrinsics.
        let focal = max(min(fx, fy), 1e-3)
        let spacingPerDepth = Float(step) / focal

        // The capture camera saw every sample, so orient each triangle's winding
        // so its normal faces the camera. That makes all surface normals point
        // consistently "inward" (toward where you scanned from) — which lets the
        // viewer cull the near wall (back-face) and reveal the interior.
        let camPos = transform.translation
        func addTri(_ a: Int, _ b: Int, _ c: Int) {
            let pa = positions[a], pb = positions[b], pc = positions[c]
            // Depth-adaptive max edge: scale with the nearest vertex's depth so
            // near surfaces use a tight threshold and far surfaces a looser one,
            // clamped to a sane [floor, ceil] band.
            let nearZ = min(depthAt[a], depthAt[b], depthAt[c])
            let edgeLimit = min(maxEdge, max(edgeFloor, edgeSlack * spacingPerDepth * nearZ))
            if simd_distance(pa, pb) > edgeLimit || simd_distance(pa, pc) > edgeLimit || simd_distance(pb, pc) > edgeLimit {
                return
            }
            var n = simd_cross(pb - pa, pc - pa)
            let centroid = (pa + pb + pc) / 3
            if simd_dot(n, camPos - centroid) >= 0 {
                indices.append(UInt32(a)); indices.append(UInt32(b)); indices.append(UInt32(c))
            } else {
                indices.append(UInt32(a)); indices.append(UInt32(c)); indices.append(UInt32(b))
                n = -n
            }
            normals[a] += n; normals[b] += n; normals[c] += n
        }

        for gy in 0..<(rows - 1) {
            for gx in 0..<(cols - 1) {
                let i00 = grid[gy * cols + gx]
                let i10 = grid[gy * cols + gx + 1]
                let i01 = grid[(gy + 1) * cols + gx]
                let i11 = grid[(gy + 1) * cols + gx + 1]
                if i00 >= 0, i01 >= 0, i10 >= 0 { addTri(i00, i01, i10) }
                if i10 >= 0, i01 >= 0, i11 >= 0 { addTri(i10, i01, i11) }
            }
        }

        for i in 0..<normals.count {
            normals[i] = simd_length(normals[i]) > 1e-5 ? simd_normalize(normals[i]) : SIMD3(0, 1, 0)
        }
        return (positions, normals, indices)
    }
}
