#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ bridge to the C++ stitching core (core/uy360_stitch.hpp).
@interface UyStitcher : NSObject

/// frames: array of {path, transform[16], intrinsics[4], imageWidth, imageHeight, targetPitch}
/// Returns {ok, width, height, frames, coverage, seconds, pairs, residualBefore, residualAfter, blend, align, error}
+ (NSDictionary<NSString *, id> *)stitchFrames:(NSArray<NSDictionary<NSString *, id> *> *)frames
                                         width:(int)width
                                      panoPath:(NSString *)panoPath
                                   previewPath:(NSString *)previewPath
                                     logoPath:(NSString *_Nullable)logoPath
                                      progress:(void (^_Nullable)(float fraction, NSString *message))progress;

/// Same input; runs the full on-device MVS pipeline (bundle adjustment → depth maps →
/// depth re-projection stitch). Result adds {depthFrames, baSeconds, mvsSeconds, stitchSeconds,
/// baMedianBeforePx, baMedianAfterPx}.
/// highQuality: 1008 px / 96-plane depth (≈2× slower); otherwise the fast preset (756 px / 64 planes).
+ (NSDictionary<NSString *, id> *)stitchMVSFrames:(NSArray<NSDictionary<NSString *, id> *> *)frames
                                            width:(int)width
                                      highQuality:(BOOL)highQuality
                                      sensorPoses:(BOOL)sensorPoses
                                         panoPath:(NSString *)panoPath
                                      previewPath:(NSString *)previewPath
                                        logoPath:(NSString *_Nullable)logoPath
                                         progress:(void (^_Nullable)(float fraction, NSString *message))progress;

/// DIAGNOSTICS ONLY — do not show these numbers to the user. Runs the bundle adjustment
/// (sensor-pose priors) over the given frames and reports the spread of the recovered camera
/// positions. For gyro captures there is no metric anchor: the scale is set by the BA's position
/// prior, not measured, so the "metres" are indicative at best. An in-capture lock built on this
/// reported drift while the phone was demonstrably still, and was removed.
/// Returns {ok, count, radiusM, lastOffsetM, maxPairM, seconds, points, error}.
+ (NSDictionary<NSString *, id> *)poseDriftForFrames:(NSArray<NSDictionary<NSString *, id> *> *)frames
                                             baWidth:(int)baWidth;

@end

NS_ASSUME_NONNULL_END
