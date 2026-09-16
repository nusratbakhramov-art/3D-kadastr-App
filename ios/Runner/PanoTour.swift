//
//  PanoTour.swift — 360° panorama ko'ruvchisi va «house tour» (xonalarni
//  bir-biriga bog'lash), SceneKit.
//
//  MANBA: Uy360 `PanoramaView` + `TourViewerView`
//  (`360/ios/Uy360/{PanoramaView,TourView}.swift`). Farqlar:
//
//   1. Matnlar Dart'dan (`strings`) — ilova uch tilli.
//   2. Panorama tasviri LOKAL FAYL yoki URL (S3) bo'lishi mumkin — sehrgarda
//      hamma panorama allaqachon yuklangan, ya'ni odatda URL. Tarmoqdan
//      kelgani `Caches/kadastr-pano/` ga saqlanadi (qayta ochishda tez).
//   3. Burchaklar CHEGARADA kadastr konvensiyasiga o'tkaziladi: Dart/backend
//      `yaw_deg` — ekvirekt bo'ylama (0° = tasvir chap cheti, 180° = markaz,
//      o'ngga burilganda o'sadi), `pitch_deg` + = yuqori. Uy360 sahnasida esa
//      yaw 0 = tasvir markazi, musbat = chapga (radian). Shuning uchun
//      `yaw_uy = π − yaw_deg·π/180`, teskarisi `yaw_deg = (180 − deg(yaw_uy)) mod 360`.
//      Sahna matematikasi Uy360'dagidek qoldi — u qurilmada tekshirilgan.
//   4. «Yangi xona — hozir tushirish» nativ tarafda tushirmaydi: ekran
//      `{action: newRoom, fromKey, yawDeg, pitchDeg}` bilan yopiladi, Dart
//      capture → tikish → yuklash oqimini yuritadi, havolani ikki tomonlama
//      qo'shadi va turni yangi xonada qayta ochadi.
//   5. Chegaralar Dart/backend bilan bir xil: bitta panoramadan ko'pi bilan
//      8 ta havola (`MAX_TOUR_LINKS_PER_PANORAMA`), ikki tugma orasi < 12°
//      bo'lsa OGOHLANTIRISH (taqiq emas — tor yo'lakda ikki eshik yonma-yon
//      bo'lishi mumkin).
//
//  Kanal: `tour {panoramas:[{key,name?,url?,path?}], links:[{from,to,yawDeg,
//  pitchDeg,label?}], startKey, editable, strings}` →
//  `{links:[…], action: nil | {type:"newRoom", fromKey, yawDeg, pitchDeg}}`.
//  `preview {path, strings}` → `{action: "accept" | "retake"}`.
//

import CryptoKit
import Flutter
import SceneKit
import SwiftUI
import UIKit

// MARK: - Model

/// Turdagi bitta xona (panorama).
struct TourRoom: Identifiable, Equatable {
    let key: String        // Dart `ref` — S3 kaliti (yoki lokal ref)
    let name: String
    let url: String?
    let path: String?
    var id: String { key }
}

/// Xona 360° ichidagi bosiladigan havola — boshqa xonaga olib boradi.
/// Yo'nalish Uy360 sahna konvensiyasida (radian): yaw 0 = panorama markazi,
/// musbat = chapga; pitch + = yuqori.
struct TourHotspot: Identifiable, Equatable {
    var id: String
    var yaw: Float
    var pitch: Float
    var targetKey: String
    var label: String?

    /// Sahna dunyo freymidagi birlik vektor (`PanoramaView` kamera konvensiyasi).
    var direction: SIMD3<Float> {
        SIMD3(-cos(pitch) * sin(yaw), sin(pitch), -cos(pitch) * cos(yaw))
    }

    static func angles(of d: SIMD3<Float>) -> (yaw: Float, pitch: Float) {
        let n = simd_normalize(d)
        return (atan2(-n.x, -n.z), asin(max(-1, min(1, n.y))))
    }

