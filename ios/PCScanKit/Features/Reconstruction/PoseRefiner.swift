import Foundation
import simd

/// Keyframe pozalarini aniqlashtirish (point-to-plane ICP) — Polycam'ning
/// "global pose optimization" bosqichiga funksional ekvivalent.
///
/// Muammo: frames.json pozalari suratga olish PAYTIDAGI (jonli) ARKit
/// pozalari. ARKit dunyo xaritasini sessiya davomida uzluksiz aniqlashtiradi
/// (loop closure) — ARMeshAnchor'lar yangilanadi, lekin O'TGAN kadr pozalari
/// retroaktiv tuzatilmaydi. Natija: yakuniy ARKit meshi bilan kadr pozalari
/// orasida 3–10sm nomuvofiqlik → tekstura surkalishi va carving xatolari.
///
/// Yechim: har kadrning LiDAR depth-buluti (o'sha paytdagi SENSOR haqiqati)
/// YAKUNIY ARKit meshiga (o'z-o'ziga muvofiq nishon) point-to-plane ICP
/// bilan tekislanadi. Aniqlashgan pozalar frames.json ga qayta yoziladi —
/// shundan keyin texrecon, depth-gate, carver va ekspozitsiya BARI
/// muvofiqlashgan ma'lumot bilan ishlaydi.
enum PoseRefiner {

    struct FrameDepth {
        let depthMM: [UInt16]
        let conf: [UInt8]?
        let dw: Int
        let dh: Int
    }

    struct Stats {
        var frames = 0
        var refined = 0
        var skipped = 0          // xavfsizlik darvozasi rad etganlar (asl poza qoladi)
        var residBeforeMM: Float = 0   // median-of-medians
        var residAfterMM: Float = 0
    }

    // MARK: - Sozlamalar

    /// Depth piksel qadami (256x192 / 4 → ~3k nuqta/kadr).
    private static let pixelStride = 4
    /// ICP iteratsiya jadvali: mos-nuqta qidiruv radiusi (m), qadamma-qadam torayadi.
    /// ARKit drifti kamdan-kam 12sm dan oshadi.
    private static let iterations: [Float] = [0.12, 0.07, 0.045]
    /// Ishonchli yechim uchun minimal mosliklar soni.
    private static let minCorrespondences = 400
    /// Xavfsizlik: bundan katta tuzatish — ICP adashgan, asl poza qoladi.
    private static let maxTranslation: Float = 0.25
    private static let maxRotation: Float = 8 * .pi / 180
    /// Depth ishonch oralig'i (m).
    private static let minZ: Float = 0.3
    private static let maxZ: Float = 4.0

    // MARK: - Diskda (app yo'li)

