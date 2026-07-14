import Foundation
import UIKit
import CoreGraphics
import simd

/// Skan tugagach ishga tushadigan "qayta ishlash" bosqichi: har chunk uchun
/// alohida tekstura pishiriladi (bake). Har piksel bir nechta keyframe'dan
/// og'irlik bilan aralashtiriladi:
///  - kadr sirtga qanchalik to'g'ri qaragan (facing)
///  - masofa
///  - kadr o'tkirligi (xira kadr kam vazn oladi)
///  - rang gain'lari (ColorHarmonizer) qo'llanadi
/// Natija: choksiz, rang-tekis, blur'ga chidamli teksturali model.
enum TextureBaker {

    struct BakedChunk {
        let geometry: ChunkGeometry
        /// Atlas UV (0..1, bottom-left origin — OBJ/RealityKit konvensiyasi)
        let uvs: [SIMD2<Float>]
        let image: CGImage?
    }

    private static let textureSize = 256
    private static let candidatesPerChunk = 4

    // MARK: - Public

    static func bake(
        geometries: [Int64: ChunkGeometry],
        keyframes: [KeyframeStore.Keyframe],
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> [Int64: BakedChunk] {
        guard !geometries.isEmpty, !keyframes.isEmpty else { return [:] }

        // Har chunk uchun eng yaxshi K ta kadr
        var candidates: [Int64: [Int]] = [:]
        var assignments: [Int64: Int] = [:]
        for (id, geo) in geometries {
            let ranked = TexturedOBJExporter.rankedKeyframes(
                for: geo, keyframes: keyframes, top: candidatesPerChunk
            )
            candidates[id] = ranked
            if let first = ranked.first { assignments[id] = first }
        }

        let usedIndices = Set(candidates.values.flatMap { $0 })
        guard !usedIndices.isEmpty else { return [:] }

        // Rang tekislash gain'lari
        let gains = ColorHarmonizer.computeGains(
            geometries: geometries, keyframes: keyframes, assignments: assignments
        )

        // Kadr bitmaplari (640px) va o'tkirlik og'irliklari
        var bitmaps: [Int: Bitmap] = [:]
        var sharpness: [Int: Float] = [:]
        for index in usedIndices {
            guard let bitmap = makeBitmap(keyframes[index], targetWidth: 640) else { continue }
            bitmaps[index] = bitmap
            sharpness[index] = laplacianVariance(bitmap)
        }
        let maxSharpness = max(sharpness.values.max() ?? 1, 1e-6)

        var result: [Int64: BakedChunk] = [:]
        let sorted = geometries.sorted { $0.key < $1.key }
        for (order, entry) in sorted.enumerated() {
            let (id, geo) = entry
            defer { onProgress?(order + 1, sorted.count) }

            guard let chunkCandidates = candidates[id], !chunkCandidates.isEmpty,
                  let primary = chunkCandidates.first
            else {
                result[id] = BakedChunk(geometry: geo, uvs: fallbackUVs(geo), image: nil)
                continue
            }

            let baked = bakeChunk(
                geometry: geo,
                primary: keyframes[primary],
                candidateIndices: chunkCandidates,
                keyframes: keyframes,
                bitmaps: bitmaps,
                gains: gains,
                sharpness: sharpness,
                maxSharpness: maxSharpness
            )
            result[id] = baked
        }
        return result
    }

    // MARK: - Chunk baking

    private static func bakeChunk(
        geometry geo: ChunkGeometry,
        primary: KeyframeStore.Keyframe,
        candidateIndices: [Int],
        keyframes: [KeyframeStore.Keyframe],
        bitmaps: [Int: Bitmap],
        gains: [Int: ColorGains],
        sharpness: [Int: Float],
        maxSharpness: Float
    ) -> BakedChunk {
        let n = textureSize

        // 1) Atlas parametrizatsiyasi: vertexlarni asosiy kadrga proyeksiya qilib,
        // bounding box bo'yicha [0,1]² ga siqamiz (v — yuqoridan pastga).
        var uvTop = [SIMD2<Float>](repeating: .zero, count: geo.positions.count)
        var minU: Float = .greatestFiniteMagnitude, maxU: Float = -.greatestFiniteMagnitude
        var minV: Float = .greatestFiniteMagnitude, maxV: Float = -.greatestFiniteMagnitude
        for (i, p) in geo.positions.enumerated() {
            let px = projectClamped(point: p, keyframe: primary)
            uvTop[i] = px
            minU = min(minU, px.x); maxU = max(maxU, px.x)
            minV = min(minV, px.y); maxV = max(maxV, px.y)
        }
        let extentU = max(maxU - minU, 1e-4)
        let extentV = max(maxV - minV, 1e-4)
        let pad: Float = 0.02
        for i in 0..<uvTop.count {
            let u = (uvTop[i].x - minU) / extentU
            let v = (uvTop[i].y - minV) / extentV
            uvTop[i] = SIMD2<Float>(pad + u * (1 - 2 * pad), pad + v * (1 - 2 * pad))
        }

        // 2) Rasterizatsiya + multi-view blending
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        var filled = [Bool](repeating: false, count: n * n)

        // Kandidat kadrlarning tayyor ma'lumotlari
        struct Candidate {
            let kf: KeyframeStore.Keyframe
            let bitmap: Bitmap
            let gain: SIMD3<Float>
            let weightScale: Float
        }
        var cands: [Candidate] = []
        for index in candidateIndices {
            guard let bitmap = bitmaps[index] else { continue }
            let g = gains[index] ?? ColorGains()
            let sharpWeight = 0.25 + 0.75 * ((sharpness[index] ?? 0) / maxSharpness)
            cands.append(Candidate(
                kf: keyframes[index],
                bitmap: bitmap,
                gain: SIMD3<Float>(g.r, g.g, g.b),
                weightScale: sharpWeight
            ))
        }
        guard !cands.isEmpty else {
            return BakedChunk(geometry: geo, uvs: flipV(uvTop), image: nil)
        }

        let hasNormals = geo.normals != nil
        var t = 0
        while t + 2 < geo.indices.count {
            let ia = Int(geo.indices[t]), ib = Int(geo.indices[t + 1]), ic = Int(geo.indices[t + 2])
            t += 3
            guard ia < geo.positions.count, ib < geo.positions.count, ic < geo.positions.count else { continue }

            let a = uvTop[ia] * Float(n - 1)
            let b = uvTop[ib] * Float(n - 1)
            let c = uvTop[ic] * Float(n - 1)
            let pa = geo.positions[ia], pb = geo.positions[ib], pc = geo.positions[ic]

            var na: SIMD3<Float>, nb: SIMD3<Float>, nc: SIMD3<Float>
            if hasNormals, let normals = geo.normals {
                na = normals[ia]; nb = normals[ib]; nc = normals[ic]
            } else {
                let face = simd_normalize(simd_cross(pb - pa, pc - pa))
                na = face; nb = face; nc = face
            }

            let denom = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            guard abs(denom) > 1e-6 else { continue }

            let minX = max(0, Int(min(a.x, b.x, c.x).rounded(.down)))
            let maxX = min(n - 1, Int(max(a.x, b.x, c.x).rounded(.up)))
            let minY = max(0, Int(min(a.y, b.y, c.y).rounded(.down)))
            let maxY = min(n - 1, Int(max(a.y, b.y, c.y).rounded(.up)))
            guard minX <= maxX, minY <= maxY else { continue }

            for py in minY...maxY {
                for px in minX...maxX {
                    let fx = Float(px), fy = Float(py)
                    let w0 = ((b.y - c.y) * (fx - c.x) + (c.x - b.x) * (fy - c.y)) / denom
                    let w1 = ((c.y - a.y) * (fx - c.x) + (a.x - c.x) * (fy - c.y)) / denom
                    let w2 = 1 - w0 - w1
                    guard w0 >= -0.002, w1 >= -0.002, w2 >= -0.002 else { continue }

                    let idx = py * n + px
                    if filled[idx] { continue }

                    let world = w0 * pa + w1 * pb + w2 * pc
                    let normal = simd_normalize(w0 * na + w1 * nb + w2 * nc)

                    var accum = SIMD3<Float>.zero
                    var weightSum: Float = 0
                    for cand in cands {
                        guard let (px2, expectedDepth) = projectPixelDepth(point: world, keyframe: cand.kf) else { continue }
                        // Occlusion: kadr bu yo'nalishda yaqinroq narsani ko'rgan
                        // bo'lsa (masalan, devor oldidagi kuler) — kadr yaroqsiz.
                        if cand.kf.isOccluded(u: px2.x, v: px2.y, expectedDepth: expectedDepth) { continue }
                        let camPos = SIMD3<Float>(
                            cand.kf.transform.columns.3.x,
                            cand.kf.transform.columns.3.y,
                            cand.kf.transform.columns.3.z
                        )
                        let toCam = camPos - world
                        let dist = simd_length(toCam)
                        guard dist > 1e-4 else { continue }
                        var facing = simd_dot(normal, toCam / dist)
                        facing = abs(facing)  // normal yo'nalishi noaniq bo'lishi mumkin
                        guard facing > 0.12 else { continue }

                        let sx = px2.x / Float(cand.kf.width) * Float(cand.bitmap.width)
                        let sy = px2.y / Float(cand.kf.height) * Float(cand.bitmap.height)
                        guard let color = bilinearSample(cand.bitmap, x: sx, y: sy) else { continue }

                        let weight = facing * cand.weightScale / (0.3 + dist * dist)
                        accum += color * cand.gain * weight
                        weightSum += weight
                    }

                    if weightSum > 0 {
                        let color = simd_clamp(accum / weightSum, SIMD3<Float>.zero, SIMD3<Float>(repeating: 1))
                        let offset = idx * 4
                        pixels[offset] = UInt8(color.x * 255)
                        pixels[offset + 1] = UInt8(color.y * 255)
                        pixels[offset + 2] = UInt8(color.z * 255)
                        pixels[offset + 3] = 255
                        filled[idx] = true
                    }
                }
            }
        }

        // 3) Dilatatsiya: bo'sh piksellar qo'shnilardan to'ldiriladi (chok oldini oladi)
        dilate(&pixels, &filled, size: n, passes: 4)

        // Qolgan bo'sh joylar — neytral kulrang
        for idx in 0..<(n * n) where !filled[idx] {
            let offset = idx * 4
            pixels[offset] = 140; pixels[offset + 1] = 140
            pixels[offset + 2] = 140; pixels[offset + 3] = 255
        }

        let image = makeCGImage(pixels: pixels, size: n)
        return BakedChunk(geometry: geo, uvs: flipV(uvTop), image: image)
    }

    // MARK: - Projection helpers

    /// To'liq kadr piksel koordinatalari (v — yuqoridan), chegaraga qisqartirilgan.
    private static func projectClamped(
        point: SIMD3<Float>, keyframe: KeyframeStore.Keyframe
    ) -> SIMD2<Float> {
        let world = SIMD4<Float>(point.x, point.y, point.z, 1)
        let p = keyframe.transform.inverse * world
        let depth = max(0.05, -p.z)
        let k = keyframe.intrinsics
        let u = k[0][0] * p.x / depth + k[2][0]
        let v = k[2][1] - k[1][1] * p.y / depth
        return SIMD2<Float>(
            simd_clamp(u, 0, Float(keyframe.width)),
            simd_clamp(v, 0, Float(keyframe.height))
        )
    }

    /// Piksel koordinatalari + kamera-fazo masofasi — faqat kadr ichida
    /// (2% margin), aks holda nil.
    private static func projectPixelDepth(
        point: SIMD3<Float>, keyframe: KeyframeStore.Keyframe
    ) -> (SIMD2<Float>, Float)? {
        let world = SIMD4<Float>(point.x, point.y, point.z, 1)
        let p = keyframe.transform.inverse * world
        let depth = -p.z
        guard depth > 0.05 else { return nil }
        let k = keyframe.intrinsics
        let u = k[0][0] * p.x / depth + k[2][0]
        let v = k[2][1] - k[1][1] * p.y / depth
        let mx = Float(keyframe.width) * 0.02
        let my = Float(keyframe.height) * 0.02
        guard u > mx, u < Float(keyframe.width) - mx,
              v > my, v < Float(keyframe.height) - my else { return nil }
        return (SIMD2<Float>(u, v), depth)
    }

    private static func flipV(_ uvs: [SIMD2<Float>]) -> [SIMD2<Float>] {
        uvs.map { SIMD2<Float>($0.x, 1 - $0.y) }
    }

    private static func fallbackUVs(_ geo: ChunkGeometry) -> [SIMD2<Float>] {
        [SIMD2<Float>](repeating: SIMD2<Float>(0.5, 0.5), count: geo.positions.count)
    }

    // MARK: - Bitmap

    private struct Bitmap {
        let pixels: [UInt8]  // RGBA
        let width: Int
        let height: Int
    }

    private static func makeBitmap(
        _ keyframe: KeyframeStore.Keyframe, targetWidth: Int
    ) -> Bitmap? {
        guard let uiImage = UIImage(data: keyframe.jpegData),
              let cgImage = uiImage.cgImage else { return nil }
        let width = targetWidth
        let height = max(1, cgImage.height * width / cgImage.width)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Bitmap(pixels: pixels, width: width, height: height)
    }

    /// 0..1 oraliqdagi RGB, bilinear interpolatsiya bilan.
    private static func bilinearSample(_ bitmap: Bitmap, x: Float, y: Float) -> SIMD3<Float>? {
        let fx = x - 0.5, fy = y - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        guard x0 >= 0, y0 >= 0, x0 + 1 < bitmap.width, y0 + 1 < bitmap.height else {
            let cx = min(max(Int(x), 0), bitmap.width - 1)
            let cy = min(max(Int(y), 0), bitmap.height - 1)
            let o = (cy * bitmap.width + cx) * 4
            return SIMD3<Float>(
                Float(bitmap.pixels[o]), Float(bitmap.pixels[o + 1]), Float(bitmap.pixels[o + 2])
            ) / 255
        }
        let tx = fx - Float(x0), ty = fy - Float(y0)

        func pixel(_ px: Int, _ py: Int) -> SIMD3<Float> {
            let o = (py * bitmap.width + px) * 4
            return SIMD3<Float>(
                Float(bitmap.pixels[o]), Float(bitmap.pixels[o + 1]), Float(bitmap.pixels[o + 2])
            )
        }
        let top = pixel(x0, y0) * (1 - tx) + pixel(x0 + 1, y0) * tx
        let bottom = pixel(x0, y0 + 1) * (1 - tx) + pixel(x0 + 1, y0 + 1) * tx
        return (top * (1 - ty) + bottom * ty) / 255
    }

    /// Kadr o'tkirligi — Laplasian dispersiyasi (xira kadr past qiymat oladi).
    private static func laplacianVariance(_ bitmap: Bitmap) -> Float {
        var sum: Double = 0
        var sumSq: Double = 0
        var count = 0
        let w = bitmap.width, h = bitmap.height
        var y = 2
        while y < h - 2 {
            var x = 2
            while x < w - 2 {
                func gray(_ px: Int, _ py: Int) -> Double {
                    let o = (py * w + px) * 4
                    return (Double(bitmap.pixels[o]) + Double(bitmap.pixels[o + 1]) + Double(bitmap.pixels[o + 2])) / 3
                }
                let lap = 4 * gray(x, y) - gray(x - 1, y) - gray(x + 1, y) - gray(x, y - 1) - gray(x, y + 1)
                sum += lap
                sumSq += lap * lap
                count += 1
                x += 2
            }
            y += 2
        }
        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        return Float(sumSq / Double(count) - mean * mean)
    }

    // MARK: - Post-processing

    private static func dilate(_ pixels: inout [UInt8], _ filled: inout [Bool], size n: Int, passes: Int) {
        for _ in 0..<passes {
            var newFilled = filled
            var newPixels = pixels
            for y in 0..<n {
                for x in 0..<n {
                    let idx = y * n + x
                    if filled[idx] { continue }
                    var accum = SIMD3<Int>.zero
                    var count = 0
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < n, ny >= 0, ny < n else { continue }
                        let nIdx = ny * n + nx
                        if filled[nIdx] {
                            let o = nIdx * 4
                            accum &+= SIMD3<Int>(Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2]))
                            count += 1
                        }
                    }
                    if count > 0 {
                        let o = idx * 4
                        newPixels[o] = UInt8(accum.x / count)
                        newPixels[o + 1] = UInt8(accum.y / count)
                        newPixels[o + 2] = UInt8(accum.z / count)
                        newPixels[o + 3] = 255
                        newFilled[idx] = true
                    }
                }
            }
            pixels = newPixels
            filled = newFilled
        }
    }

    private static func makeCGImage(pixels: [UInt8], size n: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: n, height: n,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
