// MLAtlasEnhancer — Phase 6.1: CoreML AI integration.
//
// Real-ESRGAN super-resolution: atlas'ni AI bilan sharpening + detail recovery.
// Phase 4 over-blur regression'ini AI orqali tuzatadi: bizning Phase 5
// smoothing tuning'i + ESRGAN SR = Polycam darajasiga yaqin atlas.
//
// Model: mszpro/CoreML_RealESRGAN (Hugging Face)
//   Input:  512×512 RGB (uint8)
//   Output: 2048×2048 RGB (4x upscale)
//   Size:   64 MB compiled
//   Speed:  ~500ms / tile on Neural Engine (iPhone 14 Pro)
//
// Atlas SR strategy:
//   1. 2048×2048 atlas → 4×4 grid of 512×512 tiles (overlap 32px)
//   2. Har tile SR → 2048×2048 (4x)
//   3. Assemble 4×4 of 2048×2048 with feather blend → 8192×8192
//   4. Downscale to 4096×4096 (USDZ texture cap)
//
// Faqat Neural Engine'da run (computeUnits .cpuAndNeuralEngine).
// CPU fallback'siz — model katta, CPU'da ~30s/tile, qabul qilib bo'lmas.

import Foundation
import CoreML
import CoreImage
import CoreGraphics
import UIKit

enum MLAtlasEnhancer {

    // MARK: - Public API

