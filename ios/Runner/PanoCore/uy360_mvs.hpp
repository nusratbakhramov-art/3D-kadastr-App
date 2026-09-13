// Uy360 on-device plane-sweep multi-view stereo (port of server/mvs_depth.py).
//
// For every frame i: pick neighbours j (optical axes within maxAngleDeg, baseline
// ≥ minBaselineM), sweep `planes` fronto-parallel planes spaced linearly in inverse
// depth between zMin and zMax, warp each neighbour into i's view with the plane
// homography H = K_j (R_ji + t_ji nᵀ/d) K_i⁻¹ and score it with a windowed ZNCC on the
// blurred grey images. Per pixel the cost is the mean of the best two neighbours,
// each cost slice is guided-filtered (guide = grey image), a 4-direction semi-global
// aggregation runs over the plane axis, winner-take-all with parabolic refinement
// gives inverse depth. A pixel is confident when its raw cost is low, the second
// distinct minimum is clearly worse, ≥ minViews neighbours saw it and a neighbour's
// own confident depth agrees (cross-frame check). Unconfident pixels are filled by
// pull-push interpolation of inverse depth (snapped onto RANSAC-fitted dominant
// planes), a weighted guided filter and a median.
//
// Memory: the cost volume is uint8 (0..200 = cost×100, 255 = unseen) and the SGM
// keeps only one direction stored (uint8), the other three are streamed, so a
// 1008×756×64 frame needs ≈ 100 MB of volumes; per-thread scratch is band-sized.
#pragma once

#include "uy360_stitch.hpp"  // FrameInput
#include "uy360_types.hpp"   // Pose, DepthMap, ProgressFn

#include <vector>

namespace uy360 {

struct MvsOptions {
    int width = 1008;          // working width (height follows the frame aspect)
    int planes = 96;           // depth planes, linear in inverse depth (server-validated: 96)
    float zMin = 0.6f, zMax = 12.f;
    int neighbours = 6;
    float maxAngleDeg = 60.f;  // max angle between optical axes of i and a neighbour
    float minBaselineM = 0.05f;
    int winRadius = 5;         // ZNCC window radius
    float blurSigma = 1.f;     // Gaussian blur of the grey images before matching
    float costMax = 0.5f;      // confident: raw cost (1 − ZNCC) below this
    float margin = 0.1f;       // confident: second distinct minimum worse by this
    int minViews = 2;          // confident: neighbours that saw the pixel at the winner
    float tolInv = 0.06f;      // cross-frame consistency tolerance in 1/m (0 = off)
    float sgmP1 = 0.05f, sgmP2 = 0.4f;  // semi-global penalties (P2 = 0 disables SGM)
    int gfRadius = 8;          // guided filter radius for the cost slices (0 = off)
    float gfEps = 1e-3f;

    /// ~3× faster depth (phones): 756 px working width, 64 planes, 5 neighbours. Walls, doors
    /// and furniture stay straight; only small nearby objects get a coarser depth.
    static MvsOptions fast() {
        MvsOptions o;
        o.width = 756;
        o.planes = 64;
        o.neighbours = 5;
        o.gfRadius = 6;
        return o;
    }
};

struct MvsStats {
    double seconds = 0;
    std::vector<float> confFraction;  // per frame, after the cross-frame check
};

/// One DepthMap per frame at opt.width × (frame aspect); z in metres, conf 2 = measured,
/// 1 = filled, 0 = unknown (frame without usable neighbours). `poses` (camera→world)
/// override FrameInput::transform; if empty the transforms are used.
std::vector<DepthMap> computeDepthMaps(const std::vector<FrameInput>& frames, const std::vector<Pose>& poses,
                                       const MvsOptions& opt, const ProgressFn& progress, MvsStats* stats);

}  // namespace uy360
