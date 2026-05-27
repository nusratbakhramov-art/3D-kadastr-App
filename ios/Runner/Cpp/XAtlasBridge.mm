// XAtlasBridge — Objective-C++ implementation. xatlas.cpp shu yerda compile
// qilinadi (#include orqali) — alohida fayl sifatida pbxproj'ga qo'shilmaydi.

#import "XAtlasBridge.h"
#include "xatlas.h"

// xatlas internal logger — bizga kerakmas. Silence.
static int XAtlasPrintLog(const char *format, ...) {
    (void)format;
    return 0;
}

@implementation XAtlasResult

- (instancetype)initWithWidth:(NSUInteger)w
                       height:(NSUInteger)h
                  vertexCount:(NSUInteger)vc
                   indexCount:(NSUInteger)ic
                    positions:(NSData *)pos
                      normals:(NSData *)nrm
                          uvs:(NSData *)uvs
                      indices:(NSData *)idx
              originalIndices:(NSData *)origIdx {
    if ((self = [super init])) {
        _atlasWidth = w;
        _atlasHeight = h;
        _vertexCount = vc;
        _indexCount = ic;
        _positions = pos;
        _normals = nrm;
        _uvs = uvs;
        _indices = idx;
        _originalIndices = origIdx;
    }
    return self;
}

@end

@implementation XAtlasBridge

