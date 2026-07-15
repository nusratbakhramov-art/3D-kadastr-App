import Foundation
import UIKit
import CoreGraphics
import simd

/// Per-vertex rang (Scaniverse xom ko'rinishi kabi silliq, shovqinsiz):
/// har mesh vertexi barcha kadrlarga proyeksiya qilinib, ranglar ko'p-ko'rinishli
/// o'rtacha olinadi (occlusion + facing + o'tkirlik bilan vaznlangan). Ko'rilmagan
/// vertexlar qo'shnilardan to'ldiriladi. Keyin per-chunk kichik teksturaga
/// Gouraud (barycentric) interpolatsiya bilan pishiriladi.
enum SmoothColorBaker {

    private struct Bitmap {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    static func bake(
        geometries: [Int64: ChunkGeometry],
        keyframes: [KeyframeStore.Keyframe],
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> [Int64: TextureBaker.BakedChunk] {
        guard !geometries.isEmpty, !keyframes.isEmpty else { return [:] }

        // 1) Kadr bitmaplari (256px — per-vertex rang uchun yetarli, xotira tejaydi)
        var bitmaps = [Bitmap?](repeating: nil, count: keyframes.count)
        for (i, kf) in keyframes.enumerated() {
            bitmaps[i] = makeBitmap(kf, targetWidth: 256)
        }
        let maxSharpness = max(keyframes.map(\.sharpness).max() ?? 1, 1e-6)

        let chunkList = geometries.sorted { $0.key < $1.key }
        var results = [Int64: TextureBaker.BakedChunk]()
        let lock = NSLock()
        var done = 0

        DispatchQueue.concurrentPerform(iterations: chunkList.count) { ci in
            let (id, geo) = chunkList[ci]
            if let baked = bakeChunk(
                geo, keyframes: keyframes, bitmaps: bitmaps, maxSharpness: maxSharpness
            ) {
                lock.lock(); results[id] = baked; done += 1; let d = done; lock.unlock()
                onProgress?(d, chunkList.count)
            } else {
                lock.lock(); done += 1; let d = done; lock.unlock()
                onProgress?(d, chunkList.count)
            }
        }
        return results
    }

    // MARK: - Chunk bake

    private static func bakeChunk(
        _ geo: ChunkGeometry,
        keyframes: [KeyframeStore.Keyframe],
        bitmaps: [Bitmap?],
        maxSharpness: Float
    ) -> TextureBaker.BakedChunk? {
        let vCount = geo.positions.count
        guard vCount >= 3, geo.indices.count >= 3 else { return nil }

        let hasN = geo.normals != nil

        // 1) Per-vertex rang + ishonch (multi-view o'rtacha)
        var colors = [SIMD3<Float>](repeating: SIMD3<Float>(0.55, 0.55, 0.55), count: vCount)
        var confidence = [Float](repeating: 0, count: vCount)

        for vi in 0..<vCount {
            let p = geo.positions[vi]
            let n = hasN ? geo.normals![vi] : SIMD3<Float>(0, 1, 0)
            var accum = SIMD3<Float>.zero
            var wSum: Float = 0
            for (k, kf) in keyframes.enumerated() {
                guard let bmp = bitmaps[k] else { continue }
                guard let (uv, depth) = project(p, kf) else { continue }
                if kf.isOccluded(u: uv.x, v: uv.y, expectedDepth: depth) { continue }
                let toCam = kf.position - p
                let dist = simd_length(toCam)
                guard dist > 1e-4 else { continue }
                let facing = abs(simd_dot(n, toCam / dist))
                guard facing > 0.1 else { continue }
                let sx = uv.x / Float(kf.width) * Float(bmp.width)
                let sy = uv.y / Float(kf.height) * Float(bmp.height)
                guard let c = sample(bmp, sx, sy) else { continue }
                let sharpW = 0.25 + 0.75 * (kf.sharpness / maxSharpness)
                let w = facing * sharpW / (0.3 + dist * dist)
                accum += c * w
                wSum += w
            }
            if wSum > 0 {
                colors[vi] = accum / wSum
                confidence[vi] = wSum
            }
        }

        // 2) Ko'rilmagan vertexlarni qo'shnilardan to'ldirish (Laplacian)
        var neighbors = [[Int]](repeating: [], count: vCount)
        var t = 0
        while t + 2 < geo.indices.count {
            let a = Int(geo.indices[t]), b = Int(geo.indices[t + 1]), c = Int(geo.indices[t + 2])
            t += 3
            neighbors[a].append(b); neighbors[a].append(c)
            neighbors[b].append(a); neighbors[b].append(c)
            neighbors[c].append(a); neighbors[c].append(b)
        }
        for _ in 0..<8 {
            var changed = false
            var next = colors
            for vi in 0..<vCount where confidence[vi] <= 0 {
                var accum = SIMD3<Float>.zero
                var cnt: Float = 0
                for nb in neighbors[vi] where confidence[nb] > 0 {
                    accum += colors[nb]; cnt += 1
                }
                if cnt > 0 {
                    next[vi] = accum / cnt
                    changed = true
                }
            }
            colors = next
            // to'ldirilganlarni "ishonchli" deb belgilaymiz (keyingi iteratsiya tarqatadi)
            for vi in 0..<vCount where confidence[vi] <= 0 {
                for nb in neighbors[vi] where confidence[nb] > 0 { confidence[vi] = 0.001; break }
            }
            if !changed { break }
        }

        // 3) Yengil rang silliqlash (shovqinni kamaytiradi)
        for _ in 0..<2 {
            var next = colors
            for vi in 0..<vCount {
                guard !neighbors[vi].isEmpty else { continue }
                var accum = colors[vi]
                var cnt: Float = 1
                for nb in neighbors[vi] { accum += colors[nb]; cnt += 1 }
                next[vi] = accum / cnt
            }
            colors = next
        }

        // 4) Planar UV (chunk dominant tekisligiga proyeksiya)
        let uvs = planarUVs(geo)

        // 5) Gouraud rasterizatsiya kichik teksturaga
        let n = 128
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        var filled = [Bool](repeating: false, count: n * n)
        rasterizeGouraud(geo, uvs: uvs, colors: colors, size: n, pixels: &pixels, filled: &filled)
        dilate(&pixels, &filled, size: n, passes: 6)

        guard let image = makeCGImage(pixels, n) else { return nil }
        // UV: bottom-left origin (RealityKit)
        let flipped = uvs.map { SIMD2<Float>($0.x, 1 - $0.y) }
        return TextureBaker.BakedChunk(geometry: geo, uvs: flipped, image: image)
    }

    // MARK: - Planar UV

    private static func planarUVs(_ geo: ChunkGeometry) -> [SIMD2<Float>] {
        var centroid = SIMD3<Float>.zero
        for p in geo.positions { centroid += p }
        centroid /= Float(geo.positions.count)

        // Dominant normal (uchburchak normalari yig'indisi)
        var normal = SIMD3<Float>.zero
        var t = 0
        while t + 2 < geo.indices.count {
            let a = geo.positions[Int(geo.indices[t])]
            let b = geo.positions[Int(geo.indices[t + 1])]
            let c = geo.positions[Int(geo.indices[t + 2])]
            normal += simd_cross(b - a, c - a)
            t += 3
        }
        if simd_length(normal) < 1e-8 { normal = SIMD3<Float>(0, 1, 0) }
        normal = simd_normalize(normal)

        // Tangent basis
        let ref: SIMD3<Float> = abs(normal.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let tangent = simd_normalize(simd_cross(ref, normal))
        let bitangent = simd_cross(normal, tangent)

        var uv = [SIMD2<Float>](repeating: .zero, count: geo.positions.count)
        var minU: Float = .greatestFiniteMagnitude, maxU: Float = -.greatestFiniteMagnitude
        var minV: Float = .greatestFiniteMagnitude, maxV: Float = -.greatestFiniteMagnitude
        for (i, p) in geo.positions.enumerated() {
            let d = p - centroid
            let u = simd_dot(d, tangent), v = simd_dot(d, bitangent)
            uv[i] = SIMD2<Float>(u, v)
            minU = min(minU, u); maxU = max(maxU, u)
            minV = min(minV, v); maxV = max(maxV, v)
        }
        let eu = max(maxU - minU, 1e-4), ev = max(maxV - minV, 1e-4)
        let pad: Float = 0.03
        for i in 0..<uv.count {
            uv[i] = SIMD2<Float>(
                pad + (uv[i].x - minU) / eu * (1 - 2 * pad),
                pad + (uv[i].y - minV) / ev * (1 - 2 * pad)
            )
        }
        return uv
    }

    // MARK: - Gouraud rasterization

    private static func rasterizeGouraud(
        _ geo: ChunkGeometry, uvs: [SIMD2<Float>], colors: [SIMD3<Float>],
        size n: Int, pixels: inout [UInt8], filled: inout [Bool]
    ) {
        var t = 0
        while t + 2 < geo.indices.count {
            let i0 = Int(geo.indices[t]), i1 = Int(geo.indices[t + 1]), i2 = Int(geo.indices[t + 2])
            t += 3
            let a = uvs[i0] * Float(n - 1), b = uvs[i1] * Float(n - 1), c = uvs[i2] * Float(n - 1)
            let ca = colors[i0], cb = colors[i1], cc = colors[i2]
            let denom = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            guard abs(denom) > 1e-6 else { continue }
            let minX = max(0, Int(min(a.x, b.x, c.x).rounded(.down)))
            let maxX = min(n - 1, Int(max(a.x, b.x, c.x).rounded(.up)))
            let minY = max(0, Int(min(a.y, b.y, c.y).rounded(.down)))
            let maxY = min(n - 1, Int(max(a.y, b.y, c.y).rounded(.up)))
            guard minX <= maxX, minY <= maxY else { continue }
            for py in minY...maxY {
                for px in minX...maxX {
                    let fx = Float(px) + 0.5, fy = Float(py) + 0.5
                    let w0 = ((b.y - c.y) * (fx - c.x) + (c.x - b.x) * (fy - c.y)) / denom
                    let w1 = ((c.y - a.y) * (fx - c.x) + (a.x - c.x) * (fy - c.y)) / denom
                    let w2 = 1 - w0 - w1
                    guard w0 >= -0.01, w1 >= -0.01, w2 >= -0.01 else { continue }
                    let col = simd_clamp(w0 * ca + w1 * cb + w2 * cc, .zero, SIMD3<Float>(repeating: 1))
                    let idx = py * n + px
                    let o = idx * 4
                    pixels[o] = UInt8(col.x * 255)
                    pixels[o + 1] = UInt8(col.y * 255)
                    pixels[o + 2] = UInt8(col.z * 255)
                    pixels[o + 3] = 255
                    filled[idx] = true
                }
            }
        }
    }

    // MARK: - Projection / sampling

    private static func project(_ p: SIMD3<Float>, _ kf: KeyframeStore.Keyframe) -> (SIMD2<Float>, Float)? {
        let world = SIMD4<Float>(p.x, p.y, p.z, 1)
        let pc = kf.transform.inverse * world
        let depth = -pc.z
        guard depth > 0.05 else { return nil }
        let k = kf.intrinsics
        let u = k[0][0] * pc.x / depth + k[2][0]
        let v = k[2][1] - k[1][1] * pc.y / depth
        let mx = Float(kf.width) * 0.02, my = Float(kf.height) * 0.02
        guard u > mx, u < Float(kf.width) - mx, v > my, v < Float(kf.height) - my else { return nil }
        return (SIMD2<Float>(u, v), depth)
    }

    private static func sample(_ bmp: Bitmap, _ x: Float, _ y: Float) -> SIMD3<Float>? {
        let cx = min(max(Int(x), 0), bmp.width - 1)
        let cy = min(max(Int(y), 0), bmp.height - 1)
        let o = (cy * bmp.width + cx) * 4
        return SIMD3<Float>(Float(bmp.pixels[o]), Float(bmp.pixels[o + 1]), Float(bmp.pixels[o + 2])) / 255
    }

    private static func makeBitmap(_ kf: KeyframeStore.Keyframe, targetWidth: Int) -> Bitmap? {
        guard let ui = UIImage(data: kf.jpegData), let cg = ui.cgImage else { return nil }
        let w = min(targetWidth, cg.width)
        let h = max(1, cg.height * w / cg.width)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Bitmap(pixels: px, width: w, height: h)
    }

    private static func dilate(_ pixels: inout [UInt8], _ filled: inout [Bool], size n: Int, passes: Int) {
        for _ in 0..<passes {
            var np = pixels, nf = filled
            for y in 0..<n {
                for x in 0..<n {
                    let idx = y * n + x
                    if filled[idx] { continue }
                    var acc = SIMD3<Int>.zero, cnt = 0
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < n, ny >= 0, ny < n else { continue }
                        let ni = ny * n + nx
                        if filled[ni] { let o = ni * 4; acc &+= SIMD3<Int>(Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2])); cnt += 1 }
                    }
                    if cnt > 0 {
                        let o = idx * 4
                        np[o] = UInt8(acc.x / cnt); np[o + 1] = UInt8(acc.y / cnt); np[o + 2] = UInt8(acc.z / cnt); np[o + 3] = 255
                        nf[idx] = true
                    }
                }
            }
            pixels = np; filled = nf
        }
    }

    private static func makeCGImage(_ pixels: [UInt8], _ n: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
