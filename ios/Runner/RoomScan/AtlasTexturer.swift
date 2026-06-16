import Foundation
import simd

/// Photorealistic texturing: bakes a texture **atlas** instead of per-vertex
/// colour, so detail is independent of mesh density (sharp walls, readable text,
/// crisp object surfaces).
///
/// Pipeline:
///  1. Decimate the dense depth mesh (vertex-cluster weld at a coarser cell) so
///     each triangle is large enough to own a usable atlas region.
///  2. Pack one square cell per triangle into a grid atlas; map the triangle to
///     a right-triangle inside its cell (per-triangle UVs ⇒ vertices are split).
///  3. For each triangle, prefilter the keyframes that actually see it (cheap
///     centroid visibility test), then for every atlas texel inside the triangle
///     recover its 3D point by barycentric interpolation, project it into those
///     keyframes and blend the colour (`ProjectiveSampler`).
///  4. Dilate the atlas a few texels past triangle edges so bilinear filtering
///     doesn't bleed the background in at seams.
enum AtlasTexturer {
    struct Options {
        var decimateCell: Float = 0.08   // metres; coarser ⇒ bigger atlas cells ⇒ sharper
        var maxAtlasSize = 6144          // ~144 MB atlas; sharper walls on big rooms
        var targetCellTexels = 32        // desired texels per triangle side
        var minCellTexels = 6
        var gutter = 1                   // texels kept clear at each cell edge
        var dilateIterations = 4
        // Occlude using a depth buffer rendered from the mesh ITSELF (not the raw
        // LiDAR map). The raw map is misaligned with the decimated mesh, so it
        // rejected objects' own surfaces (grey dotted sofa); a self-rendered buffer
        // matches exactly. Disable only for the no-occlusion diagnostic.
        var meshOcclusion = true
        // Per-texel view-blend sharpness. 1 = plain average (ghosted/smeared);
        // higher peaks toward the single best view (crisp, Polycam-like).
        var viewPeak: Float = 6
        // Min triangles for a connected component to survive. The RoomShell drop
        // disconnects furniture from the floor/wall (its contact triangles are
        // replaced by the clean shell), so objects become small floating pieces —
        // a high threshold deletes them ("sofa merged into the wall"). Keep it low.
        var minObjectTriangles = 8
    }

