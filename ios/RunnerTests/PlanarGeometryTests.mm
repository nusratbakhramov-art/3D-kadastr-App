#include "../Runner/PanoCore/uy360_planar.hpp"
#include <opencv2/imgproc.hpp>
#include <cmath>
#import <XCTest/XCTest.h>

namespace {
struct Fixture {
    std::vector<uy360::FrameInput> frames;
    std::vector<uy360::Pose> poses;
    std::vector<uy360::DepthMap> depths;
    std::vector<cv::Mat> interior;
};

// Three calibrated views of an upright board at world z=-2. Stereo depth is
// deliberately wavy; the photographed silhouette remains the true rectangle.
Fixture board(NSString *directory) {
    Fixture fixture;
    constexpr int width = 1008, height = 756;
    constexpr float focal = 600;
    for (int i = 0; i < 3; ++i) {
        float yaw = (i - 1) * 20 * M_PI / 180;
        uy360::Pose pose;
        pose.R = cv::Matx33f(std::cos(yaw), 0, -std::sin(yaw), 0, 1, 0, std::sin(yaw), 0, std::cos(yaw)) *
                 cv::Matx33f(0, 1, 0, -1, 0, 0, 0, 0, 1);
        pose.p = {-0.2f + .2f * i, 0, -0.2f + .225f * i};
        uy360::DepthMap depth;
        depth.fx = depth.fy = focal; depth.cx = width / 2; depth.cy = height / 2;
        depth.z = cv::Mat(height, width, CV_32F, cv::Scalar(4));
        depth.conf = cv::Mat(height, width, CV_8U, cv::Scalar(1));
        cv::Mat image(height, width, CV_8UC3, cv::Scalar(220, 220, 220));
        cv::Mat interior = cv::Mat::zeros(height, width, CV_8U);
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
            cv::Vec3f ray = pose.R * cv::Vec3f((x - depth.cx) / focal, -(y - depth.cy) / focal, -1);
            float t = (-2 - pose.p[2]) / ray[2];
            cv::Vec3f world = pose.p + t * ray;
            if (t > 0 && std::abs(world[0]) < 1 && std::abs(world[1]) < .8) {
                image.at<cv::Vec3b>(y, x) = {20, 20, 20};
                depth.z.at<float>(y, x) = t * (1 + .15f * std::sin(x / 80.f) * std::cos(y / 65.f));
                if (std::abs(world[0]) < .75 && std::abs(world[1]) < .6) interior.at<uchar>(y, x) = 255;
            }
        }
        uy360::FrameInput frame;
        frame.path = std::string(directory.UTF8String) + "/frame_" + std::to_string(i) + ".png";
        frame.imageWidth = width; frame.imageHeight = height;
        frame.fx = frame.fy = focal; frame.cx = depth.cx; frame.cy = depth.cy;
        cv::imwrite(frame.path, image);
        fixture.frames.push_back(frame); fixture.poses.push_back(pose);
        fixture.depths.push_back(depth); fixture.interior.push_back(interior);
    }
    return fixture;
}

double planeError(const Fixture& fixture) {
    double error = 0; int count = 0;
    for (size_t i = 0; i < fixture.frames.size(); ++i) {
        const auto& d = fixture.depths[i];
        const auto& p = fixture.poses[i];
        for (int y = 0; y < d.z.rows; y += 8) for (int x = 0; x < d.z.cols; x += 8) {
            if (!fixture.interior[i].at<uchar>(y, x)) continue;
            cv::Vec3f ray((x - d.cx) / d.fx, -(y - d.cy) / d.fy, -1);
            cv::Vec3f world = p.p + p.R * (ray * d.z.at<float>(y, x));
            error += std::abs(world[2] + 2); ++count;
        }
    }
    return error / std::max(1, count);
}
}

@interface PlanarGeometryTests : XCTestCase
@end

