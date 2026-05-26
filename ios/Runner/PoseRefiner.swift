// PoseRefiner — Phase 4: Bundle Adjustment infrastructure.
//
// Phase 4.1 (HOZIR): Loop closure detection via Apple Vision feature prints
//   - Har photo uchun feature signature
//   - Visual o'xshashlik orqali "bir xil joy" candidates
//   - ARKit pose'lar bilan solishtirish → drift detect
//   - Faqat diagnostic log, hech narsa o'zgartirmaydi
//
// Phase 4.2: Feature matching (ORB) + relative pose computation
// Phase 4.3: Pose graph optimization (Ceres yoki Gauss-Newton)
// Phase 4.4: Refined poses integration

import Foundation
import Vision
import simd
import CoreGraphics
import ImageIO

struct PhotoPoseSample {
    let index: Int                // sequence index (time proxy)
    let imageURL: URL
    let pose: simd_float4x4       // camera → world (ARKit)
    var position: SIMD3<Float> {
        return SIMD3<Float>(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
    }
}

struct LoopClosureCandidate {
    let photoA: Int               // sequence index A
    let photoB: Int               // sequence index B
    let visualDistance: Float     // 0 = identical, higher = more different
    let arkitPositionDelta: Float // meters between ARKit poses
    let indexGap: Int             // sequence gap (time proxy)
}

enum PoseRefiner {
    /// Phase 4.1 — Loop closure detection only. Apple Vision feature prints
    /// orqali photo o'xshashligini hisoblaydi. Photo'lar **vaqtda uzoq** (gap
    /// >50) lekin **ARKit'da yaqin** (<1.5m) bo'lsa → camera shu joyga qaytib
    /// kelgan. Visual similarity yuqori bo'lsa, loop closure candidate.
    ///
    /// Hozirgi versiya pose'ni o'zgartirmaydi — faqat detection + log.
    static func detectLoopClosures(
        photos: [PhotoPoseSample],
        minIndexGap: Int = 50,
        maxArkitDistance: Float = 1.5,
        maxVisualDistance: Float = 1.0,
        progress: ((Float, String) -> Void)? = nil,
    ) async -> [LoopClosureCandidate] {
        guard photos.count >= 2 else { return [] }

        progress?(0.0, "Feature prints \(photos.count) ta photo'dan…")

        // 1. Extract feature prints (sequential — Apple Vision ~50ms/photo)
        let prints = await extractFeaturePrints(photos: photos, progress: progress)

        progress?(0.5, "Loop closure analyzer…")

        // 2. Pairwise distance matrix — faqat kerakli pair'lar
        var candidates: [LoopClosureCandidate] = []
        for i in 0..<(photos.count - minIndexGap) {
            guard let pi = prints[i] else { continue }
            for j in (i + minIndexGap)..<photos.count {
                guard let pj = prints[j] else { continue }

                let posDelta = simd_distance(photos[i].position, photos[j].position)
                if posDelta > maxArkitDistance { continue }

                var distance: Float = 0
                do {
                    try pi.computeDistance(&distance, to: pj)
                } catch {
                    continue
                }
                if distance > maxVisualDistance { continue }

                candidates.append(LoopClosureCandidate(
                    photoA: photos[i].index,
                    photoB: photos[j].index,
                    visualDistance: distance,
                    arkitPositionDelta: posDelta,
                    indexGap: j - i,
                ))
            }
        }

        progress?(1.0, "Loop detection ✓")
        return candidates
    }

    /// Diagnostic helper — loop closure'lardan drift statistikasini hisoblaydi.
    static func driftDiagnostic(_ loops: [LoopClosureCandidate]) -> String {
        guard !loops.isEmpty else { return "No loop closures detected" }
        let distances = loops.map { $0.arkitPositionDelta }
        let avgDelta = distances.reduce(0, +) / Float(distances.count)
        let maxDelta = distances.max() ?? 0
        let minDelta = distances.min() ?? 0
        return String(
            format: "%d loops, ARKit pose delta: min=%.1fcm avg=%.1fcm max=%.1fcm",
            loops.count, minDelta * 100, avgDelta * 100, maxDelta * 100,
        )
    }

    // MARK: - Internals

    private static func extractFeaturePrints(
        photos: [PhotoPoseSample],
        progress: ((Float, String) -> Void)?,
    ) async -> [VNFeaturePrintObservation?] {
        var prints: [VNFeaturePrintObservation?] = Array(repeating: nil, count: photos.count)
        for (i, photo) in photos.enumerated() {
            autoreleasepool {
                guard let cg = loadCGImage(url: photo.imageURL) else { return }
                let request = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do {
                    try handler.perform([request])
                    if let obs = request.results?.first as? VNFeaturePrintObservation {
                        prints[i] = obs
                    }
                } catch {
                    NSLog("KADASTR feature print failed #\(i): \(error.localizedDescription)")
                }
            }
            if i % 20 == 0 {
                progress?(0.05 + 0.40 * Float(i) / Float(max(photos.count, 1)),
                          "Feature prints \(i + 1)/\(photos.count)")
            }
        }
        return prints
    }

    private static func loadCGImage(url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
