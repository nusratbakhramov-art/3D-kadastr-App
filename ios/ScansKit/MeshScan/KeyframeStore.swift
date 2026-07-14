import Foundation
import ARKit
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Skan paytida kamera keyframe'larini (rasm + poza + intrinsics) yig'ib boradi.
/// Yangi keyframe faqat qurilma yetarlicha siljigan/burilganda olinadi.
final class KeyframeStore {

    struct Keyframe {
        let jpegData: Data
        /// camera → world (ARKit fazosi)
        let transform: simd_float4x4
        /// JPEG o'lchamiga moslashtirilgan intrinsics
        let intrinsics: simd_float3x3
        let width: Int
        let height: Int
        let position: SIMD3<Float>
        /// Kamera qarash yo'nalishi (-Z ustuni)
        let forward: SIMD3<Float>
        /// LiDAR depth xaritasi (metr) — occlusion tekshiruvi uchun
        let depthMap: [Float32]?
        let depthWidth: Int
        let depthHeight: Int
        /// Kadr o'tkirligi (luma Laplasian dispersiyasi) — xira kadr past qiymat
        let sharpness: Float

        /// Rasm piksel koordinatasidagi (v — yuqoridan) o'lchangan masofa.
        /// Bu yo'nalishda kadrda `expected`dan sezilarli yaqin narsa ko'ringan
        /// bo'lsa — nuqta to'silgan (occluded).
        func isOccluded(u: Float, v: Float, expectedDepth: Float) -> Bool {
            guard let depthMap, depthWidth > 0, depthHeight > 0 else { return false }
            let dx = Int(u / Float(width) * Float(depthWidth))
            let dy = Int(v / Float(height) * Float(depthHeight))
            guard dx >= 0, dx < depthWidth, dy >= 0, dy < depthHeight else { return false }
            let stored = depthMap[dy * depthWidth + dx]
            guard stored > 0.05 else { return false }
            let tolerance = max(0.08, expectedDepth * 0.08)
            return stored + tolerance < expectedDepth
        }
    }

    private(set) var keyframes: [Keyframe] = []

    private let lock = NSLock()
    private var lastPosition: SIMD3<Float>?
    private var lastForward: SIMD3<Float>?
    private var lastFrameTimestamp: TimeInterval?
    private var lastFramePosition: SIMD3<Float>?
    private var lastFrameForward: SIMD3<Float>?
    private let ciContext = CIContext()

    private let maxDimension: CGFloat = 1024   // 1440→1024: ko'p kadr (2-3 xona) xotiraga sig'sin
    // Zichroq kadr — rangli qamrov LiDAR qamroviga mos bo'lishi uchun (teshik qolmaydi)
    private let minDistance: Float = 0.2
    private let minAngleCos: Float = cos(20 * .pi / 180)   // 15°→20°: kamroq ortiqcha kadr
    private let maxKeyframes = 1500   // 2-3 xona uchun (avval 300 — bitta xonaga yetardi)

