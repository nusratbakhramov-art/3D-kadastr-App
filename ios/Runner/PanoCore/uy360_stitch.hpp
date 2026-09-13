// Uy360 on-device stitching core (C++17 + OpenCV, no ML).
//
// Same algorithm as server/stitch.py minus the AI steps (person removal, LaMa):
//   1. rotation refinement (SIFT + gyro-gated matches, Kabsch / Gauss-Seidel)
//   2. pose-seeded warp onto a periodic equirect canvas, feather weights, scalar gain
//   3. two-pass DIS optical-flow local alignment (parallax)
//   4. graph-cut seams + multi-band blend, "best frame" fill where seams leave gaps
//   5. fold the ±180° wrap along a DP seam
//   6. zenith/nadir holes: nadir = radial mirror of the floor, zenith = Telea inpaint,
//      both in a perspective face view; remaining holes = Telea
//
// One core for iOS (Objective-C++ bridge), Android (JNI) and a desktop CLI.
#pragma once

#include "uy360_types.hpp"

#include <array>
#include <functional>
#include <string>
#include <vector>

namespace uy360 {

struct FrameInput {
    std::string path;                 // JPEG in sensor orientation (not rotated)
    std::array<float, 16> transform{};// camera→world 4x4, column-major (ARKit / ARCore)
    float fx = 0, fy = 0, cx = 0, cy = 0;  // intrinsics for imageWidth × imageHeight
    int imageWidth = 0, imageHeight = 0;
    float targetPitch = 0;            // radians, informational
};

struct Options {
    int width = 4096;          // output width (height = width/2)
    bool refine = true;
    bool localAlign = false;  // no local warping (see localAlign): parallax is handled by depth
    bool seams = true;
    bool gainComp = true;
    float feather = 0.18f;     // border ramp width as a fraction of the frame size (weight 0 → 1)
    float seamMinWeight = 0.12f;  // seam finder may only cut where the feather weight exceeds this
    float nadirCutDeg = 12.f;  // drop everything below −(90−cut)° (feet / hands)
    float poleCapDeg = 45.f;   // pole fill works inside this cap
    int bands = 5;
    /// Nadir patch: a logo (PNG/JPEG, square, optional alpha) stamped over the bottom cap of the
    /// panorama — hides the tripod/feet/mirror-fill area like professional tours do. Empty = off.
    std::string nadirLogoPath;
    float nadirLogoDeg = 28.f;  // angular radius of the disc (degrees from the nadir); feet/tripod reach ~25°
    int seamWidth = 1024;      // seam finder resolution (1536 → 1024: −60 % graph-cut time, no visible change)
    int refineSmallWidth = 1000;
    int alignMaxSide = 1024;
};

struct Result {
    bool ok = false;
    int width = 0, height = 0, frames = 0;
    float coverage = 0;
    double seconds = 0;
    int pairs = 0;
    float residualBeforeDeg = 0, residualAfterDeg = 0;
    int depthFrames = 0;       // frames re-projected through a depth map
    std::string blend, align, error;
};

// progress in [0,1] + short message (may be called from the stitching thread)
using Progress = std::function<void(float, const std::string&)>;

// Defaults tuned to the capture grid.
//   n >= 24: the 30-target grid (12 horizon frames 30° apart, ±45° rows 45° apart)
//            overlaps ~25° → plain Options.
//   n <  24: the sparse 18-target grid (8 horizon frames 45° apart, 4 at +48° and
//            4 at −48° 90° apart, zenith, nadir) overlaps only ~7–13°. With the
//            default ramp the seam masks (weight > seamMinWeight) barely overlap and
//            the graph cut is forced onto the frame borders, so the ramp and the
//            threshold are reduced: feather = 0.12, seamMinWeight = 0.06.
// Everything else keeps the Options defaults; callers set width etc. afterwards.
Options optionsForFrameCount(int n);

Result stitch(const std::vector<FrameInput>& frames, const Options& opt,
              const std::string& panoPath, const std::string& previewPath,
              const Progress& progress);

/// Depth-aware stitch (the parallax fix): `poses` (one per frame, e.g. bundle-adjusted)
/// replace the frame transforms and `depths` (one per frame; an empty `z` means "no
/// depth for this frame") let every frame be re-projected from the mean camera
/// position through its depth map, with an occlusion consistency check. Rotation
/// refinement is not run (it would absorb parallax into the rotations).
Result stitchWithDepth(const std::vector<FrameInput>& frames, const std::vector<Pose>& poses,
                       const std::vector<DepthMap>& depths, const Options& opt,
                       const std::string& panoPath, const std::string& previewPath,
                       const Progress& progress);

}  // namespace uy360
