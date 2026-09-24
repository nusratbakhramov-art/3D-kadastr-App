// OpenCV must precede the Apple headers (the Objective-C YES/NO macros conflict with OpenCV).
#include "../Runner/PanoCore/uy360_pipeline.hpp"
#include "../Runner/PanoCore/uy360_ba_diagnostics.hpp"
#include <opencv2/imgproc.hpp>
#include <cmath>
#import <XCTest/XCTest.h>
#import "../Runner/PanoCore/UyStitcher.h"
#import "RunnerTests-Swift.h"

static cv::Mat sourceImage() {
    cv::Mat image(1024, 2048, CV_8UC3);
    for (int y = 0; y < image.rows; ++y)
        for (int x = 0; x < image.cols; ++x) {
            const float checker = ((x / 64 + y / 64) % 2) ? 1.f : 0.65f;
            image.at<cv::Vec3b>(y, x) = cv::Vec3b((40 + x * 160 / 2048) * checker,
                                                (50 + y * 150 / 1024) * checker, 140 * checker);
        }
    cv::RNG rng(813);
    for (int i = 0; i < 1500; ++i) {
        cv::Point p(rng.uniform(0, 2048), rng.uniform(0, 1024));
        cv::Scalar color(rng.uniform(30, 240), rng.uniform(30, 240), rng.uniform(30, 240));
        const int radius = rng.uniform(2, 9);
        for (int y = std::max(0, p.y - radius); y <= std::min(1023, p.y + radius); ++y)
            for (int x = std::max(0, p.x - radius); x <= std::min(2047, p.x + radius); ++x)
                if ((x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) <= radius * radius)
                    image.at<cv::Vec3b>(y, x) = cv::Vec3b(color[0], color[1], color[2]);
    }
    for (int x = 0; x < 2048; x += 128) image.colRange(x, x + 2).setTo(cv::Scalar(240, 240, 240));
    return image;
}

static std::vector<uy360::FrameInput> rotationCapture(NSString *dir, const cv::Mat& source,
                                                   float pivot = 0, bool arkit = false) {
    std::vector<std::pair<float, float>> targets;
    if (arkit) {
        // Existing Kadastr capture: 28 required views, optional zenith omitted.
        for (int i = 0; i < 12; ++i) targets.push_back({i * 30.f, 0});
        for (float pitch : {45.f, -45.f})
            for (int i = 0; i < 8; ++i) targets.push_back({i * 45.f + 22.5f, pitch});
    } else {
        for (int i = 0; i < 8; ++i) targets.push_back({i * 45.f, 0});
        for (float pitch : {52.f, -52.f})
            for (int i = 0; i < 4; ++i) targets.push_back({i * 90.f + 45, pitch});
        targets.push_back({0, 89});
    }
    std::vector<uy360::FrameInput> frames;
    const int w = 1008, h = 756;
    const float f = w / (2 * std::tan((arkit ? 34.5 : 52) * M_PI / 180));
    for (auto target : targets) {
        float yaw = target.first * M_PI / 180, pitch = target.second * M_PI / 180;
        cv::Vec3f z(-std::cos(pitch) * std::sin(yaw), -std::sin(pitch), std::cos(pitch) * std::cos(yaw));
        cv::Vec3f x = cv::normalize(cv::Vec3f(0, 1, 0).cross(z)), y = z.cross(x);
        cv::Matx33f R(x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]);
        R = R * cv::Matx33f(0, 1, 0, -1, 0, 0, 0, 0, 1); // portrait sensor
        cv::Mat mx(h, w, CV_32F), my(h, w, CV_32F);
        for (int v = 0; v < h; ++v)
            for (int u = 0; u < w; ++u) {
                cv::Vec3f ray = cv::normalize(R * cv::Vec3f((u - w / 2.f) / f, -(v - h / 2.f) / f, -1));
                if (pivot != 0) {
                    // A textured sphere at 3m, photographed along the requested hand-held pivot.
                    cv::Vec3f p = -pivot * cv::Vec3f(R(0, 2), R(1, 2), R(2, 2));
                    float dot = ray.dot(p);
                    float distance = -dot + std::sqrt(dot * dot + 9 - p.dot(p));
                    ray = cv::normalize(p + distance * ray);
                }
                mx.at<float>(v, u) = (std::atan2(ray[0], -ray[2]) + M_PI) / (2 * M_PI) * source.cols - 0.5f;
                my.at<float>(v, u) = (M_PI / 2 - std::asin(ray[1])) / M_PI * source.rows - 0.5f;
            }
        cv::Mat image;
        cv::remap(source, image, mx, my, cv::INTER_LINEAR, cv::BORDER_WRAP);
        uy360::FrameInput frame;
        frame.path = std::string(dir.UTF8String) + "/frame_" + std::to_string(frames.size()) + ".jpg";
        cv::imwrite(frame.path, image, {cv::IMWRITE_JPEG_QUALITY, 95});
        frame.fx = frame.fy = f;
        frame.cx = w / 2.f; frame.cy = h / 2.f;
        frame.imageWidth = w; frame.imageHeight = h; frame.targetPitch = pitch;
        for (int r = 0; r < 3; ++r)
            for (int c = 0; c < 3; ++c) frame.transform[c * 4 + r] = R(r, c);
        frame.transform[15] = 1;
        if (arkit) {
            // ARKit supplies the measured camera positions used to render each view.
            for (int r = 0; r < 3; ++r) frame.transform[12 + r] = -pivot * R(r, 2);
        }
        frames.push_back(frame);
    }
    return frames;
}

