import ARKit
import CoreVideo

/// Pulls the LiDAR depth + confidence buffers out of an `ARDepthData` into
/// tightly-packed `Data` blobs we can write to disk.
enum DepthExtractor {
    struct Result {
        var depth: Data          // Float32, metres, row-major width×height
        var confidence: Data?    // UInt8, ARConfidenceLevel raw values
        var width: Int
        var height: Int
    }

    static func extract(_ depthData: ARDepthData) -> Result? {
        let map = depthData.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)

        guard let depth = copyTightly(map, bytesPerPixel: 4, width: width, height: height) else {
            return nil
        }

        var confidence: Data?
        if let confMap = depthData.confidenceMap {
            confidence = copyTightly(confMap, bytesPerPixel: 1, width: width, height: height)
        }

        return Result(depth: depth, confidence: confidence, width: width, height: height)
    }

    /// Copy a pixel buffer row by row into a tightly-packed buffer (dropping any
    /// per-row padding the source may carry).
    private static func copyTightly(_ buffer: CVPixelBuffer, bytesPerPixel: Int, width: Int, height: Int) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let dstBytesPerRow = width * bytesPerPixel

        var out = Data(count: dstBytesPerRow * height)
        out.withUnsafeMutableBytes { dst in
            guard let dstBase = dst.baseAddress else { return }
            for row in 0..<height {
                memcpy(
                    dstBase.advanced(by: row * dstBytesPerRow),
                    base.advanced(by: row * srcBytesPerRow),
                    dstBytesPerRow
                )
            }
        }
        return out
    }
}
