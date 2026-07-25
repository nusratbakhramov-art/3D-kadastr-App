import Foundation
import SceneKit
import UIKit

/// Teksturali OBJ (texrecon chiqishi) ni SCNNode sifatida yuklaydi.
/// `MDLAsset` OBJ import qilganda UV↔tekstura bog'lanishini ishonchli o'rnatmaydi
/// (hammasi oq chiqadi), shuning uchun OBJ+MTL'ni qo'lda parse qilib,
/// aniq vertex/UV manbalari va har material uchun element quramiz.
enum TexturedOBJLoader {

    /// OBJ faylni teksturali SCNNode qilib qaytaradi (world koordinatada).
    /// Muvaffaqiyatsiz bo'lsa nil.
    static func load(objURL: URL) -> SCNNode? {
        guard let objText = try? String(contentsOf: objURL, encoding: .utf8) else { return nil }
        let dir = objURL.deletingLastPathComponent()
        let materials = parseMTL(objURL: objURL, dir: dir)

        var positions: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        struct Group { var mat: String; var indices: [Int32] = [] }
        var groups: [Group] = []
        var comboIndex: [String: Int32] = [:]
        var outPos: [SCNVector3] = []
        var outUV: [CGPoint] = []
        // Cho'qqi ranglari (v x y z r g b) — obyektlarning ko'rinmagan qismi
        // TEKSTURASIZ bo'yaladi (AtlasInpainter.vertexColorUnseen): chart yo'q →
        // chart chegarasi yo'q → chok/faset yo'q; render uchburchak ichida rangni
        // o'zi interpolyatsiya qiladi.
        var vColors: [SIMD3<Float>?] = []
        var outCol: [SCNVector3] = []
        var anyVertexColor = false

        objText.enumerateLines { line, _ in
            if line.hasPrefix("v ") {
                let p = line.dropFirst(2).split(separator: " ").compactMap { Float($0) }
                if p.count >= 3 {
                    positions.append(SIMD3(p[0], p[1], p[2]))
                    if p.count >= 6 {
                        vColors.append(SIMD3(p[3], p[4], p[5])); anyVertexColor = true
                    } else {
                        vColors.append(nil)
                    }
                }
            } else if line.hasPrefix("vt ") {
                let p = line.dropFirst(3).split(separator: " ").compactMap { Float($0) }
                if p.count >= 2 { texcoords.append(SIMD2(p[0], p[1])) }
            } else if line.hasPrefix("usemtl ") {
                groups.append(Group(mat: String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("f ") {
                if groups.isEmpty { groups.append(Group(mat: "")) }
                let verts = line.dropFirst(2).split(separator: " ")
                var tri: [Int32] = []
                for v in verts {
                    let key = String(v)
                    if let existing = comboIndex[key] {
                        tri.append(existing)
                    } else {
                        let parts = v.split(separator: "/", omittingEmptySubsequences: false)
                        guard let vi = Int(parts[0]), vi >= 1, vi <= positions.count else { continue }
                        let e = Int32(outPos.count)
                        let pos = positions[vi - 1]
                        outPos.append(SCNVector3(pos.x, pos.y, pos.z))
                        let vc = vi - 1 < vColors.count ? vColors[vi - 1] : nil
                        outCol.append(SCNVector3(vc?.x ?? 1, vc?.y ?? 1, vc?.z ?? 1))
                        if parts.count > 1, !parts[1].isEmpty, let ti = Int(parts[1]), ti >= 1, ti <= texcoords.count {
                            let uv = texcoords[ti - 1]
                            outUV.append(CGPoint(x: CGFloat(uv.x), y: CGFloat(1 - uv.y)))  // OBJ→SceneKit V flip
                        } else {
                            outUV.append(.zero)
                        }
                        comboIndex[key] = e
                        tri.append(e)
                    }
                }
                // Fan triangulyatsiya (poligon → uchburchaklar).
                if tri.count >= 3 {
                    for k in 1..<(tri.count - 1) {
                        groups[groups.count - 1].indices.append(contentsOf: [tri[0], tri[k], tri[k + 1]])
                    }
                }
            }
        }

        guard !outPos.isEmpty else { return nil }

        let posSource = SCNGeometrySource(vertices: outPos)
        let uvSource = SCNGeometrySource(textureCoordinates: outUV)
        var elements: [SCNGeometryElement] = []
        var sceneMaterials: [SCNMaterial] = []
        let cams = loadCameraPositions(objURL: objURL)
        // Parcha qatlami: `unseen_vc` + `fillmat`. Ular mayda va ko'p (o'lchandi,
        // #26: 940 + 267 ta ajralgan dog'). Winding'ni to'g'rilash ularni ORQADAN
        // kesadi, lekin QIYA burchakda normal hali kameraga qaragan bo'lib qoladi
        // va parcha ko'rinaveradi. Shuning uchun ular alohida tugunga chiqariladi:
        // yurish rejimida (ichkarida) ko'rinadi, orbita rejimida (tashqaridan)
        // yashiriladi — burchakdan qat'i nazar.
        var fragElements: [SCNGeometryElement] = []
        var fragMaterials: [SCNMaterial] = []
        for g in groups where !g.indices.isEmpty {
            var idx = g.indices
            // `unseen_vc` va `fillmat` tarixan IKKI TOMONLAMA chizilardi ("winding
            // beqaror"), ya'ni culling ularni hech qachon olib tashlamasdi va ular
            // ORQA tomondan ham parcha bo'lib ko'rinardi. Winding'ni skan kamera
            // yo'liga qarab to'g'rilaymiz, so'ng devor kabi bir tomonlama qilamiz:
            // to'g'ri tomondan ko'rinadi, orqadan kesiladi. (Ularni O'CHIRISH
            // sinab ko'rilgan va YARAMAGAN — to'g'ri tomondan teshik ochilgan.)
            let needsOrient = materials[g.mat] == nil || g.mat == "fillmat"
            if needsOrient, !cams.isEmpty {
                idx = orientToScanPath(idx, positions: outPos, cams: cams)
            }
            if idx.isEmpty { continue }
            elements.append(SCNGeometryElement(indices: idx, primitiveType: .triangles))
            let m = SCNMaterial()
            m.lightingModel = .constant           // ranglar allaqachon kadr yorug'ligini o'zida saqlaydi
            if g.mat == "fillmat" {
                // Winding yuqorida kamera yo'liga qarab to'g'rilangan bo'lsa bir
                // tomonlama; kamera yo'li yo'q (eski skan) — ikki tomonlama.
                m.isDoubleSided = cams.isEmpty
                m.cullMode = .back
            } else {
                // Dollhouse effekti: kameraga qaragan (yaqin) devorlarni kesamiz, ichi ko'rinsin.
                m.isDoubleSided = false
                m.cullMode = .back
            }
            if let tex = materials[g.mat] {
                m.diffuse.contents = tex
            } else {
                // Teksturasiz material (obyektlarning ko'rinmagan qismi) — rang
                // cho'qqilardan keladi. OQ diffuse: SceneKit uni cho'qqi rangiga
                // ko'paytiradi. Bu YO'Q bo'lsa diffuse nil qoladi va .constant
                // yorug'lik modelida yuza QOP-QORA chiqadi.
                m.diffuse.contents = UIColor.white
                m.isDoubleSided = cams.isEmpty   // winding to'g'rilangan -> bir tomonlama
                m.cullMode = .back
            }
            m.diffuse.wrapS = .clamp
            m.diffuse.wrapT = .clamp
            if needsOrient {
                fragElements.append(SCNGeometryElement(indices: idx, primitiveType: .triangles))
                fragMaterials.append(m)
                elements.removeLast()
            } else {
                sceneMaterials.append(m)
            }
        }
        guard !elements.isEmpty else { return nil }

        var sources: [SCNGeometrySource] = [posSource, uvSource]
        if anyVertexColor {
            // SCNGeometrySource'da `colors:` qulay initsializatori yo'q — qo'lda.
            // SCNVector3 iOS'da 3 ta Float (stride 12), ya'ni zich joylashadi.
            let data = outCol.withUnsafeBufferPointer { Data(buffer: $0) }
            sources.append(SCNGeometrySource(data: data, semantic: .color,
                                             vectorCount: outCol.count,
                                             usesFloatComponents: true,
                                             componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size,
                                             dataOffset: 0,
                                             dataStride: MemoryLayout<SCNVector3>.stride))
        }
        let geometry = SCNGeometry(sources: sources, elements: elements)
        geometry.materials = sceneMaterials
        let inner = SCNNode(geometry: geometry)
        guard !fragElements.isEmpty else { return inner }

        inner.name = "ichkiVaraq"
        let parent = SCNNode()
        parent.addChildNode(inner)
        if !fragElements.isEmpty {
            let fragGeo = SCNGeometry(sources: sources, elements: fragElements)
            fragGeo.materials = fragMaterials
            let frag = SCNNode(geometry: fragGeo)
            frag.name = fragmentNodeName
            frag.isHidden = true          // boshlang'ich: orbita rejimi
            parent.addChildNode(frag)
        }
        return parent
    }

    /// Parcha qatlami (unseen_vc + fillmat) — faqat yurish rejimida ko'rsatiladi.
    static let fragmentNodeName = "parchaQatlam"

    /// Teksturasiz / teshik-parda yuzalarining winding'ini skan kamera yo'liga
    /// qaratadi, shunda ular devor kabi bir tomonlama bo'la oladi.
    private static func orientToScanPath(_ indices: [Int32], positions: [SCNVector3],
                                         cams: [SIMD3<Float>]) -> [Int32] {
        var out = indices
        var i = 0
        while i + 2 < out.count {
            let a = positions[Int(out[i])], b = positions[Int(out[i + 1])]
            let c = positions[Int(out[i + 2])]
            let pa = SIMD3<Float>(Float(a.x), Float(a.y), Float(a.z))
            let pb = SIMD3<Float>(Float(b.x), Float(b.y), Float(b.z))
            let pc = SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z))
            let n = simd_cross(pb - pa, pc - pa)
            let ctr = (pa + pb + pc) / 3
            var best = Float.greatestFiniteMagnitude
            var bestCam = cams[0]
            for cam in cams {
                let d = simd_length_squared(cam - ctr)
                if d < best { best = d; bestCam = cam }
            }
            if simd_dot(n, bestCam - ctr) < 0 { out.swapAt(i + 1, i + 2) }
            i += 3
        }
        return out
    }

    /// Skan kamera pozitsiyalari (frames.json, obj'dan bir pog'ona yuqorida).
    private static func loadCameraPositions(objURL: URL) -> [SIMD3<Float>] {
        let root = objURL.deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appendingPathComponent("frames.json")),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(arr.count)
        for f in arr {
            guard let t = f["transform"] as? [Double], t.count >= 16 else { continue }
            out.append(SIMD3(Float(t[12]), Float(t[13]), Float(t[14])))
        }
        // Har uchburchak uchun eng yaqinini qidiramiz — kadrni siyraklashtiramiz
        // (kamera yo'li zich, 200 ta nuqta yo'l shaklini to'liq beradi).
        guard out.count > 200 else { return out }
        let stride = out.count / 200 + 1
        return Swift.stride(from: 0, to: out.count, by: stride).map { out[$0] }
    }

    /// MTL fayldan `material nomi → atlas UIImage` xaritasi.
    private static func parseMTL(objURL: URL, dir: URL) -> [String: UIImage] {
        var mtlName = objURL.deletingPathExtension().lastPathComponent + ".mtl"
        if let handle = try? FileHandle(forReadingFrom: objURL) {
            let head = handle.readData(ofLength: 4096)
            try? handle.close()
            if let text = String(data: head, encoding: .utf8) {
                for line in text.split(separator: "\n") where line.hasPrefix("mtllib ") {
                    mtlName = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        guard let mtl = try? String(contentsOf: dir.appendingPathComponent(mtlName), encoding: .utf8) else { return [:] }
        var result: [String: UIImage] = [:]
        var current: String?
        for raw in mtl.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("newmtl ") {
                current = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("map_Kd "), let name = current {
                let png = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                if let img = UIImage(contentsOfFile: dir.appendingPathComponent(png).path) {
                    result[name] = img
                }
            }
        }
        return result
    }
}
