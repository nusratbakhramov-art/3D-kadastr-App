import Foundation
import simd

/// All mesh anchors merged into a single world-space mesh. Plain value type so
/// it can cross actor / thread boundaries into the texturing pass.
struct ConsolidatedMesh: Sendable {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]

    var vertexCount: Int { positions.count }
    var triangleCount: Int { indices.count / 3 }
}

/// Mesh plus a baked per-vertex colour (0…1 RGB).
struct TexturedMesh: Sendable {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]
    var colors: [SIMD3<Float>]
}

/// A captured camera view used as a texture source: an RGBA frame plus the
/// intrinsics (scaled to match) and the world→camera transform. Optionally
/// carries the registered LiDAR depth map so the texturer can reject vertices
/// that are occluded in this view (depth-buffer visibility test).
struct Keyframe: Sendable {
    let width: Int
    let height: Int
    let rgba: [UInt8]              // width * height * 4, RGBA8
    let intrinsics: simd_float3x3 // scaled to `width`/`height`
    let worldToCamera: simd_float4x4

    // Optional depth for occlusion testing (same camera pose, lower resolution).
    let depth: [Float]?           // depthWidth * depthHeight, metres
    let depthWidth: Int
    let depthHeight: Int
    let depthIntrinsics: simd_float3x3 // scaled to depthWidth/depthHeight

    // View-quality hints used to pick the sharpest, most head-on source per texel.
    let cameraPosition: SIMD3<Float>   // world-space camera position
    let sharpness: Float               // image gradient energy (higher = sharper)

    init(
        width: Int, height: Int, rgba: [UInt8],
        intrinsics: simd_float3x3, worldToCamera: simd_float4x4,
        depth: [Float]? = nil, depthWidth: Int = 0, depthHeight: Int = 0,
        depthIntrinsics: simd_float3x3 = matrix_identity_float3x3,
        cameraPosition: SIMD3<Float> = .zero, sharpness: Float = 1
    ) {
        self.width = width
        self.height = height
        self.rgba = rgba
        self.intrinsics = intrinsics
        self.worldToCamera = worldToCamera
        self.depth = depth
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
        self.depthIntrinsics = depthIntrinsics
        self.cameraPosition = cameraPosition
        self.sharpness = sharpness
    }
}

/// A mesh with a baked texture atlas: per-vertex UVs plus one RGBA image. Gives
/// sharp, density-independent detail (unlike per-vertex colour). Vertices are
/// split per triangle, so `positions`/`normals`/`uvs` are 3 × triangleCount.
struct AtlasTexturedMesh: Sendable {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var uvs: [SIMD2<Float>]        // [0,1], top-left origin
    var indices: [UInt32]
    var atlas: [UInt8]            // RGBA8, atlasSize × atlasSize
    var atlasSize: Int

    var vertexCount: Int { positions.count }
    var triangleCount: Int { indices.count / 3 }
}

/// Exported file URLs for a textured result.
struct ExportBundle: Equatable {
    var usdz: URL
    var ply: URL
    var obj: URL
}
