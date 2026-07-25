import Foundation
import CoreGraphics
import ImageIO

/// Yakuniy atlas PNG'larini o'tkirlashtirish (unsharp mask).
///
/// NEGA: yorug' tekis devorlar bake'da "sutdek/hira" chiqadi. O'lchandi (skan
/// 20260713-192242, manba kadr vs atlas): yorug' zonada detal manba KADRNING
/// O'ZIDA 1.56x kam — ya'ni bo'yalgan devor fizik jihatdan tekis, yuvadigan
/// narsa kam. Lekin bake bir necha kadr o'rtachasi bo'lgani uchun bor zaif
/// naqshni ham yumshatadi. Unsharp-mask (asl + amount·(asl − blur)) o'sha zaif
/// naqshni qaytarib, "hira" ni sezilarli kamaytiradi.
///
/// FAQAT real tekstura atlaslari (`room_material####_map_Kd.png`). `room_unseen`
/// va `fillbake` — ATAYIN silliq to'ldirish; ularni o'tkirlash chok/dog'ni
/// qaytaradi. Gutter (chart orasidagi qora fon) yaqinida o'tkirlash halo (oq
/// hoshiya) beradi — shuning uchun chetdan `radius` ichkaridagina qo'llanadi.
enum AtlasSharpen {

    /// O'tkirlik kuchi (UserDefaults "atlasSharpen" bilan A/B). 0 -> o'chiq.
    static var amount: Float {
        if UserDefaults.standard.object(forKey: "atlasSharpen") == nil { return 0.6 }
        return UserDefaults.standard.float(forKey: "atlasSharpen")
    }
    private static let radius = 2
    private static let gutterLum: Float = 12   // bundan qorong'i = gutter

    static func run(objURL: URL, log: (String) -> Void) {
        let amt = amount
        guard amt > 0.001 else { log("SHARPEN o'chiq (amount=0)"); return }
        let dir = objURL.deletingLastPathComponent()
        guard let mtl = try? String(contentsOf: dir.appendingPathComponent("room.mtl"),
                                    encoding: .utf8) else { log("SHARPEN: mtl yo'q"); return }
        var pngs = Set<String>()
        for line in mtl.split(separator: "\n") where line.hasPrefix("map_Kd ") {
            let f = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            if f.contains("unseen") || f == "fillbake.png" { continue }  // silliq to'ldirish EMAS
            pngs.insert(f)
        }
        var done = 0
        // Har PNG autoreleasepool ichida — dekodlangan CGImage/CGContext (yana bir
        // to'liq w*h*4 bufer) darhol bo'shatilsin, scope oxirigacha yig'ilib qolmasin.
        for name in pngs.sorted() {
            autoreleasepool {
                if sharpenPNG(dir.appendingPathComponent(name), amount: amt) { done += 1 }
            }
        }
        log("SHARPEN atlas=\(done) amount=\(String(format: "%.2f", amt)) radius=\(radius)")
    }

    /// Bitta PNG'ni o'rnida o'tkirlashtiradi. Qaytadi: muvaffaqiyatmi.
    static func sharpenPNG(_ url: URL, amount: Float) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        let w = img.width, h = img.height
        guard w > 2 * radius, h > 2 * radius else { return false }
        // Xotira qopqog'i: sharpenPNG ~9 ta Float massiv (~40 B/piksel) ajratadi —
        // 4096² atlas ≈ 640MB. Qurilma byudjetidan oshsa o'tkirlashni O'TKAZIB
        // YUBORAMIZ (kosmetik effekt; jetsam OOM'ni oldini olish muhimroq).
        guard 40 * w * h <= MemoryBudget.current().atlasFloatBudget else { return false }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

        let n = w * h
        var R = [Float](repeating: 0, count: n)
        var G = [Float](repeating: 0, count: n)
        var B = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: n)     // 1 = gutter emas
        for i in 0..<n {
            let r = Float(px[i * 4]), g = Float(px[i * 4 + 1]), b = Float(px[i * 4 + 2])
            R[i] = r; G[i] = g; B[i] = b
            real[i] = (0.2126 * r + 0.7152 * g + 0.0722 * b) > gutterLum ? 1 : 0
        }
        // Gutter yaqinidan qochish: maska ham blur qilinib, to'liq real (>0.98)
        // bo'lgan piksellargagina o'tkirlash qo'llanadi (chetda halo bo'lmasin).
        var maskBlur = real
        boxBlur(&maskBlur, w: w, h: h, radius: radius)
        var Rb = R, Gb = G, Bb = B
        boxBlur(&Rb, w: w, h: h, radius: radius)
        boxBlur(&Gb, w: w, h: h, radius: radius)
        boxBlur(&Bb, w: w, h: h, radius: radius)

        for i in 0..<n where real[i] > 0 && maskBlur[i] > 0.98 {
            let nr = R[i] + amount * (R[i] - Rb[i])
            let ng = G[i] + amount * (G[i] - Gb[i])
            let nb = B[i] + amount * (B[i] - Bb[i])
            px[i * 4]     = UInt8(max(0, min(255, nr)))
            px[i * 4 + 1] = UInt8(max(0, min(255, ng)))
            px[i * 4 + 2] = UInt8(max(0, min(255, nb)))
        }

        guard let out = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let outImg = out.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, outImg, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// Ajratiladigan quti-blur (integral emas — oddiy yugurma yig'indi).
    private static func boxBlur(_ a: inout [Float], w: Int, h: Int, radius: Int) {
        let cnt = Float(2 * radius + 1)
        var tmp = a
        // Gorizontal
        for y in 0..<h {
            var acc: Float = 0
            let row = y * w
            for x in 0...radius { acc += a[row + x] }
            for x in 0..<w {
                tmp[row + x] = acc / cnt
                let add = x + radius + 1, sub = x - radius
                acc += (add < w ? a[row + add] : a[row + w - 1])
                acc -= (sub >= 0 ? a[row + sub] : a[row])
            }
        }
        // Vertikal
        for x in 0..<w {
            var acc: Float = 0
            for y in 0...radius { acc += tmp[y * w + x] }
            for y in 0..<h {
                a[y * w + x] = acc / cnt
                let add = y + radius + 1, sub = y - radius
                acc += (add < h ? tmp[add * w + x] : tmp[(h - 1) * w + x])
                acc -= (sub >= 0 ? tmp[sub * w + x] : tmp[x])
            }
        }
    }
}
