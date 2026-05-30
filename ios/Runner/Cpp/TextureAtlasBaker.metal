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
    // Phase 3.3 view-dependent blending: per-photo sharpness [0..1]
    // + 12 bytes pad to keep 16-byte alignment.
    float sharpness;         // 4
    // Phase 16: per-camera exposure/WB gain (pad o'rniga). Sample rangga ko'paytiriladi.
    float gainR, gainG, gainB;  // 12 → total camera struct 176 bytes
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
    float viewPower;  // Phase 17b: soft best-view exponent (score^viewPower weight)
};

// Batch kernel — har atlas piksel uchun batch'dagi cameralarni iteratsiya
// qiladi va color/weight accumulators'ga qo'shadi.
kernel void bakeAtlasBatch(
    device float4 *colorAccum   [[buffer(0)]],
    device float  *weightAccum  [[buffer(1)]],
    constant AtlasCamera *cameras [[buffer(2)]],
    constant AtlasParams &params  [[buffer(3)]],
    device float4 *bestAccum    [[buffer(4)]],  // Multi-band: rgb=bestColor, a=bestScore
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
    // Multi-band: ikkala akkumulyatsiya bir vaqtda —
    //  (1) O'RTACHA (past chastota base, seamless): colorAccum=Σ(c·w), weightAccum=Σw.
    //      Ko'p kamera o'rtalanadi → exposure/rang silliq, seam yo'q (lekin blur).
    //  (2) BEST-VIEW (yuqori chastota detail, sharp): bestAccum rgb=eng yaxshi
    //      kamera rangi, a=eng katta score. Bitta sharp kamera → tiniq detail.
    // Combine bosqichida: final = blur(avg) + (best − blur(best)).
    float3 avgSum = colorAccum[idx].rgb;
    float avgW = weightAccum[idx];
    float4 bestPrev = bestAccum[idx];
    float bestScore = bestPrev.a;
    float3 bestColor = bestPrev.rgb;

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

        // Depth occlusion — to'liq rad etish O'RNIGA og'ir penalty. Non-occluded
        // kamera 50x g'olib; lekin agar texel'ni FAQAT occluded kameralar ko'rsa,
        // eng yaxshi occluded rang olinadi (qora teshik/voxel o'rniga).
        float2 depthUV = float2(pu / cam.imageSize.x, pv / cam.imageSize.y);
        float sampledDepth = depthArray.sample(nearestSampler, depthUV, i).r;
        float occlPenalty = 1.0;
        if (sampledDepth > 0.05 && depth > sampledDepth + params.occlusionTolerance) {
            // params.pad = hardOcclusion flag (clean room): occluded kamerani TO'LIQ rad et
            // (mebel devorга proyeksiya bo'lmasin; devorni to'g'ridan ko'rgan kamera yoki fallback).
            if (params.pad > 0.5) { continue; }
            occlPenalty = 0.02;
        }

        // Sample image (bilinear)
        float2 imgUV = float2(pu / cam.imageSize.x, pv / cam.imageSize.y);
        float3 color = imageArray.sample(linearSampler, imgUV, i).rgb;
        // Phase 16: per-camera exposure/WB gain — fotolar rang jihatdan moslanadi (choklar yo'qoladi).
        color = clamp(color * float3(cam.gainR, cam.gainG, cam.gainB), 0.0, 1.0);

        // Phase 3.3: glare/specular detection. Agar pixel deyarli oq (RGB
        // ham yuqori, ham balanced) — bu mat yuza emas, ko'zgu/spekulyar.
        // luma = max channel. Saturate'ga yaqin bo'lsa, weight kamayadi.
        // Diffuse oq devor ham bo'lishi mumkin — shu sababli butunlay
        // tashlamaymiz, faqat weight'ni yumshatamiz (0.3x at full glare).
        float luma = max(color.r, max(color.g, color.b));
        float glareReduction = 1.0 - 0.7 * smoothstep(0.92, 0.99, luma);

        // Selection score — qaysi kamera bu nuqtani "eng yaxshi" ko'radi:
        // face-on (camAlign·faceDot), yaqin (1/dist²), sharp, glare'siz.
        float score = (camAlign + 0.1) * (faceDot + 0.1) / max(dist * dist, 0.25);
        score *= (cam.sharpness + 0.1);
        score *= glareReduction;
        score *= occlPenalty;  // occluded → 50x kichik, lekin >0 (teshik to'ldiriladi)

        // (1) Phase 17b: SOFT best-view base — tunable power weight (score^viewPower).
        // power 2 (eski) juda silliq edi → blur. Yuqori power (4..8): region ICHIDA
        // eng yaxshi kamera dominant (2x score → 2^P x weight → sharp, best-view kabi
        // tiniq), region CHEGARASIDA 2 kamera score yaqin → silliq blend (best-view'ning
        // keskin argmax seam/konsentrik naqshi YO'QOLADI). Detail + chok yo'q balansi
        // viewPower bilan: past=tiniqroq(biroz seam), yuqori=silliqroq(seamless).
        float wBase = pow(max(score, 1e-8), params.viewPower);
        avgSum += color * wBase;
        avgW += wBase;

        // (2) Best-view detail uchun — eng katta score'li kamerani saqlash (argmax).
        if (score > bestScore) {
            bestScore = score;
            bestColor = color;
        }
    }

    colorAccum[idx] = float4(avgSum, 0.0);
    weightAccum[idx] = avgW;
    bestAccum[idx] = float4(bestColor, bestScore);
}

