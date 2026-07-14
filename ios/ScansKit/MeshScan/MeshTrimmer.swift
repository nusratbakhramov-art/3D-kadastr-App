import Foundation
import simd

/// Scaniverse-uslubidagi chegara tozalash (Mac `clean_mesh.py` mantiqi, on-device).
///  1) PER-FACE VISIBILITY — har yuz nechta kamera frontal ko'rgan (frustum+facing+depth-occlusion)
///  2) ko'rilmagan yuzlarni (cho'zilgan/yirtiq chegara flaplari) o'chirish
///  3) kichik bog'langan komponentlarni (flying triangles) o'chirish
enum MeshTrimmer {

    static func trim(
        _ mesh: WeldedMesh,
        keyframes: [KeyframeStore.Keyframe],
        minObservations: Int = 1,
        strongFacing: Float = 0.4,
        minComponentFaces: Int = 200,
        erodeRings: Int = 0,
        onProgress: ((Int) -> Void)? = nil
    ) -> WeldedMesh {
        let V = mesh.positions
        let idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 100, keyframes.count >= 2 else { return mesh }

        // Yuz markazlari + normal
        var centroid = [SIMD3<Float>](repeating: .zero, count: faceCount)
        var fnormal = [SIMD3<Float>](repeating: .zero, count: faceCount)
        for f in 0..<faceCount {
            let a = V[Int(idx[f*3])], b = V[Int(idx[f*3+1])], c = V[Int(idx[f*3+2])]
            centroid[f] = (a + b + c) / 3
            let n = simd_cross(b - a, c - a)
            let l = simd_length(n)
            fnormal[f] = l > 1e-9 ? n / l : SIMD3<Float>(0, 1, 0)
        }

        // Kamera parametrlarini oldindan tayyorlash
        struct Cam {
            let invT: simd_float4x4
            let pos: SIMD3<Float>
            let fx, fy, cx, cy: Float
            let w, h: Float
            let depth: [Float32]?
            let dw, dh: Int
        }
        let cams: [Cam] = keyframes.map { kf in
            let k = kf.intrinsics
            return Cam(invT: kf.transform.inverse, pos: kf.position,
                       fx: k[0][0], fy: k[1][1], cx: k[2][0], cy: k[2][1],
                       w: Float(kf.width), h: Float(kf.height),
                       depth: kf.depthMap, dw: kf.depthWidth, dh: kf.depthHeight)
        }

        // Per-face: nechta kamera ko'rgan + eng kuchli facing (parallel)
        let obsPtr = UnsafeMutablePointer<Int32>.allocate(capacity: faceCount)
        let maxfPtr = UnsafeMutablePointer<Float>.allocate(capacity: faceCount)
        obsPtr.initialize(repeating: 0, count: faceCount)
        maxfPtr.initialize(repeating: 0, count: faceCount)
        defer { obsPtr.deallocate(); maxfPtr.deallocate() }

        DispatchQueue.concurrentPerform(iterations: faceCount) { f in
            let cen = centroid[f], nrm = fnormal[f]
            var count: Int32 = 0
            var maxf: Float = 0
            for cam in cams {
                let pc = cam.invT * SIMD4<Float>(cen.x, cen.y, cen.z, 1)
                let d = -pc.z
                if d <= 0.15 || d > 4.0 { continue }
                let u = cam.fx * pc.x / d + cam.cx
                let v = cam.cy - cam.fy * pc.y / d
                let mx = cam.w * 0.02, my = cam.h * 0.02
                if u <= mx || u >= cam.w - mx || v <= my || v >= cam.h - my { continue }
                let viewDir = cen - cam.pos
                let vl = simd_length(viewDir) + 1e-9
                let facing = -simd_dot(nrm, viewDir) / vl
                if facing <= 0.15 { continue }
                // depth-occlusion
                if let depth = cam.depth, cam.dw > 0, cam.dh > 0 {
                    let du = min(max(Int(u / cam.w * Float(cam.dw)), 0), cam.dw - 1)
                    let dv = min(max(Int(v / cam.h * Float(cam.dh)), 0), cam.dh - 1)
                    let stored = depth[dv * cam.dw + du]
                    let tol = max(0.1, d * 0.1)
                    if stored > 0.05 && stored + tol < d { continue }
                }
                count += 1
                if facing > maxf { maxf = facing }
            }
            obsPtr[f] = count
            maxfPtr[f] = maxf
        }
        onProgress?(60)

        // keep = ko'p kamera YOKI bitta kuchli frontal
        var keepFace = [Bool](repeating: false, count: faceCount)
        for f in 0..<faceCount {
            keepFace[f] = Int(obsPtr[f]) >= minObservations || maxfPtr[f] > strongFacing
        }

        // Kichik komponentlarni o'chirish (union-find, umumiy qirra bo'yicha)
        keepFace = removeSmallComponents(idx: idx, keepFace: keepFace, minFaces: minComponentFaces)
        onProgress?(80)

        // Chegara eroziyasi — DEFAULT O'CHIQ (erodeRings: 0). Eroziya har teshik/chegara
        // atrofidan 1 halqa yuzni o'chiradi → katta xonada teshiklarni KENGAYTIRADI.
        // Ko'rilmagan flaplar allaqachon visibility testda o'chadi, shuning uchun kerak emas.
        if erodeRings > 0 {
            keepFace = erodeBoundary(idx: idx, vertexCount: V.count, keepFace: keepFace, rings: erodeRings)
            keepFace = removeSmallComponents(idx: idx, keepFace: keepFace, minFaces: minComponentFaces)
        }
        onProgress?(90)

        // Yangi mesh yig'ish (ishlatilgan vertekslarni qayta indekslash)
        return rebuild(mesh, keepFace: keepFace)
    }

