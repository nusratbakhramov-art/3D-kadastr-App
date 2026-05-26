// PoseRefiner — Phase 4: Bundle Adjustment infrastructure.
//
// Phase 4.1 (HOZIR): Loop closure detection via Apple Vision feature prints
//   - Har photo uchun feature signature
//   - Visual o'xshashlik orqali "bir xil joy" candidates
//   - ARKit pose'lar bilan solishtirish → drift detect
//   - Faqat diagnostic log, hech narsa o'zgartirmaydi
//
// Phase 4.2: Feature matching (ORB) + relative pose computation
// Phase 4.3: Pose graph optimization (Ceres yoki Gauss-Newton)
// Phase 4.4: Refined poses integration

import Foundation
import Vision
import simd
import CoreGraphics
import ImageIO

struct PhotoPoseSample {
    let index: Int                // sequence index (time proxy)
    let imageURL: URL
    let pose: simd_float4x4       // camera → world (ARKit)
    var position: SIMD3<Float> {
        return SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
    }
}

struct LoopClosureCandidate {
    let photoA: Int               // sequence index A
    let photoB: Int               // sequence index B
    let visualDistance: Float     // 0 = identical, higher = more different
    let arkitPositionDelta: Float // meters between ARKit poses
    let indexGap: Int             // sequence gap (time proxy)
}

enum PoseRefiner {
    /// Phase 4.1 — Loop closure detection only. Apple Vision feature prints
    /// orqali photo o'xshashligini hisoblaydi. Photo'lar **vaqtda uzoq** (gap
    /// >50) lekin **ARKit'da yaqin** (<1.5m) bo'lsa → camera shu joyga qaytib
    /// kelgan. Visual similarity yuqori bo'lsa, loop closure candidate.
    ///
    /// Hozirgi versiya pose'ni o'zgartirmaydi — faqat detection + log.
    static func detectLoopClosures(
        photos: [PhotoPoseSample],
        minIndexGap: Int = 50,
        maxArkitDistance: Float = 1.5,
        maxVisualDistance: Float = 1.0,
        progress: ((Float, String) -> Void)? = nil,
    ) async -> [LoopClosureCandidate] {
        guard photos.count >= 2 else { return [] }

        progress?(0.0, "Feature prints \(photos.count) ta photo'dan…")

        // 1. Extract feature prints (sequential — Apple Vision ~50ms/photo)
        let prints = await extractFeaturePrints(photos: photos, progress: progress)

        progress?(0.5, "Loop closure analyzer…")

        // 2. Pairwise distance matrix — faqat kerakli pair'lar
        var candidates: [LoopClosureCandidate] = []
        for i in 0..<(photos.count - minIndexGap) {
            guard let pi = prints[i] else { continue }
            for j in (i + minIndexGap)..<photos.count {
                guard let pj = prints[j] else { continue }

                let posDelta = simd_distance(photos[i].position, photos[j].position)
                if posDelta > maxArkitDistance { continue }

                var distance: Float = 0
                do {
                    try pi.computeDistance(&distance, to: pj)
                } catch {
                    continue
                }
                if distance > maxVisualDistance { continue }

                candidates.append(LoopClosureCandidate(
                    photoA: photos[i].index,
                    photoB: photos[j].index,
                    visualDistance: distance,
                    arkitPositionDelta: posDelta,
                    indexGap: j - i,
                ))
            }
        }

        progress?(1.0, "Loop detection ✓")
        return candidates
    }

    /// Diagnostic helper — loop closure'lardan drift statistikasini hisoblaydi.
    static func driftDiagnostic(_ loops: [LoopClosureCandidate]) -> String {
        guard !loops.isEmpty else { return "No loop closures detected" }
        let distances = loops.map { $0.arkitPositionDelta }
        let avgDelta = distances.reduce(0, +) / Float(distances.count)
        let maxDelta = distances.max() ?? 0
        let minDelta = distances.min() ?? 0
        return String(
            format: "%d loops, ARKit pose delta: min=%.1fcm avg=%.1fcm max=%.1fcm",
            loops.count, minDelta * 100, avgDelta * 100, maxDelta * 100,
        )
    }

    // MARK: - Internals

