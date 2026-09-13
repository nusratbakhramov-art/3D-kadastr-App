// Shared types for the Uy360 C++ core modules (stitch / bundle adjustment / MVS).
#pragma once

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>

#include <functional>
#include <string>
#include <vector>

namespace uy360 {

/// Camera pose: R = camera→world rotation (ARKit convention: camera +X right, +Y up,
/// −Z forward; world +Y up), p = camera position in metres.
struct Pose {
    cv::Matx33f R = cv::Matx33f::eye();
    cv::Vec3f p{0, 0, 0};
};

/// Per-frame depth map at a reduced resolution (typically 1008×756 for a 4032×3024 frame).
/// z = distance along the camera −Z axis in metres (same definition as ARKit sceneDepth
/// and as the Python depth files `*_depth.f32`); conf: 2 = measured/confident,
/// 1 = filled by interpolation/plane prior, 0 = unknown.
/// Intrinsics are for z's own resolution:  u = fx·x/(−z) + cx,  v = cy − fy·y/(−z).
struct DepthMap {
    cv::Mat z;     // CV_32FC1
    cv::Mat conf;  // CV_8UC1
    float fx = 0, fy = 0, cx = 0, cy = 0;
};

/// progress in [0,1] + short message (may be called from a worker thread)
using ProgressFn = std::function<void(float, const std::string&)>;

/// Decode a JPEG no larger than needed: libjpeg scales in the DCT domain (1/2, 1/4, 1/8), which
/// is 3–6× cheaper than a full decode + resize. `fullWidth` = the frame's real width (from the
/// metadata; 0 = unknown → full decode). The result is >= targetWidth wide; the caller resizes.
inline cv::Mat imreadForWidth(const std::string& path, int targetWidth, int fullWidth, bool color) {
    int flag = color ? cv::IMREAD_COLOR : cv::IMREAD_GRAYSCALE;
    if (fullWidth > 0 && targetWidth > 0) {
        if (fullWidth / 8 >= targetWidth) flag = color ? cv::IMREAD_REDUCED_COLOR_8 : cv::IMREAD_REDUCED_GRAYSCALE_8;
        else if (fullWidth / 4 >= targetWidth) flag = color ? cv::IMREAD_REDUCED_COLOR_4 : cv::IMREAD_REDUCED_GRAYSCALE_4;
        else if (fullWidth / 2 >= targetWidth) flag = color ? cv::IMREAD_REDUCED_COLOR_2 : cv::IMREAD_REDUCED_GRAYSCALE_2;
    }
    return cv::imread(path, flag);
}

}  // namespace uy360