    /// FREE-SPACE CARVING (CHISEL/ReFusion, depth-map post-hoc versiyasi) — HAVODA OSILGAN
    /// yuzlarni o'chiradi. Har yuz markazini har kadrga proyeksiya qilamiz; agar o'lchangan
    /// LiDAR chuqurligi yuznikidan SEZILARLI UZOQ bo'lsa (kamera yuz ORTIDAGI bo'shliqni
    /// ko'radi) → bu "free-space violation" (yuz bo'sh joyda osilgan). Ko'p kamera shunday
    /// ko'rsa VA hech biri yuzni sirtда o'lchamasa → o'chiriladi.
    static func freeSpaceCull(
        _ mesh: WeldedMesh,
        keyframes: [KeyframeStore.Keyframe],
        freeMargin: Float = 0.12,     // o'lchangan chuqurlik yuzdan shuncha uzoq bo'lsa = violation
        supportTol: Float = 0.06,     // |d_meas - d_face| shundan kichik = sirtda (support)
        minViolations: Int = 2,
        onProgress: ((Int) -> Void)? = nil
    ) -> WeldedMesh {
        let V = mesh.positions, idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 100, keyframes.count >= 2 else { return mesh }

        struct Cam {
            let invT: simd_float4x4; let fx, fy, cx, cy, w, h: Float
            let depth: [Float32]?; let dw, dh: Int
        }
        let cams: [Cam] = keyframes.compactMap { kf in
            guard let d = kf.depthMap, kf.depthWidth > 0, kf.depthHeight > 0, !d.isEmpty else { return nil }
            let k = kf.intrinsics
            return Cam(invT: kf.transform.inverse, fx: k[0][0], fy: k[1][1], cx: k[2][0], cy: k[2][1],
                       w: Float(kf.width), h: Float(kf.height), depth: d, dw: kf.depthWidth, dh: kf.depthHeight)
        }
        guard cams.count >= 2 else { return mesh }

        var keepFace = [Bool](repeating: true, count: faceCount)
        let viol = UnsafeMutablePointer<Int32>.allocate(capacity: faceCount)
        let supp = UnsafeMutablePointer<Int32>.allocate(capacity: faceCount)
        viol.initialize(repeating: 0, count: faceCount); supp.initialize(repeating: 0, count: faceCount)
        defer { viol.deallocate(); supp.deallocate() }

        DispatchQueue.concurrentPerform(iterations: faceCount) { f in
            let a = V[Int(idx[f*3])], b = V[Int(idx[f*3+1])], c = V[Int(idx[f*3+2])]
            let cen = (a + b + c) / 3
            var vCount: Int32 = 0, sCount: Int32 = 0
            for cam in cams {
                let pc = cam.invT * SIMD4<Float>(cen.x, cen.y, cen.z, 1)
                let dFace = -pc.z
                if dFace <= 0.15 || dFace > 5.0 { continue }
                let u = cam.fx * pc.x / dFace + cam.cx
                let v = cam.cy - cam.fy * pc.y / dFace
                if u < 0 || u >= cam.w || v < 0 || v >= cam.h { continue }
                let du = min(max(Int(u / cam.w * Float(cam.dw)), 0), cam.dw - 1)
                let dv = min(max(Int(v / cam.h * Float(cam.dh)), 0), cam.dh - 1)
                let dMeas = cam.depth![dv * cam.dw + du]
                if dMeas <= 0.05 { continue }   // yaroqsiz o'lchov
                if dMeas > dFace + freeMargin {
                    vCount += 1                 // kamera yuz ORTINI ko'rdi → free-space violation
                } else if abs(dMeas - dFace) < supportTol {
                    sCount += 1                 // yuz sirtda o'lchandi → support
                }
            }
            viol[f] = vCount; supp[f] = sCount
        }
        onProgress?(50)

        for f in 0..<faceCount {
            // ko'p kamera ORTINI ko'rgan VA hech biri sirtда o'lchamagan → osilgan → o'chir
            if Int(viol[f]) >= minViolations && supp[f] == 0 { keepFace[f] = false }
        }
        // o'chirishdan keyin kichik uzilgan bo'laklarni ham tozalash
        keepFace = removeSmallComponents(idx: idx, keepFace: keepFace, minFaces: 150)
        onProgress?(90)
        return rebuild(mesh, keepFace: keepFace)
    }