@implementation PlanarGeometryTests
- (void)testNearPlaneProjectionReturnsTheObservedPixelExactly {
    uy360::DepthMap depth;
    depth.z = cv::Mat(756, 1008, CV_32F, cv::Scalar(1));
    depth.planarMask = cv::Mat(756, 1008, CV_8U, cv::Scalar(255));
    depth.fx = depth.fy = 400; depth.cx = 504; depth.cy = 378;
    depth.planarNormal = {.8f, 0, -.6f}; depth.planarOffset = .64f;
    const cv::Vec3f observed(.2f, -.1f, -.8f), offset(.3f, .1f, .15f);
    cv::Vec3f direction = cv::normalize(observed + offset), actual;
    XCTAssertTrue(uy360::depthPlanePoint(depth, direction, offset, actual));
    XCTAssertLessThan(cv::norm(actual - observed), 0.00001);
    XCTAssertEqualWithAccuracy(depth.fx * actual[0] / -actual[2] + depth.cx, 604., .001);
    depth.planarMask.setTo(0);
    XCTAssertFalse(uy360::depthPlanePoint(depth, direction, offset, actual));
}

- (void)testSharedEdgesRecoverFlatGeometryWithoutChangingBackground {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    auto fixture = board(directory);
    XCTAssertGreaterThan(planeError(fixture), .08);
    auto result = uy360::regularizePlanarObjects(fixture.frames, fixture.poses, fixture.depths);
    XCTAssertEqual(result.groups, 1);
    XCTAssertEqual(result.frames, 3);
    XCTAssertLessThan(planeError(fixture), .03);
    for (const auto& depth : fixture.depths) XCTAssertEqual(depth.z.at<float>(0, 0), 4.f);
    for (size_t i = 0; i < fixture.frames.size(); ++i) {
        cv::Mat image = cv::imread(fixture.frames[i].path, cv::IMREAD_GRAYSCALE);
        cv::Mat background = image > 150;
        cv::erode(background, background, cv::Mat::ones(7, 7, CV_8U));
        XCTAssertEqual(cv::countNonZero((fixture.depths[i].z != 4.f) & background), 0);
    }
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}

- (void)testUnobservablePlaneCannotInventDepthOrTranslation {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    auto fixture = board(directory);
    for (auto& pose : fixture.poses) pose.p = {0, 0, 0};
    std::vector<cv::Mat> originals;
    for (const auto& depth : fixture.depths) originals.push_back(depth.z.clone());
    auto result = uy360::regularizePlanarObjects(fixture.frames, fixture.poses, fixture.depths);
    XCTAssertEqual(result.groups, 0);
    for (size_t i = 0; i < fixture.frames.size(); ++i) {
        XCTAssertEqual(cv::norm(originals[i], fixture.depths[i].z, cv::NORM_INF), 0.);
        XCTAssertEqual(cv::norm(fixture.poses[i].p), 0.);
    }
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}

- (void)testWindowSilhouetteCannotFlattenReliableDepthBehindIt {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    auto fixture = board(directory);
    std::vector<cv::Mat> originals;
    for (size_t i = 0; i < fixture.depths.size(); ++i) {
        auto& depth = fixture.depths[i];
        depth.z.setTo(5, fixture.interior[i]);
        depth.conf.setTo(2, fixture.interior[i]);
        originals.push_back(depth.z.clone());
    }
    auto result = uy360::regularizePlanarObjects(fixture.frames, fixture.poses, fixture.depths);
    XCTAssertEqual(result.groups, 0);
    for (size_t i = 0; i < fixture.depths.size(); ++i)
        XCTAssertEqual(cv::norm(originals[i], fixture.depths[i].z, cv::NORM_INF), 0.);
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}