    // Kadastr (Dart/backend) konvensiyasi bilan almashish — fayl sarlavhasi §3.
    static func yawFromDeg(_ yawDeg: Double) -> Float { Float(.pi - yawDeg * .pi / 180) }
    static func yawToDeg(_ yaw: Float) -> Double {
        var d = 180 - Double(yaw) * 180 / .pi
        d = d.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }

    func toDart(from: String) -> [String: Any] {
        var out: [String: Any] = [
            "from": from,
            "to": targetKey,
            "yawDeg": Self.yawToDeg(yaw),
            "pitchDeg": Double(pitch) * 180 / .pi,
        ]
        if let l = label, !l.isEmpty { out["label"] = l }
        return out
    }
}

/// Bitta panoramadan chiqadigan havolalar chegarasi (Dart `kMaxTourLinksPerPanorama`,
/// backend `MAX_TOUR_LINKS_PER_PANORAMA`).
let kMaxTourLinksPerPanorama = 8
/// Ikki tugma orasidagi eng kichik burchak (Dart `kMinHotspotSeparationDeg`).
let kMinHotspotSeparationDeg: Float = 12

// MARK: - Tasvir yuklash

/// Panorama tasvirini fayldan yoki tarmoqdan oladi; tarmoqdagi Caches'ga tushadi.
enum PanoImageLoader {
    private static var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("kadastr-pano", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func cachedFile(for url: String) -> URL {
        let h = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(h).jpg")
    }

    /// `path` bo'lsa undan, bo'lmasa `url` dan (kesh → tarmoq).
    static func load(path: String?, url: String?) async throws -> UIImage {
        if let p = path, FileManager.default.fileExists(atPath: p), let img = UIImage(contentsOfFile: p) {
            return img
        }
        guard let u = url, !u.isEmpty else { throw LoadError.missing }
        // A storage key identifies a room; it is not a downloadable URL. Never
        // hand a relative key or a deleted local path to URLSession.
        guard let remote = URL(string: u),
              ["https", "http"].contains(remote.scheme?.lowercased() ?? ""),
              remote.host?.isEmpty == false else { throw LoadError.invalidSource }
        let cached = cachedFile(for: u)
        if let img = UIImage(contentsOfFile: cached.path) { return img }
        let (data, resp) = try await URLSession.shared.data(from: remote)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoadError.network(http.statusCode)
        }
        guard let img = UIImage(data: data) else { throw LoadError.decode }
        try? data.write(to: cached, options: .atomic)
        return img
    }

    enum LoadError: Error { case missing, invalidSource, network(Int), decode }
}

// MARK: - Sfera ko'ruvchisi

/// Oflayn 360° ko'ruvchi: ekvirekt tasvir sferaning ICHIGA yopishtiriladi,
/// kamera markazda. Surish — qarash, chimdish — masshtab. Hotspot'lar sferada
/// billboard; bosish yo hotspot id'ni, yo erkin yo'nalishni qaytaradi
/// (tahrirlovchi yangi tugma qo'yish uchun ishlatadi).
struct PanoramaSceneView: UIViewRepresentable {
    let image: UIImage?
    var hotspots: [TourHotspot] = []
    var labels: [String: String] = [:]          // hotspot id → yozuv
    var initialDirection: SIMD3<Float>? = nil   // tasvir (qayta) yuklanganda qaysi tomonga qarash
    var onHotspotTap: ((TourHotspot) -> Void)? = nil
    var onFreeTap: ((_ yaw: Float, _ pitch: Float) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.isJitteringEnabled = false

        let scene = SCNScene()
        view.scene = scene

        let sphere = SCNSphere(radius: 20)
        sphere.segmentCount = 96
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.diffuse.contents = UIColor.black
        // Ichkaridan qaralganda tekstura ko'zguda — gorizontal aylantiramiz.
        material.diffuse.wrapS = .repeat
        material.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(-1, 1, 1), SCNMatrix4MakeTranslation(1, 0, 0))
        sphere.materials = [material]
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.name = "sphere"
        // SCNSphere UV choki +X da; panorama markazi (dunyo −Z) kameraga qarasin.
        sphereNode.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        scene.rootNode.addChildNode(sphereNode)

        let camera = SCNCamera()
        camera.fieldOfView = 80
        camera.zNear = 0.1
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3Zero
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode

