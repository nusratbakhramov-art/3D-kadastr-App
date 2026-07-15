import Foundation
import Metal
import UIKit
import simd

/// Tekstura atlasini Metal GPU'da pishiradi: har keyframe uchun bitta render
/// pass — o'z face'larini atlas UV bo'yicha rasterizatsiya qiladi, fragment
/// shader world→keyframe proyeksiya qilib rangni sample qiladi (occlusion +
/// gain + chok-tuzatish bilan). CPU software rasterizerdan ancha tez, 8K atlasni
/// ochadi.
enum MetalTextureBaker {

    struct Output {
        let pixels: [UInt8]  // RGBA, row0 = tepa
        let filled: [Bool]
    }

    private struct Uniforms {
        var invTransform: matrix_float4x4
        var intrinsics: SIMD4<Float>  // fx, fy, cx, cy
        var sizes: SIMD4<Float>       // imageW, imageH, depthW, depthH
        var gain: SIMD4<Float>        // gain.rgb, pad
    }

    static func bake(
        positions: [SIMD3<Float>],
        atlasUVs: [SIMD2<Float>],
        indices: [UInt32],
        faceLabels: [Int32],
        corrections: [SIMD3<Float>],
        keyframes: [KeyframeStore.Keyframe],
        gains: [Int: ColorGains],
        width: Int, height: Int
    ) -> Output? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.scansKitDefaultLibrary(),
              let vfn = library.makeFunction(name: "meshBakeVertex"),
              let ffn = library.makeFunction(name: "meshBakeFragment")
        else { return nil }

        // A12+ qurilmalarda 2D tekstura maksimumi 16384 — 8192 xavfsiz
        guard width <= 16384, height <= 16384 else { return nil }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = vfn
        pipeDesc.fragmentFunction = ffn
        pipeDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: pipeDesc) else { return nil }

        // Render target
        let targetDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        targetDesc.usage = [.renderTarget, .shaderRead]
        targetDesc.storageMode = .shared
        guard let target = device.makeTexture(descriptor: targetDesc) else { return nil }

        // Face'larni label bo'yicha guruhlaymiz
        let faceCount = indices.count / 3
        var facesByLabel: [Int32: [Int]] = [:]
        for f in 0..<faceCount where faceLabels[f] >= 0 {
            facesByLabel[faceLabels[f], default: []].append(f)
        }
        guard !facesByLabel.isEmpty else { return nil }

        let labelsSorted = facesByLabel.keys.sorted()
        var first = true

        for label in labelsSorted {
            guard let faces = facesByLabel[label], !faces.isEmpty else { continue }
            let kf = keyframes[Int(label)]

            // Vertex buferi: 8 float × 3 × faceCount [atlasUV, worldPos, correction]
            var verts = [Float]()
            verts.reserveCapacity(faces.count * 24)
            for f in faces {
                for c in 0..<3 {
                    let vi = Int(indices[f * 3 + c])
                    let uv = atlasUVs[vi]
                    let p = positions[vi]
                    let corr = corrections[f * 3 + c]
                    verts.append(uv.x); verts.append(uv.y)
                    verts.append(p.x); verts.append(p.y); verts.append(p.z)
                    verts.append(corr.x); verts.append(corr.y); verts.append(corr.z)
                }
            }
            guard let vbuf = device.makeBuffer(
                bytes: verts, length: verts.count * MemoryLayout<Float>.size, options: .storageModeShared
            ) else { continue }

            guard let colorTex = makeColorTexture(kf, device: device, targetWidth: 1440),
                  let depthTex = makeDepthTexture(kf, device: device)
            else { continue }

            let g = gains[Int(label)] ?? ColorGains()
            var uniforms = Uniforms(
                invTransform: kf.transform.inverse,
                intrinsics: SIMD4<Float>(kf.intrinsics[0][0], kf.intrinsics[1][1], kf.intrinsics[2][0], kf.intrinsics[2][1]),
                sizes: SIMD4<Float>(Float(kf.width), Float(kf.height), Float(kf.depthWidth), Float(kf.depthHeight)),
                gain: SIMD4<Float>(g.r, g.g, g.b, 0)
            )

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = first ? .clear : .load
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            first = false

            guard let cmd = queue.makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(vbuf, offset: 0, index: 0)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.setFragmentTexture(colorTex, index: 0)
            enc.setFragmentTexture(depthTex, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count / 8)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
        }

        if first { return nil }  // hech narsa chizilmadi

        // Readback
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let region = MTLRegionMake2D(0, 0, width, height)
        pixels.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: width * 4, from: region, mipmapLevel: 0)
        }

        var filled = [Bool](repeating: false, count: width * height)
        for i in 0..<(width * height) where pixels[i * 4 + 3] > 0 {
            filled[i] = true
        }

        return Output(pixels: pixels, filled: filled)
    }

    // MARK: - Texture upload

    private static func makeColorTexture(
        _ kf: KeyframeStore.Keyframe, device: MTLDevice, targetWidth: Int
    ) -> MTLTexture? {
        guard let uiImage = UIImage(data: kf.jpegData), let cgImage = uiImage.cgImage else { return nil }
        let w = min(targetWidth, cgImage.width)
        let h = max(1, cgImage.height * w / cgImage.width)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false
        )
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: pixels, bytesPerRow: w * 4)
        return tex
    }

    private static func makeDepthTexture(
        _ kf: KeyframeStore.Keyframe, device: MTLDevice
    ) -> MTLTexture? {
        guard let depth = kf.depthMap, kf.depthWidth > 0, kf.depthHeight > 0 else {
            // Depth yo'q bo'lsa — 1×1 nol texture (occlusion o'chirilgan)
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false
            )
            desc.usage = .shaderRead
            guard let tex = device.makeTexture(descriptor: desc) else { return nil }
            var zero: Float = 0
            tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 4)
            return tex
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: kf.depthWidth, height: kf.depthHeight, mipmapped: false
        )
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        depth.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, kf.depthWidth, kf.depthHeight),
                        mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: kf.depthWidth * 4)
        }
        return tex
    }
}
