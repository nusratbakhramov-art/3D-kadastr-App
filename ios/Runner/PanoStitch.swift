//
//  PanoStitch.swift — 360° panoramani TELEFONNING O'ZIDA tikish.
//
//  Both capture paths save frames and metadata in Application Support/pano/<uuid>.
//  Astra 0.5 PanoCore (via UyStitcher.mm) produces pano.jpg + preview.jpg locally.
//  Both JPEGs are validated before publication; Dart uploads only pano.jpg.
//
//  Exact poseSource "sensors:coremotion" selects high-quality sensor BA/MVS,
//  planar/structural processing and 6144×3072 output. Weak reconstruction falls
//  back to rotation. Legacy ARKit keeps 4096×2048 and auto/mvs/fast selection;
//  auto selects MVS at ≥5.5 GB RAM. Capture count never selects the pipeline.
//  Device performance for the integrated ultra-wide path still needs measurement.
//
//  Progress Dart'ga o'sha `kadastr/pano_capture` kanali orqali TESKARI
//  yo'nalishda keladi: `progress {p, msg}` (asosiy oqimda, ≥ 150 ms oraliq).
//  Tikish davomida ekran o'chmaydi (`isIdleTimerDisabled`).
//

import Flutter
import Foundation
import ImageIO
import UIKit

@available(iOS 15.0, *)
final class PanoStitchCoordinator {
    static let shared = PanoStitchCoordinator()

    /// Bir vaqtda BITTA tikish — yadro ikkita yadroni to'liq band qiladi va
    /// ikkinchisi xotirani ikki barobar oshirardi.
    private var running = false

    /// "auto" rejimda MVS uchun minimal RAM. iPhone 13 Pro / 14 va yuqorisi
    /// 6 GB; iPhone 12/13 (4 GB) da MVS cho'qqisi jetsam chegarasiga yaqin.
    private static let mvsMinRAM: UInt64 = 5_500_000_000

    static func resolveMode(_ requested: String?,
                            physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        switch requested ?? "auto" {
        case "mvs": return "mvs"
        case "fast": return "fast"
        default:
            return physicalMemory >= mvsMinRAM ? "mvs" : "fast"
        }
    }

    struct ProcessingOptions {
        let sensorPoses: Bool
        let highQuality: Bool
        let width: Int
        let mode: String

        init(metas: [PanoFrameMeta], width: Int? = nil, mode: String? = nil,
             physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
            // Saved pose provenance, never the number of shots, selects the pipeline.
            sensorPoses = metas.contains { $0.poseSource == "sensors:coremotion" }
            highQuality = sensorPoses
            self.width = width.flatMap { $0 > 0 ? $0 : nil } ?? (sensorPoses ? 6144 : 4096)
            // Sensor BA decides whether images support translation/depth. The core
            // retains sensor orientations and falls back to rotation when they do not.
            self.mode = sensorPoses ? "mvs" : resolveMode(mode, physicalMemory: physicalMemory)
        }
    }

