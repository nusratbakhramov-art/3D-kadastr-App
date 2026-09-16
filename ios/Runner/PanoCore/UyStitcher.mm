// OpenCV headers must come before any Apple framework header in an .mm file.
#include "uy360_pipeline.hpp"
#include "uy360_stitch.hpp"

#import "UyStitcher.h"

#include <string>
#include <vector>

static std::vector<uy360::FrameInput> parseFrames(NSArray<NSDictionary<NSString *, id> *> *frames) {
    std::vector<uy360::FrameInput> inputs;
    inputs.reserve(frames.count);
    for (NSDictionary *d in frames) {
        uy360::FrameInput f;
        f.path = std::string([d[@"path"] UTF8String]);
        NSArray *t = d[@"transform"];
        NSArray *k = d[@"intrinsics"];
        if (t.count != 16 || k.count != 4) continue;
        for (int i = 0; i < 16; ++i) f.transform[i] = [t[i] floatValue];
        f.fx = [k[0] floatValue];
        f.fy = [k[1] floatValue];
        f.cx = [k[2] floatValue];
        f.cy = [k[3] floatValue];
        f.imageWidth = [d[@"imageWidth"] intValue];
        f.imageHeight = [d[@"imageHeight"] intValue];
        f.targetPitch = [d[@"targetPitch"] floatValue];
        inputs.push_back(f);
    }
    return inputs;
}

static NSMutableDictionary<NSString *, id> *resultDict(const uy360::Result &r) {
    return [@{
        @"ok": @(r.ok),
        @"width": @(r.width),
        @"height": @(r.height),
        @"frames": @(r.frames),
        @"coverage": @(r.coverage),
        @"seconds": @(r.seconds),
        @"pairs": @(r.pairs),
        @"residualBefore": @(r.residualBeforeDeg),
        @"residualAfter": @(r.residualAfterDeg),
        @"blend": [NSString stringWithUTF8String:r.blend.c_str()],
        @"align": [NSString stringWithUTF8String:r.align.c_str()],
        @"error": [NSString stringWithUTF8String:r.error.c_str()],
        @"depthFrames": @(r.depthFrames),
    } mutableCopy];
}

/// centroid radius / first-to-last offset / widest pair, in metres.
static void positionSpread(const std::vector<uy360::Pose> &poses, double &radius, double &lastOffset,
                           double &maxPair) {
    radius = lastOffset = maxPair = 0;
    const size_t n = poses.size();
    if (n < 2) return;
    cv::Vec3f c(0, 0, 0);
    for (const auto &p : poses) c += p.p;
    c *= 1.0f / (float)n;
    for (const auto &p : poses) radius += cv::norm(p.p - c);
    radius /= (double)n;
    lastOffset = cv::norm(poses.back().p - poses.front().p);
    for (size_t i = 0; i < n; ++i)
        for (size_t j = i + 1; j < n; ++j) maxPair = std::max(maxPair, cv::norm(poses[i].p - poses[j].p));
}

@implementation UyStitcher

+ (NSDictionary<NSString *, id> *)stitchFrames:(NSArray<NSDictionary<NSString *, id> *> *)frames
                                         width:(int)width
                                      panoPath:(NSString *)panoPath
                                   previewPath:(NSString *)previewPath
                                      logoPath:(NSString *_Nullable)logoPath
                                      progress:(void (^_Nullable)(float, NSString *))progress {
    std::vector<uy360::FrameInput> inputs = parseFrames(frames);
    uy360::Options opt = uy360::optionsForFrameCount((int)inputs.size());  // sparse 18-shot grid → narrower feather/seam masks
    opt.width = width;
    if (logoPath) opt.nadirLogoPath = std::string([logoPath UTF8String]);
    uy360::Result r = uy360::stitch(inputs, opt, std::string([panoPath UTF8String]),
                                    std::string([previewPath UTF8String]),
                                    [progress](float p, const std::string &m) {
                                        if (progress) progress(p, [NSString stringWithUTF8String:m.c_str()]);
                                    });
    return resultDict(r);
}