// Voxel grid params (matches StreamingTSDF layout). Used for color fallback.
struct VoxelParams {
    float originX, originY, originZ, voxelSize;
    uint  gridX, gridY, gridZ, hasVoxelColor;  // hasVoxelColor: 0/1 flag
};

// Voxel color fallback — TRILINEAR (8-corner) interpolation. Atlas piksel hech
// qaysi cameradan rang olmaganda StreamingTSDF voxel grid'dan rang oladi.
// outColor'ga rang yozadi va true qaytaradi; voxel ham bo'sh bo'lsa false.
static bool sampleVoxelColor(device const float4 *voxelColor,
                             constant VoxelParams &vparams,
                             float3 worldPos,
                             thread float3 &outColor) {
    if (vparams.hasVoxelColor == 0) return false;
    float3 origin = float3(vparams.originX, vparams.originY, vparams.originZ);
    float3 local = (worldPos - origin) / vparams.voxelSize - 0.5;
    int x0 = int(floor(local.x));
    int y0 = int(floor(local.y));
    int z0 = int(floor(local.z));
    float fx = local.x - float(x0);
    float fy = local.y - float(y0);
    float fz = local.z - float(z0);

    float3 colorSum = float3(0.0);
    float weightSum = 0.0;
    for (int dz = 0; dz < 2; ++dz) {
        for (int dy = 0; dy < 2; ++dy) {
            for (int dx = 0; dx < 2; ++dx) {
                int vx = x0 + dx;
                int vy = y0 + dy;
                int vz = z0 + dz;
                if (vx < 0 || vx >= int(vparams.gridX) ||
                    vy < 0 || vy >= int(vparams.gridY) ||
                    vz < 0 || vz >= int(vparams.gridZ)) continue;
                uint vidx = uint(vx) + uint(vy) * vparams.gridX + uint(vz) * vparams.gridX * vparams.gridY;
                float4 vc = voxelColor[vidx];
                if (vc.a <= 0.5) continue;
                float wx = (dx == 0) ? (1.0 - fx) : fx;
                float wy = (dy == 0) ? (1.0 - fy) : fy;
                float wz = (dz == 0) ? (1.0 - fz) : fz;
                float w = wx * wy * wz;
                colorSum += vc.rgb * w;
                weightSum += w;
            }
        }
    }
    if (weightSum > 0.05) {
        float3 c = saturate(colorSum / weightSum);
        // Voxel TSDF ko'k artefakt (depth edge/noise integration) → neytral kulrang.
        // Real ssenada to'yingan ko'k yo'q (devor oq, divan jigarrang, pol kulrang),
        // shuning uchun b>>r,g voxel = artefakt, real rang emas.
        if (c.b > c.r + 0.12 && c.b > c.g + 0.10) {
            c = float3(dot(c, float3(0.299, 0.587, 0.114)));
        }
        outColor = c;
        return true;
    }
    return false;
}