    static func bake(mesh: ConsolidatedMesh, keyframes inputKeyframes: [Keyframe], options: Options = Options()) -> AtlasTexturedMesh {
        // 1. Decimate so triangles are big enough to texture well.
        let coarse = MeshCleanup.removeSmallComponents(
            VoxelWelder.weld(mesh, cell: options.decimateCell),
            minComponentTriangles: options.minObjectTriangles
        )

        // Replace each keyframe's occlusion depth with one rendered from the
        // decimated mesh, so the occlusion test sees exactly the surface we bake:
        // an object's own face is the front surface (never self-rejected), while a
        // wall/floor hidden behind an object stays correctly occluded. This kills
        // BOTH the grey "dotted object" (self-occlusion) and the flat colour
        // "smear" (no-occlusion bleed) at once.
        let keyframes = options.meshOcclusion ? inputKeyframes.map { meshDepthKeyframe(coarse, $0) } : inputKeyframes
        let triCount = coarse.indices.count / 3
        guard triCount > 0 else {
            return AtlasTexturedMesh(positions: [], normals: [], uvs: [], indices: [], atlas: [], atlasSize: 1)
        }

        // 2. Atlas layout: AREA-PROPORTIONAL cells. Each triangle's cell edge ∝
        //    √(world area), so texel density (texels/m²) is ~uniform across the
        //    whole room — big walls get the resolution they need and tiny object
        //    triangles don't hog the atlas. (A fixed cell-per-triangle starves big
        //    walls ⇒ blurry on large rooms.) Cells are shelf-packed into a square.
        let gutI = options.gutter
        let g = Float(gutI)
        var area = [Float](repeating: 0, count: triCount)
        var totalArea: Float = 0
        for t in 0..<triCount {
            let q0 = coarse.positions[Int(coarse.indices[t * 3])]
            let q1 = coarse.positions[Int(coarse.indices[t * 3 + 1])]
            let q2 = coarse.positions[Int(coarse.indices[t * 3 + 2])]
            let a = 0.5 * simd_length(simd_cross(q1 - q0, q2 - q0))
            area[t] = a; totalArea += a
        }
        let minEdge = max(options.minCellTexels, 2 * gutI + 2)
        let maxEdge = max(minEdge, options.maxAtlasSize / 8)
        let densityCap: Float = 1400        // texels/metre ceiling (~0.7 mm/texel)
        let fill: Float = 0.80              // shelf-pack efficiency
        var tpm = totalArea > 1e-5
            ? min(densityCap, Float(options.maxAtlasSize) * (fill / totalArea).squareRoot())
            : Float(options.targetCellTexels)
        var edge = [Int](repeating: minEdge, count: triCount)
        func computeEdges(_ tpm: Float) {
            for t in 0..<triCount {
                let e = Int((area[t].squareRoot() * tpm).rounded()) + 2 * gutI
                edge[t] = min(maxEdge, max(minEdge, e))
            }
        }
        func pack(width W: Int) -> (orig: [(Int, Int, Int)], height: Int) {
            let order = (0..<triCount).sorted { edge[$0] > edge[$1] }
            var orig = [(Int, Int, Int)](repeating: (0, 0, 0), count: triCount)
            var rx = 0, ry = 0, rh = 0, H = 0
            for t in order {
                let e = edge[t]
                if rx + e > W { ry += rh; rx = 0; rh = 0 }
                orig[t] = (rx, ry, e); rx += e; rh = max(rh, e); H = max(H, ry + rh)
            }
            return (orig, H)
        }
        computeEdges(tpm)
        var totCell: Float = 0; for t in 0..<triCount { totCell += Float(edge[t] * edge[t]) }
        var side = min(options.maxAtlasSize,
                       max(max(minEdge, edge.max() ?? minEdge), Int((totCell / fill).squareRoot()) + 1))
        var (cellOrigin, packH) = pack(width: side)
        var atlasSize = max(side, packH)
        if atlasSize > options.maxAtlasSize {       // overflowed → shrink density, re-pack
            tpm *= Float(options.maxAtlasSize) / Float(atlasSize)
            computeEdges(tpm)
            side = options.maxAtlasSize
            (cellOrigin, packH) = pack(width: side)
            atlasSize = min(options.maxAtlasSize, max(side, packH))
        }

        var positions = [SIMD3<Float>](); positions.reserveCapacity(triCount * 3)
        var normals = [SIMD3<Float>](); normals.reserveCapacity(triCount * 3)
        var uvs = [SIMD2<Float>](); uvs.reserveCapacity(triCount * 3)
        var indices = [UInt32](); indices.reserveCapacity(triCount * 3)

        var atlas = [UInt8](repeating: 0, count: atlasSize * atlasSize * 4)
        var covered = [Bool](repeating: false, count: atlasSize * atlasSize)

        let invAtlas = 1 / Float(atlasSize)

        for t in 0..<triCount {
            let i0 = Int(coarse.indices[t * 3]),
                i1 = Int(coarse.indices[t * 3 + 1]),
                i2 = Int(coarse.indices[t * 3 + 2])
            let p0 = coarse.positions[i0], p1 = coarse.positions[i1], p2 = coarse.positions[i2]
            let faceN = safeNormalize(simd_cross(p1 - p0, p2 - p0))

            // Per-triangle packed cell (area-proportional) + right-triangle UVs.
            let (cx, cy, edgeT) = cellOrigin[t]
            let cxF = Float(cx), cyF = Float(cy)
            let cellF = Float(edgeT)
            let uv0 = SIMD2<Float>(cxF + g, cyF + g)
            let uv1 = SIMD2<Float>(cxF + cellF - g, cyF + g)
            let uv2 = SIMD2<Float>(cxF + g, cyF + cellF - g)

            let base = UInt32(positions.count)
            positions.append(p0); positions.append(p1); positions.append(p2)
            normals.append(faceN); normals.append(faceN); normals.append(faceN)
            uvs.append(uv0 * invAtlas); uvs.append(uv1 * invAtlas); uvs.append(uv2 * invAtlas)
            indices.append(base); indices.append(base + 1); indices.append(base + 2)

            // 3a. Prefilter keyframes that frame this triangle (ignore occlusion
            //     here — a bumpy object centroid can read as occluded in every
            //     view, which would wrongly leave the whole triangle untextured;
            //     per-texel occlusion + fallback below sorts out the detail).
            let centroid = (p0 + p1 + p2) / 3
            let candidates = keyframes.filter {
                ProjectiveSampler.project(point: centroid, kf: $0, requireVisible: false) != nil
            }
            if candidates.isEmpty { continue }

            // 3b. Rasterize the cell; bake each covered texel.
            let denom = (uv1.y - uv2.y) * (uv0.x - uv2.x) + (uv2.x - uv1.x) * (uv0.y - uv2.y)
            if abs(denom) < 1e-6 { continue }
            let invDenom = 1 / denom

            for ty in cy..<min(cy + edgeT, atlasSize) {
                for tx in cx..<min(cx + edgeT, atlasSize) {
                    let px = Float(tx) + 0.5, py = Float(ty) + 0.5
                    var w0 = ((uv1.y - uv2.y) * (px - uv2.x) + (uv2.x - uv1.x) * (py - uv2.y)) * invDenom
                    var w1 = ((uv2.y - uv0.y) * (px - uv2.x) + (uv0.x - uv2.x) * (py - uv2.y)) * invDenom
                    var w2 = 1 - w0 - w1
                    if w0 < -0.02 || w1 < -0.02 || w2 < -0.02 { continue }
                    // Clamp to the triangle for points just inside the gutter.
                    w0 = max(0, w0); w1 = max(0, w1); w2 = max(0, w2)
                    let s = w0 + w1 + w2
                    let point = (p0 * w0 + p1 * w1 + p2 * w2) / max(s, 1e-6)

                    // Sample only from views where this texel is the FRONT surface
                    // (occlusion test on). The tolerance (≈0.24 m at 2 m) already
                    // absorbs the decimation shift + soft-furniture noise, so an
                    // object's own surface passes — while a floor/wall texel hidden
                    // BEHIND an object (≥0.45 m back) is correctly rejected and left
                    // for fillUnseen. A blanket no-occlusion fallback here would
                    // paint the floor/wall with the object in front of it (a flat
                    // "smear" that reads as a flattened sofa) — so we DON'T fall back.
                    guard let color = ProjectiveSampler.sample(point: point, keyframes: candidates, normal: faceN, peak: options.viewPeak) else { continue }
                    let idx = ty * atlasSize + tx
                    atlas[idx * 4] = toByte(color.x)
                    atlas[idx * 4 + 1] = toByte(color.y)
                    atlas[idx * 4 + 2] = toByte(color.z)
                    atlas[idx * 4 + 3] = 255
                    covered[idx] = true
                }
            }
        }

        // 4. Dilate covered colours into the gutters to avoid seam bleeding.
        dilate(&atlas, &covered, size: atlasSize, iterations: options.dilateIterations)

        // 5. Fill never-seen texels (ceiling, unscanned wall patches, glass) with
        //    the mean captured colour so they read as plain surfaces — not black
        //    holes. This is most of what makes the result look "complete".
        fillUnseen(&atlas, covered: covered, size: atlasSize)

        return AtlasTexturedMesh(
            positions: positions, normals: normals, uvs: uvs,
            indices: indices, atlas: atlas, atlasSize: atlasSize
        )
    }

