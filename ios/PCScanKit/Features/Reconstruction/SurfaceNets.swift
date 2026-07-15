import Foundation
import simd

/// TSDF hajmidan yuza ajratish — Surface Nets usuli.
/// Har sign-change katakka bitta vertex (qirra kesishmalari o'rtachasi),
/// har sign-change qirra atrofidagi 4 katak vertexi kvadrat (2 uchburchak) bo'ladi.
/// Yo'nalish: yuzalar TSDF musbat (bo'sh joy — xona ichi) tomonga qaraydi.
enum SurfaceNets {

    struct Mesh {
        var positions: [SIMD3<Float>]
        var faces: [UInt32]   // uchburchaklar (3 tadan)
    }

    /// weights (ixtiyoriy, TSDF wsum): berilsa, yuza faqat IKKALA vokseli ham
    /// KUZATILGAN (w>minWeight) sign-change qirralarda chiqariladi. Bu
    /// kuzatilmagan hudud chegarasidagi soxta "orqa qobiq"/"parda"larni oldini
    /// oladi. minWeight>0 — yakka miltillagan o'qishdan hosil bo'lgan shovqin
    /// qobiqlari (qora/yaltiroq obyekt atrofidagi oq "konfetti") ham chiqmaydi.
    static func extract(tsdf: [Float], dims: SIMD3<Int>, mins: SIMD3<Float>, vox: Float,
                        weights: [Float]? = nil, minWeight: Float = 0) -> Mesh {
        let nx = dims.x, ny = dims.y, nz = dims.z
        let cx = nx - 1, cy = ny - 1, cz = nz - 1
        let hasW = weights != nil
        let wArr = weights ?? []

        @inline(__always) func g(_ i: Int, _ j: Int, _ k: Int) -> Float {
            tsdf[(i * ny + j) * nz + k]
        }
        @inline(__always) func observed(_ i: Int, _ j: Int, _ k: Int) -> Bool {
            !hasW || wArr[(i * ny + j) * nz + k] > minWeight
        }
        @inline(__always) func cellIdx(_ i: Int, _ j: Int, _ k: Int) -> Int {
            (i * cy + j) * cz + k
        }

        var cellVertex = [Int32](repeating: -1, count: cx * cy * cz)
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(1 << 18)

        // 1-bosqich: sign-change kataklarga vertex (qirra kesishmalari o'rtachasi).
        let corners: [SIMD3<Int>] = [
            SIMD3(0,0,0), SIMD3(1,0,0), SIMD3(0,1,0), SIMD3(1,1,0),
            SIMD3(0,0,1), SIMD3(1,0,1), SIMD3(0,1,1), SIMD3(1,1,1)
        ]
        // 12 qirra: korner juftlari
        let edges: [(Int, Int)] = [
            (0,1),(2,3),(4,5),(6,7),
            (0,2),(1,3),(4,6),(5,7),
            (0,4),(1,5),(2,6),(3,7)
        ]

        var vals = [Float](repeating: 0, count: 8)
        for i in 0..<cx {
            for j in 0..<cy {
                for k in 0..<cz {
                    var negMask = 0
                    for c in 0..<8 {
                        let v = g(i + corners[c].x, j + corners[c].y, k + corners[c].z)
                        vals[c] = v
                        if v < 0 { negMask |= 1 << c }
                    }
                    if negMask == 0 || negMask == 255 { continue }

                    // Qirra kesishmalarining o'rtachasi (lokal [0,1]^3 koordinatada)
                    var sum = SIMD3<Float>()
                    var count: Float = 0
                    for (a, b) in edges {
                        let va = vals[a], vb = vals[b]
                        if (va < 0) == (vb < 0) { continue }
                        let t = va / (va - vb)
                        let pa = SIMD3<Float>(Float(corners[a].x), Float(corners[a].y), Float(corners[a].z))
                        let pb = SIMD3<Float>(Float(corners[b].x), Float(corners[b].y), Float(corners[b].z))
                        sum += pa + (pb - pa) * t
                        count += 1
                    }
                    let local = sum / max(count, 1)
                    let world = mins + (SIMD3<Float>(Float(i), Float(j), Float(k)) + local + 0.5) * vox
                    cellVertex[cellIdx(i, j, k)] = Int32(positions.count)
                    positions.append(world)
                }
            }
        }

        // 2-bosqich: har sign-change qirra uchun kvadrat.
        // O'q d bo'ylab (p -> p+e_d) qirra atrofidagi 4 katak: p dan (u,v) bo'yicha -1 siljishlar.
        var faces: [UInt32] = []
        faces.reserveCapacity(positions.count * 6)

        func emitQuad(_ q0: Int32, _ q1: Int32, _ q2: Int32, _ q3: Int32, flip: Bool) {
            guard q0 >= 0, q1 >= 0, q2 >= 0, q3 >= 0 else { return }
            let (a, b, c, d) = flip
                ? (q0, q3, q2, q1)
                : (q0, q1, q2, q3)
            faces.append(UInt32(a)); faces.append(UInt32(b)); faces.append(UInt32(c))
            faces.append(UInt32(a)); faces.append(UInt32(c)); faces.append(UInt32(d))
        }

        for i in 0..<nx {
            for j in 0..<ny {
                for k in 0..<nz {
                    let v0 = g(i, j, k)

                    // X o'qi bo'ylab qirra
                    if i + 1 < nx && j > 0 && k > 0 && j < cy && k < cz {
                        let v1 = g(i + 1, j, k)
                        if (v0 < 0) != (v1 < 0), i < cx, observed(i, j, k), observed(i + 1, j, k) {
                            // Normal +X tomonга (v0 ichkarida, v1 tashqarida bo'lsa)
                            emitQuad(
                                cellVertex[cellIdx(i, j - 1, k - 1)],
                                cellVertex[cellIdx(i, j, k - 1)],
                                cellVertex[cellIdx(i, j, k)],
                                cellVertex[cellIdx(i, j - 1, k)],
                                flip: v0 >= 0   // v0 musbat (bo'sh) bo'lsa normal -X tomonga
                            )
                        }
                    }
                    // Y o'qi bo'ylab qirra
                    if j + 1 < ny && i > 0 && k > 0 && i < cx && k < cz {
                        let v1 = g(i, j + 1, k)
                        if (v0 < 0) != (v1 < 0), j < cy, observed(i, j, k), observed(i, j + 1, k) {
                            emitQuad(
                                cellVertex[cellIdx(i - 1, j, k - 1)],
                                cellVertex[cellIdx(i - 1, j, k)],
                                cellVertex[cellIdx(i, j, k)],
                                cellVertex[cellIdx(i, j, k - 1)],
                                flip: v0 >= 0
                            )
                        }
                    }
                    // Z o'qi bo'ylab qirra
                    if k + 1 < nz && i > 0 && j > 0 && i < cx && j < cy {
                        let v1 = g(i, j, k + 1)
                        if (v0 < 0) != (v1 < 0), k < cz, observed(i, j, k), observed(i, j, k + 1) {
                            emitQuad(
                                cellVertex[cellIdx(i - 1, j - 1, k)],
                                cellVertex[cellIdx(i, j - 1, k)],
                                cellVertex[cellIdx(i, j, k)],
                                cellVertex[cellIdx(i - 1, j, k)],
                                flip: v0 >= 0
                            )
                        }
                    }
                }
            }
        }

        return Mesh(positions: positions, faces: faces)
    }
}