    private static func extractFeaturePrints(
        photos: [PhotoPoseSample],
        progress: ((Float, String) -> Void)?,
    ) async -> [VNFeaturePrintObservation?] {
        var prints: [VNFeaturePrintObservation?] = Array(repeating: nil, count: photos.count)
        for (i, photo) in photos.enumerated() {
            autoreleasepool {
                guard let cg = loadCGImage(url: photo.imageURL) else { return }
                let request = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do {
                    try handler.perform([request])
                    if let obs = request.results?.first as? VNFeaturePrintObservation {
                        prints[i] = obs
                    }
                } catch {
                    NSLog("KADASTR feature print failed #\(i): \(error.localizedDescription)")
                }
            }
            if i % 20 == 0 {
                progress?(0.05 + 0.40 * Float(i) / Float(max(photos.count, 1)),
                          "Feature prints \(i + 1)/\(photos.count)")
            }
        }
        return prints
    }

    private static func loadCGImage(url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}

// ────────────────────────────────────────────────────────────────────────
// Phase 3.2 — Light Bundle Adjustment via depth-to-mesh ICP.
//
// Polycam-style seam-free texturing'ning ikkinchi siri: photo pose'lari
// drift'idan ozod. Bizning ARKit pose'lar har ~30s'da ~3-5 sm drift beradi
// → ikki yaqin photo orasida ~1-2 sm sub-pixel mismatch → atlas seam.
//
// Yondashuv: ARKit anchor mesh — `ground truth` deb hisoblaymiz (LiDAR fusion).
// Har photo'ning depth map'i ushbu mesh'ga ICP bilan moslantiriladi:
//   1. Depth → 3D points (joriy pose bilan world space)
//   2. Har point uchun mesh'da eng yaqin vertex (spatial hash)
//   3. 6-DOF Gauss-Newton: rotation+translation delta'ni minimize qiladi
//   4. Pose'ni yangilang, 2-3 iteratsiya takrorlang
//
// Natija: photo pose'lar mesh bilan sinx → seam'lar yo'qoladi.
// ────────────────────────────────────────────────────────────────────────

struct PhotoDepthSample {
    let index: Int
    let pose: simd_float4x4               // camera → world (initial, ARKit)
    let intrinsics: simd_float3x3         // pixel intrinsics (depth resolution scale)
    let depthURL: URL
    let depthWidth: Int
    let depthHeight: Int
    let imageWidth: Float                 // image pose'lar uchun (depth scale aniqlash)
    let imageHeight: Float
}

extension PoseRefiner {
    /// Phase 3.2: har photo'ning pose'ini ARKit anchor mesh'iga ICP qiladi.
    /// Bu drift'ni kompensatsiya qiladi va atlas seam'larini yo'qotadi.
    ///
    /// - Parameters:
    ///   - photos: depth bilan birga keladigan photo sample'lar
    ///   - meshVertices: ARKit anchor mesh world-space vertex'lari (reference)
    ///   - voxelSize: spatial hash cell o'lchami (0.05 m default)
    ///   - iterations: ICP iter / photo (2-3 yetarli)
    ///   - maxCorrespondenceDistance: vertex match radius (0.10 m default)
    ///   - dampingFactor: pose update step (0.6 — Levenberg-Marquardt nudge)
    /// - Returns: refined pose'lar (input order'da)
    static func refinePosesViaICP(
        photos: [PhotoDepthSample],
        meshVertices: [SIMD3<Float>],
        voxelSize: Float = 0.05,
        iterations: Int = 3,
        maxCorrespondenceDistance: Float = 0.10,
        dampingFactor: Float = 0.6,
        progress: ((Float, String) -> Void)? = nil,
    ) async -> [simd_float4x4] {
        guard !photos.isEmpty, meshVertices.count > 100 else {
            return photos.map { $0.pose }
        }

        progress?(0.0, "Spatial hash quryapman…")
        let hash = SpatialHash(vertices: meshVertices, cellSize: voxelSize)

        var refined: [simd_float4x4] = photos.map { $0.pose }

        await Task.detached(priority: .userInitiated) {
            for (i, photo) in photos.enumerated() {
                guard let depthBuf = loadDepth(url: photo.depthURL,
                                               expectedW: photo.depthWidth,
                                               expectedH: photo.depthHeight) else {
                    continue
                }

                // Sample uniformly downsampled grid (max ~512 points). Strong points
                // — non-zero depth, distance 0.3-4.0 m.
                let depthSamples = sampleDepthPoints(
                    depth: depthBuf, w: photo.depthWidth, h: photo.depthHeight,
                    maxSamples: 512,
                )
                if depthSamples.count < 32 { continue }

                // Build intrinsics scaled to depth resolution.
                let scaleX = Float(photo.depthWidth) / photo.imageWidth
                let scaleY = Float(photo.depthHeight) / photo.imageHeight
                var depthK = photo.intrinsics
                depthK.columns.0.x *= scaleX
                depthK.columns.2.x *= scaleX
                depthK.columns.1.y *= scaleY
                depthK.columns.2.y *= scaleY
                let fx = depthK.columns.0.x
                let fy = depthK.columns.1.y
                let cx = depthK.columns.2.x
                let cy = depthK.columns.2.y

                var pose = refined[i]
                for _ in 0..<iterations {
                    // 1. Project depth points to 3D world using current pose
                    var worldPoints: [SIMD3<Float>] = []
                    worldPoints.reserveCapacity(depthSamples.count)
                    for s in depthSamples {
                        // ARKit camera: +X right, +Y up, -Z forward.
                        // Pixel (u, v) → ray. Y flip: image (top-down) → camera (Y up).
                        let xCam = (s.u - cx) * s.depth / fx
                        let yCam = -(s.v - cy) * s.depth / fy   // image Y → world Y (flip)
                        let zCam = -s.depth                      // forward = -Z
                        let pc = SIMD4<Float>(xCam, yCam, zCam, 1.0)
                        let pw = pose * pc
                        worldPoints.append(SIMD3<Float>(pw.x, pw.y, pw.z))
                    }

                    // 2. Find correspondences via spatial hash
                    var corrPoints: [(src: SIMD3<Float>, dst: SIMD3<Float>)] = []
                    corrPoints.reserveCapacity(worldPoints.count)
                    for wp in worldPoints {
                        if let near = hash.nearestWithin(wp, maxDistance: maxCorrespondenceDistance) {
                            corrPoints.append((src: wp, dst: near))
                        }
                    }
                    if corrPoints.count < 16 { break }

                    // 3. Solve small-angle ICP (Gauss-Newton, linearized).
                    // Pose update via Lie-algebra-style δ = [rx, ry, rz, tx, ty, tz]
                    // Residual = dst - src. Approximate Jacobian at identity rotation:
                    //   ∂residual/∂t = I (per-axis translation moves point 1:1)
                    //   ∂residual/∂r = -skew(src) (rotation around src acts as cross)
                    // Stack 3N residuals into 6x6 normal equations: J^T J δ = J^T r
                    let delta = solveICPDelta(correspondences: corrPoints)
                    let damped = delta.map { $0 * dampingFactor }
                    let nudge = makeDeltaTransform(damped)
                    pose = nudge * pose
                }
                refined[i] = pose

                if i % 10 == 0 {
                    let p = 0.05 + 0.93 * Float(i) / Float(max(photos.count, 1))
                    progress?(p, "ICP \(i + 1)/\(photos.count)")
                }
            }
        }.value

        progress?(1.0, "ICP ✓")
        return refined
    }

