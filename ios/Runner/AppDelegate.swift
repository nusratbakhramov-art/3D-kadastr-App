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
      let channel = FlutterMethodChannel(
        name: "kadastr/scan_capability",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "probe":
          result(self.probe())
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func probe() -> [String: Any] {
    let hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
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
