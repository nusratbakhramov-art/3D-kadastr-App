import Foundation
import simd

/// texrecon `room.obj` (+`room.mtl` + atlas PNG'lari) ni **GLB** (binary glTF 2.0) ga
/// eksport qiladi — backend'ga yuklanadigan asosiy 3D model. **Sof Foundation+simd**
/// (UIKit/SceneKit YO'Q) → simulyatorda ham ishlaydi va macOS harness'da sinaladi.
///
/// texrecon OBJ **ko'p-materialli + ko'p atlas-sahifali**; `unseen_vc`/`fillmat`
/// guruhlari TEKSTURASIZ (per-vertex rang: `v x y z r g b`). Shuning uchun:
///   • har `usemtl` guruhi → alohida glTF primitiv;
///   • teksturali guruh → `baseColorTexture` (mos atlas PNG, BIN chunk'ga embed);
///   • vertex-rangli guruh → `COLOR_0` (tekstura'siz).
/// UV `1-v` ga flip qilinadi (OBJ pastki-chap → glTF yuqori-chap). Materiallar
/// `KHR_materials_unlit` — ranglar allaqachon kadr yorug'ligini o'zida saqlaydi
/// (kit viewer'ining `.constant` ko'rinishiga mos). `TexturedOBJLoader` parse mantig'i
/// aynan takrorlangan (dedup, fan-triangulyatsiya).
enum PCScanGLBExport {

