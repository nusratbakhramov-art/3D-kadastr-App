// Pure capture models and geometry; no camera or motion-session dependencies.
// Geometry helpers ported from Astra 0.5 ios/Uy360/CaptureGeometry.swift.
import Foundation
import simd

// MARK: - Nishonlar

/// Sferadagi bitta nishon. Burchaklar radianda; yaw 0 = dunyo −Z (ARKit'ning
/// boshlang'ich oldi), pitch + = yuqori.
struct PanoTarget: Identifiable, Hashable {
    let id: Int
    let yaw: Float
    let pitch: Float
    let optional: Bool

    var direction: SIMD3<Float> {
        SIMD3(cos(pitch) * sin(yaw), sin(pitch), -cos(pitch) * cos(yaw))
    }
}

enum PanoTargetGrid {
    /// Gorizontda 12 (30°), +45° da 8, −45° da 8, zenit ixtiyoriy. NADIR YO'Q:
    /// eng pastki qism (oyoq osti) suratga olinmaydi — tikishda o'sha joyga
    /// «3D kadastr» disk-logosi bosiladi (`PanoStitch.swift` → `nadirLogoPath`,
    /// yadro 28° qopqoqni logo bilan yopadi, −45° qatori esa 45°+34° gacha
    /// yetadi, ya'ni bo'shliq qolmaydi).
    /// Portret asosiy linza ≈ 55°×69° FOV → hamma joyda ≥30% ustma-ustlik.
    static func build() -> [PanoTarget] {
        var out: [PanoTarget] = []
        func add(_ yawDeg: Float, _ pitchDeg: Float, optional: Bool = false) {
            out.append(PanoTarget(
                id: out.count,
                yaw: yawDeg * .pi / 180,
                pitch: pitchDeg * .pi / 180,
                optional: optional
            ))
        }
        for k in 0..<12 { add(Float(k) * 30, 0) }
        for k in 0..<8 { add(Float(k) * 45 + 22.5, 45) }
        for k in 0..<8 { add(Float(k) * 45 + 22.5, -45) }
        add(0, 89, optional: true)
        return out
    }

    /// Astra 0.5 ultra-wide grid: 8 horizon + 4 upper + 4 lower + required zenith.
    /// The tilted rings use 45° yaw offsets. A dedicated ceiling frame avoids
    /// relying only on the soft outer edges of the tilted photos; no nadir shot.
    /// Astra calls this `ultraWide16`, but it includes 17 required targets.
    /// The ARKit compatibility controller retains its separate `build()` grid.
    static func ultraWide17() -> [PanoTarget] {
        var out: [PanoTarget] = []
        func add(_ yawDeg: Float, _ pitchDeg: Float) {
            out.append(PanoTarget(
                id: out.count,
                yaw: yawDeg * .pi / 180,
                pitch: pitchDeg * .pi / 180,
                optional: false
            ))
        }
        for k in 0..<8 { add(Float(k) * 45, 0) }
        for k in 0..<4 { add(Float(k) * 90 + 45, 52) }
        for k in 0..<4 { add(Float(k) * 90 + 45, -52) }
        add(0, 89) // Near-vertical zenith, matching Astra's coordinate convention.
        return out
    }
}

/// Har kadrning pozasi/intrinsics'i — `meta.json` qatori.
///
/// ⚠️ Nomlar `PanoStitch.swift` (→ `PanoCore/UyStitcher.mm`) o'qiydigan
/// nomlar; server `pano_stitch.py` ham aynan shu sxemani kutadi. `transform`
/// — camera→world 4×4, COLUMN-MAJOR.
struct PanoFrameMeta: Codable {
    var index: Int
    var targetId: Int
    var targetYaw: Float
    var targetPitch: Float
    var transform: [Float]
    var intrinsics: [Float]      // fx, fy, cx, cy — `imageWidth×imageHeight` uchun
    var imageWidth: Int          // ASL o'lcham (intrinsics shunga tegishli)
    var imageHeight: Int
    var pixelWidth: Int          // yozilgan JPEG'ning haqiqiy o'lchami
    var pixelHeight: Int
    var timestamp: Double
    /// Exposure time in seconds, optional in Astra's schema. Existing ARKit
    /// captures leave it absent; ultra-wide currently also leaves it absent,
    /// matching Astra. Pose validation uses the photo exposure timestamp.
    var exposureDuration: Double? = nil
    var highRes: Bool
    var file: String
    /// nil / "arkit": ARKit 6-DoF. "sensors:coremotion": rotation-only sensor pose.
    /// Optional so existing meta.json files decode and re-encode unchanged.
    var poseSource: String? = nil
}

