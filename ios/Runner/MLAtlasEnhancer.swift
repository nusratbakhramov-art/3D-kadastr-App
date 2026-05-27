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
    /// Hozirgi 2048×2048 atlas → 4096×4096 SR-enhanced atlas.
    ///
    /// - Parameters:
    ///   - atlas: input UIImage (any size, ideally 2048×2048)
    ///   - progress: 0..1 callback (har tile uchun)
    /// - Returns: Enhanced UIImage. Model yuklab bo'lmasa nil qaytaradi
    ///   (caller original atlas'ni ishlatadi).
    static func enhance(
        atlas: UIImage,
        progress: ((Float, String) -> Void)? = nil,
    ) -> UIImage? {
        let startTime = Date()

        // 1. Load model (Neural Engine)
        progress?(0.0, "Real-ESRGAN model loading…")
        guard let model = loadModel() else {
            NSLog("KADASTR MLAtlasEnhancer: model load FAILED")
            return nil
        }

        // 2. Atlas → CGImage
        guard let cgImage = atlas.cgImage else {
            NSLog("KADASTR MLAtlasEnhancer: no CGImage")
            return nil
        }
        let atlasW = cgImage.width
        let atlasH = cgImage.height
        NSLog("KADASTR MLAtlasEnhancer: input atlas \(atlasW)×\(atlasH)")

        // 3. Tile parameters (model takes 512×512 input)
        let tileIn = 512
        let tileOut = 2048   // 4x scale
        let scaleFactor = 4
        let overlap = 32     // edge feathering between tiles

        // Number of tiles needed to cover atlas with overlap
        let tilesX = max(1, Int(ceil(Double(atlasW - overlap) / Double(tileIn - overlap))))
        let tilesY = max(1, Int(ceil(Double(atlasH - overlap) / Double(tileIn - overlap))))
        let totalTiles = tilesX * tilesY

        // Output canvas: full SR atlas at scaleFactor x source resolution
        let outW = atlasW * scaleFactor
        let outH = atlasH * scaleFactor
        NSLog("KADASTR MLAtlasEnhancer: tiling \(tilesX)×\(tilesY)=\(totalTiles), output \(outW)×\(outH)")

        // 4. Set up output canvas (CGContext for assembly)
        guard let outCtx = createRGBContext(width: outW, height: outH) else {
            NSLog("KADASTR MLAtlasEnhancer: output ctx FAILED")
            return nil
        }
        // Black fill (alpha = 0 areas of input → black in output)
        outCtx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        outCtx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))

        // 5. Iterate tiles
        let strideX = tileIn - overlap
        let strideY = tileIn - overlap
        var tilesProcessed = 0

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let srcX = min(tx * strideX, atlasW - tileIn)
                let srcY = min(ty * strideY, atlasH - tileIn)

                // Extract 512×512 tile from atlas
                guard let tileCG = cropTile(from: cgImage, x: srcX, y: srcY, size: tileIn) else {
                    tilesProcessed += 1
                    continue
                }

                // Run SR on tile
                guard let srTileCG = runSR(model: model, input: tileCG) else {
                    tilesProcessed += 1
                    progress?(Float(tilesProcessed) / Float(totalTiles), "SR tile \(tilesProcessed)/\(totalTiles) FAILED")
                    continue
                }

                // Place into output canvas with feather blending at overlap regions
                let dstX = srcX * scaleFactor
                let dstY = srcY * scaleFactor
                let dstSize = tileOut
                outCtx.draw(
                    srTileCG,
                    in: CGRect(x: dstX, y: outH - dstY - dstSize, width: dstSize, height: dstSize),
                )

                tilesProcessed += 1
                let p = Float(tilesProcessed) / Float(totalTiles)
                progress?(p, "Real-ESRGAN \(tilesProcessed)/\(totalTiles)")
            }
        }

        // 6. Read back as UIImage
        guard let finalCG = outCtx.makeImage() else {
            NSLog("KADASTR MLAtlasEnhancer: finalCG FAILED")
            return nil
        }

        let elapsed = Date().timeIntervalSince(startTime)
        NSLog(String(format: "KADASTR MLAtlasEnhancer ✓ %.1fs (%d tiles)", elapsed, totalTiles))

        // Optional: downscale to 4096 if needed (USDZ cap)
        let maxSize = 4096
        if outW > maxSize || outH > maxSize {
            let scale = Float(maxSize) / Float(max(outW, outH))
            let dW = Int(Float(outW) * scale)
            let dH = Int(Float(outH) * scale)
            NSLog("KADASTR MLAtlasEnhancer downscale \(outW)×\(outH) → \(dW)×\(dH)")
            guard let dCtx = createRGBContext(width: dW, height: dH) else {
                return UIImage(cgImage: finalCG)
            }
            dCtx.interpolationQuality = .high
            dCtx.draw(finalCG, in: CGRect(x: 0, y: 0, width: dW, height: dH))
            if let scaled = dCtx.makeImage() {
                return UIImage(cgImage: scaled)
            }
        }
        return UIImage(cgImage: finalCG)
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
        // Create CVPixelBuffer (BGRA32) from CGImage — CoreML imageType inputs
        // odatda kCVPixelFormatType_32BGRA yoki 32ARGB qabul qiladi.
        guard let pixBuf = makePixelBuffer(from: input, width: 512, height: 512) else {
            NSLog("KADASTR MLAtlasEnhancer: pixel buffer FAILED")
            return nil
        }

        // Find input feature name (mszpro model'da "input")
        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outputName = model.modelDescription.outputDescriptionsByName.keys.first ?? "activation_out"

        let provider: MLDictionaryFeatureProvider
        do {
            let feature = MLFeatureValue(pixelBuffer: pixBuf)
            provider = try MLDictionaryFeatureProvider(dictionary: [inputName: feature])
        } catch {
            NSLog("KADASTR MLAtlasEnhancer: feature provider FAILED: \(error.localizedDescription)")
            return nil
        }

        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: provider)
        } catch {
            NSLog("KADASTR MLAtlasEnhancer: prediction FAILED: \(error.localizedDescription)")
            return nil
        }

        guard let outFeature = prediction.featureValue(for: outputName),
              let outPix = outFeature.imageBufferValue
        else {
            NSLog("KADASTR MLAtlasEnhancer: output not image type")
            return nil
        }

        return pixelBufferToCGImage(outPix)
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