- (void)testVerifiedForegroundBlocksAnInconsistentBackgroundView {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    auto fixture = board(directory);
    auto fitted = uy360::regularizePlanarObjects(fixture.frames, fixture.poses, fixture.depths);
    XCTAssertEqual(fitted.groups, 1);
    auto background = fixture.frames[1];
    background.path = std::string(directory.UTF8String) + "/background.png";
    cv::imwrite(background.path, cv::Mat(756, 1008, CV_8UC3, cv::Scalar(255, 0, 0)));
    auto depth = fixture.depths[1];
    depth.z = cv::Mat(756, 1008, CV_32F, cv::Scalar(5));
    depth.planarMask.release();
    fixture.frames.push_back(background); fixture.poses.push_back(fixture.poses[1]); fixture.depths.push_back(depth);
    auto options = uy360::optionsForFrameCount(4);
    options.width = 1024; options.seams = false; options.gainComp = false;
    auto path = std::string(directory.UTF8String) + "/pano.jpg";
    auto result = uy360::stitchWithDepth(fixture.frames, fixture.poses, fixture.depths, options,
                                        path, std::string(directory.UTF8String) + "/preview.jpg", {});
    XCTAssertTrue(result.ok);
    cv::Mat panorama = cv::imread(path);
    XCTAssertFalse(panorama.empty());
    if (!panorama.empty()) {
        cv::Scalar color = cv::mean(panorama(cv::Rect(508, 252, 8, 8)));
        XCTAssertLessThan(color[0], 40.); // background blue must not enter the observed board
        XCTAssertLessThan(std::abs(color[0] - color[2]), 5.);
    }
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}

- (void)testBroadestPlaneObservationOwnsItsInteriorAcrossReflections {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    auto fixture = board(directory);
    auto fitted = uy360::regularizePlanarObjects(fixture.frames, fixture.poses, fixture.depths);
    XCTAssertEqual(fitted.groups, 1);
    // Equal geometry but a view-dependent bright reflection in a partial view.
    // Put that view first: per-pixel feather ties must not give it ownership of
    // the central surface when another observation covers the whole board.
    auto fullFrame = fixture.frames[1];
    auto fullPose = fixture.poses[1];
    auto fullDepth = fixture.depths[1];
    auto partialFrame = fullFrame;
    partialFrame.path = std::string(directory.UTF8String) + "/reflection.png";
    cv::imwrite(partialFrame.path, cv::Mat(756, 1008, CV_8UC3, cv::Scalar(240, 240, 240)));
    auto partialDepth = fullDepth;
    partialDepth.planarMask = fullDepth.planarMask.clone();
    cv::erode(partialDepth.planarMask, partialDepth.planarMask, cv::Mat::ones(151, 151, CV_8U));
    std::vector<uy360::FrameInput> frames{partialFrame, fullFrame};
    std::vector<uy360::Pose> poses{fullPose, fullPose};
    std::vector<uy360::DepthMap> depths{partialDepth, fullDepth};
    auto options = uy360::optionsForFrameCount(2);
    options.width = 1024; options.seams = false; options.gainComp = false;
    auto path = std::string(directory.UTF8String) + "/pano.jpg";
    auto result = uy360::stitchWithDepth(frames, poses, depths, options, path,
                                        std::string(directory.UTF8String) + "/preview.jpg", {});
    XCTAssertTrue(result.ok);
    cv::Mat panorama = cv::imread(path);
    XCTAssertFalse(panorama.empty());
    if (!panorama.empty()) {
        cv::Scalar center = cv::mean(panorama(cv::Rect(508, 252, 8, 8)));
        XCTAssertLessThan(center[0], 40.);
        XCTAssertLessThan(center[1], 40.);
        XCTAssertLessThan(center[2], 40.);
    }
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}
- (void)testFineSilhouetteResolvesEdgesWithinOneStereoPixel {
    uy360::DepthMap depth;
    depth.z = cv::Mat(8, 8, CV_32F, cv::Scalar(1));
    depth.planarMask = cv::Mat::zeros(32, 32, CV_8U);
    for (int y = 0; y < 32; ++y) for (int x = y + 1; x < 32; ++x) depth.planarMask.at<uchar>(y, x) = 255;
    XCTAssertTrue(uy360::depthPlaneContains(depth, 2.4f, 2.0f));
    XCTAssertFalse(uy360::depthPlaneContains(depth, 2.0f, 2.4f));
    XCTAssertFalse(uy360::depthPlaneContains(depth, -0.1f, 2.f));
}

