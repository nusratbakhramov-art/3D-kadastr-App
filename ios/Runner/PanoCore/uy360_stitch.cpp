#include "uy360_stitch.hpp"

#include <opencv2/opencv.hpp>
#include <opencv2/stitching/detail/blenders.hpp>
#include <opencv2/stitching/detail/seam_finders.hpp>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <climits>
#include <cmath>
#include <numeric>

namespace uy360 {
namespace {

using cv::Mat;
using cv::Matx33f;
using cv::Point;
using cv::Rect;
using cv::Size;
using cv::Vec3f;

constexpr float kPi = 3.14159265358979323846f;

template <typename T>
static T clampf(T v, T lo, T hi) { return v < lo ? lo : (v > hi ? hi : v); }

static Matx33f toMatx(const Mat& m) {
    Matx33f out;
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j) out(i, j) = m.at<float>(i, j);
    return out;
}

// Nearest rotation (Frobenius) to an arbitrary 3x3.
static Matx33f projectSO3(const Matx33f& M) {
    Mat m(M);
    cv::SVD svd(m, cv::SVD::FULL_UV);
    Mat u = svd.u.clone(), vt = svd.vt.clone();
    Mat R = u * vt;
    if (cv::determinant(R) < 0) {
        u.col(2) *= -1;
        R = u * vt;
    }
    return toMatx(R);
}

static Matx33f rotationFromTransform(const std::array<float, 16>& t) {
    // column j of the 4x4 = t[4j .. 4j+3]
    Matx33f R(t[0], t[4], t[8],
              t[1], t[5], t[9],
              t[2], t[6], t[10]);
    return projectSO3(R);
}

static Vec3f positionFromTransform(const std::array<float, 16>& t) { return Vec3f(t[12], t[13], t[14]); }

// R minimising Σ w |R a − b|²
static Matx33f kabsch(const std::vector<Vec3f>& A, const std::vector<Vec3f>& B, const std::vector<float>& w) {
    Matx33f H = Matx33f::zeros();
    for (size_t k = 0; k < A.size(); ++k)
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j) H(i, j) += w[k] * A[k][i] * B[k][j];
    Mat h(H);
    cv::SVD svd(h, cv::SVD::FULL_UV);
    Mat V = svd.vt.t(), Ut = svd.u.t();
    Mat D = Mat::eye(3, 3, CV_32F);
    D.at<float>(2, 2) = cv::determinant(V * Ut) < 0 ? -1.f : 1.f;
    return toMatx(V * D * Ut);
}

// ------------------------------------------------------------ rotation refine
struct FeatureSet {
    std::vector<Vec3f> bearings;
    Mat desc;
};

struct Obs {
    int i, j;
    std::vector<Vec3f> a, b;
};

static float meanResidualDeg(const std::vector<Obs>& obs, const std::vector<Matx33f>& R) {
    double sum = 0;
    size_t n = 0;
    for (const auto& o : obs)
        for (size_t k = 0; k < o.a.size(); ++k) {
            Vec3f wa = R[o.i] * o.a[k], wb = R[o.j] * o.b[k];
            float c = clampf(wa.dot(wb), -1.f, 1.f);
            sum += std::acos(c) * 180.0 / kPi;
            ++n;
        }
    return n ? float(sum / n) : 0.f;
}

static std::vector<Matx33f> refineRotations(const std::vector<FrameInput>& frames, const std::vector<Matx33f>& R0,
                                            const Options& opt, const Progress& progress, Result& res) {
    const int n = (int)frames.size();
    auto sift = cv::SIFT::create(3000, 3, 0.03);
    std::vector<FeatureSet> feats(n);
    for (int i = 0; i < n; ++i) {
        if (progress) progress(0.02f + 0.10f * i / n, "Feature'lar " + std::to_string(i + 1) + "/" + std::to_string(n));
        Mat img = cv::imread(frames[i].path, cv::IMREAD_REDUCED_GRAYSCALE_4);
        if (img.empty()) continue;
        if (img.cols > opt.refineSmallWidth)
            cv::resize(img, img, Size(opt.refineSmallWidth, img.rows * opt.refineSmallWidth / img.cols), 0, 0, cv::INTER_AREA);
        const float sx = (float)img.cols / frames[i].imageWidth, sy = (float)img.rows / frames[i].imageHeight;
        const float fx = frames[i].fx * sx, fy = frames[i].fy * sy, cx = frames[i].cx * sx, cy = frames[i].cy * sy;
        std::vector<cv::KeyPoint> kp;
        Mat de;
        sift->detectAndCompute(img, cv::noArray(), kp, de);
        if (de.empty() || kp.size() < 8) continue;
        feats[i].bearings.reserve(kp.size());
        for (const auto& k : kp) {
            Vec3f b((k.pt.x - cx) / fx, -(k.pt.y - cy) / fy, -1.f);
            feats[i].bearings.push_back(cv::normalize(b));
        }
        feats[i].desc = de;
    }

    std::vector<Vec3f> fwd(n);
    for (int i = 0; i < n; ++i) fwd[i] = Vec3f(-R0[i](0, 2), -R0[i](1, 2), -R0[i](2, 2));
    cv::BFMatcher matcher(cv::NORM_L2);
    const float gate = std::cos(4.f * kPi / 180.f), maxPair = std::cos(80.f * kPi / 180.f);
    std::vector<Obs> obs;
    int nMatches = 0;
    for (int i = 0; i < n; ++i) {
        if (feats[i].desc.empty()) continue;
        for (int j = i + 1; j < n; ++j) {
            if (feats[j].desc.empty() || fwd[i].dot(fwd[j]) < maxPair) continue;
            std::vector<std::vector<cv::DMatch>> knn;
            matcher.knnMatch(feats[i].desc, feats[j].desc, knn, 2);
            Obs o{i, j, {}, {}};
            for (const auto& p : knn) {
                if (p.size() < 2 || p[0].distance >= 0.78f * p[1].distance) continue;
                Vec3f a = feats[i].bearings[p[0].queryIdx], b = feats[j].bearings[p[0].trainIdx];
                Vec3f wa = R0[i] * a, wb = R0[j] * b;  // gyro-consistency gate
                if (wa.dot(wb) > gate) {
                    o.a.push_back(a);
                    o.b.push_back(b);
                }
            }
            if (o.a.size() >= 12) {
                nMatches += (int)o.a.size();
                obs.push_back(std::move(o));
            }
        }
    }
    res.pairs = (int)obs.size();
    if (progress) progress(0.13f, std::to_string(obs.size()) + " juft, " + std::to_string(nMatches) + " moslik");

    std::vector<Matx33f> R = R0;
    if (obs.empty()) return R;
    res.residualBeforeDeg = meanResidualDeg(obs, R);

    std::vector<std::vector<int>> per(n);
    for (int k = 0; k < (int)obs.size(); ++k) {
        per[obs[k].i].push_back(k);
        per[obs[k].j].push_back(k);
    }
    const float s = 1.f * kPi / 180.f;  // Cauchy scale
    for (int it = 0; it < 20; ++it) {
        for (int i = 0; i < n; ++i) {
            if (per[i].empty()) continue;
            std::vector<Vec3f> A, B;
            std::vector<float> Wt;
            for (int k : per[i]) {
                const Obs& o = obs[k];
                const bool first = (o.i == i);
                const int j = first ? o.j : o.i;
                const auto& a = first ? o.a : o.b;
                const auto& b = first ? o.b : o.a;
                for (size_t m = 0; m < a.size(); ++m) {
                    Vec3f target = R[j] * b[m], cur = R[i] * a[m];
                    float r = std::acos(clampf(cur.dot(target), -1.f, 1.f));
                    A.push_back(a[m]);
                    B.push_back(target);
                    Wt.push_back(1.f / (1.f + (r / s) * (r / s)));
                }
            }
            R[i] = kabsch(A, B, Wt);
        }
        if (progress && it % 5 == 0) progress(0.14f + 0.04f * it / 20, "BA iteratsiya " + std::to_string(it + 1) + "/20");
    }
    // snap the whole solution back onto the gravity frame of the sensor poses
    Matx33f S = Matx33f::zeros();
    for (int i = 0; i < n; ++i) S += R0[i] * R[i].t();
    Matx33f Rg = projectSO3(S);
    for (auto& r : R) r = Rg * r;
    res.residualAfterDeg = meanResidualDeg(obs, R);
    return R;
}

