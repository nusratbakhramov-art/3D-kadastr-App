import Foundation

/// Top-level description of one saved scan (`scanNNN/manifest.json`). Records
/// what was captured and which files hold the raw data, so the later pipeline
/// stages (mesh view, texturing) can run entirely off disk — no re-scan needed.
struct ScanManifest: Codable, Equatable {
    var id: String                 // "scan001"
    var createdAt: Date
    var deviceModel: String

    // What we captured
    var hasRoom: Bool = false      // RoomPlan parametric room (walls/objects)
    var hasMesh: Bool = false      // dense LiDAR mesh
    var frameCount: Int = 0        // saved RGB keyframes
    var depthCount: Int = 0        // saved LiDAR depth maps
    var meshVertexCount: Int = 0
    var meshTriangleCount: Int = 0
    var roomObjectCount: Int = 0
    var roomWallCount: Int = 0
    var floorAreaM2: Float?         // derived from the classified scene mesh (Polycam-style)

    // Relative file names within the scan folder
    var roomUSDZ: String?          // "room.usdz"  (parametric + mesh)
    var roomJSON: String?          // "room.json"  (CapturedRoom, Codable)
    var roomDataFile: String?      // "room.capturedroomdata" (re-processable)
    var meshUSDZ: String?          // "mesh.usdz"  (dense geometry)
    var meshPLY: String?           // "mesh.ply"
    var geometryBin: String?       // "geometry.bin" (fast reload for texturing)
    var lidarBin: String?          // "lidar.bin" (raw depth mesh, NO RoomShell — the
                                   //   true as-captured surface; cached on first view)
    var framesJSON: String?        // "frames/frames.json"

    // Pipeline outputs
    var texturedBin: String?       // "result/textured.bin" (per-vertex preview)
    var texturedUSDZ: String?      // "result/textured.usdz"
    var texturedPLY: String?       // "result/textured.ply"

    // Atlas (photorealistic) result
    var atlasGeo: String?          // "result/atlas.geo"
    var atlasPNG: String?          // "result/atlas.png"
    var atlasOBJ: String?          // "result/atlas.obj" (+ .mtl + .png)
    var atlasUSDZ: String?         // "result/atlas.usdz"
}

/// Per-keyframe metadata stored in `frames/frames.json`. The matrices are
/// column-major flattened arrays (see `simd_float*` `flat` helpers).
struct FrameMetadata: Codable, Equatable {
    var index: Int
    var timestamp: Double
    var image: String              // "000.jpg"
    var imageWidth: Int
    var imageHeight: Int
    var transform: [Float]         // 16 — camera → world
    var intrinsics: [Float]        // 9  — scaled to image size
    var depth: String?             // "000.depth" (Float32, depthWidth×depthHeight)
    var confidence: String?        // "000.conf"  (UInt8)
    var depthWidth: Int?
    var depthHeight: Int?
}

struct FramesIndex: Codable, Equatable {
    var frames: [FrameMetadata]
}

extension JSONEncoder {
    static var scan: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var scan: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
