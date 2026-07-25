import Flutter
import UIKit

/// AI Baholash skan-provayderi. Default `.roomScan`. `.pcScan` da PCScanKit ("#2")
/// ishlaydi; PCScan mavjud bo'lmasa (iOS<17 / kit yuklanmadi) avtomatik RoomScan'ga
/// tushadi (qarang `AppDelegate.scanBridge`).
enum ScanProvider {
    case roomScan
    case pcScan
}

/// Runner'dagi skaner bridge'lari uchun umumiy interfeys — AppDelegate provayder
/// bo'yicha bittasini tanlaydi. `RoomScanBridge` va `PCScanBridge` shunga muvofiq.
protocol ScanBridge: AnyObject {
    @discardableResult
    func handleRoomPlan(_ call: FlutterMethodCall, presenter: UIViewController?,
                        result: @escaping FlutterResult) -> Bool
    func handleSavedScans(_ call: FlutterMethodCall, presenter: UIViewController?,
                          result: @escaping FlutterResult)
}

/// "#2" PCScanKit skanerini AI Baholash kanallariga ulaydigan bridge —
/// `RoomScanBridge` egizagi. Runner PCScanKit'ni LINK QILMAYDI, shuning uchun kit
/// ish vaqtida `Bundle.load()` bilan yuklanib, `PCScanFacade` orqali chaqiriladi
/// (dlopen). PCScan id'lari `1_000_000 + index` bilan RoomScan id'laridan ajratiladi.
final class PCScanBridge: ScanBridge {
    static let shared = PCScanBridge()
    private init() {}

    private var cachedFacade: PCScanFacade?

    /// PCScanKit.framework'ni yuklab, `PCScanEntry` ni `PCScanFacade` sifatida
    /// qaytaradi. iOS<17 / kit yo'q / cast muvaffaqiyatsiz bo'lsa nil.
    func facade() -> PCScanFacade? {
        if let f = cachedFacade { return f }
        guard #available(iOS 17, *),
              let url = Bundle.main.privateFrameworksURL?
                .appendingPathComponent("PCScanKit.framework"),
              let bundle = Bundle(url: url) else { return nil }
        if !bundle.isLoaded { bundle.load() }
        guard let cls = NSClassFromString("PCScanEntry") as? NSObject.Type,
              let facade = cls.init() as? PCScanFacade else { return nil }
        cachedFacade = facade
        return facade
    }

    /// PCScan bu qurilmada mavjudmi (iOS17 + kit yuklanadi + cast). LiDAR
    /// tekshiruvi PCScan onboarding'i ichida.
    var isAvailable: Bool { facade() != nil }

    // MARK: - kadastr/room_plan_scanner

    @discardableResult
    func handleRoomPlan(_ call: FlutterMethodCall, presenter: UIViewController?,
                        result: @escaping FlutterResult) -> Bool {
        switch call.method {
        case "isSupported":
            result(isAvailable)
            return true

        case "startTexturedScan":
            guard let presenter, let f = facade() else {
                result(nil)   // Flutter buni "skan yo'q" deb qabul qiladi
                return true
            }
            f.presentCapture(from: presenter) { map in result(map) }
            return true

        case "previewModel":
            guard let presenter, let f = facade(),
                  let path = (call.arguments as? [String: Any])?["filePath"] as? String else {
                result(FlutterError(code: "NO_FILE", message: "Natija topilmadi", details: nil))
                return true
            }
            f.presentViewer(from: presenter, path: path)
            result(true)
            return true

        default:
            return false
        }
    }

    // MARK: - kadastr/saved_scans

    func handleSavedScans(_ call: FlutterMethodCall, presenter: UIViewController?,
                          result: @escaping FlutterResult) {
        guard let f = facade() else {
            result(FlutterError(code: "UNSUPPORTED", message: "PCScan mavjud emas", details: nil))
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "process":
            guard let id = args["id"] as? Int else {
                result(FlutterError(code: "BAD_ARGS", message: "id yo'q", details: nil)); return
            }
            f.processScan(id) { map, err in
                if let err = err {
                    result(FlutterError(code: "PROCESS_FAILED",
                                        message: err.localizedDescription, details: nil))
                } else {
                    result(map)
                }
            }

        case "listScanFiles":
            guard let id = args["id"] as? Int else { result(nil); return }
            result(f.listScanFiles(id))

        case "outputPath":
            guard let id = args["id"] as? Int else { result(nil); return }
            result(f.outputPath(id))

        case "delete":
            guard let id = args["id"] as? Int else { result(false); return }
            result(f.deleteScan(id))

        case "list":
            result(f.listScans())
        case "get":
            guard let id = args["id"] as? Int else { result(nil); return }
            result(f.scanSummary(id))
        case "deleteOutput":
            guard let id = args["id"] as? Int else { result(false); return }
            result(f.deleteOutput(id))
        case "viewLidarMesh":
            result(nil)   // PCScan xom LiDAR mesh ko'rish qo'llab-quvvatlanmaydi (graceful)
        case "rename":
            result(true)  // PCScan nomlari index-asosli ("Skan #N")

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