static NSArray *frameDictionaries(const std::vector<uy360::FrameInput>& frames) {
    NSMutableArray *input = [NSMutableArray array];
    for (const auto& f : frames) {
        NSMutableArray *transform = [NSMutableArray array];
        for (float value : f.transform) [transform addObject:@(value)];
        [input addObject:@{@"path": [NSString stringWithUTF8String:f.path.c_str()], @"transform": transform,
                           @"intrinsics": @[@(f.fx), @(f.fy), @(f.cx), @(f.cy)],
                           @"imageWidth": @(f.imageWidth), @"imageHeight": @(f.imageHeight), @"targetPitch": @(f.targetPitch)}];
    }
    return input;
}

@interface StitchingTests : XCTestCase
@end

@implementation StitchingTests
// Android natijasi JSON ichida shu diagnostikani qaytaradi; u umumiy `core` da
// yashaydi, shuning uchun sinov shu yerda — iOS ham o'sha faylni kompilyatsiya
// qiladi va buzilgan format ikkala platformada ham bir xil sinadi.
- (void)testBAGeometryDiagnosticsSerializeGraphsAndUnscaledPositions {
    uy360::BAStats stats;
    stats.frameCount = 3;
    stats.acceptedPairEdges = {{0, 1}, {1, 2}};
    stats.triangulatedEdges = {{0, 1}};
    stats.cameraObservations = {12, 12, 0};
    stats.optimizedPositions = {{0, 0, 0}, {0.25f, 0, 0}, {0, 0, 0}};
    std::string encoded = uy360::baGeometryJson(stats);
    NSData *data = [NSData dataWithBytes:encoded.data() length:encoded.size()];
    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(json[@"frameCount"], @3);
    XCTAssertEqualObjects(json[@"acceptedPairEdges"], (@[@[@0, @1], @[@1, @2]]));
    XCTAssertEqualObjects(json[@"triangulatedEdges"], (@[@[@0, @1]]));
    XCTAssertEqualObjects(json[@"cameraObservations"], (@[@12, @12, @0]));
    XCTAssertEqualObjects(json[@"optimizedPositionsSolvedUnits"][1], (@[@0.25, @0, @0]));
}

