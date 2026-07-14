import Foundation
import Metal
import MetalKit
import simd

/// 3D Gaussian splat forward renderer (MTKView). Splatlarni billboard sifatida
/// chizadi, chuqurlik bo'yicha (back-to-front) saralab alpha-blend qiladi.
/// Orbit kamera bilan ko'riladi.
final class SplatRenderer: NSObject, MTKViewDelegate {

    private struct Uniforms {
        var view: matrix_float4x4
        var proj: SIMD4<Float>     // fx, fy, cx, cy
        var viewport: SIMD2<Float>
        var pad: SIMD2<Float>
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private let splatBuffer: MTLBuffer
    private var indexBuffer: MTLBuffer
    private let splatCount: Int
    private let positions: [SIMD3<Float>]

    // Orbit kamera
    var azimuth: Float = 0.6
    var elevation: Float = 0.3
    var distance: Float = 4
    private let center: SIMD3<Float>

    private var sorting = false
    private var lastSortAz: Float = .greatestFiniteMagnitude
    private var lastSortEl: Float = .greatestFiniteMagnitude

    init?(device: MTLDevice, model: GaussianSplatModel) {
        guard !model.splats.isEmpty,
              let queue = device.makeCommandQueue(),
              let library = device.scansKitDefaultLibrary(),
              let vfn = library.makeFunction(name: "splatVertex"),
              let ffn = library.makeFunction(name: "splatFragment")
        else { return nil }
        self.device = device
        self.queue = queue
        self.splatCount = model.splats.count

        // Splat buferi: 14 float/splat [pos3, logScale3, rot4, opacity1, shDC3]
        var flat = [Float](); flat.reserveCapacity(model.splats.count * 14)
        var pos = [SIMD3<Float>](); pos.reserveCapacity(model.splats.count)
        for s in model.splats {
            flat.append(s.position.x); flat.append(s.position.y); flat.append(s.position.z)
            flat.append(s.scale.x); flat.append(s.scale.y); flat.append(s.scale.z)
            flat.append(s.rotation.x); flat.append(s.rotation.y); flat.append(s.rotation.z); flat.append(s.rotation.w)
            flat.append(s.opacity)
            flat.append(s.shDC.x); flat.append(s.shDC.y); flat.append(s.shDC.z)
            pos.append(s.position)
        }
        self.positions = pos
        guard let sb = device.makeBuffer(bytes: flat, length: flat.count * 4, options: .storageModeShared),
              let ib = device.makeBuffer(length: model.splats.count * 4, options: .storageModeShared)
        else { return nil }
        self.splatBuffer = sb
        self.indexBuffer = ib
        // Boshlang'ich indekslar (0..n)
        let ip = ib.contents().bindMemory(to: UInt32.self, capacity: model.splats.count)
        for i in 0..<model.splats.count { ip[i] = UInt32(i) }

        // Markaz (bbox)
        var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var mx = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in pos { mn = simd_min(mn, p); mx = simd_max(mx, p) }
        self.center = (mn + mx) / 2
        self.distance = max(1, simd_length(mx - mn) * 0.9)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Premultiplied over-blend
        let att = desc.colorAttachments[0]!
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .one
        att.sourceAlphaBlendFactor = .one
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipe = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.pipeline = pipe
        super.init()
    }

    // MARK: - Kamera / sort

    private func viewMatrix() -> matrix_float4x4 {
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)
        let eye = center + SIMD3<Float>(x, y, z)
        return lookAt(eye: eye, target: center, up: SIMD3<Float>(0, 1, 0))
    }

    private func maybeSort(_ view: matrix_float4x4) {
        // Kamera sezilarli o'zgarganda fonda qayta saralaymiz
        if sorting { return }
        if abs(azimuth - lastSortAz) < 0.03 && abs(elevation - lastSortEl) < 0.03 { return }
        sorting = true
        lastSortAz = azimuth; lastSortEl = elevation
        let pos = positions
        let count = splatCount
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            // Chuqurlik = -(view*p).z; back-to-front = katta chuqurlik oldin
            var order = [(UInt32, Float)]()
            order.reserveCapacity(count)
            let r2 = view.columns.2
            let t = view.columns.3
            for i in 0..<count {
                let p = pos[i]
                let z = r2.x * p.x + r2.y * p.y + r2.z * p.z + t.z
                order.append((UInt32(i), z))  // z manfiy; kichikroq z = uzoqroq
            }
            order.sort { $0.1 < $1.1 }  // eng uzoq (eng manfiy) oldin
            let ip = indexBuffer.contents().bindMemory(to: UInt32.self, capacity: count)
            for i in 0..<count { ip[i] = order[i].0 }
            sorting = false
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer() else { return }

        let vm = viewMatrix()
        maybeSort(vm)

        let w = Float(view.drawableSize.width), h = Float(view.drawableSize.height)
        let focal = h * 1.2
        var uniforms = Uniforms(
            view: vm,
            proj: SIMD4<Float>(focal, focal, w / 2, h / 2),
            viewport: SIMD2<Float>(w, h),
            pad: .zero
        )

        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(splatBuffer, offset: 0, index: 0)
        enc.setVertexBuffer(indexBuffer, offset: 0, index: 1)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: splatCount)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}

// MARK: - Matritsa yordamchilari

private func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    let f = simd_normalize(target - eye)
    let s = simd_normalize(simd_cross(f, up))
    let u = simd_cross(s, f)
    // world → camera (kamera -Z ga qaraydi)
    return matrix_float4x4(columns: (
        SIMD4<Float>(s.x, u.x, -f.x, 0),
        SIMD4<Float>(s.y, u.y, -f.y, 0),
        SIMD4<Float>(s.z, u.z, -f.z, 0),
        SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
    ))
}
