import Flutter
import UIKit
import ARKit
import SceneKit
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

        case "viewLidarMesh":
          // Xom LiDAR mesh (anchors.bin) → flat clay USDZ. Pipeline'siz, tez.
          // SceneKit viewer bilan ko'rsatamiz (simulatorда ham ishlaydi, AR yo'q).
          guard let args = call.arguments as? [String: Any],
                let id = args["id"] as? Int else {
            result(FlutterError(code: "ARGS", message: "id kerak", details: nil))
            return
          }
          guard let url = LidarMeshExporter.exportRawMesh(scanId: id) else {
            result(FlutterError(code: "LIDAR_MESH_FAILED", message: "LiDAR mesh topilmadi", details: nil))
            return
          }
          guard let controller = controller else {
            result(FlutterError(code: "NO_CONTROLLER", message: "VC yo'q", details: nil))
            return
          }
          let viewer = SceneKitModelViewerController(url: url)
          viewer.modalPresentationStyle = .fullScreen
          controller.present(viewer, animated: true) { result(url.path) }

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

// MARK: - LidarMeshExporter
// Xom ARKit LiDAR mesh (anchors.bin) ni hech qanday pipeline'siz (TSDF/clean/
// taubin/atlas YO'Q) to'g'ridan-to'g'ri flat clay USDZ sifatida eksport qiladi.
// Foydalanuvchi sensor xom geometriyasini "shunchaki" ko'rishi uchun — tez.
enum LidarMeshExporter {
  static func exportRawMesh(scanId: Int) -> URL? {
    guard let data = SavedScanStorage.loadAnchorsData(id: scanId) else {
      NSLog("KADASTR LidarMeshExporter: anchors.bin topilmadi scan=\(scanId)")
      return nil
    }
    let anchors = AnchorSerializer.deserialize(data)
    guard !anchors.isEmpty else {
      NSLog("KADASTR LidarMeshExporter: 0 anchor")
      return nil
    }

    // Barcha anchor world-mesh'larini bitta geometriyaga birlashtirish.
    var verts: [SIMD3<Float>] = []
    var norms: [SIMD3<Float>] = []
    var idxs: [UInt32] = []
    for a in anchors {
      let base = UInt32(verts.count)
      verts.append(contentsOf: a.worldVertices)
      norms.append(contentsOf: a.worldNormals)
      for i in a.indices { idxs.append(base + i) }
    }
    guard !verts.isEmpty, idxs.count >= 3 else { return nil }
    NSLog("KADASTR LidarMeshExporter: \(anchors.count) anchor → \(verts.count) vert, \(idxs.count / 3) tri")

    let vData = verts.withUnsafeBufferPointer { Data(buffer: $0) }
    let nData = norms.withUnsafeBufferPointer { Data(buffer: $0) }
    let iData = idxs.withUnsafeBufferPointer { Data(buffer: $0) }
    let vSrc = SCNGeometrySource(
      data: vData, semantic: .vertex, vectorCount: verts.count,
      usesFloatComponents: true, componentsPerVector: 3,
      bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
      dataStride: MemoryLayout<SIMD3<Float>>.stride,
    )
    let nSrc = SCNGeometrySource(
      data: nData, semantic: .normal, vectorCount: norms.count,
      usesFloatComponents: true, componentsPerVector: 3,
      bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
      dataStride: MemoryLayout<SIMD3<Float>>.stride,
    )
    let elem = SCNGeometryElement(
      data: iData, primitiveType: .triangles,
      primitiveCount: idxs.count / 3, bytesPerIndex: MemoryLayout<UInt32>.size,
    )
    let geom = SCNGeometry(sources: [vSrc, nSrc], elements: [elem])
    let mat = SCNMaterial()
    mat.lightingModel = .physicallyBased
    mat.diffuse.contents = UIColor(white: 0.74, alpha: 1.0)
    mat.roughness.contents = 0.9
    mat.metalness.contents = 0.0
    mat.isDoubleSided = true
    geom.materials = [mat]

    let scene = SCNScene()
    scene.rootNode.addChildNode(SCNNode(geometry: geom))
    let out = FileManager.default.temporaryDirectory
      .appendingPathComponent("lidar_mesh_\(scanId)_\(UUID().uuidString).usdz")
    let ok = scene.write(to: out, options: nil, delegate: nil, progressHandler: nil)
    return ok ? out : nil
  }
}

// MARK: - SceneKitModelViewerController
// USDZ/SCN model'ni SceneKit (SCNView) bilan ko'rsatadi — QLPreviewController
// dan farqli, SIMULATORda ham ishlaydi (QLPreview USDZ 3D'ni sim'da render
// qilmaydi). AR yo'q — shunchaki orbit/zoom bilan model.
final class SceneKitModelViewerController: UIViewController {
  private let url: URL
  init(url: URL) { self.url = url; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { fatalError("init(coder:) ishlatilmaydi") }

  override func viewDidLoad() {
    super.viewDidLoad()
    let bg = UIColor(white: 0.13, alpha: 1.0)
    view.backgroundColor = bg

    let scnView = SCNView(frame: view.bounds)
    scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    scnView.allowsCameraControl = true            // orbit / pan / zoom
    scnView.autoenablesDefaultLighting = true     // clay material yoritilsin
    scnView.antialiasingMode = .multisampling4X
    scnView.backgroundColor = bg
    if let scene = try? SCNScene(url: url, options: [.checkConsistency: false]) {
      scnView.scene = scene
      // Kamerani mesh bounding box markaziga qaratamiz — xom LiDAR mesh world
      // koordinatasi origin'dan uzoq bo'lishi mumkin, aks holda bo'sh ko'rinadi.
      let (minV, maxV) = scene.rootNode.boundingBox
      let cx = (minV.x + maxV.x) / 2
      let cy = (minV.y + maxV.y) / 2
      let cz = (minV.z + maxV.z) / 2
      let radius = max(maxV.x - minV.x, max(maxV.y - minV.y, maxV.z - minV.z))
      let camNode = SCNNode()
      camNode.camera = SCNCamera()
      camNode.camera!.zNear = 0.01
      camNode.camera!.zFar = Double(radius) * 12 + 20
      let d = max(radius, 0.5) * 1.8
      camNode.position = SCNVector3(cx + d * 0.6, cy + d * 0.5, cz + d * 0.9)
      camNode.look(at: SCNVector3(cx, cy, cz))
      scene.rootNode.addChildNode(camNode)
      scnView.pointOfView = camNode
    } else {
      NSLog("KADASTR SceneKitModelViewer: SCNScene yuklanmadi \(url.lastPathComponent)")
    }
    scnView.defaultCameraController.interactionMode = .orbitTurntable
    view.addSubview(scnView)

    let close = UIButton(type: .system)
    close.setTitle("✕", for: .normal)
    close.setTitleColor(.white, for: .normal)
    close.titleLabel?.font = .systemFont(ofSize: 26, weight: .bold)
    close.backgroundColor = UIColor(white: 0.0, alpha: 0.35)
    close.layer.cornerRadius = 22
    close.frame = CGRect(x: view.bounds.width - 60, y: 52, width: 44, height: 44)
    close.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
    close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    view.addSubview(close)
  }

  @objc private func closeTapped() { dismiss(animated: true) }
}
