// Shared types for the Uy360 C++ core modules (stitch / bundle adjustment / MVS).
#pragma once

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>

#include <functional>
#include <algorithm>
#include <cmath>
#include <limits>
#include <string>
#include <vector>

namespace uy360 {

/// Camera pose: R = camera→world rotation (ARKit convention: camera +X right, +Y up,
/// −Z forward; world +Y up), p = camera position in metres.
struct Pose {
    cv::Matx33f R = cv::Matx33f::eye();
    cv::Vec3f p{0, 0, 0};
};

// A small surface supported by matching photographed edges in several views.
// Its local camera position is fitted only for this surface: uncertain stereo
// around a textureless fixture must not move the rest of the room.
struct RectifiedPatch {
    int group = 0;
    cv::Vec3f center, axisU, axisV;
    cv::Vec2f halfExtent;
    cv::Vec3f cameraPosition;
    float margin = 0;
};

struct WallSurface {
    cv::Mat mask;
    cv::Vec3f normal;
    float offset = 0;
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
    // Optional verified surface in this camera's coordinates: n·X = offset.
    // Keeps near-object projection exact instead of relying on three iterations.
    cv::Mat planarMask; // CV_8UC1, may exceed z's resolution to retain fine silhouettes
    cv::Vec3f planarNormal{0, 0, 0};
    float planarOffset = 0;
    std::vector<RectifiedPatch> patches;
    std::vector<WallSurface> walls;
};

// Depth and silhouette have independent resolutions. Interpolate the silhouette
// at the continuous source coordinate; rounding on the stereo grid makes an
// otherwise straight foreground edge into large steps in the final panorama.
inline bool depthPlaneContains(const DepthMap& depth, float u, float v) {
    if (depth.planarMask.empty() || u < 0 || v < 0 ||
        u > depth.z.cols - 1 || v > depth.z.rows - 1) return false;
    float x = (u + .5f) * depth.planarMask.cols / depth.z.cols - .5f;
    float y = (v + .5f) * depth.planarMask.rows / depth.z.rows - .5f;
    x = std::max(0.f, std::min(x, float(depth.planarMask.cols - 1)));
    y = std::max(0.f, std::min(y, float(depth.planarMask.rows - 1)));
    int x0 = int(x), y0 = int(y);
    int x1 = std::min(x0 + 1, depth.planarMask.cols - 1);
    int y1 = std::min(y0 + 1, depth.planarMask.rows - 1);
    float a = x - x0, b = y - y0;
    return (1 - b) * ((1 - a) * depth.planarMask.at<uchar>(y0, x0) + a * depth.planarMask.at<uchar>(y0, x1)) +
           b * ((1 - a) * depth.planarMask.at<uchar>(y1, x0) + a * depth.planarMask.at<uchar>(y1, x1)) >= 127.5f;
}

/// Intersect a panorama ray with the verified plane, then require that its
/// source pixel is inside the observed object. cameraOffset = camera - panorama
/// centre, expressed in camera coordinates; point = t*direction - offset.
inline bool depthPlanePoint(const DepthMap& depth, const cv::Vec3f& direction,
                            const cv::Vec3f& cameraOffset, cv::Vec3f& point) {
    if (depth.planarMask.empty()) return false;
    float denominator = depth.planarNormal.dot(direction);
    if (std::abs(denominator) < 1e-6f) return false;
    float t = (depth.planarOffset + depth.planarNormal.dot(cameraOffset)) / denominator;
    if (!std::isfinite(t) || t <= 0) return false;
    point = t * direction - cameraOffset;
    if (-point[2] < 1e-3f) return false;
    float u = depth.fx * point[0] / -point[2] + depth.cx;
    float v = depth.cy - depth.fy * point[1] / -point[2];
    return depthPlaneContains(depth, u, v);
}

// Shared walls use the same exact intersection as a near object, but do not
// acquire reflective-object ownership in the blend. Their masks protect doors,
// furniture and windows with independently measured depth.
inline bool depthWallPoint(const DepthMap& depth, const cv::Vec3f& direction,
                           const cv::Vec3f& cameraOffset, cv::Vec3f& point) {
    float nearest = std::numeric_limits<float>::infinity();
    for (const auto& wall : depth.walls) {
        float denominator = wall.normal.dot(direction);
        if (std::abs(denominator) < 1e-6f) continue;
        float t = (wall.offset + wall.normal.dot(cameraOffset)) / denominator;
        if (!std::isfinite(t) || t <= 0 || t >= nearest) continue;
        cv::Vec3f candidate = t * direction - cameraOffset;
        if (-candidate[2] < 1e-3f) continue;
        float u = depth.fx * candidate[0] / -candidate[2] + depth.cx;
        float v = depth.cy - depth.fy * candidate[1] / -candidate[2];
        if (u < 0 || v < 0 || u > wall.mask.cols - 1 || v > wall.mask.rows - 1) continue;
        if (!wall.mask.at<uchar>(cvRound(v), cvRound(u))) continue;
        point = candidate; nearest = t;
    }
    return std::isfinite(nearest);
}

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
