import Foundation
import UIKit
import CoreGraphics
import simd

/// Yakuniy natija: yagona mesh + yagona tekstura atlasi.
struct AtlasModel {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    /// 0..1, bottom-left origin (OBJ/RealityKit konvensiyasi), har vertexga
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
    let atlasImage: CGImage
    let atlasWidth: Int
    let atlasHeight: Int
}

/// Scaniverse-parity pipeline (quick-win bosqichi):
/// chunk'lar payvandlanadi → xatlas yagona UV → har FACE'ga BITTA eng yaxshi
/// kadr (blending yo'q — o'tkirlik saqlanadi) → yagona atlasga bake →
/// dilatatsiya + pull-push teshik to'ldirish.
enum GlobalTextureBaker {

    static func bake(
        geometries: [Int64: ChunkGeometry],
        keyframes: [KeyframeStore.Keyframe],
        overrideMesh: WeldedMesh? = nil,
        resolution: Int = 4096,
        onProgress: ((String, Int) -> Void)? = nil
    ) -> AtlasModel? {
        guard !geometries.isEmpty, !keyframes.isEmpty else { return nil }

        // 1) Geometriya manbai: NSDK zich TSDF mesh (chunk'lar payvandlanadi) —
        // Ghidra dekompilyatsiyasi Scaniverse ham TSDF fusion ishlatishini
        // ko'rsatdi (Poisson emas). Override berilsa (masalan implicit mesh) undan.
        onProgress?("Mesh birlashtirilmoqda", 4)
        let rawMesh: WeldedMesh
        if let overrideMesh, overrideMesh.indices.count >= 3 {
            rawMesh = overrideMesh
        } else {
            rawMesh = MeshWelder.weld(geometries)
        }
        guard rawMesh.indices.count >= 3 else { return nil }

        // 1b) Tozalash: yengil silliqlash + decimation
        onProgress?("Mesh tozalanmoqda", 8)
        let welded = MeshPostProcess.cleanup(rawMesh, targetTriangles: 150_000)
        guard welded.indices.count >= 3 else { return nil }

        // 2) xatlas — yagona UV unwrap
        onProgress?("UV atlas qurilmoqda", 15)
        var flatPositions = [Float](repeating: 0, count: welded.positions.count * 3)
        for (i, p) in welded.positions.enumerated() {
            flatPositions[i * 3] = p.x
            flatPositions[i * 3 + 1] = p.y
            flatPositions[i * 3 + 2] = p.z
        }
        guard let xr = NSDKXAtlasBridge.generate(
            withPositions: flatPositions,
            vertexCount: UInt32(welded.positions.count),
            indices: welded.indices,
            indexCount: UInt32(welded.indices.count),
            resolution: UInt32(resolution)
        ) else {
            print("[GlobalTextureBaker] xatlas failed")
            return nil
        }

        let atlasW = Int(xr.width), atlasH = Int(xr.height)
        let newVertexCount = Int(xr.vertexCount)

        // xatlas natijasini massivlarga ochamiz
        var positions = [SIMD3<Float>](repeating: .zero, count: newVertexCount)
        var normals = [SIMD3<Float>](repeating: .zero, count: newVertexCount)
        var uvTexels = [SIMD2<Float>](repeating: .zero, count: newVertexCount)
        var origIds = [UInt32](repeating: 0, count: newVertexCount)
        xr.uvs.withUnsafeBytes { raw in
            let uvPtr = raw.bindMemory(to: Float.self)
            xr.xrefs.withUnsafeBytes { rawX in
                let xrefPtr = rawX.bindMemory(to: UInt32.self)
                for i in 0..<newVertexCount {
                    let src = Int(xrefPtr[i])
                    origIds[i] = xrefPtr[i]
                    positions[i] = welded.positions[src]
                    normals[i] = welded.normals[src]
                    uvTexels[i] = SIMD2<Float>(uvPtr[i * 2], uvPtr[i * 2 + 1])
                }
            }
        }
        var indices = [UInt32](repeating: 0, count: Int(xr.indexCount))
        xr.indices.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt32.self)
            for i in 0..<indices.count { indices[i] = ptr[i] }
        }

        // 3) Har face uchun eng yaxshi kadr (greedy, blending yo'q)
        onProgress?("Kadrlar tanlanmoqda", 25)
        let faceCount = indices.count / 3
        let maxSharpness = max(keyframes.map(\.sharpness).max() ?? 1, 1e-6)
        var faceLabels = [Int32](repeating: -1, count: faceCount)
        var faceCandidates = [[(label: Int32, score: Float)]](repeating: [], count: faceCount)

        // Ko'p-yadroli view-selection (embarrassingly parallel: har face mustaqil).
        // Arraylarni buffer pointer orqali yozamiz — bu concurrentPerform'da xavfsiz.
        faceLabels.withUnsafeMutableBufferPointer { labelBuf in
            faceCandidates.withUnsafeMutableBufferPointer { candBuf in
                DispatchQueue.concurrentPerform(iterations: faceCount) { f in
                    let ia = Int(indices[f * 3]), ib = Int(indices[f * 3 + 1]), ic = Int(indices[f * 3 + 2])
                    let pa = positions[ia], pb = positions[ib], pc = positions[ic]
                    let centroid = (pa + pb + pc) / 3
                    let cross = simd_cross(pb - pa, pc - pa)
                    let crossLen = simd_length(cross)
                    guard crossLen > 1e-10 else { return }
                    let faceNormal = cross / crossLen

                    var cands: [(label: Int32, score: Float)] = []
                    for (k, kf) in keyframes.enumerated() {
                        guard let (uv, depth) = projectPixel(point: centroid, keyframe: kf) else { continue }
                        if kf.isOccluded(u: uv.x, v: uv.y, expectedDepth: depth) { continue }
                        guard projectPixel(point: pa, keyframe: kf) != nil,
                              projectPixel(point: pb, keyframe: kf) != nil,
                              projectPixel(point: pc, keyframe: kf) != nil else { continue }

                        let toCam = kf.position - centroid
                        let dist = simd_length(toCam)
                        guard dist > 1e-4 else { continue }
                        let facing = abs(simd_dot(faceNormal, toCam / dist))
                        guard facing > 0.12 else { continue }

                        let sharpW = 0.25 + 0.75 * (kf.sharpness / maxSharpness)
                        let score = facing * sharpW / (0.3 + dist * dist)
                        if score > 0.05 {
                            cands.append((Int32(k), score))
                        }
                    }
                    cands.sort { $0.score > $1.score }
                    if cands.count > 6 { cands.removeLast(cands.count - 6) }
                    candBuf[f] = cands
                    labelBuf[f] = cands.first?.label ?? -1
                }
            }
        }

        // 3b) Qo'shnilik grafigi (payvandlangan vertex idlari orqali —
        // xatlas chart chegaralari ham qo'shni hisoblanadi)
        onProgress?("Choklar silliqlanmoqda", 30)
        var adjacency = [[Int32]](repeating: [], count: faceCount)
        var edgeToFace: [UInt64: Int32] = [:]
        edgeToFace.reserveCapacity(faceCount * 2)
        for f in 0..<faceCount {
            let a = origIds[Int(indices[f * 3])]
            let b = origIds[Int(indices[f * 3 + 1])]
            let c = origIds[Int(indices[f * 3 + 2])]
            for (v0, v1) in [(a, b), (b, c), (c, a)] {
                let key = (UInt64(min(v0, v1)) << 32) | UInt64(max(v0, v1))
                if let other = edgeToFace[key] {
                    if other != Int32(f) {
                        adjacency[Int(other)].append(Int32(f))
                        adjacency[f].append(other)
                    }
                } else {
                    edgeToFace[key] = Int32(f)
                }
            }
        }

        // 3c) ICM label-silliqlash: data cost + Potts — "konfetti" labellarni
        // yaxlit hududlarga birlashtiradi
        let lambda: Float = 0.35
        for _ in 0..<3 {
            var changed = 0
            for f in 0..<faceCount {
                let cands = faceCandidates[f]
                guard cands.count > 1, let best = cands.first else { continue }
                var bestCost = Float.greatestFiniteMagnitude
                var bestLabel = faceLabels[f]
                for (label, score) in cands {
                    let dataCost = 1 - score / best.score
                    var disagree = 0
                    for n in adjacency[f] {
                        let nl = faceLabels[Int(n)]
                        if nl >= 0 && nl != label { disagree += 1 }
                    }
                    let cost = dataCost + lambda * Float(disagree)
                    if cost < bestCost {
                        bestCost = cost
                        bestLabel = label
                    }
                }
                if bestLabel != faceLabels[f] {
                    faceLabels[f] = bestLabel
                    changed += 1
                }
            }
            if changed == 0 { break }
        }

        // 4) Rang gain'lari (kadrlar orasidagi ekspozitsiya/WB tekislash)
        onProgress?("Ranglar tekislanmoqda", 35)
        let assignments = TexturedOBJExporter.assignKeyframes(
            geometries: geometries, keyframes: keyframes
        )
        let gains = ColorHarmonizer.computeGains(
            geometries: geometries, keyframes: keyframes, assignments: assignments
        )

        // 4b) Chok-vertex rang yechimi (Waechter uslubidagi additiv global
        // tuzatish): chokning ikki tomonidagi ranglar bir nuqtaga tortiladi
        onProgress?("Chok ranglari yechilmoqda", 38)
        let corrections = solveSeamCorrections(
            faceCount: faceCount, indices: indices, origIds: origIds,
            positions: positions, labels: faceLabels,
            keyframes: keyframes, gains: gains
        )

        // UV: texel (v yuqoridan) → normalizatsiya + bottom-left origin
        var uvs = [SIMD2<Float>](repeating: .zero, count: newVertexCount)
        for i in 0..<newVertexCount {
            uvs[i] = SIMD2<Float>(
                uvTexels[i].x / Float(atlasW),
                1 - uvTexels[i].y / Float(atlasH)
            )
        }

        // 5) Bake — avval Metal GPU (tez, 8K), muvaffaqiyatsizlikda CPU
        var pixels: [UInt8]
        var filled: [Bool]

        onProgress?("Teksturalar pishirilmoqda (GPU)", 55)
        if let gpu = MetalTextureBaker.bake(
            positions: positions, atlasUVs: uvs, indices: indices,
            faceLabels: faceLabels, corrections: corrections,
            keyframes: keyframes, gains: gains,
            width: atlasW, height: atlasH
        ) {
            pixels = gpu.pixels
            filled = gpu.filled
        } else {
            // CPU fallback: label bo'yicha guruhlab rasterizatsiya
            pixels = [UInt8](repeating: 0, count: atlasW * atlasH * 4)
            filled = [Bool](repeating: false, count: atlasW * atlasH)
            var facesByLabel: [Int32: [Int]] = [:]
            for f in 0..<faceCount where faceLabels[f] >= 0 {
                facesByLabel[faceLabels[f], default: []].append(f)
            }
            let labelsSorted = facesByLabel.keys.sorted()
            for (li, label) in labelsSorted.enumerated() {
                onProgress?("Teksturalar pishirilmoqda (CPU)", 55 + Int(Float(li) / Float(max(labelsSorted.count, 1)) * 30))
                let kf = keyframes[Int(label)]
                guard let bitmap = makeBitmap(kf, targetWidth: 1440) else { continue }
                let g = gains[Int(label)] ?? ColorGains()
                let gain = SIMD3<Float>(g.r, g.g, g.b)
                for f in facesByLabel[label] ?? [] {
                    rasterizeFace(
                        f, indices: indices, positions: positions, uvTexels: uvTexels,
                        keyframe: kf, bitmap: bitmap, gain: gain,
                        corr0: corrections[f * 3],
                        corr1: corrections[f * 3 + 1],
                        corr2: corrections[f * 3 + 2],
                        atlasW: atlasW, atlasH: atlasH,
                        pixels: &pixels, filled: &filled
                    )
                }
            }
        }

        // 6) Teshik to'ldirish: dilatatsiya + pull-push
        onProgress?("Teshiklar to'ldirilmoqda", 90)
        dilate(&pixels, &filled, w: atlasW, h: atlasH, passes: 1)
        pullPushFill(&pixels, filled: filled, w: atlasW, h: atlasH)

        guard let image = makeCGImage(pixels: pixels, w: atlasW, h: atlasH) else { return nil }

        onProgress?("Tayyor", 100)
        return AtlasModel(
            positions: positions, normals: normals, uvs: uvs, indices: indices,
            atlasImage: image, atlasWidth: atlasW, atlasHeight: atlasH
        )
    }

    // MARK: - Seam color solve (Waechter global adjustment, additiv)

    /// Har (vertex, label) juftligi uchun additiv rang tuzatish g ni yechadi:
    /// chok vertexlarida ikki label tomoni bir rangga kelishi, patch ichida esa
    /// tuzatish silliq o'zgarishi talab qilinadi. Gauss-Seidel bilan yechiladi.
    /// Natija: har face har corner uchun tuzatish (faceCount*3).
    private static func solveSeamCorrections(
        faceCount: Int, indices: [UInt32], origIds: [UInt32],
        positions: [SIMD3<Float>], labels: [Int32],
        keyframes: [KeyframeStore.Keyframe], gains: [Int: ColorGains]
    ) -> [SIMD3<Float>] {
        var corrections = [SIMD3<Float>](repeating: .zero, count: faceCount * 3)

        struct VL: Hashable {
            let v: UInt32
            let l: Int32
        }

        // 1) Noma'lumlar: har face cornerdagi (origVertex, label)
        var unknownIndex: [VL: Int] = [:]
        var unknownPosition: [SIMD3<Float>] = []
        var unknownsByLabel: [Int32: [Int]] = [:]
        var unknownVL: [VL] = []
        for f in 0..<faceCount where labels[f] >= 0 {
            let label = labels[f]
            for c in 0..<3 {
                let vi = Int(indices[f * 3 + c])
                let key = VL(v: origIds[vi], l: label)
                if unknownIndex[key] == nil {
                    let idx = unknownPosition.count
                    unknownIndex[key] = idx
                    unknownPosition.append(positions[vi])
                    unknownVL.append(key)
                    unknownsByLabel[label, default: []].append(idx)
                }
            }
        }
        let unknownCount = unknownPosition.count
        guard unknownCount > 0 else { return corrections }

        // 2) f_{v,l}: vertexning o'z labelidagi rangi (512px bitmap yetarli)
        var sampled = [SIMD3<Float>?](repeating: nil, count: unknownCount)
        for (label, idxList) in unknownsByLabel {
            let kf = keyframes[Int(label)]
            guard let bitmap = makeBitmap(kf, targetWidth: 512) else { continue }
            let g = gains[Int(label)] ?? ColorGains()
            let gain = SIMD3<Float>(g.r, g.g, g.b)
            for idx in idxList {
                let p = unknownPosition[idx]
                guard let (uv, depth) = projectPixel(point: p, keyframe: kf) else { continue }
                if kf.isOccluded(u: uv.x, v: uv.y, expectedDepth: depth) { continue }
                let sx = uv.x / Float(kf.width) * Float(bitmap.width)
                let sy = uv.y / Float(kf.height) * Float(bitmap.height)
                if let color = bilinearSample(bitmap, x: sx, y: sy) {
                    sampled[idx] = simd_clamp(color * gain, .zero, SIMD3<Float>(repeating: 1))
                }
            }
        }

        // 3) Cheklovlar
        // Seam: bitta vertexda turli labellar — ranglar tenglashsin
        var vertexToUnknowns: [UInt32: [Int]] = [:]
        for (idx, vl) in unknownVL.enumerated() {
            vertexToUnknowns[vl.v, default: []].append(idx)
        }
        var seamAdj = [[Int]](repeating: [], count: unknownCount)
        for (_, idxs) in vertexToUnknowns where idxs.count > 1 {
            for i in 0..<idxs.count {
                for j in (i + 1)..<idxs.count {
                    let a = idxs[i], b = idxs[j]
                    guard sampled[a] != nil, sampled[b] != nil else { continue }
                    seamAdj[a].append(b)
                    seamAdj[b].append(a)
                }
            }
        }

        // Smooth: mesh qirrasi bo'ylab bir xil label ichida g silliq o'zgarsin
        var smoothAdj = [[Int]](repeating: [], count: unknownCount)
        var seenEdges = Set<UInt64>()
        for f in 0..<faceCount where labels[f] >= 0 {
            let label = labels[f]
            let a = origIds[Int(indices[f * 3])]
            let b = origIds[Int(indices[f * 3 + 1])]
            let c = origIds[Int(indices[f * 3 + 2])]
            for (v0, v1) in [(a, b), (b, c), (c, a)] {
                guard let i0 = unknownIndex[VL(v: v0, l: label)],
                      let i1 = unknownIndex[VL(v: v1, l: label)] else { continue }
                let lo = UInt64(min(i0, i1)), hi = UInt64(max(i0, i1))
                let key = lo << 32 | hi
                if seenEdges.insert(key).inserted {
                    smoothAdj[i0].append(i1)
                    smoothAdj[i1].append(i0)
                }
            }
        }

        // 4) Gauss-Seidel
        let wSeam: Float = 2.0
        let wSmooth: Float = 0.6
        let wPrior: Float = 0.05
        var g = [SIMD3<Float>](repeating: .zero, count: unknownCount)

        for _ in 0..<50 {
            for i in 0..<unknownCount {
                var num = SIMD3<Float>.zero
                var den: Float = wPrior  // prior g → 0
                if let fi = sampled[i] {
                    for j in seamAdj[i] {
                        guard let fj = sampled[j] else { continue }
                        num += wSeam * (fj + g[j] - fi)
                        den += wSeam
                    }
                }
                for j in smoothAdj[i] {
                    num += wSmooth * g[j]
                    den += wSmooth
                }
                g[i] = num / den
            }
        }
        for i in 0..<unknownCount {
            g[i] = simd_clamp(g[i], SIMD3<Float>(repeating: -0.4), SIMD3<Float>(repeating: 0.4))
        }

        // 5) Face cornerlarga tarqatish
        for f in 0..<faceCount where labels[f] >= 0 {
            let label = labels[f]
            for c in 0..<3 {
                let key = VL(v: origIds[Int(indices[f * 3 + c])], l: label)
                if let idx = unknownIndex[key] {
                    corrections[f * 3 + c] = g[idx]
                }
            }
        }
        return corrections
    }

    // MARK: - Rasterization

    private static func rasterizeFace(
        _ f: Int,
        indices: [UInt32], positions: [SIMD3<Float>], uvTexels: [SIMD2<Float>],
        keyframe kf: KeyframeStore.Keyframe, bitmap: Bitmap, gain: SIMD3<Float>,
        corr0: SIMD3<Float>, corr1: SIMD3<Float>, corr2: SIMD3<Float>,
        atlasW: Int, atlasH: Int,
        pixels: inout [UInt8], filled: inout [Bool]
    ) {
        let ia = Int(indices[f * 3]), ib = Int(indices[f * 3 + 1]), ic = Int(indices[f * 3 + 2])
        let a = uvTexels[ia], b = uvTexels[ib], c = uvTexels[ic]
        let pa = positions[ia], pb = positions[ib], pc = positions[ic]

        let denom = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        guard abs(denom) > 1e-9 else { return }

        let minX = max(0, Int(min(a.x, b.x, c.x).rounded(.down)) - 1)
        let maxX = min(atlasW - 1, Int(max(a.x, b.x, c.x).rounded(.up)) + 1)
        let minY = max(0, Int(min(a.y, b.y, c.y).rounded(.down)) - 1)
        let maxY = min(atlasH - 1, Int(max(a.y, b.y, c.y).rounded(.up)) + 1)
        guard minX <= maxX, minY <= maxY else { return }

        for py in minY...maxY {
            for px in minX...maxX {
                let fx = Float(px) + 0.5, fy = Float(py) + 0.5
                let w0 = ((b.y - c.y) * (fx - c.x) + (c.x - b.x) * (fy - c.y)) / denom
                let w1 = ((c.y - a.y) * (fx - c.x) + (a.x - c.x) * (fy - c.y)) / denom
                let w2 = 1 - w0 - w1
                guard w0 >= -0.02, w1 >= -0.02, w2 >= -0.02 else { continue }

                let world = w0 * pa + w1 * pb + w2 * pc
                guard let (uv, depth) = projectPixel(point: world, keyframe: kf) else { continue }
                if kf.isOccluded(u: uv.x, v: uv.y, expectedDepth: depth) { continue }

                let sx = uv.x / Float(kf.width) * Float(bitmap.width)
                let sy = uv.y / Float(kf.height) * Float(bitmap.height)
                guard var color = bilinearSample(bitmap, x: sx, y: sy) else { continue }
                let correction = w0 * corr0 + w1 * corr1 + w2 * corr2
                color = simd_clamp(color * gain + correction, .zero, SIMD3<Float>(repeating: 1))

                let idx = py * atlasW + px
                let offset = idx * 4
                pixels[offset] = UInt8(color.x * 255)
                pixels[offset + 1] = UInt8(color.y * 255)
                pixels[offset + 2] = UInt8(color.z * 255)
                pixels[offset + 3] = 255
                filled[idx] = true
            }
        }
    }

    // MARK: - Coverage test

    /// Face uchala vertexi kadr ichida ko'rinadimi va occlusion'dan o'tadimi.
    private static func faceCoveredBy(
        _ f: Int, keyframe kf: KeyframeStore.Keyframe,
        indices: [UInt32], positions: [SIMD3<Float>]
    ) -> Bool {
        let ia = Int(indices[f * 3]), ib = Int(indices[f * 3 + 1]), ic = Int(indices[f * 3 + 2])
        let pa = positions[ia], pb = positions[ib], pc = positions[ic]
        let centroid = (pa + pb + pc) / 3
        for p in [pa, pb, pc, centroid] {
            guard let (uv, depth) = projectPixel(point: p, keyframe: kf) else { return false }
            if kf.isOccluded(u: uv.x, v: uv.y, expectedDepth: depth) { return false }
        }
        return true
    }

    // MARK: - Projection

    private static func projectPixel(
        point: SIMD3<Float>, keyframe: KeyframeStore.Keyframe
    ) -> (SIMD2<Float>, Float)? {
        let world = SIMD4<Float>(point.x, point.y, point.z, 1)
        let p = keyframe.transform.inverse * world
        let depth = -p.z
        guard depth > 0.05 else { return nil }
        let k = keyframe.intrinsics
        let u = k[0][0] * p.x / depth + k[2][0]
        let v = k[2][1] - k[1][1] * p.y / depth
        let mx = Float(keyframe.width) * 0.01
        let my = Float(keyframe.height) * 0.01
        guard u > mx, u < Float(keyframe.width) - mx,
              v > my, v < Float(keyframe.height) - my else { return nil }
        return (SIMD2<Float>(u, v), depth)
    }

    // MARK: - Bitmap

    struct Bitmap {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    private static func makeBitmap(
        _ keyframe: KeyframeStore.Keyframe, targetWidth: Int
    ) -> Bitmap? {
        guard let uiImage = UIImage(data: keyframe.jpegData),
              let cgImage = uiImage.cgImage else { return nil }
        let width = min(targetWidth, cgImage.width)
        let height = max(1, cgImage.height * width / cgImage.width)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Bitmap(pixels: pixels, width: width, height: height)
    }

    private static func bilinearSample(_ bitmap: Bitmap, x: Float, y: Float) -> SIMD3<Float>? {
        let fx = x - 0.5, fy = y - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        guard x0 >= 0, y0 >= 0, x0 + 1 < bitmap.width, y0 + 1 < bitmap.height else {
            let cx = min(max(Int(x), 0), bitmap.width - 1)
            let cy = min(max(Int(y), 0), bitmap.height - 1)
            let o = (cy * bitmap.width + cx) * 4
            return SIMD3<Float>(
                Float(bitmap.pixels[o]), Float(bitmap.pixels[o + 1]), Float(bitmap.pixels[o + 2])
            ) / 255
        }
        let tx = fx - Float(x0), ty = fy - Float(y0)
        func px(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let o = (y * bitmap.width + x) * 4
            return SIMD3<Float>(
                Float(bitmap.pixels[o]), Float(bitmap.pixels[o + 1]), Float(bitmap.pixels[o + 2])
            )
        }
        let top = px(x0, y0) * (1 - tx) + px(x0 + 1, y0) * tx
        let bot = px(x0, y0 + 1) * (1 - tx) + px(x0 + 1, y0 + 1) * tx
        return (top * (1 - ty) + bot * ty) / 255
    }

    // MARK: - Hole filling

    private static func dilate(
        _ pixels: inout [UInt8], _ filled: inout [Bool], w: Int, h: Int, passes: Int
    ) {
        for _ in 0..<passes {
            var newFilled = filled
            var newPixels = pixels
            for y in 0..<h {
                for x in 0..<w {
                    let idx = y * w + x
                    if filled[idx] { continue }
                    var accum = SIMD3<Int>.zero
                    var count = 0
                    if x > 0, filled[idx - 1] { let o = (idx - 1) * 4; accum &+= SIMD3<Int>(Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2])); count += 1 }
                    if x < w - 1, filled[idx + 1] { let o = (idx + 1) * 4; accum &+= SIMD3<Int>(Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2])); count += 1 }
                    if y > 0, filled[idx - w] { let o = (idx - w) * 4; accum &+= SIMD3<Int>(Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2])); count += 1 }
                    if y < h - 1, filled[idx + w] { let o = (idx + w) * 4; accum &+= SIMD3<Int>(Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2])); count += 1 }
                    if count > 0 {
                        let o = idx * 4
                        newPixels[o] = UInt8(accum.x / count)
                        newPixels[o + 1] = UInt8(accum.y / count)
                        newPixels[o + 2] = UInt8(accum.z / count)
                        newPixels[o + 3] = 255
                        newFilled[idx] = true
                    }
                }
            }
            pixels = newPixels
            filled = newFilled
        }
    }

    /// Pull-push: mip piramida orqali katta bo'sh joylarni atrof rangi bilan
    /// ishonchli to'ldiradi (dilatatsiya faqat chekka pikselni to'ldira oladi).
    private static func pullPushFill(
        _ pixels: inout [UInt8], filled: [Bool], w: Int, h: Int
    ) {
        struct Level {
            var w: Int, h: Int
            var rgba: [UInt8]  // alpha: 0 = bo'sh, 255 = to'la
        }

        // Level 0
        var level0 = Level(w: w, h: h, rgba: [UInt8](repeating: 0, count: w * h * 4))
        for i in 0..<(w * h) {
            let o = i * 4
            if filled[i] {
                level0.rgba[o] = pixels[o]
                level0.rgba[o + 1] = pixels[o + 1]
                level0.rgba[o + 2] = pixels[o + 2]
                level0.rgba[o + 3] = 255
            }
        }

        // Pull: pastga (kichrayish)
        var levels: [Level] = [level0]
        while levels.last!.w > 2 || levels.last!.h > 2 {
            let prev = levels.last!
            let nw = max(1, (prev.w + 1) / 2)
            let nh = max(1, (prev.h + 1) / 2)
            var next = Level(w: nw, h: nh, rgba: [UInt8](repeating: 0, count: nw * nh * 4))
            for y in 0..<nh {
                for x in 0..<nw {
                    var accum = SIMD3<Int>.zero
                    var count = 0
                    for dy in 0..<2 {
                        for dx in 0..<2 {
                            let sx = x * 2 + dx, sy = y * 2 + dy
                            guard sx < prev.w, sy < prev.h else { continue }
                            let o = (sy * prev.w + sx) * 4
                            if prev.rgba[o + 3] > 0 {
                                accum &+= SIMD3<Int>(Int(prev.rgba[o]), Int(prev.rgba[o + 1]), Int(prev.rgba[o + 2]))
                                count += 1
                            }
                        }
                    }
                    if count > 0 {
                        let o = (y * nw + x) * 4
                        next.rgba[o] = UInt8(accum.x / count)
                        next.rgba[o + 1] = UInt8(accum.y / count)
                        next.rgba[o + 2] = UInt8(accum.z / count)
                        next.rgba[o + 3] = 255
                    }
                }
            }
            levels.append(next)
        }

        // Push: yuqoriga (kattalashish) — bo'sh piksellar coarser level'dan oladi
        for li in stride(from: levels.count - 2, through: 0, by: -1) {
            let coarse = levels[li + 1]
            for y in 0..<levels[li].h {
                for x in 0..<levels[li].w {
                    let o = (y * levels[li].w + x) * 4
                    if levels[li].rgba[o + 3] > 0 { continue }
                    let cx = min(x / 2, coarse.w - 1)
                    let cy = min(y / 2, coarse.h - 1)
                    let co = (cy * coarse.w + cx) * 4
                    if coarse.rgba[co + 3] > 0 {
                        levels[li].rgba[o] = coarse.rgba[co]
                        levels[li].rgba[o + 1] = coarse.rgba[co + 1]
                        levels[li].rgba[o + 2] = coarse.rgba[co + 2]
                        levels[li].rgba[o + 3] = 255
                    }
                }
            }
        }

        // Natijani bo'sh piksellarga qaytarish
        for i in 0..<(w * h) where !filled[i] {
            let o = i * 4
            pixels[o] = levels[0].rgba[o]
            pixels[o + 1] = levels[0].rgba[o + 1]
            pixels[o + 2] = levels[0].rgba[o + 2]
            pixels[o + 3] = 255
        }
    }

    private static func makeCGImage(pixels: [UInt8], w: Int, h: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
