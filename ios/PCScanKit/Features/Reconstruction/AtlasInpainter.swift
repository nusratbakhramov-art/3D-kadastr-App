import Foundation
import CoreGraphics
import ImageIO
import simd

/// Ko'rilmagan atlas hududlarini atrofdagi yuza rangi bilan bo'yash (inpainting).
///
/// texrecon ko'rilmagan yuzalarni 0.55 kulrang (140,140,140) bilan to'ldiradi —
/// devorda kulrang dog' bo'lib qoladi. Atlas RASMIDAGI qo'shnilardan bo'yash
/// NOTO'G'RI: patch'lar atlasga ixtiyoriy joylashadi, rasm-qo'shni ≠ fazoviy
/// qo'shni. Shuning uchun MESH orqali ishlaymiz:
///   1. room.obj + room.mtl parse (pozitsiyalar, yuzalar, UV, materiallar).
///   2. Kulrang yuzalarni aniqlash (bir tekis 140±tol — texrecon fill'i aynan).
///   3. Qirra-qo'shnilik bo'yicha kulrang HUDUDLAR (union-find).
///   4. Har hudud chegarasidagi TEKSTURALI yuzalardan (3D pozitsiya + rang)
///      namunalar yig'iladi.
///   5. Hudud yuzalari per-VERTEX IDW (1/d²) gradient bilan bo'yaladi —
///      obyekt tomonidan obyekt rangi, devor tomonidan devor rangi silliq
///      "cho'ziladi" (tekis yakka rang emas). +2px kengayish — seam himoyasi.
/// UV-Y konvensiyasi (flip) EMPIRIK aniqlanadi: qaysi variant ko'proq
/// "bir tekis kulrang" yuza topsa — o'sha to'g'ri (EV ishorasi trikidek).
enum AtlasInpainter {

    /// texrecon unseen fill: 0.55 * 255 = 140.25 → 140.
    private static let grayValue = 140
    private static let grayTol = 3

    // MARK: - Kirish nuqtasi

    static func run(objURL: URL, log: (String) -> Void) {
        guard let model = parseOBJ(objURL: objURL) else {
            log("INPAINT skip: obj/mtl o'qilmadi"); return
        }
        var atlases: [Atlas] = []
        for texURL in model.textureURLs {
            guard let a = Atlas(url: texURL) else { log("INPAINT skip: atlas o'qilmadi \(texURL.lastPathComponent)"); return }
            atlases.append(a)
        }
        guard !atlases.isEmpty else { log("INPAINT skip: atlas yo'q"); return }

        // UV flip'ni empirik aniqlaymiz: to'g'ri konvensiyada kulrang yuzalar ko'p topiladi.
        let grayFlipTrue = detectGray(model: model, atlases: atlases, flipY: true)
        let grayFlipFalse = detectGray(model: model, atlases: atlases, flipY: false)
        let flipY = grayFlipTrue.count >= grayFlipFalse.count
        let grayFaces = flipY ? grayFlipTrue : grayFlipFalse
        guard !grayFaces.isEmpty else { log("INPAINT: kulrang yuza topilmadi"); return }

        // Kulrang hududlar (union-find, umumiy qirra bo'yicha).
        var parent = [Int](repeating: -1, count: model.faces.count)
        for f in grayFaces { parent[f] = f }
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != r { let n = parent[c]; parent[c] = r; c = n }
            return r
        }
        var edgeMap = [Int64: Int]()   // qirra -> birinchi kulrang yuza
        var neighborsOf = [Int: [Int]]()   // kulrang yuza -> teksturali qo'shnilar
        @inline(__always) func ekey(_ a: Int, _ b: Int) -> Int64 {
            a < b ? (Int64(a) << 32 | Int64(b)) : (Int64(b) << 32 | Int64(a))
        }
        let isGray = Set(grayFaces)
        for (fi, face) in model.faces.enumerated() {
            let edges = [ekey(face.v.0, face.v.1), ekey(face.v.1, face.v.2), ekey(face.v.2, face.v.0)]
            for e in edges {
                if let other = edgeMap[e] {
                    let og = isGray.contains(other), fg = isGray.contains(fi)
                    if og && fg {
                        let ro = find(other), rf = find(fi)
                        if ro != rf { parent[ro] = rf }
                    } else if og != fg {
                        let gray = og ? other : fi
                        let tex = og ? fi : other
                        neighborsOf[gray, default: []].append(tex)
                    }
                } else {
                    edgeMap[e] = fi
                }
            }
        }