    /// CHO'ZILGAN FLAP tozalash — zich mesh'да normal Hoppe uchburchaklari ~2-4 sm; chegaradagi
    /// "flap"lar cho'zilgan (uzun qirrali, 10+ sm) va ingichka. Uzun qirrali yuzlarni o'chiradi
    /// (shift/junction'dagi ragged flaplar). Zich mesh'да xavfsiz (katta yuz = flap).
    static func removeStretchedFaces(_ mesh: WeldedMesh, maxEdge: Float = 0.10) -> WeldedMesh {
        let V = mesh.positions, idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 500 else { return mesh }
        let me2 = maxEdge * maxEdge
        var keepFace = [Bool](repeating: true, count: faceCount)
        for f in 0..<faceCount {
            let a = V[Int(idx[f*3])], b = V[Int(idx[f*3+1])], c = V[Int(idx[f*3+2])]
            let e0 = simd_length_squared(b - a)
            let e1 = simd_length_squared(c - b)
            let e2 = simd_length_squared(a - c)
            if max(e0, max(e1, e2)) > me2 { keepFace[f] = false }
        }
        keepFace = removeSmallComponents(idx: idx, keepFace: keepFace, minFaces: 150)
        return rebuild(mesh, keepFace: keepFace)
    }

    /// CHEGARA TIKAN/FLAP tozalash — chiqib turgan "tent-pole" spike va ingichka flaplarni
    /// o'chiradi. Bunday yuzda ≥2 OCHIQ qirra (faqat 1 yuz ishlatgan) bo'ladi (barmoqsimon
    /// chiqib turgan), yoki juda ingichka (needle, min burchak < 8°) VA chegarada. Bir necha
    /// marta takrorlanadi (spike zanjiri). Ichki teshik ochmaydi — faqat chegarani tozalaydi.
    static func removeBoundarySpikes(_ mesh: WeldedMesh, iterations: Int = 3) -> WeldedMesh {
        var keep = [Bool](repeating: true, count: mesh.indices.count / 3)
        let V = mesh.positions, idx = mesh.indices
        func ekey(_ a: UInt32, _ b: UInt32) -> UInt64 { let lo = min(a,b), hi = max(a,b); return (UInt64(lo) << 32) | UInt64(hi) }
        for _ in 0..<iterations {
            var edgeCount = [UInt64: Int](minimumCapacity: idx.count)
            for f in 0..<(idx.count/3) where keep[f] {
                let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
                edgeCount[ekey(a,b), default: 0] += 1
                edgeCount[ekey(b,c), default: 0] += 1
                edgeCount[ekey(c,a), default: 0] += 1
            }
            var removed = 0
            for f in 0..<(idx.count/3) where keep[f] {
                let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
                let e0 = edgeCount[ekey(a,b)] ?? 0, e1 = edgeCount[ekey(b,c)] ?? 0, e2 = edgeCount[ekey(c,a)] ?? 0
                let openEdges = (e0 == 1 ? 1 : 0) + (e1 == 1 ? 1 : 0) + (e2 == 1 ? 1 : 0)
                if openEdges >= 2 { keep[f] = false; removed += 1; continue }   // chiqib turgan spike/flap
                // chegarada (≥1 ochiq qirra) VA needle (juda ingichka) bo'lsa
                if openEdges == 1 {
                    let pa = V[Int(a)], pb = V[Int(b)], pc = V[Int(c)]
                    let minAngle = triMinAngle(pa, pb, pc)
                    if minAngle < 8.0 { keep[f] = false; removed += 1 }
                }
            }
            if removed == 0 { break }
        }
        keep = removeSmallComponents(idx: idx, keepFace: keep, minFaces: 100)
        return rebuild(mesh, keepFace: keep)
    }