+ (XAtlasResult *)unwrapMeshWithPositions:(NSData *)positions
                                  normals:(NSData *)normals
                                  indices:(NSData *)indices
                              vertexCount:(NSUInteger)vertexCount
                            triangleCount:(NSUInteger)triangleCount
                          atlasResolution:(uint32_t)atlasResolution
                                    error:(NSError **)error {
    if (vertexCount == 0 || triangleCount == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"XAtlasBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty mesh"}];
        }
        return nil;
    }
    if (positions.length < vertexCount * 3 * sizeof(float)) {
        if (error) {
            *error = [NSError errorWithDomain:@"XAtlasBridge" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Positions data too small"}];
        }
        return nil;
    }

    xatlas::Atlas *atlas = xatlas::Create();
    xatlas::SetPrint(XAtlasPrintLog, false);

    xatlas::MeshDecl meshDecl;
    meshDecl.vertexCount = (uint32_t)vertexCount;
    meshDecl.vertexPositionData = positions.bytes;
    meshDecl.vertexPositionStride = 3 * sizeof(float);
    if (normals.length >= vertexCount * 3 * sizeof(float)) {
        meshDecl.vertexNormalData = normals.bytes;
        meshDecl.vertexNormalStride = 3 * sizeof(float);
    }
    meshDecl.indexCount = (uint32_t)(triangleCount * 3);
    meshDecl.indexData = indices.bytes;
    meshDecl.indexFormat = xatlas::IndexFormat::UInt32;

    xatlas::AddMeshError addErr = xatlas::AddMesh(atlas, meshDecl, 1);
    if (addErr != xatlas::AddMeshError::Success) {
        xatlas::Destroy(atlas);
        if (error) {
            *error = [NSError errorWithDomain:@"XAtlasBridge" code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                  [NSString stringWithFormat:@"AddMesh failed: %s",
                                                                              xatlas::StringForEnum(addErr)]}];
        }
        return nil;
    }

    // Phase 9.3: Atlas chart parametrlari — KAMROQ lekin KATTAROQ chart'lar.
    // Eski sozlamada chart'lar juda kichik bo'lib ketadi → renderda fragment
    // ko'rinishi. Quyidagi tweak'lar bilan algoritm triangle'larni ko'proq
    // birgalikda guruhlaydi:
    xatlas::ChartOptions chartOptions;
    chartOptions.maxCost = 8.0f;             // default 2 → 8: yomon-roq chart'lar ham qo'shilsin
    chartOptions.maxIterations = 3;          // default 1 → 3: charts'larni qayta-qayta birlashtir
    chartOptions.normalDeviationWeight = 1.0f;  // default 2: normal farqlarga kamroq sezgir
    chartOptions.normalSeamWeight = 2.0f;       // default 4: normal seam penalty kamroq

    xatlas::PackOptions packOptions;
    packOptions.resolution = atlasResolution;
    packOptions.padding = 4;       // 2 → 4: kengroq border, bilinear filtering safe
    packOptions.bilinear = true;
    packOptions.blockAlign = false;
    packOptions.bruteForce = false; // BURUFORCE 20min+ olardi 200k tri'da
    packOptions.texelsPerUnit = 0;

    xatlas::Generate(atlas, chartOptions, packOptions);

    if (atlas->meshCount == 0) {
        xatlas::Destroy(atlas);
        if (error) {
            *error = [NSError errorWithDomain:@"XAtlasBridge" code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"No output meshes"}];
        }
        return nil;
    }

    // Output (1 ta input mesh → 1 ta output mesh)
    const xatlas::Mesh &out = atlas->meshes[0];
    const uint32_t outVC = out.vertexCount;
    const uint32_t outIC = out.indexCount;

    // Pre-allocate output buffers
    NSMutableData *outPos = [NSMutableData dataWithLength:outVC * 3 * sizeof(float)];
    NSMutableData *outNrm = [NSMutableData dataWithLength:outVC * 3 * sizeof(float)];
    NSMutableData *outUV = [NSMutableData dataWithLength:outVC * 2 * sizeof(float)];
    NSMutableData *outIdx = [NSMutableData dataWithLength:outIC * sizeof(uint32_t)];
    NSMutableData *outOrig = [NSMutableData dataWithLength:outVC * sizeof(uint32_t)];

    const float *inPos = (const float *)positions.bytes;
    const float *inNrm = (normals.length >= vertexCount * 3 * sizeof(float))
                        ? (const float *)normals.bytes : nullptr;

    float *posData = (float *)outPos.mutableBytes;
    float *nrmData = (float *)outNrm.mutableBytes;
    float *uvData = (float *)outUV.mutableBytes;
    uint32_t *origData = (uint32_t *)outOrig.mutableBytes;

    const float aw = (float)atlas->width;
    const float ah = (float)atlas->height;
    const float invW = aw > 0 ? 1.0f / aw : 0.0f;
    const float invH = ah > 0 ? 1.0f / ah : 0.0f;

    for (uint32_t i = 0; i < outVC; ++i) {
        const xatlas::Vertex &v = out.vertexArray[i];
        const uint32_t origIdx = v.xref;
        origData[i] = origIdx;

        if (origIdx < vertexCount) {
            posData[i * 3 + 0] = inPos[origIdx * 3 + 0];
            posData[i * 3 + 1] = inPos[origIdx * 3 + 1];
            posData[i * 3 + 2] = inPos[origIdx * 3 + 2];
            if (inNrm) {
                nrmData[i * 3 + 0] = inNrm[origIdx * 3 + 0];
                nrmData[i * 3 + 1] = inNrm[origIdx * 3 + 1];
                nrmData[i * 3 + 2] = inNrm[origIdx * 3 + 2];
            } else {
                nrmData[i * 3 + 0] = 0.0f;
                nrmData[i * 3 + 1] = 1.0f;
                nrmData[i * 3 + 2] = 0.0f;
            }
        }

        // xatlas uv is in pixel coords [0..atlasWidth/Height]. Normalize to [0..1].
        uvData[i * 2 + 0] = v.uv[0] * invW;
        uvData[i * 2 + 1] = v.uv[1] * invH;
    }

    memcpy(outIdx.mutableBytes, out.indexArray, outIC * sizeof(uint32_t));

    const uint32_t aWidth = atlas->width;
    const uint32_t aHeight = atlas->height;

    xatlas::Destroy(atlas);

    return [[XAtlasResult alloc] initWithWidth:aWidth
                                        height:aHeight
                                   vertexCount:outVC
                                    indexCount:outIC
                                     positions:outPos
                                       normals:outNrm
                                           uvs:outUV
                                       indices:outIdx
                               originalIndices:outOrig];
}

@end
