import Foundation
import UIKit
import simd

/// On-device depth fusion: LiDAR depth kadrlarini TSDF hajmiga birlashtirib,
/// silliq rangli mesh quradi (Polycam yondashuvi).
/// Natija: mesh.bin (LiDARMeshData) + colors.bin (per-vertex RGB Float).
enum FusionEngine {

    enum FusionError: LocalizedError {
        case noDepthData(Int)
        case emptyVolume
        case emptyMesh

        var errorDescription: String? {
            switch self {
            case .noDepthData(let n):
                return "Depth kadrlari yetarli emas (\(n)). Bu skan eski versiyada olingan bo'lishi mumkin — yangi skan qiling."
            case .emptyVolume: return "Skan hajmi aniqlanmadi."
            case .emptyMesh: return "Yuza topilmadi."
            }
        }
    }

    private struct Frame {
        var R: simd_float3x3          // kamera->world rotatsiya (ustunlar)
        var t: SIMD3<Float>
        var fx: Float, fy: Float, cx: Float, cy: Float   // depth o'lchamiga moslangan
        var dw: Int, dh: Int
        var depth: [Float]            // metr
        var conf: [UInt8]             // 0/1/2
        var imageURL: URL
    }

    /// Butun pipeline. Og'ir — background thread'da chaqirilsin.
    static func run(paths: ScanPaths, progress: @escaping (Double, String) -> Void) throws -> (meshURL: URL, colorsURL: URL, stats: String) {

        // ===== 1. Kadrlarni yuklash =====
        progress(0.02, "Kadrlar yuklanmoqda…")
        let posesData = try Data(contentsOf: paths.framesJSON)
        let poses = try JSONDecoder().decode([KeyframePose].self, from: posesData)

        var frames: [Frame] = []
        for pose in poses {
            guard let dw = pose.depthWidth, let dh = pose.depthHeight, dw > 0, dh > 0 else { continue }
            let dURL = paths.depthFolder.appendingPathComponent(String(format: "depth_%04d.bin", pose.index))
            let cURL = paths.depthFolder.appendingPathComponent(String(format: "conf_%04d.bin", pose.index))
            let iURL = paths.imagesFolder.appendingPathComponent(String(format: "frame_%04d.jpg", pose.index))
            guard let dData = try? Data(contentsOf: dURL),
                  dData.count == dw * dh * 2,
                  FileManager.default.fileExists(atPath: iURL.path) else { continue }

            var depth = [Float](repeating: 0, count: dw * dh)
            dData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let mm = raw.bindMemory(to: UInt16.self)
                for i in 0..<dw * dh { depth[i] = Float(mm[i]) / 1000 }
            }
            var conf = [UInt8](repeating: 2, count: dw * dh)
            if let cData = try? Data(contentsOf: cURL), cData.count == dw * dh {
                cData.copyBytes(to: &conf, count: dw * dh)
            }

            let T = unflatten4(pose.transform)
            let K = unflatten3(pose.intrinsics)
            let sx = Float(pose.width) / Float(dw)
            let sy = Float(pose.height) / Float(dh)
            frames.append(Frame(
                R: simd_float3x3(
                    SIMD3(T.columns.0.x, T.columns.0.y, T.columns.0.z),
                    SIMD3(T.columns.1.x, T.columns.1.y, T.columns.1.z),
                    SIMD3(T.columns.2.x, T.columns.2.y, T.columns.2.z)),
                t: SIMD3(T.columns.3.x, T.columns.3.y, T.columns.3.z),
                fx: K.columns.0.x / sx, fy: K.columns.1.y / sy,
                cx: K.columns.2.x / sx, cy: K.columns.2.y / sy,
                dw: dw, dh: dh, depth: depth, conf: conf, imageURL: iURL
            ))
        }
        guard frames.count >= 10 else { throw FusionError.noDepthData(frames.count) }

