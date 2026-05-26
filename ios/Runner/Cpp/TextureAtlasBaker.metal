// TextureAtlasBaker — Per-pixel atlas baking via batched Metal compute.
// xatlas UV unwrap'dan keyin har atlas piksel uchun:
//   1. CPU rasterizatsiyadan world position va normal o'qiladi (textures)
//   2. Cameralar batch-by-batch yuklab, sampling natija accumulator buffer'ga
//   3. Final normalize pass → RGBA8 atlas
//   4. Dilate pass → bilinear filtering uchun chetlarni "bleed"

#include <metal_stdlib>
using namespace metal;

struct AtlasCamera {
    float4x4 invTransform;   // 64 bytes — world → camera-space
    float3x3 intrinsics;     // 48 bytes (3 columns of 16 bytes each)
    float2 imageSize;        // 8
    float2 depthSize;        // 8 (unused but reserved)
    float3 position;         // 16 (12 + 4 pad)
    float3 forward;          // 16
    // Total: 160 bytes (aligned)
};

struct AtlasParams {
    uint cameraCount;
    uint atlasW;
    uint atlasH;
    float minCamAlign;
    float minFaceDot;
    float maxDistance;
    float occlusionTolerance;
    float pad;
};

// Batch kernel — har atlas piksel uchun batch'dagi cameralarni iteratsiya
// qiladi va color/weight accumulators'ga qo'shadi.
kernel void bakeAtlasBatch(
    device float4 *colorAccum   [[buffer(0)]],
    device float  *weightAccum  [[buffer(1)]],
    constant AtlasCamera *cameras [[buffer(2)]],
    constant AtlasParams &params  [[buffer(3)]],
    texture2d<float, access::read> positionTex   [[texture(0)]],
    texture2d<float, access::read> normalTex     [[texture(1)]],
    texture2d_array<float, access::sample> imageArray [[texture(2)]],
    texture2d_array<float, access::sample> depthArray [[texture(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.atlasW || gid.y >= params.atlasH) return;

    float4 posTexel = positionTex.read(gid);
    if (posTexel.w < 0.5) return;  // outside triangle

    float3 worldPos = posTexel.xyz;
    float3 normal = normalize(normalTex.read(gid).xyz);

    constexpr sampler nearestSampler(coord::normalized, filter::nearest, address::clamp_to_edge);
    constexpr sampler linearSampler(coord::normalized, filter::linear, address::clamp_to_edge);

    uint idx = gid.y * params.atlasW + gid.x;
    float3 colorSum = colorAccum[idx].rgb;
    float wSum = weightAccum[idx];

    for (uint i = 0; i < params.cameraCount; ++i) {
        AtlasCamera cam = cameras[i];

        float3 toV = worldPos - cam.position;
        float dist = length(toV);
        if (dist > params.maxDistance || dist < 0.05) continue;
        float3 toVn = toV / dist;
        float camAlign = dot(cam.forward, toVn);
        if (camAlign <= params.minCamAlign) continue;
        float faceDot = dot(normal, -toVn);
        if (faceDot <= params.minFaceDot) continue;

        float4 camSpace = cam.invTransform * float4(worldPos, 1.0);
        float depth = -camSpace.z;
        if (depth <= 0.05) continue;
        float3 proj = cam.intrinsics * float3(camSpace.x, -camSpace.y, depth);
        float pu = proj.x / proj.z;
        float pv = proj.y / proj.z;
        if (pu < 4 || pu >= cam.imageSize.x - 4 || pv < 4 || pv >= cam.imageSize.y - 4) continue;

        // Depth occlusion check
        float2 depthUV = float2(pu / cam.imageSize.x, pv / cam.imageSize.y);
        float sampledDepth = depthArray.sample(nearestSampler, depthUV, i).r;
        if (sampledDepth > 0.05 && depth > sampledDepth + params.occlusionTolerance) continue;

        // Sample image (bilinear)
        float2 imgUV = float2(pu / cam.imageSize.x, pv / cam.imageSize.y);
        float3 color = imageArray.sample(linearSampler, imgUV, i).rgb;

        // POWER weighting — best camera (yaqin + perpendikulyar) MASSIVELY
        // dominate qiladi. Power 8: top camera ~256x kuchliroq → 2-chi camera
        // ta'siri ~0.4%. Faktik top-1 sampling, lekin transitions yumshoq.
        float baseWeight = (camAlign + 0.1) * (faceDot + 0.1) / max(dist * dist, 0.25);
        float w2 = baseWeight * baseWeight;
        float w4 = w2 * w2;
        float weight = w4 * w4;  // power 8
        colorSum += color * weight;
        wSum += weight;
    }

    colorAccum[idx] = float4(colorSum, 0.0);
    weightAccum[idx] = wSum;
}

// Final normalize: accumulated sums → RGBA8 atlas pixel
kernel void normalizeAtlas(
    device const float4 *colorAccum  [[buffer(0)]],
    device const float  *weightAccum [[buffer(1)]],
    texture2d<float, access::read>  positionTex [[texture(0)]],
    texture2d<float, access::write> atlasOut    [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = atlasOut.get_width();
    uint h = atlasOut.get_height();
    if (gid.x >= w || gid.y >= h) return;
    uint idx = gid.y * w + gid.x;

    // Outside triangle → transparent (dilate pass keyin to'ldiradi)
    float4 posTexel = positionTex.read(gid);
    if (posTexel.w < 0.5) {
        atlasOut.write(float4(0.0, 0.0, 0.0, 0.0), gid);
        return;
    }

    float wt = weightAccum[idx];
    if (wt > 0.0001) {
        float3 c = colorAccum[idx].rgb / wt;
        atlasOut.write(float4(saturate(c), 1.0), gid);
    } else {
        // Triangle ichida, lekin hech qaysi cameradan ko'rinmagan → kulrang
        atlasOut.write(float4(0.5, 0.5, 0.5, 1.0), gid);
    }
}

// Dilate pass — chartlar chetlarini "bleed" qilish (bilinear filtering bilan
// SCN qo'shni chart pikselini olishni oldini olishi uchun). 1 piksel padding.
kernel void dilateAtlas(
    texture2d<float, access::read>  atlasIn  [[texture(0)]],
    texture2d<float, access::write> atlasOut [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = atlasIn.get_width();
    uint h = atlasIn.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 c = atlasIn.read(gid);
    if (c.a > 0.5) {
        atlasOut.write(c, gid);
        return;
    }

    float3 sum = float3(0.0);
    float cnt = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            if (dx == 0 && dy == 0) continue;
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;
            if (nx < 0 || nx >= int(w) || ny < 0 || ny >= int(h)) continue;
            float4 n = atlasIn.read(uint2(uint(nx), uint(ny)));
            if (n.a > 0.5) {
                sum += n.rgb;
                cnt += 1.0;
            }
        }
    }
    if (cnt > 0.0) {
        atlasOut.write(float4(sum / cnt, 1.0), gid);
    } else {
        atlasOut.write(float4(0.0, 0.0, 0.0, 0.0), gid);
    }
}
