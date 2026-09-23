#include "uy360_pipeline.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <opencv2/core/persistence.hpp>

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

bool sensorTranslationSupported(int constrainedCameras, int frameCount, bool requireAll) {
    if (frameCount < 3 || constrainedCameras > frameCount) return false;
    const int required = requireAll ? frameCount : std::max(3, (frameCount * 3 + 3) / 4);
    return constrainedCameras >= required;
}

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
    bool baOK = false;
    if (popt.runBA && frames.size() >= 3) {
        try {
            BAOptions baOpt = popt.sensorPoses ? BAOptions::forSensorPoses() : popt.ba;
            if (popt.sensorPoses) {
                baOpt.width = popt.ba.width;
                baOpt.sensorTranslationInit = popt.ba.sensorTranslationInit;
                baOpt.iterations = std::max(popt.ba.iterations, 40);
            }
            poses = bundleAdjustPoses(frames, baOpt,
                                      [&](float p, const std::string& m) {
                                          if (progress) progress(0.12f * p, m);
                                      },
                                      &st.ba);
            baOK = poses.size() == frames.size() && st.ba.points > 0 &&
                   std::isfinite(st.ba.medianAfterPx);
        } catch (const std::exception& e) {
            poses.clear();
            st.fallbackReason = std::string("ba-failed: ") + e.what();
        }
    }
    // Sensor translations begin as an arbitrary pivot, unlike ARKit's measured positions.
    // A returned vector alone is not evidence that BA recovered motion. Pure rotation and
    // textureless rooms can leave most cameras constrained only by that invented pivot;
    // feeding it to MVS bends otherwise aligned walls. Require observation support across
    // the capture, otherwise retain the sensor rotations and use the rotation stitcher.
    const bool weakSensorRotations = popt.sensorPoses &&
        (!baOK || !sensorTranslationSupported(st.ba.constrainedCameras, int(frames.size()), false));
    const bool unsupportedSensorDepth = popt.sensorPoses && popt.requireAllSensorCameras &&
        (!baOK || !sensorTranslationSupported(st.ba.constrainedCameras, int(frames.size()), true));
    const bool sensorFallback = weakSensorRotations || unsupportedSensorDepth;
    if (weakSensorRotations) {
        poses.clear();
        baOK = false;
    }
    if (poses.size() != frames.size()) {
        poses.resize(frames.size());
        for (size_t i = 0; i < frames.size(); ++i) poses[i] = poseFromTransform(frames[i].transform);
    }
    if (sensorFallback) {
        if (progress) progress(0.12f, "Chuqurlik uchun moslik kam: rotatsiya bilan tikish");
        if (st.fallbackReason.empty()) st.fallbackReason = weakSensorRotations ? "insufficient triangulated observations" :
            "unconstrained sensor cameras " + std::to_string(st.ba.constrainedCameras) + "/" + std::to_string(frames.size());
        // Retain well-supported BA rotations, never its guessed translations.
        for (auto& pose : poses) pose.p = cv::Vec3f(0, 0, 0);
    }
    st.baSeconds = secondsSince(t0);

    // Rotation-only when requested or when sensor translation is under-constrained.
    // Write the retained poses into the transforms. Progress: BA 0–0.12, stitch 0.12–1.0.
    if (!popt.runMVS || sensorFallback) {
        std::vector<FrameInput> f2 = frames;
        for (size_t i = 0; i < f2.size(); ++i) {
            const cv::Matx33f& R = poses[i].R;
            const cv::Vec3f& p = poses[i].p;
            auto& t = f2[i].transform;
            t[0] = R(0, 0); t[1] = R(1, 0); t[2] = R(2, 0); t[3] = 0;
            t[4] = R(0, 1); t[5] = R(1, 1); t[6] = R(2, 1); t[7] = 0;
            t[8] = R(0, 2); t[9] = R(1, 2); t[10] = R(2, 2); t[11] = 0;
            t[12] = p[0]; t[13] = p[1]; t[14] = p[2]; t[15] = 1;
        }
        // The bundle adjustment already solved every rotation jointly, with feature tracks and
        // pose priors. Running the stitcher's pairwise rotation refine on top of that re-estimates
        // them from a handful of gated pair matches and measurably degrades the result on
        // low-texture rooms, so it is skipped whenever the BA succeeded.
        Options o2 = opt;
        if (baOK) o2.refine = false;
        const auto ts = std::chrono::steady_clock::now();
        res = stitch(f2, o2, panoPath, previewPath,
                     [&](float p, const std::string& m) {
                         if (progress) progress(0.12f + 0.88f * p, m);
                     });
        st.stitchSeconds = secondsSince(ts);
        res.seconds = secondsSince(t0);
        if (sensorFallback) res.align = "rotation-fallback: " + st.fallbackReason;
        if (stats) *stats = st;
        if (posesOut) *posesOut = std::move(poses);
        if (depthsOut) depthsOut->assign(frames.size(), DepthMap());
        return res;
    }

    // 2. depth
    const auto t1 = std::chrono::steady_clock::now();
    std::vector<DepthMap> depths;
    try {
        MvsOptions mvs = popt.mvs;
        if (popt.sensorPoses && baOK && st.ba.medianDepth > 0 &&
            std::isfinite(st.ba.depth10) && std::isfinite(st.ba.depth95)) {
            // Gyro-only reconstruction has no metric scale. A fixed 0.6m near plane
            // clipped furniture in captures whose solved room depth was ~1 unit.
            // Use the triangulated scene to choose both the sweep and baseline gate.
            mvs.zMin = std::clamp(st.ba.depth10 * 0.7f, 0.05f, 12.f);
            mvs.zMax = std::max(mvs.zMin * 2, std::clamp(st.ba.depth95 * 1.5f, 2.f, 50.f));
            mvs.minBaselineM = std::min(mvs.minBaselineM, st.ba.medianDepth * 0.005f);
        }
        depths = computeDepthMaps(frames, poses, mvs,
                                  [&](float p, const std::string& m) {
                                      if (progress) progress(0.12f + 0.56f * p, m);
                                  },
                                  &st.mvs);
    } catch (const std::exception& e) {
        res.error = std::string("mvs: ") + e.what();
        return res;
    }
    if (depths.size() != frames.size()) depths.resize(frames.size());