// ------------------------------------------------------------------- canvas
struct Canvas {
    int W, H, pad, We;
    std::vector<float> sinLon, cosLon, sinLat, cosLat;
    explicit Canvas(int w) : W(w), H(w / 2), pad(int(w * 0.10)), We(w + 2 * int(w * 0.10)) {
        sinLon.resize(We);
        cosLon.resize(We);
        sinLat.resize(H);
        cosLat.resize(H);
        for (int x = 0; x < We; ++x) {
            float lon = ((x - pad) + 0.5f) / W * 2.f * kPi - kPi;
            sinLon[x] = std::sin(lon);
            cosLon[x] = std::cos(lon);
        }
        for (int y = 0; y < H; ++y) {
            float lat = kPi / 2 - (y + 0.5f) / H * kPi;
            sinLat[y] = std::sin(lat);
            cosLat[y] = std::cos(lat);
        }
    }
    inline Vec3f dir(int x, int y) const { return Vec3f(cosLat[y] * sinLon[x], sinLat[y], -cosLat[y] * cosLon[x]); }
};

struct Warp {
    Rect box;
    Mat img;  // 8UC3
    Mat w;    // 32F feather weight (0 = no data)
};

// Canvas boxes covered by a frame. A frame may need two boxes (it straddles the
// ±180° seam or lies in the periodic margin) and a pole frame needs the full width.
static std::vector<Rect> frameBoxes(const Canvas& C, const Matx33f& R, float fx, float fy, float cx, float cy,
                                    int w, int h) {
    const int N = 40;
    std::vector<float> lons;
    float minLat = 1e9f, maxLat = -1e9f;
    for (int a = 0; a <= N; ++a)
        for (int b = 0; b <= N; ++b) {
            float u = (w - 1) * (float)a / N, v = (h - 1) * (float)b / N;
            Vec3f dc((u - cx) / fx, -(v - cy) / fy, -1.f);
            Vec3f d = cv::normalize(R * dc);
            lons.push_back(std::atan2(d[0], -d[2]));
            float lat = std::asin(clampf(d[1], -1.f, 1.f));
            minLat = std::min(minLat, lat);
            maxLat = std::max(maxLat, lat);
        }
    bool hasZenith = false, hasNadir = false;
    Matx33f Rt = R.t();
    for (int s : {1, -1}) {
        Vec3f dc = Rt * Vec3f(0, (float)s, 0);
        if (dc[2] < -1e-4f) {
            float u = fx * dc[0] / (-dc[2]) + cx, v = cy - fy * dc[1] / (-dc[2]);
            if (u >= 0 && u <= w - 1 && v >= 0 && v <= h - 1) (s == 1 ? hasZenith : hasNadir) = true;
        }
    }
    const int my = std::max(4, int(C.H * 0.02)), mx = std::max(4, int(C.W * 0.02));
    int y0 = hasZenith ? 0 : std::max(0, int((kPi / 2 - maxLat) / kPi * C.H) - my);
    int y1 = hasNadir ? C.H : std::min(C.H, int((kPi / 2 - minLat) / kPi * C.H) + my + 1);
    if (hasZenith || hasNadir) return {Rect(0, y0, C.We, y1 - y0)};

    float minLon = *std::min_element(lons.begin(), lons.end()), maxLon = *std::max_element(lons.begin(), lons.end());
    if (maxLon - minLon > kPi) {  // straddles ±π: unwrap the negative side
        minLon = 1e9f;
        maxLon = -1e9f;
        for (float l : lons) {
            if (l < 0) l += 2 * kPi;
            minLon = std::min(minLon, l);
            maxLon = std::max(maxLon, l);
        }
    }
    float x0f = (minLon + kPi) / (2 * kPi) * C.W + C.pad - mx;
    float x1f = (maxLon + kPi) / (2 * kPi) * C.W + C.pad + mx;
    std::vector<Rect> out;
    for (int k = -2; k <= 2; ++k) {
        int xa = std::max(0, int(std::floor(x0f + k * C.W)));
        int xb = std::min(C.We, int(std::ceil(x1f + k * C.W)) + 1);
        if (xb - xa > 2) out.push_back(Rect(xa, y0, xb - xa, y1 - y0));
    }
    return out;
}

