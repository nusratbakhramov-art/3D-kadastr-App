import Foundation
import RealityKit
import UIKit
import CoreImage
import simd

/// Skan geometriyasi + keyframe'lardan appning o'zida ko'rsatiladigan
/// teksturali RealityKit entity'larini quradi.
enum TexturedModelBuilder {

    /// Bitta chunk uchun tayyorlangan ma'lumot (background thread'da hisoblanadi).
    struct PreparedChunk {
        let geometry: ChunkGeometry
        let uvs: [SIMD2<Float>]?
        let keyframeIndex: Int?
    }

    /// prepare() natijasi: chunk'lar + har keyframe uchun rang gain'lari.
    struct PreparedModel {
        let chunks: [PreparedChunk]
        let gains: [Int: ColorGains]
    }

    /// Og'ir hisob-kitob: chunk→keyframe tayinlash, UV proyeksiya va
    /// rang garmonizatsiyasi. Background thread'da chaqirish mumkin.
    static func prepare(
        geometries: [Int64: ChunkGeometry],
        keyframes: [KeyframeStore.Keyframe],
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> PreparedModel {
        let assignments = TexturedOBJExporter.assignKeyframes(
            geometries: geometries, keyframes: keyframes
        )
        let total = geometries.count
        var result: [PreparedChunk] = []
        for (id, geo) in geometries.sorted(by: { $0.key < $1.key }) {
            defer { onProgress?(result.count, total) }
            if let kfIndex = assignments[id] {
                let kf = keyframes[kfIndex]
                let uvs = geo.positions.map {
                    TexturedOBJExporter.projectUV(point: $0, keyframe: kf)
                }
                result.append(PreparedChunk(geometry: geo, uvs: uvs, keyframeIndex: kfIndex))
            } else {
                result.append(PreparedChunk(geometry: geo, uvs: nil, keyframeIndex: nil))
            }
        }

        // Kadrlar orasidagi rang/ekspozitsiya farqini tekislash
        let gains = ColorHarmonizer.computeGains(
            geometries: geometries, keyframes: keyframes, assignments: assignments
        )
        return PreparedModel(chunks: result, gains: gains)
    }

    /// Entity yaratish — main thread'da chaqirilishi kerak (RealityKit resurslari).
    static func makeEntities(
        from model: PreparedModel,
        keyframes: [KeyframeStore.Keyframe]
    ) -> [ModelEntity] {
        let prepared = model.chunks
        var textureCache: [Int: TextureResource] = [:]
        var entities: [ModelEntity] = []

        for chunk in prepared {
            var descriptor = MeshDescriptor(name: "texturedChunk")
            descriptor.positions = MeshBuffers.Positions(chunk.geometry.positions)
            if let normals = chunk.geometry.normals {
                descriptor.normals = MeshBuffers.Normals(normals)
            }
            if let uvs = chunk.uvs {
                descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
            }
            descriptor.primitives = .triangles(chunk.geometry.indices)

            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }

            var material = UnlitMaterial(color: .init(white: 0.55, alpha: 1.0))
            if let kfIndex = chunk.keyframeIndex,
               let texture = texture(
                for: kfIndex, keyframes: keyframes,
                gains: model.gains[kfIndex], cache: &textureCache
               ) {
                material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
            }

            entities.append(ModelEntity(mesh: mesh, materials: [material]))
        }
        return entities
    }

    // MARK: - Rangli mesh (teksturasiz, darhol — NSDK xom mesh)

    /// Har chunk uchun bitta rangli ModelEntity (deterministik rang).
    /// Qayta ishlashsiz, darhol — skanni to'xtatgach ko'rsatish uchun.
    static func makeColoredEntities(from geometries: [Int64: ChunkGeometry]) -> [ModelEntity] {
        var entities: [ModelEntity] = []
        for (id, geo) in geometries.sorted(by: { $0.key < $1.key }) {
            guard let mesh = geo.toMeshResource() else { continue }
            let hue = CGFloat((id % 10 + 10) % 10) / 10.0
            let color = UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1.0)
            let material = SimpleMaterial(color: color, roughness: 0.6, isMetallic: false)
            entities.append(ModelEntity(mesh: mesh, materials: [material]))
        }
        return entities
    }

    // MARK: - Atlas model (yagona mesh + yagona tekstura)

    static func makeEntity(atlas: AtlasModel) -> ModelEntity? {
        var descriptor = MeshDescriptor(name: "atlasMesh")
        descriptor.positions = MeshBuffers.Positions(atlas.positions)
        descriptor.normals = MeshBuffers.Normals(atlas.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(atlas.uvs)
        descriptor.primitives = .triangles(atlas.indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]),
              let texture = try? TextureResource.generate(
                from: atlas.atlasImage, options: .init(semantic: .color)
              )
        else { return nil }

        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        return ModelEntity(mesh: mesh, materials: [material])
    }

    // MARK: - Baked model

    /// Bake qilingan chunk'lardan viewer entity'larini yaratadi (main thread).
    static func makeEntities(baked: [Int64: TextureBaker.BakedChunk]) -> [ModelEntity] {
        var entities: [ModelEntity] = []
        for (_, chunk) in baked.sorted(by: { $0.key < $1.key }) {
            let geo = chunk.geometry
            var descriptor = MeshDescriptor(name: "bakedChunk")
            descriptor.positions = MeshBuffers.Positions(geo.positions)
            if let normals = geo.normals {
                descriptor.normals = MeshBuffers.Normals(normals)
            }
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(chunk.uvs)
            descriptor.primitives = .triangles(geo.indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }

            var material = UnlitMaterial(color: .init(white: 0.55, alpha: 1.0))
            if let image = chunk.image,
               let texture = try? TextureResource.generate(
                from: image, options: .init(semantic: .color)
               ) {
                material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
            }
            entities.append(ModelEntity(mesh: mesh, materials: [material]))
        }
        return entities
    }

    // MARK: - Textures

    /// Ko'rish uchun teksturalar xotirani tejash maqsadida 768px gacha kichraytiriladi.
    private static let viewerTextureMaxDimension: CGFloat = 768

    private static let textureCIContext = CIContext()

    private static func texture(
        for index: Int,
        keyframes: [KeyframeStore.Keyframe],
        gains: ColorGains?,
        cache: inout [Int: TextureResource]
    ) -> TextureResource? {
        if let cached = cache[index] { return cached }

        guard var ciImage = CIImage(data: keyframes[index].jpegData) else { return nil }

        if let gains, !gains.isNearIdentity {
            ciImage = ColorHarmonizer.apply(gains, to: ciImage)
        }

        let size = ciImage.extent.size
        let scale = min(1.0, viewerTextureMaxDimension / max(size.width, size.height))
        if scale < 1.0 {
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let cgImage = textureCIContext.createCGImage(ciImage, from: ciImage.extent),
              let texture = try? TextureResource.generate(
                from: cgImage,
                options: .init(semantic: .color)
              )
        else { return nil }

        cache[index] = texture
        return texture
    }
}