        let hotspotRoot = SCNNode()
        hotspotRoot.name = "hotspots"
        scene.rootNode.addChildNode(hotspotRoot)

        let c = context.coordinator
        c.cameraNode = cameraNode
        c.sphereMaterial = material
        c.hotspotRoot = hotspotRoot
        c.view = view

        view.addGestureRecognizer(UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))))
        view.addGestureRecognizer(UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:))))
        c.apply(self)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.apply(self)
    }

    final class Coordinator: NSObject {
        var cameraNode: SCNNode?
        var sphereMaterial: SCNMaterial?
        var hotspotRoot: SCNNode?
        weak var view: SCNView?
        var onHotspotTap: ((TourHotspot) -> Void)?
        var onFreeTap: ((Float, Float) -> Void)?

        private var yaw: Float = 0
        private var pitch: Float = 0
        private var startYaw: Float = 0
        private var startPitch: Float = 0
        private var startFov: CGFloat = 80
        private var loadedImage: UIImage?
        private var renderedKey = ""
        private var hotspotById: [String: TourHotspot] = [:]

        func apply(_ v: PanoramaSceneView) {
            onHotspotTap = v.onHotspotTap
            onFreeTap = v.onFreeTap
            if loadedImage !== v.image {
                loadedImage = v.image
                sphereMaterial?.diffuse.contents = v.image
                if let d = v.initialDirection { look(at: d) } else { setAngles(yaw: 0, pitch: 0) }
            }
            let key = v.hotspots.map { "\($0.id):\($0.yaw):\($0.pitch):\(v.labels[$0.id] ?? "")" }.joined(separator: "|")
            if key != renderedKey {
                renderedKey = key
                rebuildHotspots(v.hotspots, labels: v.labels)
            }
        }

        // MARK: kamera

        private func setAngles(yaw y: Float, pitch p: Float) {
            yaw = y
            pitch = min(max(p, -.pi / 2 + 0.05), .pi / 2 - 0.05)
            cameraNode?.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        /// eulerAngles (pitch, yaw, 0) uchun kamera oldi = (−cos p·sin y, sin p, −cos p·cos y).
        func look(at d: SIMD3<Float>) {
            let a = TourHotspot.angles(of: d)
            setAngles(yaw: a.yaw, pitch: a.pitch)
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let cam = cameraNode, let v = view else { return }
            let t = g.translation(in: v)
            if g.state == .began {
                startYaw = yaw
                startPitch = pitch
            }
            let fov = Float(cam.camera?.fieldOfView ?? 80) * .pi / 180
            let perPixel = fov / Float(v.bounds.width)
            setAngles(yaw: startYaw + Float(t.x) * perPixel, pitch: startPitch + Float(t.y) * perPixel)
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let cam = cameraNode?.camera else { return }
            if g.state == .began { startFov = cam.fieldOfView }
            cam.fieldOfView = min(max(startFov / g.scale, 25), 110)
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let v = view else { return }
            let p = g.location(in: v)
            let hits = v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
            // avval hotspot'lar (ular sfera ichida)
            for h in hits {
                var n: SCNNode? = h.node
                while let node = n {
                    if let name = node.name, name.hasPrefix("hs:"), let hs = hotspotById[String(name.dropFirst(3))] {
                        onHotspotTap?(hs)
                        return
                    }
                    n = node.parent
                }
            }
            if let sphereHit = hits.first(where: { $0.node.name == "sphere" }) {
                let w = sphereHit.worldCoordinates
                let a = TourHotspot.angles(of: SIMD3(w.x, w.y, w.z))
                onFreeTap?(a.yaw, a.pitch)
            }
        }

        // MARK: hotspot'lar

        private func rebuildHotspots(_ list: [TourHotspot], labels: [String: String]) {
            guard let root = hotspotRoot else { return }
            root.childNodes.forEach { $0.removeFromParentNode() }
            hotspotById = [:]
            for hs in list {
                hotspotById[hs.id] = hs
                let node = makeHotspotNode(caption: labels[hs.id] ?? hs.label ?? "")
                node.name = "hs:\(hs.id)"
                let d = hs.direction
                node.position = SCNVector3(d.x * 12, d.y * 12, d.z * 12)
                root.addChildNode(node)
            }
        }

        private func makeHotspotNode(caption: String) -> SCNNode {
            let img = Self.renderBadge(caption: caption)
            let aspect = img.size.width / img.size.height
            let h: CGFloat = 1.6
            let plane = SCNPlane(width: h * aspect, height: h)
            let m = SCNMaterial()
            m.diffuse.contents = img
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.readsFromDepthBuffer = false
            m.writesToDepthBuffer = false
            plane.materials = [m]
            let node = SCNNode(geometry: plane)
            node.renderingOrder = 10
            node.constraints = [SCNBillboardConstraint()]
            return node
        }

        /// Ko'k disk, eshik belgisi va ostida yozuv (uzbekistan360 markerlaridek).
        static func renderBadge(caption: String) -> UIImage {
            let font = UIFont.systemFont(ofSize: 34, weight: .semibold)
            let text = caption as NSString
            let textSize = text.size(withAttributes: [.font: font])
            let disc: CGFloat = 120
            let pad: CGFloat = 16
            let w = max(disc, textSize.width + 2 * pad) + 8
            let hgt = disc + (caption.isEmpty ? 0 : textSize.height + 2 * pad + 8)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: hgt))
            return renderer.image { ctx in
                let g = ctx.cgContext
                let cx = w / 2
                g.setFillColor(UIColor.white.withAlphaComponent(0.85).cgColor)
                g.fillEllipse(in: CGRect(x: cx - disc / 2, y: 0, width: disc, height: disc))
                g.setFillColor(UIColor(red: 0.18, green: 0.47, blue: 0.85, alpha: 1).cgColor)
                g.fillEllipse(in: CGRect(x: cx - disc / 2 + 8, y: 8, width: disc - 16, height: disc - 16))
                let cfg = UIImage.SymbolConfiguration(pointSize: 52, weight: .semibold)
                if let sym = UIImage(systemName: "door.left.hand.open", withConfiguration: cfg)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let s = sym.size
                    sym.draw(in: CGRect(x: cx - s.width / 2, y: disc / 2 - s.height / 2, width: s.width, height: s.height))
                }
                if !caption.isEmpty {
                    let boxW = textSize.width + 2 * pad
                    let box = CGRect(x: cx - boxW / 2, y: disc + 8, width: boxW, height: textSize.height + 2 * pad)
                    let path = UIBezierPath(roundedRect: box, cornerRadius: box.height / 2)
                    g.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
                    g.addPath(path.cgPath)
                    g.fillPath()
                    text.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad),
                              withAttributes: [.font: font, .foregroundColor: UIColor.white])
                }
            }
        }
    }
}

