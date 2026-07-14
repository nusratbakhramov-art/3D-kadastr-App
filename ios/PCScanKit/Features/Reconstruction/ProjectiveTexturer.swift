import UIKit
import SceneKit
import RoomPlan
import simd

/// Bake qilingan yuza tavsifi (viewer shu asosda tekis panel quradi).
struct SurfaceDef: Codable {
    let transform: [Float]   // 16, column-major (RoomPlan world)
    let width: Float
    let height: Float
    let texture: String      // PNG fayl nomi
}

/// M2 (Variant A) — RoomPlan yuzalariga (devor/pol) RGB kadrlarni proyeksiya qilib
/// to'liq xonani teksturalaydi. Geometriya RoomPlan'dan (aniq), rang kadrlardan.
enum ProjectiveTexturer {

    private struct Frame {
        let pixels: [UInt8]     // RGBA, row0 = top
        let width: Int
        let height: Int
        let invTransform: simd_float4x4
        let intrinsics: simd_float3x3   // downscaled
        let camPos: simd_float3
    }

    private struct Surface {
        let transform: simd_float4x4
        let width: Float
        let height: Float
    }

    enum TexturerError: LocalizedError {
        case noFrames
        var errorDescription: String? { "Tekstura uchun kamera pozitsiyalari topilmadi." }
    }

    /// Barcha yuzalarni bake qiladi. Natija: PNG'lar + surfaces.json outputDir'da.
    static func bake(room: CapturedRoom,
                     framesJSON: URL,
                     imagesFolder: URL,
                     outputDir: URL,
                     resolution: Int = 512,
                     imageScale: Float = 0.5,
                     progress: @escaping (Double) -> Void) throws -> [SurfaceDef] {

        let poses = try loadPoses(framesJSON)
        guard !poses.isEmpty else { throw TexturerError.noFrames }

        let fm = FileManager.default
        try? fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let frames = loadFrames(poses: poses, imagesFolder: imagesFolder, scale: imageScale)
        guard !frames.isEmpty else { throw TexturerError.noFrames }

        let surfaces = collectSurfaces(room: room)
        var defs: [SurfaceDef] = []

        for (i, surface) in surfaces.enumerated() {
            let texture = bakeSurface(surface, frames: frames, resolution: resolution)
            let name = String(format: "tex_%02d.png", i)
            if let png = texture {
                try? png.write(to: outputDir.appendingPathComponent(name))
                defs.append(SurfaceDef(transform: flatten(surface.transform),
                                       width: surface.width, height: surface.height,
                                       texture: name))
            }
            progress(Double(i + 1) / Double(surfaces.count))
        }

        let surfacesURL = outputDir.appendingPathComponent("surfaces.json")
        let data = try JSONEncoder().encode(defs)
        try data.write(to: surfacesURL)
        return defs
    }

    // MARK: - Yuzalar (devor + pol)

    private static func collectSurfaces(room: CapturedRoom) -> [Surface] {
        var result: [Surface] = []
        for wall in room.walls {
            result.append(Surface(transform: wall.transform,
                                  width: wall.dimensions.x, height: wall.dimensions.y))
        }
        for floor in room.floors {
            result.append(Surface(transform: floor.transform,
                                  width: floor.dimensions.x, height: floor.dimensions.y))
        }
        return result
    }

    // MARK: - Bitta yuzani bake qilish

