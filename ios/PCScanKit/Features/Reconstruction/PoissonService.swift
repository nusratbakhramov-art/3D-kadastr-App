import Foundation
import simd

/// Poisson Surface Reconstruction (Polycam uslubi) — on-device.
/// ARKit nuqta-bulutidan silliq, yopiq (watertight) mesh yasaydi:
///   1. Voxel downsample (bir xil zichlik).
///   2. Normallarni eng yaqin kameraga qaratish (izchil oriyentatsiya — texrecon uchun).
///   3. C++ PoissonRecon (pcscan_poisson).
///   4. ARKit bbox'ga kesish (Poisson tashqariga cho'zadi).
enum PoissonService {

    /// ARKit meshdan Poisson mesh. Muvaffaqiyatsiz bo'lsa nil.
    static func reconstruct(mesh: LiDARMeshData, cameraPositions: [SIMD3<Float>],
                            paths: ScanPaths, depth: Int32 = 9,
                            log: ((String) -> Void)? = nil) -> LiDARMeshData? {
        guard !mesh.isEmpty, !cameraPositions.isEmpty else { return nil }

        // 1. Nuqta+normal ajratamiz.
        let vc = mesh.vertexCount
        var pts = [SIMD3<Float>](); pts.reserveCapacity(vc)
        var nrm = [SIMD3<Float>](); nrm.reserveCapacity(vc)
        for i in 0..<vc {
            pts.append(SIMD3(mesh.positions[i*3], mesh.positions[i*3+1], mesh.positions[i*3+2]))
            let n = SIMD3(mesh.normals[i*3], mesh.normals[i*3+1], mesh.normals[i*3+2])
            let l = simd_length(n)
            nrm.append(l > 1e-6 ? n / l : SIMD3(0, 1, 0))
        }

        // 2. Voxel downsample (2sm).
        let voxel: Float = 0.02
        var acc = [SIMD3<Int32>: (p: SIMD3<Float>, n: SIMD3<Float>, c: Float)]()
        acc.reserveCapacity(vc / 4)
        for i in 0..<vc {
            let key = SIMD3<Int32>(Int32(floor(pts[i].x / voxel)),
                                   Int32(floor(pts[i].y / voxel)),
                                   Int32(floor(pts[i].z / voxel)))
            if var e = acc[key] { e.p += pts[i]; e.n += nrm[i]; e.c += 1; acc[key] = e }
            else { acc[key] = (pts[i], nrm[i], 1) }
        }
        var dpts = [SIMD3<Float>](); dpts.reserveCapacity(acc.count)
        var dnrm = [SIMD3<Float>](); dnrm.reserveCapacity(acc.count)
        var minB = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxB = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for (_, e) in acc {
            let p = e.p / e.c
            var n = e.n / e.c
            let l = simd_length(n); n = l > 1e-6 ? n / l : SIMD3(0, 1, 0)
            dpts.append(p); dnrm.append(n)
            minB = simd_min(minB, p); maxB = simd_max(maxB, p)
        }
        log?("POISSON downsampled \(dpts.count) points")

        // 2b. Statistik outlier tozalash (SOR) — shaffof/yaltiroq yuzalar (baklashka)
        //     hosil qilgan phantom nuqtalarni olib tashlaydi. Bular Poisson'да
        //     obyekt-devor "blob"lariga aylanardi.
        (dpts, dnrm) = removeOutliers(dpts, dnrm, log: log)

        // 3. Normallarni eng yaqin kameraga qaratamiz (izchil).
        for i in 0..<dpts.count {
            var best = 0; var bestD = Float.greatestFiniteMagnitude
            for (ci, cpos) in cameraPositions.enumerated() {
                let d = simd_distance_squared(dpts[i], cpos)
                if d < bestD { bestD = d; best = ci }
            }
            let toCam = cameraPositions[best] - dpts[i]
            if simd_dot(dnrm[i], toCam) < 0 { dnrm[i] = -dnrm[i] }
        }

        // 4. Nuqta-bulut PLY (points+normals, binary LE).
        let ptsPLY = paths.texturesDir.appendingPathComponent("poisson_points.ply")
        let outPLY = paths.texturesDir.appendingPathComponent("poisson_mesh.ply")
        try? FileManager.default.createDirectory(at: paths.texturesDir, withIntermediateDirectories: true)
        guard writePointsPLY(dpts, dnrm, to: ptsPLY) else { return nil }

        // 5. C++ PoissonRecon.
        // Xotira xavfsizligi: katta xonalarda depth 9 oktree juda ko'p xotira olib
        // qurilmani OOM (jetsam) qildiradi. Yakuniy mesh baribir 180k uchburchakka
        // kamaytiriladi, shuning uchun katta xonada depth 8 deyarli bir xil natija
        // beradi, lekin ~2.6× kam xotira (143MB vs 378MB). Kichik xona depth 9 qoladi.
        let diag = simd_length(maxB - minB)
        let effectiveDepth: Int32 = diag > 9.0 ? min(depth, 8) : depth
        if effectiveDepth != depth {
            log?("POISSON depth \(depth)→\(effectiveDepth) (katta xona diag=\(String(format: "%.1f", diag))m)")
        }
        #if targetEnvironment(simulator)
        // Native PoissonRecon faqat qurilmada (kutubxonalar simulyatorга linklanmaydi).
        log?("POISSON: native recon faqat qurilmada mavjud"); return nil
        #else
        log?("POISSON reconstructing (depth=\(effectiveDepth))…")
        let rc = ptsPLY.path.withCString { ip in
            outPLY.path.withCString { op in pcscan_poisson(ip, op, effectiveDepth) }
        }
        guard rc == 0, FileManager.default.fileExists(atPath: outPLY.path) else {
            log?("POISSON failed rc=\(rc)"); return nil
        }
        #endif

        // 6. Chiqish mesh'ini o'qib, bbox'ga kesamiz.
        guard var result = readPoissonPLY(outPLY) else { return nil }
        result = crop(result, minB: minB - 0.05, maxB: maxB + 0.05)
        log?("POISSON raw verts=\(result.vertexCount) tris=\(result.indices.count/3)")

        // 6b. Bo'sh fazo bo'yicha GIBRID kesish (Polycam uslubi): Poisson
        //     obyekt-devor orasida to'qigan "parda"/halo yuzalari (1) tayanchsiz
        //     (kirish nuqtalaridan uzoq) va (2) kameralar ular ORQAsini ko'rgan —
        //     kesiladi. Haqiqiy yuzalar kirish nuqtalari ustida yotadi — poza
        //     drifti ularni kesolmaydi (divan/pol regressiyasidan saqlaydi).
        let depthFrames = FreeSpaceCarver.loadFrames(framesJSON: paths.framesJSON,
                                                     depthFolder: paths.depthFolder)
        if !depthFrames.isEmpty {
            result = FreeSpaceCarver.carve(result, frames: depthFrames,
                                           supportPoints: dpts, log: log)
            log?("POISSON carved verts=\(result.vertexCount) tris=\(result.indices.count/3)")
        } else {
            log?("POISSON carve skipped (depth kadrlari yo'q)")
        }
        guard !result.isEmpty else { return nil }

        // 7. Decimation — texrecon xotirasi uchun yuza sonini kamaytiramiz
        //    (depth 9 nozik geometriyasi saqlanadi, lekin texrecon yengil bo'ladi).
        result = decimate(result, targetTris: 180_000)
        log?("POISSON decimated tris=\(result.indices.count/3)")
        return result.isEmpty ? nil : result
    }

