import Foundation
import RoomPlan
import simd

/// RoomPlan POL KONTURI bo'yicha xona TASHQARISIDAGI geometriyani kesish.
///
/// TSDF/Poisson meshi ba'zan devor ortiga 15–25sm "chiqib ketadi" (oyna/plitka
/// aksi, eshik oralig'idan ko'ringan qo'shni hudud, LiDAR multipath). Bu
/// bo'laklar orbit ko'rinishda devor tashqarisida osilib qoladi.
///
/// Mezon — POL KONTURI (footprint) + zaxira, "har devor tekisligining ortidagi
/// hamma narsa" EMAS. Eski mezon faqat QAVARIQ xonada to'g'ri edi: L-shaklli
/// xonada bitta devorning ortida xonaning HAQIQIY qismi turadi va u kesilardi
/// (o'lchandi: 33.7% vs 1.3% — batafsil `footprintMargin` izohida). Kontur
/// bo'lmagan/buzuq skanlarda eski devor-mezoni zaxira sifatida qoladi.
/// Pol ostidagi va shift tepasidagi geometriya balandlik bo'yicha kesiladi.
///
/// Xavfsizlik darvozasi: kesish uchburchaklarning 60% dan ko'pini olsa —
/// room ma'lumoti meshga mos emas deb hisoblanadi, asl mesh qaytariladi.
enum RoomClipper {

    // MARK: - Sozlamalar

    /// Devor tekisligidan tashqariga ruxsat etilgan chuqurlik (m) —
    /// TSDF voxel shovqini (~1.5-3sm) + devor tekislik xatosini qoplaydi.
    private static let wallMargin: Float = 0.07
    /// Devor to'rtburchagi chetiga qo'shiladigan zaxira (m) — burchaklar va
    /// RoomPlan biroz kalta o'lchagan devorlar uchun.
    private static let extentPad: Float = 0.25
    private static let floorMargin: Float = 0.10
    private static let ceilingMargin: Float = 0.15
    /// Pol konturidan tashqariga ruxsat etilgan masofa (m).
    ///
    /// NEGA KONTUR, DEVOR EMAS: ilgari har devor uchun "shu devor tekisligining
    /// ORTIDAGI hamma narsa — tashqarida" deb hisoblanardi. Bu faqat QAVARIQ
    /// (to'rtburchak) xonada to'g'ri. Bu xona esa L-shaklli (pol konturi 14
    /// burchak) — unda bitta devorning "ortida" xonaning HAQIQIY qismi turadi.
    /// O'lchandi (skan 20260717-110900, ARKit meshiga solib):
    ///   devor yarim-fazolari -> 92105 cho'qqi (33.7%) kesilardi
    ///   pol konturi + 0.25m  ->  3488 cho'qqi ( 1.3%)
    /// Ya'ni eski mezon 26 barobar ortiqcha kesardi — pol va shiftni ham
    /// (kesilganlarning 21691 tasi pol balandligida, 19329 tasi shift).
    /// Kontur yuzasi 65.8 m² — RoomPlan'ning o'z raqami bilan aynan mos.
    private static let footprintMargin: Float = 0.25
    /// Kesishdan keyin qolgan mayda orollar chegarasi.
    private static let minComponentVerts = 120

    private struct WallPlane {
        let c: SIMD3<Float>       // devor markazi
        let nIn: SIMD3<Float>     // xona ichiga qaragan normal
        let xAxis: SIMD3<Float>
        let yAxis: SIMD3<Float>
        let halfW: Float
        let halfH: Float
    }

    // MARK: - Pol konturi (footprint)

