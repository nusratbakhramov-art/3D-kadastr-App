#include <metal_stdlib>
using namespace metal;

// 3D Gaussian Splatting forward render (Kerbl va b. 2023).
// Har splat billboard-quadga yoyiladi; 3D kovariatsiya 2D konusga proyeksiya
// qilinadi, fragment gaussian alpha hisoblaydi. Chuqurlik bo'yicha saralangan
// (back-to-front) alpha-blend.

struct SplatUniforms {
    float4x4 view;        // world → camera
    float4   proj;        // fx, fy, cx, cy (piksel)
    float2   viewport;    // W, H (piksel)
    float2   pad;
};

// Splat buferi (GaussianSplat bilan mos, tekislangan)
struct SplatIn {
    packed_float3 position;
    packed_float3 logScale;
    packed_float4 rotation;   // x,y,z,w
    float         opacityLogit;
    packed_float3 shDC;
};

struct SplatOut {
    float4 position [[position]];
    float2 center;     // ekran markazi (piksel)
    float3 conic;      // 2D konus (a, b, c) — teskari kovariatsiya
    float3 color;      // ko'rsatiladigan rang (0..1)
    float  opacity;    // 0..1
    float2 delta;      // quad burchagining markazdan siljishi (piksel)
};

static inline float sigmoidf(float x) { return 1.0 / (1.0 + exp(-x)); }

// Kvaterniondan 3x3 aylanish
static inline float3x3 quatToMat(float4 q) {
    float x = q.x, y = q.y, z = q.z, w = q.w;
    return float3x3(
        float3(1 - 2*(y*y+z*z), 2*(x*y+w*z),     2*(x*z-w*y)),
        float3(2*(x*y-w*z),     1 - 2*(x*x+z*z), 2*(y*z+w*x)),
        float3(2*(x*z+w*y),     2*(y*z-w*x),     1 - 2*(x*x+y*y))
    );
}

vertex SplatOut splatVertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            constant SplatIn* splats [[buffer(0)]],
                            constant uint* sortedIndices [[buffer(1)]],
                            constant SplatUniforms& U [[buffer(2)]]) {
    SplatOut out;
    out.opacity = 0;
    out.color = float3(0);
    out.center = float2(0);
    out.conic = float3(0);
    out.delta = float2(0);
    out.position = float4(0, 0, 2, 1); // clip tashqarisi (default ko'rinmas)

    uint si = sortedIndices[iid];
    SplatIn s = splats[si];

    // Kamera fazosi
    float4 pc = U.view * float4(s.position, 1.0);
    if (pc.z >= -0.05) return out;   // orqada yoki juda yaqin
    float depth = -pc.z;

    float fx = U.proj.x, fy = U.proj.y, cx = U.proj.z, cy = U.proj.w;

    // 3D kovariatsiya Σ = R S S^T R^T
    float3 sc = exp(float3(s.logScale));
    float3x3 R = quatToMat(normalize(s.rotation));
    float3x3 S = float3x3(float3(sc.x,0,0), float3(0,sc.y,0), float3(0,0,sc.z));
    float3x3 M = R * S;
    float3x3 Sigma = M * transpose(M);

    // Proyeksiya Jacobiani (kamera fazosida)
    float3x3 W = float3x3(U.view[0].xyz, U.view[1].xyz, U.view[2].xyz);
    float z = pc.z; // manfiy
    float3x3 J = float3x3(
        float3(fx / z, 0, 0),
        float3(0, fy / z, 0),
        float3(-fx * pc.x / (z*z), -fy * pc.y / (z*z), 0)
    );
    float3x3 T = J * W;
    float3x3 cov3 = T * Sigma * transpose(T);
    // 2D kovariatsiya (yuqori-chap 2x2) + kichik regularizatsiya
    float a = cov3[0][0] + 0.3;
    float b = cov3[0][1];
    float c = cov3[1][1] + 0.3;

    float det = a * c - b * b;
    if (det <= 1e-9) return out;
    float invDet = 1.0 / det;
    // Konus = teskari kovariatsiya
    float3 conic = float3(c * invDet, -b * invDet, a * invDet);

    // Radius (3 sigma) — quad o'lchami
    float mid = 0.5 * (a + c);
    float lambda = mid + sqrt(max(0.1, mid*mid - det));
    float radius = 3.0 * sqrt(lambda);

    // Ekran markazi (piksel; y pastdan yuqoriga clip uchun keyin aylantiramiz)
    float2 center = float2(fx * pc.x / depth + cx, cy - fy * pc.y / depth);

    // Quad burchagi (vid: 0..5 → 2 uchburchak)
    float2 corner;
    switch (vid) {
        case 0: corner = float2(-1, -1); break;
        case 1: corner = float2( 1, -1); break;
        case 2: corner = float2( 1,  1); break;
        case 3: corner = float2(-1, -1); break;
        case 4: corner = float2( 1,  1); break;
        default: corner = float2(-1,  1); break;
    }
    float2 delta = corner * radius;
    float2 pix = center + delta;

    // Piksel → clip (-1..1), y ni aylantiramiz
    float2 clip = float2(pix.x / U.viewport.x * 2.0 - 1.0,
                         1.0 - pix.y / U.viewport.y * 2.0);

    out.position = float4(clip, 0.0, 1.0);
    out.center = center;
    out.conic = conic;
    out.opacity = sigmoidf(s.opacityLogit);
    out.color = clamp(0.5 + 0.28209479 * float3(s.shDC), 0.0, 1.0);
    out.delta = delta;
    return out;
}

fragment float4 splatFragment(SplatOut in [[stage_in]]) {
    float2 d = in.delta;
    float power = -0.5 * (in.conic.x * d.x * d.x
                          + 2.0 * in.conic.y * d.x * d.y
                          + in.conic.z * d.y * d.y);
    if (power > 0.0) discard_fragment();
    float alpha = in.opacity * exp(power);
    if (alpha < 0.004) discard_fragment();
    alpha = min(alpha, 0.99);
    // Premultiplied alpha (back-to-front over-blend)
    return float4(in.color * alpha, alpha);
}
