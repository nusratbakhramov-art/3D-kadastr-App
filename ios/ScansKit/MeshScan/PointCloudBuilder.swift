import Foundation
import UIKit
import simd

/// Dense rangli nuqta buluti (Scaniverse `VoxelHashing/PointCloudBuilder`
/// bosqichiga mos): barcha keyframe LiDAR depth xaritalari dunyoga
/// unproyeksiya qilinadi, voxel-panjara bilan siyraklashtiriladi.
/// Bu — Poisson Surface Reconstruction uchun kirish ma'lumoti, hamda
/// mustaqil PLY eksporti (Scaniverse .ply bilan solishtirish uchun).
enum PointCloudBuilder {

    struct Point {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var color: SIMD3<UInt8>
    }

    /// Voxel o'lchami (metr) — Scaniverse ~7mm; biz 8mm.
    private static let voxelSize: Float = 0.008

    static func build(
        keyframes: [KeyframeStore.Keyframe],
        needColor: Bool = true,
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> [Point] {
        struct Accum {
            var sumPos = SIMD3<Float>.zero
            var sumNormal = SIMD3<Float>.zero
            var sumColor = SIMD3<Float>.zero
            var count: Float = 0
        }
        var grid: [SIMD3<Int32>: Accum] = [:]
        let inv = 1 / voxelSize

        for (ki, kf) in keyframes.enumerated() {
            onProgress?(ki + 1, keyframes.count)
            guard let depth = kf.depthMap, kf.depthWidth > 0, kf.depthHeight > 0 else { continue }
            // Geometriya-only rejimda JPEG dekod qilinmaydi (tez, kam qizish)
            let bitmap: Bitmap? = needColor ? makeBitmap(kf, targetWidth: 512) : nil

            let dW = kf.depthWidth, dH = kf.depthHeight
            let k = kf.intrinsics
            let fx = k[0][0], fy = k[1][1], cx = k[2][0], cy = k[2][1]
            let colorScaleX = Float(kf.width) / Float(dW)
            let colorScaleY = Float(kf.height) / Float(dH)
            let transform = kf.transform

            // Depth pikselni kamera fazosiga unproyeksiya qiladigan yordamchi
            func unproject(_ dx: Int, _ dy: Int) -> SIMD3<Float>? {
                let d = depth[dy * dW + dx]
                guard d > 0.1, d < 8 else { return nil }
                let u = (Float(dx) + 0.5) * colorScaleX
                let v = (Float(dy) + 0.5) * colorScaleY
                let px = (u - cx) * d / fx
                let py = (cy - v) * d / fy
                return SIMD3<Float>(px, py, -d)
            }

            var dy = 1
            while dy < dH - 1 {
                var dx = 1
                while dx < dW - 1 {
                    guard let camP = unproject(dx, dy) else { dx += 1; continue }

                    // Normal: qo'shni depth piksellaridan (kamera fazosida)
                    var normalWorld = SIMD3<Float>(0, 1, 0)
                    if let right = unproject(dx + 1, dy), let down = unproject(dx, dy + 1) {
                        let n = simd_cross(right - camP, down - camP)
                        let len = simd_length(n)
                        if len > 1e-9 {
                            var camNormal = n / len
                            // Kameraga qaratamiz (-Z tomon)
                            if simd_dot(camNormal, -camP) < 0 { camNormal = -camNormal }
                            let nw = transform * SIMD4<Float>(camNormal, 0)
                            normalWorld = simd_normalize(SIMD3<Float>(nw.x, nw.y, nw.z))
                        }
                    }

                    let worldP4 = transform * SIMD4<Float>(camP, 1)
                    let worldP = SIMD3<Float>(worldP4.x, worldP4.y, worldP4.z)

                    // Rang: color-fazo pikselidan (geometriya-only rejimda o'tkaziladi)
                    var color = SIMD3<Float>(140, 140, 140)
                    if let bitmap {
                        let u = (Float(dx) + 0.5) * colorScaleX / Float(kf.width) * Float(bitmap.width)
                        let vv = (Float(dy) + 0.5) * colorScaleY / Float(kf.height) * Float(bitmap.height)
                        color = sampleColor(bitmap, x: Int(u), y: Int(vv))
                    }

                    let key = SIMD3<Int32>(
                        Int32((worldP.x * inv).rounded(.down)),
                        Int32((worldP.y * inv).rounded(.down)),
                        Int32((worldP.z * inv).rounded(.down))
                    )
                    var acc = grid[key] ?? Accum()
                    acc.sumPos += worldP
                    acc.sumNormal += normalWorld
                    acc.sumColor += color
                    acc.count += 1
                    grid[key] = acc

                    dx += 1
                }
                dy += 1
            }
        }

        var points: [Point] = []
        points.reserveCapacity(grid.count)
        for (_, acc) in grid {
            let p = acc.sumPos / acc.count
            let nLen = simd_length(acc.sumNormal)
            let n = nLen > 1e-9 ? acc.sumNormal / nLen : SIMD3<Float>(0, 1, 0)
            let c = acc.sumColor / acc.count
            points.append(Point(
                position: p, normal: n,
                color: SIMD3<UInt8>(
                    UInt8(min(max(c.x, 0), 255)),
                    UInt8(min(max(c.y, 0), 255)),
                    UInt8(min(max(c.z, 0), 255))
                )
            ))
        }
        return points
    }

    // MARK: - PLY eksport (binary_little_endian — Scaniverse formatiga mos)

    static func plyData(_ points: [Point]) -> Data {
        var header = "ply\n"
        header += "format binary_little_endian 1.0\n"
        header += "comment Created with ScansApp\n"
        header += "element vertex \(points.count)\n"
        header += "property float x\nproperty float y\nproperty float z\n"
        header += "property float nx\nproperty float ny\nproperty float nz\n"
        header += "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        header += "end_header\n"

        var data = Data(header.utf8)
        data.reserveCapacity(header.count + points.count * 27)
        for p in points {
            var x = p.position.x, y = p.position.y, z = p.position.z
            var nx = p.normal.x, ny = p.normal.y, nz = p.normal.z
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &nx) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &ny) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &nz) { data.append(contentsOf: $0) }
            data.append(p.color.x)
            data.append(p.color.y)
            data.append(p.color.z)
        }
        return data
    }

    // MARK: - Helpers

    private struct Bitmap {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    private static func makeBitmap(_ keyframe: KeyframeStore.Keyframe, targetWidth: Int) -> Bitmap? {
        guard let uiImage = UIImage(data: keyframe.jpegData),
              let cgImage = uiImage.cgImage else { return nil }
        let width = min(targetWidth, cgImage.width)
        let height = max(1, cgImage.height * width / cgImage.width)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Bitmap(pixels: pixels, width: width, height: height)
    }

    private static func sampleColor(_ bitmap: Bitmap, x: Int, y: Int) -> SIMD3<Float> {
        let cx = min(max(x, 0), bitmap.width - 1)
        let cy = min(max(y, 0), bitmap.height - 1)
        let o = (cy * bitmap.width + cx) * 4
        return SIMD3<Float>(Float(bitmap.pixels[o]), Float(bitmap.pixels[o + 1]), Float(bitmap.pixels[o + 2]))
    }
}