    /// CHEGARA SILLIQLASH — ochiq chegara (siluet + teshik chetlari) vertekslarini halqa
    /// bo'ylab Laplacian silliqlaydi → "burchak-burchak" (sawtooth) qirralarni TEKIS egri qiladi.
    /// Faqat chegara vertekslari halqa qo'shnilari o'rtachasiga tortiladi (tangensial); ichki
    /// struktura tegilmaydi. Bir necha marta takrorlanadi.
    static func smoothBoundary(_ mesh: WeldedMesh, iterations: Int = 8, alpha: Float = 0.5) -> WeldedMesh {
        let idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 200 else { return mesh }
        func ekey(_ a: UInt32, _ b: UInt32) -> UInt64 { let lo = min(a,b), hi = max(a,b); return (UInt64(lo) << 32) | UInt64(hi) }
        var edgeCount = [UInt64: Int](minimumCapacity: idx.count)
        for f in 0..<faceCount {
            let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
            edgeCount[ekey(a,b), default: 0] += 1
            edgeCount[ekey(b,c), default: 0] += 1
            edgeCount[ekey(c,a), default: 0] += 1
        }
        // chegara qo'shnilik (faqat ochiq qirralar bo'ylab)
        var bnbr = [Int: [Int]](minimumCapacity: 1024)
        for (e, cnt) in edgeCount where cnt == 1 {
            let a = Int(e >> 32), b = Int(e & 0xFFFFFFFF)
            bnbr[a, default: []].append(b)
            bnbr[b, default: []].append(a)
        }
        guard !bnbr.isEmpty else { return mesh }
        var pos = mesh.positions
        // faqat MANIFOLD chegara vertekslari (aynan 2 chegara qo'shnisi) silliqlanadi —
        // tarmoqlangan (non-manifold) chegara qo'zg'almaydi (buzilmasin).
        let smooth = bnbr.filter { $0.value.count == 2 }
        for _ in 0..<iterations {
            var upd = [Int: SIMD3<Float>](minimumCapacity: smooth.count)
            for (v, ns) in smooth {
                let mid = (pos[ns[0]] + pos[ns[1]]) * 0.5
                upd[v] = pos[v] * (1 - alpha) + mid * alpha
            }
            for (v, p) in upd { pos[v] = p }
        }
        NSLog("MeshTrimmer.smoothBoundary: %d chegara verteks silliqlandi", smooth.count)
        return WeldedMesh(positions: pos, normals: [], indices: idx)
    }