- (void)testRepeatedCeilingEdgesRecoverFixtureWithoutFlatteningBackground {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    std::vector<uy360::FrameInput> frames;
    std::vector<uy360::Pose> poses;
    std::vector<uy360::DepthMap> depths;
    cv::Matx33f yaw(std::cos(.37f), 0, -std::sin(.37f), 0, 1, 0, std::sin(.37f), 0, std::cos(.37f));
    for (int i = 0; i < 4; ++i) {
        uy360::Pose pose;
        pose.p = yaw * cv::Vec3f((i - 1.5f) * .11f, i % 2 ? .08f : -.07f, (i % 2 - .5f) * .2f);
        cv::Vec3f forward = cv::normalize(yaw * cv::Vec3f(0, 2, -.2f) - pose.p);
        cv::Vec3f right = yaw * cv::Vec3f(1, 0, 0);
        right = cv::normalize(right - forward * right.dot(forward));
        cv::Vec3f up = right.cross(forward);
        pose.R = cv::Matx33f(right[0], up[0], -forward[0], right[1], up[1], -forward[1], right[2], up[2], -forward[2]);
        uy360::DepthMap depth;
        depth.fx = depth.fy = 650; depth.cx = 504; depth.cy = 378;
        depth.z = cv::Mat(756, 1008, CV_32F); depth.conf = cv::Mat(756, 1008, CV_8U, cv::Scalar(1));
        cv::Mat image(756, 1008, CV_8UC3, cv::Scalar(35, 35, 35));
        for (int y = 0; y < image.rows; ++y) for (int x = 0; x < image.cols; ++x) {
            cv::Vec3f ray = pose.R * cv::Vec3f((x - depth.cx) / depth.fx, -(y - depth.cy) / depth.fy, -1);
            float z = (2 - pose.p[1]) / ray[1];
            cv::Vec3f world = yaw.t() * (pose.p + ray * z);
            float u = std::abs(world[0]), v = std::abs(world[2] + .2f);
            bool strip = (std::abs(u - .7f) < .035f && v < .635f) || (std::abs(v - .6f) < .035f && u < .735f);
            if (strip) image.at<cv::Vec3b>(y, x) = {225, 225, 225};
            bool measured = !strip && x % 4 == 0 && y % 4 == 0;
            depth.conf.at<uchar>(y, x) = measured ? 2 : 1;
            depth.z.at<float>(y, x) = measured ? z : z * (1 + .18f * std::sin(x / 61.f) * std::cos(y / 75.f));
        }
        uy360::FrameInput frame;
        frame.path = std::string(directory.UTF8String) + "/ceiling_" + std::to_string(i) + ".png";
        frame.imageWidth = 1008; frame.imageHeight = 756;
        frame.fx = depth.fx; frame.fy = depth.fy; frame.cx = depth.cx; frame.cy = depth.cy;
        cv::imwrite(frame.path, image);
        frames.push_back(frame); poses.push_back(pose); depths.push_back(depth);
    }
    std::vector<cv::Mat> originals;
    for (const auto& d : depths) originals.push_back(d.z.clone());
    int count = uy360::regularizeCeilingFixtures(frames, poses, depths);
    XCTAssertEqual(count, 1);
    int observations = 0;
    for (size_t i = 0; i < depths.size(); ++i) {
        XCTAssertEqual(cv::norm(depths[i].z, originals[i], cv::NORM_INF), 0.);
        for (const auto& patch : depths[i].patches) {
            ++observations;
            XCTAssertEqualWithAccuracy(patch.center[1], 2.f, .08f);
            XCTAssertLessThan(cv::norm(patch.cameraPosition - poses[i].p), .03);
        }
        depths[i].patches.clear();
    }
    XCTAssertGreaterThanOrEqual(observations, 3);
    // The same rays with no baseline cannot determine a physical plane height.
    for (auto& pose : poses) pose.p = {0, 0, 0};
    XCTAssertEqual(uy360::regularizeCeilingFixtures(frames, poses, depths), 0);
    for (auto& d : depths) { d.conf.setTo(1); d.patches.clear(); }
    XCTAssertEqual(uy360::regularizeCeilingFixtures(frames, poses, depths), 0);
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}
- (void)testSharedWallCorrectsSparseViewAndPreservesForeground {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    auto fixture = board(directory);
    std::vector<cv::Mat> foreground;
    for (size_t i = 0; i < fixture.frames.size(); ++i) {
        auto& depth = fixture.depths[i]; const auto& pose = fixture.poses[i];
        cv::Mat image = cv::imread(fixture.frames[i].path, cv::IMREAD_GRAYSCALE);
        foreground.push_back(image < 100);
        for (int y = 0; y < image.rows; ++y) for (int x = 0; x < image.cols; ++x) {
            if (image.at<uchar>(y, x) < 100) continue;
            cv::Vec3f ray = pose.R * cv::Vec3f((x - depth.cx) / depth.fx, -(y - depth.cy) / depth.fy, -1);
            float z = (-4 - pose.p[2]) / ray[2];
            cv::Vec3f world = pose.p + ray * z;
            bool measured = (x + y) % 4 == 0 && (i == 0 || std::abs(world[0] - 1.7f) < .05f);
            depth.conf.at<uchar>(y, x) = measured ? 2 : 1;
            depth.z.at<float>(y, x) = measured ? z : z * (1 + .12f * std::sin(x / 50.f));
        }
    }
    std::vector<cv::Mat> original;
    for (const auto& d : fixture.depths) original.push_back(d.z.clone());
    int regions = uy360::regularizeWallSurfaces(fixture.frames, fixture.poses, fixture.depths);
    XCTAssertGreaterThanOrEqual(regions, 2);
    for (size_t i = 0; i < fixture.depths.size(); ++i) {
        cv::Mat inner;
        cv::erode(foreground[i], inner, cv::Mat::ones(15, 15, CV_8U));
        cv::Mat difference; cv::absdiff(original[i], fixture.depths[i].z, difference);
        double max = 0; cv::minMaxLoc(difference, nullptr, &max, nullptr, nullptr, inner);
        XCTAssertEqual(max, 0.);
    }
    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}

- (void)testSharedWallProjectsExactlyAndRejectsForegroundPixels {
    uy360::DepthMap depth;
    depth.z = cv::Mat(756, 1008, CV_32F, cv::Scalar(2));
    depth.fx = depth.fy = 400; depth.cx = 504; depth.cy = 378;
    uy360::WallSurface wall;
    wall.normal = {.8f, 0, -.6f}; wall.offset = .64f;
    wall.mask = cv::Mat(756, 1008, CV_8U, cv::Scalar(255));
    depth.walls.push_back(wall);
    const cv::Vec3f observed(.2f, -.1f, -.8f), offset(.3f, .1f, .15f);
    cv::Vec3f direction = cv::normalize(observed + offset), point;
    XCTAssertTrue(uy360::depthWallPoint(depth, direction, offset, point));
    XCTAssertLessThan(cv::norm(point - observed), .00001);
    // A photographed foreground cutout cannot be replaced by the wall behind it.
    depth.walls.front().mask(cv::Rect(599, 423, 11, 11)).setTo(0);
    XCTAssertFalse(uy360::depthWallPoint(depth, direction, offset, point));
    XCTAssertFalse(uy360::depthWallPoint(depth, -direction, offset, point));
}
@end