    // MARK: - Statistik outlier tozalash (SOR + normal izchilligi)

    /// Har nuqta uchun qo'shni voxel katakchalaridagi eng yaqin 8 qo'shnigacha
    /// o'rtacha masofa hisoblanadi; o'rtacha+1.5σ dan uzoq nuqtalar (siyrak phantom)
    /// va qo'shnilar normali bilan mos kelmaydiganlar (tartibsiz shaffof aks) tashlanadi.
    private static func removeOutliers(_ pts: [SIMD3<Float>], _ nrm: [SIMD3<Float>],
                                       log: ((String) -> Void)?) -> ([SIMD3<Float>], [SIMD3<Float>]) {
        let n = pts.count
        guard n > 100 else { return (pts, nrm) }
        let cell: Float = 0.04
        var grid = [SIMD3<Int32>: [Int32]](minimumCapacity: n)
        @inline(__always) func key(_ p: SIMD3<Float>) -> SIMD3<Int32> {
            SIMD3(Int32(floor(p.x / cell)), Int32(floor(p.y / cell)), Int32(floor(p.z / cell)))
        }
        for i in 0..<n { grid[key(pts[i]), default: []].append(Int32(i)) }

        var meanDist = [Float](repeating: 0, count: n)
        var normAgree = [Float](repeating: 1, count: n)
        var best = [Float](repeating: 0, count: 8)
        for i in 0..<n {
            let p = pts[i], k = key(p)
            var count = 0
            var agreeSum: Float = 0; var agreeN = 0
            for _ in 0..<1 { best.replaceSubrange(0..<8, with: repeatElement(.greatestFiniteMagnitude, count: 8)) }
            for dx in Int32(-1)...1 {
                for dy in Int32(-1)...1 {
                    for dz in Int32(-1)...1 {
                        guard let cellPts = grid[SIMD3(k.x+dx, k.y+dy, k.z+dz)] else { continue }
                        for jj in cellPts {
                            let j = Int(jj)
                            if j == i { continue }
                            let d = simd_distance(p, pts[j])
                            // eng yaqin 8 talikka kiritamiz
                            if d < best[7] {
                                var t = 7
                                while t > 0 && best[t-1] > d { best[t] = best[t-1]; t -= 1 }
                                best[t] = d
                                if count < 8 { count += 1 }
                            }
                            agreeSum += simd_dot(nrm[i], nrm[j]); agreeN += 1
                        }
                    }
                }
            }
            if count >= 3 {
                var s: Float = 0
                for t in 0..<count { s += best[t] }
                meanDist[i] = s / Float(count)
            } else {
                meanDist[i] = 1.0        // juda siyrak — deyarli aniq outlier
            }
            if agreeN > 0 { normAgree[i] = agreeSum / Float(agreeN) }
        }
        var mean: Float = 0
        for v in meanDist { mean += v }
        mean /= Float(n)
        var varSum: Float = 0
        for v in meanDist { varSum += (v - mean) * (v - mean) }
        let sigma = sqrt(varSum / Float(n))
        let thr = mean + 1.5 * sigma

        var outPts = [SIMD3<Float>](); outPts.reserveCapacity(n)
        var outNrm = [SIMD3<Float>](); outNrm.reserveCapacity(n)
        for i in 0..<n where meanDist[i] < thr && normAgree[i] > 0.3 {
            outPts.append(pts[i]); outNrm.append(nrm[i])
        }
        log?("POISSON SOR \(n) -> \(outPts.count) (\(n - outPts.count) outlier)")
        return outPts.isEmpty ? (pts, nrm) : (outPts, outNrm)
    }

