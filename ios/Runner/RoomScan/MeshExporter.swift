import Foundation
import ModelIO
import simd
#if canImport(SceneKit)
import SceneKit
#endif

enum ExportError: Error {
    case usdzUnsupported
    case usdzWriteFailed
}

/// Writes a `TexturedMesh` to disk in three formats:
///   • USDZ — geometry (shaded) for Quick Look preview & AR.
///   • PLY  — geometry + per-vertex colour (carries the baked texture).
///   • OBJ  — geometry + normals, for DCC tools.
enum MeshExporter {
    static func export(_ mesh: TexturedMesh, name: String) throws -> ExportBundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let usdz = dir.appendingPathComponent("\(name).usdz")
        let ply = dir.appendingPathComponent("\(name).ply")
        let obj = dir.appendingPathComponent("\(name).obj")

        try exportUSDZ(mesh, to: usdz)
        try exportPLY(mesh, to: ply)
        try exportOBJ(mesh, to: obj)

        return ExportBundle(usdz: usdz, ply: ply, obj: obj)
    }

    // MARK: - USDZ (ModelIO)

    static func exportUSDZ(_ mesh: TexturedMesh, to url: URL) throws {
        guard MDLAsset.canExportFileExtension(url.pathExtension) else {
            throw ExportError.usdzUnsupported
        }

        let allocator = MDLMeshBufferDataAllocator()

        let positionData = mesh.positions.withUnsafeBytes {
            Data(bytes: $0.baseAddress!, count: $0.count)
        }
        let vertexBuffer = allocator.newBuffer(with: positionData, type: .vertex)

        let indexData = mesh.indices.withUnsafeBytes {
            Data(bytes: $0.baseAddress!, count: $0.count)
        }
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: mesh.indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)

        let mdlMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: mesh.positions.count,
            descriptor: descriptor,
            submeshes: [submesh]
        )
        mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)

        let asset = MDLAsset()
        asset.add(mdlMesh)
        try asset.export(to: url)
    }

    // MARK: - PLY (ASCII, with vertex colours)

    static func exportPLY(_ mesh: TexturedMesh, to url: URL) throws {
        var header = "ply\nformat ascii 1.0\n"
        header += "comment RoomScanPlanAI export\n"
        header += "element vertex \(mesh.positions.count)\n"
        header += "property float x\nproperty float y\nproperty float z\n"
        header += "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        header += "element face \(mesh.indices.count / 3)\n"
        header += "property list uchar int vertex_indices\n"
        header += "end_header\n"

        var lines: [String] = []
        lines.reserveCapacity(mesh.positions.count + mesh.indices.count / 3)

        for i in 0..<mesh.positions.count {
            let p = mesh.positions[i]
            let c = mesh.colors[i]
            let r = UInt8(clamping: Int(c.x * 255))
            let g = UInt8(clamping: Int(c.y * 255))
            let b = UInt8(clamping: Int(c.z * 255))
            lines.append("\(p.x) \(p.y) \(p.z) \(r) \(g) \(b)")
        }

        var f = 0
        while f + 2 < mesh.indices.count {
            lines.append("3 \(mesh.indices[f]) \(mesh.indices[f + 1]) \(mesh.indices[f + 2])")
            f += 3
        }

        let body = header + lines.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .ascii)
    }

    // MARK: - Atlas (OBJ + MTL + PNG, and best-effort USDZ)

    /// Write a textured OBJ that references an atlas PNG via an MTL. Universally
    /// loadable (Blender, Preview, etc.). Writes `name.obj`, `name.mtl`, `name.png`.
    static func exportAtlasOBJ(_ mesh: AtlasTexturedMesh, baseURL: URL, name: String) throws {
        let objURL = baseURL.appendingPathComponent("\(name).obj")
        let mtlURL = baseURL.appendingPathComponent("\(name).mtl")
        let pngURL = baseURL.appendingPathComponent("\(name).png")

        try AtlasIO.writePNG(rgba: mesh.atlas, size: mesh.atlasSize, to: pngURL)

        let mtl = """
        newmtl atlas
        Ka 1.000 1.000 1.000
        Kd 1.000 1.000 1.000
        d 1.0
        illum 1
        map_Kd \(name).png
        """
        try (mtl + "\n").write(to: mtlURL, atomically: true, encoding: .ascii)

        var lines: [String] = ["mtllib \(name).mtl", "usemtl atlas"]
        lines.reserveCapacity(mesh.positions.count * 3 + mesh.indices.count / 3 + 2)
        for p in mesh.positions { lines.append("v \(p.x) \(p.y) \(p.z)") }
        for n in mesh.normals { lines.append("vn \(n.x) \(n.y) \(n.z)") }
        // OBJ texcoord origin is bottom-left; our UVs are top-left → flip V.
        for uv in mesh.uvs { lines.append("vt \(uv.x) \(1 - uv.y)") }
        var f = 0
        while f + 2 < mesh.indices.count {
            let a = mesh.indices[f] + 1, b = mesh.indices[f + 1] + 1, c = mesh.indices[f + 2] + 1
            lines.append("f \(a)/\(a)/\(a) \(b)/\(b)/\(b) \(c)/\(c)/\(c)")
            f += 3
        }
        try (lines.joined(separator: "\n") + "\n").write(to: objURL, atomically: true, encoding: .ascii)
    }

    #if canImport(SceneKit)
    /// Reliable USDZ via SceneKit (`SCNScene.write`) — embeds the atlas texture
    /// and works on device, unlike the finicky ModelIO multi-buffer path. This is
    /// the PRIMARY USDZ exporter (the QuickLook preview reads this file).
    static func exportAtlasUSDZSceneKit(_ mesh: AtlasTexturedMesh, to url: URL) throws {
        let scene = SCNScene()
        scene.rootNode.addChildNode(AtlasSceneBuilder.makeNode(mesh))
        try? FileManager.default.removeItem(at: url)
        guard scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) else {
            throw ExportError.usdzWriteFailed
        }
    }
    #endif

    /// Export the atlas-textured mesh as **GLB** (binary glTF 2.0) — one portable
    /// file (geometry + embedded PNG texture) that the app (model_viewer_plus), web,
    /// and other tools can open. The material is KHR_materials_unlit so the baked
    /// atlas shows as-is (matching the in-app `.constant` SceneKit look). This is
    /// the format uploaded to the kadastr backend.
    static func exportAtlasGLB(_ mesh: AtlasTexturedMesh, to url: URL, atlasPNG: URL) throws {
        let png = try Data(contentsOf: atlasPNG)
        let vCount = mesh.positions.count

        // Tight little-endian buffers (glTF needs packed f32x3 / f32x2 / u32 —
        // SIMD3<Float> has 16-byte stride, so we repack by component).
        var pos = [Float](); pos.reserveCapacity(vCount * 3)
        var nrm = [Float](); nrm.reserveCapacity(vCount * 3)
        var uv  = [Float](); uv.reserveCapacity(vCount * 2)
        var pmin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var pmax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for i in 0..<vCount {
            let p = mesh.positions[i], n = mesh.normals[i], t = mesh.uvs[i]
            pos.append(p.x); pos.append(p.y); pos.append(p.z)
            nrm.append(n.x); nrm.append(n.y); nrm.append(n.z)
            uv.append(t.x); uv.append(t.y)
            pmin = simd_min(pmin, p); pmax = simd_max(pmax, p)
        }

        var bin = Data()
        func align4() { while bin.count % 4 != 0 { bin.append(0) } }
        func appendBytes<T>(_ arr: [T]) -> (Int, Int) {
            let off = bin.count
            arr.withUnsafeBytes { bin.append(contentsOf: $0) }
            let len = bin.count - off
            align4()
            return (off, len)
        }
        let (idxOff, idxLen) = appendBytes(mesh.indices)   // UInt32
        let (posOff, posLen) = appendBytes(pos)
        let (nrmOff, nrmLen) = appendBytes(nrm)
        let (uvOff,  uvLen)  = appendBytes(uv)
        let imgOff = bin.count; bin.append(png); let imgLen = png.count; align4()

        func f(_ v: Float) -> String { String(v) }
        let json = """
        {"asset":{"version":"2.0","generator":"kadastr-roomscan"},\
        "scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0}],\
        "meshes":[{"primitives":[{"attributes":{"POSITION":1,"NORMAL":2,"TEXCOORD_0":3},"indices":0,"material":0,"mode":4}]}],\
        "materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0,"roughnessFactor":1},"extensions":{"KHR_materials_unlit":{}},"doubleSided":true}],\
        "extensionsUsed":["KHR_materials_unlit"],\
        "textures":[{"source":0,"sampler":0}],\
        "images":[{"bufferView":4,"mimeType":"image/png"}],\
        "samplers":[{"magFilter":9729,"minFilter":9729,"wrapS":33071,"wrapT":33071}],\
        "accessors":[\
        {"bufferView":0,"componentType":5125,"count":\(mesh.indices.count),"type":"SCALAR"},\
        {"bufferView":1,"componentType":5126,"count":\(vCount),"type":"VEC3","min":[\(f(pmin.x)),\(f(pmin.y)),\(f(pmin.z))],"max":[\(f(pmax.x)),\(f(pmax.y)),\(f(pmax.z))]},\
        {"bufferView":2,"componentType":5126,"count":\(vCount),"type":"VEC3"},\
        {"bufferView":3,"componentType":5126,"count":\(vCount),"type":"VEC2"}],\
        "bufferViews":[\
        {"buffer":0,"byteOffset":\(idxOff),"byteLength":\(idxLen),"target":34963},\
        {"buffer":0,"byteOffset":\(posOff),"byteLength":\(posLen),"target":34962},\
        {"buffer":0,"byteOffset":\(nrmOff),"byteLength":\(nrmLen),"target":34962},\
        {"buffer":0,"byteOffset":\(uvOff),"byteLength":\(uvLen),"target":34962},\
        {"buffer":0,"byteOffset":\(imgOff),"byteLength":\(imgLen)}],\
        "buffers":[{"byteLength":\(bin.count)}]}
        """
        var jsonData = Data(json.utf8)
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }   // pad with spaces

        // GLB container: header + JSON chunk + BIN chunk.
        var glb = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { glb.append(contentsOf: $0) } }
        let total = 12 + 8 + jsonData.count + 8 + bin.count
        u32(0x46546C67); u32(2); u32(UInt32(total))               // "glTF", version 2, length
        u32(UInt32(jsonData.count)); u32(0x4E4F534A); glb.append(jsonData)   // JSON chunk
        u32(UInt32(bin.count)); u32(0x004E4942); glb.append(bin)            // BIN chunk
        try glb.write(to: url)
    }

    /// Best-effort USDZ with the atlas as baseColor texture (ModelIO; device only).
    static func exportAtlasUSDZ(_ mesh: AtlasTexturedMesh, to url: URL, atlasPNG: URL) throws {
        guard MDLAsset.canExportFileExtension(url.pathExtension) else { throw ExportError.usdzUnsupported }

        let allocator = MDLMeshBufferDataAllocator()
        let posData = mesh.positions.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
        let nrmData = mesh.normals.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
        let uvData = mesh.uvs.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
        let idxData = mesh.indices.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }

        let posBuf = allocator.newBuffer(with: posData, type: .vertex)
        let nrmBuf = allocator.newBuffer(with: nrmData, type: .vertex)
        let uvBuf = allocator.newBuffer(with: uvData, type: .vertex)
        let idxBuf = allocator.newBuffer(with: idxData, type: .index)

        let scatter = MDLScatteringFunction()
        let material = MDLMaterial(name: "atlas", scatteringFunction: scatter)
        let tex = MDLURLTexture(url: atlasPNG, name: "atlas")
        let sampler = MDLTextureSampler()
        sampler.texture = tex
        material.setProperty(MDLMaterialProperty(name: "baseColor", semantic: .baseColor, textureSampler: sampler))

        let submesh = MDLSubmesh(indexBuffer: idxBuf, indexCount: mesh.indices.count,
                                 indexType: .uInt32, geometryType: .triangles, material: material)

        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 0, bufferIndex: 1)
        descriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 0, bufferIndex: 2)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        descriptor.layouts[1] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        descriptor.layouts[2] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD2<Float>>.stride)

        let mdlMesh = MDLMesh(vertexBuffers: [posBuf, nrmBuf, uvBuf], vertexCount: mesh.positions.count,
                              descriptor: descriptor, submeshes: [submesh])
        let asset = MDLAsset()
        asset.add(mdlMesh)
        try asset.export(to: url)
    }

    // MARK: - OBJ

    static func exportOBJ(_ mesh: TexturedMesh, to url: URL) throws {
        var lines: [String] = []
        lines.reserveCapacity(mesh.positions.count * 2 + mesh.indices.count / 3)

        for p in mesh.positions { lines.append("v \(p.x) \(p.y) \(p.z)") }
        for n in mesh.normals { lines.append("vn \(n.x) \(n.y) \(n.z)") }

        var f = 0
        while f + 2 < mesh.indices.count {
            let a = mesh.indices[f] + 1
            let b = mesh.indices[f + 1] + 1
            let c = mesh.indices[f + 2] + 1
            lines.append("f \(a)//\(a) \(b)//\(b) \(c)//\(c)")
            f += 3
        }

        let body = lines.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .ascii)
    }
}
