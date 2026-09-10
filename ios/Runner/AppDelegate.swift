import AVFoundation
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

    // Splash intro roligining ovozi (VideoSplashScreen) uchun audio sessiya.
    // `.ambient` — jimlik (Ring/Silent) tugmasini HURMAT qiladi, `.mixWithOthers`
    // esa foydalanuvchining musiqasini to'xtatmaydi. iOS ning standarti bo'lgan
    // `.soloAmbient` boshqa ilovalarning ovozini uzib qo'yardi.
    // Ovoz jimlik rejimida HAM eshitilishi kerak bo'lsa — `.ambient` o'rniga
    // `.playback` qo'yiladi (lekin bu App Store'da "startda ovoz portlaydi"
    // shikoyatiga olib keladi).
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])


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
          // Qurilma qobiliyati (LiDAR + RoomPlan) VA #2 (PCScanKit) yuklanishi — IKKALASI.
          // Simulyator (LiDAR yo'q) → RoomCaptureSession.isSupported=false → disabled.
          var capable = false
          #if canImport(RoomPlan)
          if #available(iOS 16, *) { capable = RoomCaptureSession.isSupported }
          #endif
          let pc = PCScanBridge.shared.isAvailable
          NSLog("PCSCAN-ISSUPPORTED: capable(LiDAR/RoomPlan)=\(capable) pcAvailable=\(pc) → \(capable && pc)")
          result(capable && pc)

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
          // #2 (PCScanKit) capture-only oqim.
          PCScanBridge.shared.handleRoomPlan(call, presenter: controller, result: result)

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
          // #2 viewer (room.obj → SceneKit).
          PCScanBridge.shared.handleRoomPlan(call, presenter: controller, result: result)

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
        // Scan list/get/process/outputPath/delete/viewLidarMesh → ported
        // RoomScanPlanAI pipeline (Documents/Scans/scanNNN). Debug-log helpers
        // stay on the legacy path below.
        if call.method != "readDebugLog" && call.method != "clearDebugLog" {
          // #2 (PCScanKit) — barcha saved_scans amallari.
          PCScanBridge.shared.handleSavedScans(call, presenter: controller, result: result)
          return
        }
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
          guard let scene = LidarMeshExporter.buildRawMeshScene(scanId: id) else {
            result(FlutterError(code: "LIDAR_MESH_FAILED", message: "LiDAR mesh topilmadi", details: nil))
            return
          }
          guard let controller = controller else {
            result(FlutterError(code: "NO_CONTROLLER", message: "VC yo'q", details: nil))
            return
          }
          // USDZ ni path uchun yozamiz (share/eksport). Vertex rang USDZ round-trip'da
          // yo'qoladi — shuning uchun viewer'ga IN-MEMORY scene beramiz (ranglar saqlanadi).
          let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidar_mesh_\(id)_\(UUID().uuidString).usdz")
          scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
          let viewer = SceneKitModelViewerController(scene: scene)
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
          // Clean-room DEFAULT OFF (foydalanuvchi qarori: v24 = clean_room OFF = raw mesh + tekstura,
          // foto MOS keladi, real geometriya). UI "Qayta ishlash" → v24 kabi natija beradi.
          // params["clean_room"]=="1" bo'lsagina watertight clean-room yoqiladi (ixtiyoriy).
          if params["clean_room"] == "1" {
            setenv("KADASTR_CLEAN_ROOM", "1", 1)
          } else {
            unsetenv("KADASTR_CLEAN_ROOM")
          }
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

      // PCScan (RoomPlan+ObjectCapture) scanner — profil skan-picker "#2" shu
      // kanalni chaqiradi. iOS 17+ + weak-linked PCScanKit framework.
      // iOS 15/16'da UNSUPPORTED.
      let pcscanScannerChannel = FlutterMethodChannel(
        name: "kadastr/pcscan_scanner",
        binaryMessenger: controller.binaryMessenger
      )
      pcscanScannerChannel.setMethodCallHandler { [weak controller] call, result in
        switch call.method {
        case "isAvailable":
          if #available(iOS 17, *) {
            result(AppDelegate.loadPCScanEntry() != nil)
          } else {
            result(false)
          }

        case "open":
          guard let controller = controller else {
            result(FlutterError(code: "NO_CONTROLLER", message: "Flutter view controller yo'q", details: nil))
            return
          }
          if #available(iOS 17, *), let entry = AppDelegate.loadPCScanEntry() {
            let sel = NSSelectorFromString("presentFrom:")
            if entry.responds(to: sel) {
              entry.perform(sel, with: controller)
              result(true)
            } else {
              result(FlutterError(code: "ENTRY", message: "PCScan entry topilmadi", details: nil))
            }
          } else {
            result(FlutterError(code: "UNSUPPORTED", message: "Skan iOS 17+ qurilma talab qiladi", details: nil))
          }

        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // Debug-only video capture — 0.5x (ultra-wide) 1080p HD. Flutter'dagi
      // tugma faqat kDebugMode'da ko'rinadi; kanal esa har doim ro'yxatda
      // turadi (release build'da hech kim chaqirmaydi).
      let videoCaptureChannel = FlutterMethodChannel(
        name: "kadastr/video_capture",
        binaryMessenger: controller.binaryMessenger
      )
      videoCaptureChannel.setMethodCallHandler { [weak controller] call, result in
        switch call.method {
        case "isSupported":
          result(VideoCaptureCoordinator.isSupported)

        case "record":
          guard let controller = controller else {
            result(FlutterError(code: "NO_CONTROLLER", message: "Flutter view controller yo'q", details: nil))
            return
          }
          VideoCaptureCoordinator.shared.start(from: controller, result: result)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// PCScanKit.framework'ni (embedded, Runner'ga LINK QILINMAGAN) ish vaqtida
  /// yuklab, `PCScanEntry` namunasini qaytaradi.
  /// iOS 15/16'da `bundle.load()` false qaytaradi (crash yo'q) va
  /// NSClassFromString nil beradi, shu sabab nil qaytamiz.
  private static func loadPCScanEntry() -> NSObject? {
    guard let url = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("PCScanKit.framework"),
          let bundle = Bundle(url: url) else { return nil }
    if !bundle.isLoaded { bundle.load() }
    guard let cls = NSClassFromString("PCScanEntry") as? NSObject.Type else {
      return nil
    }
    return cls.init()
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
  static func buildRawMeshScene(scanId: Int) -> SCNScene? {
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

    // Per-vertex foto rang: har vertexni eng yaxshi ko'rgan kameradan rang (projection +
    // depth occlusion + gap-fill). Devor/pol/mebel/pufak haqiqiy rangда. Mesh GEOMETRIYASI
    // o'zgarmaydi — faqat .color manbasi biriktiriladi (Mac scan_009'da tasdiq: 94.6%).
    let vColors = computeVertexColors(verts: verts, normals: norms, idxs: idxs, scanId: scanId)

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
    var sources = [vSrc, nSrc]
    if let vColors = vColors {
      let cData = vColors.withUnsafeBufferPointer { Data(buffer: $0) }
      sources.append(SCNGeometrySource(
        data: cData, semantic: .color, vectorCount: vColors.count,
        usesFloatComponents: true, componentsPerVector: 4,
        bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
        dataStride: MemoryLayout<SIMD4<Float>>.stride,
      ))
    }
    let geom = SCNGeometry(sources: sources, elements: [elem])
    let mat = SCNMaterial()
    mat.lightingModel = .physicallyBased
    // Rang bo'lsa → vertex color ko'rinsin (diffuse oq, vertexColor × yengil soya).
    // Rang yo'q (poses yo'q) → kulrang clay.
    mat.diffuse.contents = (vColors != nil) ? UIColor.white : UIColor(white: 0.74, alpha: 1.0)
    mat.roughness.contents = 0.9
    mat.metalness.contents = 0.0
    // Dollhouse: single-sided (default cullMode .back). ARKit mesh normallari xona
    // ICHIga qaraydi → tashqaridan qaralganda kameraga eng yaqin devor back-face bo'lib
    // cull qilinadi, foydalanuvchi xona ichini ko'radi (Mac kadastr_raw.obj'da tasdiq).
    mat.isDoubleSided = false
    geom.materials = [mat]

    let scene = SCNScene()
    scene.rootNode.addChildNode(SCNNode(geometry: geom))

    // Kamera pozitsiyalari: poses.json'dan har frame pozasi → mesh ICHIga marker.
    // Sfera = qayerdan rasmga olingan; konus = qaysi tomonga qaragan (-Z view dir).
    // Rang = suratga olish TARTIBI (yashil → qizil) — capture yo'lini ko'rsatadi.
    if let pdata = try? Data(contentsOf: SavedScanStorage.posesURL(id: scanId)),
       let pjson = try? JSONSerialization.jsonObject(with: pdata) as? [String: Any],
       let frames = pjson["frames"] as? [[String: Any]] {
      let n = frames.count
      for (i, fr) in frames.enumerated() {
        guard let tm = fr["transform_matrix"] as? [[Double]], tm.count == 4 else { continue }
        func col(_ k: Int) -> SIMD4<Float> {
          SIMD4<Float>(Float(tm[0][k]), Float(tm[1][k]), Float(tm[2][k]), Float(tm[3][k]))
        }
        let xform = simd_float4x4(columns: (col(0), col(1), col(2), col(3)))
        let t = n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0
        let color = UIColor(hue: (1 - t) * 0.33, saturation: 0.9, brightness: 1.0, alpha: 1.0)
        let markerNode = SCNNode()
        markerNode.simdTransform = xform
        // Sfera — kamera pozitsiyasi
        let sph = SCNSphere(radius: 0.04); sph.segmentCount = 12
        let sm = SCNMaterial(); sm.lightingModel = .constant; sm.diffuse.contents = color
        sph.firstMaterial = sm
        markerNode.addChildNode(SCNNode(geometry: sph))
        // Konus — qarash yo'nalishi (-Z bo'ylab kengayadi, "flashlight")
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.035, height: 0.13)
        let cm = SCNMaterial(); cm.lightingModel = .constant; cm.diffuse.contents = color
        cone.firstMaterial = cm
        let coneNode = SCNNode(geometry: cone)
        coneNode.eulerAngles.x = .pi / 2          // +Y apex → +Z, baza -Z (view) tomon
        coneNode.position = SCNVector3(0, 0, -0.065)
        markerNode.addChildNode(coneNode)
        scene.rootNode.addChildNode(markerNode)
      }
      NSLog("KADASTR exportRawMesh: \(n) kamera markeri qo'shildi")
    }

    return scene
  }

  /// Per-vertex foto rang: har vertexni eng yaxshi ko'rgan kameradan (projection + depth
  /// occlusion) rang olib, ko'rilmaganlarni qo'shni o'rtacha bilan to'ldiradi (gap-fill).
  /// Mesh geometriyasi O'ZGARMAYDI. poses.json yo'q bo'lsa nil (kulrang clay fallback).
  /// Mac scan_009'da tasdiq: 94.6% to'g'ridan, toza dollhouse, haqiqiy ranglar.
  static func computeVertexColors(
    verts: [SIMD3<Float>], normals: [SIMD3<Float>], idxs: [UInt32], scanId: Int,
  ) -> [SIMD4<Float>]? {
    let posesURL = SavedScanStorage.posesURL(id: scanId)
    guard let pdata = try? Data(contentsOf: posesURL),
          let pjson = try? JSONSerialization.jsonObject(with: pdata) as? [String: Any],
          let frames = pjson["frames"] as? [[String: Any]], !frames.isEmpty
    else { return nil }
    let photoDir = SavedScanStorage.photoFolder(id: scanId)

    struct Cam {
      let inv: simd_float4x4; let fx, fy, cx, cy, w, h: Float; let pos: SIMD3<Float>; let sharp: Float
      let px: [UInt8]; let pw, ph: Int; let depth: [Float]; let dw, dh: Int
    }
    let DS = 3
    var cams: [Cam] = []
    for fr in frames {
      guard let tm = fr["transform_matrix"] as? [[Double]], tm.count == 4,
            let intr = fr["intrinsics"] as? [[Double]], let idx = fr["index"] as? Int else { continue }
      func col(_ k: Int) -> SIMD4<Float> { SIMD4<Float>(Float(tm[0][k]), Float(tm[1][k]), Float(tm[2][k]), Float(tm[3][k])) }
      let x = simd_float4x4(columns: (col(0), col(1), col(2), col(3)))
      // foto (downsample)
      let purl = photoDir.appendingPathComponent(String(format: "photo_%04d.jpg", idx))
      guard let img = UIImage(contentsOfFile: purl.path), let cg = img.cgImage else { continue }
      let w = cg.width / DS, h = cg.height / DS
      var buf = [UInt8](repeating: 0, count: w * h * 4)
      guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
      // depth (256x192 float32, 8-byte header)
      var depth: [Float] = []; var dw = 0, dh = 0
      let durl = photoDir.appendingPathComponent(String(format: "depth_%04d.bin", idx))
      if let dd = try? Data(contentsOf: durl), dd.count >= 8 + 256 * 192 * 4 {
        dw = 256; dh = 192
        depth = dd.withUnsafeBytes { raw in
          let f = raw.baseAddress!.advanced(by: 8).assumingMemoryBound(to: Float.self)
          return Array(UnsafeBufferPointer(start: f, count: dw * dh))
        }
      }
      cams.append(Cam(inv: x.inverse, fx: Float(intr[0][0]), fy: Float(intr[1][1]),
                      cx: Float(intr[0][2]), cy: Float(intr[1][2]), w: Float(cg.width), h: Float(cg.height),
                      pos: SIMD3<Float>(x.columns.3.x, x.columns.3.y, x.columns.3.z),
                      sharp: Float((fr["sharpness"] as? Double) ?? 0.5),
                      px: buf, pw: w, ph: h, depth: depth, dw: dw, dh: dh))
    }
    if cams.isEmpty { return nil }

    let nv = verts.count
    var colors = [SIMD3<Float>](repeating: SIMD3<Float>(0.55, 0.55, 0.55), count: nv)
    var seen = [Bool](repeating: false, count: nv)
    for vi in 0..<nv {
      let p = verts[vi]; let n = normals[vi]
      var bestScore: Float = -1e9; var found = false; var bestRGB = SIMD3<Float>(0, 0, 0)
      for c in cams {
        let viewv = c.pos - p; let vn = simd_normalize(viewv)
        if simd_dot(n, vn) < 0.0 { continue }
        let pc = c.inv * SIMD4<Float>(p, 1); let d = -pc.z
        if d <= 0.05 { continue }
        let sx = c.fx * pc.x / d + c.cx; let sy = c.fy * (-pc.y) / d + c.cy
        if sx < 0 || sx >= c.w || sy < 0 || sy >= c.h { continue }
        if c.dw > 0 {
          let dmx = min(c.dw - 1, max(0, Int(sx / c.w * Float(c.dw))))
          let dmy = min(c.dh - 1, max(0, Int(sy / c.h * Float(c.dh))))
          let dm = c.depth[dmy * c.dw + dmx]
          if dm <= 0.05 || abs(d - dm) > 0.12 { continue }   // invalid yoki occluded
        }
        let score = simd_dot(n, vn) * 2 - simd_length(viewv) * 0.25 + c.sharp * 0.5
        if score > bestScore {
          bestScore = score; found = true
          let ix = min(c.pw - 1, max(0, Int(sx / c.w * Float(c.pw))))
          let iyTop = Int(sy / c.h * Float(c.ph))
          let iy = min(c.ph - 1, max(0, c.ph - 1 - iyTop))    // Y-flip (CGContext bottom-up)
          let si = (iy * c.pw + ix) * 4
          bestRGB = SIMD3<Float>(Float(c.px[si]) / 255, Float(c.px[si + 1]) / 255, Float(c.px[si + 2]) / 255)
        }
      }
      if found { colors[vi] = bestRGB; seen[vi] = true }
    }
    // GAP-FILL: ko'rilmaganlarni qo'shni ko'rilganlar o'rtachasi bilan
    var adj = [[Int]](repeating: [], count: nv)
    var t = 0
    while t + 2 < idxs.count {
      let a = Int(idxs[t]), b = Int(idxs[t + 1]), cc = Int(idxs[t + 2]); t += 3
      adj[a].append(b); adj[a].append(cc); adj[b].append(a); adj[b].append(cc); adj[cc].append(a); adj[cc].append(b)
    }
    for _ in 0..<12 {
      var changed = 0; let snapColors = colors; let snapSeen = seen
      for vi in 0..<nv where !snapSeen[vi] {
        var sum = SIMD3<Float>(0, 0, 0); var cnt = 0
        for nb in adj[vi] where snapSeen[nb] { sum += snapColors[nb]; cnt += 1 }
        if cnt > 0 { colors[vi] = sum / Float(cnt); seen[vi] = true; changed += 1 }
      }
      if changed == 0 { break }
    }
    let coloredN = seen.lazy.filter { $0 }.count
    NSLog("KADASTR computeVertexColors: \(cams.count) kamera → \(coloredN)/\(nv) vertex bo'yaldi")
    return colors.map { SIMD4<Float>($0.x, $0.y, $0.z, 1) }
  }
}

// MARK: - SceneKitModelViewerController
// USDZ/SCN model'ni SceneKit (SCNView) bilan ko'rsatadi — QLPreviewController
// dan farqli, SIMULATORda ham ishlaydi (QLPreview USDZ 3D'ni sim'da render
// qilmaydi). AR yo'q — shunchaki orbit/zoom bilan model.
final class SceneKitModelViewerController: UIViewController {
  private let url: URL?
  private let providedScene: SCNScene?
  init(url: URL) { self.url = url; self.providedScene = nil; super.init(nibName: nil, bundle: nil) }
  // In-memory scene (vertex color USDZ round-trip'da yo'qoladi → to'g'ridan beramiz).
  init(scene: SCNScene) { self.url = nil; self.providedScene = scene; super.init(nibName: nil, bundle: nil) }
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
    if let scene = providedScene ?? url.flatMap({ try? SCNScene(url: $0, options: [.checkConsistency: false]) }) {
      scnView.scene = scene
      // Dollhouse: barcha materiallarni single-sided qil (default cullMode .back) →
      // kameraga eng yaqin (qaralayotgan) devor cull bo'ladi, xona ICHI ko'rinadi.
      // Istalgan burchakdan ishlaydi (orbit'da yaqin devor doim back-face).
      scene.rootNode.enumerateChildNodes { node, _ in
        node.geometry?.materials.forEach { $0.isDoubleSided = false }
      }
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
      // ZOOM/orbit modelmarkaz atrofida bo'lsin: xom LiDAR mesh origin'dan uzoq joyda
      // bo'lishi mumkin; default target (0,0,0) bo'lsa zoom modelga emas origin'ga
      // yaqinlashardi → "yaqinlashmayapti"dek tuyulardi. Target = mesh markazi.
      scnView.defaultCameraController.automaticTarget = false
      scnView.defaultCameraController.target = SCNVector3(cx, cy, cz)
    } else {
      NSLog("KADASTR SceneKitModelViewer: SCNScene yuklanmadi \(url?.lastPathComponent ?? "in-memory")")
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