    // MARK: - ICP internals

    /// `delta` = [rx, ry, rz, tx, ty, tz] (radians + meters, small-angle).
    /// Qaytadigan matrix: small rotation (Rodrigues 1st-order) + translation.
    private static func makeDeltaTransform(_ delta: [Float]) -> simd_float4x4 {
        let rx = delta[0], ry = delta[1], rz = delta[2]
        let tx = delta[3], ty = delta[4], tz = delta[5]
        // Small-angle rotation matrix (Rodrigues' first-order):
        //   R ≈ I + skew([rx, ry, rz])
        // Orthonormal repair via 2nd-order term for stability.
        let R = simd_float3x3(rows: [
            SIMD3<Float>(1,        -rz,  ry),
            SIMD3<Float>( rz,       1,  -rx),
            SIMD3<Float>(-ry,      rx,   1),
        ])
        // Compose into 4×4 with translation in last column.
        return simd_float4x4(
            SIMD4<Float>(R.columns.0, 0),
            SIMD4<Float>(R.columns.1, 0),
            SIMD4<Float>(R.columns.2, 0),
            SIMD4<Float>(tx, ty, tz, 1),
        )
    }

    /// Gauss-Newton normal equations uchun 6-DOF delta.
    /// J^T J = 6×6 (symmetric), J^T r = 6×1. Solve via Cholesky.
    private static func solveICPDelta(
        correspondences: [(src: SIMD3<Float>, dst: SIMD3<Float>)],
    ) -> [Float] {
        // Build 6×6 normal matrix Atb and 6-vector b
        var ATA = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 6)
        var ATb = [Double](repeating: 0, count: 6)