    /// Atlas image'ga Real-ESRGAN super-resolution qo'llaydi.
    /// Iter10: Downscale-then-SR strategy — same output size, FEWER tiles.
    ///   atlas 4096 → downscale to 1024 → tile 2×2 → ESRGAN each 512→2048
    ///   → assemble 4096. Total = 4 tiles instead of 81.
    static func enhance(
        atlas: UIImage,
        progress: ((Float, String) -> Void)? = nil,
    ) -> UIImage? {
        let startTime = Date()
        NSLog("KADASTR ESRGAN ▶ enhance() boshlandi")
        logMemory(label: "boshlanish")

        progress?(0.0, "Real-ESRGAN model loading…")
        let modelStart = Date()
        guard let model = loadModel() else {
            NSLog("KADASTR ESRGAN ✗ model load FAILED")
            return nil
        }
        NSLog(String(format: "KADASTR ESRGAN model loaded in %.2fs", Date().timeIntervalSince(modelStart)))

        guard let cgImage = atlas.cgImage else {
            NSLog("KADASTR ESRGAN ✗ no CGImage")
            return nil
        }
        let atlasW = cgImage.width
        let atlasH = cgImage.height
        NSLog("KADASTR ESRGAN input atlas: \(atlasW)×\(atlasH)")

        // Iter10 strategy: downscale atlas to 1024 → 2×2 tiles of 512 → SR each
        // → output 2×2 of 2048 = 4096. Output size same as input atlas if 4096,
        // or larger if input < 4096. Total: 4 ESRGAN inferences.
        let outW = atlasW
        let outH = atlasH

        // Downscaled input (4096 → 1024, or atlasSize/4)
        let downW = max(512, atlasW / 4)
        let downH = max(512, atlasH / 4)
        guard let downCG = resizeCGImage(cgImage, toWidth: downW, height: downH) else {
            NSLog("KADASTR ESRGAN ✗ downscale FAILED")
            return nil
        }
        NSLog("KADASTR ESRGAN downscaled: \(downW)×\(downH) (input to ESRGAN)")

        let tileIn = 512
        let tileOut = 2048
        let tilesX = max(1, Int(ceil(Double(downW) / Double(tileIn))))
        let tilesY = max(1, Int(ceil(Double(downH) / Double(tileIn))))
        let totalTiles = tilesX * tilesY
        NSLog("KADASTR ESRGAN tiling: \(tilesX)×\(tilesY)=\(totalTiles), output canvas \(outW)×\(outH)")

        guard let outCtx = createRGBContext(width: outW, height: outH) else {
            NSLog("KADASTR ESRGAN ✗ output ctx FAILED")
            return nil
        }
        outCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        outCtx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))

        var tilesProcessed = 0
        var tilesFailed = 0

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let tileStart = Date()
                let srcX = min(tx * tileIn, max(0, downW - tileIn))
                let srcY = min(ty * tileIn, max(0, downH - tileIn))

                autoreleasepool {
                    guard let tileCG = cropTile(from: downCG, x: srcX, y: srcY, size: tileIn) else {
                        tilesFailed += 1; tilesProcessed += 1
                        NSLog("KADASTR ESRGAN tile #\(tilesProcessed) crop FAIL")
                        return
                    }
                    guard let srTileCG = runSR(model: model, input: tileCG) else {
                        tilesFailed += 1; tilesProcessed += 1
                        NSLog("KADASTR ESRGAN tile #\(tilesProcessed) SR FAIL")
                        progress?(Float(tilesProcessed) / Float(totalTiles), "SR \(tilesProcessed)/\(totalTiles) FAIL")
                        return
                    }
                    // Place: srcX in 1024-space → dstX in 4096-space (scale 4x)
                    let dstX = srcX * (outW / downW)
                    let dstY = srcY * (outH / downH)
                    let placeW = min(tileOut, outW - dstX)
                    let placeH = min(tileOut, outH - dstY)
                    outCtx.draw(
                        srTileCG,
                        in: CGRect(x: dstX, y: outH - dstY - placeH, width: placeW, height: placeH),
                    )

                    tilesProcessed += 1
                    let p = Float(tilesProcessed) / Float(totalTiles)
                    let elapsed = Date().timeIntervalSince(tileStart)
                    NSLog(String(format: "KADASTR ESRGAN tile %d/%d ✓ %.2fs", tilesProcessed, totalTiles, elapsed))
                    progress?(p, "Real-ESRGAN \(tilesProcessed)/\(totalTiles)")
                }
            }
        }

        NSLog("KADASTR ESRGAN tiles done: \(tilesProcessed - tilesFailed)/\(totalTiles) OK")
        guard let finalCG = outCtx.makeImage() else {
            NSLog("KADASTR ESRGAN ✗ makeImage FAILED")
            return nil
        }
        let elapsed = Date().timeIntervalSince(startTime)
        NSLog(String(format: "KADASTR ESRGAN ✓ TOTAL %.1fs (%d/%d ok)", elapsed, tilesProcessed - tilesFailed, totalTiles))
        return UIImage(cgImage: finalCG)
    }

    /// Resize CGImage with high-quality interpolation.
    private static func resizeCGImage(_ src: CGImage, toWidth w: Int, height h: Int) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGImageByteOrderInfo.order32Big.rawValue
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: info,
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// iOS memory footprint logging.
    private static func logMemory(label: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let mb = Double(info.resident_size) / 1024.0 / 1024.0
            NSLog(String(format: "KADASTR ESRGAN [mem %@] resident: %.1f MB", label, mb))
        }
    }

    // MARK: - Internals

    private static var cachedModel: MLModel?

    private static func loadModel() -> MLModel? {
        if let cached = cachedModel { return cached }

        guard let url = Bundle.main.url(forResource: "RealESRGAN", withExtension: "mlmodelc") else {
            NSLog("KADASTR MLAtlasEnhancer: RealESRGAN.mlmodelc bundle'da topilmadi")
            return nil
        }
        let config = MLModelConfiguration()
        if #available(iOS 16.0, *) {
            config.computeUnits = .cpuAndNeuralEngine
        } else {
            config.computeUnits = .all
        }
        do {
            let model = try MLModel(contentsOf: url, configuration: config)
            cachedModel = model
            return model
        } catch {
            NSLog("KADASTR MLAtlasEnhancer: model init FAILED: \(error.localizedDescription)")
            return nil
        }
    }

    /// 512×512 RGB CGImage → 2048×2048 RGB CGImage (4x SR).
    private static func runSR(model: MLModel, input: CGImage) -> CGImage? {
        // Create CVPixelBuffer (BGRA32) from CGImage
        let pbStart = Date()
        guard let pixBuf = makePixelBuffer(from: input, width: 512, height: 512) else {
            NSLog("KADASTR ESRGAN ✗ pixel buffer create FAILED")
            return nil
        }
        let pbTime = Date().timeIntervalSince(pbStart)
        if pbTime > 0.1 { NSLog(String(format: "KADASTR ESRGAN pixBuf %.3fs", pbTime)) }

        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outputName = model.modelDescription.outputDescriptionsByName.keys.first ?? "activation_out"

        let provider: MLDictionaryFeatureProvider
        do {
            let feature = MLFeatureValue(pixelBuffer: pixBuf)
            provider = try MLDictionaryFeatureProvider(dictionary: [inputName: feature])
        } catch {
            NSLog("KADASTR ESRGAN ✗ feature provider FAILED: \(error.localizedDescription)")
            return nil
        }

        // Actual NN inference — bu yerda Neural Engine ishlaydi
        let infStart = Date()
        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: provider)
        } catch {
            NSLog("KADASTR ESRGAN ✗ prediction FAILED: \(error.localizedDescription)")
            return nil
        }
        let infTime = Date().timeIntervalSince(infStart)
        if infTime > 1.0 {
            NSLog(String(format: "KADASTR ESRGAN ⚠ slow inference %.2fs", infTime))
        }

        guard let outFeature = prediction.featureValue(for: outputName) else {
            NSLog("KADASTR ESRGAN ✗ no output feature")
            return nil
        }

        // Path 1: imageBufferValue (preferred — model declared imageType)
        if let outPix = outFeature.imageBufferValue {
            let cgStart = Date()
            let result = pixelBufferToCGImage(outPix)
            let cgTime = Date().timeIntervalSince(cgStart)
            if cgTime > 0.3 { NSLog(String(format: "KADASTR ESRGAN ⚠ slow CGImage conv %.2fs", cgTime)) }
            return result
        }

        // Path 2 (Phase 6.1a): mszpro/CoreML_RealESRGAN output rank 3 — CoreML
        // imageType rank 4 kutadi va imageBufferValue nil qaytaradi.
        // MLMultiArray sifatida o'qib, manually CGImage'ga konvert qilamiz.
        if let arr = outFeature.multiArrayValue {
            return multiArrayToCGImage(arr)
        }
        NSLog("KADASTR ESRGAN ✗ neither image nor multiArray output")
        return nil
    }

    /// MLMultiArray (CHW float32/float16, 0..1 yoki 0..255) → CGImage RGB.
    /// Shape: [3, H, W] (CHW) yoki [H, W, 3] (HWC) — ikkalasini ham try qilamiz.
    private static func multiArrayToCGImage(_ arr: MLMultiArray) -> CGImage? {
        let shape = arr.shape.map { $0.intValue }
        guard shape.count == 3 else {
            NSLog("KADASTR ESRGAN ✗ rank \(shape.count), expected 3")
            return nil
        }

        // Detect layout: CHW if first dim == 3, HWC if last dim == 3.
        let isCHW: Bool
        let H: Int, W: Int
        if shape[0] == 3 {
            isCHW = true; H = shape[1]; W = shape[2]
        } else if shape[2] == 3 {
            isCHW = false; H = shape[0]; W = shape[1]
        } else {
            NSLog("KADASTR ESRGAN ✗ unexpected shape \(shape)")
            return nil
        }

        // Pixel buffer (RGBA8, premultipliedLast)
        let bytesPerRow = W * 4
        var pixels = [UInt8](repeating: 255, count: H * bytesPerRow)

        // Determine value range — sample center pixel
        let sampleVal: Float
        if isCHW {
            sampleVal = arr[[0, H/2, W/2] as [NSNumber]].floatValue
        } else {
            sampleVal = arr[[H/2, W/2, 0] as [NSNumber]].floatValue
        }
        // Heuristic: if any sample > 5 → assume 0..255 range, else 0..1
        let scale: Float = (abs(sampleVal) > 5.0) ? 1.0 : 255.0

        let strides = arr.strides.map { $0.intValue }
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(arr.dataPointer))

        // Check data type — most CoreML models use float32 or float16
        let dataType = arr.dataType
        if dataType == .float32 {
            for y in 0..<H {
                for x in 0..<W {
                    let pIdx = y * bytesPerRow + x * 4
                    let r: Float, g: Float, b: Float
                    if isCHW {
                        r = ptr[0 * strides[0] + y * strides[1] + x * strides[2]]
                        g = ptr[1 * strides[0] + y * strides[1] + x * strides[2]]
                        b = ptr[2 * strides[0] + y * strides[1] + x * strides[2]]
                    } else {
                        r = ptr[y * strides[0] + x * strides[1] + 0 * strides[2]]
                        g = ptr[y * strides[0] + x * strides[1] + 1 * strides[2]]
                        b = ptr[y * strides[0] + x * strides[1] + 2 * strides[2]]
                    }
                    pixels[pIdx + 0] = UInt8(max(0, min(255, r * scale)))
                    pixels[pIdx + 1] = UInt8(max(0, min(255, g * scale)))
                    pixels[pIdx + 2] = UInt8(max(0, min(255, b * scale)))
                    pixels[pIdx + 3] = 255
                }
            }
        } else if #available(iOS 16.0, *), dataType == .float16 {
            // Float16 stored as UInt16; we need to convert per-element.
            let raw = UnsafeMutablePointer<UInt16>(OpaquePointer(arr.dataPointer))
            for y in 0..<H {
                for x in 0..<W {
                    let pIdx = y * bytesPerRow + x * 4
                    let r: Float, g: Float, b: Float
                    if isCHW {
                        r = halfToFloat(raw[0 * strides[0] + y * strides[1] + x * strides[2]])
                        g = halfToFloat(raw[1 * strides[0] + y * strides[1] + x * strides[2]])
                        b = halfToFloat(raw[2 * strides[0] + y * strides[1] + x * strides[2]])
                    } else {
                        r = halfToFloat(raw[y * strides[0] + x * strides[1] + 0 * strides[2]])
                        g = halfToFloat(raw[y * strides[0] + x * strides[1] + 1 * strides[2]])
                        b = halfToFloat(raw[y * strides[0] + x * strides[1] + 2 * strides[2]])
                    }
                    pixels[pIdx + 0] = UInt8(max(0, min(255, r * scale)))
                    pixels[pIdx + 1] = UInt8(max(0, min(255, g * scale)))
                    pixels[pIdx + 2] = UInt8(max(0, min(255, b * scale)))
                    pixels[pIdx + 3] = 255
                }
            }
        } else {
            NSLog("KADASTR ESRGAN ✗ unsupported dataType \(dataType.rawValue)")
            return nil
        }

        // Pack into CGImage
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGImageByteOrderInfo.order32Big.rawValue
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        guard let provider = provider else { return nil }
        return CGImage(
            width: W, height: H,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: cs, bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent,
        )
    }

    /// IEEE 754 half (16-bit) → single (32-bit). Standard formula.
    private static func halfToFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h >> 15) & 0x1
        let exp = UInt32(h >> 10) & 0x1F
        let mant = UInt32(h & 0x3FF)
        var bits: UInt32 = 0
        if exp == 0 {
            if mant == 0 {
                bits = sign << 31
            } else {
                // Denormal — normalize
                var e: Int32 = -1
                var m = mant
                repeat {
                    e += 1
                    m <<= 1
                } while (m & 0x400) == 0
                bits = (sign << 31) | (UInt32(127 - 15 - e) << 23) | ((m & 0x3FF) << 13)
            }
        } else if exp == 31 {
            bits = (sign << 31) | 0x7F800000 | (mant << 13)
        } else {
            bits = (sign << 31) | (UInt32(Int(exp) - 15 + 127) << 23) | (mant << 13)
        }
        return Float(bitPattern: bits)
    }

    // MARK: - Image helpers

    private static func cropTile(from img: CGImage, x: Int, y: Int, size: Int) -> CGImage? {
        // CGImage coordinate origin is top-left. y here is in image coords.
        let rect = CGRect(x: x, y: y, width: size, height: size)
        return img.cropping(to: rect)
    }

    private static func createRGBContext(width: Int, height: Int) -> CGContext? {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGImageByteOrderInfo.order32Big.rawValue
        return CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: info,
        )
    }

    private static func makePixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var pixBuf: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixBuf,
        )
        guard status == kCVReturnSuccess, let pb = pixBuf else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGImageByteOrderInfo.order32Little.rawValue
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: cs, bitmapInfo: info,
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pb
    }

    private static func pixelBufferToCGImage(_ pixBuf: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixBuf)
        let context = CIContext(options: nil)
        return context.createCGImage(ci, from: ci.extent)
    }
}