    struct ExportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `objURL` (texrecon room.obj) → `glbURL`. Xatoda `ExportError`.
    static func export(objURL: URL, to glbURL: URL) throws {
        guard let objText = try? String(contentsOf: objURL, encoding: .utf8) else {
            throw ExportError(message: "OBJ o'qib bo'lmadi: \(objURL.lastPathComponent)")
        }
        let dir = objURL.deletingLastPathComponent()
        let mtl = parseMTL(objText: objText, dir: dir)   // material nomi → atlas PNG URL

        var positions: [SIMD3<Float>] = []
        var vColors: [SIMD3<Float>?] = []
        var texcoords: [SIMD2<Float>] = []
        struct Group { var mat: String; var indices: [UInt32] = [] }
        var groups: [Group] = []
        var comboIndex: [String: UInt32] = [:]
        var outPos: [SIMD3<Float>] = []
        var outUV: [SIMD2<Float>] = []
        var outCol: [SIMD3<Float>] = []
        var anyVertexColor = false

        objText.enumerateLines { line, _ in
            if line.hasPrefix("v ") {
                let p = line.dropFirst(2).split(separator: " ").compactMap { Float($0) }
                if p.count >= 3 {
                    positions.append(SIMD3(p[0], p[1], p[2]))
                    if p.count >= 6 { vColors.append(SIMD3(p[3], p[4], p[5])); anyVertexColor = true }
                    else { vColors.append(nil) }
                }
            } else if line.hasPrefix("vt ") {
                let p = line.dropFirst(3).split(separator: " ").compactMap { Float($0) }
                if p.count >= 2 { texcoords.append(SIMD2(p[0], p[1])) }
            } else if line.hasPrefix("usemtl ") {
                groups.append(Group(mat: String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("f ") {
                if groups.isEmpty { groups.append(Group(mat: "")) }
                let verts = line.dropFirst(2).split(separator: " ")
                var tri: [UInt32] = []
                for v in verts {
                    let key = String(v)
                    if let e = comboIndex[key] { tri.append(e); continue }
                    let parts = v.split(separator: "/", omittingEmptySubsequences: false)
                    guard let vi = Int(parts[0]), vi >= 1, vi <= positions.count else { continue }
                    let e = UInt32(outPos.count)
                    outPos.append(positions[vi - 1])
                    let vc = (vi - 1 < vColors.count) ? vColors[vi - 1] : nil
                    outCol.append(vc ?? SIMD3(1, 1, 1))
                    if parts.count > 1, !parts[1].isEmpty, let ti = Int(parts[1]), ti >= 1, ti <= texcoords.count {
                        let uv = texcoords[ti - 1]
                        outUV.append(SIMD2(uv.x, 1 - uv.y))   // OBJ→glTF V flip
                    } else {
                        outUV.append(SIMD2(0, 0))
                    }
                    comboIndex[key] = e
                    tri.append(e)
                }
                // Fan triangulyatsiya (poligon → uchburchaklar).
                if tri.count >= 3 {
                    for k in 1..<(tri.count - 1) {
                        groups[groups.count - 1].indices.append(contentsOf: [tri[0], tri[k], tri[k + 1]])
                    }
                }
            }
        }

        let nonEmpty = groups.filter { !$0.indices.isEmpty }
        guard !outPos.isEmpty, !nonEmpty.isEmpty else {
            throw ExportError(message: "OBJ bo'sh yoki uchburchaksiz")
        }

        // ---- BIN buferi + bufferView'lar ----
        var bin = Data()
        var bufferViews: [[String: Any]] = []
        func align4() { while bin.count % 4 != 0 { bin.append(0) } }
        func addBV(_ data: Data, target: Int?) -> Int {
            let off = bin.count
            bin.append(data)
            var bv: [String: Any] = ["buffer": 0, "byteOffset": off, "byteLength": data.count]
            if let target { bv["target"] = target }
            align4()
            bufferViews.append(bv)
            return bufferViews.count - 1
        }
        func floatData(_ arr: [Float]) -> Data { arr.withUnsafeBufferPointer { Data(buffer: $0) } }

        var accessors: [[String: Any]] = []

        // Har guruh uchun indeks accessor (u32).
        var idxAcc: [Int] = []
        for g in nonEmpty {
            let bv = addBV(g.indices.withUnsafeBufferPointer { Data(buffer: $0) }, target: 34963)  // ELEMENT_ARRAY_BUFFER
            accessors.append(["bufferView": bv, "componentType": 5125, "count": g.indices.count, "type": "SCALAR"])
            idxAcc.append(accessors.count - 1)
        }

        // POSITION (VEC3 f32 + min/max).
        var posF = [Float](); posF.reserveCapacity(outPos.count * 3)
        var pmin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var pmax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in outPos {
            posF.append(p.x); posF.append(p.y); posF.append(p.z)
            pmin = simd_min(pmin, p); pmax = simd_max(pmax, p)
        }
        let posBV = addBV(floatData(posF), target: 34962)  // ARRAY_BUFFER
        let posAcc = accessors.count
        accessors.append(["bufferView": posBV, "componentType": 5126, "count": outPos.count, "type": "VEC3",
                          "min": [Double(pmin.x), Double(pmin.y), Double(pmin.z)],
                          "max": [Double(pmax.x), Double(pmax.y), Double(pmax.z)]])

        // TEXCOORD_0 (VEC2 f32, allaqachon flip qilingan).
        var uvF = [Float](); uvF.reserveCapacity(outUV.count * 2)
        for t in outUV { uvF.append(t.x); uvF.append(t.y) }
        let uvBV = addBV(floatData(uvF), target: 34962)
        let uvAcc = accessors.count
        accessors.append(["bufferView": uvBV, "componentType": 5126, "count": outUV.count, "type": "VEC2"])

        // COLOR_0 (VEC3 f32) — faqat vertex-rang bo'lsa.
        var colAcc: Int? = nil
        if anyVertexColor {
            var colF = [Float](); colF.reserveCapacity(outCol.count * 3)
            for c in outCol { colF.append(c.x); colF.append(c.y); colF.append(c.z) }
            let colBV = addBV(floatData(colF), target: 34962)
            colAcc = accessors.count
            accessors.append(["bufferView": colBV, "componentType": 5126, "count": outCol.count, "type": "VEC3"])
        }

        // Noyob atlas PNG'lar (BIN chunk'ga embed).
        var imagePaths: [String] = []
        var imageIndexFor: [String: Int] = [:]
        for g in nonEmpty {
            if let url = mtl[g.mat], FileManager.default.fileExists(atPath: url.path), imageIndexFor[url.path] == nil {
                imageIndexFor[url.path] = imagePaths.count
                imagePaths.append(url.path)
            }
        }
        var images: [[String: Any]] = []
        var textures: [[String: Any]] = []
        for path in imagePaths {
            let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
            let bv = addBV(data, target: nil)
            images.append(["bufferView": bv, "mimeType": "image/png"])
            textures.append(["source": images.count - 1, "sampler": 0])
        }

        // Materiallar + primitivlar (har guruh uchun bittadan).
        var materials: [[String: Any]] = []
        var primitives: [[String: Any]] = []
        for (gi, g) in nonEmpty.enumerated() {
            var attrs: [String: Any] = ["POSITION": posAcc, "TEXCOORD_0": uvAcc]
            if let colAcc { attrs["COLOR_0"] = colAcc }
            var pbr: [String: Any] = ["metallicFactor": 0, "roughnessFactor": 1]
            if let url = mtl[g.mat], let ti = imageIndexFor[url.path] {
                pbr["baseColorTexture"] = ["index": ti]
            } else {
                pbr["baseColorFactor"] = [1, 1, 1, 1]   // vertex-rang COLOR_0'dan keladi
            }
            materials.append([
                "pbrMetallicRoughness": pbr,
                "extensions": ["KHR_materials_unlit": [String: Any]()],
                "doubleSided": false,   // dollhouse cull (Flutter ham single-sided qiladi)
            ])
            primitives.append(["attributes": attrs, "indices": idxAcc[gi],
                               "material": materials.count - 1, "mode": 4])
        }

        // ---- glTF JSON ----
        var gltf: [String: Any] = [
            "asset": ["version": "2.0", "generator": "kadastr-pcscankit"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]],
            "meshes": [["primitives": primitives]],
            "materials": materials,
            "extensionsUsed": ["KHR_materials_unlit"],
            "accessors": accessors,
            "bufferViews": bufferViews,
            "buffers": [["byteLength": bin.count]],
            "samplers": [["magFilter": 9729, "minFilter": 9729, "wrapS": 33071, "wrapT": 33071]],
        ]
        if !images.isEmpty { gltf["images"] = images; gltf["textures"] = textures }

        var jsonData = try JSONSerialization.data(withJSONObject: gltf, options: [.sortedKeys])
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }   // JSON chunk'ni bo'sh joy bilan to'ldirish

        // ---- GLB konteyner: header + JSON chunk + BIN chunk ----
        var glb = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { glb.append(contentsOf: $0) } }
        let total = 12 + 8 + jsonData.count + 8 + bin.count
        u32(0x46546C67); u32(2); u32(UInt32(total))                    // "glTF", versiya 2, umumiy uzunlik
        u32(UInt32(jsonData.count)); u32(0x4E4F534A); glb.append(jsonData)   // "JSON" chunk
        u32(UInt32(bin.count)); u32(0x004E4942); glb.append(bin)            // "BIN\0" chunk
        try glb.write(to: glbURL)
    }

    /// MTL: material nomi → atlas PNG URL (`map_Kd`). `map_Kd`'siz material = vertex-rangli.
    private static func parseMTL(objText: String, dir: URL) -> [String: URL] {
        var mtlName: String?
        for line in objText.split(separator: "\n") where line.hasPrefix("mtllib ") {
            mtlName = line.dropFirst(7).trimmingCharacters(in: .whitespaces); break
        }
        guard let name = mtlName,
              let mtl = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { return [:] }
        var result: [String: URL] = [:]
        var current: String?
        for raw in mtl.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("newmtl ") {
                current = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("map_Kd "), let cur = current {
                let png = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                result[cur] = dir.appendingPathComponent(png)
            }
        }
        return result
    }
}