    // MARK: - Decimation (meshoptimizer)

    /// TSDFGeometry yo'li ham ishlatadi (TexReconService orqali) — internal.
    static func decimate(_ mesh: LiDARMeshData, targetTris: Int) -> LiDARMeshData {
        let indexCount = mesh.indices.count
        guard indexCount / 3 > targetTris, mesh.vertexCount > 0 else { return mesh }
        #if targetEnvironment(simulator)
        // meshoptimizer (pcscan_simplify) faqat qurilmada — simulyatorда decimation'siz.
        return mesh
        #else
        let ratio = Float(targetTris * 3) / Float(indexCount)
        var out = [UInt32](repeating: 0, count: indexCount)
        let n = mesh.positions.withUnsafeBufferPointer { pp -> Int32 in
            mesh.indices.withUnsafeBufferPointer { ip in
                out.withUnsafeMutableBufferPointer { op in
                    pcscan_simplify(pp.baseAddress, Int32(mesh.vertexCount),
                                    ip.baseAddress, Int32(indexCount),
                                    op.baseAddress, ratio)
                }
            }
        }
        guard n >= 3 else { return mesh }
        let newIndices = Array(out.prefix(Int(n)))
        var normals = mesh.normals
        computeNormals(&normals, positions: mesh.positions, indices: newIndices)
        return LiDARMeshData(positions: mesh.positions, normals: normals, indices: newIndices)
        #endif
    }

