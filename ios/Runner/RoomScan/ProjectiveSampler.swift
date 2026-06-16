import simd

/// Shared projective colour sampler used by both the per-vertex texturer and the
/// atlas texturer. For a world-space surface point it blends the colour from
/// every keyframe that genuinely sees it — weighted toward closer, more central
/// views, and skipping views where the point is occluded (depth-buffer test).
enum ProjectiveSampler {
    /// Blend the colour of `point` across the keyframes that see it, strongly
    /// favouring the sharpest and most head-on view so the result stays crisp.
    /// `normal` (the surface normal at `point`) enables the head-on weighting.
    /// `requireVisible` enforces the occlusion test; pass false as a fallback for
    /// points every view "occludes" (noisy/bumpy object surfaces — otherwise they
    /// fall back to grey). Returns nil if no keyframe sees it.
    /// `peak` sharpens the blend toward the single best view: each view's weight is
    /// raised to this power before averaging, so the most head-on / sharpest view
    /// dominates (peak=1 = plain average ⇒ multi-view ghosting/smear; peak≈6 ≈
    /// best-view ⇒ crisp like Polycam, while still cross-fading enough to hide
    /// exposure seams).
    static func sample(point: SIMD3<Float>, keyframes: [Keyframe], normal: SIMD3<Float>? = nil,
                       vFlip: Bool = false, requireVisible: Bool = true, peak: Float = 1) -> SIMD3<Float>? {
        var sumColor = SIMD3<Float>(repeating: 0)
        var sumWeight: Float = 0

        for kf in keyframes {
            guard let s = project(point: point, kf: kf, normal: normal, vFlip: vFlip, requireVisible: requireVisible) else { continue }
            let w = peak == 1 ? s.weight : powf(max(s.weight, 1e-12), peak)
            sumColor += s.color * w
            sumWeight += w
        }
        return sumWeight > 0 ? sumColor / sumWeight : nil
    }

    /// Project a point into one keyframe and return its sampled colour + a
    /// view-quality weight, or nil if not visible / occluded / out of frame.
    /// The weight rewards: head-on viewing angle (sharper, less foreshortened),
    /// image sharpness (avoids motion blur), proximity, and frame-centre.
    static func project(point: SIMD3<Float>, kf: Keyframe, normal: SIMD3<Float>? = nil,
                        vFlip: Bool = false, requireVisible: Bool = true) -> (color: SIMD3<Float>, weight: Float)? {
        let cam = kf.worldToCamera * SIMD4<Float>(point, 1)
        guard cam.z < -0.05 else { return nil }   // behind camera

        let zCV = -cam.z
        let xCV = cam.x
        let yCV = -cam.y

        if requireVisible && isOccluded(xCV: xCV, yCV: yCV, zCV: zCV, kf: kf) { return nil }

        let fx = kf.intrinsics.columns.0.x
        let fy = kf.intrinsics.columns.1.y
        let cx = kf.intrinsics.columns.2.x
        let cy = kf.intrinsics.columns.2.y

        let u = fx * (xCV / zCV) + cx
        var v = fy * (yCV / zCV) + cy
        if vFlip { v = Float(kf.height) - 1 - v }

        guard u >= 0, v >= 0, u < Float(kf.width), v < Float(kf.height) else { return nil }

        let xi = Int(u)
        let yi = Int(v)
        let idx = (yi * kf.width + xi) * 4
        guard idx + 2 < kf.rgba.count else { return nil }

        // Frame-edge falloff (grazing image borders are unreliable).
        let edgeU = min(u, Float(kf.width) - 1 - u) / Float(kf.width)
        let edgeV = min(v, Float(kf.height) - 1 - v) / Float(kf.height)
        let edgeWeight = min(1, 6 * min(edgeU, edgeV))

        // Head-on weighting: a view perpendicular to the surface resolves far
        // more detail than a grazing one. Cubed so the best view dominates.
        var facing: Float = 1
        if let normal {
            let viewDir = simd_normalize(kf.cameraPosition - point)
            let d = max(0.05, simd_dot(simd_normalize(normal), viewDir))
            facing = d * d * d
        }

        let weight = edgeWeight * kf.sharpness * facing / (zCV * zCV + 0.05)
        guard weight > 0 else { return nil }

        let color = SIMD3<Float>(
            Float(kf.rgba[idx]) / 255,
            Float(kf.rgba[idx + 1]) / 255,
            Float(kf.rgba[idx + 2]) / 255
        )
        return (color, weight)
    }

    /// Depth-buffer visibility test against the keyframe's registered depth map.
    static func isOccluded(xCV: Float, yCV: Float, zCV: Float, kf: Keyframe) -> Bool {
        guard let depth = kf.depth, kf.depthWidth > 0, kf.depthHeight > 0 else { return false }

        let fx = kf.depthIntrinsics.columns.0.x
        let fy = kf.depthIntrinsics.columns.1.y
        let cx = kf.depthIntrinsics.columns.2.x
        let cy = kf.depthIntrinsics.columns.2.y

        let du = Int(fx * (xCV / zCV) + cx)
        let dv = Int(fy * (yCV / zCV) + cy)
        guard du >= 0, dv >= 0, du < kf.depthWidth, dv < kf.depthHeight else { return false }

        let measured = depth[dv * kf.depthWidth + du]
        guard measured > 0.05 else { return false }

        // Tolerance must absorb the surface's OWN noise (soft furniture like a sofa
        // is bumpy/tufted and the depth map is low-res), or whole objects get
        // rejected as "occluded" and fall back to grey. Still rejects real
        // occluders (a closer surface more than this in front).
        let tolerance = 0.12 + 0.06 * zCV
        return zCV > measured + tolerance
    }
}
