// ImageQuality — hi-res photo capture vaqtida sharpness kabi sifat
// metrikalarini hisoblash. Atlas baker view-dependent blending'da har camera
// uchun sharpness weight'i ishlatadi, blurry frame'lar ta'siri kamayadi.
//
// Polycam-style view-dependent texturing'ning asosi:
//   weight = camAlign × faceDot × 1/dist² × sharpness × (1 - glareFactor)
//
// Sharpness = variance of Laplacian (downsampled grayscale)
// 0.0 = blank/blurry, ~1.0+ = sharp textured content.

import Foundation
import CoreGraphics
import ImageIO

enum ImageQuality {
    /// CGImage'dan sharpness (variance of Laplacian) hisoblaydi.
    /// Image downsample qilinadi (~192×144 gray), 3×3 Laplacian, variance.
    /// Qaytadigan qiymat odatda 0.0001 (blank) … 0.05 (motion blur) … 0.5+ (sharp).
    /// Normalize qilinadi: returned value [0, 1] orasida (1.0 = juda sharp).
    static func sharpness(of cgImage: CGImage, targetWidth: Int = 192) -> Float {
        let scale = Float(targetWidth) / Float(cgImage.width)
        let w = targetWidth
        let h = max(64, Int(Float(cgImage.height) * scale))
        guard let gray = renderGrayscale(cgImage: cgImage, width: w, height: h) else {
            return 0.0
        }
        return laplacianVarianceNormalized(gray: gray, width: w, height: h)
    }

    // MARK: - Internal

    /// CGImage → 8-bit grayscale buffer (linearizable luminance).
    /// Uses CGContext grayscale color space (~Rec.601 luma).
    private static func renderGrayscale(cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        let cs = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        let result: Bool = pixels.withUnsafeMutableBufferPointer { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue,
            ) else {
                return false
            }
            ctx.interpolationQuality = .low  // speed > quality for metric
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return result ? pixels : nil
    }

    /// 3×3 Laplacian variance. Returned value normalized to ~[0, 1]:
    ///   raw < 50  → blurry  (≈ 0)
    ///   raw 200   → moderate (≈ 0.3)
    ///   raw 800+  → sharp (≈ 1.0)
    private static func laplacianVarianceNormalized(gray: [UInt8], width: Int, height: Int) -> Float {
        if width < 3 || height < 3 { return 0.0 }
        var sum: Double = 0
        var sumSq: Double = 0
        var count: Double = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let c = Int(gray[y * width + x])
                let n = Int(gray[(y - 1) * width + x])
                let s = Int(gray[(y + 1) * width + x])
                let e = Int(gray[y * width + x + 1])
                let we = Int(gray[y * width + x - 1])
                // 4-neighborhood Laplacian: ∇²I = 4c - n - s - e - w
                let lap = 4 * c - n - s - e - we
                let lapD = Double(lap)
                sum += lapD
                sumSq += lapD * lapD
                count += 1
            }
        }
        if count <= 0 { return 0.0 }
        let mean = sum / count
        let variance = sumSq / count - mean * mean
        // Normalize: empirical range [0, ~800] → [0, 1] sigmoid-style.
        // 200 → 0.5, 800+ → ~0.9
        let v = max(0.0, variance)
        let norm = v / (v + 200.0)
        return Float(norm)
    }
}
