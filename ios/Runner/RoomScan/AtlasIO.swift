import Foundation
import simd
import CoreGraphics
import ImageIO
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Persists an `AtlasTexturedMesh`: geometry (positions/normals/uvs/indices) as a
/// compact binary, and the atlas image as a PNG. Lets the result viewer reopen a
/// textured scan without re-baking.
enum AtlasIO {
    // MARK: - Geometry binary
    // Layout: uint32 vertexCount, indexCount, atlasSize
    //   vertexCount × SIMD3<Float> positions, × SIMD3<Float> normals, × SIMD2<Float> uvs
    //   indexCount  × UInt32 indices

    static func writeGeometry(_ mesh: AtlasTexturedMesh, to url: URL) throws {
        var data = Data()
        var vc = UInt32(mesh.positions.count)
        var ic = UInt32(mesh.indices.count)
        var asz = UInt32(mesh.atlasSize)
        withUnsafeBytes(of: &vc) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &ic) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &asz) { data.append(contentsOf: $0) }
        mesh.positions.withUnsafeBytes { data.append(contentsOf: $0) }
        mesh.normals.withUnsafeBytes { data.append(contentsOf: $0) }
        mesh.uvs.withUnsafeBytes { data.append(contentsOf: $0) }
        mesh.indices.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url)
    }

    static func read(geometry geometryURL: URL, atlas atlasURL: URL) throws -> AtlasTexturedMesh {
        let data = try Data(contentsOf: geometryURL)
        let vec3 = MemoryLayout<SIMD3<Float>>.stride
        let vec2 = MemoryLayout<SIMD2<Float>>.stride

        let parsed: (pos: [SIMD3<Float>], nrm: [SIMD3<Float>], uv: [SIMD2<Float>], idx: [UInt32], size: Int) =
        data.withUnsafeBytes { raw in
            var off = 0
            func u32() -> Int { let v = raw.loadUnaligned(fromByteOffset: off, as: UInt32.self); off += 4; return Int(v) }
            let vc = u32(), ic = u32(), asz = u32()
            func v3(_ n: Int) -> [SIMD3<Float>] {
                var a = [SIMD3<Float>](repeating: .zero, count: n)
                for i in 0..<n { a[i] = raw.loadUnaligned(fromByteOffset: off + i * vec3, as: SIMD3<Float>.self) }
                off += n * vec3; return a
            }
            let pos = v3(vc), nrm = v3(vc)
            var uv = [SIMD2<Float>](repeating: .zero, count: vc)
            for i in 0..<vc { uv[i] = raw.loadUnaligned(fromByteOffset: off + i * vec2, as: SIMD2<Float>.self) }
            off += vc * vec2
            var idx = [UInt32](repeating: 0, count: ic)
            for i in 0..<ic { idx[i] = raw.loadUnaligned(fromByteOffset: off + i * 4, as: UInt32.self) }
            return (pos, nrm, uv, idx, asz)
        }

        let (rgba, size) = try decodeRGBA(atlasURL)
        return AtlasTexturedMesh(
            positions: parsed.pos, normals: parsed.nrm, uvs: parsed.uv, indices: parsed.idx,
            atlas: rgba, atlasSize: size > 0 ? size : parsed.size
        )
    }

    // MARK: - PNG

    static func writePNG(rgba: [UInt8], size: Int, to url: URL) throws {
        guard let image = makeCGImage(rgba: rgba, width: size, height: size) else {
            throw NSError(domain: "AtlasIO", code: 1)
        }
        let type = pngTypeIdentifier()
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw NSError(domain: "AtlasIO", code: 2)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "AtlasIO", code: 3) }
    }

    /// Build a CGImage from tightly-packed RGBA (alpha ignored — opaque texture).
    /// The pointer must stay valid while `makeImage` reads it, so do both inside
    /// `withUnsafeMutableBytes` (an `&array` temporary would dangle).
    static func makeCGImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        var pixels = rgba
        let cs = CGColorSpaceCreateDeviceRGB()
        return pixels.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let ctx = CGContext(
                data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: cs,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }

    private static func decodeRGBA(_ url: URL) throws -> (rgba: [UInt8], size: Int) {
        guard let data = try? Data(contentsOf: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "AtlasIO", code: 4)
        }
        let w = img.width, h = img.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        // `ctx.draw` writes AFTER the context is created, so the backing pointer
        // must remain valid across both calls — `CGContext(data: &rgba)` would
        // dangle by the time draw runs, leaving the buffer all-zero (black).
        let ok: Bool = rgba.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(
                data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: cs,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw NSError(domain: "AtlasIO", code: 5) }
        return (rgba, w)
    }

    private static func pngTypeIdentifier() -> CFString {
        #if canImport(UniformTypeIdentifiers)
        if #available(iOS 14.0, macOS 11.0, *) { return UTType.png.identifier as CFString }
        #endif
        return "public.png" as CFString
    }
}
