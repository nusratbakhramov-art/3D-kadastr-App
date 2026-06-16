import Flutter
import UIKit
import SwiftUI
import SceneKit

/// Routes kadastr's EXISTING scan MethodChannels to the ported RoomScanPlanAI
/// pipeline (RoomPlan capture + atlas texturing with mesh-depth occlusion),
/// keeping the Flutter UI + channel contract unchanged.
///
/// ID mapping: Flutter uses Int ids; ScanStore uses "scanNNN" strings. We map
/// N ⇄ String(format: "scan%03d", N). Each scan has ONE textured output
/// (result/atlas.usdz), surfaced to the UI as version 1.
final class RoomScanBridge {
    static let shared = RoomScanBridge()

    private func scanID(_ n: Int) -> String { String(format: "scan%03d", n) }
    private func intID(_ s: String) -> Int? { Int(s.dropFirst(4)) }

    private func usdzURL(_ id: Int) -> URL {
        ScanStore.shared.folder(for: scanID(id)).appendingPathComponent("result/atlas.usdz")
    }
    private func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    // MARK: - kadastr/room_plan_scanner

    /// Returns true if this bridge handled the method (else AppDelegate keeps its
    /// own handler for it — e.g. startObjectCapture / startHybridScan).
    @discardableResult
    func handleRoomPlan(_ call: FlutterMethodCall, presenter: UIViewController?,
                        result: @escaping FlutterResult) -> Bool {
        switch call.method {
        case "startTexturedScan":
            startCapture(presenter: presenter, result: result)
            return true
        case "isSupported":
            if #available(iOS 17, *) { result(true) } else { result(false) }
            return true
        case "previewModel":
            let path = (call.arguments as? [String: Any])?["filePath"] as? String
            presentResultViewer(path: path, presenter: presenter, result: result)
            return true
        default:
            return false
        }
    }

    /// View the textured result EXACTLY like RoomScanPlanAI: load atlas.geo +
    /// atlas.png and render them directly in SceneKit (no USDZ round-trip). Falls
    /// back to loading the given file (USDZ) if the atlas pair isn't present.
    private func presentResultViewer(path: String?, presenter: UIViewController?, result: @escaping FlutterResult) {
        guard let presenter else {
            result(FlutterError(code: "NO_PRESENTER", message: "Ko'rsatish oynasi yo'q", details: nil)); return
        }
        if let path {
            let dir = (path as NSString).deletingLastPathComponent
            let geo = URL(fileURLWithPath: dir).appendingPathComponent("atlas.geo")
            let png = URL(fileURLWithPath: dir).appendingPathComponent("atlas.png")
            if FileManager.default.fileExists(atPath: geo.path),
               FileManager.default.fileExists(atPath: png.path),
               let mesh = try? AtlasIO.read(geometry: geo, atlas: png) {
                let scene = SCNScene()
                scene.rootNode.addChildNode(AtlasSceneBuilder.makeNode(mesh))
                let viewer = SceneKitModelViewerController(scene: scene)
                viewer.modalPresentationStyle = .fullScreen
                presenter.present(viewer, animated: true) { result(true) }
                return
            }
            if FileManager.default.fileExists(atPath: path) {   // fallback: the file itself
                let viewer = SceneKitModelViewerController(url: URL(fileURLWithPath: path))
                viewer.modalPresentationStyle = .fullScreen
                presenter.present(viewer, animated: true) { result(true) }
                return
            }
        }
        result(FlutterError(code: "NO_FILE", message: "Natija topilmadi", details: nil))
    }

