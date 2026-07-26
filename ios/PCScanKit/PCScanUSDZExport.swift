import Foundation
import SceneKit
import UIKit

/// texrecon `room.obj` → teksturali **USDZ** (QuickLook/fallback model, backend'ga
/// GLB bilan birga yuklanadi).
///
/// `TexturedOBJLoader` OBJ+MTL+atlas'ni SCNNode qilib TO'G'RI bog'laydi (UV↔tekstura),
/// so'ng `SCNScene.write` USDZ'ga teksturani EMBED qiladi. **`MDLAsset(url: obj)`
/// ISHLATILMAYDI** — u UV↔tekstura bog'lanishini yo'qotadi (hammasi oq chiqadi,
/// `TexturedOBJLoader.swift:6-8`). RoomScan'ning `MeshExporter.exportAtlasUSDZSceneKit`
/// bilan bir xil, isbotlangan yondashuv (device'da ishlaydi).
enum PCScanUSDZExport {

    struct ExportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func export(objURL: URL, to usdzURL: URL) throws {
        guard let node = TexturedOBJLoader.load(objURL: objURL) else {
            throw ExportError(message: "OBJ SceneKit'ga yuklanmadi: \(objURL.lastPathComponent)")
        }
        // Parcha (fillmat/unseen_vc) qatlami viewer'da orbita uchun yashirilgan bo'ladi;
        // eksport uchun to'liq geometriya kerak — ko'rsatamiz. Winding allaqachon skan
        // yo'liga qaratilgan (single-sided) → orbita'da baribir culling qiladi.
        node.childNodes.forEach { $0.isHidden = false }

        // ⚠️ USDZ localizatsiyasi IN-MEMORY tekstura (SceneKit uni "texgen_N.png" deb
        // ataydi) ni topa olmaydi → "Failed to resolve reference @texgen_0.png@" xatosi.
        // Yechim: har materialning UIImage'ini vaqtinchalik faylga yozib, file-backed
        // qilamiz — shunda SCNScene.write uni USDZ ichiga to'g'ri joylaydi.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pcsusdz-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        var texIdx = 0
        node.enumerateHierarchy { n, _ in
            n.geometry?.materials.forEach { m in
                guard let img = m.diffuse.contents as? UIImage, let data = img.pngData() else { return }
                let u = tmpDir.appendingPathComponent("tex_\(texIdx).png"); texIdx += 1
                if (try? data.write(to: u)) != nil {
                    m.diffuse.contents = u   // file URL → USDZ localize qila oladi
                }
            }
        }

        let scene = SCNScene()
        scene.rootNode.addChildNode(node)
        try? FileManager.default.removeItem(at: usdzURL)
        guard scene.write(to: usdzURL, options: nil, delegate: nil, progressHandler: nil) else {
            throw ExportError(message: "USDZ yozilmadi")
        }
    }
}