    /// Pol konturi world XZ da. `polygonCorners` surface-lokal — floor.transform
    /// bilan world'ga o'tkaziladi. Kontur yo'q/buzuq bo'lsa — bo'sh (zaxira yo'lga).
    private static func footprintXZ(of room: CapturedRoom) -> [SIMD2<Float>] {
        guard let floor = room.floors.max(by: {
            RoomGeometry.polygonArea($0.polygonCorners) < RoomGeometry.polygonArea($1.polygonCorners)
        }), floor.polygonCorners.count >= 3 else { return [] }
        let t = floor.transform
        let world = floor.polygonCorners.map { c -> SIMD2<Float> in
            let w = t * SIMD4<Float>(c.x, c.y, c.z, 1)
            return SIMD2(w.x, w.z)
        }
        // Aql-idrok: kontur devor markazlari atrofida bo'lsin (koordinata buzuq emas).
        var c = SIMD2<Float>.zero
        for p in world { c += p }
        c /= Float(world.count)
        var wc = SIMD2<Float>.zero
        for w in room.walls {
            wc += SIMD2(w.transform.columns.3.x, w.transform.columns.3.z)
        }
        wc /= Float(max(room.walls.count, 1))
        guard simd_distance(c, wc) < 3 else { return [] }
        return world
    }