        // ===== 2. Chegara =====
        var mins = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxs = -mins
        for f in stride(from: 0, to: frames.count, by: max(1, frames.count / 20)).map({ frames[$0] }) {
            for v in stride(from: 0, to: f.dh, by: 8) {
                for u in stride(from: 0, to: f.dw, by: 8) {
                    let z = f.depth[v * f.dw + u]
                    guard z > 0.1, z < 6, f.conf[v * f.dw + u] >= 1 else { continue }
                    let X = (Float(u) - f.cx) / f.fx * z
                    let Y = (Float(v) - f.cy) / f.fy * z
                    let world = f.R * SIMD3(X, -Y, -z) + f.t
                    mins = simd_min(mins, world)
                    maxs = simd_max(maxs, world)
                }
            }
        }
        guard mins.x < maxs.x else { throw FusionError.emptyVolume }
        mins -= SIMD3(repeating: 0.15); maxs += SIMD3(repeating: 0.15)

        var vox: Float = 0.03
        var dims = SIMD3<Int>(0, 0, 0)
        // Xotira qopqog'i: ~9M voxel
        while true {
            dims = SIMD3(Int(ceil((maxs.x - mins.x) / vox)),
                         Int(ceil((maxs.y - mins.y) / vox)),
                         Int(ceil((maxs.z - mins.z) / vox)))
            if dims.x * dims.y * dims.z <= 9_000_000 { break }
            vox *= 1.2
        }
        let total = dims.x * dims.y * dims.z

        // ===== 3. TSDF integratsiya =====
        let trunc: Float = vox * 3
        var tsdf = [Float](repeating: 1, count: total)
        var wsum = [Float](repeating: 0, count: total)

        tsdf.withUnsafeMutableBufferPointer { tPtr in
            wsum.withUnsafeMutableBufferPointer { wPtr in
                for (fi, f) in frames.enumerated() {
                    let RT = f.R.transpose
                    let colX = RT * SIMD3<Float>(vox, 0, 0)
                    let base0 = RT * (mins + SIMD3(repeating: vox / 2) - f.t)
                    f.depth.withUnsafeBufferPointer { dPtr in
                        f.conf.withUnsafeBufferPointer { cPtr in
                            var idx = 0
                            for i in 0..<dims.x {
                                let lcI = base0 + colX * Float(i)
                                for j in 0..<dims.y {
                                    let lcJ = lcI + RT * SIMD3<Float>(0, vox * Float(j), 0)
                                    for k in 0..<dims.z {
                                        let lc = lcJ + RT * SIMD3<Float>(0, 0, vox * Float(k))
                                        idx += 1
                                        let zc = -lc.z
                                        if zc <= 0.1 { continue }
                                        let u = lc.x / zc * f.fx + f.cx
                                        let v = -lc.y / zc * f.fy + f.cy
                                        if u < 0 || v < 0 { continue }
                                        let iu = Int(u), iv = Int(v)
                                        if iu >= f.dw || iv >= f.dh { continue }
                                        let di = iv * f.dw + iu
                                        let d = dPtr[di]
                                        if d <= 0.1 || d >= 6 || cPtr[di] < 1 { continue }
                                        let sdf = d - zc
                                        if sdf <= -trunc { continue }
                                        let s = min(max(sdf / trunc, -1), 1)
                                        let vi = idx - 1
                                        let w = wPtr[vi]
                                        tPtr[vi] = (tPtr[vi] * w + s) / (w + 1)
                                        wPtr[vi] = w + 1
                                    }
                                }
                            }
                        }
                    }
                    progress(0.05 + 0.5 * Double(fi + 1) / Double(frames.count), "Chuqurlik birlashtirilmoqda… \(fi + 1)/\(frames.count)")
                }
            }
        }

        // ===== 4. Yuzani ajratish =====
        progress(0.58, "Yuza qurilmoqda…")
        var mesh = SurfaceNets.extract(tsdf: tsdf, dims: dims, mins: mins, vox: vox)
        tsdf = []; wsum = []
        guard !mesh.positions.isEmpty, !mesh.faces.isEmpty else { throw FusionError.emptyMesh }

