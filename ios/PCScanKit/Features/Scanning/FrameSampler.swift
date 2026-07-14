import ARKit
import CoreImage
import simd

/// Skanerlash davomida sifatli RGB keyframe'larni to'plab, Object Capture uchun
/// papkaga JPEG sifatida yozadi. Loyqa/takroriy kadrlar filtrlanadi.
final class FrameSampler {

    private let session: ARSession
    private let outputFolder: URL
    private let depthFolder: URL?
    private let denseFolder: URL?
    private(set) var depthSavedCount = 0
    private let ciContext = CIContext(options: [.priorityRequestLow: false])
    private let encodeQueue = DispatchQueue(label: "com.pcscan.frame-encode", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var lastSavedTransform: simd_float4x4?
    private var lastTickTransform: simd_float4x4?
    private(set) var savedCount = 0
    /// Saqlangan kadrlarning kamera pozitsiyalari (2-bosqich: tekstura proyeksiyasi).
    private(set) var poses: [KeyframePose] = []
    /// Zich depth-kesh pozalari (Scaniverse uslubi: HAR tick, harakat shartisiz).
    private(set) var densePoses: [KeyframePose] = []
    private var denseCount = 0
    private var tickCount = 0
    /// Zich kesh qopqog'i: 1200 × ~70-100KB (LZFSE) ≈ 100MB — 3 daqiqalik skan.
    private let maxDenseFrames = 1200

    /// Yangi kadr olish sharti: yetarli SILJISH (m) YOKI yetarli BURILISH (rad).
    /// Burilish triggeri — joyda turib devorga aylanganda ham qoplama beradi.
    private let minTranslation: Float = 0.05
    private let minRotation: Float = 0.12     // ~7°
    /// Xotira/vaqtni cheklash uchun maksimal kadr soni. Katta/detalli xonalar
    /// 400 kadrga sig'may qolardi — 600 ga oshirildi. Texrecon rasmlarni birma-bir
    /// yuklaydi, shuning uchun qo'shimcha kadrlar asosan VAQTga ta'sir qiladi.
    private let maxFrames = 600
    /// Tick oralig'i: dense kesh 6.7Hz (har tick), RGB keyframe 3.3Hz (har
    /// 2-tick) — qisqa skan ham zich depth oladi, RGB hajmi o'zgarmaydi.
    private let interval: TimeInterval = 0.15
    /// Blur filtri: bir tick ichida ruxsat etilgan maksimal siljish (m) va burilish (rad).
    /// Bundan tez harakat — loyqa kadr degani, uni tashlaymiz.
    private let maxTickTranslation: Float = 0.16
    private let maxTickRotation: Float = 0.22

    init(session: ARSession, outputFolder: URL, depthFolder: URL? = nil, denseFolder: URL? = nil) {
        self.session = session
        self.outputFolder = outputFolder
        self.depthFolder = depthFolder
        self.denseFolder = denseFolder
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Namuna olish

    private func tick() {
        guard let frame = session.currentFrame else { return }

        // Faqat barqaror tracking holatida sifatli kadr olamiz.
        guard case .normal = frame.camera.trackingState else { return }

        // ZICH depth-kesh: HAR tick'da (6.7Hz), harakat/keyframe shartisiz
        // (Scaniverse uslubi) — TSDF 10-20× ko'p kuzatuv oladi. RGB yozilmaydi.
        saveDense(frame: frame)

        // RGB keyframe mantiqiy qismi har 2-tick'da (3.3Hz — avvalgi tezlik).
        tickCount += 1
        guard tickCount % 2 == 0 else { return }

        guard savedCount < maxFrames else { return }

        let transform = frame.camera.transform
        let position = transform.columns.3
        let current = simd_float3(position.x, position.y, position.z)

        // Blur filtri: oldingi tick'ga nisbatan tez harakat = loyqa kadr → tashlaymiz.
        if let last = lastTickTransform {
            let translation = simd_distance(current, simd_float3(last.columns.3.x, last.columns.3.y, last.columns.3.z))
            let rotation = Self.rotationAngle(between: last, and: transform)
            lastTickTransform = transform
            if translation > maxTickTranslation || rotation > maxTickRotation {
                return
            }
        } else {
            lastTickTransform = transform
        }

        // Yangi nuqta yoki yangi burchak bo'lsagina saqlaymiz (siljish YOKI burilish).
        if let lastT = lastSavedTransform {
            let moved = simd_distance(current, simd_float3(lastT.columns.3.x, lastT.columns.3.y, lastT.columns.3.z))
            let turned = Self.rotationAngle(between: lastT, and: transform)
            if moved < minTranslation && turned < minRotation {
                return
            }
        }
        lastSavedTransform = transform

        // Pixel buffer'ni CIImage sifatida ushlab, fon oqimida yozamiz.
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let index = savedCount
        savedCount += 1

        // Kamera pozitsiyasini (transform + intrinsics) yozamiz.
        let resolution = frame.camera.imageResolution
        var pose = KeyframePose(
            index: index,
            transform: transform,
            intrinsics: frame.camera.intrinsics,
            width: Int(resolution.width),
            height: Int(resolution.height)
        )
        // Avto-ekspozitsiya siljishi (EV) — teksturalashda yorqinlikni
        // tenglashtirish uchun (deraza pereexposure / burchak qorayishi).
        pose.exposureOffset = frame.camera.exposureOffset

        // LiDAR depth + confidence (fusion uchun). Buffer qayta ishlatilishidan
        // oldin sinxron nusxalab, diskka fonda yozamiz.
        if let depthFolder, let sceneDepth = frame.sceneDepth {
            if let packed = Self.packDepth(sceneDepth) {
                pose.depthWidth = packed.width
                pose.depthHeight = packed.height
                depthSavedCount += 1
                let dURL = depthFolder.appendingPathComponent(String(format: "depth_%04d.bin", index))
                let cURL = depthFolder.appendingPathComponent(String(format: "conf_%04d.bin", index))
                encodeQueue.async {
                    try? packed.depth.write(to: dURL)
                    try? packed.conf.write(to: cURL)
                }
            }
        }
        poses.append(pose)

        encodeQueue.async { [ciContext, outputFolder] in
            let url = outputFolder.appendingPathComponent(String(format: "frame_%04d.jpg", index))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let options: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.9
            ]
            if let data = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options) {
                try? data.write(to: url)
            }
        }
    }

