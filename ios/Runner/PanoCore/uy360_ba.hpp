// Light 6-DoF bundle adjustment of ARKit poses from SIFT tracks (port of server/ba_poses.py).
//
// ARKit poses are metric and locally accurate (~1 px between consecutive frames) but drift
// 1–2° around a ring, which breaks multi-view stereo. This refines all camera rotations
// *and* positions jointly with a sparse set of triangulated SIFT tracks, using the ARKit
// poses as a weak prior so scale and gravity stay anchored.
//
//   1. SIFT (6000 features, contrast 0.02) on every frame downscaled to `width` px
//   2. neighbouring pairs (optical axes within maxAngleDeg, k nearest): ratio-test matches,
//      essential matrix with a 1.5 px Sampson inlier threshold: pose-seeded and 8-point
//      RANSAC hypotheses with robust refinement, plus OpenCV's calibrated five-point
//      hypothesis when its consensus is stronger and rotation is within 8° of the prior.
//      Pairs whose estimated rotation disagrees with the prior by > 25° are rejected.
//   3. image-derived baseline initialization for unknown sensor positions, union-find
//      tracks, and linear (DLT) triangulation
//   4. Levenberg–Marquardt with the Schur complement over cameras (axis-angle + position)
//      and points, Cauchy loss (scale 2 px) on every residual, ARKit prior residuals
//      (p − p0)/posSigma and dθ/rotSigma exactly as in the Python reference.
//
// Frames without observations keep their ARKit pose. Note that the Python reference stops at
// max_nfev = 500 (scipy status 0, median reprojection unchanged); this solver runs to
// convergence of the same objective, so its corrections are larger (≈1°, 2–5 cm on xona10)
// and the reprojection error much lower (0.19 px vs 0.77 px median).
#pragma once

#include "uy360_stitch.hpp"
#include "uy360_types.hpp"

#include <vector>

namespace uy360 {

struct BAOptions {
    // Android opt-in: isolate randomized matching from worker/caller RNG history.
    // Default remains false to preserve the existing iOS processing path.
    bool stableMatching = false;
    bool sensorTranslationInit = true; // initialize unknown positions from image baselines
    int width = 1008;          // feature extraction width (px)
    float posSigmaM = 0.03f;   // ARKit position prior σ (m)
    float rotSigmaDeg = 1.5f;  // ARKit rotation prior σ (deg)
    int neighbours = 6;        // pairs per frame
    float maxAngleDeg = 60.f;  // max angle between optical axes of a pair
    int iterations = 30;       // LM iterations
    /// Relative-rotation prior between consecutive frames (capture order), σ in degrees; 0 = off.
    /// For poses from a phone's gyro/accelerometer fusion (no ARCore/ARKit) the *relative* rotation
    /// between two shots taken seconds apart is far more accurate (~0.3°) than the absolute one
    /// (drift), and it breaks the per-camera rotation↔translation ambiguity of the reprojection term.
    float relRotSigmaDeg = 0.f;
    /// Separate σ for the yaw component (rotation about the world vertical) of the absolute
    /// prior; 0 = same as rotSigmaDeg. Gyro/accelerometer fusion knows tilt (gravity) to ~0.5°
    /// but yaw only up to a slow drift, so sensor poses use a tight tilt σ and a loose yaw σ.
    float yawSigmaDeg = 0.f;

    /// Opt-in rotation-only camera graph, for captures that will be stitched rotation-only.
    /// The joint solve optimizes each rotation together with a translation; zeroing those
    /// translations afterwards leaves rotations that no longer describe a pure pivot. When
    /// this is on, the rotations are additionally solved on their own from per-pair RANSAC
    /// rotation consensus over unit bearings (no essential matrix, no parallax) synchronised
    /// across the graph, and reported in BAStats. The joint solve and every existing gate are
    /// untouched; only a caller that asks for these rotations uses them.
    bool rotationGraph = false;
    /// Weight of the relative-sensor link that lets a camera with no accepted pair follow its
    /// solved neighbours. Applied one-sidedly: a camera the graph measured is never pulled.
    /// The solution is insensitive to this between roughly 1 and 12.
    float rotationGraphPriorWeight = 4.f;
    /// Inliers a pair must reach before its rotation is allowed to move a camera. A thin edge
    /// over a weakly textured ceiling can swing one frame several degrees while its neighbours
    /// have no evidence to follow it, which shows up as a step along the beam.
    int rotationGraphMinInliers = 10;
    /// Angular inlier threshold of the per-pair rotation consensus. Weak, low-texture pairs
    /// (upper ring, zenith) need a looser one to reach the inlier count at all.
    float rotationGraphThresholdDeg = 0.5f;

    /// Preset for poses from a phone's gyro/accelerometer (no ARCore/ARKit): positions unknown
    /// (pivot model or zero, σ 15 cm), tilt 0.5°, yaw 3°, consecutive relative rotation 0.3°.
    static BAOptions forSensorPoses() {
        BAOptions o;
        o.posSigmaM = 0.15f;
        o.rotSigmaDeg = 0.5f;
        o.yawSigmaDeg = 3.f;
        o.relRotSigmaDeg = 0.3f;
        // The 0.5x rings overlap horizon views whose axes are ~64 degrees apart.
        o.maxAngleDeg = 75.f;
        return o;
    }
};

struct BAStats {
    float medianBeforePx = 0, medianAfterPx = 0;
    int points = 0, observations = 0;
    float depth10 = 0, depth95 = 0, medianDepth = 0; // positive sparse depths, in the solved scale
    int constrainedCameras = 0; // cameras with enough triangulated observations for 6-DoF
    std::vector<int> cameraObservations; // same order as the input frames
    // Read-only experiment diagnostics; no effect on matching/optimization/depth gates.
    int frameCount = 0, featureTracks = 0, minCameraObservations = 10;
    bool optimized = false;
    std::vector<std::array<int, 2>> acceptedPairEdges, triangulatedEdges;
    std::vector<cv::Vec3f> optimizedPositions; // before pivot fill; solved units, not metric for sensors
    /// Filled only when BAOptions::rotationGraph is set: camera→world rotations solved
    /// rotation-only. Empty otherwise; never used by this solver's own optimization.
    std::vector<cv::Matx33f> rotationGraphRotations;
    int rotationGraphPairs = 0;             // pairs that produced an accepted rotation edge
    int rotationGraphSupportedCameras = 0;  // cameras with at least one such edge
    double seconds = 0;
};

/// One Pose per frame (same order), refined from the ARKit transforms.
std::vector<Pose> bundleAdjustPoses(const std::vector<FrameInput>& frames, const BAOptions& opt,
                                    const ProgressFn& progress, BAStats* stats);

}  // namespace uy360