    private func startCapture(presenter: UIViewController?, result: @escaping FlutterResult) {
        guard #available(iOS 17, *) else {
            result(FlutterError(code: "UNSUPPORTED", message: "Skan uchun iOS 17+ kerak", details: nil))
            return
        }
        guard let presenter else {
            result(FlutterError(code: "NO_PRESENTER", message: "Ko'rsatish oynasi topilmadi", details: nil))
            return
        }
        var returned = false
        let finish: (String?) -> Void = { [weak self] scanIDStr in
            guard let self, !returned else { return }
            returned = true
            presenter.dismiss(animated: true)
            guard let sid = scanIDStr, let n = self.intID(sid),
                  let m = ScanStore.shared.loadManifest(sid) else {
                result(nil)   // cancelled / failed → Flutter treats as no scan
                return
            }
            let areaVal: Any = m.floorAreaM2.map { Double($0) } ?? NSNull()
            result([
                "savedScanId": n,
                "mode": "saved_raw",
                "walls": m.roomWallCount,
                "doors": 0,
                "windows": 0,
                "objects": m.roomObjectCount,
                "floorAreaSqm": areaVal,
                "fileSize": 0,
            ])
        }
        let host = UIHostingController(rootView: RoomCaptureScreen(onFinished: finish))
        host.modalPresentationStyle = .fullScreen
        presenter.present(host, animated: true)
    }

    // MARK: - kadastr/saved_scans

    func handleSavedScans(_ call: FlutterMethodCall, presenter: UIViewController?,
                          result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "list":
            result(listScans())
        case "get":
            guard let id = (args["id"] as? NSNumber)?.intValue else { result(nil); return }
            result(scanMap(id))
        case "process":
            guard let id = (args["id"] as? NSNumber)?.intValue else {
                result(FlutterError(code: "BAD_ARGS", message: "id yo'q", details: nil)); return
            }
            process(id, result: result)
        case "outputPath":
            guard let id = (args["id"] as? NSNumber)?.intValue else { result(nil); return }
            let url = usdzURL(id)
            result(FileManager.default.fileExists(atPath: url.path) ? url.path : nil)
        case "delete":
            guard let id = (args["id"] as? NSNumber)?.intValue else { result(false); return }
            ScanStore.shared.delete(scanID(id))
            result(true)
        case "deleteOutput":
            guard let id = (args["id"] as? NSNumber)?.intValue else { result(false); return }
            try? FileManager.default.removeItem(at: usdzURL(id))
            result(true)
        case "viewLidarMesh":
            guard let id = (args["id"] as? NSNumber)?.intValue else { result(nil); return }
            let folder = ScanStore.shared.folder(for: scanID(id))
            for name in ["mesh.usdz", "room.usdz"] {
                let u = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: u.path) { result(u.path); return }
            }
            result(nil)
        case "listScanFiles":
            guard let id = (args["id"] as? NSNumber)?.intValue else { result(nil); return }
            result(listScanFiles(id))
        case "rename":
            result(true)   // names are derived from scanNNN; rename is a no-op for now
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Enumerate every uploadable artifact of a scan (no depth — large & unused by
    /// the backend), tagged by type + size, so Flutter can upload the full bundle
    /// with file-level progress. Returns [{path, rel, type, sizeBytes}].
    private func listScanFiles(_ id: Int) -> [[String: Any]] {
        let folder = ScanStore.shared.folder(for: scanID(id))
        let fm = FileManager.default
        var out: [[String: Any]] = []
        func add(_ url: URL, _ type: String) {
            guard fm.fileExists(atPath: url.path) else { return }
            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
            let rel = url.path.replacingOccurrences(of: folder.path + "/", with: "")
            out.append(["path": url.path, "rel": rel, "type": type, "sizeBytes": size])
        }
        // Textured result + mesh + metadata.
        add(folder.appendingPathComponent("result/atlas.glb"), "glb")
        add(folder.appendingPathComponent("result/atlas.usdz"), "usdz")
        add(folder.appendingPathComponent("result/atlas.geo"), "geo")
        add(folder.appendingPathComponent("result/atlas.png"), "png")
        add(folder.appendingPathComponent("geometry.bin"), "geometry_bin")
        add(folder.appendingPathComponent("mesh.ply"), "mesh_ply")
        add(folder.appendingPathComponent("mesh.usdz"), "mesh_usdz")
        add(folder.appendingPathComponent("manifest.json"), "manifest")
        add(folder.appendingPathComponent("frames/frames.json"), "frames_json")
        // RGB keyframes (the "rasmlar").
        let framesDir = folder.appendingPathComponent("frames")
        if let items = try? fm.contentsOfDirectory(atPath: framesDir.path) {
            for f in items.sorted() where f.lowercased().hasSuffix(".jpg") {
                add(framesDir.appendingPathComponent(f), "frame")
            }
        }
        return out
    }

    private func listScans() -> [[String: Any]] {
        ScanStore.shared.listScanIDs().compactMap { scanMap(forStringID: $0) }
    }

    private func scanMap(_ id: Int) -> [String: Any]? { scanMap(forStringID: scanID(id)) }

    private func scanMap(forStringID sid: String) -> [String: Any]? {
        guard let n = intID(sid), let m = ScanStore.shared.loadManifest(sid) else { return nil }
        var outputs: [[String: Any]] = []
        let usdz = usdzURL(n)
        if FileManager.default.fileExists(atPath: usdz.path) {
            outputs.append([
                "version": 1,
                "fileName": "atlas.usdz",
                "createdAt": m.createdAt.timeIntervalSince1970,
                "sizeBytes": fileSize(usdz),
                "params": [String: String](),
            ])
        }
        return [
            "id": n,
            "name": m.id,
            "createdAt": m.createdAt.timeIntervalSince1970,
            "photoCount": m.frameCount,
            "areaSqm": 0.0,
            "outputs": outputs,
        ]
    }

    private func process(_ id: Int, result: @escaping FlutterResult) {
        let sid = scanID(id)
        DebugLog.log("ROOMSCAN", "process START \(sid)")
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let bundle = try await TexturingService.run(scanID: sid)
                // GLB is the primary output (uploaded to the backend); fall back to
                // USDZ only if GLB export failed. The local viewer reads atlas.geo+
                // png from the same result/ folder, so either path works for it.
                let glb = bundle.usdz.deletingLastPathComponent().appendingPathComponent("atlas.glb")
                let model = FileManager.default.fileExists(atPath: glb.path) ? glb : bundle.usdz
                let size = self.fileSize(model)
                DebugLog.log("ROOMSCAN", "process DONE \(sid) model=\(model.lastPathComponent) \(size)B")
                await MainActor.run {
                    result([
                        "scanId": id,
                        "version": 1,
                        "filePath": model.path,
                        "fileSize": size,
                        "mode": "offline_processed",
                    ])
                }
            } catch {
                DebugLog.log("ROOMSCAN", "process FAILED \(sid): \(error)")
                await MainActor.run {
                    result(FlutterError(code: "PROCESS_FAILED",
                                        message: error.localizedDescription, details: nil))
                }
            }
        }
    }
}