        // ===== 5. Laplacian silliqlash (2 marta) =====
        progress(0.62, "Silliqlanmoqda…")
        let nV = mesh.positions.count
        for _ in 0..<2 {
            var acc = [SIMD3<Float>](repeating: .zero, count: nV)
            var cnt = [Float](repeating: 0, count: nV)
            var fi = 0
            while fi < mesh.faces.count {
                let a = Int(mesh.faces[fi]), b = Int(mesh.faces[fi + 1]), c = Int(mesh.faces[fi + 2])
                acc[a] += mesh.positions[b] + mesh.positions[c]; cnt[a] += 2
                acc[b] += mesh.positions[a] + mesh.positions[c]; cnt[b] += 2
                acc[c] += mesh.positions[a] + mesh.positions[b]; cnt[c] += 2
                fi += 3
            }
            for i in 0..<nV where cnt[i] > 0 {
                mesh.positions[i] += (acc[i] / cnt[i] - mesh.positions[i]) * 0.5
            }
        }

        // ===== 6. Normallar =====
        var normals = [SIMD3<Float>](repeating: .zero, count: nV)
        var fi2 = 0
        while fi2 < mesh.faces.count {
            let a = Int(mesh.faces[fi2]), b = Int(mesh.faces[fi2 + 1]), c = Int(mesh.faces[fi2 + 2])
            let n = simd_cross(mesh.positions[b] - mesh.positions[a], mesh.positions[c] - mesh.positions[a])
            normals[a] += n; normals[b] += n; normals[c] += n
            fi2 += 3
        }
        for i in 0..<nV { normals[i] = simd_normalize(normals[i]) }

        // Global orientatsiya: yuzalar kameralar (xona ichi) tomon qarashi kerak.
        var camCentroid = SIMD3<Float>.zero
        for f in frames { camCentroid += f.t }
        camCentroid /= Float(frames.count)
        var dotSum: Float = 0
        for i in stride(from: 0, to: nV, by: max(1, nV / 5000)) {
            dotSum += simd_dot(normals[i], camCentroid - mesh.positions[i])
        }
        if dotSum < 0 {
            var fi3 = 0
            while fi3 < mesh.faces.count {
                mesh.faces.swapAt(fi3 + 1, fi3 + 2)
                fi3 += 3
            }
            for i in 0..<nV { normals[i] = -normals[i] }
        }

        // ===== 7. Ranglash (aralash — barcha ko'rgan kadrlardan) =====
        var accColor = [SIMD3<Float>](repeating: .zero, count: nV)
        var accW = [Float](repeating: 0, count: nV)

