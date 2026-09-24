#pragma once
#include "uy360_ba.hpp"
#include <opencv2/core/persistence.hpp>
#include <cmath>

namespace uy360 {
// Shared by Android and desktop replay so the comparison reads the same measurements.
inline void writeBAGeometry(cv::FileStorage& json, const BAStats& s) {
    json << "frameCount" << s.frameCount << "featureTracks" << s.featureTracks
         << "triangulatedTracks" << s.points << "observations" << s.observations
         << "constrainedCameras" << s.constrainedCameras << "minCameraObservations" << s.minCameraObservations
         << "optimized" << int(s.optimized) << "medianBeforePx" << s.medianBeforePx
         << "medianAfterPx" << s.medianAfterPx << "medianDepthSolvedUnits" << s.medianDepth
         << "seconds" << s.seconds;
    auto edges = [&](const char* name, const std::vector<std::array<int, 2>>& values) {
        json << name << "[";
        for (const auto& edge : values) json << "[:" << edge[0] << edge[1] << "]";
        json << "]";
    };
    edges("acceptedPairEdges", s.acceptedPairEdges);
    edges("triangulatedEdges", s.triangulatedEdges);
    json << "cameraObservations" << s.cameraObservations << "optimizedPositionsSolvedUnits" << "[";
    for (const auto& p : s.optimizedPositions) {
        json << "[:";
        for (int k = 0; k < 3; ++k) {
            if (std::isfinite(p[k])) json << p[k]; else json << "nonfinite";
        }
        json << "]";
    }
    json << "]";
}
inline std::string baGeometryJson(const BAStats& s) {
    cv::FileStorage json(".json", cv::FileStorage::WRITE | cv::FileStorage::MEMORY | cv::FileStorage::FORMAT_JSON);
    writeBAGeometry(json, s);
    return json.releaseAndGetString();
}
} // namespace uy360