    /// `args`: `dir` (majburiy), `width` (ARKit 4096 / CoreMotion 6144),
    /// `mode` (auto|mvs|fast, legacy ARKit only),
    /// `logoAsset` (ixtiyoriy — Flutter asset kaliti, nadir'ga bosiladigan disk).
    func stitch(args: [String: Any]?, channel: FlutterMethodChannel, result: @escaping FlutterResult) {
        guard !running else {
            result(FlutterError(code: "BUSY", message: "Tikish allaqachon ketmoqda", details: nil))
            return
        }
        guard let dirPath = args?["dir"] as? String, !dirPath.isEmpty else {
            result(FlutterError(code: "ARGS", message: "`dir` berilmadi", details: nil))
            return
        }
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        let metaURL = dir.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let metas = try? JSONDecoder().decode([PanoFrameMeta].self, from: data),
              !metas.isEmpty else {
            result(FlutterError(code: "NO_FRAMES", message: "meta.json topilmadi yoki bo'sh", details: nil))
            return
        }

        let options = ProcessingOptions(metas: metas, width: args?["width"] as? Int,
                                        mode: args?["mode"] as? String)
        let logoPath = (args?["logoAsset"] as? String).flatMap { Self.bundlePath(forFlutterAsset: $0) }

        // `UyStitcher` kutadigan shakl: {path, transform[16], intrinsics[4],
        // imageWidth, imageHeight, targetPitch}. Diskda yo'q kadrlar tashlanadi
        // (undo yoki yarim yozilgan fayl).
        let frames: [[String: Any]] = metas.compactMap { m in
            let path = dir.appendingPathComponent(m.file).path
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return [
                "path": path,
                "transform": m.transform,
                "intrinsics": m.intrinsics,
                "imageWidth": m.imageWidth,
                "imageHeight": m.imageHeight,
                "targetPitch": m.targetPitch,
            ]
        }
        guard frames.count >= 4 else {
            result(FlutterError(code: "NO_FRAMES", message: "Kadrlar yetarli emas (\(frames.count))", details: nil))
            return
        }

        let pano = dir.appendingPathComponent("pano.jpg").path
        let preview = dir.appendingPathComponent("preview.jpg").path

        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        let started = Date()

        // Progress — asosiy oqimga, siyraklashtirilgan: yadro ~200 marta
        // chaqiradi, Dart esa har birini qayta chizishi shart emas.
        var lastSent = Date.distantPast
        var lastMsg = ""
        let progress: (Float, String) -> Void = { p, msg in
            let now = Date()
            guard msg != lastMsg || now.timeIntervalSince(lastSent) >= 0.15 || p >= 1 else { return }
            lastSent = now
            lastMsg = msg
            DispatchQueue.main.async {
                channel.invokeMethod("progress", arguments: ["p": Double(p), "msg": msg])
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let work = dir.appendingPathComponent(".stitch-\(UUID().uuidString)", isDirectory: true)
            var r: [String: Any]
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: work) }
                r = Self.run(options: options, frames: frames, pano: work.appendingPathComponent("pano.jpg").path,
                             preview: work.appendingPathComponent("preview.jpg").path,
                             logoPath: logoPath, progress: progress)
                if r["ok"] as? Bool == true {
                    try Self.publishOutput(from: work, to: dir, width: r["width"] as? Int ?? 0)
                }
            } catch {
                r = ["ok": false, "error": error.localizedDescription]
            }
            let wall = Date().timeIntervalSince(started)
            DispatchQueue.main.async {
                self?.running = false
                UIApplication.shared.isIdleTimerDisabled = false
                let ok = (r["ok"] as? Bool) == true
                guard ok, FileManager.default.fileExists(atPath: pano) else {
                    var err = "Tikish muvaffaqiyatsiz"
                    if let e = r["error"] as? String, !e.isEmpty { err = e }
                    result(FlutterError(code: "STITCH_FAILED", message: err, details: nil))
                    return
                }
                result(Self.payload(r, pano: pano, preview: preview, frames: frames.count,
                                    seconds: wall, mode: options.mode))
            }
        }
    }

    /// Publish only complete JPEGs. pano.jpg is the final commit point, so an
    /// interrupted native encoder cannot leave a partial result for draft resume.
    static func publishOutput(from work: URL, to dir: URL, width: Int) throws {
        guard width > 0, completeJPEG(work.appendingPathComponent("pano.jpg"), width: width, height: width / 2),
              completeJPEG(work.appendingPathComponent("preview.jpg"), width: 1024, height: 512) else {
            throw NSError(domain: "PanoStitch", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Panorama JPEG outputs are incomplete"])
        }
        for name in ["preview.jpg", "pano.jpg"] {
            try Data(contentsOf: work.appendingPathComponent(name), options: .mappedIfSafe)
                .write(to: dir.appendingPathComponent(name), options: .atomic)
        }
    }

    private static func completeJPEG(_ url: URL, width: Int, height: Int) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.starts(with: [0xff, 0xd8]), data.suffix(2).elementsEqual([0xff, 0xd9]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              props[kCGImagePropertyPixelWidth] as? Int == width,
              props[kCGImagePropertyPixelHeight] as? Int == height else { return false }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
        ] as CFDictionary) != nil
    }

    private static func run(options: ProcessingOptions, frames: [[String: Any]], pano: String,
                            preview: String, logoPath: String?,
                            progress: @escaping (Float, String) -> Void) -> [String: Any] {
        if options.mode == "mvs" {
            return UyStitcher.stitchMVSFrames(frames, width: Int32(options.width),
                                              highQuality: options.highQuality,
                                              sensorPoses: options.sensorPoses,
                                              panoPath: pano, previewPath: preview,
                                              logoPath: logoPath, progress: progress)
        }
        return UyStitcher.stitchFrames(frames, width: Int32(options.width), panoPath: pano,
                                       previewPath: preview, logoPath: logoPath, progress: progress)
    }

    private static func payload(_ r: [String: Any], pano: String, preview: String, frames: Int,
                                seconds: Double, mode: String) -> [String: Any] {
        var out: [String: Any] = [:]
        out["pano"] = pano
        out["preview"] = preview
        out["width"] = r["width"] as? Int ?? 0
        out["height"] = r["height"] as? Int ?? 0
        out["frames"] = r["frames"] as? Int ?? frames
        out["coverage"] = r["coverage"] as? Double ?? 0.0
        out["seconds"] = seconds
        out["mode"] = mode
        out["baSeconds"] = r["baSeconds"] as? Double ?? 0.0
        out["mvsSeconds"] = r["mvsSeconds"] as? Double ?? 0.0
        out["stitchSeconds"] = r["stitchSeconds"] as? Double ?? 0.0
        return out
    }

    /// Flutter asset kaliti (`assets/branding/x.png`) → bundle'dagi fayl yo'li.
    private static func bundlePath(forFlutterAsset key: String) -> String? {
        let lookup = FlutterDartProject.lookupKey(forAsset: key)
        guard let path = Bundle.main.path(forResource: lookup, ofType: nil),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
}