    // MARK: - Kesish (bbox)

    private static func crop(_ mesh: LiDARMeshData, minB: SIMD3<Float>, maxB: SIMD3<Float>) -> LiDARMeshData {
        let vc = mesh.vertexCount
        var keep = [Bool](repeating: false, count: vc)
        var remap = [Int32](repeating: -1, count: vc)
        var pos = [Float](); var nrm = [Float]()
        for i in 0..<vc {
            let p = SIMD3(mesh.positions[i*3], mesh.positions[i*3+1], mesh.positions[i*3+2])
            if all(p .>= minB) && all(p .<= maxB) {
                keep[i] = true; remap[i] = Int32(pos.count / 3)
                pos.append(p.x); pos.append(p.y); pos.append(p.z)
                nrm.append(mesh.normals[i*3]); nrm.append(mesh.normals[i*3+1]); nrm.append(mesh.normals[i*3+2])
            }
        }
        var idx = [UInt32]()
        var t = 0
        while t + 2 < mesh.indices.count {
            let a = Int(mesh.indices[t]), b = Int(mesh.indices[t+1]), c = Int(mesh.indices[t+2])
            if keep[a] && keep[b] && keep[c] {
                idx.append(UInt32(remap[a])); idx.append(UInt32(remap[b])); idx.append(UInt32(remap[c]))
            }
            t += 3
        }
        return LiDARMeshData(positions: pos, normals: nrm, indices: idx)
    }

    // MARK: - PLY I/O

    private static func writePointsPLY(_ pts: [SIMD3<Float>], _ nrm: [SIMD3<Float>], to url: URL) -> Bool {
        var header = "ply\nformat binary_little_endian 1.0\n"
        header += "element vertex \(pts.count)\n"
        header += "property float x\nproperty float y\nproperty float z\n"
        header += "property float nx\nproperty float ny\nproperty float nz\n"
        header += "end_header\n"
        var data = Data(header.utf8)
        var buf = [Float](); buf.reserveCapacity(pts.count * 6)
        for i in 0..<pts.count {
            buf.append(pts[i].x); buf.append(pts[i].y); buf.append(pts[i].z)
            buf.append(nrm[i].x); buf.append(nrm[i].y); buf.append(nrm[i].z)
        }
        buf.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return (try? data.write(to: url)) != nil
    }