    // MARK: - Helpers

    private static func toByte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, Int(v * 255)))) }

    /// Replace still-uncovered texels with the mean covered colour (the room's
    /// dominant tone), so unseen surfaces blend in instead of rendering black.
    private static func fillUnseen(_ atlas: inout [UInt8], covered: [Bool], size: Int) {
        var r = 0, g = 0, b = 0, n = 0
        for i in 0..<(size * size) where covered[i] {
            r += Int(atlas[i * 4]); g += Int(atlas[i * 4 + 1]); b += Int(atlas[i * 4 + 2]); n += 1
        }
        guard n > 0 else { return }
        let mr = UInt8(r / n), mg = UInt8(g / n), mb = UInt8(b / n)
        for i in 0..<(size * size) where !covered[i] {
            atlas[i * 4] = mr; atlas[i * 4 + 1] = mg; atlas[i * 4 + 2] = mb; atlas[i * 4 + 3] = 255
        }
    }

    private static func safeNormalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let l = simd_length(v)
        return l > 1e-6 ? v / l : SIMD3<Float>(0, 1, 0)
    }

    /// Render `mesh` into this keyframe's view as a depth buffer (camera-space z),
    /// and return a copy of the keyframe whose occlusion depth IS that buffer.
    /// Rasterized at the LiDAR depth resolution when available (its intrinsics are
    /// already correctly scaled), else a coarse downscale of the RGB intrinsics.
    private static func meshDepthKeyframe(_ mesh: ConsolidatedMesh, _ kf: Keyframe) -> Keyframe {
        let w: Int, h: Int
        var intr: simd_float3x3
        if kf.depthWidth > 0, kf.depthHeight > 0 {
            w = kf.depthWidth; h = kf.depthHeight; intr = kf.depthIntrinsics
        } else {
            let target = 192
            let scale = Float(target) / Float(max(1, kf.width))
            w = max(1, Int((Float(kf.width) * scale).rounded()))
            h = max(1, Int((Float(kf.height) * scale).rounded()))
            intr = kf.intrinsics
            intr.columns.0.x *= scale; intr.columns.1.y *= scale
            intr.columns.2.x *= scale; intr.columns.2.y *= scale
        }
        let fx = intr.columns.0.x, fy = intr.columns.1.y
        let cx = intr.columns.2.x, cy = intr.columns.2.y
        let w2c = kf.worldToCamera

        var zbuf = [Float](repeating: .greatestFiniteMagnitude, count: w * h)
        mesh.positions.withUnsafeBufferPointer { pos in
        mesh.indices.withUnsafeBufferPointer { idx in
            let triCount = idx.count / 3
            for t in 0..<triCount {
                let p0 = pos[Int(idx[t*3])], p1 = pos[Int(idx[t*3+1])], p2 = pos[Int(idx[t*3+2])]
                // Project the 3 vertices to image space (camera-space z kept).
                let c0 = w2c * SIMD4<Float>(p0, 1)
                let c1 = w2c * SIMD4<Float>(p1, 1)
                let c2 = w2c * SIMD4<Float>(p2, 1)
                if c0.z >= -0.02 || c1.z >= -0.02 || c2.z >= -0.02 { continue }
                let z0 = -c0.z, z1 = -c1.z, z2 = -c2.z
                let x0 = fx * (c0.x / z0) + cx, y0 = fy * ((-c0.y) / z0) + cy
                let x1 = fx * (c1.x / z1) + cx, y1 = fy * ((-c1.y) / z1) + cy
                let x2 = fx * (c2.x / z2) + cx, y2 = fy * ((-c2.y) / z2) + cy

                let minX = max(0, Int(min(x0, x1, x2)))
                let maxX = min(w - 1, Int(max(x0, x1, x2)) + 1)
                let minY = max(0, Int(min(y0, y1, y2)))
                let maxY = min(h - 1, Int(max(y0, y1, y2)) + 1)
                if minX > maxX || minY > maxY { continue }
                let denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
                if abs(denom) < 1e-7 { continue }
                let invD = 1 / denom
                for py in minY...maxY {
                    let fpy = Float(py) + 0.5
                    for px in minX...maxX {
                        let fpx = Float(px) + 0.5
                        let b0 = ((y1 - y2) * (fpx - x2) + (x2 - x1) * (fpy - y2)) * invD
                        let b1 = ((y2 - y0) * (fpx - x2) + (x0 - x2) * (fpy - y2)) * invD
                        let b2 = 1 - b0 - b1
                        if b0 < -0.001 || b1 < -0.001 || b2 < -0.001 { continue }
                        let z = b0 * z0 + b1 * z1 + b2 * z2
                        let di = py * w + px
                        if z < zbuf[di] { zbuf[di] = z }
                    }
                }
            }
        }}
        // 0 = "no surface here" (the occlusion test treats ≤0.05 as no occluder).
        for i in 0..<zbuf.count where zbuf[i] == .greatestFiniteMagnitude { zbuf[i] = 0 }

        return Keyframe(width: kf.width, height: kf.height, rgba: kf.rgba,
                        intrinsics: kf.intrinsics, worldToCamera: kf.worldToCamera,
                        depth: zbuf, depthWidth: w, depthHeight: h, depthIntrinsics: intr,
                        cameraPosition: kf.cameraPosition, sharpness: kf.sharpness)
    }

    /// Grow covered texels outward by averaging covered 4-neighbours.
    private static func dilate(_ atlas: inout [UInt8], _ covered: inout [Bool], size: Int, iterations: Int) {
        guard iterations > 0 else { return }
        let offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for _ in 0..<iterations {
            var newlyCovered: [(Int, [UInt8])] = []
            for y in 0..<size {
                for x in 0..<size {
                    let idx = y * size + x
                    if covered[idx] { continue }
                    var r = 0, g = 0, b = 0, n = 0
                    for (dx, dy) in offsets {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < size, ny < size else { continue }
                        let nIdx = ny * size + nx
                        if covered[nIdx] {
                            r += Int(atlas[nIdx * 4]); g += Int(atlas[nIdx * 4 + 1]); b += Int(atlas[nIdx * 4 + 2]); n += 1
                        }
                    }
                    if n > 0 {
                        newlyCovered.append((idx, [UInt8(r / n), UInt8(g / n), UInt8(b / n), 255]))
                    }
                }
            }
            if newlyCovered.isEmpty { break }
            for (idx, c) in newlyCovered {
                atlas[idx * 4] = c[0]; atlas[idx * 4 + 1] = c[1]; atlas[idx * 4 + 2] = c[2]; atlas[idx * 4 + 3] = c[3]
                covered[idx] = true
            }
        }
    }
}