static inline float sampleBilinear(const Mat& z, float u, float v) {
    const int w = z.cols, h = z.rows;
    u = clampf(u, 0.f, (float)(w - 1));
    v = clampf(v, 0.f, (float)(h - 1));
    const int x0 = (int)u, y0 = (int)v;
    const int x1 = std::min(x0 + 1, w - 1), y1 = std::min(y0 + 1, h - 1);
    const float a = u - x0, b = v - y0;
    const float* r0 = z.ptr<float>(y0);
    const float* r1 = z.ptr<float>(y1);
    return (r0[x0] * (1 - a) + r0[x1] * a) * (1 - b) + (r1[x0] * (1 - a) + r1[x1] * a) * b;
}

// Parallax-corrected warp: for each canvas direction from the panorama centre `Cpos`,
// find the pixel of camera (R, p) that sees the scene point along that ray, using the
// frame's depth map (fixed-point iteration on the distance t), then reject pixels whose
// measured depth disagrees with the point found (occlusion / foreground edge) so a
// neighbouring frame fills them instead of a smear.
static bool renderWarpDepth(const Canvas& C, const Matx33f& R, const Vec3f& p, const Vec3f& Cpos, const DepthMap& dm,
                            float fx, float fy, float cx, float cy, const Mat& img, const Rect& box, float feather,
                            Warp& out) {
    const Matx33f Rt = R.t();
    const int w = img.cols, h = img.rows;
    const Vec3f off = p - Cpos;
    const float fxd = dm.fx, fyd = dm.fy, cxd = dm.cx, cyd = dm.cy;
    const int dw = dm.z.cols, dh = dm.z.rows;
    Mat mapx(box.height, box.width, CV_32F), mapy(box.height, box.width, CV_32F), wgt(box.height, box.width, CV_32F);
    std::atomic<int> validTotal{0};
    // rows are independent: parallel over row stripes (this loop was ~40 % of the depth stitch)
    cv::parallel_for_(cv::Range(0, box.height), [&](const cv::Range& rg) {
    int valid = 0;
    for (int y = rg.start; y < rg.end; ++y) {
        float* mx = mapx.ptr<float>(y);
        float* my = mapy.ptr<float>(y);
        float* mw = wgt.ptr<float>(y);
        for (int x = 0; x < box.width; ++x) {
            const Vec3f d = C.dir(box.x + x, box.y + y);
            float t = -1.f;
            Vec3f Xc = Rt * d;
            for (int it = 0; it < 3; ++it) {
                if (t >= 0.f) Xc = Rt * (t * d - off);
                const float zc = -Xc[2];
                if (zc <= 1e-3f) { t = 50.f; continue; }
                const float inv = 1.f / zc;
                const float ud = fxd * Xc[0] * inv + cxd, vd = cyd - fyd * Xc[1] * inv;
                if (ud < 0 || ud > dw - 1 || vd < 0 || vd > dh - 1) { t = 50.f; continue; }
                const float zs = sampleBilinear(dm.z, ud, vd);
                if (zs <= 0.05f) { t = 50.f; continue; }
                const Vec3f Pc = Xc * (zs * inv);          // point on that pixel ray at the measured depth
                const Vec3f Pw = R * Pc + off;             // relative to the panorama centre
                t = std::sqrt(Pw.dot(Pw));
            }
            Xc = Rt * (t * d - off);
            const float zc = -Xc[2];
            bool okp = zc > 1e-3f;
            float u = -1, v = -1;
            if (okp) {
                const float inv = 1.f / zc;
                u = fx * Xc[0] * inv + cx;
                v = cy - fy * Xc[1] * inv;
                const float ud = fxd * Xc[0] * inv + cxd, vd = cyd - fyd * Xc[1] * inv;
                okp = u >= 0 && u <= w - 1 && v >= 0 && v <= h - 1 && ud >= 0 && ud <= dw - 1 && vd >= 0 && vd <= dh - 1;
                if (okp) {
                    const float zs = sampleBilinear(dm.z, ud, vd);
                    okp = std::fabs(zs - zc) < std::max(0.06f, 0.06f * zc);
                }
            }
            if (okp) {
                mx[x] = u;
                my[x] = v;
                float du = std::min(u, (w - 1) - u) / (w * feather);
                float dv = std::min(v, (h - 1) - v) / (h * feather);
                float tt = clampf(std::min(du, dv), 0.f, 1.f);
                mw[x] = tt * tt * (3 - 2 * tt);
                ++valid;
            } else {
                mx[x] = -1;
                my[x] = -1;
                mw[x] = 0;
            }
        }
    }
    validTotal += valid;
    });
    const int valid = validTotal.load();
    if (valid < 64) return false;
    cv::remap(img, out.img, mapx, mapy, cv::INTER_LINEAR, cv::BORDER_CONSTANT);
    out.w = wgt;
    out.box = box;
    return true;
}

static bool renderWarp(const Canvas& C, const Matx33f& R, float fx, float fy, float cx, float cy, const Mat& img,
                       const Rect& box, float feather, Warp& out) {
    const Matx33f Rt = R.t();
    const int w = img.cols, h = img.rows;
    Mat mapx(box.height, box.width, CV_32F), mapy(box.height, box.width, CV_32F), wgt(box.height, box.width, CV_32F);
    int valid = 0;
    for (int y = 0; y < box.height; ++y) {
        float* mx = mapx.ptr<float>(y);
        float* my = mapy.ptr<float>(y);
        float* mw = wgt.ptr<float>(y);
        for (int x = 0; x < box.width; ++x) {
            Vec3f dc = Rt * C.dir(box.x + x, box.y + y);
            const float z = dc[2];
            if (z < -1e-4f) {
                const float inv = 1.f / (-z);
                const float u = fx * dc[0] * inv + cx, v = cy - fy * dc[1] * inv;
                if (u >= 0 && u <= w - 1 && v >= 0 && v <= h - 1) {
                    mx[x] = u;
                    my[x] = v;
                    float du = std::min(u, (w - 1) - u) / (w * feather);
                    float dv = std::min(v, (h - 1) - v) / (h * feather);
                    float t = clampf(std::min(du, dv), 0.f, 1.f);
                    mw[x] = t * t * (3 - 2 * t);
                    ++valid;
                    continue;
                }
            }
            mx[x] = -1;
            my[x] = -1;
            mw[x] = 0;
        }
    }
    if (valid < 64) return false;
    cv::remap(img, out.img, mapx, mapy, cv::INTER_LINEAR, cv::BORDER_CONSTANT);
    out.w = wgt;
    out.box = box;
    return true;
}