        // Har hudud chegarasidagi teksturali yuzalardan namunalar:
        // 3D pozitsiya (gradient uchun) + median rang.
        let hasPositions = !model.positions.isEmpty
        var regionSamples = [Int: [(pos: SIMD3<Float>, color: SIMD3<Float>)]]()
        for f in grayFaces {
            guard let texNbrs = neighborsOf[f] else { continue }
            let root = find(f)
            for tn in texNbrs {
                let face = model.faces[tn]
                let atlas = atlases[face.mat]
                var cols: [(UInt8, UInt8, UInt8)] = []
                for s in samplePoints(face: face, model: model) {
                    if let c = atlas.sample(uv: s, flipY: flipY), !isGrayColor(c) {
                        cols.append(c)
                    }
                }
                guard !cols.isEmpty else { continue }
                let m = medianColor(cols)
                var pos = SIMD3<Float>(repeating: 0)
                if hasPositions,
                   face.v.0 < model.positions.count, face.v.1 < model.positions.count,
                   face.v.2 < model.positions.count {
                    pos = (model.positions[face.v.0] + model.positions[face.v.1]
                           + model.positions[face.v.2]) / 3
                }
                regionSamples[root, default: []].append(
                    (pos, SIMD3(Float(m.0), Float(m.1), Float(m.2)) / 255))
            }
        }
        // Zaxira tekis rang (kanal bo'yicha median) — yakka namunali hududlar uchun.
        var regionColor = [Int: SIMD3<Float>]()
        for (root, samples) in regionSamples where !samples.isEmpty {
            let r = samples.map { $0.color.x }.sorted()
            let g = samples.map { $0.color.y }.sorted()
            let b = samples.map { $0.color.z }.sorted()
            regionColor[root] = SIMD3(r[r.count / 2], g[g.count / 2], b[b.count / 2])
        }
        guard !regionColor.isEmpty else {
            log("INPAINT: hududlar uchun qo'shni rang topilmadi (\(grayFaces.count) kulrang yuza)"); return
        }

        // Qayta bo'yash — per-vertex IDW gradient ("cho'zilgan/blurry" effekt).
        var painted = 0
        var vCache = [Int64: SIMD3<Float>]()
        func vertexColor(root: Int, v: Int,
                         samples: [(pos: SIMD3<Float>, color: SIMD3<Float>)],
                         flat: SIMD3<Float>) -> SIMD3<Float> {
            guard hasPositions, samples.count > 1, v < model.positions.count else { return flat }
            let key = Int64(root) << 32 | Int64(v)
            if let c = vCache[key] { return c }
            let p = model.positions[v]
            var acc = SIMD3<Float>(repeating: 0); var wsum: Float = 0
            for s in samples {
                let w = 1 / (simd_distance_squared(p, s.pos) + 1e-3)
                acc += s.color * w; wsum += w
            }
            let c = wsum > 0 ? acc / wsum : flat
            vCache[key] = c
            return c
        }
        // Hudud kattaligi — katta yamoqlar kuchliroq blur oladi (2c).
        var regionFaceCount = [Int: Int]()
        for f in grayFaces { regionFaceCount[find(f), default: 0] += 1 }
        let largeRegionFaces = 60

        for f in grayFaces {
            let root = find(f)
            guard let flat = regionColor[root], let samples = regionSamples[root] else { continue }
            let face = model.faces[f]
            let colors = (vertexColor(root: root, v: face.v.0, samples: samples, flat: flat),
                          vertexColor(root: root, v: face.v.1, samples: samples, flat: flat),
                          vertexColor(root: root, v: face.v.2, samples: samples, flat: flat))
            atlases[face.mat].rasterize(face: face, model: model, flipY: flipY, colors: colors,
                                        large: (regionFaceCount[root] ?? 0) > largeRegionFaces)
            painted += 1
        }
        // "Fokusdan chiqqan" yumshoqlik: bo'yalgan piksellar blur qilinadi —
        // o'qishda atrofdagi o'tkir tekstura ham qatnashadi (chegara silliq
        // quyiladi), yozish faqat maska ichida. Katta yamoqlar qo'shimcha
        // kuchliroq eriydi.
        for a in atlases where a.dirty { a.blurPainted(radius: 2, passes: 2, onlyLarge: false) }
        for a in atlases where a.dirty { a.blurPainted(radius: 4, passes: 1, onlyLarge: true) }
        // Kengayish: bo'yalganlar atrofidagi qolgan SOF kulrang piksellarga 2px
        // (UV chegara seam'lari uchun padding).
        for a in atlases where a.dirty { a.dilateIntoGray(passes: 2) }