// MARK: - Tur ekrani

/// Tur bo'ylab yurish: joriy xonaning 360° si va boshqa xonalarga olib
/// boradigan hotspot'lar. Tahrir rejimi panorama ichiga bosib tugma
/// qo'yadi / ko'chiradi / o'chiradi.
@available(iOS 16.0, *)
struct PanoTourView: View {
    let rooms: [TourRoom]
    let editable: Bool
    let strings: [String: String]
    /// Yopilganda: yakuniy havolalar (xona kaliti → hotspot'lar) va ixtiyoriy amal.
    let onClose: (_ links: [String: [TourHotspot]], _ action: [String: Any]?) -> Void

    @State var currentKey: String
    @State var links: [String: [TourHotspot]]

    @State private var image: UIImage?
    @State private var loading = false
    @State private var loadError: String?
    @State private var loadToken = 0
    @State private var retryAttempt = 0

    @State private var editing = false
    @State private var history: [String] = []
    @State private var entryDirection: SIMD3<Float>? = nil
    @State private var pendingTap: (yaw: Float, pitch: Float)? = nil
    @State private var movingHotspot: TourHotspot? = nil
    @State private var hotspotActions: TourHotspot? = nil
    @State private var showRooms = false
    @State private var flash = false
    @State private var notice: String? = nil

