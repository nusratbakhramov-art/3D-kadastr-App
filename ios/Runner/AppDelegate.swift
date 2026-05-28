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
