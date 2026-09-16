#include "uy360_planar.hpp"
#include <opencv2/imgproc.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <set>
#include <cstdio>
#include <cstdlib>

namespace uy360 {
namespace {
using cv::Vec3d;
using cv::Point2d;
using cv::Mat;
const Vec3d up(0, 1, 0);
struct Strip {
    int frame, axis = 0;
    Point2d a, b;
    Vec3d normal;
    double length, offset = 0;
};
struct Side {
    int axis;
    double offset;
    std::vector<int> strips;
};
struct Observation { int frame, side; Vec3d normal; };

double median(std::vector<double> values) {
    if (values.empty()) return 0;
    auto mid = values.begin() + values.size() / 2;
    std::nth_element(values.begin(), mid, values.end());
    return *mid;
}
float grayAt(const Mat& image, Point2d p) {
    int x = std::max(0, std::min(cvRound(p.x), image.cols - 1));
    int y = std::max(0, std::min(cvRound(p.y), image.rows - 1));
    return image.at<uchar>(y, x);
}
Vec3d rayAt(Point2d pixel, const DepthMap& depth, const Pose& pose) {
    return cv::Matx33d(pose.R) * Vec3d((pixel.x - depth.cx) / depth.fx,
                                    -(pixel.y - depth.cy) / depth.fy, -1);
}
std::vector<Strip> detectStrips(const FrameInput& frame, const DepthMap& depth, const Pose& pose, int index) {
    std::vector<Strip> result;
    if (depth.z.empty()) return result;
    Mat image = imreadForWidth(frame.path, depth.z.cols, frame.imageWidth, false);
    if (image.empty()) return result;
    cv::resize(image, image, depth.z.size());
    std::vector<cv::Vec4f> raw, lines;
    cv::createLineSegmentDetector()->detect(image, raw);
    double scale = image.cols / 1008.;
    for (const auto& l : raw)
        if (cv::norm(Point2d(l[0] - l[2], l[1] - l[3])) > 100 * scale) lines.push_back(l);
    for (size_t i = 0; i < lines.size(); ++i) {
        const auto& l = lines[i];
        Point2d a(l[0], l[1]), b(l[2], l[3]), direction = b - a;
        double length = cv::norm(direction); direction *= 1 / length;
        Point2d normal(-direction.y, direction.x);
        for (size_t j = i + 1; j < lines.size(); ++j) {
            const auto& q = lines[j];
            Point2d c(q[0], q[1]), d(q[2], q[3]);
            double otherLength = cv::norm(d - c);
            if (std::abs((d - c).dot(direction)) < .998 * otherLength) continue;
            double separation = ((c + d - a - b) * .5).dot(normal);
            if (std::abs(separation) < 4 * scale || std::abs(separation) > 65 * scale) continue;
            double lo = (c - a).dot(direction), hi = (d - a).dot(direction);
            if (lo > hi) std::swap(lo, hi);
            lo = std::max(0., lo); hi = std::min(length, hi);
            if (hi - lo < std::max(70 * scale, std::min(length, otherLength) * .6)) continue;
            std::vector<double> contrast;
            for (int k = 0; k < 20; ++k) {
                Point2d p = a + direction * (lo + (hi - lo) * (k + .5) / 20);
                double sign = separation > 0 ? 1 : -1;
                contrast.push_back(grayAt(image, p + normal * separation * .5) -
                    .5 * (grayAt(image, p - normal * (sign * 3 * scale)) +
                          grayAt(image, p + normal * (separation + sign * 3 * scale))));
            }
            if (median(contrast) < 35) continue;
            Point2d p = a + direction * lo + normal * (separation * .5);
            Point2d q2 = a + direction * hi + normal * (separation * .5);
            Vec3d ra = rayAt(p, depth, pose), rb = rayAt(q2, depth, pose);
            Vec3d centerRay = (ra + rb) * .5;
            if (centerRay[1] / cv::norm(centerRay) < .3) continue;
            Vec3d n = cv::normalize(ra.cross(rb));
            if (std::abs(n[1]) < .01) continue;
            result.push_back({index, 0, p, q2, n, hi - lo, 0});
        }
    }
    return result;
}
std::set<int> cameras(const Side& side, const std::vector<Strip>& strips) {
    std::set<int> result;
    for (int i : side.strips) result.insert(strips[i].frame);
    return result;
}
} // namespace

int regularizeCeilingFixtures(const std::vector<FrameInput>& frames, const std::vector<Pose>& poses,
                             std::vector<DepthMap>& depths) {
    if (frames.size() < 3 || poses.size() != frames.size() || depths.size() != frames.size()) return 0;
    std::vector<double> heights;
    std::set<int> measuredViews;
    for (size_t i = 0; i < depths.size(); ++i) {
        const auto& d = depths[i];
        if (d.z.empty() || d.conf.empty()) continue;
        for (int y = 0; y < d.z.rows; y += 4) for (int x = 0; x < d.z.cols; x += 4) {
            if (d.conf.at<uchar>(y, x) != 2) continue;
            Vec3d ray = rayAt(Point2d(x, y), d, poses[i]);
            double height = poses[i].p[1] + ray[1] * d.z.at<float>(y, x);
            if (ray[1] / cv::norm(ray) > .65 && std::isfinite(height) && height > 0) {
                heights.push_back(height); measuredViews.insert(int(i));
            }
        }
    }
    if (heights.size() < 100 || measuredViews.size() < 3) return 0;
    double height = median(heights);
    std::vector<Strip> strips;
    for (size_t i = 0; i < frames.size(); ++i) {
        auto found = detectStrips(frames[i], depths[i], poses[i], int(i));
        strips.insert(strips.end(), found.begin(), found.end());
    }
    if (strips.size() < 8) return 0;
    // Derive room axes from the observations, independent of capture starting yaw.
    double sine = 0, cosine = 0;
    for (const auto& s : strips) {
        double angle = std::atan2(s.normal[2], s.normal[0]);
        sine += s.length * std::sin(4 * angle); cosine += s.length * std::cos(4 * angle);
    }
    double angle = std::atan2(sine, cosine) * .25;
    std::array<Vec3d, 2> axes{Vec3d(std::cos(angle), 0, std::sin(angle)),
                             Vec3d(-std::sin(angle), 0, std::cos(angle))};
    std::vector<Strip> aligned;
    for (auto s : strips) {
        Vec3d horizontal(s.normal[0], 0, s.normal[2]); horizontal = cv::normalize(horizontal);
        s.axis = std::abs(horizontal.dot(axes[1])) > std::abs(horizontal.dot(axes[0])) ? 1 : 0;
        if (std::abs(horizontal.dot(axes[s.axis])) < .998) continue;
        if (s.normal.dot(axes[s.axis]) < 0) s.normal *= -1;
        s.offset = (s.normal.dot(Vec3d(poses[s.frame].p)) - s.normal[1] * height) / s.normal.dot(axes[s.axis]);
        if (std::isfinite(s.offset)) aligned.push_back(s);
    }
    strips = std::move(aligned);
    std::vector<int> order(strips.size());
    for (size_t i = 0; i < order.size(); ++i) order[i] = int(i);
    std::sort(order.begin(), order.end(), [&](int a, int b) { return strips[a].offset < strips[b].offset; });
    std::vector<Side> sides;
    for (int i : order) {
        const auto& s = strips[i];
        auto group = std::find_if(sides.begin(), sides.end(), [&](const auto& g) {
            return g.axis == s.axis && std::abs(g.offset - s.offset) < .10 * height;
        });
        if (group == sides.end()) sides.push_back({s.axis, s.offset, {i}});
        else {
            group->strips.push_back(i); group->offset = 0;
            for (int k : group->strips) group->offset += strips[k].offset / group->strips.size();
        }
    }
    sides.erase(std::remove_if(sides.begin(), sides.end(), [&](const auto& s) { return cameras(s, strips).size() < 2; }), sides.end());
    std::array<std::vector<int>, 2> axisSides;
    for (size_t i = 0; i < sides.size(); ++i) axisSides[sides[i].axis].push_back(int(i));
    int accepted = 0;
    std::vector<Vec3d> centers;
    for (size_t a = 0; a < axisSides[0].size(); ++a) for (size_t b = a + 1; b < axisSides[0].size(); ++b)
    for (size_t c = 0; c < axisSides[1].size(); ++c) for (size_t d = c + 1; d < axisSides[1].size(); ++d) {
        std::array<Side, 4> rectangle{sides[axisSides[0][a]], sides[axisSides[0][b]], sides[axisSides[1][c]], sides[axisSides[1][d]]};
        double width = rectangle[1].offset - rectangle[0].offset, length = rectangle[3].offset - rectangle[2].offset;
        if (std::min(width, length) < .25 * height || std::max(width, length) > 2 * height) continue;
        std::map<int, std::set<int>> seen;
        bool valid = true;
        for (int k = 0; k < 4; ++k) {
            auto& side = rectangle[k];
            int other = side.axis == 0 ? 2 : 0;
            double lower = rectangle[other].offset, upper = rectangle[other + 1].offset;
            std::vector<int> supported;
            for (int j : side.strips) {
                const auto& s = strips[j]; const auto& pose = poses[s.frame];
                Vec3d ra = rayAt(s.a, depths[s.frame], pose), rb = rayAt(s.b, depths[s.frame], pose);
                if (ra[1] <= .01 || rb[1] <= .01) continue;
                Vec3d pa = Vec3d(pose.p) + ra * ((height - pose.p[1]) / ra[1]);
                Vec3d pb = Vec3d(pose.p) + rb * ((height - pose.p[1]) / rb[1]);
                double lo = pa.dot(axes[1 - side.axis]), hi = pb.dot(axes[1 - side.axis]);
                if (lo > hi) std::swap(lo, hi);
                double overlap = std::max(0., std::min(hi, upper) - std::max(lo, lower));
                if (overlap > .35 * (upper - lower) && overlap > .7 * (hi - lo)) {
                    supported.push_back(j); seen[s.frame].insert(k);
                }
            }
            side.strips = supported;
            if (cameras(side, strips).size() < 2) { valid = false; break; }
        }
        if (!valid || seen.size() < 3 || std::none_of(seen.begin(), seen.end(), [](const auto& v) { return v.second.size() >= 3; })) continue;
        // Average duplicate detections before solving, so line fragmentation in
        // one photograph does not outweigh several independent observations.
        std::vector<Observation> observations;
        for (int k = 0; k < 4; ++k) {
            std::map<int, std::pair<Vec3d, double>> sum;
            for (int j : rectangle[k].strips) {
                const auto& s = strips[j]; sum[s.frame].first += s.normal * s.length; sum[s.frame].second += s.length;
            }
            for (const auto& entry : sum) observations.push_back({entry.first, k, cv::normalize(entry.second.first)});
        }
        Mat A(int(observations.size()), 5, CV_64F, cv::Scalar(0)), target(A.rows, 1, CV_64F);
        for (int j = 0; j < A.rows; ++j) {
            const auto& o = observations[j]; A.at<double>(j, 0) = o.normal[1];
            A.at<double>(j, o.side + 1) = o.normal.dot(axes[o.side / 2]);
            target.at<double>(j) = o.normal.dot(Vec3d(poses[o.frame].p));
        }
        cv::SVD svd(A, cv::SVD::NO_UV);
        if (svd.w.at<double>(4) < .002 * svd.w.at<double>(0)) continue;
        Mat fit;
        if (!cv::solve(A, target, fit, cv::DECOMP_SVD)) continue;
        double h = fit.at<double>(0), u0 = fit.at<double>(1), u1 = fit.at<double>(2), v0 = fit.at<double>(3), v1 = fit.at<double>(4);
        if (!std::isfinite(h) || h < .5 * height || h > 1.5 * height || u1 <= u0 || v1 <= v0 ||
            cv::norm(A * fit - target, cv::NORM_INF) > .07 * height) continue;
        Vec3d center = up * h + axes[0] * ((u0 + u1) * .5) + axes[1] * ((v0 + v1) * .5);
        if (std::any_of(centers.begin(), centers.end(), [&](const auto& p) { return cv::norm(p - center) < .2 * height; })) continue;
        std::vector<std::pair<int, RectifiedPatch>> patches;
        int wellObserved = 0;
        for (const auto& item : seen) {
            int i = item.first;
            if (item.second.size() < 2) continue;
            Mat M(int(item.second.size()), 3, CV_64F), rhs(M.rows, 1, CV_64F); int row = 0;
            for (const auto& o : observations) if (o.frame == i) {
                for (int k = 0; k < 3; ++k) M.at<double>(row, k) = o.normal[k];
                rhs.at<double>(row++) = o.normal[1] * h + o.normal.dot(axes[o.side / 2]) * fit.at<double>(o.side + 1) - o.normal.dot(Vec3d(poses[i].p));
            }
            Mat inverse, correction; cv::invert(M, inverse, cv::DECOMP_SVD); correction = inverse * rhs;
            if (cv::norm(correction) > .12 * height || cv::norm(M * correction - rhs, cv::NORM_INF) > .02 * height) continue;
            RectifiedPatch patch;
            patch.group = accepted; patch.center = cv::Vec3f(center);
            patch.axisU = cv::Vec3f(axes[0]); patch.axisV = cv::Vec3f(axes[1]);
            patch.halfExtent = {float((u1 - u0) * .5), float((v1 - v0) * .5)};
            patch.margin = float(.2 * std::min(u1 - u0, v1 - v0));
            patch.cameraPosition = poses[i].p + cv::Vec3f(float(correction.at<double>(0)), float(correction.at<double>(1)), float(correction.at<double>(2)));
            patches.emplace_back(i, patch);
            wellObserved += item.second.size() >= 3;
        }
        if (patches.size() < 3 || wellObserved < 2) continue;
        if (std::getenv("UY360_PLANAR_DEBUG")) std::fprintf(stderr, "ceiling rectangle h=%.4f u=%.4f..%.4f v=%.4f..%.4f views=%zu\n", h,u0,u1,v0,v1,patches.size());
        for (const auto& entry : patches) depths[entry.first].patches.push_back(entry.second);
        centers.push_back(center); ++accepted;
        if (accepted >= 4) return accepted;
    }
    return accepted;
}
} // namespace uy360

