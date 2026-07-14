import Foundation
import Compression
import simd

/// Zich depth-kesh (Scaniverse uslubi): skan paytida HAR tick'da (harakat
/// shartisiz) depth+conf saqlanadi — TSDF 10-20× ko'p kuzatuv oladi, natijada
/// yakka-o'qish shovqini yo'qoladi, qora sirtlar to'planadi, teshiklar kichik.
///
/// Fayl formati (little-endian): "PCDD" | u32 dw | u32 dh |
///   u32 depthComp | u32 confComp | [depthComp bayt LZFSE(u16 mm)] |
///   [confComp bayt LZFSE(u8 conf)]  (confComp=0 — conf yo'q)
/// LZFSE depth'ni ~2-3× siqadi (147KB → ~50-70KB/kadr).
enum DenseDepthStore {

    // MARK: - Yozish (skan paytida)

    /// depth (u16 mm) + conf (u8) ni siqib yozadi. Fon navbatida chaqirilsin.
    static func save(depth: Data, conf: Data?, width: Int, height: Int,
                     index: Int, folder: URL) {
        var out = Data("PCDD".utf8)
        var w32 = UInt32(width), h32 = UInt32(height)
        let depthComp = compress(depth) ?? depth
        let confComp = conf.flatMap { compress($0) } ?? conf
        var dLen = UInt32(depthComp.count)
        var cLen = UInt32(confComp?.count ?? 0)
        // Siqilmagan bo'lsa belgilash uchun yuqori bit (fallback).
        if depthComp.count == depth.count { dLen |= 0x8000_0000 }
        if let cc = confComp, let c = conf, cc.count == c.count { cLen |= 0x8000_0000 }
        withUnsafeBytes(of: &w32) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &h32) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &dLen) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &cLen) { out.append(contentsOf: $0) }
        out.append(depthComp)
        if let confComp { out.append(confComp) }
        let url = folder.appendingPathComponent(String(format: "dense_%04d.bin", index))
        try? out.write(to: url)
    }

    // MARK: - O'qish

    struct DenseFrame {
        let depthMM: [UInt16]
        let conf: [UInt8]?
        let dw: Int
        let dh: Int
    }

    static func load(index: Int, folder: URL) -> DenseFrame? {
        let url = folder.appendingPathComponent(String(format: "dense_%04d.bin", index))
        guard let data = try? Data(contentsOf: url), data.count >= 20 else { return nil }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> DenseFrame? in
            // "PCDD" magic tekshiruvi.
            guard data[0] == 0x50, data[1] == 0x43, data[2] == 0x44, data[3] == 0x44 else { return nil }
            let dw = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            let dh = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            let dLenRaw = raw.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
            let cLenRaw = raw.loadUnaligned(fromByteOffset: 16, as: UInt32.self)
            let dUncompressed = (dLenRaw & 0x8000_0000) != 0
            let cUncompressed = (cLenRaw & 0x8000_0000) != 0
            let dLen = Int(dLenRaw & 0x7FFF_FFFF)
            let cLen = Int(cLenRaw & 0x7FFF_FFFF)
            guard dw > 0, dh > 0, dw * dh < 16 * 1024 * 1024,
                  data.count >= 20 + dLen + cLen else { return nil }

            let pixels = dw * dh
            let depthBlob = data.subdata(in: 20..<(20 + dLen))
            let depthData: Data
            if dUncompressed {
                depthData = depthBlob
            } else {
                guard let d = decompress(depthBlob, rawSize: pixels * 2) else { return nil }
                depthData = d
            }
            guard depthData.count == pixels * 2 else { return nil }
            var depthMM = [UInt16](repeating: 0, count: pixels)
            depthData.withUnsafeBytes { src in
                depthMM.withUnsafeMutableBytes { $0.copyMemory(from: src) }
            }

            var conf: [UInt8]? = nil
            if cLen > 0 {
                let confBlob = data.subdata(in: (20 + dLen)..<(20 + dLen + cLen))
                let confData = cUncompressed ? confBlob : decompress(confBlob, rawSize: pixels)
                if let cd = confData, cd.count == pixels { conf = [UInt8](cd) }
            }
            return DenseFrame(depthMM: depthMM, conf: conf, dw: dw, dh: dh)
        }
    }

    /// dense_poses.json + dense/*.bin dan TSDF uchun kadrlar (tekis stride,
    /// maxFrames cheklovi). FreeSpaceCarver.DepthFrame bilan bir xil format —
    /// TSDFGeometry.integrate to'g'ridan-to'g'ri ishlatadi.
    static func loadFrames(posesJSON: URL, folder: URL,
                           maxFrames: Int) -> [FreeSpaceCarver.DepthFrame] {
        guard let data = try? Data(contentsOf: posesJSON),
              let poses = try? JSONDecoder().decode([KeyframePose].self, from: data),
              !poses.isEmpty else { return [] }

        let eligible = poses.filter { ($0.depthWidth ?? 0) > 0 && ($0.depthHeight ?? 0) > 0 }
        guard !eligible.isEmpty else { return [] }
        // Ceil — aks holda (masalan 900/600=1) qopqoq ishlamaydi.
        let stride = max(1, (eligible.count + maxFrames - 1) / maxFrames)

        var frames: [FreeSpaceCarver.DepthFrame] = []
        frames.reserveCapacity(min(eligible.count, maxFrames))
        var i = 0
        while i < eligible.count && frames.count < maxFrames {
            let pose = eligible[i]; i += stride
            guard let df = load(index: pose.index, folder: folder),
                  df.dw == pose.depthWidth, df.dh == pose.depthHeight else { continue }
            let t = pose.transform
            let R = simd_float3x3(
                SIMD3(t[0], t[1], t[2]),
                SIMD3(t[4], t[5], t[6]),
                SIMD3(t[8], t[9], t[10]))
            let k = pose.intrinsics
            let sx = Float(pose.width) / Float(df.dw)
            let sy = Float(pose.height) / Float(df.dh)
            frames.append(FreeSpaceCarver.DepthFrame(
                R: R, t: SIMD3(t[12], t[13], t[14]),
                fx: k[0] / sx, fy: k[4] / sy, cx: k[6] / sx, cy: k[7] / sy,
                dw: df.dw, dh: df.dh, depthMM: df.depthMM, conf: df.conf))
        }
        return frames
    }

    /// Diskdagi dense kadrlar soni (pose faylidan).
    static func frameCount(posesJSON: URL) -> Int {
        guard let data = try? Data(contentsOf: posesJSON),
              let poses = try? JSONDecoder().decode([KeyframePose].self, from: data) else { return 0 }
        return poses.count
    }

    // MARK: - LZFSE

    private static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let dstCap = data.count
        var dst = Data(count: dstCap)
        let written = dst.withUnsafeMutableBytes { (dstRaw: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
                guard let d = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let s = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_encode_buffer(d, dstCap, s, data.count, nil, COMPRESSION_LZFSE)
            }
        }
        // Siqilish foyda bermasa (0 yoki kattaroq) — nil, chaqiruvchi xomni yozadi.
        guard written > 0, written < data.count else { return nil }
        dst.removeSubrange(written..<dstCap)
        return dst
    }

    private static func decompress(_ data: Data, rawSize: Int) -> Data? {
        guard !data.isEmpty, rawSize > 0 else { return nil }
        var dst = Data(count: rawSize)
        let written = dst.withUnsafeMutableBytes { (dstRaw: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
                guard let d = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let s = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(d, rawSize, s, data.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written == rawSize else { return nil }
        return dst
    }
}