    /// CHEGARA FLAP-SHAVER — chegaradagi INGICHKA/MAYDA "flap" (ragged fringe) uchburchaklarni
    /// iterativ o'chiradi (teksturalashda QORA chiqadigan chetlar). removeBoundarySpikes'dan
    /// kuchliroq: ≥1 ochiq qirrali VA (minAngle < angleThresh YOKI area < areaThresh) yuz.
    /// Toza chegara (deyarli teng-tomonli, katta yuz) SAQLANADI → o'z-o'zini cheklaydi.
    /// Oxirida kichik AJRALGAN komponentlarni (floating fragment) o'chiradi.
    static func shaveBoundaryFlaps(_ mesh: WeldedMesh,
                                   iterations: Int = 4,
                                   angleThresh: Float = 25,
                                   minComponentFaces: Int = 200) -> WeldedMesh {
        let V = mesh.positions, idx = mesh.indices
        let faceCount = idx.count / 3
        guard faceCount > 500 else { return mesh }
        var keep = [Bool](repeating: true, count: faceCount)
        func ekey(_ a: UInt32, _ b: UInt32) -> UInt64 { let lo = min(a,b), hi = max(a,b); return (UInt64(lo) << 32) | UInt64(hi) }
        func triArea(_ f: Int) -> Float {
            let a = V[Int(idx[f*3])], b = V[Int(idx[f*3+1])], c = V[Int(idx[f*3+2])]
            return 0.5 * simd_length(simd_cross(b - a, c - a))
        }
        // median yuza (boshlang'ich) — mayda sliver chegarasi
        var areas = [Float](); areas.reserveCapacity(faceCount)
        for f in 0..<faceCount { areas.append(triArea(f)) }
        let sorted = areas.sorted()
        let medianArea = sorted.isEmpty ? 0 : sorted[sorted.count/2]
        let areaThresh = 0.3 * medianArea

        for _ in 0..<iterations {
            var edgeCount = [UInt64: Int](minimumCapacity: idx.count)
            for f in 0..<faceCount where keep[f] {
                let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
                edgeCount[ekey(a,b), default: 0] += 1
                edgeCount[ekey(b,c), default: 0] += 1
                edgeCount[ekey(c,a), default: 0] += 1
            }
            var removed = 0
            for f in 0..<faceCount where keep[f] {
                let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
                let e0 = edgeCount[ekey(a,b)] ?? 0, e1 = edgeCount[ekey(b,c)] ?? 0, e2 = edgeCount[ekey(c,a)] ?? 0
                let openEdges = (e0 == 1 ? 1 : 0) + (e1 == 1 ? 1 : 0) + (e2 == 1 ? 1 : 0)
                if openEdges == 0 { continue }
                if openEdges >= 2 { keep[f] = false; removed += 1; continue }
                let pa = V[Int(a)], pb = V[Int(b)], pc = V[Int(c)]
                if triMinAngle(pa, pb, pc) < angleThresh || triArea(f) < areaThresh {
                    keep[f] = false; removed += 1
                }
            }
            if removed == 0 { break }
        }
        keep = removeSmallComponents(idx: idx, keepFace: keep, minFaces: minComponentFaces)
        return rebuild(mesh, keepFace: keep)
    }

    /// Uchburchakning eng kichik burchagi (gradus).
    private static func triMinAngle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float {
        func ang(_ p: SIMD3<Float>, _ q: SIMD3<Float>, _ r: SIMD3<Float>) -> Float {
            let u = simd_normalize(q - p), v = simd_normalize(r - p)
            return acos(max(-1, min(1, simd_dot(u, v)))) * 180 / .pi
        }
        return min(ang(a,b,c), min(ang(b,a,c), ang(c,a,b)))
    }

    // MARK: - Kichik komponentlarni o'chirish