    /// Nuqta konturning ICHIDA yoki undan `margin` dan yaqinda (qirraga masofa).
    private static func insideFootprint(_ p: SIMD2<Float>, _ poly: [SIMD2<Float>],
                                        margin: Float) -> Bool {
        var inside = false
        var j = poly.count - 1
        var best = Float.greatestFiniteMagnitude
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            // qirraga masofa (chegaradan tashqaridagi zaxira uchun)
            let ab = b - a
            let len2 = simd_dot(ab, ab)
            let t = len2 > 1e-9 ? min(max(simd_dot(p - a, ab) / len2, 0), 1) : 0
            best = min(best, simd_distance(p, a + ab * t))
            j = i
        }
        return inside || best <= margin
    }

    // MARK: - Kesish

    static func clip(_ mesh: LiDARMeshData, room: CapturedRoom,
                     log: ((String) -> Void)? = nil) -> LiDARMeshData {
        guard !mesh.isEmpty, !room.walls.isEmpty else { return mesh }

        // Xona markazi — devor markazlari o'rtachasi (ichki tomonni aniqlash uchun).
        var center = SIMD3<Float>.zero
        for w in room.walls {
            let t = w.transform
            center += SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        }
        center /= Float(room.walls.count)

        var planes: [WallPlane] = []
        planes.reserveCapacity(room.walls.count)
        for w in room.walls {
            let t = w.transform
            var n = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
            let l = simd_length(n)
            guard l > 1e-6 else { continue }
            n /= l
            let c = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            if simd_dot(center - c, n) < 0 { n = -n }
            planes.append(WallPlane(
                c: c, nIn: n,
                xAxis: simd_normalize(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z)),
                yAxis: simd_normalize(SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z)),
                halfW: w.dimensions.x / 2 + extentPad,
                halfH: w.dimensions.y / 2 + extentPad))
        }
        guard !planes.isEmpty else { return mesh }

        // Pol/shift balandliklari (devor pastki/yuqori qirralaridan; pol aniqrog'i floors'dan).
        var floorY = Float.greatestFiniteMagnitude
        var ceilY = -Float.greatestFiniteMagnitude
        for (i, w) in room.walls.enumerated() where i < planes.count {
            floorY = min(floorY, planes[i].c.y - w.dimensions.y / 2)
            ceilY = max(ceilY, planes[i].c.y + w.dimensions.y / 2)
        }
        for f in room.floors {
            floorY = min(floorY, f.transform.columns.3.y)
        }

        // Pol konturi (world XZ) — xona TASHQARISINI aniqlashning to'g'ri mezoni.
        let footprint = footprintXZ(of: room)

        // 1. Har cho'qqi: pol konturidan (yoki pol/shift chegarasidan) tashqarida?
        let vc = mesh.vertexCount
        var outside = [Bool](repeating: false, count: vc)
        let chunk = 8192
        mesh.positions.withUnsafeBufferPointer { pp in
            outside.withUnsafeMutableBufferPointer { ob in
                DispatchQueue.concurrentPerform(iterations: (vc + chunk - 1) / chunk) { ci in
                    let lo = ci * chunk, hi = min(lo + chunk, vc)
                    for vi in lo..<hi {
                        let p = SIMD3<Float>(pp[vi * 3], pp[vi * 3 + 1], pp[vi * 3 + 2])
                        if p.y < floorY - floorMargin || p.y > ceilY + ceilingMargin {
                            ob[vi] = true
                            continue
                        }
                        // Xona TASHQARISI = pol KONTURIDAN tashqarida (footprint),
                        // "birorta devor tekisligining ortida" EMAS.
                        if !footprint.isEmpty {
                            ob[vi] = !insideFootprint(SIMD2(p.x, p.z), footprint,
                                                      margin: footprintMargin)
                            continue
                        }
                        // Kontur yo'q (eski skan) — zaxira: devor yarim-fazolari.
                        for pl in planes {
                            let d = p - pl.c
                            if simd_dot(d, pl.nIn) < -wallMargin,
                               abs(simd_dot(d, pl.xAxis)) < pl.halfW,
                               abs(simd_dot(d, pl.yAxis)) < pl.halfH {
                                ob[vi] = true
                                break
                            }
                        }
                    }
                }
            }
        }

        // 2. Uchburchak: 3 cho'qqidan kamida 2 tasi tashqarida bo'lsa — kesiladi.
        var kept = [UInt32]()
        kept.reserveCapacity(mesh.indices.count)
        var removed = 0
        var ti = 0
        while ti + 2 < mesh.indices.count {
            let a = Int(mesh.indices[ti]), b = Int(mesh.indices[ti + 1]), c = Int(mesh.indices[ti + 2])
            let cnt = (outside[a] ? 1 : 0) + (outside[b] ? 1 : 0) + (outside[c] ? 1 : 0)
            if cnt >= 2 {
                removed += 1
            } else {
                kept.append(mesh.indices[ti]); kept.append(mesh.indices[ti + 1]); kept.append(mesh.indices[ti + 2])
            }
            ti += 3
        }
        guard removed > 0 else {
            log?("ROOMCLIP: tashqarida geometriya yo'q")
            return mesh
        }

        // Xavfsizlik: room mos kelmasa (koordinata buzuq) — asl mesh qoladi.
        let totalTris = mesh.indices.count / 3
        guard removed < totalTris * 6 / 10 else {
            log?("ROOMCLIP bekor: \(removed)/\(totalTris) tris kesilardi — room meshga mos emas")
            return mesh
        }

        // 3. Kesishdan qolgan mayda orollar + zichlashtirish.
        let cleaned = FreeSpaceCarver.removeSmallComponents(indices: kept, vertexCount: vc,
                                                            minVerts: minComponentVerts, log: log)
        let out = compact(positions: mesh.positions, normals: mesh.normals, indices: cleaned)
        log?("ROOMCLIP tris \(totalTris) -> \(out.indices.count / 3) (xona tashqarisida \(removed), mezon=\(footprint.isEmpty ? "devor" : "kontur"))")
        return out.isEmpty ? mesh : out
    }

    // MARK: - Zichlashtirish

    private static func compact(positions: [Float], normals: [Float], indices: [UInt32]) -> LiDARMeshData {
        let vc = positions.count / 3
        var remap = [Int32](repeating: -1, count: vc)
        var pos = [Float](); var nrm = [Float]()
        var idx = [UInt32](); idx.reserveCapacity(indices.count)
        for i in indices {
            let v = Int(i)
            if remap[v] == -1 {
                remap[v] = Int32(pos.count / 3)
                pos.append(positions[v * 3]); pos.append(positions[v * 3 + 1]); pos.append(positions[v * 3 + 2])
                nrm.append(normals[v * 3]); nrm.append(normals[v * 3 + 1]); nrm.append(normals[v * 3 + 2])
            }
            idx.append(UInt32(remap[v]))
        }
        return LiDARMeshData(positions: pos, normals: nrm, indices: idx)
    }
}