// MARK: - Astra capture geometry

/// Roll has no gravity reference when the optical axis points up/down. Keep the last
/// well-defined preview angle there, and let pole captures use any roll orientation.
struct CaptureLevelState {
    private(set) var previewRoll: Float = 0

    mutating func update(forwardY: Float, gravityRoll: Float, maxRoll: Float) -> Bool {
        if abs(forwardY) > 0.9 { return true }
        previewRoll = gravityRoll
        return abs(gravityRoll) < maxRoll
    }
}

/// Motion samples and AVCapture timestamps are expressed on the host clock (seconds since boot).
/// Retain history because a quality photo can be delivered long after its exposure, or selected
/// from before the shutter request by zero shutter lag.
struct CapturePoseHistory {
    private struct Sample {
        let time: TimeInterval
        let rotation: simd_quatf
        let angularSpeed: Float
    }
    private var samples: [Sample] = []

    mutating func append(time: TimeInterval, rotation: simd_float3x3, angularSpeed: Float = 0) {
        guard time.isFinite else { return }
        if let last = samples.last, time <= last.time { return }
        samples.append(Sample(time: time, rotation: simd_quatf(rotation), angularSpeed: angularSpeed))
        samples.removeAll { $0.time < time - 10 }
    }

    /// Do not attach an old orientation to a new photo after motion updates stall.
    func rotation(at time: TimeInterval, tolerance: TimeInterval = 0.05,
                  maxAngularSpeed: Float = .infinity) -> simd_float3x3? {
        guard time.isFinite, let first = samples.first, let last = samples.last else { return nil }
        if time <= first.time {
            return first.time - time <= tolerance && first.angularSpeed <= maxAngularSpeed
                ? simd_float3x3(first.rotation) : nil
        }
        if time >= last.time {
            return time - last.time <= tolerance && last.angularSpeed <= maxAngularSpeed
                ? simd_float3x3(last.rotation) : nil
        }
        guard let upper = samples.firstIndex(where: { $0.time >= time }) else { return nil }
        let a = samples[upper - 1], b = samples[upper]
        guard b.time - a.time <= 2 * tolerance else { return nil }
        guard a.angularSpeed <= maxAngularSpeed, b.angularSpeed <= maxAngularSpeed else { return nil }
        let fraction = Float((time - a.time) / (b.time - a.time))
        return simd_float3x3(simd_slerp(a.rotation, b.rotation, fraction))
    }
}

struct CaptureIntrinsics {
    let fx: Float, fy: Float, cx: Float, cy: Float
    let width: Int, height: Int

    /// A 16:9 video stream is a centre crop of the 4:3 still. Stretching its two axes
    /// independently changes fy and bends the panorama. Undo the crop with one scale and offset.
    func forPhoto(width photoWidth: Int, height photoHeight: Int) -> [Float]? {
        guard width > 0, height > 0, photoWidth > 0, photoHeight > 0,
              [fx, fy, cx, cy].allSatisfy({ $0.isFinite }), fx > 0, fy > 0 else { return nil }
        let scale = Float(photoWidth) / Float(width)
        // This path saves full sensor 4:3 stills; don't guess for an unexpected narrower crop.
        guard Float(photoHeight) + 1 >= Float(height) * scale else { return nil }
        let offsetY = (Float(photoHeight) - Float(height) * scale) / 2
        return [fx * scale, fy * scale, cx * scale, cy * scale + offsetY]
    }
}