        for c in correspondences {
            let s = c.src
            let r = SIMD3<Double>(Double(c.dst.x - c.src.x),
                                   Double(c.dst.y - c.src.y),
                                   Double(c.dst.z - c.src.z))
            // Per-correspondence Jacobian rows. Residual is 3D, so each correspondence
            // contributes 3 rows. Each row: [∂rx, ∂ry, ∂rz, ∂tx, ∂ty, ∂tz].
            //   x-row: [0,         -s.z,   s.y,  1, 0, 0]
            //   y-row: [s.z,        0,    -s.x,  0, 1, 0]
            //   z-row: [-s.y,       s.x,   0,    0, 0, 1]
            let sx = Double(s.x), sy = Double(s.y), sz = Double(s.z)
            let rows: [[Double]] = [
                [0,    -sz,   sy,  1, 0, 0],
                [sz,    0,   -sx,  0, 1, 0],
                [-sy,   sx,   0,   0, 0, 1],
            ]
            let resids: [Double] = [r.x, r.y, r.z]
            for k in 0..<3 {
                let Jrow = rows[k]
                let resid = resids[k]
                for a in 0..<6 {
                    ATb[a] += Jrow[a] * resid
                    for b in 0..<6 {
                        ATA[a][b] += Jrow[a] * Jrow[b]
                    }
                }
            }
        }

        // Levenberg-Marquardt damping on diagonal (small, ~1e-4) for stability.
        for k in 0..<6 { ATA[k][k] += 1e-4 }

        // Solve 6×6 SPD system via Cholesky. Tiny, can hand-roll.
        guard let delta = choleskySolve6(A: ATA, b: ATb) else {
            return [Float](repeating: 0, count: 6)
        }
        // Cap absolute delta to avoid wild jumps from outliers (5 cm / 5°).
        let maxR: Float = 0.087   // ~5°
        let maxT: Float = 0.05    // 5 cm
        return [
            max(-maxR, min(maxR, Float(delta[0]))),
            max(-maxR, min(maxR, Float(delta[1]))),
            max(-maxR, min(maxR, Float(delta[2]))),
            max(-maxT, min(maxT, Float(delta[3]))),
            max(-maxT, min(maxT, Float(delta[4]))),
            max(-maxT, min(maxT, Float(delta[5]))),
        ]
    }

