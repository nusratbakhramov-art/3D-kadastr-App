import Foundation

/// texrecon OBJ + MTL + atlas PNG'larni RealityKit/Quick Look'da YORUG' ochiladigan
/// usdz faylga aylantiradi. Retsept (Mac'da tasdiqlangan): bitta Mesh + faceVarying st +
/// GeomSubset (har material) + `doubleSided = 1` + UsdPreviewSurface diffuseColor=atlas.
/// (emissive ISHLATILMAYDI — RealityKit'da ortiqcha yorug'/qorong'i qiladi.)
/// usdz = zip (STORED, har fayl 64-baytga tekislangan — RealityKit teksturani mmap qiladi).
enum USDZExporter {

    enum ExportError: Error { case objRead, noFaces }

    /// Ixcham float formatlash (~0.1mm aniqlik) — usda hajmini kamaytiradi.
    private static func fmt(_ v: Float) -> String {
        if v == v.rounded() && abs(v) < 1e6 { return String(Int(v)) }
        return String(format: "%.5g", v)
    }

    static func export(objURL: URL, outURL: URL) throws {
        let dir = objURL.deletingLastPathComponent()
        guard let objText = try? String(contentsOf: objURL, encoding: .utf8) else { throw ExportError.objRead }

        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var faceV: [(Int, Int, Int)] = []      // 0-asosli pozitsiya indekslari
        var faceVT: [(Int, Int, Int)] = []     // 0-asosli uv indekslari
        var faceMat: [Int] = []                // har yuz uchun material indeksi
        var matNames: [String] = []            // material tartibi (m0, m1, ...)
        var matIndex: [String: Int] = [:]
        var curMat = 0

        func matIdx(_ name: String) -> Int {
            if let i = matIndex[name] { return i }
            let i = matNames.count; matNames.append(name); matIndex[name] = i; return i
        }

        objText.enumerateLines { line, _ in
            if line.hasPrefix("v ") {
                let c = line.dropFirst(2).split(separator: " ")
                if c.count >= 3 { positions.append(SIMD3(Float(c[0]) ?? 0, Float(c[1]) ?? 0, Float(c[2]) ?? 0)) }
            } else if line.hasPrefix("vt ") {
                let c = line.dropFirst(3).split(separator: " ")
                if c.count >= 2 { uvs.append(SIMD2(Float(c[0]) ?? 0, Float(c[1]) ?? 0)) }
            } else if line.hasPrefix("usemtl ") {
                curMat = matIdx(String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("f ") {
                let toks = line.dropFirst(2).split(separator: " ")
                guard toks.count >= 3 else { return }
                func pv(_ t: Substring) -> (Int, Int) {
                    let p = t.split(separator: "/", omittingEmptySubsequences: false)
                    let vi = (Int(p[0]) ?? 1) - 1
                    let ti = p.count > 1 ? (Int(p[1]) ?? 1) - 1 : 0
                    return (vi, ti)
                }
                let a = pv(toks[0]), b = pv(toks[1]), c = pv(toks[2])
                faceV.append((a.0, b.0, c.0)); faceVT.append((a.1, b.1, c.1)); faceMat.append(curMat)
            }
        }
        guard !faceV.isEmpty else { throw ExportError.noFaces }

        // MTL: material nomi -> atlas png
        var matTex: [String: String] = [:]
        let mtlURL = dir.appendingPathComponent(objURL.deletingPathExtension().lastPathComponent + ".mtl")
        if let mtl = try? String(contentsOf: mtlURL, encoding: .utf8) {
            var cur = ""
            for raw in mtl.split(separator: "\n") {
                let p = raw.split(separator: " ", omittingEmptySubsequences: true)
                guard let k = p.first else { continue }
                if k == "newmtl", p.count > 1 { cur = String(p[1]) }
                else if k == "map_Kd", p.count > 1 { matTex[cur] = String(p[1]) }
            }
        }

        // --- usda matn qurish ---
        var s = "#usda 1.0\n(\n    defaultPrim = \"Room\"\n    upAxis = \"Y\"\n    metersPerUnit = 1\n)\n"
        s += "def Xform \"Room\"\n{\n"
        s += "    def Mesh \"geom\" (\n        prepend apiSchemas = [\"MaterialBindingAPI\"]\n    )\n    {\n"
        s += "        uniform token subdivisionScheme = \"none\"\n"
        s += "        uniform bool doubleSided = 1\n"

        // faceVertexCounts
        s += "        int[] faceVertexCounts = ["
        s += Array(repeating: "3", count: faceV.count).joined(separator: ", ")
        s += "]\n"

        // faceVertexIndices
        s += "        int[] faceVertexIndices = ["
        var fvi = [String](); fvi.reserveCapacity(faceV.count * 3)
        for f in faceV { fvi.append(String(f.0)); fvi.append(String(f.1)); fvi.append(String(f.2)) }
        s += fvi.joined(separator: ", "); s += "]\n"

        // points
        s += "        point3f[] points = ["
        var pts = [String](); pts.reserveCapacity(positions.count)
        for p in positions {
            pts.append("(\(fmt(p.x)), \(fmt(p.y)), \(fmt(p.z)))")
        }
        s += pts.joined(separator: ", "); s += "]\n"

        // primvars:st (faceVarying — har yuz-uchi uchun bitta uv, faceVertexIndices tartibida)
        s += "        texCoord2f[] primvars:st = ["
        var st = [String](); st.reserveCapacity(faceVT.count * 3)
        for f in faceVT {
            for ti in [f.0, f.1, f.2] {
                let uv = (ti >= 0 && ti < uvs.count) ? uvs[ti] : SIMD2<Float>(0, 0)
                st.append("(\(fmt(uv.x)), \(fmt(uv.y)))")
            }
        }
        s += st.joined(separator: ", "); s += "] (\n            interpolation = \"faceVarying\"\n        )\n"

        // default binding = birinchi material
        s += "        rel material:binding = </Room/m0>\n"

        // GeomSubset har material uchun (o'sha materialga tegishli yuz indekslari)
        for (mi, _) in matNames.enumerated() {
            var faces = [String]()
            for (fi, m) in faceMat.enumerated() where m == mi { faces.append(String(fi)) }
            if faces.isEmpty { continue }
            s += "        def GeomSubset \"m\(mi)\" (\n            prepend apiSchemas = [\"MaterialBindingAPI\"]\n        )\n        {\n"
            s += "            uniform token elementType = \"face\"\n"
            s += "            uniform token familyName = \"materialBind\"\n"
            s += "            int[] indices = [" + faces.joined(separator: ", ") + "]\n"
            s += "            rel material:binding = </Room/m\(mi)>\n        }\n"
        }
        s += "    }\n"

        // Materiallar (diffuse = atlas)
        var atlasFiles: [String] = []
        for (mi, name) in matNames.enumerated() {
            let tex = matTex[name] ?? ""
            if !tex.isEmpty { atlasFiles.append(tex) }
            s += "    def Material \"m\(mi)\"\n    {\n"
            s += "        token outputs:surface.connect = </Room/m\(mi)/pbr.outputs:surface>\n"
            s += "        def Shader \"pbr\"\n        {\n"
            s += "            uniform token info:id = \"UsdPreviewSurface\"\n"
            s += "            color3f inputs:diffuseColor.connect = </Room/m\(mi)/tex.outputs:rgb>\n"
            s += "            float inputs:roughness = 1\n            float inputs:metallic = 0\n"
            s += "            token outputs:surface\n        }\n"
            s += "        def Shader \"tex\"\n        {\n"
            s += "            uniform token info:id = \"UsdUVTexture\"\n"
            s += "            asset inputs:file = @\(tex)@\n"
            s += "            float2 inputs:st.connect = </Room/m\(mi)/stR.outputs:result>\n"
            s += "            token inputs:wrapS = \"clamp\"\n            token inputs:wrapT = \"clamp\"\n"
            s += "            float3 outputs:rgb\n        }\n"
            s += "        def Shader \"stR\"\n        {\n"
            s += "            uniform token info:id = \"UsdPrimvarReader_float2\"\n"
            s += "            token inputs:varname = \"st\"\n            float2 outputs:result\n        }\n"
            s += "    }\n"
        }
        s += "}\n"

        // --- usdz paketlash ---
        let usdaData = Data(s.utf8)
        var entries: [(name: String, data: Data)] = [("scene.usda", usdaData)]
        for f in atlasFiles {
            let u = dir.appendingPathComponent(f)
            if let d = try? Data(contentsOf: u) { entries.append((f, d)) }
        }
        let zip = buildUSDZ(entries)
        try zip.write(to: outURL)
    }

    // MARK: - usdz (zip, STORED, 64-bayt tekislangan)

    private static func buildUSDZ(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        struct CD { var name: String; var crc: UInt32; var size: Int; var offset: Int }
        var cds: [CD] = []

        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }

        for e in entries {
            let nameBytes = Array(e.name.utf8)
            let crc = crc32(e.data)
            let localHeaderOffset = out.count
            // data offset = localHeaderOffset + 30 + nameLen + extraLen ; 64 ga tekislash
            let base = localHeaderOffset + 30 + nameBytes.count
            var extraLen = (64 - (base % 64)) % 64
            if extraLen > 0 && extraLen < 4 { extraLen += 64 }   // extra field min 4 bayt (id+len)
            var localHeader = [UInt8]()
            localHeader += u32(0x04034b50)      // local file header sig
            localHeader += u16(20)              // version needed
            localHeader += u16(0)               // flags
            localHeader += u16(0)               // method = 0 (stored)
            localHeader += u16(0)               // mod time
            localHeader += u16(0x21)            // mod date (1980-01-01 ~)
            localHeader += u32(crc)
            localHeader += u32(UInt32(e.data.count))   // compressed size
            localHeader += u32(UInt32(e.data.count))   // uncompressed size
            localHeader += u16(nameBytes.count)
            localHeader += u16(extraLen)
            out.append(contentsOf: localHeader)
            out.append(contentsOf: nameBytes)
            if extraLen >= 4 {
                out.append(contentsOf: u16(0x1991))          // custom extra field id (readerlar o'tkazib yuboradi)
                out.append(contentsOf: u16(extraLen - 4))    // data size
                out.append(contentsOf: [UInt8](repeating: 0, count: extraLen - 4))
            }
            out.append(e.data)
            cds.append(CD(name: e.name, crc: crc, size: e.data.count, offset: localHeaderOffset))
        }

        let cdStart = out.count
        for c in cds {
            let nameBytes = Array(c.name.utf8)
            var h = [UInt8]()
            h += u32(0x02014b50)   // central dir sig
            h += u16(20)           // version made by
            h += u16(20)           // version needed
            h += u16(0)            // flags
            h += u16(0)            // method stored
            h += u16(0)            // time
            h += u16(0x21)         // date
            h += u32(c.crc)
            h += u32(UInt32(c.size))
            h += u32(UInt32(c.size))
            h += u16(nameBytes.count)
            h += u16(0)            // extra len
            h += u16(0)            // comment len
            h += u16(0)            // disk number
            h += u16(0)            // internal attrs
            h += u32(0)            // external attrs
            h += u32(UInt32(c.offset))
            out.append(contentsOf: h)
            out.append(contentsOf: nameBytes)
        }
        let cdSize = out.count - cdStart
        var eocd = [UInt8]()
        eocd += u32(0x06054b50)
        eocd += u16(0); eocd += u16(0)
        eocd += u16(cds.count); eocd += u16(cds.count)
        eocd += u32(UInt32(cdSize)); eocd += u32(UInt32(cdStart))
        eocd += u16(0)
        out.append(contentsOf: eocd)
        return out
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}
