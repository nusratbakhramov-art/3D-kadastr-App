// AutoProcessRunner — Phase 8.1: simulator iteration uchun avtomatik trigger.
// App launch'da env var KADASTR_AUTO_PROCESS=N bo'lsa, profilga kirishni
// o'tkazib yuborib, to'g'ridan-to'g'ri scan N ni process qiladi va natijani
// /tmp/kadastr_result.usdz ga yozadi.
//
// Edit→build→run loop'ni 5 daqiqadan 30 soniyaga tushiradi.
// Iteration:
//   1. Code o'zgartirish (e.g., dilate iter, voxel size)
//   2. xcodebuild ... build
//   3. xcrun simctl launch booted uz.kadastr.kadastr \
//          --setenv KADASTR_AUTO_PROCESS=3 \
//          --setenv KADASTR_AUTO_OUT=/tmp/result.usdz
//   4. Wait for /tmp/result.usdz, open via QuickLook

import Foundation
import UIKit

@available(iOS 17.0, *)
enum AutoProcessRunner {
    static func run(scanId: Int) {
        DebugLog.log("AUTORUN", "Auto-process triggered for scan #\(scanId)")
        guard let entry = SavedScanStorage.get(id: scanId) else {
            DebugLog.log("AUTORUN", "Scan #\(scanId) topilmadi")
            exit(2)
        }
        DebugLog.log("AUTORUN", "Found scan: \(entry.name), photos=\(entry.photoCount)")

        // Topmost view controller'ni topib, undan present qilamiz.
        // Flutter root window asosida.
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first
        else {
            DebugLog.log("AUTORUN", "No rootVC")
            exit(3)
        }

        // Wait for full Flutter init
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            startProcessing(scanId: scanId, presenter: rootVC)
        }
    }

    private static func startProcessing(scanId: Int, presenter: UIViewController) {
        DebugLog.log("AUTORUN", "Starting headless processing of scan #\(scanId)")
        let outPath = ProcessInfo.processInfo.environment["KADASTR_AUTO_OUT"]
            ?? "/tmp/kadastr_result.usdz"
        let outURL = URL(fileURLWithPath: outPath)

        // Top-most VC topish (root chained presents bo'lishi mumkin)
        var topVC = presenter
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        TexturedScanCoordinator.shared.processSavedScan(
            scanId: scanId,
            params: [:],
            from: topVC,
        ) { result in
            // result = [scanId, version, filePath, fileSize, mode] OR FlutterError
            DebugLog.log("AUTORUN", "process result type: \(type(of: result))")
            if let err = result as? FlutterError {
                DebugLog.log("AUTORUN", "FAIL: \(err.message ?? err.code)")
                writeDoneMarker(success: false, outURL: outURL, message: err.message ?? err.code)
                exit(4)
            }
            guard let dict = result as? [String: Any],
                  let srcPath = dict["filePath"] as? String
            else {
                DebugLog.log("AUTORUN", "FAIL: unexpected result \(String(describing: result))")
                writeDoneMarker(success: false, outURL: outURL, message: "no filePath")
                exit(5)
            }
            // USDZ'ni env var-specified path'ga ko'chirish
            let src = URL(fileURLWithPath: srcPath)
            try? FileManager.default.removeItem(at: outURL)
            do {
                try FileManager.default.copyItem(at: src, to: outURL)
                DebugLog.log("AUTORUN", "USDZ saved → \(outURL.path)")
                writeDoneMarker(success: true, outURL: outURL, message: "ok")
            } catch {
                DebugLog.log("AUTORUN", "copy FAIL: \(error.localizedDescription)")
                writeDoneMarker(success: false, outURL: outURL, message: error.localizedDescription)
            }
            // Exit so iteration script knows we're done
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
        }
    }

    private static func writeDoneMarker(success: Bool, outURL: URL, message: String) {
        let marker = outURL.deletingPathExtension().appendingPathExtension("done.txt")
        let line = "\(success ? "OK" : "FAIL"): \(message) at \(Date())\n"
        try? line.data(using: .utf8)?.write(to: marker)
    }
}
