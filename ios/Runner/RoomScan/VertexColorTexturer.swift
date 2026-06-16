import simd

/// Per-vertex texturing: sample each mesh vertex's colour by blending the
/// keyframes that see it (via `ProjectiveSampler`). Fast, used for the live
/// preview and as a fallback. For sharp, density-independent detail use
/// `AtlasTexturer` instead.
enum VertexColorTexturer {
    static let fallbackColor = SIMD3<Float>(0.62, 0.62, 0.66)

    static func bake(mesh: ConsolidatedMesh, keyframes: [Keyframe], vFlip: Bool = false) -> TexturedMesh {
        var colors = [SIMD3<Float>](repeating: fallbackColor, count: mesh.positions.count)

        if !keyframes.isEmpty {
            for i in 0..<mesh.positions.count {
                let normal = i < mesh.normals.count ? mesh.normals[i] : nil
                if let color = ProjectiveSampler.sample(point: mesh.positions[i], keyframes: keyframes, normal: normal, vFlip: vFlip) {
                    colors[i] = color
                }
            }
        }

        return TexturedMesh(
            positions: mesh.positions,
            normals: mesh.normals,
            indices: mesh.indices,
            colors: colors
        )
    }
}
