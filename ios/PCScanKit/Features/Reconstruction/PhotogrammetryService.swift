import Foundation
import RealityKit
import CoreImage
import CoreMotion
import CoreVideo

/// M2 — Object Capture (fotogrammetriya) pipeline'i.
/// Skanerlash davomida yig'ilgan RGB kadrlardan teksturali 3D model quradi.
struct PhotogrammetryService {

    enum ServiceError: LocalizedError {
        case unsupported
        case notEnoughFrames(Int)
        case noOutput

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "Bu qurilma Object Capture'ni qo'llab-quvvatlamaydi."
            case .notEnoughFrames(let n):
                return "Tekstura uchun yetarli kadr yo'q (\(n) ta). Xonani sekinroq va to'liqroq skanerlang."
            case .noOutput:
                return "Object Capture natija bermadi."
            }
        }
    }

    /// Object Capture uchun minimal kadr soni.
    static let minimumFrames = 12

    /// Papkadagi kadrlardan teksturali modelni quradi.
    /// - Returns: yaratilgan model (USDZ) URL manzili.
    func reconstruct(
        imagesFolder: URL,
        outputURL: URL,
        detail: PhotogrammetrySession.Request.Detail = .reduced,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {

        guard PhotogrammetrySession.isSupported else {
            throw ServiceError.unsupported
        }

        let frameCount = try imageCount(in: imagesFolder)
        guard frameCount >= Self.minimumFrames else {
            throw ServiceError.notEnoughFrames(frameCount)
        }

        var configuration = PhotogrammetrySession.Configuration()
        // Kadrlar skanerlash tartibida yig'ilgani uchun sequential tezroq ishlaydi.
        configuration.sampleOrdering = .sequential
        // Kam teksturali yuzalarda (ofis devorlari) ko'proq nuqta topish uchun high.
        configuration.featureSensitivity = .high

        // Qayta ishlashda eski natijani o'chiramiz (ustidan yozish uchun).
        try? FileManager.default.removeItem(at: outputURL)

        let session = try PhotogrammetrySession(input: imagesFolder, configuration: configuration)
        try session.process(requests: [.modelFile(url: outputURL, detail: detail)])

        var producedURL: URL?
        for try await output in session.outputs {
            switch output {
            case .requestProgress(_, let fraction):
                progress(fraction)
            case .requestComplete(_, let result):
                if case .modelFile(let url) = result {
                    producedURL = url
                }
            case .processingComplete:
                if let url = producedURL ?? (FileManager.default.fileExists(atPath: outputURL.path) ? outputURL : nil) {
                    return url
                }
                throw ServiceError.noOutput
            case .requestError(_, let error):
                throw error
            case .processingCancelled:
                throw CancellationError()
            default:
                break
            }
        }
        throw ServiceError.noOutput
    }

    // MARK: - To'liq xona: depth-sample oqimi bilan (masking o'chirilgan)

    /// LiDAR depth biriktirilgan PhotogrammetrySample oqimi bilan TO'LIQ XONA quradi.
    /// isObjectMaskingEnabled=false — "obyektga kesish" o'chiriladi.
    func reconstructFullRoom(
        paths: ScanPaths,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard PhotogrammetrySession.isSupported else { throw ServiceError.unsupported }

        let posesData = try Data(contentsOf: paths.framesJSON)
        let poses = try JSONDecoder().decode([KeyframePose].self, from: posesData)
            .filter { $0.depthWidth != nil }
        guard poses.count >= Self.minimumFrames else {
            throw ServiceError.notEnoughFrames(poses.count)
        }

        var configuration = PhotogrammetrySession.Configuration()
        configuration.sampleOrdering = .sequential
        configuration.featureSensitivity = .high
        configuration.isObjectMaskingEnabled = false

        try? FileManager.default.removeItem(at: paths.modelURL)

        let stream = SampleStream(poses: poses, paths: paths)
        let session = try PhotogrammetrySession(input: stream, configuration: configuration)
        try session.process(requests: [.modelFile(url: paths.modelURL, detail: .reduced)])

        var producedURL: URL?
        for try await output in session.outputs {
            switch output {
            case .requestProgress(_, let fraction):
                progress(fraction)
            case .requestComplete(_, let result):
                if case .modelFile(let url) = result { producedURL = url }
            case .processingComplete:
                if let url = producedURL ?? (FileManager.default.fileExists(atPath: paths.modelURL.path) ? paths.modelURL : nil) {
                    return url
                }
                throw ServiceError.noOutput
            case .requestError(_, let error):
                throw error
            case .processingCancelled:
                throw CancellationError()
            default:
                break
            }
        }
        throw ServiceError.noOutput
    }

    /// Kadrlarni bittalab (lazy) beruvchi oqim — xotirani tejaydi.
    private struct SampleStream: Sequence {
        let poses: [KeyframePose]
        let paths: ScanPaths

        func makeIterator() -> Iterator {
            Iterator(poses: poses, paths: paths)
        }

        struct Iterator: IteratorProtocol {
            let poses: [KeyframePose]
            let paths: ScanPaths
            var index = 0
            let ciContext = CIContext(options: [.cacheIntermediates: false])

            mutating func next() -> PhotogrammetrySample? {
                while index < poses.count {
                    let pose = poses[index]
                    index += 1
                    var result: PhotogrammetrySample?
                    autoreleasepool {
                        let imgURL = paths.imagesFolder
                            .appendingPathComponent(String(format: "frame_%04d.jpg", pose.index))
                        guard let image = Self.imageBuffer(imgURL, ciContext: ciContext) else { return }
                        var sample = PhotogrammetrySample(id: pose.index, image: image)

                        if let dw = pose.depthWidth, let dh = pose.depthHeight {
                            let dURL = paths.depthFolder
                                .appendingPathComponent(String(format: "depth_%04d.bin", pose.index))
                            sample.depthDataMap = Self.depthBuffer(dURL, width: dw, height: dh)
                        }
                        // gravity kamera fazosida: g_cam = R^T * (0,-1,0)
                        let t = pose.transform
                        sample.gravity = CMAcceleration(x: Double(-t[1]), y: Double(-t[5]), z: Double(-t[9]))
                        result = sample
                    }
                    if let result { return result }
                }
                return nil
            }

            static func imageBuffer(_ url: URL, ciContext: CIContext) -> CVPixelBuffer? {
                guard let ci = CIImage(contentsOf: url) else { return nil }
                let w = Int(ci.extent.width), h = Int(ci.extent.height)
                var pb: CVPixelBuffer?
                CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA,
                                    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
                guard let buffer = pb else { return nil }
                ciContext.render(ci, to: buffer)
                return buffer
            }

            static func depthBuffer(_ url: URL, width: Int, height: Int) -> CVPixelBuffer? {
                guard let data = try? Data(contentsOf: url), data.count == width * height * 2 else { return nil }
                var pb: CVPixelBuffer?
                CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_DepthFloat32, nil, &pb)
                guard let buffer = pb else { return nil }
                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
                let stride = CVPixelBufferGetBytesPerRow(buffer) / 4
                let dst = base.assumingMemoryBound(to: Float32.self)
                data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    let mm = raw.bindMemory(to: UInt16.self)
                    for r in 0..<height {
                        for c in 0..<width {
                            let v = mm[r * width + c]
                            dst[r * stride + c] = v == 0 ? Float.nan : Float(v) / 1000
                        }
                    }
                }
                return buffer
            }
        }
    }

    private func imageCount(in folder: URL) throws -> Int {
        let items = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )
        return items.filter { $0.pathExtension.lowercased() == "jpg" }.count
    }
}