- (void)testSavedCoreMotionMetadataEntersHighQualityBAAndMVS {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    // Same deterministic, well-supported 15 cm pivot as the sensor core test.
    // Photos contain parallax, but saved sensor transforms contain NO translation.
    auto frames = rotationCapture(dir, sourceImage(), .15f);
    NSArray *input = frameDictionaries(frames);
    NSMutableArray *metas = [NSMutableArray array];
    for (NSUInteger index = 0; index < input.count; ++index) {
        NSMutableDictionary *meta = [input[index] mutableCopy];
        NSString *path = meta[@"path"];
        [meta removeObjectForKey:@"path"];
        meta[@"file"] = path.lastPathComponent;
        meta[@"index"] = @(index);
        meta[@"targetId"] = @(index);
        const auto& f = frames[index];
        meta[@"targetYaw"] = @(std::atan2(-f.transform[8], f.transform[10]));
        meta[@"pixelWidth"] = meta[@"imageWidth"];
        meta[@"pixelHeight"] = meta[@"imageHeight"];
        meta[@"timestamp"] = @(index);
        meta[@"highRes"] = @YES;
        meta[@"poseSource"] = @"sensors:coremotion";
        XCTAssertEqual(f.transform[12], 0);
        XCTAssertEqual(f.transform[13], 0);
        XCTAssertEqual(f.transform[14], 0);
        [metas addObject:meta];
    }
    NSData *metadata = [NSJSONSerialization dataWithJSONObject:metas options:0 error:nil];
    NSString *metaPath = [dir stringByAppendingPathComponent:@"meta.json"];
    XCTAssertTrue([metadata writeToFile:metaPath atomically:YES]);
    XCTestExpectation *done = [self expectationWithDescription:@"Saved sensor capture finishes"];
    // Override only output size to bound test composition cost. The production
    // adapter still chooses high-quality depth and sensor BA despite mode=fast.
    [PanoStitchTestDriver stitchDirectory:dir width:1024 completion:^(NSDictionary *result) {
        XCTAssertNil(result[@"error"], @"%@", result);
        XCTAssertEqualObjects(result[@"mode"], @"mvs");
        XCTAssertEqual([result[@"frames"] intValue], 17);
        XCTAssertEqual([result[@"width"] intValue], 1024);
        XCTAssertEqual([result[@"height"] intValue], 512);
        XCTAssertGreaterThan([result[@"baSeconds"] doubleValue], 0);
        XCTAssertGreaterThan([result[@"mvsSeconds"] doubleValue], 0);
        XCTAssertGreaterThan([result[@"coverage"] doubleValue], .92);
        for (NSString *key in @[@"pano", @"preview"]) {
            NSString *path = [dir stringByAppendingPathComponent:[key stringByAppendingString:@".jpg"]];
            XCTAssertEqualObjects(result[key], path);
            cv::Mat image = cv::imread(path.UTF8String);
            XCTAssertEqual(image.cols, 1024);
            XCTAssertEqual(image.rows, 512);
            NSData *jpeg = [NSData dataWithContentsOfFile:path];
            XCTAssertGreaterThan(jpeg.length, 2u);
            if (jpeg.length >= 2) {
                const uint8_t *bytes = (const uint8_t *)jpeg.bytes;
                XCTAssertEqual(bytes[0], 0xff);
                XCTAssertEqual(bytes[1], 0xd8);
            }
        }
        XCTAssertEqualObjects([NSData dataWithContentsOfFile:metaPath], metadata);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:180];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testMeasuredARKitCaptureProcessesThroughBothBridgeModes {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    auto frames = rotationCapture(dir, sourceImage(), .2f, true);
    NSArray *input = frameDictionaries(frames);
    for (BOOL mvs : {NO, YES}) {
        NSString *pano = [dir stringByAppendingPathComponent:@"pano.jpg"];
        NSString *preview = [dir stringByAppendingPathComponent:@"preview.jpg"];
        NSDictionary *result = mvs
            ? [UyStitcher stitchMVSFrames:input width:1024 highQuality:NO sensorPoses:NO
                                panoPath:pano previewPath:preview logoPath:nil progress:nil]
            : [UyStitcher stitchFrames:input width:1024 panoPath:pano previewPath:preview logoPath:nil progress:nil];
        XCTAssertTrue([result[@"ok"] boolValue], @"%@", result);
        XCTAssertEqual([result[@"frames"] intValue], 28);
        XCTAssertGreaterThan([result[@"coverage"] doubleValue], .85);
        if (mvs) {
            XCTAssertGreaterThan([result[@"depthFrames"] intValue], 0);
            XCTAssertLessThan([result[@"baMedianAfterPx"] doubleValue], 1.0);
            XCTAssertEqual([result[@"planarGroups"] intValue], 0); // sensor-only correction stays off
            XCTAssertGreaterThan([result[@"driftMaxM"] doubleValue], .1); // measured baseline retained
            XCTAssertFalse([result[@"align"] hasPrefix:@"rotation-fallback"]);
        }
        for (NSString *path in @[pano, preview]) {
            cv::Mat image = cv::imread(path.UTF8String);
            XCTAssertEqual(image.cols, 1024);
            XCTAssertEqual(image.rows, 512);
            NSData *data = [NSData dataWithContentsOfFile:path];
            XCTAssertGreaterThan(data.length, 2u);
            if (data.length >= 2) {
                const auto *bytes = static_cast<const unsigned char *>(data.bytes);
                XCTAssertEqual(bytes[0], 0xff);
                XCTAssertEqual(bytes[1], 0xd8);
            }
        }
        NSLog(@"Measured ARKit %@ result: %@", mvs ? @"MVS" : @"rotation", result);
    }
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testMeasuredPoseWithoutBaselineKeepsUnknownConfidenceAndRotationGeometry {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    auto frames = rotationCapture(dir, sourceImage(), 0, true);
    auto options = uy360::optionsForFrameCount(int(frames.size()));
    options.width = 1024;
    options.refine = false;
    uy360::PipelineOptions pipeline;
    pipeline.sensorPoses = false;
    pipeline.runBA = false; // Isolate stereo's baseline rejection from bundle adjustment.
    pipeline.mvs.width = 160;
    pipeline.mvs.planes = 16;
    std::vector<uy360::DepthMap> depths;
    auto result = uy360::stitchMVS(frames, options, pipeline, std::string(dir.UTF8String) + "/pano.jpg",
                                  std::string(dir.UTF8String) + "/preview.jpg", {}, nullptr, nullptr, &depths);
    XCTAssertTrue(result.ok, @"%s", result.error.c_str());
    XCTAssertEqual(depths.size(), frames.size());
    // ARKit retains filled depth buffers, but marks every unsupported pixel unknown.
    // With no translation these buffers must project identically to rotation-only.
    for (const auto& depth : depths) XCTAssertEqual(cv::countNonZero(depth.conf), 0);
    std::string rotationPath = std::string(dir.UTF8String) + "/rotation.jpg";
    XCTAssertTrue(uy360::stitch(frames, options, rotationPath, "", {}).ok);
    cv::Mat rotation = cv::imread(rotationPath);
    cv::Mat actual = cv::imread(std::string(dir.UTF8String) + "/pano.jpg");
    XCTAssertFalse(rotation.empty());
    XCTAssertFalse(actual.empty());
    if (!rotation.empty() && !actual.empty()) XCTAssertGreaterThan(cv::PSNR(rotation, actual), 40.);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testEmptyCaptureReturnsFailureWithoutOutput {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *pano = [dir stringByAppendingPathComponent:@"pano.jpg"];
    NSDictionary *result = [UyStitcher stitchMVSFrames:@[] width:1024 highQuality:NO sensorPoses:NO
                                             panoPath:pano previewPath:@"" logoPath:nil progress:nil];
    XCTAssertFalse([result[@"ok"] boolValue]);
    XCTAssertEqualObjects(result[@"error"], @"no frames");
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:pano]);
}

- (void)testWeakElevationFrameCannotOverwriteCoveredRoomButStillFillsCeiling {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    auto frames = rotationCapture(dir, sourceImage());
    // A visibly inconsistent elevation view models a failed pose or moving foreground.
    // It must remain available for the unobserved ceiling, without invading the room.
    cv::imwrite(frames[8].path, cv::Mat(756, 1008, CV_8UC3, cv::Scalar(255, 0, 255)));
    frames[8].supplemental = true;
    // Remove other elevation views so that this frame also provides unique coverage.
    frames.resize(9);
    auto opt = uy360::optionsForFrameCount((int)frames.size());
    opt.width = 1024; opt.refine = false; opt.gainComp = false;
    std::string pano = std::string(dir.UTF8String) + "/pano.jpg";
    auto result = uy360::stitch(frames, opt, pano, std::string(dir.UTF8String) + "/preview.jpg", {});
    XCTAssertTrue(result.ok, @"%s", result.error.c_str());
    cv::Mat actual = cv::imread(pano);
    XCTAssertFalse(actual.empty());
    if (!actual.empty()) {
        int roomMagenta = 0, ceilingMagenta = 0;
        for (int y = 0; y < actual.rows; ++y)
            for (int x = 0; x < actual.cols; ++x) {
                auto c = actual.at<cv::Vec3b>(y, x);
                bool magenta = c[0] > 220 && c[2] > 220 && c[1] < 40;
                if (magenta && y >= 210 && y < 300) ++roomMagenta;
                if (magenta && y < 160) ++ceilingMagenta;
            }
        XCTAssertEqual(roomMagenta, 0);
        XCTAssertGreaterThan(ceilingMagenta, 100);
    }
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testUltraWideRotationRoundTripThroughIOSBridge {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    cv::Mat source = sourceImage();
    auto frames = rotationCapture(dir, source);
    NSArray *input = frameDictionaries(frames);
    NSString *pano = [dir stringByAppendingPathComponent:@"pano.jpg"];
    NSDictionary *result = [UyStitcher stitchMVSFrames:input width:2048 highQuality:YES sensorPoses:YES
                                            panoPath:pano previewPath:[dir stringByAppendingPathComponent:@"preview.jpg"]
                                            logoPath:nil progress:nil];
    XCTAssertTrue([result[@"ok"] boolValue], @"%@", result);
    XCTAssertEqual([result[@"frames"] intValue], 17);
    XCTAssertEqual([result[@"depthFrames"] intValue], 0, @"Pure rotation must not invent depth");
    XCTAssertGreaterThan([result[@"coverage"] doubleValue], 0.92);
    cv::Mat actual = cv::imread(pano.UTF8String);
    XCTAssertEqual(actual.cols, 2048);
    XCTAssertEqual(actual.rows, 1024);
    if (!actual.empty()) {
        // Exclude the deliberately unphotographed nadir (bottom 12 degrees).
        const cv::Rect measured(0, 0, 2048, 900);
        double psnr = cv::PSNR(source(measured), actual(measured));
        NSLog(@"Ultra-wide synthetic round-trip PSNR: %.2f dB; %@", psnr, result);
        XCTAssertGreaterThan(psnr, 24.0);
    }
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testObservableTranslationStillUsesDepth {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    // A 15 cm pivot gives robust feature support with the pinned OpenCV build.
    auto frames = rotationCapture(dir, sourceImage(), 0.15f);
    NSDictionary *result = [UyStitcher stitchMVSFrames:frameDictionaries(frames) width:1024 highQuality:NO sensorPoses:YES
                                            panoPath:[dir stringByAppendingPathComponent:@"pano.jpg"]
                                         previewPath:[dir stringByAppendingPathComponent:@"preview.jpg"]
                                            logoPath:nil progress:nil];
    XCTAssertTrue([result[@"ok"] boolValue], @"%@", result);
    XCTAssertEqual([result[@"depthFrames"] intValue], 17, @"%@", result);
    XCTAssertLessThan([result[@"baMedianAfterPx"] doubleValue], 1.0);
    XCTAssertGreaterThan([result[@"coverage"] doubleValue], 0.92);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testUnderconstrainedSensorCaptureFallsBackToRotation {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    auto frames = rotationCapture(dir, sourceImage(), .2f);
    // Five textureless views leave at most 12 supported cameras, below the
    // required 13 of 17, regardless of randomized feature-matching results.
    for (size_t index = 12; index < frames.size(); ++index) {
        XCTAssertTrue(cv::imwrite(frames[index].path,
                                 cv::Mat(756, 1008, CV_8UC3, cv::Scalar(120, 120, 120))));
    }
    // Returning a pose vector must not be mistaken for reliable translation.
    NSDictionary *result = [UyStitcher stitchMVSFrames:frameDictionaries(frames) width:1024
                                          highQuality:NO sensorPoses:YES
                                             panoPath:[dir stringByAppendingPathComponent:@"pano.jpg"]
                                          previewPath:[dir stringByAppendingPathComponent:@"preview.jpg"]
                                             logoPath:nil progress:nil];
    XCTAssertTrue([result[@"ok"] boolValue], @"%@", result);
    XCTAssertEqual([result[@"depthFrames"] intValue], 0, @"%@", result);
    XCTAssertTrue([result[@"align"] hasPrefix:@"rotation-fallback"], @"%@", result);
    XCTAssertEqual([result[@"mvsSeconds"] doubleValue], 0);
    XCTAssertEqual([result[@"driftMaxM"] doubleValue], 0);
    cv::Mat image = cv::imread(std::string(dir.UTF8String) + "/pano.jpg");
    XCTAssertEqual(image.cols, 1024);
    XCTAssertEqual(image.rows, 512);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testUnknownTranslationCanOpposeTheAssumedBodyPivot {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    cv::Mat source = sourceImage();
    auto frames = rotationCapture(dir, source, -0.2f);
    NSString *pano = [dir stringByAppendingPathComponent:@"pano.jpg"];
    NSDictionary *result = [UyStitcher stitchMVSFrames:frameDictionaries(frames) width:2048 highQuality:NO sensorPoses:YES
                                            panoPath:pano previewPath:[dir stringByAppendingPathComponent:@"preview.jpg"]
                                            logoPath:nil progress:nil];
    XCTAssertTrue([result[@"ok"] boolValue], @"%@", result);
    XCTAssertEqual([result[@"depthFrames"] intValue], 17);
    cv::Mat actual = cv::imread(pano.UTF8String);
    XCTAssertFalse(actual.empty());
    if (!actual.empty()) {
        const cv::Rect measured(0, 0, 2048, 900);
        double psnr = cv::PSNR(source(measured), actual(measured));
        NSLog(@"Reverse-pivot round-trip PSNR: %.2f dB", psnr);
        XCTAssertGreaterThan(psnr, 19.0);
    }
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}

- (void)testNoFeaturesDoesNotReturnInventedSensorTranslation {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    auto frames = rotationCapture(dir, cv::Mat(1024, 2048, CV_8UC3, cv::Scalar(120, 120, 120)));
    uy360::BAStats stats;
    auto poses = uy360::bundleAdjustPoses(frames, uy360::BAOptions::forSensorPoses(), {}, &stats);
    XCTAssertEqual(stats.points, 0);
    XCTAssertEqual(poses.size(), frames.size());
    for (const auto& pose : poses) XCTAssertLessThan(cv::norm(pose.p), 0.00001);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}
- (void)testInvisibleStereoWorkCanBeSkippedWithoutChangingDepth {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    auto frames = rotationCapture(dir, sourceImage(), .2f);
    std::vector<uy360::Pose> poses;
    for (const auto& f : frames) {
        uy360::Pose p;
        for (int r = 0; r < 3; ++r) for (int c = 0; c < 3; ++c) p.R(r, c) = f.transform[c * 4 + r];
        p.p = -.2f * cv::Vec3f(p.R(0, 2), p.R(1, 2), p.R(2, 2));
        poses.push_back(p);
    }
    uy360::MvsOptions options;
    options.width = 160; options.planes = 16; options.neighbours = 4;
    options.zMin = .1f; options.zMax = 6;
    options.cullInvisibleNeighbours = false;
    auto full = uy360::computeDepthMaps(frames, poses, options, {}, nullptr);
    options.cullInvisibleNeighbours = true;
    auto optimized = uy360::computeDepthMaps(frames, poses, options, {}, nullptr);
    XCTAssertEqual(full.size(), optimized.size());
    for (size_t i = 0; i < full.size(); ++i) {
        XCTAssertEqual(cv::norm(full[i].conf, optimized[i].conf, cv::NORM_INF), 0.);
        XCTAssertEqual(cv::norm(full[i].z, optimized[i].z, cv::NORM_INF), 0.);
    }
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}
- (void)testDetailEnhancementIsBoundedAndDoesNotMovePixels {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    auto frames = rotationCapture(dir, sourceImage());
    uy360::Options options = uy360::optionsForFrameCount(int(frames.size()));
    options.width = 1024; options.refine = false; options.seams = false; options.gainComp = false;
    options.sharpening = 0;
    std::string before = std::string(dir.UTF8String) + "/before.png";
    std::string after = std::string(dir.UTF8String) + "/after.png";
    XCTAssertTrue(uy360::stitch(frames, options, before, "", {}).ok);
    options.sharpening = .2f;
    XCTAssertTrue(uy360::stitch(frames, options, after, "", {}).ok);
    cv::Mat a = cv::imread(before), b = cv::imread(after), delta;
    XCTAssertEqual(a.size(), b.size());
    cv::absdiff(a, b, delta);
    XCTAssertLessThanOrEqual(cv::norm(a, b, cv::NORM_INF), 3.);
    XCTAssertGreaterThan(cv::countNonZero(delta.reshape(1)), 0);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
}
// Regression for stuff: 13/17 cameras pass the legacy policy, but four
// invented translations must not enter Android sensor MVS. End-to-end fixture
// and saved-JPEG replay coverage live in Android's PanoDeviceTest.
- (void)testSensorTranslationSupportRequiresEveryCameraWhenOptedIn {
    XCTAssertFalse(uy360::PipelineOptions().requireAllSensorCameras);
    XCTAssertTrue(uy360::sensorTranslationSupported(13, 17, false));
    XCTAssertFalse(uy360::sensorTranslationSupported(12, 17, false));
    XCTAssertFalse(uy360::sensorTranslationSupported(13, 17, true));
    XCTAssertFalse(uy360::sensorTranslationSupported(16, 17, true));
    XCTAssertTrue(uy360::sensorTranslationSupported(17, 17, true));
    XCTAssertTrue(uy360::sensorTranslationSupported(4, 4, true));
    XCTAssertFalse(uy360::sensorTranslationSupported(0, 17, true));
    XCTAssertFalse(uy360::sensorTranslationSupported(0, 0, true));
    XCTAssertFalse(uy360::sensorTranslationSupported(2, 2, true));
    XCTAssertFalse(uy360::sensorTranslationSupported(18, 17, true));
}

@end
