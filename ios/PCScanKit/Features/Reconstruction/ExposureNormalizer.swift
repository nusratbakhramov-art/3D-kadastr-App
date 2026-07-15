import Foundation

/// Kadrlar orasidagi ekspozitsiya farqini tenglashtirish (texrecon uchun).
///
/// Muammo: ARKit avto-ekspozitsiyasi deraza tomon qaraganda kadrni qorayтиради,
/// qorong'i burchakda yoritadi. texrecon turli yorqinlikdagi kadrlarni bitta
/// atlasga tikkanda devorlarda pereexposure oq dog'lar va qora chiziqlar qoladi.
///
/// GIBRID yechim:
/// - EV (KeyframePose.exposureOffset) bo'lsa: fizik ekspozitsiya farqi
///   2^(EVmed−EV) bilan tenglashtiriladi. EV ISHORASI aprior noma'lum
///   (Apple hujjati noaniq) — ikkala ishora sinab ko'riladi, qaysi biri
///   luma tarqalishini ko'proq kamaytirsa, o'sha EMPIRIK tanlanadi.
///   Qoldiq farq yumshoq luma-gain bilan tuzatiladi (klamp [0.8, 1.25]).
/// - EV yo'q/foydasiz bo'lsa: sof luma-gain (FusionEngine uslubi,
///   klamp [0.75, 1.35]) — kontent-bog'liq, shuning uchun tor klamp.
///
/// Diqqat: hamma hisob ENCODED (sRGB) domenida — FusionEngine bilan izchil;
/// gain ham encoded piksellarga to'g'ridan-to'g'ri ko'paytiriladi (C++).
enum ExposureNormalizer {

    /// Yakuniy gain chegarasi (himoya).
    static let hardClamp: ClosedRange<Float> = 0.5...2.0

    /// Har kadr uchun encoded-domen gain hisoblaydi.
    /// - lumas: kadr o'rtacha yorqinligi (encoded RGB o'rtachasi, 0..255)
    /// - evs: kadr exposureOffset (EV) yoki nil (eski skan)
    static func computeGains(lumas: [Float], evs: [Float?]) -> [Float] {
        let n = lumas.count
        guard n >= 3 else { return [Float](repeating: 1, count: n) }

        let safeLumas = lumas.map { max($0, 1) }
        let lumaMed = median(safeLumas)

        // EV yo'lини sinash: ishora kalibrovkasi.
        let evVals = evs.compactMap { $0 }
        var evGains: [Float]? = nil
        if evVals.count == n, let lo = evVals.min(), let hi = evVals.max(), hi - lo > 0.15 {
            let evMed = median(evVals)
            let baseline = logSpread(safeLumas)
            var bestSpread = baseline * 0.9      // kamida 10% yaxshilanish talab
            for sign: Float in [1, -1] {
                let g = (0..<n).map { exp2(sign * (evMed - evVals[$0])) }
                let adjusted = (0..<n).map { safeLumas[$0] * g[$0] }
                let spread = logSpread(adjusted)
                if spread < bestSpread { bestSpread = spread; evGains = g }
            }
        }

        var gains = [Float](repeating: 1, count: n)
        for i in 0..<n {
            var g: Float
            if let evGains {
                // EV asosiy + yumshoq qoldiq luma tuzatish.
                let residual = lumaMed / (safeLumas[i] * evGains[i])
                g = evGains[i] * min(max(residual, 0.8), 1.25)
            } else {
                // Sof luma-gain (FusionEngine klampi).
                g = min(max(lumaMed / safeLumas[i], 0.75), 1.35)
            }
            gains[i] = min(max(g, hardClamp.lowerBound), hardClamp.upperBound)
        }
        return gains
    }

    // MARK: - Statistika

    private static func median(_ v: [Float]) -> Float {
        let s = v.sorted()
        return s[s.count / 2]
    }

    /// log2 bo'yicha standart og'ish — yorqinlik tarqalishi o'lchovi.
    private static func logSpread(_ v: [Float]) -> Float {
        let logs = v.map { log2(max($0, 1e-3)) }
        let mean = logs.reduce(0, +) / Float(logs.count)
        let varSum = logs.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) }
        return sqrt(varSum / Float(logs.count))
    }
}