#ifndef NDEBUG
    // Preserve the device's actual geometry before optional plane corrections.
    // This lets the desktop core reproduce a reported device artifact exactly.
    if (std::getenv("UY360_STITCH_DIAGNOSTICS")) {
        cv::FileStorage dump(panoPath + ".geometry.yml.gz", cv::FileStorage::WRITE);
        dump << "frames" << "[";
        for (size_t i = 0; i < frames.size(); ++i) {
            const auto& d = depths[i];
            dump << "{" << "rotation" << cv::Mat(poses[i].R) << "position" << cv::Mat(poses[i].p)
                 << "fx" << d.fx << "fy" << d.fy << "cx" << d.cx << "cy" << d.cy
                 << "depth" << d.z << "confidence" << d.conf
                 << "supplemental" << int(popt.sensorPoses && baOK && st.ba.cameraObservations.size() == frames.size() &&
                     std::fabs(frames[i].targetPitch) > .35f && st.ba.cameraObservations[i] < 20) << "}";
        }
        dump << "]";
    }
#endif
    auto stitchFrames = frames;
    if (popt.sensorPoses && baOK && st.ba.cameraObservations.size() == frames.size())
        for (size_t i = 0; i < frames.size(); ++i)
            // The horizon ring defines the base panorama. Elevated views need
            // redundant feature support before competing inside that base: the
            // mathematical minimum for solving a pose is too weak for near objects.
            stitchFrames[i].supplemental = std::fabs(frames[i].targetPitch) > 0.35f &&
                                           st.ba.cameraObservations[i] < 20;
    if (popt.sensorPoses && baOK && popt.regularizePlanes)
        st.planar = regularizePlanarObjects(stitchFrames, poses, depths, [&](float p, const std::string& m) {
            if (progress) progress(0.68f + 0.04f * p, m);
        });
    for (const auto& d : depths) st.depthFrames += !d.z.empty();
    st.mvsSeconds = secondsSince(t1);

    // 3. stitch
    const auto t2 = std::chrono::steady_clock::now();
    res = stitchWithDepth(stitchFrames, poses, depths, opt, panoPath, previewPath,
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