    init(rooms: [TourRoom], links: [String: [TourHotspot]], startKey: String, editable: Bool,
         strings: [String: String],
         onClose: @escaping (_ links: [String: [TourHotspot]], _ action: [String: Any]?) -> Void) {
        self.rooms = rooms
        self.editable = editable
        self.strings = strings
        self.onClose = onClose
        _currentKey = State(initialValue: startKey)
        _links = State(initialValue: links)
    }

    private func s(_ key: String, _ fallback: String) -> String { strings[key] ?? fallback }

    private var current: TourRoom? { rooms.first { $0.key == currentKey } }
    private var currentLinks: [TourHotspot] { links[currentKey] ?? [] }
    private func room(_ key: String) -> TourRoom? { rooms.first { $0.key == key } }
    private func name(_ key: String) -> String { room(key)?.name ?? s("room", "Xona") }

    private var labels: [String: String] {
        var out: [String: String] = [:]
        for h in currentLinks {
            out[h.id] = (h.label?.isEmpty == false ? h.label! : name(h.targetKey))
        }
        return out
    }

    var body: some View {
        ZStack {
            // Match the working local preview: create the SceneKit sphere with
            // its texture already available. A nil texture renders solid white
            // and also hides white loading/error UI when a download fails.
            if let image {
                PanoramaSceneView(image: image,
                              hotspots: currentLinks,
                              labels: labels,
                              initialDirection: entryDirection,
                              onHotspotTap: { hs in hotspotTapped(hs) },
                              onFreeTap: { yaw, pitch in freeTapped(yaw: yaw, pitch: pitch) })
                .ignoresSafeArea()
            }
            if loading || (image == nil && loadError == nil) {
                ProgressView().scaleEffect(1.5).tint(.white)
            } else if let e = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "photo").font(.system(size: 44)).foregroundStyle(.white)
                    Text(e).font(.headline).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button(s("retry", "Qayta urinish")) { retryAttempt += 1 }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("pano.retry")
                }
                .padding(24)
                .accessibilityIdentifier("pano.error")
            }
            if flash { Color.black.ignoresSafeArea().transition(.opacity) }
            overlay
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .task(id: [currentKey, String(retryAttempt)]) { await load() }
        .sheet(isPresented: Binding(get: { pendingTap != nil }, set: { if !$0 { pendingTap = nil } })) {
            targetPicker
        }
        .confirmationDialog(s("hotspot_title", "Tugma"),
                            isPresented: Binding(get: { hotspotActions != nil }, set: { if !$0 { hotspotActions = nil } }),
                            titleVisibility: .visible) {
            if let hs = hotspotActions {
                Button(s("move", "Ko'chirish (yangi joyga bosing)")) { movingHotspot = hs }
                Button(s("remove", "O'chirish"), role: .destructive) { removeHotspot(hs) }
                Button(s("cancel", "Bekor"), role: .cancel) {}
            }
        } message: {
            if let hs = hotspotActions { Text("→ \(name(hs.targetKey))") }
        }
        .sheet(isPresented: $showRooms) { roomsSheet }
    }

    @MainActor
    private func load() async {
        loadToken += 1
        let token = loadToken
        guard let r = current else { loadError = s("err", "Panoramani ochib bo'lmadi"); return }
        loading = true
        loadError = nil
        image = nil   // bir vaqtda BITTA dekod qilingan tasvir (xotira)
        do {
            let img = try await PanoImageLoader.load(path: r.path, url: r.url)
            guard !Task.isCancelled, token == loadToken, r.key == currentKey else { return }
            image = img
        } catch {
            guard !Task.isCancelled, token == loadToken, r.key == currentKey else { return }
            switch error {
            case PanoImageLoader.LoadError.missing:
                loadError = s("err_missing", "Fayl endi qurilmada yo'q")
            case PanoImageLoader.LoadError.invalidSource:
                loadError = s("err", "Panoramani ochib bo'lmadi")
            case PanoImageLoader.LoadError.decode:
                loadError = s("err_decode", "Fayl buzilgan")
            case PanoImageLoader.LoadError.network(let status):
                loadError = "\(s("err_network", "Yuklab bo'lmadi")) (HTTP \(status))"
            default:
                loadError = "\(s("err_network", "Yuklab bo'lmadi")) (\((error as NSError).code))"
            }
            // No URL query, auth token or device file path in diagnostics.
            NSLog("[PanoViewer] image load failed: source=%@ domain=%@ code=%ld",
                  r.url == nil ? "local" : "remote", (error as NSError).domain, (error as NSError).code)
        }
        loading = false
    }

    // MARK: qoplama

    private var overlay: some View {
        VStack {
            HStack(spacing: 10) {
                circleButton("xmark") { onClose(links, nil) }
                if !history.isEmpty {
                    circleButton("arrow.uturn.backward") { goBack() }
                }
                Spacer()
                Text(current?.name ?? "")
                    .font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                Spacer()
                circleButton("list.bullet") { showRooms = true }
                if editable {
                    circleButton(editing ? "checkmark" : "pencil", tint: editing ? .green : .white) {
                        editing.toggle()
                        movingHotspot = nil
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 14)
            Spacer()
            if let n = notice {
                Text(n).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 12)
            }
            if editing {
                VStack(spacing: 6) {
                    if movingHotspot != nil {
                        Text(s("move_here", "Tugmaning yangi joyiga bosing")).font(.subheadline.weight(.semibold))
                    } else {
                        Text(s("edit_place", "Eshik yoki o'tish joyiga bosing — tugma qo'yiladi")).font(.subheadline.weight(.semibold))
                        Text(s("edit_existing", "Mavjud tugmaga bosib: ko'chirish / o'chirish")).font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 24)
            } else if editable, currentLinks.isEmpty, rooms.count > 1 {
                Text(s("no_links", "Boshqa xonalarga o'tish tugmalari yo'q — ✎ bilan qo'shing"))
                    .font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 24)
            } else if !editable {
                Text(s("view_hint", "Atrofga qarash uchun suring · kattalashtirish — chimdib"))
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }

    private func circleButton(_ symbol: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 42, height: 42).background(.black.opacity(0.45), in: Circle())
        }
    }

    private func showNotice(_ text: String) {
        withAnimation { notice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { if notice == text { notice = nil } }
        }
    }

    // MARK: varaqlar

    private var targetPicker: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        // Tushirish Dart tarafda: ekran amal bilan yopiladi.
                        guard let t = pendingTap else { return }
                        pendingTap = nil
                        onClose(links, [
                            "type": "newRoom",
                            "fromKey": currentKey,
                            "yawDeg": TourHotspot.yawToDeg(t.yaw),
                            "pitchDeg": Double(t.pitch) * 180 / .pi,
                        ])
                    } label: {
                        Label(s("new_room", "Yangi xona — hozir tushirish"), systemImage: "camera.viewfinder").font(.headline)
                    }
                }
                Section(s("pick_title", "Qaysi panoramaga olib boradi?")) {
                    ForEach(rooms.filter { $0.key != currentKey }) { r in
                        Button {
                            if let t = pendingTap { addHotspot(yaw: t.yaw, pitch: t.pitch, target: r) }
                            pendingTap = nil
                        } label: {
                            HStack {
                                Text(r.name)
                                Spacer()
                                if (links[currentKey] ?? []).contains(where: { $0.targetKey == r.key }) {
                                    Text(s("linked", "bog'langan")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if rooms.count < 2 {
                        Text(s("need_two", "Tur uchun kamida ikkita 360° kerak")).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(s("hotspot_title", "Tugma"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(s("cancel", "Bekor")) { pendingTap = nil } } }
        }
        .presentationDetents([.medium])
    }

    private var roomsSheet: some View {
        NavigationStack {
            List(rooms) { r in
                Button {
                    showRooms = false
                    if r.key != currentKey { jump(to: r.key, direction: nil) }
                } label: {
                    HStack {
                        Text(r.name).fontWeight(r.key == currentKey ? .bold : .regular)
                        Spacer()
                        if r.key == currentKey { Image(systemName: "location.fill").foregroundStyle(.blue) }
                    }
                }
            }
            .navigationTitle(s("rooms", "Xonalar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(s("close", "Yopish")) { showRooms = false } } }
        }
        .presentationDetents([.medium])
    }

    // MARK: amallar

    private func hotspotTapped(_ hs: TourHotspot) {
        if editing {
            hotspotActions = hs
            return
        }
        guard room(hs.targetKey) != nil else { return }
        // Eshikdan kirganda: o'sha xonada bizga qaytadigan tugma bo'lsa, undan
        // teskari tomonga qaraymiz.
        let back = (links[hs.targetKey] ?? []).first { $0.targetKey == currentKey }
        history.append(currentKey)
        jump(to: hs.targetKey, direction: back.map { -$0.direction })
    }

    private func freeTapped(yaw: Float, pitch: Float) {
        guard editing else { return }
        if let hs = movingHotspot {
            var list = currentLinks
            if let i = list.firstIndex(where: { $0.id == hs.id }) {
                list[i].yaw = yaw
                list[i].pitch = pitch
                links[currentKey] = list
            }
            movingHotspot = nil
            return
        }
        if currentLinks.count >= kMaxTourLinksPerPanorama {
            showNotice(s("limit", "Bu panoramada o'tishlar soni to'lgan"))
            return
        }
        pendingTap = (yaw, pitch)
    }

    private static func angleDeg(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        acos(max(-1, min(1, simd_dot(simd_normalize(a), simd_normalize(b))))) * 180 / .pi
    }

    private func addHotspot(yaw: Float, pitch: Float, target: TourRoom) {
        var list = currentLinks
        let new = TourHotspot(id: UUID().uuidString, yaw: yaw, pitch: pitch, targetKey: target.key, label: nil)
        if list.contains(where: { Self.angleDeg($0.direction, new.direction) < kMinHotspotSeparationDeg }) {
            showNotice(s("too_close", "Bu yerda allaqachon o'tish bor — boshqa joyga qarating"))
        }
        list.append(new)
        links[currentKey] = list
        // Teskari havola — tur ikki tomonga yurilsin (keyin ko'chirsa bo'ladi).
        var tl = links[target.key] ?? []
        if !tl.contains(where: { $0.targetKey == currentKey }), tl.count < kMaxTourLinksPerPanorama {
            let d = new.direction
            let back = TourHotspot.angles(of: -SIMD3(d.x, 0, d.z))
            tl.append(TourHotspot(id: UUID().uuidString, yaw: back.yaw, pitch: 0, targetKey: currentKey, label: nil))
            links[target.key] = tl
        }
    }

    private func removeHotspot(_ hs: TourHotspot) {
        var list = currentLinks
        list.removeAll { $0.id == hs.id }
        links[currentKey] = list
    }

    private func goBack() {
        guard let prev = history.popLast() else { return }
        jump(to: prev, direction: nil)
    }

    private func jump(to key: String, direction: SIMD3<Float>?) {
        withAnimation(.easeIn(duration: 0.15)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            entryDirection = direction
            currentKey = key
            movingHotspot = nil
            withAnimation(.easeOut(duration: 0.35)) { flash = false }
        }
    }
}

// MARK: - Natija ko'rish (tikishdan keyin)

/// Uy360 `LocalResultView` ning kadastr varianti: tikilgan panoramani sferada
/// ko'rsatadi; «Davom etish» — Dart yuklaydi, «Qayta tushirish» — kadrlar
/// tashlanadi va capture qaytadan ochiladi.
struct PanoPreviewView: View {
    let path: String
    let strings: [String: String]
    let onAccept: () -> Void
    let onRetake: () -> Void

    private func s(_ key: String, _ fallback: String) -> String { strings[key] ?? fallback }

    var body: some View {
        ZStack {
            PanoramaSceneView(image: UIImage(contentsOfFile: path)).ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Text(s("preview_title", "Natija")).font(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                    Spacer()
                }
                .padding(.top, 14)
                Spacer()
                Text(s("view_hint", "Atrofga qarash uchun suring · kattalashtirish — chimdib"))
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 8)
                HStack(spacing: 12) {
                    Button { onRetake() } label: {
                        Label(s("retake", "Qayta tushirish"), systemImage: "camera.rotate")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.white)
                    Button { onAccept() } label: {
                        Label(s("accept", "Davom etish"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
        }
        .background(Color.black)
        .statusBarHidden(true)
    }
}

// MARK: - Koordinator (Flutter kanali)

/// `tour` va `preview` metodlarini ochadi; natija bir marta qaytariladi.
@available(iOS 15.0, *)
final class PanoTourCoordinator {
    static let shared = PanoTourCoordinator()

    private var host: UIViewController?
    private var pending: FlutterResult?

    private func finish(with value: Any?) {
        let cb = pending
        pending = nil
        host?.dismiss(animated: true) { [weak self] in
            self?.host = nil
            cb?(value)
        }
    }

    private func present(_ view: some View, from presenter: UIViewController, result: @escaping FlutterResult) {
        pending = result
        let vc = UIHostingController(rootView: view)
        vc.modalPresentationStyle = .fullScreen
        host = vc
        presenter.present(vc, animated: true)
    }

    @available(iOS 16.0, *)
    func tour(args: [String: Any]?, from presenter: UIViewController, result: @escaping FlutterResult) {
        guard pending == nil else {
            result(FlutterError(code: "BUSY", message: "Tur allaqachon ochiq", details: nil))
            return
        }
        let strings = (args?["strings"] as? [String: String]) ?? [:]
        let rawRooms = (args?["panoramas"] as? [[String: Any]]) ?? []
        let rooms: [TourRoom] = rawRooms.enumerated().compactMap { i, r in
            guard let key = r["key"] as? String, !key.isEmpty else { return nil }
            let fallback = (strings["room_n"] ?? "Xona %d").replacingOccurrences(of: "%d", with: "\(i + 1)")
            let name = (r["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            return TourRoom(key: key, name: name, url: r["url"] as? String, path: r["path"] as? String)
        }
        guard !rooms.isEmpty else {
            result(FlutterError(code: "ARGS", message: "panoramas bo'sh", details: nil))
            return
        }
        var links: [String: [TourHotspot]] = [:]
        for l in (args?["links"] as? [[String: Any]]) ?? [] {
            guard let from = l["from"] as? String, let to = l["to"] as? String,
                  let yawDeg = (l["yawDeg"] as? NSNumber)?.doubleValue,
                  let pitchDeg = (l["pitchDeg"] as? NSNumber)?.doubleValue else { continue }
            links[from, default: []].append(TourHotspot(
                id: UUID().uuidString,
                yaw: TourHotspot.yawFromDeg(yawDeg),
                pitch: Float(pitchDeg * .pi / 180),
                targetKey: to,
                label: l["label"] as? String
            ))
        }
        let startKey = (args?["startKey"] as? String).flatMap { k in rooms.contains { $0.key == k } ? k : nil } ?? rooms[0].key
        let editable = (args?["editable"] as? Bool) ?? false

        let view = PanoTourView(rooms: rooms, links: links, startKey: startKey, editable: editable, strings: strings) { [weak self] links, action in
            var out: [[String: Any]] = []
            for (from, list) in links {
                for h in list { out.append(h.toDart(from: from)) }
            }
            var payload: [String: Any] = ["links": out]
            if let a = action { payload["action"] = a }
            self?.finish(with: payload)
        }
        present(view, from: presenter, result: result)
    }

    func preview(args: [String: Any]?, from presenter: UIViewController, result: @escaping FlutterResult) {
        guard pending == nil else {
            result(FlutterError(code: "BUSY", message: "Ko'rish allaqachon ochiq", details: nil))
            return
        }
        guard let path = args?["path"] as? String, FileManager.default.fileExists(atPath: path) else {
            result(FlutterError(code: "ARGS", message: "pano fayli topilmadi", details: nil))
            return
        }
        let strings = (args?["strings"] as? [String: String]) ?? [:]
        let view = PanoPreviewView(path: path, strings: strings,
                                   onAccept: { [weak self] in self?.finish(with: ["action": "accept"]) },
                                   onRetake: { [weak self] in self?.finish(with: ["action": "retake"]) })
        present(view, from: presenter, result: result)
    }
}