    /// PoissonRecon chiqishi: vertex x,y,z (float), face `list int int`.
    private static func readPoissonPLY(_ url: URL) -> LiDARMeshData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Header'ni topamiz (end_header\n).
        guard let hdrRange = data.range(of: Data("end_header\n".utf8)) else { return nil }
        let headerText = String(data: data.subdata(in: 0..<hdrRange.upperBound), encoding: .ascii) ?? ""
        var vertexCount = 0, faceCount = 0
        var listCountType = "uchar", listIndexType = "int"
        var vertexFloatProps = 0            // vertexdagi float xossalar soni (x,y,z,value,…)
        var inVertexElement = false
        for line in headerText.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if line.hasPrefix("element vertex"), let n = Int(parts.last!) { vertexCount = n; inVertexElement = true }
            else if line.hasPrefix("element face"), let n = Int(parts.last!) { faceCount = n; inVertexElement = false }
            else if line.hasPrefix("property list"), parts.count >= 4 {
                listCountType = String(parts[2]); listIndexType = String(parts[3])
            } else if line.hasPrefix("property"), inVertexElement {
                vertexFloatProps += 1       // x,y,z (+ value, nx…) — barchasi float
            }
        }
        guard vertexCount > 0 else { return nil }
        let vertexStride = max(vertexFloatProps, 3) * 4   // x,y,z + qo'shimcha xossalar

        var offset = hdrRange.upperBound
        var positions = [Float](); positions.reserveCapacity(vertexCount * 3)
        var normals = [Float](repeating: 0, count: vertexCount * 3)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for _ in 0..<vertexCount {
                positions.append(raw.loadUnaligned(fromByteOffset: offset, as: Float.self))
                positions.append(raw.loadUnaligned(fromByteOffset: offset + 4, as: Float.self))
                positions.append(raw.loadUnaligned(fromByteOffset: offset + 8, as: Float.self))
                offset += vertexStride
            }
        }
        let countSize = (listCountType == "uchar" || listCountType == "uint8" || listCountType == "char") ? 1 : 4
        let idxSize = (listIndexType == "uchar" || listIndexType == "uint8") ? 1 : 4
        var indices = [UInt32](); indices.reserveCapacity(faceCount * 3)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for _ in 0..<faceCount {
                if offset >= data.count { break }
                let n: Int = countSize == 1 ? Int(raw.load(fromByteOffset: offset, as: UInt8.self))
                                            : Int(raw.loadUnaligned(fromByteOffset: offset, as: Int32.self))
                offset += countSize
                var poly = [UInt32](); poly.reserveCapacity(n)
                for _ in 0..<n {
                    let v: UInt32 = idxSize == 1 ? UInt32(raw.load(fromByteOffset: offset, as: UInt8.self))
                                                 : UInt32(raw.loadUnaligned(fromByteOffset: offset, as: Int32.self))
                    poly.append(v); offset += idxSize
                }
                // fan triangulyatsiya (Poisson uchburchak beradi, lekin ehtiyot uchun)
                for k in 1..<(poly.count - 1) where poly.count >= 3 {
                    indices.append(poly[0]); indices.append(poly[k]); indices.append(poly[k+1])
                }
            }
        }
        // Cho'qqi normallari (yuzalardan) — LiDARMeshData uchun.
        computeNormals(&normals, positions: positions, indices: indices)
        return LiDARMeshData(positions: positions, normals: normals, indices: indices)
    }

    private static func computeNormals(_ normals: inout [Float], positions: [Float], indices: [UInt32]) {
        let vc = positions.count / 3
        var acc = [SIMD3<Float>](repeating: .zero, count: vc)
        var t = 0
        while t + 2 < indices.count {
            let a = Int(indices[t]), b = Int(indices[t+1]), c = Int(indices[t+2]); t += 3
            let pa = SIMD3(positions[a*3], positions[a*3+1], positions[a*3+2])
            let pb = SIMD3(positions[b*3], positions[b*3+1], positions[b*3+2])
            let pc = SIMD3(positions[c*3], positions[c*3+1], positions[c*3+2])
            let fn = simd_cross(pb - pa, pc - pa)
            acc[a] += fn; acc[b] += fn; acc[c] += fn
        }
        for i in 0..<vc {
            let l = simd_length(acc[i])
            let n = l > 1e-8 ? acc[i] / l : SIMD3<Float>(0, 1, 0)
            normals[i*3] = n.x; normals[i*3+1] = n.y; normals[i*3+2] = n.z
        }
    }
}