+ (NSDictionary<NSString *, id> *)stitchMVSFrames:(NSArray<NSDictionary<NSString *, id> *> *)frames
                                            width:(int)width
                                      highQuality:(BOOL)highQuality
                                      sensorPoses:(BOOL)sensorPoses
                                         panoPath:(NSString *)panoPath
                                      previewPath:(NSString *)previewPath
                                         logoPath:(NSString *_Nullable)logoPath
                                         progress:(void (^_Nullable)(float, NSString *))progress {
    std::vector<uy360::FrameInput> inputs = parseFrames(frames);
    uy360::Options opt = uy360::optionsForFrameCount((int)inputs.size());
    opt.width = width;
    if (logoPath) opt.nadirLogoPath = std::string([logoPath UTF8String]);
    uy360::PipelineOptions popt;  // core defaults = the server-validated parameters
    if (!highQuality) popt.mvs = uy360::MvsOptions::fast();   // visually identical on the test rooms, 2× faster
    if (sensorPoses) {
        // Gyro poses (ultra-wide path): bundle adjust with the sensor priors, then depth-from-motion
        // as usual. Depth was disabled here at first, but it is what removes the parallax ghosting
        // on near objects (a wardrobe blending into the wall behind it, bent window frames) — both
        // test rooms, textured and white-walled, stitched measurably better with it. The BA still
        // recovers the hand translation from the features, so the depth has a real baseline.
        popt.sensorPoses = true;
    }
    uy360::PipelineStats st;
    std::vector<uy360::Pose> posesOut;
    uy360::Result r = uy360::stitchMVS(inputs, opt, popt, std::string([panoPath UTF8String]),
                                       std::string([previewPath UTF8String]),
                                       [progress](float p, const std::string &m) {
                                           if (progress) progress(p, [NSString stringWithUTF8String:m.c_str()]);
                                       },
                                       &st, &posesOut);
    NSMutableDictionary *out = resultDict(r);
    out[@"baSeconds"] = @(st.baSeconds);
    out[@"mvsSeconds"] = @(st.mvsSeconds);
    out[@"stitchSeconds"] = @(st.stitchSeconds);
    out[@"planarGroups"] = @(st.planar.groups);
    out[@"planarFrames"] = @(st.planar.frames);
    out[@"baMedianBeforePx"] = @(st.ba.medianBeforePx);
    out[@"baMedianAfterPx"] = @(st.ba.medianAfterPx);
    // How far the phone wandered while shooting — the parallax that no stitch can undo.
    double radius = 0, lastOffset = 0, maxPair = 0;
    positionSpread(posesOut, radius, lastOffset, maxPair);
    out[@"driftRadiusM"] = @(radius);
    out[@"driftMaxM"] = @(maxPair);
    return out;
}

+ (NSDictionary<NSString *, id> *)poseDriftForFrames:(NSArray<NSDictionary<NSString *, id> *> *)frames
                                             baWidth:(int)baWidth {
    std::vector<uy360::FrameInput> inputs = parseFrames(frames);
    if (inputs.size() < 3) return @{@"ok": @NO, @"count": @((int)inputs.size()), @"error": @"need 3 frames"};
    uy360::BAOptions opt = uy360::BAOptions::forSensorPoses();
    if (baWidth > 0) opt.width = baWidth;
    opt.iterations = 25;
    uy360::BAStats st;
    std::vector<uy360::Pose> poses;
    try {
        poses = uy360::bundleAdjustPoses(inputs, opt, uy360::ProgressFn(), &st);
    } catch (const std::exception &e) {
        return @{@"ok": @NO, @"count": @((int)inputs.size()), @"error": [NSString stringWithUTF8String:e.what()]};
    }
    if (poses.size() != inputs.size()) return @{@"ok": @NO, @"count": @((int)inputs.size()), @"error": @"ba failed"};
    double radius = 0, lastOffset = 0, maxPair = 0;
    positionSpread(poses, radius, lastOffset, maxPair);
    // Where the last shot sits relative to the first one, in the capture's world frame (+Y up).
    // The app projects this onto the phone's current heading to say which way to step back.
    const cv::Vec3f d = poses.back().p - poses.front().p;
    return @{
        @"ok": @YES,
        @"count": @((int)poses.size()),
        @"radiusM": @(radius),
        @"lastOffsetM": @(lastOffset),
        @"maxPairM": @(maxPair),
        @"offsetX": @(d[0]),
        @"offsetY": @(d[1]),
        @"offsetZ": @(d[2]),
        @"seconds": @(st.seconds),
        @"points": @(st.points),
    };
}

@end