static void accumulate(Mat& acc, Mat& wacc, const Warp& wp) {
    Mat img32;
    wp.img.convertTo(img32, CV_32FC3);
    Mat w3;
    cv::merge(std::vector<Mat>{wp.w, wp.w, wp.w}, w3);
    acc(wp.box) += img32.mul(w3);
    wacc(wp.box) += wp.w;
}

static Mat composite(const Mat& acc, const Mat& wacc) {
    Mat w3;
    cv::merge(std::vector<Mat>{wacc, wacc, wacc}, w3);
    Mat out32 = acc / cv::max(w3, 1e-6f);
    Mat out;
    out32.convertTo(out, CV_8UC3);
    return out;
}

// ---------------------------------------------------------- local alignment
static std::string localAlign(std::vector<Warp>& warps, const Mat& ref, Mat& acc, Mat& wacc, const Canvas& C,
                              float maxShift, int maxSide) {
    auto dis = cv::DISOpticalFlow::create(cv::DISOpticalFlow::PRESET_MEDIUM);
    dis->setUseSpatialPropagation(true);
    Mat accNew = Mat::zeros(C.H, C.We, CV_32FC3), waccNew = Mat::zeros(C.H, C.We, CV_32F);
    std::vector<float> moved;
    for (auto& wp : warps) {
        const int bw = wp.img.cols, bh = wp.img.rows;
        const float s = std::min(1.f, (float)maxSide / std::max(bw, bh));
        const int sw = std::max(int(bw * s), 16), sh = std::max(int(bh * s), 16);
        Mat refS, imgS;
        cv::resize(ref(wp.box), refS, Size(sw, sh), 0, 0, cv::INTER_AREA);
        cv::resize(wp.img, imgS, Size(sw, sh), 0, 0, cv::INTER_AREA);
        Mat gref, gimg;
        cv::cvtColor(refS, gref, cv::COLOR_BGR2GRAY);
        cv::cvtColor(imgS, gimg, cv::COLOR_BGR2GRAY);
        Mat flow;
        dis->calc(gref, gimg, flow);  // ref(x) ≈ img(x + flow(x))

        Mat others = wacc(wp.box) - wp.w;
        Mat confFull = (others > 0.08f) & (wp.w > 0.08f);
        Mat conf;
        confFull.convertTo(conf, CV_32F, 1.0 / 255.0);
        cv::resize(conf, conf, Size(sw, sh), 0, 0, cv::INTER_AREA);
        Mat gx, gy, tex;
        cv::Sobel(gref, gx, CV_32F, 1, 0, 3);
        cv::Sobel(gref, gy, CV_32F, 0, 1, 3);
        cv::magnitude(gx, gy, tex);
        cv::GaussianBlur(tex, tex, Size(), 3);
        tex = cv::min(tex / 40.f, 1.f);
        conf = conf.mul(tex);
        std::vector<Mat> fc;
        cv::split(flow, fc);
        Mat rawMag;
        cv::magnitude(fc[0], fc[1], rawMag);
        const float lim = maxShift * s;
        Mat gate;
        Mat(rawMag < 0.85f * lim).convertTo(gate, CV_32F, 1.0 / 255.0);
        conf = conf.mul(gate);
        // Local warping is disabled: dense flow bends straight lines and a per-frame
        // homography did not help (judged on real captures). Parallax is handled by the
        // depth path (MVS / depth re-projection) instead. Only the diagnostic remains.
        {
            float p95 = 0;
            std::vector<float> mags;
            for (int y = 0; y < sh; y += 2)
                for (int x = 0; x < sw; x += 2)
                    if (conf.at<float>(y, x) > 0.3f) {
                        cv::Vec2f f = flow.at<cv::Vec2f>(y, x);
                        mags.push_back(std::sqrt(f[0] * f[0] + f[1] * f[1]));
                    }
            if (!mags.empty()) {
                std::nth_element(mags.begin(), mags.begin() + size_t(mags.size() * 0.95), mags.end());
                p95 = mags[size_t(mags.size() * 0.95)] / s;
            }
            moved.push_back(p95);
        }
        accumulate(accNew, waccNew, wp);
    }
    acc = accNew;
    wacc = waccNew;
    if (moved.empty()) return "no frames";
    std::sort(moved.begin(), moved.end());
    char buf[64];
    snprintf(buf, sizeof buf, "residual p95≈%.1fpx (no warp)", moved[moved.size() / 2]);
    return buf;
}