        // Ekspozitsiya normallashuvi uchun har kadr o'rtacha yorqinligi
        var lumas: [Float] = []
        var images: [[UInt8]] = []   // 512x384 RGBA
        let iw = 512, ih = 384
        for (fi, f) in frames.enumerated() {
            autoreleasepool {
                var px = [UInt8](repeating: 0, count: iw * ih * 4)
                if let ui = UIImage(contentsOfFile: f.imageURL.path), let cg = ui.cgImage {
                    let cs = CGColorSpaceCreateDeviceRGB()
                    if let ctx = CGContext(data: &px, width: iw, height: ih, bitsPerComponent: 8,
                                           bytesPerRow: iw * 4, space: cs,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        ctx.translateBy(x: 0, y: CGFloat(ih)); ctx.scaleBy(x: 1, y: -1)
                        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: iw, height: ih))
                    }
                }
                var s: UInt64 = 0
                var i = 0
                while i < px.count { s += UInt64(px[i]); i += 397 * 4 }
                lumas.append(Float(s))
                images.append(px)
            }
            if fi % 30 == 0 { progress(0.66 + 0.08 * Double(fi) / Double(frames.count), "Rasmlar tayyorlanmoqda…") }
        }
        let targetLuma = lumas.sorted()[lumas.count / 2]

        func colorPass(margin: Float, useCos: Bool, only: [Bool]?) {
            for (fi, f) in frames.enumerated() {
                let gain = min(max(targetLuma / max(lumas[fi], 1), 0.75), 1.35)
                let RT = f.R.transpose
                let px = images[fi]
                for i in 0..<nV {
                    if let only, !only[i] { continue }
                    let lc = RT * (mesh.positions[i] - f.t)
                    let zc = -lc.z
                    if zc <= 0.15 { continue }
                    let u = lc.x / zc * f.fx + f.cx
                    let v = -lc.y / zc * f.fy + f.cy
                    if u < 1 || v < 1 { continue }
                    let iu = Int(u), iv = Int(v)
                    if iu >= f.dw - 1 || iv >= f.dh - 1 { continue }
                    let d = f.depth[iv * f.dw + iu]
                    if abs(d - zc) >= margin { continue }
                    let toC = f.t - mesh.positions[i]
                    let dist2 = simd_length_squared(toC) + 1e-9
                    var w = 1 / dist2
                    if useCos {
                        let cosv = abs(simd_dot(normals[i], toC)) / sqrt(dist2)
                        w *= cosv * cosv
                    }
                    let ju = min(Int(u / Float(f.dw) * Float(iw)), iw - 1)
                    let jv = min(Int(v / Float(f.dh) * Float(ih)), ih - 1)
                    let p = (jv * iw + ju) * 4
                    let rgb = SIMD3<Float>(Float(px[p]), Float(px[p + 1]), Float(px[p + 2])) * gain
                    accColor[i] += rgb * w
                    accW[i] += w
                }
                if fi % 20 == 0 { progress(0.75 + 0.2 * Double(fi) / Double(frames.count), "Ranglar aralashtirilmoqda…") }
            }
        }

        colorPass(margin: 0.07, useCos: true, only: nil)
        var uncolored = accW.map { $0 <= 0 }
        if uncolored.contains(true) {
            colorPass(margin: 0.16, useCos: false, only: uncolored)
        }
        images = []

        var colors = [Float](repeating: 0.75, count: nV * 3)
        for i in 0..<nV where accW[i] > 0 {
            let c = accColor[i] / accW[i] / 255
            colors[i * 3] = min(c.x, 1); colors[i * 3 + 1] = min(c.y, 1); colors[i * 3 + 2] = min(c.z, 1)
        }
        uncolored = accW.map { $0 <= 0 }

        // Soxta tashqi qobiq: 3 vertexi ham rangsiz bo'lgan uchburchaklarni olib tashlaymiz.
        var kept: [UInt32] = []
        kept.reserveCapacity(mesh.faces.count)
        var fi4 = 0
        while fi4 < mesh.faces.count {
            let a = Int(mesh.faces[fi4]), b = Int(mesh.faces[fi4 + 1]), c = Int(mesh.faces[fi4 + 2])
            if !(uncolored[a] && uncolored[b] && uncolored[c]) {
                kept.append(mesh.faces[fi4]); kept.append(mesh.faces[fi4 + 1]); kept.append(mesh.faces[fi4 + 2])
            }
            fi4 += 3
        }

        // ===== 8. Saqlash =====
        progress(0.97, "Saqlanmoqda…")
        var flatPos = [Float](); flatPos.reserveCapacity(nV * 3)
        var flatNorm = [Float](); flatNorm.reserveCapacity(nV * 3)
        for i in 0..<nV {
            flatPos.append(mesh.positions[i].x); flatPos.append(mesh.positions[i].y); flatPos.append(mesh.positions[i].z)
            flatNorm.append(normals[i].x); flatNorm.append(normals[i].y); flatNorm.append(normals[i].z)
        }
        let out = LiDARMeshData(positions: flatPos, normals: flatNorm, indices: kept)
        try LiDARMesh.write(out, to: paths.lidarMeshURL)
        try LiDARMesh.writeColors(colors, to: paths.meshColorsURL)

        let stats = "verts=\(nV) tris=\(kept.count / 3) vox=\(String(format: "%.0f", vox * 1000))mm frames=\(frames.count)"
        progress(1, "Tayyor")
        return (paths.lidarMeshURL, paths.meshColorsURL, stats)
    }

    // MARK: - Yordamchilar

    private static func unflatten4(_ a: [Float]) -> simd_float4x4 {
        simd_float4x4(SIMD4(a[0], a[1], a[2], a[3]), SIMD4(a[4], a[5], a[6], a[7]),
                      SIMD4(a[8], a[9], a[10], a[11]), SIMD4(a[12], a[13], a[14], a[15]))
    }
    private static func unflatten3(_ a: [Float]) -> simd_float3x3 {
        simd_float3x3(SIMD3(a[0], a[1], a[2]), SIMD3(a[3], a[4], a[5]), SIMD3(a[6], a[7], a[8]))
    }
}
