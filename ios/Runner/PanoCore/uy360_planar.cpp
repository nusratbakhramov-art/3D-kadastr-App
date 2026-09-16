#include "uy360_planar.hpp"

#include <opencv2/imgproc.hpp>
#if CV_VERSION_MAJOR >= 5
#include <opencv2/geometry/2d.hpp>
#endif

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <set>

namespace uy360 {
namespace {
using cv::Mat;
using cv::Vec3d;
const Vec3d up(0, 1, 0);

struct Edge {
    Vec3d normal;
    double offset = 0, pitch = 0;
};
struct Region {
    int frame = 0, area = 0;
    Mat mask;
    Vec3d normal;
    std::array<Edge, 2> edges;
};

double quantile(std::vector<float> values, double fraction) {
    if (values.empty()) return 0;
    size_t index = std::min(values.size() - 1, size_t(fraction * (values.size() - 1)));
    std::nth_element(values.begin(), values.begin() + index, values.end());
    return values[index];
}

// Include a narrow frame/bezel around the detected rectangle without painting
// the surrounding wall onto its plane. Follow the observed contrast at the rim;
// when there is no clear contrast, keep only a small antialiasing margin.
Mat surfaceMask(const Mat& coarseRegion, const FrameInput& frame) {
    const int width = std::min(frame.imageWidth, coarseRegion.cols * 4);
    Mat image = imreadForWidth(frame.path, width, frame.imageWidth, false);
    Mat region;
    cv::resize(coarseRegion, region, cv::Size(width, cvRound(double(coarseRegion.rows) * width / coarseRegion.cols)),
               0, 0, cv::INTER_NEAREST);
    if (image.empty()) return region.clone();
    cv::resize(image, image, region.size());
    const int radius = std::max(1, cvRound(9 * region.cols / 1008.));
    Mat inner, expanded;
    int inset = std::max(1, cvRound(2 * region.cols / 1008.));
    cv::erode(region, inner, Mat::ones(2 * inset + 1, 2 * inset + 1, CV_8U));
    cv::dilate(region, expanded, Mat::ones(2 * radius + 1, 2 * radius + 1, CV_8U));
    std::vector<float> inside, outside;
    for (int y = 0; y < region.rows; ++y) for (int x = 0; x < region.cols; ++x) {
        if (region.at<uchar>(y, x) && !inner.at<uchar>(y, x)) inside.push_back(image.at<uchar>(y, x));
        if (expanded.at<uchar>(y, x) && !region.at<uchar>(y, x)) outside.push_back(image.at<uchar>(y, x));
    }
    double a = quantile(inside, .5), b = quantile(outside, .5);
    Mat mask = region.clone();
    if (inside.empty() || outside.empty() || std::abs(a - b) < 20) {
        int margin = std::max(1, cvRound(3 * region.cols / 1008.));
        cv::dilate(region, mask, Mat::ones(2 * margin + 1, 2 * margin + 1, CV_8U));
        return mask;
    }
    Mat allowed = a < b ? image < (a + b) * .5 : image > (a + b) * .5;
    // Revisit the narrow polygon rim as well: its reduced-resolution, rounded
    // corners can already contain a few background pixels before expansion.
    allowed |= inner;
    mask = inner.clone();
    for (int i = 0; i < radius + 2; ++i) {
        cv::dilate(mask, mask, Mat::ones(3, 3, CV_8U));
        mask &= allowed & expanded;
    }
    return mask;
}

bool rectangle(const Mat& region, const std::vector<cv::Vec4f>& segments,
               std::array<Vec3d, 4>& lines, std::array<bool, 4>& borders, Mat& mask) {
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(region, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    if (contours.empty()) return false;
    auto largest = std::max_element(contours.begin(), contours.end(), [](const auto& a, const auto& b) {
        return cv::contourArea(a) < cv::contourArea(b);
    });
    std::vector<cv::Point> hull, polygon;
    cv::convexHull(*largest, hull);
    double perimeter = cv::arcLength(hull, true);
    for (double epsilon : {.01, .015, .02, .025, .03}) {
        cv::approxPolyDP(hull, polygon, epsilon * perimeter, true);
        if (polygon.size() == 4) break;
    }
    if (polygon.size() != 4) return false;
    mask = Mat::zeros(region.size(), CV_8U);
    cv::fillConvexPoly(mask, polygon, 255);
    if (double(cv::countNonZero(mask & region)) / std::max(1, cv::countNonZero(mask | region)) < .83) return false;
    const double scale = region.cols / 1008.;
    int borderCount = 0, refined = 0;
    for (int j = 0; j < 4; ++j) {
        cv::Point2d a = polygon[j], b = polygon[(j + 1) % 4];
        cv::Point2d direction = b - a;
        double length = cv::norm(direction);
        if (length < 1) return false;
        direction *= 1 / length;
        cv::Point2d normal(-direction.y, direction.x), mid = (a + b) * .5;
        borders[j] = std::min({mid.x, mid.y, region.cols - mid.x, region.rows - mid.y}) <= 8 * scale;
        borderCount += borders[j];
        double best = 0;
        cv::Point2d bestA, bestB;
        if (!borders[j]) for (const auto& segment : segments) {
            cv::Point2d c(segment[0], segment[1]), d(segment[2], segment[3]), vector = d - c;
            double len = cv::norm(vector);
            if (len < std::max(25 * scale, length * .15) || std::abs(vector.dot(direction)) / len < .99) continue;
            double distance = std::abs(((c + d) * .5 - mid).dot(normal));
            if (distance > 18 * scale) continue;
            double lo = (c - a).dot(direction), hi = (d - a).dot(direction);
            if (lo > hi) std::swap(lo, hi);
            double overlap = std::max(0., std::min(length, hi) - std::max(0., lo));
            double score = overlap / (2 * scale + distance);
            if (score > best) { best = score; bestA = c; bestB = d; }
        }
        if (best > 0) {
            ++refined;
            a = bestA; b = bestB; direction = b - a; direction *= 1 / cv::norm(direction);
            normal = {-direction.y, direction.x};
        }
        lines[j] = {normal.x, normal.y, -normal.dot(a)};
    }
    if (borderCount > 1 || refined < 2) return false;
    std::vector<cv::Point> corners;
    for (int j = 0; j < 4; ++j) {
        Vec3d point = lines[(j + 3) % 4].cross(lines[j]);
        if (std::abs(point[2]) < .1) return false;
        cv::Point2d xy(point[0] / point[2], point[1] / point[2]);
        if (cv::norm(xy - cv::Point2d(polygon[j])) > 45 * scale) return false;
        corners.emplace_back(cvRound(xy.x), cvRound(xy.y));
    }
    if (!cv::isContourConvex(corners)) return false;
    mask.setTo(0);
    cv::fillConvexPoly(mask, corners, 255);
    return true;
}

std::vector<Region> detect(const FrameInput& frame, const Pose& pose, const DepthMap& depth, int index) {
    std::vector<Region> result;
    if (depth.z.empty() || depth.fx <= 0 || depth.fy <= 0) return result;
    Mat image = imreadForWidth(frame.path, depth.z.cols, frame.imageWidth, false);
    if (image.empty()) return result;
    cv::resize(image, image, depth.z.size());
    std::vector<cv::Vec4f> segments;
    cv::createLineSegmentDetector()->detect(image, segments);
    Mat small;
    cv::GaussianBlur(image, small, cv::Size(5, 5), 1);
    cv::resize(small, small, cv::Size(image.cols / 2, image.rows / 2));
    cv::Matx33d R = pose.R;
    cv::Matx33d K(depth.fx, 0, -depth.cx, 0, -depth.fy, -depth.cy, 0, 0, -1);
    cv::Matx33d Ki = K.inv();
    for (int threshold : {10, 15, 20, 30, 40, 50, 65, 80, 95, 110, 140}) {
        Mat edges, labels, stats, centers;
        cv::Canny(small, edges, threshold, threshold * 2);
        cv::dilate(edges, edges, Mat::ones(3, 3, CV_8U));
        int count = cv::connectedComponentsWithStats(edges == 0, labels, stats, centers);
        for (int label = 1; label < count; ++label) {
            double fraction = double(stats.at<int>(label, cv::CC_STAT_AREA)) / small.total();
            if (fraction < .025 || fraction > .85) continue;
            Mat region;
            cv::resize(labels == label, region, image.size(), 0, 0, cv::INTER_NEAREST);
            std::array<Vec3d, 4> lines;
            std::array<bool, 4> borders;
            Mat mask;
            if (!rectangle(region, segments, lines, borders, mask)) continue;
            int area = cv::countNonZero(mask);
            bool duplicate = false;
            for (const auto& old : result)
                if (double(cv::countNonZero(mask & old.mask)) / std::max(1, cv::countNonZero(mask | old.mask)) > .95) {
                    duplicate = true; break;
                }
            if (duplicate) continue;
            std::vector<Region> candidates;
            for (int j = 0; j < 2; ++j) {
                if (borders[j] || borders[j + 2]) continue;
                Vec3d direction = R * (Ki * lines[j].cross(lines[j + 2]));
                if (cv::norm(direction) < 1e-8) continue;
                direction *= 1 / cv::norm(direction);
                if (std::abs(direction[1]) > .15) continue;
                Region candidate;
                candidate.frame = index; candidate.mask = mask; candidate.area = area;
                candidate.normal = cv::normalize(direction.cross(up));
                // Both cameras see the same side of a surface: point the normal
                // towards the region, without using the unreliable stereo normal.
                cv::Moments moments = cv::moments(mask, true);
                Vec3d centerRay = R * (Ki * Vec3d(moments.m10 / moments.m00, moments.m01 / moments.m00, 1));
                if (candidate.normal.dot(centerRay) < 0) candidate.normal *= -1;
                for (int k = 0; k < 2; ++k) {
                    Vec3d line = lines[j + k * 2];
                    Edge& edge = candidate.edges[k];
                    edge.normal = cv::normalize(R * (K.t() * line));
                    edge.offset = edge.normal.dot(Vec3d(pose.p));
                    Vec3d ray = R * (Ki * Vec3d(-line[0] * line[2], -line[1] * line[2], 1));
                    edge.pitch = ray[1] / cv::norm(ray);
                }
                if (candidate.edges[0].pitch < candidate.edges[1].pitch) std::swap(candidate.edges[0], candidate.edges[1]);
                candidates.push_back(candidate);
            }
            // A horizontal surface can have two horizontal vanishing directions.
            // This routine handles upright rectangles only.
            if (candidates.size() == 1) {
                if (std::getenv("UY360_PLANAR_DEBUG")) std::fprintf(stderr,"candidate %d area=%d n=%.4f %.4f %.4f\n",index,area,candidates[0].normal[0],candidates[0].normal[1],candidates[0].normal[2]);
                result.push_back(candidates[0]);
            }
        }
    }
    return result;
}
} // namespace

PlanarStats regularizePlanarObjects(const std::vector<FrameInput>& frames, std::vector<Pose>& poses,
                                   std::vector<DepthMap>& depths, const ProgressFn& progress) {
    PlanarStats stats;
    if (frames.size() < 3 || frames.size() != poses.size() || frames.size() != depths.size()) return stats;
    regularizeWallSurfaces(frames, poses, depths);
    std::vector<std::vector<Region>> groups;
    std::vector<float> sceneDepths;
    for (size_t i = 0; i < frames.size(); ++i) {
        if (progress) progress(float(i) / frames.size(), "Tekis buyumlarning qirralari");
        for (int y = 0; y < depths[i].z.rows; y += 16) for (int x = 0; x < depths[i].z.cols; x += 16) {
            float z = depths[i].z.at<float>(y, x);
            if (std::isfinite(z) && z > 0) sceneDepths.push_back(z);
        }
        for (auto& region : detect(frames[i], poses[i], depths[i], int(i))) {
            ++stats.candidates;
            auto group = std::find_if(groups.begin(), groups.end(), [&](const auto& g) {
                return region.normal.dot(g.front().normal) > .999;
            });
            if (group == groups.end()) groups.push_back({region}); else group->push_back(region);
        }
    }
    double sceneScale = quantile(sceneDepths, .5);
    if (sceneScale <= 0) return stats;
    std::set<int> changed;
    for (const auto& group : groups) {
        std::map<int, const Region*> unique;
        for (const auto& region : group)
            if (!unique.count(region.frame) || region.area > unique[region.frame]->area) unique[region.frame] = &region;
        if (unique.size() < 3) continue;
        // Do not accumulate competing translation corrections from several
        // surfaces in one camera during a single pass.
        if (std::any_of(unique.begin(), unique.end(), [&](const auto& item) { return changed.count(item.first) > 0; })) continue;
        std::vector<const Region*> regions;
        Vec3d normal(0, 0, 0);
        double maxFraction = 0;
        for (const auto& entry : unique) {
            regions.push_back(entry.second); normal += entry.second->normal;
            maxFraction = std::max(maxFraction, double(entry.second->area) / depths[entry.first].z.total());
        }
        if (maxFraction < .12) continue;
        normal = cv::normalize(normal);
        Mat A(int(regions.size()) * 2, 3, CV_64F, cv::Scalar(0)), b(A.rows, 1, CV_64F);
        for (size_t i = 0; i < regions.size(); ++i) for (int j = 0; j < 2; ++j) {
            const auto& edge = regions[i]->edges[j];
            A.at<double>(int(i) * 2 + j, 0) = edge.normal.dot(normal);
            A.at<double>(int(i) * 2 + j, j + 1) = edge.normal.dot(up);
            b.at<double>(int(i) * 2 + j) = edge.offset;
        }
        cv::SVD svd(A, cv::SVD::NO_UV);
        if (svd.w.at<double>(2) < .001 * svd.w.at<double>(0)) continue;
        Mat fitted;
        if (!cv::solve(A, b, fitted, cv::DECOMP_SVD)) continue;
        double distance = fitted.at<double>(0), height = fitted.at<double>(1) - fitted.at<double>(2);
        if (std::getenv("UY360_PLANAR_DEBUG")) { std::fprintf(stderr,"group n=%.4f,%.4f,%.4f d=%.4f h=%.4f err=%.4f scale=%.4f frames",normal[0],normal[1],normal[2],distance,height,cv::norm(A*fitted-b,cv::NORM_INF),sceneScale); for (const auto* r:regions) std::fprintf(stderr," %d",r->frame); std::fprintf(stderr,"\n"); }
        if (!std::isfinite(distance) || height < .05 * sceneScale || height > 10 * sceneScale ||
            cv::norm(A * fitted - b, cv::NORM_INF) > .02 * height) continue;
        std::vector<Pose> adjusted;
        bool valid = true;
        for (const auto* region : regions) {
            Mat M(2, 3, CV_64F), residual(2, 1, CV_64F), delta;
            Pose pose = poses[region->frame];
            for (int j = 0; j < 2; ++j) {
                const Vec3d& m = region->edges[j].normal;
                for (int k = 0; k < 3; ++k) M.at<double>(j, k) = m[k];
                residual.at<double>(j) = m.dot(normal) * distance + m.dot(up) * fitted.at<double>(j + 1) - m.dot(Vec3d(pose.p));
            }
            // Minimum-norm correction of just the translations, constrained by
            // two independent edge planes. Use SVD explicitly for the 2x3 system.
            Mat inverse;
            cv::invert(M, inverse, cv::DECOMP_SVD);
            delta = inverse * residual;
            if (cv::norm(delta) > .02 * sceneScale) { valid = false; break; }
            pose.p += cv::Vec3f(float(delta.at<double>(0)), float(delta.at<double>(1)), float(delta.at<double>(2)));
            adjusted.push_back(pose);
        }
        if (!valid) continue;
        std::vector<Mat> updated, updatedConfidence, updatedMasks;
        for (size_t k = 0; k < regions.size(); ++k) {
            const Region& region = *regions[k];
            const DepthMap& depth = depths[region.frame];
            const Pose& pose = adjusted[k];
            Mat silhouette = surfaceMask(region.mask, frames[region.frame]), mask, z = depth.z.clone();
            cv::resize(silhouette, mask, z.size(), 0, 0, cv::INTER_AREA);
            mask = mask >= 128;
            std::vector<float> samples;
            for (int y = 0; y < z.rows; y += 2) for (int x = 0; x < z.cols; x += 2)
                if (mask.at<uchar>(y, x) && std::isfinite(z.at<float>(y, x)) && z.at<float>(y, x) > 0) samples.push_back(z.at<float>(y, x));
            double lo = quantile(samples, .01) * .25, hi = quantile(samples, .99) * 4;
            Vec3d nc = cv::Matx33d(pose.R).t() * normal;
            double offset = distance - normal.dot(Vec3d(pose.p));
            int accepted = 0;
            int measured = 0, disagree = 0;
            Mat confidence = depth.conf.empty() ? Mat::zeros(z.size(), CV_8U) : depth.conf.clone();
            for (int y = 0; y < z.rows; ++y) for (int x = 0; x < z.cols; ++x) {
                if (!mask.at<uchar>(y, x)) continue;
                Vec3d ray((x - depth.cx) / depth.fx, -(y - depth.cy) / depth.fy, -1);
                double value = offset / nc.dot(ray);
                if (std::isfinite(value) && value > lo && value < hi) {
                    if (region.mask.at<uchar>(y, x) && confidence.at<uchar>(y, x) == 2) {
                        ++measured;
                        if (std::abs(z.at<float>(y, x) - value) > .2 * value) ++disagree;
                    }
                    z.at<float>(y, x) = float(value);
                    confidence.at<uchar>(y, x) = 1; // inferred plane, not measured stereo
                    ++accepted;
                }
            }
            // A window frame is rectangular too, but its interior can contain a
            // scene at several depths. Do not flatten reliable stereo behind it.
            if (measured > std::max(32., .02 * region.area) && disagree > measured * .25) { valid = false; break; }
            if (accepted < .98 * cv::countNonZero(mask)) { if (std::getenv("UY360_PLANAR_DEBUG")) std::fprintf(stderr,"invalid depth %d accepted=%d/%d\n",region.frame,accepted,cv::countNonZero(mask)); valid = false; break; }
            updated.push_back(z);
            updatedConfidence.push_back(confidence);
            updatedMasks.push_back(silhouette);
        }
        if (!valid) continue;
        for (size_t k = 0; k < regions.size(); ++k) {
            int i = regions[k]->frame;
            poses[i] = adjusted[k]; depths[i].z = updated[k]; depths[i].conf = updatedConfidence[k]; changed.insert(i);
            depths[i].planarMask = updatedMasks[k];
            depths[i].planarNormal = cv::Vec3f(cv::Matx33d(adjusted[k].R).t() * normal);
            depths[i].planarOffset = float(distance - normal.dot(Vec3d(adjusted[k].p)));
        }
        // Keep the bezel and a narrow strip of its photographic context with
        // the same view as the screen. Otherwise an unmodelled background warp
        // can leave a second, displaced silhouette just outside the exact plane.
        size_t primary = 0;
        for (size_t k = 1; k < regions.size(); ++k)
            if (regions[k]->area > regions[primary]->area) primary = k;
        Vec3d horizontal = cv::normalize(up.cross(normal));
        double u0 = 1e30, u1 = -1e30, v0 = 1e30, v1 = -1e30;
        const auto& reference = depths[regions[primary]->frame];
        const auto& referencePose = adjusted[primary];
        for (int y = 0; y < reference.z.rows; y += 2) for (int x = 0; x < reference.z.cols; x += 2) {
            if (!depthPlaneContains(reference, float(x), float(y))) continue;
            Vec3d ray = cv::Matx33d(referencePose.R) * Vec3d((x - reference.cx) / reference.fx, -(y - reference.cy) / reference.fy, -1);
            double t = (distance - normal.dot(Vec3d(referencePose.p))) / normal.dot(ray);
            Vec3d point = Vec3d(referencePose.p) + ray * t;
            double u = horizontal.dot(point), v = up.dot(point);
            u0 = std::min(u0, u); u1 = std::max(u1, u); v0 = std::min(v0, v); v1 = std::max(v1, v);
        }
        if (u1 > u0 && v1 > v0) for (size_t k = 0; k < regions.size(); ++k) {
            RectifiedPatch patch;
            patch.group = -1 - stats.groups;
            patch.center = cv::Vec3f(normal * distance + horizontal * ((u0 + u1) * .5) + up * ((v0 + v1) * .5));
            patch.axisU = cv::Vec3f(horizontal); patch.axisV = cv::Vec3f(up);
            patch.halfExtent = {float((u1 - u0) * .5), float((v1 - v0) * .5)};
            patch.margin = float(.05 * std::min(u1 - u0, v1 - v0));
            patch.cameraPosition = adjusted[k].p;
            depths[regions[k]->frame].patches.push_back(patch);
        }
        ++stats.groups;
    }
    stats.groups += regularizeCeilingFixtures(frames, poses, depths);
    stats.frames = int(std::count_if(depths.begin(), depths.end(), [](const auto& d) {
        return !d.planarMask.empty() || !d.patches.empty();
    }));
    return stats;
}
} // namespace uy360