    /// Zich depth-kesh: joriy kadr depth'ini (siqib) saqlaydi — pozasi bilan.
    private func saveDense(frame: ARFrame) {
        guard let denseFolder, denseCount < maxDenseFrames,
              let sceneDepth = frame.sceneDepth,
              let packed = Self.packDepth(sceneDepth) else { return }
        let index = denseCount
        denseCount += 1

        let resolution = frame.camera.imageResolution
        var pose = KeyframePose(
            index: index,
            transform: frame.camera.transform,
            intrinsics: frame.camera.intrinsics,
            width: Int(resolution.width),
            height: Int(resolution.height)
        )
        pose.depthWidth = packed.width
        pose.depthHeight = packed.height
        densePoses.append(pose)

        encodeQueue.async {
            DenseDepthStore.save(depth: packed.depth, conf: packed.conf,
                                 width: packed.width, height: packed.height,
                                 index: index, folder: denseFolder)
        }
    }

    /// Depth (Float32 m) -> UInt16 mm va confidence -> UInt8 sifatida zichlaydi.
    private static func packDepth(_ sceneDepth: ARDepthData) -> (depth: Data, conf: Data, width: Int, height: Int)? {
        let buf = sceneDepth.depthMap
        guard CVPixelBufferGetPixelFormatType(buf) == kCVPixelFormatType_DepthFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        let w = CVPixelBufferGetWidth(buf)
        let h = CVPixelBufferGetHeight(buf)
        let stride = CVPixelBufferGetBytesPerRow(buf) / 4

        var mm = [UInt16](repeating: 0, count: w * h)
        let fp = base.assumingMemoryBound(to: Float32.self)
        for row in 0..<h {
            for col in 0..<w {
                let v = fp[row * stride + col]
                mm[row * w + col] = v.isFinite ? UInt16(min(max(v, 0), 65) * 1000) : 0
            }
        }
        let depthData = mm.withUnsafeBufferPointer { Data(buffer: $0) }

        var confData = Data(count: w * h)
        if let confMap = sceneDepth.confidenceMap {
            CVPixelBufferLockBaseAddress(confMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confMap, .readOnly) }
            if let cbase = CVPixelBufferGetBaseAddress(confMap) {
                let cstride = CVPixelBufferGetBytesPerRow(confMap)
                let cp = cbase.assumingMemoryBound(to: UInt8.self)
                confData.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
                    guard let o = out.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    for row in 0..<h {
                        for col in 0..<w {
                            o[row * w + col] = cp[row * cstride + col]
                        }
                    }
                }
            }
        }
        return (depthData, confData, w, h)
    }

    /// Ikki transform orasidagi burilish burchagi (rad).
    private static func rotationAngle(between a: simd_float4x4, and b: simd_float4x4) -> Float {
        func rotation(_ m: simd_float4x4) -> simd_quatf {
            simd_quatf(simd_float3x3(
                simd_float3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                simd_float3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                simd_float3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
            ))
        }
        let qa = rotation(a)
        let qb = rotation(b)
        let dot = min(abs(simd_dot(qa.vector, qb.vector)), 1)
        return 2 * acos(dot)
    }
}
