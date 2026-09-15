#include "uy360_pipeline.hpp"

#include <chrono>
#include <cmath>

namespace uy360 {

namespace {
inline double secondsSince(std::chrono::steady_clock::time_point t) {
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - t).count();
}
inline Pose poseFromTransform(const std::array<float, 16>& t) {
    Pose p;
    p.R = cv::Matx33f(t[0], t[4], t[8], t[1], t[5], t[9], t[2], t[6], t[10]);
    p.p = cv::Vec3f(t[12], t[13], t[14]);
    return p;
}
}  // namespace

Result stitchMVS(const std::vector<FrameInput>& frames, const Options& opt, const PipelineOptions& popt,
                 const std::string& panoPath, const std::string& previewPath, const Progress& progress,
                 PipelineStats* stats, std::vector<Pose>* posesOut, std::vector<DepthMap>* depthsOut) {
    Result res;
    if (frames.empty()) {
        res.error = "no frames";
        return res;
    }
    PipelineStats st;
    const auto t0 = std::chrono::steady_clock::now();

    // 1. poses
    std::vector<Pose> poses;
    if (popt.runBA && frames.size() >= 3) {
        try {
            BAOptions baOpt = popt.sensorPoses ? BAOptions::forSensorPoses() : popt.ba;
            if (popt.sensorPoses) { baOpt.width = popt.ba.width; baOpt.iterations = std::max(popt.ba.iterations, 40); }
            poses = bundleAdjustPoses(frames, baOpt,
                                      [&](float p, const std::string& m) {
                                          if (progress) progress(0.12f * p, m);
                                      },
                                      &st.ba);
        } catch (const std::exception& e) {
            poses.clear();
            res.align = std::string("ba-failed: ") + e.what();
        }
    }
    if (poses.size() != frames.size()) {
        poses.resize(frames.size());
        for (size_t i = 0; i < frames.size(); ++i) poses[i] = poseFromTransform(frames[i].transform);
    }
    st.baSeconds = secondsSince(t0);

    // 2. depth
    const auto t1 = std::chrono::steady_clock::now();
    std::vector<DepthMap> depths;
    try {
        depths = computeDepthMaps(frames, poses, popt.mvs,
                                  [&](float p, const std::string& m) {
                                      if (progress) progress(0.12f + 0.60f * p, m);
                                  },
                                  &st.mvs);
    } catch (const std::exception& e) {
        res.error = std::string("mvs: ") + e.what();
        return res;
    }
    if (depths.size() != frames.size()) depths.resize(frames.size());
    for (const auto& d : depths) st.depthFrames += !d.z.empty();
    st.mvsSeconds = secondsSince(t1);

    // 3. stitch
    const auto t2 = std::chrono::steady_clock::now();
    res = stitchWithDepth(frames, poses, depths, opt, panoPath, previewPath,
                          [&](float p, const std::string& m) {
                              if (progress) progress(0.72f + 0.28f * p, m);
                          });
    st.stitchSeconds = secondsSince(t2);
    res.seconds = secondsSince(t0);
    if (stats) *stats = st;
    if (posesOut) *posesOut = std::move(poses);
    if (depthsOut) *depthsOut = std::move(depths);
    return res;
}

}  // namespace uy360