namespace uy360 {
namespace {
struct WallRegion {
    int frame, label;
    std::vector<Vec3d> points;
    int plane = -1;
};
struct WallPlane { Vec3d normal; double offset; };
double percentile(std::vector<double> values, double q) {
    if (values.empty()) return 0;
    size_t k = size_t((values.size() - 1) * q);
    std::nth_element(values.begin(), values.begin() + k, values.end());
    return values[k];
}
}
int regularizeWallSurfaces(const std::vector<FrameInput>& frames, const std::vector<Pose>& poses,
                          std::vector<DepthMap>& depths) {
    if (frames.size() < 3 || frames.size() != poses.size() || frames.size() != depths.size()) return 0;
    std::vector<Mat> labels(frames.size());
    std::vector<WallRegion> regions;
    std::vector<WallPlane> planes;
    for (size_t i = 0; i < frames.size(); ++i) {
        const auto& depth = depths[i];
        if (depth.z.empty() || depth.conf.empty() || frames[i].supplemental) continue;
        Mat image = imreadForWidth(frames[i].path, depth.z.cols, frames[i].imageWidth, false);
        if (image.empty()) continue;
        cv::resize(image, image, depth.z.size());
        Mat smooth, edges, stats, centers;
        cv::GaussianBlur(image, smooth, cv::Size(5, 5), 1);
        cv::Canny(smooth, edges, 30, 60);
        cv::dilate(edges, edges, Mat::ones(3, 3, CV_8U));
        int count = cv::connectedComponentsWithStats(edges == 0, labels[i], stats, centers);
        for (int label = 1; label < count; ++label) {
            int area = stats.at<int>(label, cv::CC_STAT_AREA);
            if (area < .02 * depth.z.total()) continue;
            cv::Rect box(stats.at<int>(label, cv::CC_STAT_LEFT), stats.at<int>(label, cv::CC_STAT_TOP),
                         stats.at<int>(label, cv::CC_STAT_WIDTH), stats.at<int>(label, cv::CC_STAT_HEIGHT));
            std::vector<double> brightness;
            WallRegion region{int(i), label, {}, -1};
            for (int y = box.y; y < box.y + box.height; ++y) for (int x = box.x; x < box.x + box.width; ++x) {
                if (labels[i].at<int>(y, x) != label) continue;
                if ((x + y) % 4 == 0) brightness.push_back(image.at<uchar>(y, x));
                if (depth.conf.at<uchar>(y, x) != 2) continue;
                float z = depth.z.at<float>(y, x);
                if (std::isfinite(z) && z > 0) region.points.push_back(Vec3d(poses[i].p) + rayAt(Point2d(x, y), depth, poses[i]) * z);
            }
            if (region.points.size() < 100 || median(brightness) < 100) continue;
            std::vector<Vec3d> inliers = region.points;
            Vec3d normal, center; double eigenSmall = 0, eigenLarge = 0;
            std::vector<double> residuals;
            for (int iteration = 0; iteration < 3; ++iteration) {
                std::vector<double> xs, zs;
                for (const auto& p : inliers) { xs.push_back(p[0]); zs.push_back(p[2]); }
                center = {median(xs), 0, median(zs)};
                cv::Matx22d covariance = cv::Matx22d::zeros();
                cv::Vec2d mean(0, 0);
                for (const auto& p : inliers) mean += cv::Vec2d(p[0], p[2]);
                mean *= 1. / inliers.size();
                for (const auto& p : inliers) {
                    cv::Vec2d v = cv::Vec2d(p[0], p[2]) - mean;
                    covariance += cv::Matx22d(v[0] * v[0], v[0] * v[1], v[1] * v[0], v[1] * v[1]);
                }
                Mat eigenValues, eigenVectors;
                cv::eigen(Mat(covariance), eigenValues, eigenVectors);
                normal = {eigenVectors.at<double>(1, 0), 0, eigenVectors.at<double>(1, 1)};
                eigenSmall = eigenValues.at<double>(1); eigenLarge = eigenValues.at<double>(0);
                residuals.clear();
                for (const auto& p : region.points) residuals.push_back(std::abs((p - center).dot(normal)));
                double limit = percentile(residuals, .8);
                inliers.clear();
                for (size_t j = 0; j < region.points.size(); ++j) if (residuals[j] <= limit) inliers.push_back(region.points[j]);
                if (inliers.size() < 20) break;
            }
            regions.push_back(std::move(region));
            Vec3d tangent = normal.cross(up);
            std::vector<double> span;
            for (const auto& p : inliers) span.push_back((p - center).dot(tangent));
            double distance = normal.dot(center);
            if (percentile(residuals, .8) > .08 * std::abs(distance) ||
                percentile(span, .9) - percentile(span, .1) < .25 * std::abs(distance) ||
                eigenSmall > .025 * eigenLarge) continue;
            planes.push_back({normal, distance});
        }
    }
    // Transfer a well-constrained wall to another view only when that view's
    // measured points support it too. This also constrains blank walls whose
    // local stereo samples occupy too narrow a strip to fit their own plane.
    std::vector<std::set<int>> support(planes.size());
    for (auto& region : regions) {
        double best = .075;
        for (size_t j = 0; j < planes.size(); ++j) {
            const auto& plane = planes[j];
            double distance = std::abs(plane.offset - plane.normal.dot(Vec3d(poses[region.frame].p)));
            if (distance < 1e-4) continue;
            std::vector<double> errors;
            for (const auto& p : region.points) errors.push_back(std::abs(p.dot(plane.normal) - plane.offset));
            double error = percentile(errors, .8) / distance;
            if (error < best) { best = error; region.plane = int(j); }
        }
        if (region.plane >= 0) support[region.plane].insert(region.frame);
    }
    int accepted = 0;
    for (const auto& region : regions) {
        if (region.plane < 0 || support[region.plane].size() < 2) continue;
        auto& depth = depths[region.frame]; const auto& pose = poses[region.frame];
        const auto& plane = planes[region.plane];
        Mat mask = labels[region.frame] == region.label;
        int radius = std::max(1, cvRound(5 * depth.z.cols / 1008.));
        cv::dilate(mask, mask, Mat::ones(2 * radius + 1, 2 * radius + 1, CV_8U));
        WallSurface surface;
        surface.mask = Mat::zeros(mask.size(), CV_8U);
        surface.normal = pose.R.t() * cv::Vec3f(plane.normal);
        surface.offset = float(plane.offset - plane.normal.dot(Vec3d(pose.p)));
        for (int y = 0; y < depth.z.rows; ++y) for (int x = 0; x < depth.z.cols; ++x) {
            if (!mask.at<uchar>(y, x)) continue;
            double denominator = plane.normal.dot(rayAt(Point2d(x, y), depth, pose));
            if (std::abs(denominator) < 1e-6) continue;
            double z = (plane.offset - plane.normal.dot(Vec3d(pose.p))) / denominator;
            float old = depth.z.at<float>(y, x);
            if (std::isfinite(z) && z > 0 && z > old / 3 && z < old * 3) {
                depth.z.at<float>(y, x) = float(z);
                depth.conf.at<uchar>(y, x) = 1;
                surface.mask.at<uchar>(y, x) = 255;
            }
        }
        depth.walls.push_back(std::move(surface));
        if (std::getenv("UY360_PLANAR_DEBUG")) std::fprintf(stderr, "wall frame=%d region=%d plane=%d\n", region.frame,region.label,region.plane);
        ++accepted;
    }
    return accepted;
}
} // namespace uy360
