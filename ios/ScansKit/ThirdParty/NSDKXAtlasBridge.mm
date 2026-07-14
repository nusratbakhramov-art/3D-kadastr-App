#import "NSDKXAtlasBridge.h"
#import "xatlas/xatlas.h"

@implementation NSDKXAtlasResult
@end

@implementation NSDKXAtlasBridge

+ (nullable NSDKXAtlasResult *)generateWithPositions:(const float *)positions
                                     vertexCount:(uint32_t)vertexCount
                                         indices:(const uint32_t *)indices
                                      indexCount:(uint32_t)indexCount
                                      resolution:(uint32_t)resolution {
    if (vertexCount == 0 || indexCount < 3) return nil;

    xatlas::Atlas *atlas = xatlas::Create();

    xatlas::MeshDecl decl;
    decl.vertexCount = vertexCount;
    decl.vertexPositionData = positions;
    decl.vertexPositionStride = sizeof(float) * 3;
    decl.indexCount = indexCount;
    decl.indexData = indices;
    decl.indexFormat = xatlas::IndexFormat::UInt32;

    xatlas::AddMeshError err = xatlas::AddMesh(atlas, decl, 1);
    if (err != xatlas::AddMeshError::Success) {
        xatlas::Destroy(atlas);
        return nil;
    }

    xatlas::ChartOptions chartOptions;
    xatlas::PackOptions packOptions;
    packOptions.resolution = resolution;
    packOptions.padding = 4;
    packOptions.bilinear = true;

    xatlas::Generate(atlas, chartOptions, packOptions);

    // Bitta atlasga sig'dirish: chart'lar ikkinchi atlasga oshib ketsa,
    // texel zichligini kamaytirib qayta pack qilamiz.
    int attempts = 0;
    while (atlas->atlasCount > 1 && attempts < 4) {
        packOptions.texelsPerUnit = atlas->texelsPerUnit * 0.8f;
        xatlas::PackCharts(atlas, packOptions);
        attempts++;
    }

    if (atlas->meshCount < 1 || atlas->atlasCount > 1) {
        xatlas::Destroy(atlas);
        return nil;
    }

    const xatlas::Mesh &mesh = atlas->meshes[0];

    NSDKXAtlasResult *result = [NSDKXAtlasResult new];
    result.width = atlas->width;
    result.height = atlas->height;
    result.vertexCount = mesh.vertexCount;
    result.indexCount = mesh.indexCount;

    NSMutableData *uvs = [NSMutableData dataWithLength:(NSUInteger)mesh.vertexCount * 2 * sizeof(float)];
    NSMutableData *xrefs = [NSMutableData dataWithLength:(NSUInteger)mesh.vertexCount * sizeof(uint32_t)];
    float *uvPtr = (float *)uvs.mutableBytes;
    uint32_t *xrefPtr = (uint32_t *)xrefs.mutableBytes;
    for (uint32_t i = 0; i < mesh.vertexCount; i++) {
        uvPtr[i * 2] = mesh.vertexArray[i].uv[0];
        uvPtr[i * 2 + 1] = mesh.vertexArray[i].uv[1];
        xrefPtr[i] = mesh.vertexArray[i].xref;
    }
    result.uvs = uvs;
    result.xrefs = xrefs;
    result.indices = [NSData dataWithBytes:mesh.indexArray
                                    length:(NSUInteger)mesh.indexCount * sizeof(uint32_t)];

    xatlas::Destroy(atlas);
    return result;
}

@end