// Final normalize: accumulated sums → RGBA8 atlas pixel.
// Variant A Phase 2 — agar atlas piksel hech qaysi cameradan rang olmagan
// (wt=0), StreamingTSDF voxel grid'dan rang olishga harakat qilamiz. Gray
// fallback faqat voxel ham bo'sh bo'lsa.
kernel void normalizeAtlas(
    device const float4 *colorAccum   [[buffer(0)]],
    device const float  *weightAccum  [[buffer(1)]],
    device const float4 *voxelColor   [[buffer(2)]],  // optional voxel color
    constant VoxelParams &vparams     [[buffer(3)]],  // voxel grid params
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
        // Multi-band: o'rtacha base (past chastota uchun) — Σ(c·w)/Σw. Seamless.
        float3 c = colorAccum[idx].rgb / wt;
        atlasOut.write(float4(saturate(c), 1.0), gid);
        return;
    }

    // Camera coverage yo'q — voxel color fallback (trilinear).
    float3 voxColor;
    if (sampleVoxelColor(voxelColor, vparams, posTexel.xyz, voxColor)) {
        atlasOut.write(float4(voxColor, 1.0), gid);
        return;
    }

    // Hech narsa topilmadi — kulrang fallback
    atlasOut.write(float4(0.5, 0.5, 0.5, 1.0), gid);
}