    private static func removeSmallComponents(idx: [UInt32], keepFace: [Bool], minFaces: Int) -> [Bool] {
        let faceCount = idx.count / 3
        // Qirra -> yuzlar
        var edgeMap: [UInt64: [Int]] = [:]
        edgeMap.reserveCapacity(faceCount * 3)
        func key(_ a: UInt32, _ b: UInt32) -> UInt64 {
            let lo = min(a, b), hi = max(a, b)
            return (UInt64(lo) << 32) | UInt64(hi)
        }
        for f in 0..<faceCount where keepFace[f] {
            let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
            edgeMap[key(a, b), default: []].append(f)
            edgeMap[key(b, c), default: []].append(f)
            edgeMap[key(c, a), default: []].append(f)
        }
        // Union-find
        var parent = Array(0..<faceCount)
        func find(_ x: Int) -> Int { var r = x; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        func union(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[ra] = rb } }
        for (_, faces) in edgeMap where faces.count >= 2 {
            for i in 1..<faces.count { union(faces[0], faces[i]) }
        }
        var compSize: [Int: Int] = [:]
        for f in 0..<faceCount where keepFace[f] { compSize[find(f), default: 0] += 1 }
        var result = keepFace
        for f in 0..<faceCount where keepFace[f] {
            if (compSize[find(f)] ?? 0) < minFaces { result[f] = false }
        }
        return result
    }

    // MARK: - Chegara eroziyasi

    private static func erodeBoundary(idx: [UInt32], vertexCount: Int, keepFace: [Bool], rings: Int) -> [Bool] {
        let faceCount = idx.count / 3
        var keep = keepFace
        func key(_ a: UInt32, _ b: UInt32) -> UInt64 {
            let lo = min(a, b), hi = max(a, b); return (UInt64(lo) << 32) | UInt64(hi)
        }
        for _ in 0..<rings {
            // Chegara qirralari = faqat 1 (tirik) yuz ishlatgan qirra
            var edgeCount: [UInt64: Int] = [:]
            edgeCount.reserveCapacity(faceCount * 3)
            for f in 0..<faceCount where keep[f] {
                let a = idx[f*3], b = idx[f*3+1], c = idx[f*3+2]
                edgeCount[key(a, b), default: 0] += 1
                edgeCount[key(b, c), default: 0] += 1
                edgeCount[key(c, a), default: 0] += 1
            }
            var boundaryV = [Bool](repeating: false, count: vertexCount)
            for (e, cnt) in edgeCount where cnt == 1 {
                boundaryV[Int(e >> 32)] = true
                boundaryV[Int(e & 0xFFFFFFFF)] = true
            }
            for f in 0..<faceCount where keep[f] {
                if boundaryV[Int(idx[f*3])] || boundaryV[Int(idx[f*3+1])] || boundaryV[Int(idx[f*3+2])] {
                    keep[f] = false
                }
            }
        }
        return keep
    }

    // MARK: - Qayta yig'ish

    private static func rebuild(_ mesh: WeldedMesh, keepFace: [Bool]) -> WeldedMesh {
        let oldV = mesh.positions, oldN = mesh.normals, oldIdx = mesh.indices
        var remap = [Int32](repeating: -1, count: oldV.count)
        var newPos: [SIMD3<Float>] = []
        var newNrm: [SIMD3<Float>] = []
        var newIdx: [UInt32] = []
        newPos.reserveCapacity(oldV.count)
        for f in 0..<(oldIdx.count / 3) where keepFace[f] {
            for j in 0..<3 {
                let vi = Int(oldIdx[f*3 + j])
                if remap[vi] < 0 {
                    remap[vi] = Int32(newPos.count)
                    newPos.append(oldV[vi])
                    if vi < oldN.count { newNrm.append(oldN[vi]) }
                }
                newIdx.append(UInt32(remap[vi]))
            }
        }
        if newPos.isEmpty { return mesh }
        return WeldedMesh(positions: newPos, normals: newNrm.count == newPos.count ? newNrm : [], indices: newIdx)
    }
}