    private static func bakeSurface(_ surface: Surface, frames: [Frame], resolution: Int) -> Data? {
        let t = surface.transform
        let center = simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let xAxis = simd_normalize(simd_float3(t.columns.0.x, t.columns.0.y, t.columns.0.z))
        let yAxis = simd_normalize(simd_float3(t.columns.1.x, t.columns.1.y, t.columns.1.z))
        let normal = simd_normalize(simd_float3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
        let w = surface.width, h = surface.height

        var tex = [UInt8](repeating: 200, count: resolution * resolution * 4)
        for k in stride(from: 3, to: tex.count, by: 4) { tex[k] = 255 }  // opaque

        for row in 0..<resolution {
            let v = h / 2 - (Float(row) + 0.5) / Float(resolution) * h
            for col in 0..<resolution {
                let u = (Float(col) + 0.5) / Float(resolution) * w - w / 2
                let world = center + xAxis * u + yAxis * v

                var bestFacing: Float = 0.2
                var bestColor: (UInt8, UInt8, UInt8)? = nil

                for f in frames {
                    let viewDir = simd_normalize(f.camPos - world)
                    let facing = simd_dot(normal, viewDir)
                    if facing <= bestFacing { continue }

                    let pc = f.invTransform * simd_float4(world, 1)
                    let cv = simd_float3(pc.x, -pc.y, -pc.z)
                    if cv.z <= 0.05 { continue }
                    let uvw = f.intrinsics * cv
                    let iu = Int(uvw.x / uvw.z)
                    let iv = Int(uvw.y / uvw.z)
                    if iu < 0 || iu >= f.width || iv < 0 || iv >= f.height { continue }

                    let p = (iv * f.width + iu) * 4
                    bestColor = (f.pixels[p], f.pixels[p + 1], f.pixels[p + 2])
                    bestFacing = facing
                }

                if let c = bestColor {
                    let o = (row * resolution + col) * 4
                    tex[o] = c.0; tex[o + 1] = c.1; tex[o + 2] = c.2; tex[o + 3] = 255
                }
            }
        }

        return pngData(rgba: tex, size: resolution)
    }

    // MARK: - Kadrlarni yuklash

    private static func loadPoses(_ url: URL) throws -> [KeyframePose] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([KeyframePose].self, from: data)
    }

    private static func loadFrames(poses: [KeyframePose], imagesFolder: URL, scale: Float) -> [Frame] {
        var frames: [Frame] = []
        for pose in poses {
            let url = imagesFolder.appendingPathComponent(String(format: "frame_%04d.jpg", pose.index))
            guard let image = UIImage(contentsOfFile: url.path), let cg = image.cgImage else { continue }
            let w = Int(Float(cg.width) * scale)
            let h = Int(Float(cg.height) * scale)
            guard w > 0, h > 0 else { continue }

            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpaceCreateDeviceRGB()
            let info = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs, bitmapInfo: info) else { continue }
            // Row0 = top bo'lishi uchun kontekstni ag'daramiz.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

            let t = unflatten(pose.transform)
            let kFull = unflatten3(pose.intrinsics)
            var kScaled = kFull
            kScaled.columns.0.x *= scale     // fx
            kScaled.columns.1.y *= scale     // fy
            kScaled.columns.2.x *= scale     // cx
            kScaled.columns.2.y *= scale     // cy

            let camPos = simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            frames.append(Frame(pixels: pixels, width: w, height: h,
                                invTransform: simd_inverse(t), intrinsics: kScaled, camPos: camPos))
        }
        return frames
    }

    // MARK: - Yordamchilar

    private static func pngData(rgba: [UInt8], size: Int) -> Data? {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        guard let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: size * 4, space: cs, bitmapInfo: info,
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }

    private static func flatten(_ m: simd_float4x4) -> [Float] {
        [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
         m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
         m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
         m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w]
    }

    private static func unflatten(_ a: [Float]) -> simd_float4x4 {
        simd_float4x4(simd_float4(a[0], a[1], a[2], a[3]),
                      simd_float4(a[4], a[5], a[6], a[7]),
                      simd_float4(a[8], a[9], a[10], a[11]),
                      simd_float4(a[12], a[13], a[14], a[15]))
    }

    private static func unflatten3(_ a: [Float]) -> simd_float3x3 {
        simd_float3x3(simd_float3(a[0], a[1], a[2]),
                      simd_float3(a[3], a[4], a[5]),
                      simd_float3(a[6], a[7], a[8]))
    }
}
