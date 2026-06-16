import Foundation
import simd

/// Builds a clean, complete room shell (flat walls + floor) from RoomPlan's
/// parametric surfaces and fuses it with the noisy depth mesh: the depth mesh
/// keeps only the objects that stick OUT from the walls, while the walls/floor
/// come from RoomPlan's planes. This is what closes most of the gap to Polycam —
/// it removes the ragged silhouette, fills holes (glass doors, unscanned wall
/// patches), and gives straight, complete surfaces.
///
/// Parses `room.json` (the encoded `CapturedRoom`) as raw JSON, so it needs no
/// RoomPlan dependency and runs in the headless tool too.
enum RoomShell {
    struct Plane {
        var transform: simd_float4x4
        var width: Float
        var height: Float
    }

    static func loadPlanes(_ url: URL) -> (walls: [Plane], floors: [Plane]) {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }
        return (parsePlanes(root, "walls"), parsePlanes(root, "floors"))
    }

    /// Doors + windows — openings cut into the walls. Used to delete the recessed
    /// door/window geometry so the flat wall quad covers them (no glass hole).
    static func loadOpenings(_ url: URL) -> [Plane] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return parsePlanes(root, "doors") + parsePlanes(root, "windows")
    }

    /// Complete wall planes built by extruding the floor's footprint polygon up
    /// to `wallHeight`. One quad per polygon edge → a closed, gap-free wall loop.
    static func footprintWalls(roomJSON url: URL, wallHeight: Float) -> [Plane] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let floors = root["floors"] as? [[String: Any]], let floor = floors.first,
              let tArr = floor["transform"] as? [Double], tArr.count == 16,
              let corners = floor["polygonCorners"] as? [[Double]], corners.count >= 3
        else { return [] }

        let floorT = simd_float4x4(flat: tArr.map { Float($0) })
        let world = corners.map { c -> SIMD3<Float> in
            (floorT * SIMD4<Float>(Float(c[0]), Float(c[1]), c.count > 2 ? Float(c[2]) : 0, 1)).xyz
        }
        var up = simd_normalize(floorT.rotation * SIMD3<Float>(0, 0, 1))
        if up.y < 0 { up = -up }

        var planes: [Plane] = []
        let n = world.count
        for i in 0..<n {
            let p0 = world[i], p1 = world[(i + 1) % n]
            let edge = p1 - p0
            let length = simd_length(edge)
            guard length > 0.1 else { continue }
            let xAxis = edge / length
            var zAxis = simd_cross(xAxis, up)
            let zLen = simd_length(zAxis)
            guard zLen > 1e-4 else { continue }
            zAxis /= zLen
            let mid = (p0 + p1) / 2 + up * (wallHeight / 2)
            var transform = matrix_identity_float4x4
            transform.columns.0 = SIMD4(xAxis, 0)
            transform.columns.1 = SIMD4(up, 0)
            transform.columns.2 = SIMD4(zAxis, 0)
            transform.columns.3 = SIMD4(mid, 1)
            planes.append(Plane(transform: transform, width: length, height: wallHeight))
        }
        return planes
    }

    private static func parsePlanes(_ root: [String: Any], _ key: String) -> [Plane] {
        guard let arr = root[key] as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let t = item["transform"] as? [Double], t.count == 16,
                  let d = item["dimensions"] as? [Double], d.count >= 2 else { return nil }
            return Plane(transform: simd_float4x4(flat: t.map { Float($0) }),
                         width: Float(d[0]), height: Float(d[1]))
        }
    }

    /// Fuse the depth mesh with the RoomPlan shell by SNAPPING near-planar wall/
    /// floor/ceiling vertices onto the exact RoomPlan planes. Snapping keeps the
    /// mesh CONNECTED (it only moves vertices, never deletes triangles), so walls
    /// go dead-flat WITHOUT swallowing furniture pushed against them — the old
    /// plane-SUBSTITUTION trade-off ("sofa merges into wall" vs "spiky walls") is
    /// gone. Planes with little/no depth (unscanned wall, synthesized ceiling) are
    /// substituted with a clean quad instead. Returns the fused mesh + a mask of
    /// the snapped (held-flat) vertices so the later object-smoother skips them.
    static func fuse(depthMesh: ConsolidatedMesh, roomJSON url: URL, subdivide: Float = 0.25)
        -> (mesh: ConsolidatedMesh, snapped: [Bool]) {
        let (rpWalls, floors) = loadPlanes(url)
        let wallHeight = rpWalls.map({ $0.height }).max() ?? 2.7
        let walls = rpWalls

        var planes = walls + floors
        if let floor = floors.first {            // synthesized ceiling
            var ceiling = floor
            ceiling.transform.columns.3.y += wallHeight
            planes.append(ceiling)
        }
        let emptyMask = [Bool](repeating: false, count: depthMesh.positions.count)
        guard !planes.isEmpty else { return (depthMesh, emptyMask) }

        let locals = planes.map { simd_inverse($0.transform) }
        let planeNormals = planes.map { simd_normalize($0.transform.rotation * SIMD3<Float>(0, 0, 1)) }

        let env = ProcessInfo.processInfo.environment
        // Wider band + looser normal gate so the WHOLE wall snaps dead-flat (the
        // real wall deviates several cm from RoomPlan's idealized plane, so a tight
        // band left it crumpled). Furniture is still protected by the normal gate:
        // a sofa back / beanbag faces the room (n·planeN low) so it is NOT snapped.
        let band      = (env["KADASTR_SNAP_BAND"]).flatMap { Float($0) } ?? 0.07   // ±7 cm inlier slab
        let feather   = (env["KADASTR_SNAP_FEATHER"]).flatMap { Float($0) } ?? 0.02 // graded outer ramp
        let normalCos = (env["KADASTR_SNAP_DOT"]).flatMap { Float($0) } ?? 0.75    // |n_v·n_plane|
        let minVotes  = Int((env["KADASTR_SNAP_VOTES"]).flatMap { Float($0) } ?? 200)

        var positions = depthMesh.positions
        var normals = depthMesh.normals
        var indices = depthMesh.indices
        var snapped = [Bool](repeating: false, count: positions.count)

        // Room centroid (orients substituted-quad normals inward).
        var center = SIMD3<Float>(repeating: 0)
        if !positions.isEmpty {
            for p in positions { center += p }; center /= Float(positions.count)
        } else {
            for p in planes { center += p.transform.translation }; center /= Float(planes.count)
        }

        // 1. Per-vertex plane membership: the nearest plane this vertex is BOTH
        //    within the band of AND oriented like (parallel). Count votes per plane.
        var member = [Int](repeating: -1, count: positions.count)
        var votes = [Int](repeating: 0, count: planes.count)
        for vi in 0..<positions.count {
            let p = positions[vi]
            let nv = normals[vi]
            var best = -1; var bestPerp = Float.greatestFiniteMagnitude
            for (i, plane) in planes.enumerated() {
                let local = locals[i] * SIMD4<Float>(p, 1)
                let perp = abs(local.z)
                guard perp <= band + feather,
                      abs(local.x) <= plane.width / 2 + 0.3,
                      abs(local.y) <= plane.height / 2 + 0.3 else { continue }
                guard abs(simd_dot(nv, planeNormals[i])) >= normalCos else { continue }
                if perp < bestPerp { bestPerp = perp; best = i }
            }
            member[vi] = best
            if best >= 0 { votes[best] += 1 }
        }

        // 2. Snap members of WELL-SUPPORTED planes onto the plane (graded falloff,
        //    so the join to nearby objects isn't a hard crease). Furniture verts
        //    (outside the band / not parallel) are never touched.
        for vi in 0..<positions.count {
            let pi = member[vi]
            guard pi >= 0, votes[pi] >= minVotes else { continue }
            let n = planeNormals[pi]
            let p = positions[vi]
            let perp = simd_dot(p - planes[pi].transform.translation, n)
            let d = abs(perp)
            let w: Float = d <= band - feather ? 1
                         : d >= band + feather ? 0
                         : 1 - (d - (band - feather)) / (2 * feather)
            positions[vi] = p - perp * n * w
            if w > 0.5 { normals[vi] = n; snapped[vi] = true }
        }

        // 3. Substitute a clean quad ONLY for planes with too little depth
        //    (genuinely unscanned wall / the synthesized ceiling). Its verts are
        //    flat already → mark snapped so the object-smoother leaves them alone.
        for (i, plane) in planes.enumerated() where votes[i] < minVotes {
            let localZ = simd_normalize(plane.transform.rotation * SIMD3<Float>(0, 0, 1))
            let n = simd_dot(localZ, center - plane.transform.translation) >= 0 ? localZ : -localZ
            appendPlane(plane, normal: n, subdivide: subdivide,
                        positions: &positions, normals: &normals, indices: &indices)
        }
        if positions.count > snapped.count {
            snapped.append(contentsOf: [Bool](repeating: true, count: positions.count - snapped.count))
        }

        return (ConsolidatedMesh(positions: positions, normals: normals, indices: indices), snapped)
    }

    // MARK: - Helpers

    private static func appendPlane(_ plane: Plane, normal: SIMD3<Float>, subdivide: Float, widen: Float = 0,
                                    positions: inout [SIMD3<Float>], normals: inout [SIMD3<Float>], indices: inout [UInt32]) {
        // Widen horizontally so neighbouring walls overlap at corners (no seam gap).
        let width = plane.width + 2 * widen
        let height = plane.height
        let nx = max(1, Int((width / subdivide).rounded(.up)))
        let ny = max(1, Int((height / subdivide).rounded(.up)))
        let base = UInt32(positions.count)

        for j in 0...ny {
            for i in 0...nx {
                let lx = -width / 2 + width * Float(i) / Float(nx)
                let ly = -height / 2 + height * Float(j) / Float(ny)
                let world = plane.transform * SIMD4<Float>(lx, ly, 0, 1)
                positions.append(world.xyz)
                normals.append(normal)
            }
        }

        let stride = UInt32(nx + 1)
        for j in 0..<ny {
            for i in 0..<nx {
                let i00 = base + UInt32(j) * stride + UInt32(i)
                let i10 = i00 + 1
                let i01 = i00 + stride
                let i11 = i01 + 1
                addQuad(i00, i01, i11, i10, normal: normal, positions: positions, indices: &indices)
            }
        }
    }

    /// Emit two triangles for a quad, winding so the geometric normal matches `normal`.
    private static func addQuad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32,
                                normal: SIMD3<Float>, positions: [SIMD3<Float>], indices: inout [UInt32]) {
        func tri(_ x: UInt32, _ y: UInt32, _ z: UInt32) {
            let geo = simd_cross(positions[Int(y)] - positions[Int(x)], positions[Int(z)] - positions[Int(x)])
            if simd_dot(geo, normal) >= 0 {
                indices.append(x); indices.append(y); indices.append(z)
            } else {
                indices.append(x); indices.append(z); indices.append(y)
            }
        }
        tri(a, b, c)
        tri(a, c, d)
    }
}
