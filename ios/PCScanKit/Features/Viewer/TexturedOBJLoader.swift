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

        objText.enumerateLines { line, _ in
            if line.hasPrefix("v ") {
                let p = line.dropFirst(2).split(separator: " ").compactMap { Float($0) }
                if p.count >= 3 { positions.append(SIMD3(p[0], p[1], p[2])) }
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
        for g in groups where !g.indices.isEmpty {
            elements.append(SCNGeometryElement(indices: g.indices, primitiveType: .triangles))
            let m = SCNMaterial()
            m.lightingModel = .constant           // ranglar allaqachon kadr yorug'ligini o'zida saqlaydi
            if g.mat == "fillmat" {
                // Teshik-to'ldirish yuzalari — winding beqaror, ikki tomonlama ko'rsatamiz.
                m.isDoubleSided = true
            } else {
                // Dollhouse effekti: kameraga qaragan (yaqin) devorlarni kesamiz, ichi ko'rinsin.
                m.isDoubleSided = false
                m.cullMode = .back
            }
            m.diffuse.contents = materials[g.mat]
            m.diffuse.wrapS = .clamp
            m.diffuse.wrapT = .clamp
            sceneMaterials.append(m)
        }
        guard !elements.isEmpty else { return nil }

        let geometry = SCNGeometry(sources: [posSource, uvSource], elements: elements)
        geometry.materials = sceneMaterials
        return SCNNode(geometry: geometry)
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
