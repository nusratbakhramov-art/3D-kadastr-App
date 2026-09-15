// Full on-device "MVS" pipeline = the parallax fix that matched Teleport on the server:
//   1. bundleAdjustPoses  (uy360_ba)   — ARKit poses → drift-free 6-DoF poses
//   2. computeDepthMaps   (uy360_mvs)  — per-frame depth from motion (no LiDAR, no ML)
//   3. stitchWithDepth    (uy360_stitch) — re-project every frame from one centre through its depth
// One call for the iOS bridge, the Android JNI and the desktop CLI.
#pragma once

#include "uy360_ba.hpp"
#include "uy360_mvs.hpp"
#include "uy360_stitch.hpp"
#include "uy360_types.hpp"

#include <string>
#include <vector>

namespace uy360 {

struct PipelineOptions {
    BAOptions ba;
    MvsOptions mvs;
    bool runBA = true;   // false → use the raw frame transforms as poses
    /// Poses come from a phone's gyro/accelerometer fusion (Android without ARCore): rotation
    /// approximate, positions unknown → BAOptions::forSensorPoses() is used instead of `ba`.
    bool sensorPoses = false;
};

struct PipelineStats {
    BAStats ba;
    MvsStats mvs;
    double baSeconds = 0, mvsSeconds = 0, stitchSeconds = 0;
    int depthFrames = 0;
};

/// Progress: BA 0–0.12, MVS 0.12–0.72, stitch 0.72–1.0.
/// posesOut / depthsOut (optional) receive the intermediate results (CLI parity tests, caching).
Result stitchMVS(const std::vector<FrameInput>& frames, const Options& opt, const PipelineOptions& popt,
                 const std::string& panoPath, const std::string& previewPath, const Progress& progress,
                 PipelineStats* stats = nullptr, std::vector<Pose>* posesOut = nullptr,
                 std::vector<DepthMap>* depthsOut = nullptr);

}  // namespace uy360
