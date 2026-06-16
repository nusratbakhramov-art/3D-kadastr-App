import Foundation
import ImageIO
import simd

/// Runs texturing on a SAVED scan — reads the mesh + keyframes back from disk
/// and bakes per-vertex colour, then writes the textured outputs. Because it
/// works purely off persisted data, you can iterate on texturing without ever
/// re-scanning the room.
enum TexturingService {
    enum TexturingError: Error { case noMesh, noFrames }

    @discardableResult
    static func run(scanID: String) async throws -> ExportBundle {
        let store = ScanStore.shared
        let folder = store.folder(for: scanID)
        guard let manifest = store.loadManifest(scanID) else { throw TexturingError.noMesh }

        let consolidated = try resolveGeometry(scanID: scanID, manifest: manifest, folder: folder)
        guard consolidated.vertexCount > 0 else { throw TexturingError.noMesh }

        let keyframes = loadKeyframes(scanID: scanID)

        // Per-vertex (fast, fallback preview).
        let textured = VertexColorTexturer.bake(mesh: consolidated, keyframes: keyframes)
        let binURL = folder.appendingPathComponent("result/textured.bin")
        let plyURL = folder.appendingPathComponent("result/textured.ply")
        try GeometryIO.writeTextured(textured, to: binURL)
        try MeshExporter.exportPLY(textured, to: plyURL)

        // Atlas (photorealistic primary result).
        let atlas = AtlasTexturer.bake(mesh: consolidated, keyframes: keyframes)
        let atlasGeoURL = folder.appendingPathComponent("result/atlas.geo")
        let atlasPNGURL = folder.appendingPathComponent("result/atlas.png")
        let atlasUSDZURL = folder.appendingPathComponent("result/atlas.usdz")
        try AtlasIO.writeGeometry(atlas, to: atlasGeoURL)
        try AtlasIO.writePNG(rgba: atlas.atlas, size: atlas.atlasSize, to: atlasPNGURL)
        try? MeshExporter.exportAtlasOBJ(atlas, baseURL: folder.appendingPathComponent("result"), name: "atlas")
        // GLB (portable: geometry + embedded texture) — the format uploaded to the
        // backend and shown via model_viewer_plus.
        let atlasGLBURL = folder.appendingPathComponent("result/atlas.glb")
        try? MeshExporter.exportAtlasGLB(atlas, to: atlasGLBURL, atlasPNG: atlasPNGURL)
        // USDZ for QuickLook: SceneKit is reliable on device; ModelIO is a fallback.
        do {
            try MeshExporter.exportAtlasUSDZSceneKit(atlas, to: atlasUSDZURL)
        } catch {
            try? MeshExporter.exportAtlasUSDZ(atlas, to: atlasUSDZURL, atlasPNG: atlasPNGURL)
        }

        if var updated = store.loadManifest(scanID) {
            updated.texturedBin = "result/textured.bin"
            updated.texturedPLY = "result/textured.ply"
            updated.atlasGeo = "result/atlas.geo"
            updated.atlasPNG = "result/atlas.png"
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("result/atlas.obj").path) {
                updated.atlasOBJ = "result/atlas.obj"
            }
            if FileManager.default.fileExists(atPath: atlasUSDZURL.path) {
                updated.atlasUSDZ = "result/atlas.usdz"
            }
            // Always refresh mesh stats — texturing rebuilds geometry from depth.
            updated.hasMesh = true
            updated.geometryBin = "geometry.bin"
            updated.meshVertexCount = consolidated.vertexCount
            updated.meshTriangleCount = consolidated.triangleCount
            let plain = TexturedMesh(
                positions: consolidated.positions, normals: consolidated.normals,
                indices: consolidated.indices,
                colors: Array(repeating: SIMD3<Float>(0.72, 0.72, 0.75), count: consolidated.vertexCount)
            )
            try? MeshExporter.exportPLY(plain, to: folder.appendingPathComponent("mesh.ply"))
            updated.meshPLY = "mesh.ply"
            try store.saveManifest(updated)
        }