    /// 6×6 SPD solve via Cholesky decomposition.
    /// Returns nil if non-positive-definite (singular).
    private static func choleskySolve6(A: [[Double]], b: [Double]) -> [Double]? {
        let n = 6
        var L = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in 0...i {
                var sum = A[i][j]
                for k in 0..<j { sum -= L[i][k] * L[j][k] }
                if i == j {
                    if sum <= 0 { return nil }
                    L[i][i] = sqrt(sum)
                } else {
                    L[i][j] = sum / L[j][j]
                }
            }
        }
        // Forward: L y = b
        var y = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var sum = b[i]
            for k in 0..<i { sum -= L[i][k] * y[k] }
            y[i] = sum / L[i][i]
        }
        // Backward: L^T x = y
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = y[i]
            for k in (i + 1)..<n { sum -= L[k][i] * x[k] }
            x[i] = sum / L[i][i]
        }
        return x
    }

    // MARK: - Depth sampling

    private struct DepthSample { let u: Float; let v: Float; let depth: Float }

    private static func sampleDepthPoints(
        depth: [Float], w: Int, h: Int, maxSamples: Int,
    ) -> [DepthSample] {
        // Stride to sample at most `maxSamples` points uniformly. e.g., 256×192 =
        // 49k pixels, target 512 → stride ~10×10 grid.
        let total = w * h
        let stride = max(1, Int(sqrt(Double(total) / Double(max(maxSamples, 1)))))
        var out: [DepthSample] = []
        out.reserveCapacity(maxSamples)
        var y = stride / 2
        while y < h {
            var x = stride / 2
            while x < w {
                let d = depth[y * w + x]
                if d > 0.3 && d < 4.0 {
                    out.append(DepthSample(u: Float(x) + 0.5, v: Float(y) + 0.5, depth: d))
                    if out.count >= maxSamples { return out }
                }
                x += stride
            }
            y += stride
        }
        return out
    }

    private static func loadDepth(url: URL, expectedW: Int, expectedH: Int) -> [Float]? {
        guard let data = try? Data(contentsOf: url), data.count >= 8 else { return nil }
        let w = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int32.self) }
        let h = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) }
        let pixCount = Int(w) * Int(h)
        if pixCount <= 0 { return nil }
        if Int(w) != expectedW || Int(h) != expectedH { return nil }
        var out = [Float](repeating: 0, count: pixCount)
        out.withUnsafeMutableBufferPointer { buf in
            data.withUnsafeBytes { raw in
                let src = raw.baseAddress!.advanced(by: 8).assumingMemoryBound(to: Float.self)
                memcpy(buf.baseAddress, src, pixCount * 4)
            }
        }
        return out
    }
}

/// Sparse spatial hash for nearest-vertex queries. O(1) amortized lookup
/// vs O(N) brute force — kerakli mesh ~50k+ vertex bo'lganda kritikal.
final class SpatialHash {
    private let cellSize: Float
    private let vertices: [SIMD3<Float>]
    private var grid: [Int64: [Int32]] = [:]

    init(vertices: [SIMD3<Float>], cellSize: Float) {
        self.cellSize = cellSize
        self.vertices = vertices
        grid.reserveCapacity(vertices.count / 4)
        for (i, v) in vertices.enumerated() {
            let key = cellKey(of: v)
            grid[key, default: []].append(Int32(i))
        }
    }

    /// Eng yaqin vertex'ni qaytaradi (maxDistance ichida bo'lsa).
    func nearestWithin(_ p: SIMD3<Float>, maxDistance: Float) -> SIMD3<Float>? {
        let cx = Int32(floor(p.x / cellSize))
        let cy = Int32(floor(p.y / cellSize))
        let cz = Int32(floor(p.z / cellSize))
        // Check radius in cells (typically 1 for cellSize ~maxDistance)
        let radius = max(1, Int32(ceil(maxDistance / cellSize)))
        var bestDist = maxDistance * maxDistance
        var best: SIMD3<Float>? = nil
        for dz in -radius...radius {
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let key = packKey(cx + dx, cy + dy, cz + dz)
                    guard let bucket = grid[key] else { continue }
                    for idx in bucket {
                        let v = vertices[Int(idx)]
                        let diff = v - p
                        let d2 = simd_length_squared(diff)
                        if d2 < bestDist {
                            bestDist = d2
                            best = v
                        }
                    }
                }
            }
        }
        return best
    }

    private func cellKey(of v: SIMD3<Float>) -> Int64 {
        let cx = Int32(floor(v.x / cellSize))
        let cy = Int32(floor(v.y / cellSize))
        let cz = Int32(floor(v.z / cellSize))
        return packKey(cx, cy, cz)
    }

    private func packKey(_ x: Int32, _ y: Int32, _ z: Int32) -> Int64 {
        // Pack three signed 21-bit integers (~±1M cells = ±50km @ 0.05m). Plenty.
        let xb = Int64(x) & 0x1FFFFF
        let yb = Int64(y) & 0x1FFFFF
        let zb = Int64(z) & 0x1FFFFF
        return (xb << 42) | (yb << 21) | zb
    }
}
