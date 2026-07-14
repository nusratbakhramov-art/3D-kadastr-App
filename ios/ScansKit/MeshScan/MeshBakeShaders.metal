#include <metal_stdlib>
using namespace metal;

// Har vertex: 8 float — [atlasUV.xy, worldPos.xyz, correction.xyz].
// Tekislangan buferdan vertex_id bo'yicha o'qiladi (alignment muammosi yo'q).

struct BakeUniforms {
    float4x4 invTransform;  // world → camera (keyframe.transform.inverse)
    float4 intrinsics;      // fx, fy, cx, cy
    float4 sizes;           // imageW, imageH, depthW, depthH
    float4 gain;            // gain.rgb, pad
};

struct BakeVertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 correction;
};

vertex BakeVertexOut meshBakeVertex(uint vid [[vertex_id]],
                                    constant float *v [[buffer(0)]],
                                    constant BakeUniforms &u [[buffer(1)]]) {
    uint b = vid * 8;
    float2 atlasUV = float2(v[b], v[b + 1]);
    BakeVertexOut out;
    // atlasUV [0,1] bottom-left → clip [-1,1]. atlasUV.y=1 (tepa) → clip.y=1 (render row 0).
    out.position = float4(atlasUV.x * 2.0 - 1.0, atlasUV.y * 2.0 - 1.0, 0.0, 1.0);
    out.worldPos = float3(v[b + 2], v[b + 3], v[b + 4]);
    out.correction = float3(v[b + 5], v[b + 6], v[b + 7]);
    return out;
}

fragment float4 meshBakeFragment(BakeVertexOut in [[stage_in]],
                                 constant BakeUniforms &u [[buffer(0)]],
                                 texture2d<float> colorTex [[texture(0)]],
                                 texture2d<float> depthTex [[texture(1)]]) {
    float4 pc = u.invTransform * float4(in.worldPos, 1.0);
    float depth = -pc.z;
    if (depth <= 0.05) discard_fragment();

    float fx = u.intrinsics.x, fy = u.intrinsics.y, cx = u.intrinsics.z, cy = u.intrinsics.w;
    float px = fx * pc.x / depth + cx;
    float py = cy - fy * pc.y / depth;
    float imgW = u.sizes.x, imgH = u.sizes.y;
    if (px < 0.0 || px >= imgW || py < 0.0 || py >= imgH) discard_fragment();

    float nu = px / imgW;
    float nv = py / imgH;

    // Occlusion: LiDAR depth bilan tekshirish
    constexpr sampler ds(coord::normalized, filter::nearest, address::clamp_to_edge);
    float stored = depthTex.sample(ds, float2(nu, nv)).r;
    if (stored > 0.05 && stored + max(0.08, depth * 0.08) < depth) discard_fragment();

    constexpr sampler cs(coord::normalized, filter::linear, address::clamp_to_edge);
    float3 c = colorTex.sample(cs, float2(nu, nv)).rgb;
    c = clamp(c * u.gain.rgb + in.correction, 0.0, 1.0);
    return float4(c, 1.0);
}
