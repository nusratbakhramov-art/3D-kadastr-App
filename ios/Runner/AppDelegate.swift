import Flutter
import UIKit
import ARKit
#if canImport(RoomPlan)
import RoomPlan
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Phase 8.1: Auto-process scan from env var (simulator iteration uchun).
    // Misol: xcrun simctl launch booted uz.kadastr.kadastr --setenv KADASTR_AUTO_PROCESS=3 \
    //              --setenv KADASTR_AUTO_OUT=/tmp/result.usdz
    if #available(iOS 17.0, *), let scanIdStr = ProcessInfo.processInfo.environment["KADASTR_AUTO_PROCESS"],
       let scanId = Int(scanIdStr) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        AutoProcessRunner.run(scanId: scanId)
      }
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let probeChannel = FlutterMethodChannel(
        name: "kadastr/scan_capability",
        binaryMessenger: controller.binaryMessenger
      )
      probeChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "probe":
          result(self.probe())
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // RoomPlan scanner — iOS 16+, faqat LiDAR'li qurilmalarda.
      let scannerChannel = FlutterMethodChannel(
        name: "kadastr/room_plan_scanner",
        binaryMessenger: controller.binaryMessenger
      )
      scannerChannel.setMethodCallHandler { [weak controller] call, result in
        switch call.method {
        case "isSupported":
          var supported = false
          #if canImport(RoomPlan)
          if #available(iOS 16, *) {
            supported = RoomCaptureSession.isSupported
          }
          #endif
          result(supported)

        case "startScan":
          guard let controller = controller else {
            result(FlutterError(
              code: "NO_CONTROLLER",
              message: "Flutter view controller mavjud emas",
              details: nil,
            ))
            return
          }
          if #available(iOS 16, *) {
            RoomPlanScannerCoordinator.shared.start(from: controller, result: result)
          } else {
            result(FlutterError(
              code: "UNSUPPORTED",
              message: "RoomPlan iOS 16+ ga muhtoj",
              details: nil,
            ))
          }

        case "startTexturedScan":
          guard let controller = controller else {
            result(FlutterError(
              code: "NO_CONTROLLER",
              message: "Flutter view controller mavjud emas",
              details: nil,
            ))
            return
          }
          if #available(iOS 17.0, *) {
            TexturedScanCoordinator.shared.start(from: controller, result: result)
          } else {
            result(FlutterError(
              code: "UNSUPPORTED",
              message: "Photogrammetry scan iOS 17+ ga muhtoj",
              details: nil,
            ))
          }

        case "startTexturedRoomPlan":
          guard let controller = controller else {
            result(FlutterError(
              code: "NO_CONTROLLER",
              message: "Flutter view controller mavjud emas",
              details: nil,
            ))
            return
          }
          if #available(iOS 17, *) {
            TexturedRoomPlanCoordinator.shared.start(from: controller, result: result)
          } else {
            result(FlutterError(
              code: "UNSUPPORTED",
              message: "Textured RoomPlan iOS 17+ ga muhtoj",
              details: nil,
            ))
          }

        case "startObjectCapture":
          guard let controller = controller else {
            result(FlutterError(
              code: "NO_CONTROLLER",
              message: "Flutter view controller mavjud emas",
              details: nil,
            ))
            return
          }
          if #available(iOS 17.0, *) {
            ObjectCaptureCoordinator.shared.start(from: controller, result: result)
          } else {
            result(FlutterError(
              code: "UNSUPPORTED",
              message: "Object Capture iOS 17+ ga muhtoj",
              details: nil,
            ))
          }

        case "startHybridScan":
          guard let controller = controller else {
            result(FlutterError(
              code: "NO_CONTROLLER",
              message: "Flutter view controller mavjud emas",
              details: nil,
            ))
            return
          }
          guard let args = call.arguments as? [String: Any],
                let baseUrl = args["baseUrl"] as? String,
                let token = args["token"] as? String else {
            result(FlutterError(
              code: "ARGS",
              message: "baseUrl va token argumentlari kerak",
              details: nil,
            ))
            return
          }
          let provider = (args["provider"] as? String) ?? "local_mac"
          let algorithm = (args["algorithm"] as? String) ?? "3dgs"
          let quality = (args["quality"] as? String) ?? "balanced"
          if #available(iOS 17.0, *) {
            HybridUploadCoordinator.shared.start(
              from: controller,
              baseUrl: baseUrl,
              authToken: token,
              provider: provider,
              algorithm: algorithm,
              quality: quality,
              result: result,
            )
          } else {
            result(FlutterError(
              code: "UNSUPPORTED",
              message: "Hybrid scan iOS 17+ ga muhtoj",
              details: nil,
            ))
          }

        case "previewModel":
          guard let args = call.arguments as? [String: Any],
                let path = args["filePath"] as? String else {
            result(FlutterError(
              code: "ARGS",
              message: "filePath argument kerak",
              details: nil,
            ))
            return
          }
          guard let controller = controller else {
            result(FlutterError(
              code: "NO_CONTROLLER",
              message: "Flutter view controller mavjud emas",
              details: nil,
            ))
            return
          }
          UsdzPreviewer.shared.present(
            filePath: path,
            from: controller,
            result: result,
          )

        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // Phase 7: Saved raw scans API — Documents/saved_scans/ dagi raw data
      // (photos, depth, poses, anchors) va outputs (USDZ history).
      let savedScansChannel = FlutterMethodChannel(
        name: "kadastr/saved_scans",
        binaryMessenger: controller.binaryMessenger
      )
      savedScansChannel.setMethodCallHandler { [weak controller] call, result in
        switch call.method {
        case "list":
          let scans = SavedScanStorage.list()
          let json: [[String: Any]] = scans.map { e in
            [
              "id": e.id,
              "name": e.name,
              "createdAt": e.createdAt,
              "photoCount": e.photoCount,
              "areaSqm": e.areaSqm,
              "outputs": e.outputs.map { o -> [String: Any] in
                return [
                  "version": o.version,
                  "fileName": o.fileName,
                  "createdAt": o.createdAt,
                  "sizeBytes": o.sizeBytes,
                  "params": o.params,
                ]
              },
            ]
          }
          result(json)

        case "get":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int else {
            result(FlutterError(code: "ARGS", message: "id kerak", details: nil))
            return
          }
          guard let entry = SavedScanStorage.get(id: id) else {
            result(nil); return
          }
          result([
            "id": entry.id,
            "name": entry.name,
            "createdAt": entry.createdAt,
            "photoCount": entry.photoCount,
            "areaSqm": entry.areaSqm,
            "outputs": entry.outputs.map { o -> [String: Any] in
              return [
                "version": o.version,
                "fileName": o.fileName,
                "createdAt": o.createdAt,
                "sizeBytes": o.sizeBytes,
                "params": o.params,
              ]
            },
          ])

        case "process":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int else {
            result(FlutterError(code: "ARGS", message: "id kerak", details: nil))
            return
          }
          let params = (args["params"] as? [String: String]) ?? [:]
          guard let controller = controller else {
            result(FlutterError(code: "NO_CONTROLLER", message: "VC yo'q", details: nil))
            return
          }
          DebugLog.log("APPDELEGATE", "saved_scans/process id=\(id) params=\(params)")
          if #available(iOS 17.0, *) {
            TexturedScanCoordinator.shared.processSavedScan(
              scanId: id, params: params, from: controller, result: result,
            )
          } else {
            result(FlutterError(code: "UNSUPPORTED", message: "iOS 17+ kerak", details: nil))
          }

        case "readDebugLog":
          // Debug log fayl mazmunini qaytaradi (Mac'ga pull qilish uchun).
          let url = DebugLog.logURL
          if let data = try? Data(contentsOf: url),
             let text = String(data: data, encoding: .utf8) {
            result(text)
          } else {
            result("")
          }

        case "clearDebugLog":
          DebugLog.reset()
          result(true)

        case "outputPath":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int,
                let version = args["version"] as? Int else {
            result(FlutterError(code: "ARGS", message: "id va version kerak", details: nil))
            return
          }
          result(SavedScanStorage.outputURL(scanId: id, version: version)?.path)

        case "delete":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int else {
            result(FlutterError(code: "ARGS", message: "id kerak", details: nil))
            return
          }
          result(SavedScanStorage.delete(id: id))

        case "deleteOutput":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int,
                let version = args["version"] as? Int else {
            result(FlutterError(code: "ARGS", message: "id va version kerak", details: nil))
            return
          }
          result(SavedScanStorage.deleteOutput(scanId: id, version: version))

        case "rename":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int,
                let name = args["name"] as? String else {
            result(FlutterError(code: "ARGS", message: "id va name kerak", details: nil))
            return
          }
          result(SavedScanStorage.rename(id: id, newName: name))

        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // Local skanlar API — Documents/scans/ dagi numbered USDZ'lar.
      // Auth talab qilmaydi, to'liq local.
      let localScansChannel = FlutterMethodChannel(
        name: "kadastr/local_scans",
        binaryMessenger: controller.binaryMessenger
      )
      localScansChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "list":
          let scans = LocalScanIndex.listScans()
          let json: [[String: Any]] = scans.map { e in
            [
              "id": e.id,
              "name": e.name,
              "fileName": e.fileName,
              "createdAt": e.createdAt,
              "sizeBytes": e.sizeBytes,
              "areaSqm": e.areaSqm,
              "photoCount": e.photoCount,
            ]
          }
          result(json)

        case "getPath":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int else {
            result(FlutterError(code: "ARGS", message: "id kerak", details: nil))
            return
          }
          if let url = LocalScanIndex.scanURL(forId: id) {
            result(url.path)
          } else {
            result(nil)
          }

        case "delete":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int else {
            result(FlutterError(code: "ARGS", message: "id kerak", details: nil))
            return
          }
          result(LocalScanIndex.deleteScan(id: id))

        case "rename":
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int,
                let newName = args["name"] as? String else {
            result(FlutterError(code: "ARGS", message: "id va name kerak", details: nil))
            return
          }
          result(LocalScanIndex.renameScan(id: id, newName: newName))

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func probe() -> [String: Any] {
    var hasLidar = false
    if #available(iOS 13.4, *) {
      hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    let arSupported = ARWorldTrackingConfiguration.isSupported
    var hasRoomPlan = false
    #if canImport(RoomPlan)
    if #available(iOS 16, *) {
      hasRoomPlan = RoomCaptureSession.isSupported
    }
    #endif

    return [
      "platform": "ios",
      "hasLidar": hasLidar,
      "hasRoomPlan": hasRoomPlan,
      "hasArCore": false,
      "hasDepthApi": false,
      "arWorldTrackingSupported": arSupported,
      "deviceModel": Self.deviceModel(),
      "osVersion": UIDevice.current.systemVersion,
    ]
  }

  private static func deviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    return machineMirror.children.reduce("") { partial, element in
      guard let value = element.value as? Int8, value != 0 else { return partial }
      return partial + String(UnicodeScalar(UInt8(value)))
    }
  }
}