    // Motion-gate: tez/blur kadrlarni rad etadi — sifatli kadrlar tanlanadi
    private let maxAngularVelocity: Float = 0.55  // rad/s (~31°/s)
    private let maxLinearVelocity: Float = 0.7    // m/s

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return keyframes.count
    }

    func clear() {
        lock.lock()
        keyframes.removeAll()
        lastPosition = nil
        lastForward = nil
        lock.unlock()
    }

    func snapshot() -> [Keyframe] {
        lock.lock()
        defer { lock.unlock() }
        return keyframes
    }

    /// Har freymda chaqiriladi — threshold'lardan o'tsa keyframe sifatida saqlaydi.
    func maybeCapture(frame: ARFrame) {
        lock.lock()
        let currentCount = keyframes.count
        let lastPos = lastPosition
        let lastFwd = lastForward
        lock.unlock()

        guard currentCount < maxKeyframes else { return }
        guard case .normal = frame.camera.trackingState else { return }

        let t = frame.camera.transform
        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let forward = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)

        // Kadrni masofa/burchak oraliq bo'yicha olamiz (spacing). Blur muammosi
        // tekstura vaqtidagi o'tkirlik-og'irligida hal qilinadi — bu yerda kadrni
        // rad ETMAYMIZ (aks holda normal skanda deyarli har freym tushib qolardi).
        if let lastPos, let lastFwd {
            let moved = simd_distance(position, lastPos) > minDistance
            let turned = simd_dot(forward, lastFwd) < minAngleCos
            guard moved || turned else { return }
        }

        guard let keyframe = makeKeyframe(
            frame: frame, transform: t, position: position, forward: forward
        ) else { return }

        lock.lock()
        keyframes.append(keyframe)
        lastPosition = position
        lastForward = forward
        lock.unlock()
    }

    private func makeKeyframe(
        frame: ARFrame,
        transform: simd_float4x4,
        position: SIMD3<Float>,
        forward: SIMD3<Float>
    ) -> Keyframe? {
        let resolution = frame.camera.imageResolution
        let scale = min(1.0, maxDimension / max(resolution.width, resolution.height))

        var image = CIImage(cvPixelBuffer: frame.capturedImage)
        if scale < 1.0 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let jpeg = ciContext.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7]
        ) else { return nil }

        let s = Float(scale)
        var k = frame.camera.intrinsics
        k[0][0] *= s  // fx
        k[1][1] *= s  // fy
        k[2][0] *= s  // cx
        k[2][1] *= s  // cy

        // LiDAR depth xaritasi (bo'lsa) — occlusion tekshiruvi uchun
        var depthValues: [Float32]?
        var depthWidth = 0
        var depthHeight = 0
        if let sceneDepth = frame.sceneDepth {
            let buffer = sceneDepth.depthMap
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let rowStride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float32>.size
                let ptr = base.assumingMemoryBound(to: Float32.self)
                // 2× kichraytirib saqlaymiz — xotirani tejaydi (occlusion uchun yetarli)
                let dw = w / 2, dh = h / 2
                var values = [Float32](repeating: 0, count: dw * dh)
                for row in 0..<dh {
                    for col in 0..<dw {
                        values[row * dw + col] = ptr[(row * 2) * rowStride + col * 2]
                    }
                }
                depthValues = values
                depthWidth = dw
                depthHeight = dh
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }

        return Keyframe(
            jpegData: jpeg,
            transform: transform,
            intrinsics: k,
            width: Int((resolution.width * scale).rounded()),
            height: Int((resolution.height * scale).rounded()),
            position: position,
            forward: forward,
            depthMap: depthValues,
            depthWidth: depthWidth,
            depthHeight: depthHeight,
            sharpness: Self.lumaSharpness(frame.capturedImage)
        )
    }

    /// Kadr o'tkirligi: YCbCr buferning luma tekisligida markaziy hududda
    /// siyraklashtirilgan Laplasian dispersiyasi. JPEG dekodsiz, juda arzon.
    private static func lumaSharpness(_ pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 1,
              let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }

        let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Markaziy 60% hudud, har 6-piksel
        let x0 = w / 5, x1 = w - w / 5
        let y0 = h / 5, y1 = h - h / 5
        var sum = 0.0, sumSq = 0.0
        var count = 0
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let c = Double(ptr[y * rowStride + x])
                let lap = 4 * c
                    - Double(ptr[y * rowStride + x - 2])
                    - Double(ptr[y * rowStride + x + 2])
                    - Double(ptr[(y - 2) * rowStride + x])
                    - Double(ptr[(y + 2) * rowStride + x])
                sum += lap
                sumSq += lap * lap
                count += 1
                x += 6
            }
            y += 6
        }
        guard count > 0 else { return 0 }
        let mean = sum / Double(count)
        return Float(sumSq / Double(count) - mean * mean)
    }
}
