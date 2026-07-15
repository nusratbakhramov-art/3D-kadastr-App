import Foundation
import simd

/// Bitta 3D Gaussian (3DGS, Kerbl va b. 2023).
/// Trening davomida barcha maydonlar optimallashtiriladi.
struct GaussianSplat {
    var position: SIMD3<Float>      // markaz (world)
    var scale: SIMD3<Float>         // log-masshtab (anizotrop) — exp() bilan haqiqiy o'lcham
    var rotation: SIMD4<Float>      // birlik kvaternion (x,y,z,w)
    var opacity: Float              // logit — sigmoid() bilan 0..1
    var shDC: SIMD3<Float>          // SH 0-daraja (asosiy rang, DC koeffitsiyenti)
    // Yuqori SH keyingi bosqichda qo'shiladi (ko'rish burchagiga bog'liq rang)
}

/// Gaussian splat buluti + LiDAR nuqta bulutidan initsializatsiya + 3DGS .ply eksport.
struct GaussianSplatModel {

    var splats: [GaussianSplat]

    // SH 0-daraja doimiysi (3DGS konvensiyasi): rang = 0.5 + C0 * shDC
    private static let SH_C0: Float = 0.28209479177387814

    // MARK: - LiDAR nuqta bulutidan init

    /// Har nuqta → bitta gaussian. Rang nuqtadan, masshtab qo'shni-oraliqdan,
    /// opacity o'rtacha, aylanish birlik. Bu — treningning boshlang'ich holati.
    static func initialize(
        from points: [PointCloudBuilder.Point],
        initialScale: Float = 0.02
    ) -> GaussianSplatModel {
        let logScale = log(max(initialScale, 1e-4))
        let initOpacityLogit: Float = logit(0.5)

        var splats = [GaussianSplat]()
        splats.reserveCapacity(points.count)
        for p in points {
            let color = SIMD3<Float>(
                Float(p.color.x) / 255, Float(p.color.y) / 255, Float(p.color.z) / 255
            )
            let shDC = (color - 0.5) / SH_C0
            splats.append(GaussianSplat(
                position: p.position,
                scale: SIMD3<Float>(repeating: logScale),
                rotation: SIMD4<Float>(0, 0, 0, 1),
                opacity: initOpacityLogit,
                shDC: shDC
            ))
        }
        return GaussianSplatModel(splats: splats)
    }

    // MARK: - Yordamchi

    private static func logit(_ x: Float) -> Float {
        let c = min(max(x, 1e-6), 1 - 1e-6)
        return log(c / (1 - c))
    }

    /// Ko'rsatish uchun: har splatning haqiqiy rangi (0..1).
    func displayColor(_ i: Int) -> SIMD3<Float> {
        simd_clamp(0.5 + Self.SH_C0 * splats[i].shDC, .zero, SIMD3<Float>(repeating: 1))
    }

    // MARK: - 3DGS .ply eksport (standart format — istalgan splat viewer o'qiydi)

    func plyData() -> Data {
        var header = "ply\n"
        header += "format binary_little_endian 1.0\n"
        header += "element vertex \(splats.count)\n"
        header += "property float x\nproperty float y\nproperty float z\n"
        header += "property float nx\nproperty float ny\nproperty float nz\n"
        header += "property float f_dc_0\nproperty float f_dc_1\nproperty float f_dc_2\n"
        header += "property float opacity\n"
        header += "property float scale_0\nproperty float scale_1\nproperty float scale_2\n"
        header += "property float rot_0\nproperty float rot_1\nproperty float rot_2\nproperty float rot_3\n"
        header += "end_header\n"

        var data = Data(header.utf8)
        data.reserveCapacity(header.count + splats.count * 62)
        for s in splats {
            appendFloats(&data, [s.position.x, s.position.y, s.position.z])
            appendFloats(&data, [0, 0, 0])  // normal (splat uchun ishlatilmaydi)
            appendFloats(&data, [s.shDC.x, s.shDC.y, s.shDC.z])
            appendFloats(&data, [s.opacity])
            appendFloats(&data, [s.scale.x, s.scale.y, s.scale.z])
            // 3DGS konvensiyasi: rot (w,x,y,z)
            appendFloats(&data, [s.rotation.w, s.rotation.x, s.rotation.y, s.rotation.z])
        }
        return data
    }

    private func appendFloats(_ data: inout Data, _ values: [Float]) {
        for var v in values {
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
    }
}
