import Foundation
import UIKit
import simd

/// Teshik-to'ldirish (fill) meshiga rang berib, teksturali OBJ'ga qo'shadi.
/// Yondashuv (Mac'да tasdiqlangan, muammosiz): har fill region uchun uning
/// CHEGARASIDAGI atlas ranglari o'rtachasini oladi (atrofdagi yuza rangi) va
/// kichik teksturага "bake" qiladi — shu tufayli fill yamalar atrofga silliq
/// aralashadi (per-vertex rang emas, sRGB tekstura yo'li → rang fazosi to'g'ri).
enum FillColorizer {

    /// fill meshни room.obj (atlas) ga qo'shadi. Muvaffaqiyatsiz bo'lsa jim qaytadi.
    static func appendFill(fill: LiDARMeshData, objURL: URL, log: ((String) -> Void)? = nil) {
        guard !fill.isEmpty else { return }
        let dir = objURL.deletingLastPathComponent()

        // 1. Atlas OBJ'дан pozitsiya -> rang (atlas PNG'ni UV bo'yicha namuna olib).
        guard let posColor = atlasVertexColors(objURL: objURL, dir: dir) else {
            log?("FILLCOLOR: atlas rang o'qib bo'lmadi"); return
        }

        // 2. Fill mesh'ni ochamiz.
        let vcount = fill.vertexCount
        var positions = [SIMD3<Float>](); positions.reserveCapacity(vcount)
        for i in 0..<vcount {
            positions.append(SIMD3(fill.positions[i*3], fill.positions[i*3+1], fill.positions[i*3+2]))
        }
        var tris = [(Int, Int, Int)](); tris.reserveCapacity(fill.indices.count / 3)
        var k = 0
        while k + 2 < fill.indices.count {
            tris.append((Int(fill.indices[k]), Int(fill.indices[k+1]), Int(fill.indices[k+2]))); k += 3
        }

        // 3. Fill vert -> atlas rang (pozitsiya bo'yicha; chegara cho'qqilari mos keladi).
        var vColor = [Int: SIMD3<Float>]()
        for i in 0..<vcount {
            if let c = posColor[posKey(positions[i])] { vColor[i] = c }
        }

        // 4. Fill regionlar (bog'langan komponentlar) + per-VERTEX gradient rang.
        //    Avval har region YAKKA tekis rang olardi — yamoq "qog'oz" bo'lib,
        //    qora obyekt ustida oq devor rangi dog' bo'lib qolardi. Endi chegara
        //    (atlasdan rang olgan) cho'qqilardan IDW (1/d²) bilan ichki
        //    cho'qqilarga rang "cho'ziladi" — yamoq atrofga silliq quyiladi.
        var adj = [[Int]](repeating: [], count: vcount)
        for (a, b, c) in tris {
            adj[a].append(b); adj[b].append(a)
            adj[b].append(c); adj[c].append(b)
            adj[c].append(a); adj[a].append(c)
        }
        var comp = [Int](repeating: -1, count: vcount)
        var regionMembers = [[Int]]()
        var stack = [Int]()
        for s in 0..<vcount where comp[s] < 0 {
            let rid = regionMembers.count
            var members = [Int]()
            comp[s] = rid; stack.append(s)
            while let u = stack.popLast() {
                members.append(u)
                for w in adj[u] where comp[w] < 0 { comp[w] = rid; stack.append(w) }
            }
            regionMembers.append(members)
        }
        guard !regionMembers.isEmpty else { return }

        // Har region chegara namunalari (pozitsiya + rang) va zaxira tekis rang.
        var regionSamples = [[(SIMD3<Float>, SIMD3<Float>)]](repeating: [], count: regionMembers.count)
        var regionFlat = [SIMD3<Float>](repeating: SIMD3(0.55, 0.5, 0.45), count: regionMembers.count)
        for (rid, members) in regionMembers.enumerated() {
            var sum = SIMD3<Float>(repeating: 0); var n = 0
            for m in members {
                if let c = vColor[m] {
                    regionSamples[rid].append((positions[m], c))
                    sum += c; n += 1
                }
            }
            if n > 0 { regionFlat[rid] = sum / Float(n) }
        }

        // Per-vertex rang: chegara cho'qqisi o'z rangini saqlaydi, ichkilar IDW.
        var pvColor = [SIMD3<Float>](repeating: .zero, count: vcount)
        for v in 0..<vcount {
            if let c = vColor[v] { pvColor[v] = c; continue }
            let rid = comp[v]
            let samples = regionSamples[rid]
            guard !samples.isEmpty else { pvColor[v] = regionFlat[rid]; continue }
            var acc = SIMD3<Float>(repeating: 0); var wsum: Float = 0
            for (sp, sc) in samples {
                let w = 1 / (simd_distance_squared(positions[v], sp) + 1e-3)
                acc += sc * w; wsum += w
            }
            pvColor[v] = acc / wsum
        }

        // 5. Per-uchburchak blok tekstura: har uchburchak o'z katagida
        //    barycentric interpolyatsiya bilan bo'yaladi — umumiy cho'qqilar
        //    bir xil rang olgani uchun yamoq ichi uzluksiz gradient bo'ladi.
        let triCount = tris.count
        guard triCount > 0 else { return }
        let grid = Int(ceil(Double(triCount).squareRoot()))
        var cell = 12
        if grid * cell > 4096 { cell = max(6, 4096 / grid) }
        let texW = max(grid * cell, cell)
        guard let texData = bakeGradientTexture(tris: tris, pvColor: pvColor,
                                                grid: grid, cell: cell, texW: texW) else { return }
        let fillPNG = dir.appendingPathComponent("fillbake.png")
        guard (try? texData.write(to: fillPNG)) != nil else { return }

        // 6. OBJ'ga qo'shamiz — har uchburchakka 3 ta vt (o'z blok burchaklari).
        guard let obj = try? String(contentsOf: objURL, encoding: .utf8) else { return }
        var vBase = 0, vtBase = 0
        obj.enumerateLines { line, _ in
            if line.hasPrefix("v ") { vBase += 1 } else if line.hasPrefix("vt ") { vtBase += 1 }
        }
        var out = "\nusemtl fillmat\n"
        for p in positions { out += "v \(p.x) \(p.y) \(p.z)\n" }
        let inset: Float = 1.5
        for t in 0..<triCount {
            let cx = t % grid, cy = t / grid
            let x0 = Float(cx * cell), y0 = Float(cy * cell)
            let pts = [SIMD2<Float>(x0 + inset, y0 + inset),
                       SIMD2<Float>(x0 + Float(cell) - inset, y0 + inset),
                       SIMD2<Float>(x0 + Float(cell) / 2, y0 + Float(cell) - inset)]
            for p in pts {
                out += "vt \(p.x / Float(texW)) \(1 - p.y / Float(texW))\n"
            }
        }
        for (t, tri) in tris.enumerated() {
            let vt0 = vtBase + t * 3 + 1
            out += "f \(tri.0+1+vBase)/\(vt0) \(tri.1+1+vBase)/\(vt0+1) \(tri.2+1+vBase)/\(vt0+2)\n"
        }
        guard let handle = try? FileHandle(forWritingTo: objURL) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(out.utf8))
        try? handle.close()

