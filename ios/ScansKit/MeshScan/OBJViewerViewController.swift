import UIKit
import SceneKit
import ModelIO
import SceneKit.ModelIO

/// texrecon natijasini (OBJ + MTL + atlas PNG) SceneKit orqali ko'rsatadi.
/// SceneKit OBJ + material + teksturalarni displayда to'g'ri render qiladi.
final class OBJViewerViewController: UIViewController {

    private let objURL: URL
    private let stat: String
    private var scnView: SCNView!
    private var allMats: [SCNMaterial] = []
    private var cutaway = true

    init(objURL: URL, stat: String = "") {
        self.objURL = objURL
        self.stat = stat
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Yuqori sifat (on-device)"

        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .black
        view.addSubview(scnView)

        let folder = objURL.deletingLastPathComponent()
        let asset = MDLAsset(url: objURL)
        asset.loadTextures()
        let scene = SCNScene(mdlAsset: asset)

        // MTL'ni parse qilamiz: material nomi -> tekstura fayli (texout_material****_map_Kd.png)
        var mtlTex: [String: String] = [:]
        var orderedTex: [String] = []
        let mtlURL = folder.appendingPathComponent(objURL.deletingPathExtension().lastPathComponent + ".mtl")
        if let mtl = try? String(contentsOf: mtlURL, encoding: .utf8) {
            var cur = ""
            for raw in mtl.split(separator: "\n") {
                let p = raw.split(separator: " ", omittingEmptySubsequences: true)
                guard let key = p.first else { continue }
                if key == "newmtl", p.count > 1 { cur = String(p[1]) }
                else if key == "map_Kd", p.count > 1 {
                    mtlTex[cur] = String(p[1]); orderedTex.append(String(p[1]))
                }
            }
        }

        // Materiallarni YANGI SCNMaterial massivi bilan almashtiramiz.
        // MUHIM: MDLAsset yuklagan material'ni JOYIDA o'zgartirish iOS'da render'ga
        // yetmaydi (oq chiqadi) — faqat butun massivni fresh material bilan almashtirish ishlaydi.
        var cache: [String: UIImage] = [:]
        func img(_ file: String) -> UIImage? {
            if let c = cache[file] { return c }
            let png = folder.appendingPathComponent(file)
            guard let im = UIImage(contentsOfFile: png.path) else { return nil }
            cache[file] = im; return im
        }
        var idx = 0
        func replaceMats(_ g: SCNGeometry) {
            var newMats: [SCNMaterial] = []
            for oldMat in g.materials {
                let m = SCNMaterial()
                var file: String? = nil
                if let name = oldMat.name, let f = mtlTex[name] { file = f }
                else if idx < orderedTex.count { file = orderedTex[idx] }
                if let file, let im = img(file) { m.diffuse.contents = im }
                else { m.diffuse.contents = UIColor.gray }
                // KESIM (cutaway): bir tomonlama + orqa yuzni kesish. Xona normallari ICHKARIGA
                // qaraydi → tashqaridan qaraganда oldingi devor kesiladi, ICHKARI ko'rinadi;
                // ichkaridan qaraganда devorlar normal ko'rinadi. (Polycam/Scaniverse kabi.)
                m.isDoubleSided = false
                m.cullMode = .back
                m.lightingModel = .constant
                m.name = oldMat.name
                newMats.append(m); allMats.append(m); idx += 1
            }
            g.materials = newMats
        }
        if let g = scene.rootNode.geometry { replaceMats(g) }
        scene.rootNode.enumerateChildNodes { node, _ in
            if let g = node.geometry { replaceMats(g) }
        }
        scnView.scene = scene

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share)),
            UIBarButtonItem(title: "Kesim ✓", style: .plain, target: self, action: #selector(toggleCutaway))
        ]
    }

    /// Kesim (cutaway) yoqib/o'chirish: yoqilsa tashqaridan ichkari ko'rinadi,
    /// o'chirilsa butun model (ikkala yuz) ko'rinadi.
    @objc private func toggleCutaway() {
        cutaway.toggle()
        for m in allMats { m.isDoubleSided = !cutaway }
        navigationItem.rightBarButtonItems?.last?.title = cutaway ? "Kesim ✓" : "Kesim ✗"
    }

    @objc private func share() {
        let sheet = UIAlertController(title: "Ulashish", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "USDZ (ko'rish / AR)", style: .default) { [weak self] _ in
            self?.shareUSDZ()
        })
        sheet.addAction(UIAlertAction(title: "ZIP (xom ma'lumot)", style: .default) { [weak self] _ in
            self?.shareZIP()
        })
        sheet.addAction(UIAlertAction(title: "Bekor", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    /// OBJ+atlas'ni usdz'ga aylantirib ulashish — Files/Quick Look/AR'da YORUG' ochiladi.
    private func shareUSDZ() {
        let hud = UIActivityIndicatorView(style: .large)
        hud.center = view.center; hud.startAnimating(); view.addSubview(hud)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("Xona-\(Int(Date().timeIntervalSince1970)).usdz")
            do {
                try USDZExporter.export(objURL: self.objURL, outURL: out)
                DispatchQueue.main.async {
                    hud.removeFromSuperview()
                    let s = UIActivityViewController(activityItems: [out], applicationActivities: nil)
                    if let pop = s.popoverPresentationController { pop.barButtonItem = self.navigationItem.rightBarButtonItem }
                    self.present(s, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    hud.removeFromSuperview()
                    let a = UIAlertController(title: "USDZ xato", message: "\(error)", preferredStyle: .alert)
                    a.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(a, animated: true)
                }
            }
        }
    }

    /// Butun SKAN folderini ZIP qilib ulashish — QAYTA ISHLASH uchun XOM data ham
    /// (mesh.ply + keyframes + frames.json) qo'shiladi, nafaqat result/. Shunda eksport
    /// self-contained bo'ladi va Mac'da to'liq qayta teksturalash mumkin.
    private func shareZIP() {
        let fm = FileManager.default
        // scan ildizi = mesh.ply bor papka (result/ ning ota-papkasi)
        var folder = objURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: folder.appendingPathComponent("mesh.ply").path) {
            let parent = folder.deletingLastPathComponent()
            if fm.fileExists(atPath: parent.appendingPathComponent("mesh.ply").path) { folder = parent }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let zip = FileManager.default.temporaryDirectory
                .appendingPathComponent("XonaHQ-\(Int(Date().timeIntervalSince1970)).zip")
            var coordErr: NSError?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordErr) { url in
                try? FileManager.default.removeItem(at: zip)
                try? FileManager.default.copyItem(at: url, to: zip)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let s = UIActivityViewController(activityItems: [zip], applicationActivities: nil)
                if let pop = s.popoverPresentationController { pop.barButtonItem = self.navigationItem.rightBarButtonItem }
                self.present(s, animated: true)
            }
        }
    }
}
