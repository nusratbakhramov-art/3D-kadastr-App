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
    uy360::PipelineStats st;
    uy360::Result r = uy360::stitchMVS(inputs, opt, popt, std::string([panoPath UTF8String]),
                                       std::string([previewPath UTF8String]),
                                       [progress](float p, const std::string &m) {
                                           if (progress) progress(p, [NSString stringWithUTF8String:m.c_str()]);
                                       },
                                       &st);
    NSMutableDictionary *out = resultDict(r);
    out[@"baSeconds"] = @(st.baSeconds);
    out[@"mvsSeconds"] = @(st.mvsSeconds);
    out[@"stitchSeconds"] = @(st.stitchSeconds);
    out[@"baMedianBeforePx"] = @(st.ba.medianBeforePx);
    out[@"baMedianAfterPx"] = @(st.ba.medianAfterPx);
    return out;
}

@end
