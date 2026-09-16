#pragma once

#include "uy360_stitch.hpp"

namespace uy360 {

struct PlanarStats {
    int candidates = 0, groups = 0, frames = 0;
};

/// Rectangular, upright surfaces seen in at least three views supply shared line
/// constraints. These constrain depth where reflections/textureless surfaces make
/// stereo ambiguous. Unsupported regions and camera rotations stay untouched.
/// Gyro reconstructions have arbitrary scale; all acceptance gates are relative.
PlanarStats regularizePlanarObjects(const std::vector<FrameInput>& frames,
                                   std::vector<Pose>& poses, std::vector<DepthMap>& depths,
                                   const ProgressFn& progress = {});

// Recover horizontal rectangular fixtures from repeated bright strip edges.
// Requires four sides, multi-view support and an observable, bounded fit.
int regularizeCeilingFixtures(const std::vector<FrameInput>& frames,
                             const std::vector<Pose>& poses, std::vector<DepthMap>& depths);

int regularizeWallSurfaces(const std::vector<FrameInput>& frames,
                          const std::vector<Pose>& poses, std::vector<DepthMap>& depths);

} // namespace uy360