// ------------------------------------------------------------------- seams
static bool seamBlend(std::vector<Warp>& warps, const Canvas& C, int bands, int seamWidth, float seamMinW,
                      Mat& out, Mat& outMask) {
    const int seamW = std::min(C.We, seamWidth);
    const float scale = (float)seamW / C.We;
    std::vector<cv::UMat> imgsS, masksS;
    std::vector<Point> corners;
    for (const auto& wp : warps) {
        int sx0 = int(wp.box.x * scale), sy0 = int(wp.box.y * scale);
        int sx1 = std::max(int(std::ceil((wp.box.x + wp.box.width) * scale)), sx0 + 1);
        int sy1 = std::max(int(std::ceil((wp.box.y + wp.box.height) * scale)), sy0 + 1);
        Mat imgS, imgF, mS;
        cv::resize(wp.img, imgS, Size(sx1 - sx0, sy1 - sy0), 0, 0, cv::INTER_AREA);
        imgS.convertTo(imgF, CV_32FC3);
        Mat m8 = (wp.w > seamMinW);  // keep seams away from frame borders
        cv::resize(m8, mS, Size(sx1 - sx0, sy1 - sy0), 0, 0, cv::INTER_NEAREST);
        cv::erode(mS, mS, Mat::ones(3, 3, CV_8U));
        cv::UMat ui, um;
        imgF.copyTo(ui);
        mS.copyTo(um);
        imgsS.push_back(ui);
        masksS.push_back(um);
        corners.push_back(Point(sx0, sy0));
    }
    cv::detail::GraphCutSeamFinder finder(cv::detail::GraphCutSeamFinderBase::COST_COLOR_GRAD);
    finder.find(imgsS, corners, masksS);

    cv::detail::MultiBandBlender blender(false, bands, CV_32F);
    blender.prepare(Rect(0, 0, C.We, C.H));
    const Mat kernel = Mat::ones(5, 5, CV_8U);
    int fed = 0;
    for (size_t i = 0; i < warps.size(); ++i) {
        const Warp& wp = warps[i];
        Mat mS = masksS[i].getMat(cv::ACCESS_READ).clone(), mask;
        cv::resize(mS, mask, Size(wp.box.width, wp.box.height), 0, 0, cv::INTER_NEAREST);
        cv::dilate(mask, mask, kernel);
        mask &= (wp.w > 0.f);
        if (cv::countNonZero(mask) == 0) continue;
        Mat img16;
        wp.img.convertTo(img16, CV_16SC3);
        blender.feed(img16, mask, Point(wp.box.x, wp.box.y));
        ++fed;
    }
    if (fed == 0) return false;
    Mat res16;
    blender.blend(res16, outMask);
    res16.convertTo(out, CV_8UC3);
    return true;
}

// -------------------------------------------------------------------- fold
static std::vector<int> wrapSeamPath(const Mat& A, const Mat& B) {
    Mat a32, b32, diff;
    A.convertTo(a32, CV_32F);
    B.convertTo(b32, CV_32F);
    cv::absdiff(a32, b32, diff);
    if (diff.channels() == 3) {
        std::vector<Mat> ch;
        cv::split(diff, ch);
        diff = (ch[0] + ch[1] + ch[2]) / 3.f;
    }
    const int Hh = diff.rows, P = diff.cols;
    const int margin = std::max(4, P / 12);
    diff.colRange(0, margin) += 1e4f;
    diff.colRange(P - margin, P) += 1e4f;
    Mat cost = diff.clone();
    Mat back(Hh, P, CV_8S);
    for (int y = 1; y < Hh; ++y) {
        const float* prev = cost.ptr<float>(y - 1);
        float* cur = cost.ptr<float>(y);
        schar* bk = back.ptr<schar>(y);
        for (int x = 0; x < P; ++x) {
            float best = prev[x];
            schar arg = 0;
            if (x > 0 && prev[x - 1] < best) { best = prev[x - 1]; arg = -1; }
            if (x < P - 1 && prev[x + 1] < best) { best = prev[x + 1]; arg = 1; }
            cur[x] += best;
            bk[x] = arg;
        }
    }
    std::vector<int> path(Hh);
    const float* last = cost.ptr<float>(Hh - 1);
    path[Hh - 1] = int(std::min_element(last, last + P) - last);
    for (int y = Hh - 1; y > 0; --y) path[y - 1] = path[y] + back.at<schar>(y, path[y]);
    return path;
}

static Mat foldCanvas(const Mat& arr, int W, int pad, const std::vector<int>& path) {
    Mat core = arr(Rect(pad, 0, W, arr.rows)).clone();
    Mat A = core(Rect(W - pad, 0, pad, arr.rows));
    Mat B = arr(Rect(0, 0, pad, arr.rows));
    Mat a32, b32;
    A.convertTo(a32, CV_32F);
    B.convertTo(b32, CV_32F);
    const int ch = a32.channels();
    for (int y = 0; y < arr.rows; ++y) {
        float* pa = a32.ptr<float>(y);
        const float* pb = b32.ptr<float>(y);
        for (int x = 0; x < pad; ++x) {
            float t = clampf((x - path[y]) / 12.f + 0.5f, 0.f, 1.f);
            for (int c = 0; c < ch; ++c) pa[x * ch + c] = pa[x * ch + c] * (1 - t) + pb[x * ch + c] * t;
        }
    }
    Mat mixed;
    a32.convertTo(mixed, arr.type());
    mixed.copyTo(core(Rect(W - pad, 0, pad, arr.rows)));
    return core;
}