    /// arkit_mesh.bin + frames.json + depth/*.bin o'qib, pozalarni aniqlashtiradi
    /// va frames.json ni qayta yozadi. Asl pozalar bir marta frames_raw.json ga
    /// zaxiralanadi. Mesh/depth yo'q bo'lsa — shaffof o'tkazib yuboriladi.
    static func refineOnDisk(paths: ScanPaths, log: (String) -> Void) {
        guard let mesh = try? LiDARMesh.read(from: paths.arkitMeshURL), !mesh.isEmpty else {
            log("ICP skip: arkit_mesh yo'q"); return
        }
        guard let data = try? Data(contentsOf: paths.framesJSON),
              let poses = try? JSONDecoder().decode([KeyframePose].self, from: data), !poses.isEmpty else {
            log("ICP skip: frames.json yo'q"); return
        }

        let (refined, stats) = refine(
            meshPositions: mesh.positions, meshNormals: mesh.normals, poses: poses,
            depthFor: { pose in
                guard let dw = pose.depthWidth, let dh = pose.depthHeight, dw > 0, dh > 0 else { return nil }
                let dURL = paths.depthFolder.appendingPathComponent(String(format: "depth_%04d.bin", pose.index))
                guard let dData = try? Data(contentsOf: dURL), dData.count == dw * dh * 2 else { return nil }
                var depth = [UInt16](repeating: 0, count: dw * dh)
                dData.withUnsafeBytes { raw in depth.withUnsafeMutableBytes { $0.copyMemory(from: raw) } }
                let cURL = paths.depthFolder.appendingPathComponent(String(format: "conf_%04d.bin", pose.index))
                let conf = (try? Data(contentsOf: cURL)).flatMap { $0.count == dw * dh ? [UInt8]($0) : nil }
                return FrameDepth(depthMM: depth, conf: conf, dw: dw, dh: dh)
            })

        guard stats.refined > 0 else {
            log("ICP: aniqlashtirilmadi (refined=0, skipped=\(stats.skipped))"); return
        }
        // Asl pozalarni bir marta zaxiralaymiz (debug/qaytarish uchun).
        let backup = paths.root.appendingPathComponent("frames_raw.json")
        if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup) }
        if let out = try? JSONEncoder().encode(refined) {
            try? out.write(to: paths.framesJSON)
        }
        log(String(format: "ICP frames=%d refined=%d skipped=%d resid %.1fmm -> %.1fmm",
                   stats.frames, stats.refined, stats.skipped, stats.residBeforeMM, stats.residAfterMM))
    }

    /// Zich kesh pozalarini ham xuddi shu ICP bilan aniqlashtiradi —
    /// TSDF barcha dense kadrlarни muvofiq pozalar bilan integratsiya qilsin
    /// (aks holda jonli drift 600 kadr bo'ylab geometriyani surkaydi).
    static func refineDenseOnDisk(paths: ScanPaths, log: (String) -> Void) {
        guard let mesh = try? LiDARMesh.read(from: paths.arkitMeshURL), !mesh.isEmpty else {
            log("ICP-DENSE skip: arkit_mesh yo'q"); return
        }
        guard let data = try? Data(contentsOf: paths.densePosesJSON),
              let poses = try? JSONDecoder().decode([KeyframePose].self, from: data), !poses.isEmpty else {
            log("ICP-DENSE skip: dense_poses yo'q"); return
        }

        let (refined, stats) = refine(
            meshPositions: mesh.positions, meshNormals: mesh.normals, poses: poses,
            depthFor: { pose in
                guard let df = DenseDepthStore.load(index: pose.index, folder: paths.denseFolder),
                      df.dw == pose.depthWidth, df.dh == pose.depthHeight else { return nil }
                return FrameDepth(depthMM: df.depthMM, conf: df.conf, dw: df.dw, dh: df.dh)
            })

        guard stats.refined > 0 else {
            log("ICP-DENSE: aniqlashtirilmadi (refined=0, skipped=\(stats.skipped))"); return
        }
        let backup = paths.root.appendingPathComponent("dense_poses_raw.json")
        if !FileManager.default.fileExists(atPath: backup.path) { try? data.write(to: backup) }
        if let out = try? JSONEncoder().encode(refined) {
            try? out.write(to: paths.densePosesJSON)
        }
        log(String(format: "ICP-DENSE frames=%d refined=%d skipped=%d resid %.1fmm -> %.1fmm",
                   stats.frames, stats.refined, stats.skipped, stats.residBeforeMM, stats.residAfterMM))
    }

    // MARK: - Sof yadro (macOS'da test qilinadi)

    /// Har poza uchun ICP. Mesh — nishon (yakuniy ARKit meshi, world koordinatada).
    static func refine(meshPositions: [Float], meshNormals: [Float], poses: [KeyframePose],
                       depthFor: (KeyframePose) -> FrameDepth?) -> ([KeyframePose], Stats) {
        var stats = Stats()
        stats.frames = poses.count
        let vc = meshPositions.count / 3
        guard vc > 100 else { return (poses, stats) }

        // Har iteratsiya chegarasi uchun alohida hash-grid (bir marta, o'qish umumiy).
        let grids = iterations.map { Grid(positions: meshPositions, normals: meshNormals, cell: $0) }

        var refined = poses
        var beforeMed = [Float](repeating: -1, count: poses.count)
        var afterMed = [Float](repeating: -1, count: poses.count)
        var didRefine = [Bool](repeating: false, count: poses.count)
        var didSkip = [Bool](repeating: false, count: poses.count)

        // Kadrlar mustaqil — parallel.
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: poses.count) { pi in
            let pose = poses[pi]
            guard let fd = depthFor(pose) else { return }

            // Kamera-fazo nuqtalari (bir marta unproject).
            let camPts = unproject(pose: pose, frame: fd)
            guard camPts.count >= minCorrespondences else { return }

            var R = rotationOf(pose)
            var t = translationOf(pose)
            let R0 = R, t0 = t

            var before: Float = -1
            var converged = true
            for (it, thr) in iterations.enumerated() {
                let grid = grids[it]
                // Normal tenglamalar: A ξ = -b (Gauss-Newton, point-to-plane).
                var A = [Double](repeating: 0, count: 36)
                var b = [Double](repeating: 0, count: 6)
                var count = 0
                var residAbs: [Float] = []
                residAbs.reserveCapacity(camPts.count)

                for pc in camPts {
                    let p = R * pc + t
                    guard let (q, n) = grid.nearest(p, maxDist: thr) else { continue }
                    let r = simd_dot(n, p - q)
                    let c = simd_cross(p, n)
                    let j: [Double] = [Double(c.x), Double(c.y), Double(c.z),
                                       Double(n.x), Double(n.y), Double(n.z)]
                    let rd = Double(r)
                    for row in 0..<6 {
                        for col in row..<6 { A[row * 6 + col] += j[row] * j[col] }
                        b[row] += j[row] * rd
                    }
                    residAbs.append(abs(r))
                    count += 1
                }
                guard count >= minCorrespondences else { converged = false; break }
                if it == 0 { before = median(residAbs) }

                // Simmetrik to'ldirish + yengil damping.
                for row in 0..<6 {
                    for col in 0..<row { A[row * 6 + col] = A[col * 6 + row] }
                    A[row * 6 + row] += 1e-6
                }
                guard let xi = solve6(A, b.map { -$0 }) else { converged = false; break }

                let w = SIMD3<Float>(Float(xi[0]), Float(xi[1]), Float(xi[2]))
                let dt = SIMD3<Float>(Float(xi[3]), Float(xi[4]), Float(xi[5]))
                let Rd = rodrigues(w)
                R = Rd * R
                t = Rd * t + dt
            }

            guard converged, before >= 0 else { return }

            // Xavfsizlik darvozasi: umumiy tuzatish aql chegarasida bo'lsin.
            let dT = simd_distance(t, t0)
            let dR = rotationAngle(R * R0.transpose)
            if dT > maxTranslation || dR > maxRotation {
                lock.lock(); didSkip[pi] = true; beforeMed[pi] = before; lock.unlock()
                return
            }

            // Yakuniy qoldiq (eng tor chegara bilan).
            var finalRes: [Float] = []
            let lastGrid = grids[grids.count - 1]
            for pc in camPts {
                let p = R * pc + t
                if let (q, n) = lastGrid.nearest(p, maxDist: iterations.last!) {
                    finalRes.append(abs(simd_dot(n, p - q)))
                }
            }

            var newPose = pose
            writeTransform(R: R, t: t, into: &newPose)
            lock.lock()
            refined[pi] = newPose
            didRefine[pi] = true
            beforeMed[pi] = before
            afterMed[pi] = finalRes.isEmpty ? before : median(finalRes)
            lock.unlock()
        }

        stats.refined = didRefine.lazy.filter { $0 }.count
        stats.skipped = didSkip.lazy.filter { $0 }.count
        let bm = beforeMed.filter { $0 >= 0 }
        let am = afterMed.filter { $0 >= 0 }
        stats.residBeforeMM = bm.isEmpty ? 0 : median(bm) * 1000
        stats.residAfterMM = am.isEmpty ? 0 : median(am) * 1000
        return (refined, stats)
    }

    // MARK: - Unprojection

    private static func unproject(pose: KeyframePose, frame fd: FrameDepth) -> [SIMD3<Float>] {
        let sx = Float(pose.width) / Float(fd.dw)
        let sy = Float(pose.height) / Float(fd.dh)
        let fx = pose.intrinsics[0] / sx, fy = pose.intrinsics[4] / sy
        let cx = pose.intrinsics[6] / sx, cy = pose.intrinsics[7] / sy
        var pts: [SIMD3<Float>] = []
        pts.reserveCapacity((fd.dw / pixelStride) * (fd.dh / pixelStride))
        var v = 0
        while v < fd.dh {
            var u = 0
            while u < fd.dw {
                let i = v * fd.dw + u
                let mm = fd.depthMM[i]
                u += pixelStride
                if mm == 0 { continue }
                if let c = fd.conf, c[i] < 1 { continue }
                let z = Float(mm) / 1000
                if z < minZ || z > maxZ { continue }
                let X = (Float(u - pixelStride) + 0.5 - cx) / fx * z
                let Y = (Float(v) + 0.5 - cy) / fy * z
                pts.append(SIMD3(X, -Y, -z))     // ARKit kamera: -Z oldinga, Y flip
            }
            v += pixelStride
        }
        return pts
    }

    // MARK: - Mos-nuqta grid

    private struct Grid {
        let cell: Float
        var cells: [Int64: [Int32]] = [:]
        let positions: [Float]
        let normals: [Float]

        init(positions: [Float], normals: [Float], cell: Float) {
            self.cell = cell
            self.positions = positions
            self.normals = normals
            let vc = positions.count / 3
            cells.reserveCapacity(vc / 2)
            for i in 0..<vc {
                let key = Self.key(SIMD3(positions[i*3], positions[i*3+1], positions[i*3+2]), cell)
                cells[key, default: []].append(Int32(i))
            }
        }

        static func key(_ p: SIMD3<Float>, _ cell: Float) -> Int64 {
            let x = Int64(floor(p.x / cell)) & 0x1FFFFF
            let y = Int64(floor(p.y / cell)) & 0x1FFFFF
            let z = Int64(floor(p.z / cell)) & 0x1FFFFF
            return (x << 42) | (y << 21) | z
        }

        /// Eng yaqin mesh cho'qqisi (pozitsiya + normal), maxDist ichida.
        func nearest(_ p: SIMD3<Float>, maxDist: Float) -> (SIMD3<Float>, SIMD3<Float>)? {
            let cx = Int64(floor(p.x / cell)), cy = Int64(floor(p.y / cell)), cz = Int64(floor(p.z / cell))
            var bestD2 = maxDist * maxDist
            var bestI: Int32 = -1
            for dx in Int64(-1)...1 {
                for dy in Int64(-1)...1 {
                    for dz in Int64(-1)...1 {
                        let key = (((cx + dx) & 0x1FFFFF) << 42) | (((cy + dy) & 0x1FFFFF) << 21) | ((cz + dz) & 0x1FFFFF)
                        guard let idxs = cells[key] else { continue }
                        for i in idxs {
                            let q = SIMD3(positions[Int(i)*3], positions[Int(i)*3+1], positions[Int(i)*3+2])
                            let d2 = simd_distance_squared(p, q)
                            if d2 < bestD2 { bestD2 = d2; bestI = i }
                        }
                    }
                }
            }
            guard bestI >= 0 else { return nil }
            let i = Int(bestI)
            let n = SIMD3(normals[i*3], normals[i*3+1], normals[i*3+2])
            let l = simd_length(n)
            guard l > 1e-6 else { return nil }
            return (SIMD3(positions[i*3], positions[i*3+1], positions[i*3+2]), n / l)
        }
    }

    // MARK: - Kichik chiziqli algebra

    /// 6x6 Gauss eliminatsiyasi (qisman pivot). A satr-major.
    private static func solve6(_ Ain: [Double], _ bin: [Double]) -> [Double]? {
        var A = Ain, b = bin
        for col in 0..<6 {
            var pivot = col
            for row in (col + 1)..<6 where abs(A[row * 6 + col]) > abs(A[pivot * 6 + col]) { pivot = row }
            guard abs(A[pivot * 6 + col]) > 1e-12 else { return nil }
            if pivot != col {
                for k in 0..<6 { A.swapAt(col * 6 + k, pivot * 6 + k) }
                b.swapAt(col, pivot)
            }
            let inv = 1 / A[col * 6 + col]
            for row in (col + 1)..<6 {
                let f = A[row * 6 + col] * inv
                if f == 0 { continue }
                for k in col..<6 { A[row * 6 + k] -= f * A[col * 6 + k] }
                b[row] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: 6)
        for row in stride(from: 5, through: 0, by: -1) {
            var s = b[row]
            for k in (row + 1)..<6 { s -= A[row * 6 + k] * x[k] }
            x[row] = s / A[row * 6 + row]
        }
        return x
    }

    private static func rodrigues(_ w: SIMD3<Float>) -> simd_float3x3 {
        let th = simd_length(w)
        guard th > 1e-9 else { return matrix_identity_float3x3 }
        let k = w / th
        let K = simd_float3x3(SIMD3(0, k.z, -k.y), SIMD3(-k.z, 0, k.x), SIMD3(k.y, -k.x, 0))
        return matrix_identity_float3x3 + sin(th) * K + (1 - cos(th)) * (K * K)
    }

    private static func rotationAngle(_ R: simd_float3x3) -> Float {
        let tr = R.columns.0.x + R.columns.1.y + R.columns.2.z
        return acos(min(max((tr - 1) / 2, -1), 1))
    }

    private static func median(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[s.count / 2]
    }

    // MARK: - KeyframePose transform kirish-chiqishi

    private static func rotationOf(_ p: KeyframePose) -> simd_float3x3 {
        let t = p.transform
        return simd_float3x3(SIMD3(t[0], t[1], t[2]), SIMD3(t[4], t[5], t[6]), SIMD3(t[8], t[9], t[10]))
    }
    private static func translationOf(_ p: KeyframePose) -> SIMD3<Float> {
        SIMD3(p.transform[12], p.transform[13], p.transform[14])
    }
    private static func writeTransform(R: simd_float3x3, t: SIMD3<Float>, into pose: inout KeyframePose) {
        var m = pose.transform
        m[0] = R.columns.0.x; m[1] = R.columns.0.y; m[2] = R.columns.0.z
        m[4] = R.columns.1.x; m[5] = R.columns.1.y; m[6] = R.columns.1.z
        m[8] = R.columns.2.x; m[9] = R.columns.2.y; m[10] = R.columns.2.z
        m[12] = t.x; m[13] = t.y; m[14] = t.z
        pose.transform = m
    }
}
