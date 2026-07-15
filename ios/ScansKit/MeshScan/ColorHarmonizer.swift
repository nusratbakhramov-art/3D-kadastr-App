import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Har keyframe uchun rang kuchaytirgichlari (gain) — kadrlar orasidagi
/// ekspozitsiya/oq balans farqini tekislash uchun.
struct ColorGains {
    var r: Float = 1
    var g: Float = 1
    var b: Float = 1

    var isNearIdentity: Bool {
        abs(r - 1) < 0.02 && abs(g - 1) < 0.02 && abs(b - 1) < 0.02
    }
}

/// Panorama-tikish uslubidagi global rang tekislash: kadrlar juftligi bir xil
/// 3D nuqtalarni qanday rangda ko'rganini solishtirib, har kadr uchun
/// R/G/B gain'larni kichik kvadratlar usulida yechadi.
enum ColorHarmonizer {

    // MARK: - Public

    static func computeGains(
        geometries: [Int64: ChunkGeometry],
        keyframes: [KeyframeStore.Keyframe],
        assignments: [Int64: Int]
    ) -> [Int: ColorGains] {
        let used = Set(assignments.values)
        guard used.count > 1 else { return [:] }

        // Ishlatilgan kadrlarning kichik bitmap'lari (rang o'qish uchun)
        var bitmaps: [Int: Bitmap] = [:]
        for index in used {
            if let bitmap = makeBitmap(keyframes[index]) {
                bitmaps[index] = bitmap
            }
        }

        // Juftlik statistikasi: bir xil 3D nuqtani ikki kadr qanday ko'radi
        struct PairSum {
            var sumA = SIMD3<Double>.zero
            var sumB = SIMD3<Double>.zero
            var count = 0
        }
        var pairs: [Int64: PairSum] = [:]

        for (id, geo) in geometries {
            guard let i = assignments[id], let bitmapI = bitmaps[i] else { continue }
            let kfI = keyframes[i]

            let step = max(1, geo.positions.count / 80)
            var s = 0
            while s < geo.positions.count {
                let point = geo.positions[s]
                s += step
                guard let colorI = sampleColor(point: point, keyframe: kfI, bitmap: bitmapI) else { continue }

                for j in used where j != i {
                    guard let bitmapJ = bitmaps[j],
                          let colorJ = sampleColor(point: point, keyframe: keyframes[j], bitmap: bitmapJ)
                    else { continue }

                    let a = min(i, j), b = max(i, j)
                    let key = Int64(a) << 20 | Int64(b)
                    var pair = pairs[key] ?? PairSum()
                    if i < j {
                        pair.sumA += colorI
                        pair.sumB += colorJ
                    } else {
                        pair.sumA += colorJ
                        pair.sumB += colorI
                    }
                    pair.count += 1
                    pairs[key] = pair
                }
            }
        }

        // Kichik yoki ishonchsiz juftliklarni tashlaymiz
        let validPairs = pairs.filter { $0.value.count >= 15 }
        guard !validPairs.isEmpty else { return [:] }

        // Iterativ yechim (har kanal alohida): g_i = (Σ w·mI·mO·g_o + λ) / (Σ w·mI² + λ)
        var gains: [Int: SIMD3<Double>] = [:]
        for index in used { gains[index] = SIMD3<Double>(1, 1, 1) }

        for _ in 0..<20 {
            var next = gains
            for i in used {
                for ch in 0..<3 {
                    var num = 0.0
                    var den = 0.0
                    for (key, pair) in validPairs {
                        let a = Int(key >> 20), b = Int(key & 0xFFFFF)
                        guard a == i || b == i else { continue }
                        let other = (a == i) ? b : a
                        let count = Double(pair.count)
                        let meanI = ((a == i) ? pair.sumA : pair.sumB)[ch] / count
                        let meanO = ((a == i) ? pair.sumB : pair.sumA)[ch] / count
                        guard meanI > 0.02, meanO > 0.02 else { continue }
                        num += count * meanI * meanO * (gains[other]?[ch] ?? 1)
                        den += count * meanI * meanI
                    }
                    // Prior: ma'lumot kam bo'lsa gain 1 ga intiladi
                    let lambda = max(0.3 * den, 1e-9)
                    var value = (num + lambda) / (den + lambda)
                    value = min(max(value, 0.6), 1.7)
                    next[i]?[ch] = value
                }
            }
            gains = next
        }

        var result: [Int: ColorGains] = [:]
        for (index, g) in gains {
            result[index] = ColorGains(r: Float(g.x), g: Float(g.y), b: Float(g.z))
        }
        return result
    }

    /// Gain'larni rasmga qo'llaydi. Gain'lar gamma (sRGB) fazoda hisoblangan,
    /// CIColorMatrix esa linear fazoda ishlaydi — shuning uchun ^2.2 ko'tariladi.
    static func apply(_ gains: ColorGains, to image: CIImage) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: CGFloat(pow(gains.r, 2.2)), y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: CGFloat(pow(gains.g, 2.2)), z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: CGFloat(pow(gains.b, 2.2)), w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? image
    }

    // MARK: - Sampling

    private struct Bitmap {
        let pixels: [UInt8]  // RGBA
        let width: Int
        let height: Int
    }

    private static func makeBitmap(_ keyframe: KeyframeStore.Keyframe) -> Bitmap? {
        guard let uiImage = UIImage(data: keyframe.jpegData),
              let cgImage = uiImage.cgImage else { return nil }

        let width = 256
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

    /// 3D nuqtani keyframe'ga proyeksiya qilib, bitmap'dan rang o'qiydi.
    /// Kuyib ketgan (oq) va juda qorong'i piksellar tashlanadi.
    private static func sampleColor(
        point: SIMD3<Float>,
        keyframe: KeyframeStore.Keyframe,
        bitmap: Bitmap
    ) -> SIMD3<Double>? {
        let world = SIMD4<Float>(point.x, point.y, point.z, 1)
        let p4 = keyframe.transform.inverse * world
        let depth = -p4.z
        guard depth > 0.05 else { return nil }

        let k = keyframe.intrinsics
        let fx: Float = k[0][0]
        let fy: Float = k[1][1]
        let cx: Float = k[2][0]
        let cy: Float = k[2][1]
        let u: Float = fx * p4.x / depth + cx
        let v: Float = cy - fy * p4.y / depth

        // Chekka piksellar (stretch zonasi) ishonchsiz — 5% margin
        let marginX = Float(keyframe.width) * 0.05
        let marginY = Float(keyframe.height) * 0.05
        guard u > marginX, u < Float(keyframe.width) - marginX,
              v > marginY, v < Float(keyframe.height) - marginY else { return nil }

        // To'silgan nuqta boshqa obyekt rangini beradi — gain hisobiga yaroqsiz
        if keyframe.isOccluded(u: u, v: v, expectedDepth: depth) { return nil }

        let bx = Int(u / Float(keyframe.width) * Float(bitmap.width))
        let by = Int(v / Float(keyframe.height) * Float(bitmap.height))
        guard bx >= 0, bx < bitmap.width, by >= 0, by < bitmap.height else { return nil }

        let offset = (by * bitmap.width + bx) * 4
        let r = Double(bitmap.pixels[offset])
        let g = Double(bitmap.pixels[offset + 1])
        let b = Double(bitmap.pixels[offset + 2])

        // Kuygan oq yoki juda qorong'i — gain hisobiga yaroqsiz
        guard r < 250, g < 250, b < 250, (r + g + b) > 24 else { return nil }

        return SIMD3<Double>(r / 255.0, g / 255.0, b / 255.0)
    }
}