// ------------------------------------------------------------------- poles
static void fixPoles(Mat& out, const Mat& holes8, float capDeg, int face = 1024) {
    const int H = out.rows, W = out.cols;
    const int capRows = int(H * capDeg / 180.f);
    const float f = (face / 2.f) / std::tan((capDeg + 6.f) * kPi / 180.f), c = face / 2.f;
    for (int s : {1, -1}) {
        const Rect rows = (s == 1) ? Rect(0, 0, W, capRows) : Rect(0, H - capRows, W, capRows);
        if (cv::countNonZero(holes8(rows)) == 0) continue;
        Mat mx(face, face, CV_32F), my(face, face, CV_32F);
        for (int v = 0; v < face; ++v)
            for (int u = 0; u < face; ++u) {
                Vec3f d = cv::normalize(Vec3f((u - c) / f, (float)s, (v - c) / f));
                float lon = std::atan2(d[0], -d[2]), lat = std::asin(clampf(d[1], -1.f, 1.f));
                mx.at<float>(v, u) = (lon + kPi) / (2 * kPi) * W - 0.5f;
                my.at<float>(v, u) = (kPi / 2 - lat) / kPi * H - 0.5f;
            }
        Mat faceImg, faceHole;
        cv::remap(out, faceImg, mx, my, cv::INTER_LINEAR, cv::BORDER_WRAP);
        cv::remap(holes8, faceHole, mx, my, cv::INTER_NEAREST, cv::BORDER_WRAP);
        cv::dilate(faceHole, faceHole, Mat::ones(13, 13, CV_8U));
        if (cv::countNonZero(faceHole) == 0) continue;

        Mat filled;
        if (s < 0) {
            // nadir: continue the floor inwards by mirroring the ring around the hole (r → 2·r0 − r)
            const float r0 = std::sqrt(cv::countNonZero(faceHole) / kPi) + 4.f;
            Mat mx2(face, face, CV_32F), my2(face, face, CV_32F);
            for (int v = 0; v < face; ++v)
                for (int u = 0; u < face; ++u) {
                    float dx = u - c, dy = v - c, r = std::sqrt(dx * dx + dy * dy) + 1e-6f;
                    float rs = r < r0 ? 2 * r0 - r : r;
                    mx2.at<float>(v, u) = c + dx / r * rs;
                    my2.at<float>(v, u) = c + dy / r * rs;
                }
            cv::remap(faceImg, filled, mx2, my2, cv::INTER_LINEAR, cv::BORDER_REFLECT);
            Mat soft;
            cv::GaussianBlur(filled, soft, Size(), std::max(6.f, 0.12f * r0));
            for (int v = 0; v < face; ++v)
                for (int u = 0; u < face; ++u) {
                    float dx = u - c, dy = v - c;
                    if (std::sqrt(dx * dx + dy * dy) < r0 * 0.6f) filled.at<cv::Vec3b>(v, u) = soft.at<cv::Vec3b>(v, u);
                }
        } else {
            cv::inpaint(faceImg, faceHole, filled, 9, cv::INPAINT_TELEA);
            Mat soft;
            cv::GaussianBlur(filled, soft, Size(), 5);
            soft.copyTo(filled, faceHole);
        }
        // soft ring between the real image and the fill
        Mat alpha;
        cv::dilate(faceHole, alpha, Mat::ones(41, 41, CV_8U));
        alpha.convertTo(alpha, CV_32F, 1.0 / 255.0);
        cv::GaussianBlur(alpha, alpha, Size(), 28);
        Mat fi32, fl32, a3;
        faceImg.convertTo(fi32, CV_32FC3);
        filled.convertTo(fl32, CV_32FC3);
        cv::merge(std::vector<Mat>{alpha, alpha, alpha}, a3);
        Mat blended32 = fi32.mul(cv::Scalar::all(1.f) - a3) + fl32.mul(a3);
        Mat blended;
        blended32.convertTo(blended, CV_8UC3);

        // equirect cap pixel → face pixel
        Mat fu(capRows, W, CV_32F), fv(capRows, W, CV_32F);
        Mat inside(capRows, W, CV_8U, cv::Scalar(0));
        for (int yy = 0; yy < capRows; ++yy) {
            float lat = kPi / 2 - (rows.y + yy + 0.5f) / H * kPi;
            for (int x = 0; x < W; ++x) {
                float lon = (x + 0.5f) / W * 2 * kPi - kPi;
                float dx = std::cos(lat) * std::sin(lon), dy = std::sin(lat), dz = -std::cos(lat) * std::cos(lon);
                float t = s * dy;
                if (t > 1e-3f) {
                    float u = c + f * dx / t, v = c + f * dz / t;
                    fu.at<float>(yy, x) = u;
                    fv.at<float>(yy, x) = v;
                    if (u >= 0 && u < face && v >= 0 && v < face) inside.at<uchar>(yy, x) = 255;
                } else {
                    fu.at<float>(yy, x) = -1;
                    fv.at<float>(yy, x) = -1;
                }
            }
        }
        Mat patch, ae;
        cv::remap(blended, patch, fu, fv, cv::INTER_LINEAR, cv::BORDER_REPLICATE);
        cv::remap(alpha, ae, fu, fv, cv::INTER_LINEAR, cv::BORDER_CONSTANT);
        ae.setTo(0, ~inside);
        Mat view = out(rows);
        Mat v32, p32, ae3;
        view.convertTo(v32, CV_32FC3);
        patch.convertTo(p32, CV_32FC3);
        cv::merge(std::vector<Mat>{ae, ae, ae}, ae3);
        Mat res32 = v32.mul(cv::Scalar::all(1.f) - ae3) + p32.mul(ae3);
        res32.convertTo(view, CV_8UC3);
    }
}

}  // namespace

Options optionsForFrameCount(int n) {
    Options o;
    if (n < 24) {  // sparse 18-target grid: ~7–13° overlaps
        o.feather = 0.12f;
        o.seamMinWeight = 0.06f;
    }
    return o;
}

