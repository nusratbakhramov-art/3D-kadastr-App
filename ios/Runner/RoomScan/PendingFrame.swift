import ARKit
import CoreImage
import simd

/// An RGB keyframe captured mid-scan, with everything needed to project the
/// mesh back into it later. Heavy buffers are encoded immediately (ARKit reuses
/// its pixel buffers), but kept off the main `ScanManifest` until we flush to disk.
struct PendingFrame {
    let timestamp: Double
    let transform: simd_float4x4      // camera → world
    let intrinsics: simd_float3x3     // scaled to the stored JPEG
    let imageWidth: Int
    let imageHeight: Int
    let jpeg: Data
    let depth: Data?
    let confidence: Data?
    let depthWidth: Int?
    let depthHeight: Int?

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let targetWidth: CGFloat = 1024

    init?(frame: ARFrame) {
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let sourceWidth = image.extent.width
        guard sourceWidth > 0 else { return nil }

        let scale = min(1, Self.targetWidth / sourceWidth)
        let scaled = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let jpeg = Self.ciContext.jpegRepresentation(of: scaled, colorSpace: colorSpace) else {
            return nil
        }

        self.jpeg = jpeg
        self.imageWidth = Int(scaled.extent.width.rounded())
        self.imageHeight = Int(scaled.extent.height.rounded())
        self.timestamp = frame.timestamp
        self.transform = frame.camera.transform

        var k = frame.camera.intrinsics
        let s = Float(scale)
        k.columns.0.x *= s   // fx
        k.columns.1.y *= s   // fy
        k.columns.2.x *= s   // cx
        k.columns.2.y *= s   // cy
        self.intrinsics = k

        if let sceneDepth = frame.sceneDepth ?? frame.smoothedSceneDepth,
           let extracted = DepthExtractor.extract(sceneDepth) {
            self.depth = extracted.depth
            self.confidence = extracted.confidence
            self.depthWidth = extracted.width
            self.depthHeight = extracted.height
        } else {
            self.depth = nil
            self.confidence = nil
            self.depthWidth = nil
            self.depthHeight = nil
        }
    }
}