// Multi-band: BEST-VIEW atlas — bestAccum (eng yaxshi kamera rangi) → RGBA8.
// Yuqori chastota (sharp detail) manbasi. Coverage yo'q joyda voxel fallback.
kernel void normalizeBest(
    device const float4 *bestAccum    [[buffer(0)]],  // rgb=color, a=score
    device const float4 *voxelColor   [[buffer(2)]],
    constant VoxelParams &vparams     [[buffer(3)]],
    texture2d<float, access::read>  positionTex [[texture(0)]],
    texture2d<float, access::write> atlasOut    [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = atlasOut.get_width();
    uint h = atlasOut.get_height();
    if (gid.x >= w || gid.y >= h) return;
    uint idx = gid.y * w + gid.x;

    float4 posTexel = positionTex.read(gid);
    if (posTexel.w < 0.5) {
        atlasOut.write(float4(0.0, 0.0, 0.0, 0.0), gid);
        return;
    }

    float4 best = bestAccum[idx];
    if (best.a > 0.0001) {
        atlasOut.write(float4(saturate(best.rgb), 1.0), gid);
        return;
    }

    float3 voxColor;
    if (sampleVoxelColor(voxelColor, vparams, posTexel.xyz, voxColor)) {
        atlasOut.write(float4(voxColor, 1.0), gid);
        return;
    }
    atlasOut.write(float4(0.5, 0.5, 0.5, 1.0), gid);
}

// Multi-band combine — past chastota (seamless) + yuqori chastota (sharp).
//   final = blur(avg) + (best − blur(best))
// blur(avg): exposure/rang silliq base (seam yo'q). (best − blur(best)): faqat
// yuqori chastota detail (yozuv, plitka chizig'i) — sharp kameradan. best'ning
// past-chastota seam'i (best − blur(best)) da bekor bo'ladi.
kernel void multiBandCombine(
    texture2d<float, access::read> avgLow   [[texture(0)]],  // blur(avg)
    texture2d<float, access::read> bestTex  [[texture(1)]],  // best (sharp)
    texture2d<float, access::read> bestLow  [[texture(2)]],  // blur(best)
    texture2d<float, access::write> outTex  [[texture(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = outTex.get_width();
    uint h = outTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 b = bestTex.read(gid);
    if (b.a < 0.5) {
        // Chart tashqarisi — transparent qoldiramiz (dilate keyin to'ldiradi).
        outTex.write(float4(0.0, 0.0, 0.0, 0.0), gid);
        return;
    }
    float3 a = avgLow.read(gid).rgb;
    float3 bl = bestLow.read(gid).rgb;
    float3 high = b.rgb - bl;          // yuqori chastota detail (lumin + chroma)
    // Chromatik high-freq = turli kamera WB/exposure farqi → rangli seam + ko'k
    // overshoot. Luminance high-freq = haqiqiy detail (qirra/tekstura). Faqat
    // luminance'ni to'liq, chroma'ni 0.3x saqlaymiz: seam yo'qoladi, detail qoladi.
    // (Real ssenada chroma detail kam — devor oq, divan bir xil jigarrang.)
    float highLum = dot(high, float3(0.299, 0.587, 0.114));
    float3 final = a + highLum + (high - highLum) * 0.3;
    outTex.write(float4(saturate(final), 1.0), gid);
}

// Phase 17: Poisson-style seam leveling uchun KENG separable Gaussian.
// 3x3 smoothAtlas (radius~1) past-chastota seam'ni (chart ichida o'nlab-yuzlab
// piksel kenglikdagi exposure/rang sakrashi) ajrata olmaydi. Bu kernel katta
// radius (sigma~R/2) bilan bitta o'qda blur qiladi — H + V ketma-ket =
// separable 2D Gaussian. Chart-aware: alpha<0.5 (chart tashqarisi) qo'shni
// HISSA QO'SHMAYDI (cross-chart bleed yo'q) va markaz tegilmaydi.
struct WideBlurParams {
    uint radius;
    uint direction;  // 0 = horizontal, 1 = vertical
    uint pad0;
    uint pad1;
};

kernel void blurSeparableWide(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant WideBlurParams &bp [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = inTex.get_width();
    uint h = inTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 c = inTex.read(gid);
    if (c.a < 0.5) {
        // Chart tashqarisi — o'zgartirmaymiz (dilate keyin to'ldiradi).
        outTex.write(c, gid);
        return;
    }

    int R = int(bp.radius);
    float sigma = max(1.0, float(R) * 0.5);
    float inv2s2 = 1.0 / (2.0 * sigma * sigma);
    float3 sum = float3(0.0);
    float wSum = 0.0;
    for (int t = -R; t <= R; ++t) {
        int nx = int(gid.x) + (bp.direction == 0 ? t : 0);
        int ny = int(gid.y) + (bp.direction == 0 ? 0 : t);
        if (nx < 0 || nx >= int(w) || ny < 0 || ny >= int(h)) continue;
        float4 n = inTex.read(uint2(uint(nx), uint(ny)));
        if (n.a < 0.5) continue;  // chart boundary — cross qilmaymiz
        float k = exp(-float(t * t) * inv2s2);
        sum += n.rgb * k;
        wSum += k;
    }
    outTex.write(float4(wSum > 0.0 ? sum / wSum : c.rgb, 1.0), gid);
}

// Phase 4.3: Bilateral Gaussian smoothing — atlas pixel'larini qo'shnilar
// bilan blend qiladi, lekin chart boundary'larida (alpha = 0) cross qilmaydi.
// Multi-view overlap seam'larini sezilmaydigan qilish. 3x3 Gaussian kernel,
// faqat alpha=1 pixel'lar hissa qo'shadi (chart cross-bleed yo'q).
kernel void smoothAtlas(
    texture2d<float, access::read>  atlasIn  [[texture(0)]],
    texture2d<float, access::write> atlasOut [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = atlasIn.get_width();
    uint h = atlasIn.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 center = atlasIn.read(gid);
    if (center.a < 0.5) {
        // Outside chart — leave as-is (dilate already filled neighbors).
        atlasOut.write(center, gid);
        return;
    }

    // 3x3 Gaussian kernel (sum=16):
    //   1 2 1
    //   2 4 2
    //   1 2 1
    const float gw[9] = {1, 2, 1,
                         2, 4, 2,
                         1, 2, 1};
    float3 sum = float3(0.0);
    float wSum = 0.0;
    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;
            if (nx < 0 || nx >= int(w) || ny < 0 || ny >= int(h)) continue;
            float4 n = atlasIn.read(uint2(uint(nx), uint(ny)));
            if (n.a < 0.5) continue;  // skip chart boundary
            float kw = gw[(dy + 1) * 3 + (dx + 1)];
            sum += n.rgb * kw;
            wSum += kw;
        }
    }
    if (wSum > 0.0) {
        atlasOut.write(float4(sum / wSum, 1.0), gid);
    } else {
        atlasOut.write(center, gid);
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
