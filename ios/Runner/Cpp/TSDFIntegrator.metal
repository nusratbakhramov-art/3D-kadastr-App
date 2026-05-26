// TSDFIntegrator — Truncated Signed Distance Function volumetric reconstruction.
//
// Har voxel uchun: world-space pozitsiya → camera-space → image projection →
// observed depth (LiDAR) → SDF value (signed distance to nearest surface).
// Bir nechta photo'lar bo'yicha weighted average — multi-view fusion.

#include <metal_stdlib>
using namespace metal;

struct TSDFParams {
    // Flat layout (avoiding float3 16-byte alignment mismatch with Swift).
    float originX, originY, originZ, voxelSize;     // 16 bytes
    uint  gridX, gridY, gridZ, pad1;                // 16 bytes
    float truncation, maxIntegrationDepth, pad2, pad3;  // 16 bytes
};

struct TSDFCamera {
    float4x4 invTransform;   // world → camera
    float3x3 intrinsics;     // camera-space → image pixel
    float2 imageSize;        // depth map size (we use LiDAR depth directly)
};

// 3D thread per voxel. updates SDF + weight via running average.
kernel void integrateDepth(
    device float *sdfVolume    [[buffer(0)]],
    device float *weightVolume [[buffer(1)]],
    constant TSDFParams &params [[buffer(2)]],
    constant TSDFCamera &cam    [[buffer(3)]],
    texture2d<float, access::sample> depthMap [[texture(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.gridX || gid.y >= params.gridY || gid.z >= params.gridZ) return;

    // World position of voxel center
    float3 origin = float3(params.originX, params.originY, params.originZ);
    float3 worldPos = origin + (float3(gid) + 0.5) * params.voxelSize;

    // To camera-space
    float4 camSpace = cam.invTransform * float4(worldPos, 1.0);
    float depthVoxel = -camSpace.z;  // ARKit camera basis: forward = -Z
    if (depthVoxel <= 0.05 || depthVoxel > params.maxIntegrationDepth) return;

    // Project to image pixel
    float3 proj = cam.intrinsics * float3(camSpace.x, -camSpace.y, depthVoxel);
    float pu = proj.x / proj.z;
    float pv = proj.y / proj.z;
    if (pu < 0 || pv < 0 || pu >= cam.imageSize.x || pv >= cam.imageSize.y) return;

    // Sample observed depth (nearest filter — LiDAR is low-res but precise)
    constexpr sampler s(coord::normalized, filter::nearest, address::clamp_to_edge);
    float u = pu / cam.imageSize.x;
    float v = pv / cam.imageSize.y;
    float depthObs = depthMap.sample(s, float2(u, v)).r;
    if (depthObs <= 0.05) return;  // invalid LiDAR sample (hole)

    // SDF: positive = voxel in front of surface (empty), negative = behind (solid)
    float sdf = depthObs - depthVoxel;

    // Skip voxels far behind surface (probably not relevant)
    if (sdf < -params.truncation) return;

    // Clamp to truncation range, normalize to [-1, +1]
    sdf = clamp(sdf, -params.truncation, params.truncation) / params.truncation;

    // Weighted running average (per-pixel weight = 1.0 for now)
    uint idx = gid.x + gid.y * params.gridX + gid.z * params.gridX * params.gridY;
    float prevSDF = sdfVolume[idx];
    float prevW = weightVolume[idx];
    float newW = prevW + 1.0;
    sdfVolume[idx] = (prevSDF * prevW + sdf) / newW;
    weightVolume[idx] = newW;
}

// Optional smoothing kernel — 3x3x3 weighted average (Gaussian-like)
// Voxel'lar orasidagi shovqinni kamaytirish uchun marching cubes'dan oldin.
kernel void smoothSDF(
    device const float *sdfIn  [[buffer(0)]],
    device const float *wIn    [[buffer(1)]],
    device float *sdfOut       [[buffer(2)]],
    constant TSDFParams &params [[buffer(3)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.gridX || gid.y >= params.gridY || gid.z >= params.gridZ) return;
    uint idx = gid.x + gid.y * params.gridX + gid.z * params.gridX * params.gridY;

    if (wIn[idx] < 0.5) {
        sdfOut[idx] = sdfIn[idx];
        return;
    }

    float sum = 0.0;
    float w = 0.0;
    for (int dz = -1; dz <= 1; ++dz) {
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                int nx = int(gid.x) + dx;
                int ny = int(gid.y) + dy;
                int nz = int(gid.z) + dz;
                if (nx < 0 || nx >= int(params.gridX)) continue;
                if (ny < 0 || ny >= int(params.gridY)) continue;
                if (nz < 0 || nz >= int(params.gridZ)) continue;
                uint nidx = uint(nx) + uint(ny) * params.gridX + uint(nz) * params.gridX * params.gridY;
                if (wIn[nidx] < 0.5) continue;
                float wt = (dx == 0 && dy == 0 && dz == 0) ? 4.0 : 1.0;
                sum += sdfIn[nidx] * wt;
                w += wt;
            }
        }
    }
    sdfOut[idx] = (w > 0.0) ? sum / w : sdfIn[idx];
}