// ==================================================================== main
// Nadir logo: the bottom cap (lat < −(90° − capDeg)) of the equirect is the "little planet"
// image of a disc around the nadir. Each cap pixel (lon, lat) maps to disc polar coordinates
// r = (90° + lat)/capDeg, θ = lon, and samples the logo at its centre + r·(cos θ, sin θ)·½. The
// logo's alpha (if any) and a soft rim over the last 12 % of the radius blend it into the floor.
static void stampNadirLogo(Mat& pano, const std::string& logoPath, float capDeg) {
    Mat logo = cv::imread(logoPath, cv::IMREAD_UNCHANGED);
    if (logo.empty() || capDeg <= 0) return;
    Mat rgb, alpha;
    if (logo.channels() == 4) {
        std::vector<Mat> ch;
        cv::split(logo, ch);
        cv::merge(std::vector<Mat>{ch[0], ch[1], ch[2]}, rgb);
        alpha = ch[3];
    } else {
        if (logo.channels() == 1) cv::cvtColor(logo, rgb, cv::COLOR_GRAY2BGR); else rgb = logo;
        alpha = Mat(logo.rows, logo.cols, CV_8U, cv::Scalar(255));
    }
    const int W = pano.cols, H = pano.rows;
    const int capRows = std::min(H, int(std::ceil(H * capDeg / 180.f)) + 1);
    const float lw = (float)rgb.cols, lh = (float)rgb.rows;
    Mat mapx(capRows, W, CV_32F), mapy(capRows, W, CV_32F), wgt(capRows, W, CV_32F);
    for (int y = 0; y < capRows; ++y) {
        const int py = H - capRows + y;
        const float lat = 90.f - 180.f * (py + 0.5f) / H;          // negative near the nadir
        const float r = (90.f + lat) / capDeg;                      // 0 at the nadir, 1 at the rim
        float* mx = mapx.ptr<float>(y);
        float* my = mapy.ptr<float>(y);
        float* mw = wgt.ptr<float>(y);
        for (int x = 0; x < W; ++x) {
            const float lon = (2.f * float(M_PI)) * ((x + 0.5f) / W) - float(M_PI);
            const float rc = std::min(r, 1.f);
            mx[x] = (0.5f + 0.5f * rc * std::sin(lon)) * (lw - 1);
            my[x] = (0.5f - 0.5f * rc * std::cos(lon)) * (lh - 1);   // lon 0 (panorama centre) = logo top
            const float rim = r < 0.88f ? 1.f : (r >= 1.f ? 0.f : (1.f - r) / 0.12f);
            mw[x] = rim * rim * (3 - 2 * rim);
        }
    }
    Mat lrgb, lalpha;
    cv::remap(rgb, lrgb, mapx, mapy, cv::INTER_LINEAR, cv::BORDER_REPLICATE);
    cv::remap(alpha, lalpha, mapx, mapy, cv::INTER_LINEAR, cv::BORDER_REPLICATE);
    Mat roi = pano.rowRange(H - capRows, H);
    for (int y = 0; y < capRows; ++y) {
        cv::Vec3b* dst = roi.ptr<cv::Vec3b>(y);
        const cv::Vec3b* src = lrgb.ptr<cv::Vec3b>(y);
        const uchar* a = lalpha.ptr<uchar>(y);
        const float* w = wgt.ptr<float>(y);
        for (int x = 0; x < W; ++x) {
            const float t = w[x] * (a[x] / 255.f);
            if (t <= 0) continue;
            for (int k = 0; k < 3; ++k) dst[x][k] = uchar(dst[x][k] * (1 - t) + src[x][k] * t + 0.5f);
        }
    }
}

