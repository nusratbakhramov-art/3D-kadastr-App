import Foundation
import CoreGraphics
import ImageIO

/// Atlas gutter'ini to'ldirish (dilatatsiya) — chart chetidagi QORA hoshiyani yo'qotadi.
///
/// MUAMMO (o'lchandi, skan 20260713-192242): yuzalarning UV'i chart chetidagi
/// YOZILMAGAN piksellarga tushib qoladi va render bilinear/mipmap bilan atlas
/// fonini — qora rangni — oladi. Jami 2.84 m² yuza shunday. MUHIM: chartning
/// o'zi joyida (">64 px = 0.00 m²" — birorta chart yo'qolmagan), rang atigi
/// 1–32 px narida turadi; 77% i 4 px ichida. Ya'ni bu bake xatosi emas, gutter.
///
/// YECHIM: yozilgan ranglarni fon tomon to'lqin-to'lqin kengaytirish. Har bir fon
/// pikseli qo'shni YOZILGAN piksellar o'rtachasini oladi va keyingi to'lqin uchun
/// o'zi ham "yozilgan" bo'ladi. Faqat chegaradan tarqaladi (BFS), butun rasm
/// bo'ylab emas — shuning uchun narxi chart perimetriga proporsional.
///
/// NEGA (0,0,0) — ISHONCHLI fon belgisi: o'lchandi, atlasning 41.5–47.3% i aynan
/// qora, luma<1 da 41.7% va luma<4 da 42.0% — ya'ni 0 dan keyin egri TEKIS.
/// Haqiqiy qorong'i kontent (masalan TV ekrani) hech qachon aynan 0 emas, demak
/// uni xato yoritib yubormaymiz.
///
/// TARTIB: `AtlasSharpen` DAN KEYIN ishlashi shart — o'tkirlash gutterni halo
/// bermasligi uchun qora fonga tayanadi, dilatatsiya esa o'sha fonni yo'q qiladi.
enum AtlasDilate {

    /// Kengaytirish radiusi piksellarda (UserDefaults "atlasDilate"). 0 -> o'chiq.
    /// 16 px o'lchangan holatlarning 93.5% ini, 32 px 99% ini qoplaydi.
    static var passes: Int {
        if UserDefaults.standard.object(forKey: "atlasDilate") == nil { return 24 }
        return UserDefaults.standard.integer(forKey: "atlasDilate")
    }

    static func run(objURL: URL, log: (String) -> Void) {
        let n = passes
        guard n > 0 else { log("DILATE o'chiq (passes=0)"); return }
        let dir = objURL.deletingLastPathComponent()
        guard let mtl = try? String(contentsOf: dir.appendingPathComponent("room.mtl"),
                                    encoding: .utf8) else { log("DILATE: mtl yo'q"); return }
        var pngs = Set<String>()
        for line in mtl.split(separator: "\n") where line.hasPrefix("map_Kd ") {
            pngs.insert(String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces))
        }
        var done = 0, filled = 0
        for name in pngs.sorted() {
            let f = dilatePNG(dir.appendingPathComponent(name), passes: n)
            if f >= 0 { done += 1; filled += f }
        }
        log("DILATE atlas=\(done) passes=\(n) to'ldirilgan=\(filled) px")
    }

    /// Bitta PNG'ni o'rnida kengaytiradi. Qaytadi: to'ldirilgan piksel soni, xatoda -1.
    static func dilatePNG(_ url: URL, passes: Int) -> Int {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return -1 }
        let w = img.width, h = img.height
        guard w > 2, h > 2 else { return -1 }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return -1 }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

        let count = w * h
        var isSet = [Bool](repeating: false, count: count)
        for i in 0..<count {
            isSet[i] = !(px[i * 4] == 0 && px[i * 4 + 1] == 0 && px[i * 4 + 2] == 0)
        }
        // Boshlang'ich chegara: yozilgan pikselga tegib turgan FON piksellari.
        var queued = [Bool](repeating: false, count: count)
        var frontier: [Int] = []
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if isSet[i] { continue }
                if hasSetNeighbor(x: x, y: y, w: w, h: h, isSet: isSet) {
                    queued[i] = true
                    frontier.append(i)
                }
            }
        }
        var totalFilled = 0
        for _ in 0..<passes {
            if frontier.isEmpty { break }
            // Rang JORIY holatdan olinadi, keyin birdan qo'llanadi — bir to'lqin
            // ichida yangi piksellar bir-biridan nusxa ko'chirmasin (yo'l-yo'l bo'lardi).
            var newColors = [(Int, UInt8, UInt8, UInt8)]()
            newColors.reserveCapacity(frontier.count)
            for i in frontier where !isSet[i] {
                let x = i % w, y = i / w
                var r = 0, g = 0, b = 0, cnt = 0
                for dy in -1...1 {
                    let ny = y + dy
                    if ny < 0 || ny >= h { continue }
                    for dx in -1...1 {
                        let nx = x + dx
                        if nx < 0 || nx >= w || (dx == 0 && dy == 0) { continue }
                        let j = ny * w + nx
                        if !isSet[j] { continue }
                        r += Int(px[j * 4]); g += Int(px[j * 4 + 1]); b += Int(px[j * 4 + 2])
                        cnt += 1
                    }
                }
                guard cnt > 0 else { continue }
                newColors.append((i, UInt8(r / cnt), UInt8(g / cnt), UInt8(b / cnt)))
            }
            if newColors.isEmpty { break }
            for (i, r, g, b) in newColors {
                px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 255
                isSet[i] = true
            }
            totalFilled += newColors.count
            // Keyingi to'lqin: hozir to'ldirilganlarning hali fon bo'lgan qo'shnilari.
            var next: [Int] = []
            next.reserveCapacity(newColors.count)
            for (i, _, _, _) in newColors {
                let x = i % w, y = i / w
                for dy in -1...1 {
                    let ny = y + dy
                    if ny < 0 || ny >= h { continue }
                    for dx in -1...1 {
                        let nx = x + dx
                        if nx < 0 || nx >= w { continue }
                        let j = ny * w + nx
                        if isSet[j] || queued[j] { continue }
                        queued[j] = true
                        next.append(j)
                    }
                }
            }
            frontier = next
        }

        guard let out = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let outImg = out.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return -1 }
        CGImageDestinationAddImage(dest, outImg, nil)
        guard CGImageDestinationFinalize(dest) else { return -1 }
        return totalFilled
    }

    private static func hasSetNeighbor(x: Int, y: Int, w: Int, h: Int, isSet: [Bool]) -> Bool {
        for dy in -1...1 {
            let ny = y + dy
            if ny < 0 || ny >= h { continue }
            for dx in -1...1 {
                let nx = x + dx
                if nx < 0 || nx >= w || (dx == 0 && dy == 0) { continue }
                if isSet[ny * w + nx] { return true }
            }
        }
        return false
    }
}
