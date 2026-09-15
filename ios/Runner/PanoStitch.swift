//
//  PanoStitch.swift — 360° panoramani TELEFONNING O'ZIDA tikish.
//
//  `PanoCapture.swift` yozgan `tmp/pano/<uuid>/{frame_N.jpg, meta.json}` ni
//  `PanoCore/` (Uy360 C++ yadrosi, `UyStitcher.mm` ko'prigi) bilan tikadi va
//  `pano.jpg` + `preview.jpg` ni o'sha katalogga yozadi. Dart tayyor faylni
//  `POST /listings/media role=panorama` ga yuklaydi — SERVERDA TIKISH YO'Q.
//
//  Nega telefonda: prodda server tikishi 7–9 daqiqa olardi (celery-panorama
//  o'lchovi, 2026-09-12); yadro iPhone 14 Pro'da MVS "tez" preset bilan
//  ~1.5–2 daqiqa, rotatsiya-only rejimda 30–90 s.
//
//  Rejimlar (`mode`):
//    "mvs"  — BA (pozalar) → plane-sweep chuqurlik → chuqurlik bo'yicha
//             reproyeksiya. Parallaks (devor/eshik chetlari chokda uzilishi)
//             yo'qoladi. Xotira cho'qqisi ~1 GB.
//    "fast" — faqat rotatsiya (SIFT refine + graph-cut chok). Tez, lekin qo'l
//             siljigan joylarda chok buziladi.
//    "auto" — RAM ≥ 5.5 GB bo'lsa "mvs", aks holda "fast" (4 GB qurilmada
//             jetsam xavfi). Sukut shu.
//
//  Progress Dart'ga o'sha `kadastr/pano_capture` kanali orqali TESKARI
//  yo'nalishda keladi: `progress {p, msg}` (asosiy oqimda, ≥ 150 ms oraliq).
//  Tikish davomida ekran o'chmaydi (`isIdleTimerDisabled`).
//

import Flutter
import Foundation
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

    static func resolveMode(_ requested: String?) -> String {
        switch requested ?? "auto" {
        case "mvs": return "mvs"
        case "fast": return "fast"
        default:
            return ProcessInfo.processInfo.physicalMemory >= mvsMinRAM ? "mvs" : "fast"
        }
    }

    /// `args`: `dir` (majburiy), `width` (default 4096), `mode` (auto|mvs|fast),
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

        let width = (args?["width"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? 4096
        let mode = Self.resolveMode(args?["mode"] as? String)
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
            let r = Self.run(mode: mode, frames: frames, width: width, pano: pano,
                             preview: preview, logoPath: logoPath, progress: progress)
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
                                    seconds: wall, mode: mode))
            }
        }
    }

    private static func run(mode: String, frames: [[String: Any]], width: Int, pano: String,
                            preview: String, logoPath: String?,
                            progress: @escaping (Float, String) -> Void) -> [String: Any] {
        if mode == "mvs" {
            return UyStitcher.stitchMVSFrames(frames, width: Int32(width), highQuality: false,
                                              panoPath: pano, previewPath: preview,
                                              logoPath: logoPath, progress: progress)
        }
        return UyStitcher.stitchFrames(frames, width: Int32(width), panoPath: pano,
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