static Result stitchImpl(const std::vector<FrameInput>& frames, const std::vector<Matx33f>& R, const std::vector<Vec3f>& P,
                         const std::vector<DepthMap>* depths, const Options& opt, const std::string& panoPath,
                         const std::string& previewPath, const Progress& progress, Result res,
                         std::chrono::steady_clock::time_point t0) {
    try {
        const int n = (int)frames.size();
        Vec3f Cpos(0, 0, 0);
        for (int i = 0; i < n; ++i) Cpos += P[i];
        Cpos *= 1.f / std::max(n, 1);
        int depthFrames = 0;

        Canvas C(opt.width);
        Mat acc = Mat::zeros(C.H, C.We, CV_32FC3), wacc = Mat::zeros(C.H, C.We, CV_32F);
        std::vector<Warp> warps;
        int used = 0;
        for (int i = 0; i < n; ++i) {
            if (progress) progress(0.2f + 0.4f * i / n, "Kadr " + std::to_string(i + 1) + "/" + std::to_string(n));
            Mat img = cv::imread(frames[i].path, cv::IMREAD_COLOR);
            if (img.empty()) continue;
            const float sx = (float)img.cols / frames[i].imageWidth, sy = (float)img.rows / frames[i].imageHeight;
            const float fx = frames[i].fx * sx, fy = frames[i].fy * sy, cx = frames[i].cx * sx, cy = frames[i].cy * sy;
            bool any = false;
            const DepthMap* dm = (depths && i < (int)depths->size() && !(*depths)[i].z.empty()) ? &(*depths)[i] : nullptr;
            if (dm) ++depthFrames;
            for (Rect box : frameBoxes(C, R[i], fx, fy, cx, cy, img.cols, img.rows)) {
                Warp wp;
                bool okw;
                if (dm) {
                    // parallax can move content a few degrees: grow the box first
                    const int my = int(C.H * 0.03), mx = int(C.We * 0.03);
                    const int y0 = std::max(0, box.y - my), y1 = std::min(C.H, box.y + box.height + my);
                    const int x0 = std::max(0, box.x - mx), x1 = std::min(C.We, box.x + box.width + mx);
                    box = Rect(x0, y0, x1 - x0, y1 - y0);
                    okw = renderWarpDepth(C, R[i], P[i], Cpos, *dm, fx, fy, cx, cy, img, box, opt.feather, wp);
                } else {
                    okw = renderWarp(C, R[i], fx, fy, cx, cy, img, box, opt.feather, wp);
                }
                if (!okw) continue;
                if (opt.gainComp && used > 0) {
                    Mat ov = (wacc(box) > 0.05f) & (wp.w > 0.05f);
                    if (cv::countNonZero(ov) > 2000) {
                        Mat w3;
                        cv::merge(std::vector<Mat>{wacc(box), wacc(box), wacc(box)}, w3);
                        Mat canvas = acc(box) / cv::max(w3, 1e-6f);
                        cv::Scalar cm = cv::mean(canvas, ov), mm = cv::mean(wp.img, ov);
                        float cmean = float(cm[0] + cm[1] + cm[2]) / 3.f, mmean = float(mm[0] + mm[1] + mm[2]) / 3.f;
                        float g = clampf((cmean + 1.f) / (mmean + 1.f), 0.6f, 1.6f);
                        wp.img.convertTo(wp.img, CV_8UC3, g);
                    }
                }
                accumulate(acc, wacc, wp);
                warps.push_back(std::move(wp));
                any = true;
            }
            if (any) ++used;
        }
        if (used == 0) throw std::runtime_error("no frame projected onto the sphere");
        res.frames = used;

        const int cutRow = opt.nadirCutDeg > 0 ? int(C.H * (1 - opt.nadirCutDeg / 180.f)) : C.H;
        auto applyNadirCut = [&]() {
            if (cutRow >= C.H) return;
            for (auto& wp : warps) {
                int r0 = cutRow - wp.box.y;
                if (r0 < wp.box.height) wp.w.rowRange(std::max(r0, 0), wp.box.height).setTo(0);
            }
            wacc.rowRange(cutRow, C.H).setTo(0);
        };
        applyNadirCut();
        Mat featherOut = composite(acc, wacc);

        if (opt.localAlign && used >= 2) {
            std::string notes;
            const float shifts[2] = {C.W * 0.025f, C.W * 0.015f};
            for (int it = 0; it < 2; ++it) {
                if (progress) progress(0.62f + 0.06f * it, "Lokal tekislash " + std::to_string(it + 1) + "/2");
                std::string note = localAlign(warps, featherOut, acc, wacc, C, shifts[it], opt.alignMaxSide);
                applyNadirCut();
                featherOut = composite(acc, wacc);
                notes += (it ? " → " : "") + note;
            }
            res.align = notes;
        } else {
            res.align = "none";
        }

        // best single frame per pixel
        Mat bestW = Mat::zeros(C.H, C.We, CV_32F), bestImg = Mat::zeros(C.H, C.We, CV_8UC3);
        for (const auto& wp : warps) {
            Mat better = wp.w > bestW(wp.box);
            wp.img.copyTo(bestImg(wp.box), better);
            wp.w.copyTo(bestW(wp.box), better);
        }
        Mat out = bestImg.clone();
        res.blend = "best-frame";
        if (opt.seams && used >= 2) {
            if (progress) progress(0.76f, "Choklarni topish");
            Mat blended, blendedMask;
            try {
                if (seamBlend(warps, C, opt.bands, opt.seamWidth, opt.seamMinWeight, blended, blendedMask)) {
                    blended.copyTo(out, blendedMask);
                    res.blend = "graphcut-seam+multiband";
                }
            } catch (const cv::Exception& e) {
                res.blend = std::string("best-frame (seam failed: ") + e.what() + ")";
            }
        }
        warps.clear();

        // fold the periodic extension back to W columns
        if (progress) progress(0.9f, "Tikuvni yopish");
        std::vector<int> path = wrapSeamPath(out(Rect(C.pad + C.W - C.pad, 0, C.pad, C.H)), out(Rect(0, 0, C.pad, C.H)));
        out = foldCanvas(out, C.W, C.pad, path);
        wacc = foldCanvas(wacc, C.W, C.pad, path);

        Mat holes8 = (wacc < 1e-3f);
        res.coverage = 1.f - float(cv::countNonZero(holes8)) / float(holes8.total());
        if (cv::countNonZero(holes8) > 0) {
            if (progress) progress(0.94f, "Bo'shliqlarni to'ldirish");
            fixPoles(out, holes8, opt.poleCapDeg);
            const int capRows = int(C.H * opt.poleCapDeg / 180.f);
            Mat mid = holes8.clone();
            mid.rowRange(0, capRows).setTo(0);
            mid.rowRange(C.H - capRows, C.H).setTo(0);
            if (cv::countNonZero(mid) > 0) {
                const int sw = std::min(C.W, 2048), sh = sw / 2;
                Mat small, smask, filled;
                cv::resize(out, small, Size(sw, sh), 0, 0, cv::INTER_AREA);
                cv::resize(mid, smask, Size(sw, sh), 0, 0, cv::INTER_NEAREST);
                cv::dilate(smask, smask, Mat::ones(5, 5, CV_8U));
                cv::inpaint(small, smask, filled, 5, cv::INPAINT_TELEA);
                cv::resize(filled, filled, Size(C.W, C.H), 0, 0, cv::INTER_LINEAR);
                filled.copyTo(out, mid);
            }
        }

        if (!opt.nadirLogoPath.empty()) stampNadirLogo(out, opt.nadirLogoPath, opt.nadirLogoDeg);

        if (progress) progress(0.98f, "Saqlash");
        cv::imwrite(panoPath, out, {cv::IMWRITE_JPEG_QUALITY, 90});
        if (!previewPath.empty()) {
            Mat prev;
            cv::resize(out, prev, Size(1024, 512), 0, 0, cv::INTER_AREA);
            cv::imwrite(previewPath, prev, {cv::IMWRITE_JPEG_QUALITY, 80});
        }
        res.width = C.W;
        res.height = C.H;
        res.depthFrames = depthFrames;
        if (depthFrames > 0) res.align = "depth-reprojection(" + std::to_string(depthFrames) + ")";
        res.ok = true;
        if (progress) progress(1.f, "Tayyor");
    } catch (const std::exception& e) {
        res.error = e.what();
        res.ok = false;
    }
    res.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    return res;
}

Result stitch(const std::vector<FrameInput>& frames, const Options& opt, const std::string& panoPath,
              const std::string& previewPath, const Progress& progress) {
    Result res;
    const auto t0 = std::chrono::steady_clock::now();
    if (frames.empty()) {
        res.error = "no frames";
        return res;
    }
    const int n = (int)frames.size();
    std::vector<Matx33f> R0(n), R;
    std::vector<Vec3f> P(n);
    for (int i = 0; i < n; ++i) {
        R0[i] = rotationFromTransform(frames[i].transform);
        P[i] = positionFromTransform(frames[i].transform);
    }
    try {
        R = (opt.refine && n >= 2) ? refineRotations(frames, R0, opt, progress, res) : R0;
    } catch (const std::exception& e) {
        res.error = std::string("refine: ") + e.what();
        return res;
    }
    return stitchImpl(frames, R, P, nullptr, opt, panoPath, previewPath, progress, res, t0);
}

Result stitchWithDepth(const std::vector<FrameInput>& frames, const std::vector<Pose>& poses,
                       const std::vector<DepthMap>& depths, const Options& opt, const std::string& panoPath,
                       const std::string& previewPath, const Progress& progress) {
    Result res;
    const auto t0 = std::chrono::steady_clock::now();
    if (frames.empty() || poses.size() != frames.size()) {
        res.error = "poses/frames mismatch";
        return res;
    }
    const int n = (int)frames.size();
    std::vector<Matx33f> R(n);
    std::vector<Vec3f> P(n);
    for (int i = 0; i < n; ++i) {
        R[i] = projectSO3(poses[i].R);
        P[i] = poses[i].p;
    }
    Options o = opt;
    o.localAlign = false;
    return stitchImpl(frames, R, P, &depths, o, panoPath, previewPath, progress, res, t0);
}

}  // namespace uy360