        // 7. MTL'ga fillmat qo'shamiz.
        let mtlURL = dir.appendingPathComponent("room.mtl")
        if let mh = try? FileHandle(forWritingTo: mtlURL) {
            mh.seekToEndOfFile()
            mh.write(Data("\nnewmtl fillmat\nKa 1 1 1\nKd 1 1 1\nmap_Kd fillbake.png\n".utf8))
            try? mh.close()
        }
        log?("FILLCOLOR regions=\(regionMembers.count) tris=\(tris.count) gradient")
    }

    // MARK: - Yordamchilar

    /// Har blok ICHIDA box-blur (chegara klamp) — bloklararo rang oqmaydi.
    private static func blurBlocks(_ bytes: inout [UInt8], triCount: Int,
                                   grid: Int, cell: Int, texW: Int) {
        guard cell >= 4 else { return }
        var tmp = [UInt8](repeating: 0, count: cell * cell * 3)
        for t in 0..<triCount {
            let bx = (t % grid) * cell, by = (t / grid) * cell
            let x1 = min(bx + cell, texW), y1 = min(by + cell, texW)
            for _ in 0..<2 {
                for y in by..<y1 {
                    for x in bx..<x1 {
                        var sr = 0, sg = 0, sb = 0, cnt = 0
                        for dy in -1...1 {
                            let yy = y + dy
                            if yy < by || yy >= y1 { continue }
                            for dx in -1...1 {
                                let xx = x + dx
                                if xx < bx || xx >= x1 { continue }
                                let o = (yy * texW + xx) * 4
                                sr += Int(bytes[o]); sg += Int(bytes[o + 1]); sb += Int(bytes[o + 2])
                                cnt += 1
                            }
                        }
                        let ti = ((y - by) * cell + (x - bx)) * 3
                        tmp[ti] = UInt8(sr / cnt); tmp[ti + 1] = UInt8(sg / cnt); tmp[ti + 2] = UInt8(sb / cnt)
                    }
                }
                for y in by..<y1 {
                    for x in bx..<x1 {
                        let ti = ((y - by) * cell + (x - bx)) * 3
                        let o = (y * texW + x) * 4
                        bytes[o] = tmp[ti]; bytes[o + 1] = tmp[ti + 1]; bytes[o + 2] = tmp[ti + 2]
                    }
                }
            }
        }
    }

    private static func posKey(_ p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3(Int32((p.x * 1000).rounded()), Int32((p.y * 1000).rounded()), Int32((p.z * 1000).rounded()))
    }

    /// Atlas OBJ + PNG'lardan pozitsiya -> rang (0..1).
    private static func atlasVertexColors(objURL: URL, dir: URL) -> [SIMD3<Int32>: SIMD3<Float>]? {
        guard let obj = try? String(contentsOf: objURL, encoding: .utf8) else { return nil }
        // MTL: material -> piksel buferi.
        var mtlName = "room.mtl"
        for line in obj.split(separator: "\n") where line.hasPrefix("mtllib ") {
            mtlName = line.dropFirst(7).trimmingCharacters(in: .whitespaces); break
        }
        guard let mtl = try? String(contentsOf: dir.appendingPathComponent(mtlName), encoding: .utf8) else { return nil }
        var images = [String: PixelBuffer]()
        var cur: String?
        for raw in mtl.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("newmtl ") { cur = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("map_Kd "), let name = cur {
                let png = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                if let buf = PixelBuffer(url: dir.appendingPathComponent(png)) { images[name] = buf }
            }
        }
        guard !images.isEmpty else { return nil }

        var positions = [SIMD3<Float>]()
        var texcoords = [SIMD2<Float>]()
        var result = [SIMD3<Int32>: SIMD3<Float>](minimumCapacity: 100_000)
        var curMat: String?
        obj.enumerateLines { line, _ in
            if line.hasPrefix("v ") {
                let p = line.dropFirst(2).split(separator: " ").compactMap { Float($0) }
                if p.count >= 3 { positions.append(SIMD3(p[0], p[1], p[2])) }
            } else if line.hasPrefix("vt ") {
                let p = line.dropFirst(3).split(separator: " ").compactMap { Float($0) }
                if p.count >= 2 { texcoords.append(SIMD2(p[0], p[1])) }
            } else if line.hasPrefix("usemtl ") {
                curMat = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("f "), let mat = curMat, let img = images[mat] {
                for tok in line.dropFirst(2).split(separator: " ") {
                    let parts = tok.split(separator: "/", omittingEmptySubsequences: false)
                    guard let vi = Int(parts[0]), vi >= 1, vi <= positions.count,
                          parts.count > 1, !parts[1].isEmpty, let ti = Int(parts[1]),
                          ti >= 1, ti <= texcoords.count else { continue }
                    let key = posKey(positions[vi - 1])
                    if result[key] != nil { continue }
                    let uv = texcoords[ti - 1]
                    result[key] = img.sample(u: uv.x, v: uv.y)
                }
            }
        }
        return result
    }

    /// Har uchburchak o'z blok katagida 3 cho'qqi rangi bilan barycentric
    /// interpolyatsiya qilinadi (gradient) — blok chetlari ham to'ldiriladi
    /// (klamp + normallash), UV inset tufayli qo'shni blokka oqmaydi.
    private static func bakeGradientTexture(tris: [(Int, Int, Int)], pvColor: [SIMD3<Float>],
                                            grid: Int, cell: Int, texW: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: texW * texW * 4)
        let inset: Float = 1.5
        for (t, tri) in tris.enumerated() {
            let cx = t % grid, cy = t / grid
            let x0 = cx * cell, y0 = cy * cell
            let p0 = SIMD2<Float>(Float(x0) + inset, Float(y0) + inset)
            let p1 = SIMD2<Float>(Float(x0 + cell) - inset, Float(y0) + inset)
            let p2 = SIMD2<Float>(Float(x0) + Float(cell) / 2, Float(y0 + cell) - inset)
            let ca = pvColor[tri.0], cb = pvColor[tri.1], cc = pvColor[tri.2]
            let area = (p1.x - p0.x) * (p2.y - p0.y) - (p1.y - p0.y) * (p2.x - p0.x)
            guard abs(area) > 1e-6 else { continue }
            for py in y0..<min(y0 + cell, texW) {
                for px in x0..<min(x0 + cell, texW) {
                    let q = SIMD2<Float>(Float(px) + 0.5, Float(py) + 0.5)
                    var w0 = ((p1.x - q.x) * (p2.y - q.y) - (p1.y - q.y) * (p2.x - q.x)) / area
                    var w1 = ((p2.x - q.x) * (p0.y - q.y) - (p2.y - q.y) * (p0.x - q.x)) / area
                    var w2 = 1 - w0 - w1
                    w0 = max(w0, 0); w1 = max(w1, 0); w2 = max(w2, 0)
                    let s = w0 + w1 + w2
                    let col: SIMD3<Float> = s > 1e-6 ? (ca * w0 + cb * w1 + cc * w2) / s
                                                     : (ca + cb + cc) / 3
                    let i = (py * texW + px) * 4
                    bytes[i]     = UInt8(max(0, min(255, Int(col.x * 255))))
                    bytes[i + 1] = UInt8(max(0, min(255, Int(col.y * 255))))
                    bytes[i + 2] = UInt8(max(0, min(255, Int(col.z * 255))))
                    bytes[i + 3] = 255
                }
            }
        }
        // Blok-ichi yumshatish (2 o'tish, r=1) — yamoq kataklari "fokusdan
        // chiqqan" ko'rinadi. Blok chegarasiga KLAMP — qo'shni uchburchak
        // blokiga oqmaydi.
        blurBlocks(&bytes, triCount: tris.count, grid: grid, cell: cell, texW: texW)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: texW, height: texW, bitsPerComponent: 8,
                                  bytesPerRow: texW * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg).pngData()
    }
}

/// PNG'ni piksel bufer sifatida o'qish + UV bo'yicha namuna olish.
private struct PixelBuffer {
    let width: Int, height: Int
    let bytes: [UInt8]

    init?(url: URL) {
        guard let img = UIImage(contentsOfFile: url.path), let cg = img.cgImage else { return nil }
        // Rang namunasi uchun kichraytiramiz (xotira: 4096² × 10 atlas OOM bo'ladi).
        let cap = 512
        let scale = min(1.0, Double(cap) / Double(max(cg.width, cg.height)))
        width = max(1, Int(Double(cg.width) * scale))
        height = max(1, Int(Double(cg.height) * scale))
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buf
    }

    func sample(u: Float, v: Float) -> SIMD3<Float> {
        let x = max(0, min(width - 1, Int(u * Float(width))))
        let y = max(0, min(height - 1, Int((1 - v) * Float(height))))   // OBJ v pastdan-yuqoriga
        let i = (y * width + x) * 4
        return SIMD3(Float(bytes[i]) / 255, Float(bytes[i+1]) / 255, Float(bytes[i+2]) / 255)
    }
}