        var saved = 0
        for a in atlases where a.dirty { if a.save() { saved += 1 } }
        log("INPAINT gray=\(grayFaces.count) painted=\(painted) regions=\(regionColor.count) flipY=\(flipY) atlas=\(saved)")
    }

    // MARK: - Kulrang aniqlash

    private static func isGrayColor(_ c: (UInt8, UInt8, UInt8)) -> Bool {
        abs(Int(c.0) - grayValue) <= grayTol &&
        abs(Int(c.1) - grayValue) <= grayTol &&
        abs(Int(c.2) - grayValue) <= grayTol
    }

    /// Yuzaning UV namuna nuqtalari: markaz + 3 qirra o'rtasi.
    private static func samplePoints(face: Face, model: Model) -> [SIMD2<Float>] {
        let a = model.uvs[face.t.0], b = model.uvs[face.t.1], c = model.uvs[face.t.2]
        return [(a + b + c) / 3, (a + b) / 2, (b + c) / 2, (c + a) / 2]
    }

    private static func detectGray(model: Model, atlases: [Atlas], flipY: Bool) -> [Int] {
        var gray: [Int] = []
        for (fi, face) in model.faces.enumerated() {
            let atlas = atlases[face.mat]
            var all = true
            for s in samplePoints(face: face, model: model) {
                guard let c = atlas.sample(uv: s, flipY: flipY), isGrayColor(c) else { all = false; break }
            }
            if all { gray.append(fi) }
        }
        return gray
    }

    private static func medianColor(_ samples: [(UInt8, UInt8, UInt8)]) -> (UInt8, UInt8, UInt8) {
        let r = samples.map { $0.0 }.sorted()
        let g = samples.map { $0.1 }.sorted()
        let b = samples.map { $0.2 }.sorted()
        return (r[r.count / 2], g[g.count / 2], b[b.count / 2])
    }

    // MARK: - Model (OBJ + MTL)

    struct Face {
        var v: (Int, Int, Int)   // pozitsiya indekslari (qo'shnilik uchun)
        var t: (Int, Int, Int)   // UV indekslari
        var mat: Int             // atlas indeksi
    }
    struct Model {
        var positions: [SIMD3<Float>] = []   // gradient (IDW) uchun 3D joylar
        var uvs: [SIMD2<Float>] = []
        var faces: [Face] = []
        var textureURLs: [URL] = []
    }

    private static func parseOBJ(objURL: URL) -> Model? {
        guard let text = try? String(contentsOf: objURL, encoding: .utf8) else { return nil }
        var model = Model()

        // MTL: material nomi -> tekstura fayli.
        var mtlTextures = [String: String]()
        if let mtlLine = text.split(separator: "\n").first(where: { $0.hasPrefix("mtllib ") }) {
            let mtlName = mtlLine.dropFirst(7).trimmingCharacters(in: .whitespaces)
            let mtlURL = objURL.deletingLastPathComponent().appendingPathComponent(mtlName)
            if let mtlText = try? String(contentsOf: mtlURL, encoding: .utf8) {
                var current = ""
                for line in mtlText.split(separator: "\n") {
                    if line.hasPrefix("newmtl ") { current = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
                    else if line.hasPrefix("map_Kd "), !current.isEmpty {
                        mtlTextures[current] = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        var matIndex = [String: Int]()   // tekstura fayli -> atlas indeksi
        var currentMat = -1
        for line in text.split(separator: "\n") {
            if line.hasPrefix("vt ") {
                let p = line.split(separator: " ")
                guard p.count >= 3, let u = Float(p[1]), let v = Float(p[2]) else { continue }
                model.uvs.append(SIMD2(u, v))
            } else if line.hasPrefix("v ") {
                let p = line.split(separator: " ")
                guard p.count >= 4, let x = Float(p[1]), let y = Float(p[2]), let z = Float(p[3]) else { continue }
                model.positions.append(SIMD3(x, y, z))
            } else if line.hasPrefix("usemtl ") {
                let name = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                guard let tex = mtlTextures[name] else { currentMat = -1; continue }
                if let idx = matIndex[tex] { currentMat = idx }
                else {
                    let url = objURL.deletingLastPathComponent().appendingPathComponent(tex)
                    matIndex[tex] = model.textureURLs.count
                    currentMat = model.textureURLs.count
                    model.textureURLs.append(url)
                }
            } else if line.hasPrefix("f "), currentMat >= 0 {
                let p = line.split(separator: " ")
                guard p.count >= 4 else { continue }
                var vs: [Int] = []; var ts: [Int] = []
                for k in 1...3 {
                    let comps = p[k].split(separator: "/", omittingEmptySubsequences: false)
                    guard let vi = Int(comps[0]), comps.count >= 2, let ti = Int(comps[1]) else { break }
                    vs.append(vi - 1); ts.append(ti - 1)   // OBJ 1-indeks
                }
                guard vs.count == 3 else { continue }
                model.faces.append(Face(v: (vs[0], vs[1], vs[2]), t: (ts[0], ts[1], ts[2]), mat: currentMat))
            }
        }
        guard !model.faces.isEmpty, !model.textureURLs.isEmpty else { return nil }
        return model
    }

    // MARK: - Atlas (RGBA8 bitmap)

    final class Atlas {
        let url: URL
        let w: Int, h: Int
        var px: [UInt8]           // RGBA
        var dirty = false
        private var paintedMask: [Bool]
        private var largeMask: [Bool]   // katta hudud piksellari — kuchliroq blur

        init?(url: URL) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            w = img.width; h = img.height
            px = [UInt8](repeating: 0, count: w * h * 4)
            paintedMask = [Bool](repeating: false, count: w * h)
            largeMask = [Bool](repeating: false, count: w * h)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            self.url = url
        }

        func pixelXY(uv: SIMD2<Float>, flipY: Bool) -> (Int, Int) {
            let x = min(max(Int(uv.x * Float(w - 1) + 0.5), 0), w - 1)
            let yRaw = flipY ? (1 - uv.y) : uv.y
            let y = min(max(Int(yRaw * Float(h - 1) + 0.5), 0), h - 1)
            return (x, y)
        }

        func sample(uv: SIMD2<Float>, flipY: Bool) -> (UInt8, UInt8, UInt8)? {
            let (x, y) = pixelXY(uv: uv, flipY: flipY)
            let i = (y * w + x) * 4
            return (px[i], px[i + 1], px[i + 2])
        }

        /// UV uchburchakni 3 cho'qqi rangi bilan gradient bo'yaydi (barycentric
        /// interpolyatsiya) — hudud bo'ylab rang silliq "cho'ziladi".
        func rasterize(face: Face, model: Model, flipY: Bool,
                       colors: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>),
                       large: Bool = false) {
            let pa = pixelXY(uv: model.uvs[face.t.0], flipY: flipY)
            let pb = pixelXY(uv: model.uvs[face.t.1], flipY: flipY)
            let pc = pixelXY(uv: model.uvs[face.t.2], flipY: flipY)
            let minX = max(min(pa.0, pb.0, pc.0) - 1, 0), maxX = min(max(pa.0, pb.0, pc.0) + 1, w - 1)
            let minY = max(min(pa.1, pb.1, pc.1) - 1, 0), maxY = min(max(pa.1, pb.1, pc.1) + 1, h - 1)
            let ax = Float(pa.0), ay = Float(pa.1)
            let bx = Float(pb.0), by = Float(pb.1)
            let cx = Float(pc.0), cy = Float(pc.1)
            let avg = (colors.0 + colors.1 + colors.2) / 3
            let area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
            guard abs(area) > 1e-6 else {
                // Degenerativ (juda kichik) — bbox'ni o'rtacha rang bilan bo'yaymiz.
                for y in minY...maxY { for x in minX...maxX { put(x, y, avg, large) } }
                return
            }
            // -0.15 barycentric margin: chekka piksellar qamrab olinadi. Ortiqcha
            // bo'yash faqat o'sha unseen patch ichida qoladi (texrecon ko'rilmagan
            // yuzalarni alohida patchga joylaydi) — xavfsiz.
            for y in minY...maxY {
                for x in minX...maxX {
                    let pxf = Float(x), pyf = Float(y)
                    let w0 = ((bx - pxf) * (cy - pyf) - (by - pyf) * (cx - pxf)) / area
                    let w1 = ((cx - pxf) * (ay - pyf) - (cy - pyf) * (ax - pxf)) / area
                    let w2 = 1 - w0 - w1
                    if w0 >= -0.15 && w1 >= -0.15 && w2 >= -0.15 {
                        let c0 = max(w0, 0), c1 = max(w1, 0), c2 = max(w2, 0)
                        let s = c0 + c1 + c2
                        let col = s > 1e-6 ? (colors.0 * c0 + colors.1 * c1 + colors.2 * c2) / s : avg
                        put(x, y, col, large)
                    }
                }
            }
        }

        private func put(_ x: Int, _ y: Int, _ c: SIMD3<Float>, _ large: Bool) {
            let i = (y * w + x) * 4
            px[i]     = UInt8(max(0, min(255, Int(c.x * 255))))
            px[i + 1] = UInt8(max(0, min(255, Int(c.y * 255))))
            px[i + 2] = UInt8(max(0, min(255, Int(c.z * 255))))
            px[i + 3] = 255
            paintedMask[y * w + x] = true
            if large { largeMask[y * w + x] = true }
            dirty = true
        }

        /// Bo'yalgan piksellarni yumshatish (box blur ≈ Gauss). O'qish butun
        /// atlasdan (chegara ranglari qatnashadi — silliq quyilish), yozish
        /// faqat maska ichida — haqiqiy tekstura o'tkirligicha qoladi.
        /// onlyLarge=true — faqat katta hududlar (qo'shimcha kuchli erish).
        func blurPainted(radius: Int, passes: Int, onlyLarge: Bool) {
            var idxs: [Int32] = []
            for i in 0..<paintedMask.count where paintedMask[i] && (!onlyLarge || largeMask[i]) {
                idxs.append(Int32(i))
            }
            guard !idxs.isEmpty else { return }
            var out = [UInt8](repeating: 0, count: idxs.count * 3)
            for _ in 0..<passes {
                for (n, ii) in idxs.enumerated() {
                    let i = Int(ii)
                    let x0 = i % w, y0 = i / w
                    var sr = 0, sg = 0, sb = 0, cnt = 0
                    var dy = -radius
                    while dy <= radius {
                        let y = y0 + dy
                        dy += 1
                        if y < 0 || y >= h { continue }
                        var dx = -radius
                        while dx <= radius {
                            let x = x0 + dx
                            dx += 1
                            if x < 0 || x >= w { continue }
                            let o = (y * w + x) * 4
                            sr += Int(px[o]); sg += Int(px[o + 1]); sb += Int(px[o + 2])
                            cnt += 1
                        }
                    }
                    out[n * 3] = UInt8(sr / cnt)
                    out[n * 3 + 1] = UInt8(sg / cnt)
                    out[n * 3 + 2] = UInt8(sb / cnt)
                }
                for (n, ii) in idxs.enumerated() {
                    let o = Int(ii) * 4
                    px[o] = out[n * 3]; px[o + 1] = out[n * 3 + 1]; px[o + 2] = out[n * 3 + 2]
                }
            }
        }

        /// Bo'yalgan piksellardan qo'shni SOF KULRANG piksellarga kengayish (padding).
        func dilateIntoGray(passes: Int) {
            for _ in 0..<passes {
                var additions: [(Int, (UInt8, UInt8, UInt8))] = []
                for y in 0..<h {
                    for x in 0..<w {
                        let i = y * w + x
                        if paintedMask[i] { continue }
                        let pi = i * 4
                        let isGray = abs(Int(px[pi]) - 140) <= 3 && abs(Int(px[pi+1]) - 140) <= 3 && abs(Int(px[pi+2]) - 140) <= 3
                        guard isGray else { continue }
                        // Bo'yalgan qo'shni bormi?
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < w, ny < h, paintedMask[ny * w + nx] else { continue }
                            let ni = (ny * w + nx) * 4
                            additions.append((i, (px[ni], px[ni + 1], px[ni + 2])))
                            break
                        }
                    }
                }
                for (i, c) in additions {
                    let pi = i * 4
                    px[pi] = c.0; px[pi + 1] = c.1; px[pi + 2] = c.2
                    paintedMask[i] = true
                }
                if additions.isEmpty { break }
            }
        }

        func save() -> Bool {
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let img = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
            CGImageDestinationAddImage(dest, img, nil)
            return CGImageDestinationFinalize(dest)
        }
    }
}