        let objURL = folder.appendingPathComponent("result/atlas.obj")
        return ExportBundle(usdz: atlasUSDZURL, ply: plyURL, obj: objURL)
    }

    /// Geometry source, in priority order: a saved dense mesh (`geometry.bin`),
    /// otherwise reconstructed from the saved LiDAR depth frames. Depth-built
    /// geometry is persisted to `geometry.bin` for the mesh view + future reruns.
    private static func resolveGeometry(scanID: String, manifest: ScanManifest, folder: URL) throws -> ConsolidatedMesh {
        // ARSCNView (Polycam) capture writes the COMPLETE ARKit scene mesh to
        // geometry.bin — exactly what the live wireframe showed. With no RoomPlan
        // room.json, texture THAT directly: depth-rebuilding from the movement-gated
        // depth keyframes drops the ~30% the wireframe covered (surfaces seen while
        // rotating, or without a 0.2 m translation, have no depth frame). Matches
        // RoomScanPlanAI. (RoomPlan scans keep room.json → fall through to snapping.)
        let roomJSONURL = folder.appendingPathComponent("room.json")
        if !FileManager.default.fileExists(atPath: roomJSONURL.path),
           let bin = manifest.geometryBin,
           let saved = try? GeometryIO.read(folder.appendingPathComponent(bin)),
           saved.positions.count > 0 {
            return ConsolidatedMesh(positions: saved.positions, normals: saved.normals, indices: saved.indices)
        }

        // Prefer rebuilding from depth so mesher improvements (winding, density)
        // always apply on a rerun — depth meshing is only a few seconds.
        if manifest.depthCount > 0 {
            var mesh = DepthMesher.buildMesh(scanID: scanID)
            // 0. Decimate to ~2 cm BEFORE the smoothing passes — bounds their cost +
            //    memory on device (the atlas re-decimates to 8 cm anyway, so no loss).
            if mesh.vertexCount > 0 { mesh = VoxelWelder.weld(mesh, cell: 0.02) }
            // 1. Kill LiDAR spikes/stalactites before any flattening.
            if mesh.vertexCount > 0 { mesh = MeshCleanup.removeSpeckle(mesh, iterations: 5) }
            // 2. Snap walls/floor/ceiling flat onto the RoomPlan planes (keeps the
            //    mesh connected; furniture survives) → flat surfaces, no swallowing.
            // 3. Edge-aware Taubin smoothing flattens/denoises OBJECTS only — the
            //    snapped wall vertices are held fixed so walls stay dead-flat.
            let roomJSON = folder.appendingPathComponent("room.json")
            if mesh.vertexCount > 0, FileManager.default.fileExists(atPath: roomJSON.path) {
                let (fused, snapped) = RoomShell.fuse(depthMesh: mesh, roomJSON: roomJSON)
                mesh = MeshCleanup.taubinSmooth(fused, iterations: 3, edgeSharpness: 12, skip: snapped)
            } else if mesh.vertexCount > 0 {
                mesh = MeshCleanup.taubinSmooth(mesh, iterations: 3, edgeSharpness: 12)
            }
            if mesh.vertexCount > 0 {
                try? GeometryIO.write(mesh, to: folder.appendingPathComponent("geometry.bin"))
                return mesh
            }
        }

        if let bin = manifest.geometryBin,
           FileManager.default.fileExists(atPath: folder.appendingPathComponent(bin).path) {
            let mesh = try GeometryIO.read(folder.appendingPathComponent(bin))
            return ConsolidatedMesh(positions: mesh.positions, normals: mesh.normals, indices: mesh.indices)
        }

        throw TexturingError.noMesh
    }

    /// Max keyframe width used during texturing — caps peak memory (74 frames
    /// at full res would be ~220 MB). Intrinsics are rescaled to match.
    /// Keyframe decode width, capped so all decoded keyframes stay ~420 MB in RAM
    /// regardless of room size (a 167-frame room would OOM at full res). Env
    /// KADASTR_TEX_W overrides (harness/tuning).
    private static func textureMaxWidth(frameCount: Int) -> Int {
        if let s = ProcessInfo.processInfo.environment["KADASTR_TEX_W"], let v = Int(s) { return v }
        let cap = Int((280_000_000.0 / (3.0 * Double(max(1, frameCount)))).squareRoot())
        return min(1024, max(560, cap))
    }

    /// Decode every saved keyframe back into a `Keyframe` (RGBA + pose + intrinsics
    /// + registered depth for the occlusion test).
    static func loadKeyframes(scanID: String) -> [Keyframe] {
        let store = ScanStore.shared
        guard let index = store.loadFrames(scanID) else { return [] }
        return loadKeyframes(folder: store.folder(for: scanID), frames: index)
    }

    /// Folder-based loader shared by the app and the headless `meshcheck` tool.
    static func loadKeyframes(folder: URL, frames index: FramesIndex) -> [Keyframe] {
        var result: [Keyframe] = []
        result.reserveCapacity(index.frames.count)
        let maxW = textureMaxWidth(frameCount: index.frames.count)

        for meta in index.frames {
            let imageURL = folder.appendingPathComponent("frames/\(meta.image)")
            guard let decoded = decodeRGBA(imageURL, maxWidth: maxW) else { continue }

            // Stored intrinsics match the full-size JPEG; rescale to the decode size.
            let rgbScale = Float(decoded.width) / Float(max(1, meta.imageWidth))
            var k = simd_float3x3(flat: meta.intrinsics)
            k.columns.0.x *= rgbScale; k.columns.1.y *= rgbScale
            k.columns.2.x *= rgbScale; k.columns.2.y *= rgbScale

            // Load the registered depth map (for occlusion testing), if present.
            var depth: [Float]?
            var depthIntrinsics = matrix_identity_float3x3
            var dw = 0, dh = 0
            if let depthName = meta.depth, let w = meta.depthWidth, let h = meta.depthHeight,
               let data = try? Data(contentsOf: folder.appendingPathComponent("depth/\(depthName)")),
               data.count >= w * h * 4 {
                depth = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(w * h)) }
                dw = w; dh = h
                let dScale = Float(w) / Float(max(1, meta.imageWidth))
                var dk = simd_float3x3(flat: meta.intrinsics)
                dk.columns.0.x *= dScale; dk.columns.1.y *= dScale
                dk.columns.2.x *= dScale; dk.columns.2.y *= dScale
                depthIntrinsics = dk
            }

            let transform = simd_float4x4(flat: meta.transform)
            result.append(Keyframe(
                width: decoded.width,
                height: decoded.height,
                rgba: decoded.rgba,
                intrinsics: k,
                worldToCamera: simd_inverse(transform),
                depth: depth,
                depthWidth: dw,
                depthHeight: dh,
                depthIntrinsics: depthIntrinsics,
                cameraPosition: transform.translation,
                sharpness: sharpnessScore(decoded.rgba, width: decoded.width, height: decoded.height)
            ))
        }
        return result
    }

    /// Mean local luma-gradient energy — a cheap focus measure. Motion-blurred
    /// frames score low, so the texturer can prefer crisp views.
    private static func sharpnessScore(_ rgba: [UInt8], width: Int, height: Int) -> Float {
        guard width > 4, height > 4 else { return 1 }
        let step = 4
        var sum: Double = 0
        var n = 0
        func luma(_ x: Int, _ y: Int) -> Int {
            let i = (y * width + x) * 4
            return Int(rgba[i]) + 2 * Int(rgba[i + 1]) + Int(rgba[i + 2])
        }
        var y = step
        while y < height - step {
            var x = step
            while x < width - step {
                let l = luma(x, y)
                sum += Double(abs(l - luma(x + step, y)) + abs(l - luma(x, y + step)))
                n += 1
                x += step
            }
            y += step
        }
        return n > 0 ? Float(sum / Double(n)) + 1 : 1
    }

    /// Decode a JPEG to tightly-packed top-left-origin RGBA8, downscaled so the
    /// longest side ≤ `maxWidth`.
    private static func decodeRGBA(_ url: URL, maxWidth: Int) -> (rgba: [UInt8], width: Int, height: Int)? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxWidth
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (rgba, width, height)
    }
}
