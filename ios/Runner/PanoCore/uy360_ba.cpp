// Light 6-DoF bundle adjustment of ARKit poses (port of server/ba_poses.py). See the header.
#include "uy360_ba.hpp"

#include <opencv2/core.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/features.hpp>
#include <opencv2/flann.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <mutex>
#include <set>
#include <unordered_map>
#include <utility>
#include <vector>

namespace uy360 {
namespace {

bool debugOn() { static const bool on = std::getenv("UY360_BA_DEBUG") != nullptr; return on; }

constexpr int kMinObsPerCamera = 10;  // fewer → the camera keeps its ARKit pose

// OpenCV's FLANN indexes use the executing thread's RNG. Scope and restore it so
// prior captures and parallel scheduling cannot select different feature matches.
class ScopedMatchingRng {
public:
    ScopedMatchingRng(bool enabled, uint64_t seed) : enabled_(enabled), state_(cv::theRNG().state) {
        if (enabled_) cv::theRNG().state = seed;
    }
    ~ScopedMatchingRng() { if (enabled_) cv::theRNG().state = state_; }
    ScopedMatchingRng(const ScopedMatchingRng&) = delete;
    ScopedMatchingRng& operator=(const ScopedMatchingRng&) = delete;
private:
    bool enabled_;
    uint64_t state_;
};

using cv::Matx33d;
using cv::Vec3d;

// ----------------------------------------------------------------------------- SO(3)
Matx33d skew(const Vec3d& v) {
    return Matx33d(0, -v[2], v[1], v[2], 0, -v[0], -v[1], v[0], 0);
}

Matx33d expSO3(const Vec3d& w) {
    double th = cv::norm(w);
    Matx33d K = skew(w);
    if (th < 1e-9) return Matx33d::eye() + K;
    double a = std::sin(th) / th, b = (1.0 - std::cos(th)) / (th * th);
    return Matx33d::eye() + a * K + b * (K * K);
}

Vec3d logSO3(const Matx33d& R) {
    double c = std::max(-1.0, std::min(1.0, (R(0, 0) + R(1, 1) + R(2, 2) - 1.0) * 0.5));
    double th = std::acos(c);
    Vec3d v(R(2, 1) - R(1, 2), R(0, 2) - R(2, 0), R(1, 0) - R(0, 1));
    if (th < 1e-9) return 0.5 * v;
    if (th > M_PI - 1e-4) {
        // near π: axis from the symmetric part (R + I)/2 = a·aᵀ… pick the largest column
        Matx33d S = 0.5 * (R + Matx33d::eye());
        int k = 0;
        for (int i = 1; i < 3; ++i) if (S(i, i) > S(k, k)) k = i;
        Vec3d a(S(0, k), S(1, k), S(2, k));
        a = a / std::sqrt(std::max(S(k, k), 1e-12));
        return th * a;
    }
    return (th / (2.0 * std::sin(th))) * v;
}

double angleDeg(const Matx33d& A, const Matx33d& B) {  // angle between two rotations
    Matx33d D = A.t() * B;
    double c = std::max(-1.0, std::min(1.0, (D(0, 0) + D(1, 1) + D(2, 2) - 1.0) * 0.5));
    return std::acos(c) * 180.0 / M_PI;
}

Matx33d orthonormalize(const Matx33d& M) {
    cv::Mat A(M), w, u, vt;
    cv::SVD::compute(A, w, u, vt, cv::SVD::FULL_UV);
    cv::Mat R = u * vt;
    return Matx33d(R);
}

// ------------------------------------------------------- rotation-only camera graph (opt-in)
// A panorama stitched rotation-only cannot use rotations that were optimized jointly with a
// translation and then had that translation zeroed: the pair of them fitted the images
// together, and half of that fit is thrown away. These helpers solve the rotations on their
// own, from unit bearings, so the result is valid for a pure pivot.
Matx33d projectSO3(const Matx33d& M) {
    cv::Mat w, u, vt;
    cv::SVD::compute(cv::Mat(M), w, u, vt, cv::SVD::FULL_UV);
    cv::Mat R = u * vt;
    if (cv::determinant(R) < 0) {  // reflection: flip the least-significant axis
        cv::Mat d = cv::Mat::eye(3, 3, CV_64F);
        d.at<double>(2, 2) = -1;
        R = u * d * vt;
    }
    return Matx33d(R);
}

// R minimizing the angle between R·a_k and b_k (Kabsch on unit vectors).
Matx33d kabschSO3(const std::vector<Vec3d>& a, const std::vector<Vec3d>& b,
                  const std::vector<int>& use) {
    Matx33d M = Matx33d::zeros();
    for (int k : use)
        for (int r = 0; r < 3; ++r)
            for (int c = 0; c < 3; ++c) M(r, c) += b[k][r] * a[k][c];
    return projectSO3(M);
}

double angleBetweenDeg(const Vec3d& a, const Vec3d& b) {
    return std::acos(std::max(-1.0, std::min(1.0, a.dot(b)))) * 180.0 / M_PI;
}

/// RANSAC rotation consensus for one pair. `prior` is the relative sensor rotation; the
/// correction is bounded (maxDeltaDeg) so a wrong but self-consistent set of repeated
/// architectural features cannot rotate a camera away from the sensor. Returns the inliers.
int rotationConsensus(const std::vector<Vec3d>& a, const std::vector<Vec3d>& b,
                      const Matx33d& prior, uint64_t seed, Matx33d& out,
                      double thresholdDeg = 0.5, double maxDeltaDeg = 12.0) {
    out = prior;
    const int m = (int)a.size();
    if (m < 3) return 0;
    cv::RNG rng(seed);
    std::vector<int> best, sample(3), ok;
    double bestScore = std::numeric_limits<double>::max();
    for (int it = 0; it < 600; ++it) {
        for (int s = 0; s < 3; ++s) sample[s] = rng.uniform(0, m);
        if (sample[0] == sample[1] || sample[1] == sample[2] || sample[0] == sample[2]) continue;
        // Three nearly collinear or tightly clustered bearings do not determine a rotation.
        Matx33d S;
        for (int s = 0; s < 3; ++s)
            for (int c = 0; c < 3; ++c) S(s, c) = a[sample[s]][c];
        cv::Mat sv;
        cv::SVD::compute(cv::Mat(S), sv, cv::noArray(), cv::noArray(), cv::SVD::NO_UV);
        if (sv.at<double>(2) < 0.015) continue;
        Matx33d R = kabschSO3(a, b, sample);
        if (angleDeg(R, prior) > maxDeltaDeg) continue;
        ok.clear();
        std::vector<double> errs;
        for (int k = 0; k < m; ++k) {
            double e = angleBetweenDeg(R * a[k], b[k]);
            if (e < thresholdDeg) { ok.push_back(k); errs.push_back(e); }
        }
        if (ok.empty()) continue;
        std::nth_element(errs.begin(), errs.begin() + errs.size() / 2, errs.end());
        const double score = errs[errs.size() / 2];
        if (ok.size() > best.size() || (ok.size() == best.size() && score < bestScore)) {
            best = ok;
            bestScore = score;
        }
    }
    if ((int)best.size() < 3) return (int)best.size();
    Matx33d R = kabschSO3(a, b, best);
    for (int r = 0; r < 3; ++r) {
        ok.clear();
        for (int k = 0; k < m; ++k)
            if (angleBetweenDeg(R * a[k], b[k]) < thresholdDeg) ok.push_back(k);
        if ((int)ok.size() < 3) break;
        Matx33d cand = kabschSO3(a, b, ok);
        if (angleDeg(cand, prior) > maxDeltaDeg) break;
        R = cand;
        best = ok;
    }
    out = R;
    return (int)best.size();
}

struct RotationEdge {
    int i = 0, j = 0;
    Matx33d Rji;                 // R_jᵀ R_i from the consensus
    double weight = 0;           // capped inlier count
    std::vector<Vec3d> a, b;     // inlier bearings in camera axes
};

/// Synchronise the relative rotations over the graph, then refine directly on the bearings.
/// `soft` carries only the relative *sensor* rotation and is applied one-sidedly, to cameras
/// with no accepted edge: without it they keep the absolute sensor gauge while their
/// neighbours move several degrees, which tears the join along an untextured ceiling.
std::vector<Matx33d> solveRotationGraph(const std::vector<Matx33d>& R0,
                                        const std::vector<RotationEdge>& edges,
                                        const std::vector<RotationEdge>& soft,
                                        double priorWeight, double thresholdDeg) {
    const int n = (int)R0.size();
    std::vector<Matx33d> R = R0;
    std::vector<char> supported(n, 0);
    for (const auto& e : edges) { supported[e.i] = 1; supported[e.j] = 1; }
    auto addSoft = [&](int i, Matx33d& total) {
        if (supported[i] || priorWeight <= 0) return;
        for (const auto& l : soft) {
            // Links between two unsupported cameras still matter: they hold an untextured
            // region together while the cameras next to a solved one pull it into place.
            if (l.i == i) total += priorWeight * (R[l.j] * l.Rji);
            else if (l.j == i) total += priorWeight * (R[l.i] * l.Rji.t());
        }
    };
    for (int sweep = 0; sweep < 60; ++sweep)
        for (int i = 0; i < n; ++i) {
            Matx33d total = 2.0 * R0[i];
            for (const auto& e : edges) {
                if (e.i == i) total += e.weight * (R[e.j] * e.Rji);
                else if (e.j == i) total += e.weight * (R[e.i] * e.Rji.t());
            }
            addSoft(i, total);
            R[i] = projectSO3(total);
        }
    for (int sweep = 0; sweep < 50; ++sweep)
        for (int i = 0; i < n; ++i) {
            Matx33d total = 0.1 * R0[i];
            for (const auto& e : edges) {
                const bool first = e.i == i;
                if (!first && e.j != i) continue;
                const int j = first ? e.j : e.i;
                const std::vector<Vec3d>& a = first ? e.a : e.b;
                const std::vector<Vec3d>& b = first ? e.b : e.a;
                const double scale = e.weight / std::max<size_t>(1, a.size());
                for (size_t k = 0; k < a.size(); ++k) {
                    const Vec3d target = R[j] * b[k], current = R[i] * a[k];
                    const double err = angleBetweenDeg(current, target) / std::max(0.1, thresholdDeg);
                    const double w = scale / (1.0 + err * err);
                    for (int r = 0; r < 3; ++r)
                        for (int c = 0; c < 3; ++c) total(r, c) += w * target[r] * a[k][c];
                }
            }
            addSoft(i, total);
            R[i] = projectSO3(total);
        }
    // Restore the global sensor orientation (gauge). Individual tilts stay as solved.
    Matx33d g = Matx33d::zeros();
    for (int i = 0; i < n; ++i) g += R0[i] * R[i].t();
    const Matx33d gauge = projectSO3(g);
    for (int i = 0; i < n; ++i) R[i] = gauge * R[i];
    return R;
}

// -------------------------------------------------------------------- per-frame data
struct Cam {
    Matx33d R0;   // ARKit camera→world (orthonormalized)
    Vec3d p0;     // ARKit position
    double fx = 0, fy = 0, cx = 0, cy = 0;  // intrinsics at the feature resolution
    std::vector<cv::Point2f> kps;
    cv::Mat desc;
};

// select_neighbours() from mvs_depth.py
std::vector<int> selectNeighbours(const std::vector<Cam>& cams, int i, int k, double maxAngle, double minBase) {
    Vec3d fi(-cams[i].R0(0, 2), -cams[i].R0(1, 2), -cams[i].R0(2, 2));
    std::vector<std::pair<double, int>> cand;
    for (int j = 0; j < (int)cams.size(); ++j) {
        if (j == i) continue;
        Vec3d fj(-cams[j].R0(0, 2), -cams[j].R0(1, 2), -cams[j].R0(2, 2));
        double d = std::max(-1.0, std::min(1.0, fi.dot(fj)));
        double ang = std::acos(d) * 180.0 / M_PI;
        double base = cv::norm(cams[i].p0 - cams[j].p0);
        if (ang <= maxAngle && base >= minBase) cand.push_back({ang - 20.0 * std::min(base, 0.4), j});
    }
    std::sort(cand.begin(), cand.end());
    std::vector<int> out;
    for (int t = 0; t < (int)cand.size() && t < k; ++t) out.push_back(cand[t].second);
    return out;
}

// ------------------------------------------------------ essential matrix (8-point RANSAC)
// xa, xb: normalized pinhole coordinates ((u−cx)/fx, (v−cy)/fy; y down, z forward).
// Solves xbᵀ E xa = 0 in the least-squares sense and projects E onto the essential manifold.
bool fitEssential(const std::vector<cv::Point2d>& xa, const std::vector<cv::Point2d>& xb,
                  const std::vector<int>& idx, Matx33d& E) {
    if (idx.size() < 8) return false;
    cv::Mat A((int)idx.size(), 9, CV_64F);
    for (int r = 0; r < (int)idx.size(); ++r) {
        const cv::Point2d& a = xa[idx[r]];
        const cv::Point2d& b = xb[idx[r]];
        double* row = A.ptr<double>(r);
        row[0] = b.x * a.x; row[1] = b.x * a.y; row[2] = b.x;
        row[3] = b.y * a.x; row[4] = b.y * a.y; row[5] = b.y;
        row[6] = a.x;       row[7] = a.y;       row[8] = 1.0;
    }
    cv::Mat w, u, vt;
    cv::SVD::compute(A, w, u, vt, cv::SVD::FULL_UV);
    const double* e = vt.ptr<double>(8);
    Matx33d E0(e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8]);
    cv::Mat w2, u2, vt2;
    cv::SVD::compute(cv::Mat(E0), w2, u2, vt2, cv::SVD::FULL_UV);
    cv::Mat D = cv::Mat::zeros(3, 3, CV_64F);
    D.at<double>(0, 0) = 1.0;
    D.at<double>(1, 1) = 1.0;
    cv::Mat Em = u2 * D * vt2;
    E = Matx33d(Em);
    return std::isfinite(E(0, 0));
}

inline double sampsonSq(const Matx33d& E, const cv::Point2d& a, const cv::Point2d& b) {
    Vec3d xa(a.x, a.y, 1.0), xb(b.x, b.y, 1.0);
    Vec3d Ea = E * xa;
    Vec3d Etb = E.t() * xb;
    double num = xb.dot(Ea);
    double den = Ea[0] * Ea[0] + Ea[1] * Ea[1] + Etb[0] * Etb[0] + Etb[1] * Etb[1];
    return num * num / std::max(den, 1e-18);
}

inline int classifyE(const Matx33d& E, const std::vector<cv::Point2d>& xa, const std::vector<cv::Point2d>& xb,
                     double thr2, std::vector<char>& inl) {
    const int N = (int)xa.size();
    inl.resize(N);
    int cnt = 0;
    for (int i = 0; i < N; ++i) {
        inl[i] = sampsonSq(E, xa[i], xb[i]) < thr2;
        cnt += inl[i];
    }
    return cnt;
}

// Weighted least-squares 8-point fit (rows scaled by √w).
bool fitEssentialW(const std::vector<cv::Point2d>& xa, const std::vector<cv::Point2d>& xb,
                   const std::vector<int>& idx, const std::vector<double>& w, Matx33d& E) {
    if (idx.size() < 8) return false;
    cv::Mat A((int)idx.size(), 9, CV_64F);
    for (int r = 0; r < (int)idx.size(); ++r) {
        const cv::Point2d& a = xa[idx[r]];
        const cv::Point2d& b = xb[idx[r]];
        double s = std::sqrt(std::max(w[r], 0.0));
        double* row = A.ptr<double>(r);
        row[0] = s * b.x * a.x; row[1] = s * b.x * a.y; row[2] = s * b.x;
        row[3] = s * b.y * a.x; row[4] = s * b.y * a.y; row[5] = s * b.y;
        row[6] = s * a.x;       row[7] = s * a.y;       row[8] = s;
    }
    cv::Mat wv, u, vt;
    cv::SVD::compute(A, wv, u, vt, cv::SVD::FULL_UV);
    const double* e = vt.ptr<double>(8);
    Matx33d E0(e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8]);
    cv::Mat w2, u2, vt2;
    cv::SVD::compute(cv::Mat(E0), w2, u2, vt2, cv::SVD::FULL_UV);
    cv::Mat D = cv::Mat::zeros(3, 3, CV_64F);
    D.at<double>(0, 0) = 1.0;
    D.at<double>(1, 1) = 1.0;
    cv::Mat Em = u2 * D * vt2;
    E = Matx33d(Em);
    return std::isfinite(E(0, 0));
}

// E = [t]x R with |t| = 1 (5 DoF): R ← exp(δr)·R, t ← exp(δ3·a + δ4·b)·t with a, b ⊥ t.
struct EParam {
    Matx33d R;
    Vec3d t;
};

inline Matx33d composeE(const EParam& p) { return skew(p.t) * p.R; }

EParam decomposeE(const Matx33d& E) {
    cv::Mat w, u, vt;
    cv::SVD::compute(cv::Mat(E), w, u, vt, cv::SVD::FULL_UV);
    if (cv::determinant(u) < 0) u = -u;
    if (cv::determinant(vt) < 0) vt = -vt;
    cv::Mat W = (cv::Mat_<double>(3, 3) << 0, -1, 0, 1, 0, 0, 0, 0, 1);
    EParam p;
    p.R = Matx33d(cv::Mat(u * W * vt));
    p.t = Vec3d(u.at<double>(0, 2), u.at<double>(1, 2), u.at<double>(2, 2));
    return p;
}

EParam applyDelta(const EParam& p, const double* d) {
    Vec3d axis = std::fabs(p.t[0]) < 0.6 ? Vec3d(1, 0, 0) : Vec3d(0, 1, 0);
    Vec3d a = p.t.cross(axis);
    a *= 1.0 / cv::norm(a);
    Vec3d b = p.t.cross(a);
    EParam q;
    q.R = expSO3(Vec3d(d[0], d[1], d[2])) * p.R;
    q.t = expSO3(d[3] * a + d[4] * b) * p.t;
    q.t *= 1.0 / cv::norm(q.t);
    return q;
}

inline double sampsonSigned(const Matx33d& E, const cv::Point2d& a, const cv::Point2d& b) {
    Vec3d xa(a.x, a.y, 1.0), xb(b.x, b.y, 1.0);
    Vec3d Ea = E * xa;
    Vec3d Etb = E.t() * xb;
    double den = Ea[0] * Ea[0] + Ea[1] * Ea[1] + Etb[0] * Etb[0] + Etb[1] * Etb[1];
    return xb.dot(Ea) / std::sqrt(std::max(den, 1e-18));
}

// Geometric refinement of E on the (R, t) manifold: Levenberg–Marquardt on the Cauchy-robust
// Sampson error (scale = thr) over all matches, numeric Jacobian. The algebraic 8-point fit
// (even on clean inliers) is not accurate enough for a 1.5 px inlier threshold; this is.
void refineEssentialNonlinear(const std::vector<cv::Point2d>& xa, const std::vector<cv::Point2d>& xb,
                              double thr, Matx33d& E) {
    const int N = (int)xa.size();
    EParam p = decomposeE(E);
    const double thr2 = thr * thr;
    auto cost = [&](const EParam& q) {
        Matx33d Eq = composeE(q);
        double c = 0;
        for (int i = 0; i < N; ++i) c += std::log1p(sampsonSq(Eq, xa[i], xb[i]) / thr2);
        return thr2 * c;
    };
    double cur = cost(p), lambda = 1e-3;
    std::vector<double> r(N);
    std::vector<std::array<double, 5>> J(N);
    const double eps = 1e-6;
    for (int it = 0; it < 12; ++it) {
        Matx33d Ep = composeE(p);
        for (int i = 0; i < N; ++i) r[i] = sampsonSigned(Ep, xa[i], xb[i]);
        for (int k = 0; k < 5; ++k) {
            double d[5] = {0, 0, 0, 0, 0};
            d[k] = eps;
            Matx33d Ek = composeE(applyDelta(p, d));
            for (int i = 0; i < N; ++i) J[i][k] = (sampsonSigned(Ek, xa[i], xb[i]) - r[i]) / eps;
        }
        cv::Matx<double, 5, 5> H = cv::Matx<double, 5, 5>::zeros();
        cv::Matx<double, 5, 1> g = cv::Matx<double, 5, 1>::zeros();
        for (int i = 0; i < N; ++i) {
            double w = 1.0 / (1.0 + r[i] * r[i] / thr2);
            for (int a = 0; a < 5; ++a) {
                g(a, 0) += w * J[i][a] * r[i];
                for (int b = 0; b < 5; ++b) H(a, b) += w * J[i][a] * J[i][b];
            }
        }
        bool accepted = false;
        for (int attempt = 0; attempt < 6; ++attempt) {
            cv::Matx<double, 5, 5> Hd = H;
            for (int a = 0; a < 5; ++a) Hd(a, a) += lambda * std::max(H(a, a), 1e-12);
            cv::Matx<double, 5, 1> dlt;
            if (!cv::solve(Hd, -g, dlt, cv::DECOMP_CHOLESKY)) { lambda *= 10; continue; }
            double d[5] = {dlt(0, 0), dlt(1, 0), dlt(2, 0), dlt(3, 0), dlt(4, 0)};
            EParam q = applyDelta(p, d);
            double c = cost(q);
            if (c < cur) {
                double rel = (cur - c) / std::max(cur, 1e-12);
                p = q;
                cur = c;
                lambda = std::max(lambda / 3, 1e-9);
                accepted = rel > 1e-6;
                break;
            }
            lambda *= 5;
        }
        if (!accepted) break;
    }
    E = composeE(p);
}

// Iterative refinement of an essential-matrix hypothesis (stand-in for the local optimisation
// a 5-point RANSAC would not need): Cauchy-weighted 8-point refits on the matches within a
// shrinking Sampson threshold (ladder × thr). The state with the most inliers at `thr` wins
// (a rough start — the ARKit relative pose, or a noisy minimal sample — converges onto the
// consistent matches; a refit that degrades is never kept). Returns that inlier count.
int refineEssential(const std::vector<cv::Point2d>& xa, const std::vector<cv::Point2d>& xb, double thr,
                    Matx33d& E, std::vector<char>& inl) {
    static const double ladder[] = {5.0, 3.0, 2.0, 1.4, 1.0, 1.0, 1.0};
    const int N = (int)xa.size();
    const double thr2 = thr * thr;
    int best = classifyE(E, xa, xb, thr2, inl);
    Matx33d Ebest = E, Ecur = E;
    std::vector<char> cur;
    std::vector<int> ids;
    std::vector<double> ws;
    for (double m : ladder) {
        const double tau2 = thr2 * m * m;
        ids.clear();
        ws.clear();
        for (int i = 0; i < N; ++i) {
            double d2 = sampsonSq(Ecur, xa[i], xb[i]);
            if (d2 < tau2) { ids.push_back(i); ws.push_back(1.0 / (1.0 + d2 / tau2)); }
        }
        if ((int)ids.size() < 8) break;
        Matx33d En;
        if (!fitEssentialW(xa, xb, ids, ws, En)) break;
        Ecur = En;
        int c = classifyE(Ecur, xa, xb, thr2, cur);
        if (c > best) { best = c; Ebest = Ecur; inl = cur; }
    }
    if (best >= 8) {
        Matx33d En = Ebest;
        refineEssentialNonlinear(xa, xb, thr, En);
        int c = classifyE(En, xa, xb, thr2, cur);
        if (c > best) { best = c; Ebest = En; inl = cur; }
    }
    E = Ebest;
    return best;
}

void rotationsFromEssential(const Matx33d& E, Matx33d& R1, Matx33d& R2);
static double rotAngleDeg(const Matx33d& A, const Matx33d& B) {
    Matx33d D = A.t() * B;
    double c = std::max(-1.0, std::min(1.0, (D(0, 0) + D(1, 1) + D(2, 2) - 1.0) * 0.5));
    return std::acos(c) * 180.0 / M_PI;
}

// Essential matrix of a neighbouring pair (stand-in for cv::findEssentialMat, 5-point RANSAC).
// Two hypothesis sources, each refined with refineEssential(); the one with more inliers wins:
//   1. the ARKit relative pose  E = [t]x R  (pinhole axes) — deterministic and, since ARKit
//      is locally accurate, usually already within a few px of the true epipolar geometry;
//   2. 8-point RANSAC (prob 0.999) with local optimisation of every new best sample.
int estimateEssential(const std::vector<cv::Point2d>& xa, const std::vector<cv::Point2d>& xb, double thr,
                      const Matx33d& Rprior, const Vec3d& tprior, uint64_t seed, Matx33d& bestE,
                      std::vector<char>& inl) {
    const int N = (int)xa.size();
    inl.assign(N, 0);
    if (N < 8) return 0;
    const double thr2 = thr * thr;
    int best = 0;
    int knownRCount = 0;            // rotation-known hypothesis (1b), kept as the fallback
    Matx33d knownRE;
    std::vector<char> knownRInl;
    // 1. ARKit-seeded
    if (cv::norm(tprior) > 1e-6) {
        Matx33d E = skew(tprior * (1.0 / cv::norm(tprior))) * Rprior;
        std::vector<char> cur;
        int cnt = refineEssential(xa, xb, thr, E, cur);
        if (cnt > best) { best = cnt; bestE = E; inl = cur; }
    }
    // 1b. rotation-known 2-point RANSAC: the prior *rotation* is accurate (ARKit, or gyro fusion
    //     to ~0.5°) even when the prior translation is not (no ARCore: positions unknown). With R
    //     fixed, every match gives one linear equation on the translation direction,
    //     (xb × R·xa)·t = 0, so two matches determine t = c1 × c2. Cheap, and it rescues pairs
    //     with 25–60 matches that the 8-point sampler cannot fit. Polished by refineEssential().
    {
        std::vector<Vec3d> cv3(N);
        for (int i = 0; i < N; ++i) {
            Vec3d a(xa[i].x, xa[i].y, 1.0), b(xb[i].x, xb[i].y, 1.0);
            cv3[i] = b.cross(Rprior * a);
        }
        cv::RNG rng2(seed ^ 0x9e3779b97f4a7c15ULL);
        std::vector<char> cur;
        int bestT = 0;
        Matx33d bestET;
        const double thrLoose2 = thr2 * 4.0;   // R is approximate: classify hypotheses at 2×thr
        for (int it = 0; it < 300; ++it) {
            int i1 = rng2.uniform(0, N), i2 = rng2.uniform(0, N);
            if (i1 == i2) continue;
            Vec3d t = cv3[i1].cross(cv3[i2]);
            double nt = cv::norm(t);
            if (nt < 1e-9) continue;
            Matx33d E = skew(t * (1.0 / nt)) * Rprior;
            int cnt = classifyE(E, xa, xb, thrLoose2, cur);
            if (cnt > bestT) { bestT = cnt; bestET = E; }
        }
        if (bestT >= 8) {
            Matx33d E = bestET;
            int cnt = refineEssential(xa, xb, thr, E, cur);
            if (cnt > best) { best = cnt; bestE = E; inl = cur; }
            knownRCount = cnt; knownRE = E; knownRInl = cur;
        }
    }
    // 2. 8-point RANSAC + LO
    cv::RNG rng(seed);
    int maxIter = 1000;
    std::vector<int> sample(8);
    std::vector<char> cur(N);
    int bestRaw = 0;
    for (int it = 0; it < maxIter; ++it) {
        for (int s = 0; s < 8; ++s) {
            int v;
            bool dup;
            do {
                v = rng.uniform(0, N);
                dup = false;
                for (int q = 0; q < s; ++q) if (sample[q] == v) { dup = true; break; }
            } while (dup);
            sample[s] = v;
        }
        Matx33d E;
        if (!fitEssential(xa, xb, sample, E)) continue;
        int cnt = classifyE(E, xa, xb, thr2, cur);
        if (cnt > bestRaw && cnt >= 8) {
            bestRaw = cnt;
            if (cnt > best) { best = cnt; bestE = E; inl = cur; }
            // local optimisation of the new best sample
            Matx33d El = E;
            std::vector<char> il;
            int cl = refineEssential(xa, xb, thr, El, il);
            if (cl > best) { best = cl; bestE = El; inl = il; }
            double w = (double)std::max(cnt, cl) / N;
            double pNoOut = 1.0 - std::pow(w, 8);
            pNoOut = std::min(std::max(pNoOut, 1e-12), 1.0 - 1e-12);
            int need = (int)std::ceil(std::log(1.0 - 0.999) / std::log(pNoOut));
            maxIter = std::min(maxIter, std::max(need, it + 1));
        }
    }
    // The calibrated five-point solver also works on sparse, near-planar overlaps
    // where an eight-point sample often degenerates. Keep its hypothesis only if
    // the rotation agrees with the sensor prior and its consensus is stronger.
    cv::Mat nativeMask;
    cv::Mat nativeE = cv::findEssentialMat(xa, xb, Matx33d::eye(), cv::RANSAC, 0.999, thr, 2000, nativeMask);
    if (nativeE.cols == 3 && nativeE.rows == 3) {
        Matx33d E(nativeE), R1, R2;
        rotationsFromEssential(E, R1, R2);
        const double dR = std::min(rotAngleDeg(R1, Rprior), rotAngleDeg(R2, Rprior));
        if (dR < 8) {
            std::vector<char> mask;
            int count = classifyE(E, xa, xb, thr2, mask);
            if (count > best) { best = count; bestE = E; inl = mask; }
        }
    }
    // A degenerate 8-point solution can collect a few more inliers with a rotation that is
    // nowhere near the prior (the caller rejects such pairs). Prefer the rotation-consistent
    // hypothesis when the winner disagrees with the prior by more than 25°.
    if (best > 0 && knownRCount >= 8) {
        Matx33d R1, R2;
        rotationsFromEssential(bestE, R1, R2);
        double dR = std::min(rotAngleDeg(R1, Rprior), rotAngleDeg(R2, Rprior));
        if (dR > 25.0) { best = knownRCount; bestE = knownRE; inl = knownRInl; }
    }
    return best;
}

// The two rotation candidates of E = [t]x R (xb ~ R xa + t).
void rotationsFromEssential(const Matx33d& E, Matx33d& R1, Matx33d& R2) {
    cv::Mat w, u, vt;
    cv::SVD::compute(cv::Mat(E), w, u, vt, cv::SVD::FULL_UV);
    if (cv::determinant(u) < 0) u = -u;
    if (cv::determinant(vt) < 0) vt = -vt;
    cv::Mat W = (cv::Mat_<double>(3, 3) << 0, -1, 0, 1, 0, 0, 0, 0, 1);
    R1 = Matx33d(cv::Mat(u * W * vt));
    R2 = Matx33d(cv::Mat(u * W.t() * vt));
}

// ------------------------------------------------------------------ union-find tracks
struct UnionFind {
    std::unordered_map<int64_t, int64_t> parent;
    int64_t find(int64_t a) {
        auto it = parent.find(a);
        if (it == parent.end()) return a;
        int64_t root = a;
        while (true) {
            auto jt = parent.find(root);
            if (jt == parent.end() || jt->second == root) break;
            root = jt->second;
        }
        // path compression
        while (true) {
            auto jt = parent.find(a);
            if (jt == parent.end() || jt->second == root || jt->second == a) break;
            int64_t nxt = jt->second;
            jt->second = root;
            a = nxt;
        }
        return root;
    }
    void unite(int64_t a, int64_t b) {
        int64_t ra = find(a), rb = find(b);
        if (ra != rb) parent[ra] = rb;
        parent.emplace(a, find(a));
        parent.emplace(b, find(b));
    }
};

// ------------------------------------------------------------------------- BA problem
struct Obs {
    int cam, pt;
    double u, v;
};

struct Problem {
    int n = 0;
    std::vector<Cam>* cams = nullptr;
    std::vector<Matx33d> R;    // current rotations
    std::vector<Vec3d> p;      // current positions
    std::vector<Vec3d> dth;    // accumulated rotation correction: R = exp(dth)·R0
    std::vector<Vec3d> X;      // points
    std::vector<Obs> obs;
    std::vector<std::vector<int>> ptObs;  // per point: observation indices
    std::vector<char> fixedCam;           // too few observations: held at the ARKit pose
    double posSigma = 0.03, rotSigma = 0.026, C = 2.0;
    Vec3d rotSigmaV{0.026, 0.026, 0.026};   // per world axis (y = yaw)
    // relative-rotation chain prior: e_k = dth[k+1] − Q_k·dth[k], Q_k = R0[k+1]·R0[k]ᵀ  (0 = off)
    double relRotSigma = 0;
    std::vector<Matx33d> Q;               // n−1 entries

    // Cauchy loss ρ(r) = C² ln(1 + r²/C²), weight ρ'(r)/r… we use the IRLS weight 1/(1+z)
    double rho(double r) const { double z = r / C; return C * C * std::log1p(z * z); }
    double weight(double r) const { double z = r / C; return 1.0 / (1.0 + z * z); }

    // reprojection residual of observation o with the given state
    inline void residual(const Obs& o, const Matx33d& Rc, const Vec3d& pc, const Vec3d& Xw, double& ru,
                         double& rv, Vec3d* Xc_out = nullptr, double* z_out = nullptr) const {
        const Cam& c = (*cams)[o.cam];
        Vec3d Xc = Rc.t() * (Xw - pc);
        double z = std::max(-Xc[2], 1e-3);
        double u = c.fx * Xc[0] / z + c.cx;
        double v = c.cy - c.fy * Xc[1] / z;
        ru = u - o.u;
        rv = v - o.v;
        if (Xc_out) *Xc_out = Xc;
        if (z_out) *z_out = z;
    }

    double cost(const std::vector<Matx33d>& Rs, const std::vector<Vec3d>& ps, const std::vector<Vec3d>& dths,
                const std::vector<Vec3d>& Xs) const {
        double s = 0;
        for (const Obs& o : obs) {
            double ru, rv;
            residual(o, Rs[o.cam], ps[o.cam], Xs[o.pt], ru, rv);
            s += rho(ru) + rho(rv);
        }
        for (int c = 0; c < n; ++c) {
            Vec3d dp = (ps[c] - (*cams)[c].p0) / posSigma;
            Vec3d dr(dths[c][0] / rotSigmaV[0], dths[c][1] / rotSigmaV[1], dths[c][2] / rotSigmaV[2]);
            for (int k = 0; k < 3; ++k) s += rho(dp[k]) + rho(dr[k]);
        }
        if (relRotSigma > 0)
            for (int c = 0; c + 1 < n; ++c) {
                Vec3d e = (dths[c + 1] - Q[c] * dths[c]) / relRotSigma;
                for (int k = 0; k < 3; ++k) s += rho(e[k]);
            }
        return s;
    }

    double medianReproj() const {
        std::vector<double> e;
        e.reserve(obs.size());
        for (const Obs& o : obs) {
            double ru, rv;
            residual(o, R[o.cam], p[o.cam], X[o.pt], ru, rv);
            e.push_back(std::hypot(ru, rv));
        }
        if (e.empty()) return 0;
        size_t m = e.size() / 2;
        std::nth_element(e.begin(), e.begin() + m, e.end());
        return e[m];
    }

    // Gauge fix. The reprojection term is invariant to a global similarity transform of cameras
    // and points, so only the (Cauchy, hence weak) ARKit prior anchors the rig's orientation,
    // position and scale: a converged solution may tilt the whole rig by ~1° at almost no cost.
    // Re-align the free cameras to ARKit with the least-squares similarity (Kabsch on the
    // rotations, centroid + scale on the positions), carry the points, keep it if the objective
    // does not increase (it decreases: the prior shrinks, the reprojection term is unchanged
    // except for the few observations of cameras held at ARKit).
    bool gaugeAlign(double& curCost) {
        std::vector<int> fr;
        for (int c = 0; c < n; ++c) if (!fixedCam[c]) fr.push_back(c);
        if (fr.size() < 2) return false;
        Matx33d M = Matx33d::zeros();
        Vec3d cb(0, 0, 0), c0b(0, 0, 0);
        for (int c : fr) {
            M += (*cams)[c].R0 * R[c].t();
            cb += p[c];
            c0b += (*cams)[c].p0;
        }
        cb *= 1.0 / fr.size();
        c0b *= 1.0 / fr.size();
        cv::Mat w, u, vt;
        cv::SVD::compute(cv::Mat(M), w, u, vt, cv::SVD::FULL_UV);
        cv::Mat D = cv::Mat::eye(3, 3, CV_64F);
        if (cv::determinant(u * vt) < 0) D.at<double>(2, 2) = -1;
        Matx33d Rg(cv::Mat(u * D * vt));
        double num = 0, den = 0;
        for (int c : fr) {
            Vec3d q = Rg * (p[c] - cb), q0 = (*cams)[c].p0 - c0b;
            num += q0.dot(q);
            den += q.dot(q);
        }
        double sc = den > 1e-12 ? std::min(1.1, std::max(0.9, num / den)) : 1.0;
        Vec3d tg = c0b - sc * (Rg * cb);
        std::vector<Matx33d> Rn = R;
        std::vector<Vec3d> pn = p, dthn = dth, Xn(X.size());
        for (int c : fr) {
            Rn[c] = Rg * R[c];
            pn[c] = sc * (Rg * p[c]) + tg;
            dthn[c] = logSO3(Rn[c] * (*cams)[c].R0.t());
        }
        for (size_t k = 0; k < X.size(); ++k) Xn[k] = sc * (Rg * X[k]) + tg;
        double newCost = cost(Rn, pn, dthn, Xn);
        if (debugOn())
            std::fprintf(stderr, "  gauge: rot %.3f deg, shift %.2f cm, scale %.4f, cost %.1f -> %.1f\n",
                         cv::norm(logSO3(Rg)) * 180.0 / M_PI, 100.0 * cv::norm(tg + sc * (Rg * cb) - cb), sc, curCost, newCost);
        if (!std::isfinite(newCost) || newCost > curCost) return false;
        R.swap(Rn); p.swap(pn); dth.swap(dthn); X.swap(Xn);
        curCost = newCost;
        return true;
    }

    // One LM iteration with the Schur complement. Returns true if a step was accepted.
    bool lmStep(double& lambda, double& curCost) {
        const int npts = (int)X.size();
        typedef cv::Matx<double, 6, 6> M66;
        typedef cv::Matx<double, 6, 3> M63;
        typedef cv::Matx<double, 6, 1> V6;
        std::vector<M66> U(n, M66::zeros());
        std::vector<V6> gc(n, V6::zeros());
        std::vector<Matx33d> V(npts, Matx33d::zeros());
        std::vector<Vec3d> gp(npts, Vec3d(0, 0, 0));
        std::vector<M63> W(obs.size());

        // observation blocks
        for (size_t oi = 0; oi < obs.size(); ++oi) {
            const Obs& o = obs[oi];
            const Cam& c = (*cams)[o.cam];
            const Matx33d& Rc = R[o.cam];
            Vec3d d = X[o.pt] - p[o.cam];
            Vec3d Xc;
            double z, ru, rv;
            residual(o, Rc, p[o.cam], X[o.pt], ru, rv, &Xc, &z);
            double iz = 1.0 / z;
            // A = d(u,v)/dXc
            cv::Matx<double, 2, 3> A(c.fx * iz, 0, c.fx * Xc[0] * iz * iz,
                                     0, -c.fy * iz, -c.fy * Xc[1] * iz * iz);
            Matx33d Rt = Rc.t();
            cv::Matx<double, 2, 3> ARt = A * Rt;
            cv::Matx<double, 2, 3> Jrot = ARt * skew(d);   // d/dδ  (R ← exp(δ)R)
            cv::Matx<double, 2, 3> Jpos = -ARt;            // d/dp
            const cv::Matx<double, 2, 3>& Jpt = ARt;       // d/dX
            cv::Matx<double, 2, 6> Jc = cv::Matx<double, 2, 6>::zeros();
            if (!fixedCam[o.cam])
                for (int k = 0; k < 3; ++k) {
                    Jc(0, k) = Jrot(0, k); Jc(1, k) = Jrot(1, k);
                    Jc(0, 3 + k) = Jpos(0, k); Jc(1, 3 + k) = Jpos(1, k);
                }
            cv::Matx22d Wd(weight(ru), 0, 0, weight(rv));
            cv::Matx<double, 6, 2> JcW = Jc.t() * Wd;
            cv::Matx<double, 3, 2> JpW = Jpt.t() * Wd;
            cv::Matx21d r(ru, rv);
            U[o.cam] += JcW * Jc;
            V[o.pt] += JpW * Jpt;
            W[oi] = JcW * Jpt;
            gc[o.cam] += JcW * r;
            { cv::Matx31d g = JpW * r; gp[o.pt] += Vec3d(g(0, 0), g(1, 0), g(2, 0)); }
        }
        // prior blocks
        for (int c = 0; c < n; ++c) {
            Vec3d dp = (p[c] - (*cams)[c].p0) / posSigma;
            Vec3d dr(dth[c][0] / rotSigmaV[0], dth[c][1] / rotSigmaV[1], dth[c][2] / rotSigmaV[2]);
            for (int k = 0; k < 3; ++k) {
                double wr = weight(dr[k]) / (rotSigmaV[k] * rotSigmaV[k]);
                double wp = weight(dp[k]) / (posSigma * posSigma);
                U[c](k, k) += wr;
                U[c](3 + k, 3 + k) += wp;
                gc[c](k, 0) += weight(dr[k]) * dr[k] / rotSigmaV[k];
                gc[c](3 + k, 0) += weight(dp[k]) * dp[k] / posSigma;
            }
        }

        // relative-rotation chain blocks (couple consecutive cameras: off-diagonal 3×3 blocks)
        struct Coupling { int a, b; Matx33d ab; };   // S[a,b] += ab, S[b,a] += abᵀ
        std::vector<Coupling> couplings;
        if (relRotSigma > 0)
            for (int c = 0; c + 1 < n; ++c) {
                const int a = c, b = c + 1;
                Vec3d e = (dth[b] - Q[c] * dth[a]) / relRotSigma;
                Matx33d Wm = Matx33d::zeros();
                for (int k = 0; k < 3; ++k) Wm(k, k) = weight(e[k]) / (relRotSigma * relRotSigma);
                Vec3d we;
                for (int k = 0; k < 3; ++k) we[k] = weight(e[k]) * e[k] / relRotSigma;
                const bool fa = fixedCam[a], fb = fixedCam[b];
                // J_a = −Q (rot part of a), J_b = I (rot part of b)
                if (!fa) {
                    Matx33d QtW = Q[c].t() * Wm;
                    Matx33d blk = QtW * Q[c];
                    for (int r = 0; r < 3; ++r)
                        for (int k = 0; k < 3; ++k) U[a](r, k) += blk(r, k);
                    Vec3d ga = Q[c].t() * we;               // Jaᵀ·(w e/σ) with Ja = −Q
                    for (int k = 0; k < 3; ++k) gc[a](k, 0) -= ga[k];
                }
                if (!fb) {
                    for (int k = 0; k < 3; ++k) { U[b](k, k) += Wm(k, k); gc[b](k, 0) += we[k]; }
                }
                if (!fa && !fb) couplings.push_back({a, b, -(Q[c].t() * Wm)});   // Jaᵀ W Jb = (−Q)ᵀ W I
            }

        for (int attempt = 0; attempt < 10; ++attempt) {
            // damped blocks
            std::vector<Matx33d> Vinv(npts);
            for (int k = 0; k < npts; ++k) {
                Matx33d Vd = V[k];
                for (int t = 0; t < 3; ++t) Vd(t, t) += lambda * std::max(V[k](t, t), 1e-9);
                Vinv[k] = Vd.inv();
            }
            cv::Mat S = cv::Mat::zeros(6 * n, 6 * n, CV_64F);
            cv::Mat b = cv::Mat::zeros(6 * n, 1, CV_64F);
            for (int c = 0; c < n; ++c) {
                M66 Ud = U[c];
                for (int t = 0; t < 6; ++t) Ud(t, t) += lambda * std::max(U[c](t, t), 1e-9);
                for (int a = 0; a < 6; ++a) {
                    b.at<double>(6 * c + a) = -gc[c](a, 0);
                    for (int bb = 0; bb < 6; ++bb) S.at<double>(6 * c + a, 6 * c + bb) = Ud(a, bb);
                }
            }
            for (const Coupling& cp : couplings)
                for (int r = 0; r < 3; ++r)
                    for (int k = 0; k < 3; ++k) {
                        S.at<double>(6 * cp.a + r, 6 * cp.b + k) += cp.ab(r, k);
                        S.at<double>(6 * cp.b + k, 6 * cp.a + r) += cp.ab(r, k);
                    }
            for (int k = 0; k < npts; ++k) {
                const std::vector<int>& ol = ptObs[k];
                Vec3d vg = Vinv[k] * gp[k];
                for (int oa : ol) {
                    int ca = obs[oa].cam;
                    M63 WV = W[oa] * Vinv[k];
                    V6 t = W[oa] * vg;
                    for (int a = 0; a < 6; ++a) b.at<double>(6 * ca + a) += t(a, 0);
                    for (int ob : ol) {
                        int cb = obs[ob].cam;
                        M66 blk = WV * W[ob].t();
                        for (int a = 0; a < 6; ++a)
                            for (int bb = 0; bb < 6; ++bb) S.at<double>(6 * ca + a, 6 * cb + bb) -= blk(a, bb);
                    }
                }
            }
            cv::Mat dc;
            bool ok = cv::solve(S, b, dc, cv::DECOMP_CHOLESKY);
            if (!ok) ok = cv::solve(S, b, dc, cv::DECOMP_SVD);
            if (!ok) { lambda *= 10; continue; }
            // back-substitute points
            std::vector<Vec3d> Xn(npts);
            for (int k = 0; k < npts; ++k) {
                Vec3d rhs = -gp[k];
                for (int oa : ptObs[k]) {
                    int ca = obs[oa].cam;
                    V6 dcc;
                    for (int a = 0; a < 6; ++a) dcc(a, 0) = dc.at<double>(6 * ca + a);
                    cv::Matx31d t = W[oa].t() * dcc;
                    rhs -= Vec3d(t(0, 0), t(1, 0), t(2, 0));
                }
                Xn[k] = X[k] + Vinv[k] * rhs;
            }
            std::vector<Matx33d> Rn(n);
            std::vector<Vec3d> pn(n), dthn(n);
            for (int c = 0; c < n; ++c) {
                Vec3d dr(dc.at<double>(6 * c), dc.at<double>(6 * c + 1), dc.at<double>(6 * c + 2));
                Vec3d dp(dc.at<double>(6 * c + 3), dc.at<double>(6 * c + 4), dc.at<double>(6 * c + 5));
                Rn[c] = expSO3(dr) * R[c];
                pn[c] = p[c] + dp;
                dthn[c] = logSO3(Rn[c] * (*cams)[c].R0.t());
            }
            double newCost = cost(Rn, pn, dthn, Xn);
            if (std::isfinite(newCost) && newCost < curCost) {
                R.swap(Rn); p.swap(pn); dth.swap(dthn); X.swap(Xn);
                double rel = (curCost - newCost) / std::max(curCost, 1e-12);
                curCost = newCost;
                lambda = std::max(lambda / 3.0, 1e-9);
                return rel > 1e-8;
            }
            lambda *= 4.0;
            if (lambda > 1e10) return false;
        }
        return false;
    }
};

}  // namespace

// =============================================================================== API
std::vector<Pose> bundleAdjustPoses(const std::vector<FrameInput>& frames, const BAOptions& opt,
                                    const ProgressFn& progress, BAStats* stats) {
    auto t0 = std::chrono::steady_clock::now();
    auto elapsed = [&]() { return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count(); };
    auto report = [&](float p, const std::string& m) { if (progress) progress(p, m); };
    const int n = (int)frames.size();
    std::vector<Cam> cams(n);
    std::vector<Pose> out(n);
    for (int i = 0; i < n; ++i) {
        const auto& t = frames[i].transform;
        Matx33d M;
        for (int r = 0; r < 3; ++r)
            for (int c = 0; c < 3; ++c) M(r, c) = t[c * 4 + r];
        cams[i].R0 = orthonormalize(M);
        cams[i].p0 = Vec3d(t[12], t[13], t[14]);
        out[i].R = cv::Matx33f(cams[i].R0);
        out[i].p = cv::Vec3f((float)t[12], (float)t[13], (float)t[14]);
    }
    if (stats) { *stats = BAStats(); stats->frameCount = n; stats->minCameraObservations = kMinObsPerCamera; }
    if (n < 2) return out;

    // Sensor poses carry no translation (all positions equal, typically 0). Seed them with the
    // pivot model p = R·(0, 0, −L): the phone is held ~L in front of the body, so consecutive
    // 30° shots have a ~10 cm baseline. Only an initialisation — the prior on p is loose and
    // the LM recovers the real motion from the tracks (verified against ARKit captures).
    bool sensorNeedsTranslation = false;
    if (opt.relRotSigmaDeg > 0) {
        double spread = 0;
        for (int i = 1; i < n; ++i) spread = std::max(spread, cv::norm(cams[i].p0 - cams[0].p0));
        if (spread < 0.01) {
            sensorNeedsTranslation = true;
            const double L = 0.2;
            for (int i = 0; i < n; ++i) {
                cams[i].p0 = cams[i].R0 * Vec3d(0, 0, -L);
                // This is a solver seed, not measured motion. Keep `out` at the input pose
                // so an unsuccessful solve cannot return the invented 20 cm baseline.
            }
            report(0.0f, "BA: pivot init (no translation in the poses)");
        }
    }

    // ---------------------------------------------------------------- 1. features
    report(0.0f, "BA: SIFT features");
    const int width = std::max(64, opt.width);
    std::mutex mtx;
    int done = 0;
    // At most 3 frames in flight: a 12-MP SIFT pyramid is ~180 MB per frame, so an unbounded
    // parallel_for_ would peak at 1.4 GB on an 8-core phone (jetsam on 4 GB devices); 3 stripes
    // measured 0.6 GB for +1 s.
    cv::parallel_for_(cv::Range(0, n), [&](const cv::Range& rg) {
        cv::Ptr<cv::SIFT> sift = cv::SIFT::create(6000, 3, 0.02);   // 0.02: ceilings/plain walls still yield some features
        for (int i = rg.start; i < rg.end; ++i) {
            cv::Mat img = imreadForWidth(frames[i].path, width, frames[i].imageWidth, false);
            Cam& c = cams[i];
            if (img.empty()) continue;
            // intrinsics scale from the *full* frame size (metadata), not the reduced decode
            const int w0 = frames[i].imageWidth > 0 ? frames[i].imageWidth : img.cols;
            const int h0 = frames[i].imageHeight > 0 ? frames[i].imageHeight : img.rows;
            int h = (int)std::lround((double)h0 * width / w0);
            cv::Mat small;
            if (img.cols == width && img.rows == h) small = img;
            else cv::resize(img, small, cv::Size(width, h), 0, 0, cv::INTER_AREA);
            img.release();
            std::vector<cv::KeyPoint> kp;
            sift->detectAndCompute(small, cv::noArray(), kp, c.desc);
            c.kps.resize(kp.size());
            for (size_t k = 0; k < kp.size(); ++k) c.kps[k] = kp[k].pt;
            double iw = w0;
            double ih = h0;
            c.fx = frames[i].fx * width / iw;
            c.fy = frames[i].fy * h / ih;
            c.cx = frames[i].cx * width / iw;
            c.cy = frames[i].cy * h / ih;
            std::lock_guard<std::mutex> lk(mtx);
            ++done;
            report(0.35f * done / n, "BA: SIFT features");
        }
    }, std::min(n, 3));

    // ---------------------------------------------------------------- 2. pairs
    report(0.35f, "BA: matching pairs");
    std::set<std::pair<int, int>> keys;
    for (int i = 0; i < n; ++i)
        for (int j : selectNeighbours(cams, i, opt.neighbours, opt.maxAngleDeg, 0.03)) {
            if (cams[i].desc.empty() || cams[j].desc.empty()) continue;
            keys.insert({std::min(i, j), std::max(i, j)});
        }
    std::vector<std::pair<int, int>> pairs(keys.begin(), keys.end());
    // Approximate NN (randomized KD-trees) instead of brute force: 6000×6000×128 per pair is
    // ~5 GFLOP — the single largest BA cost on a phone. One index per camera, built once.
    std::vector<cv::Ptr<cv::flann::Index>> flannIdx(n);
    cv::parallel_for_(cv::Range(0, n), [&](const cv::Range& rg) {
        for (int i = rg.start; i < rg.end; ++i)
            if (!cams[i].desc.empty()) {
                ScopedMatchingRng rng(opt.stableMatching, 0xffffffffULL + uint64_t(i) * 7919ULL);
                flannIdx[i] = cv::makePtr<cv::flann::Index>(cams[i].desc, cv::flann::KDTreeIndexParams(4), cvflann::FLANN_DIST_L2);
            }
    });
    const int minInliers = 25;       // for a hypothesis whose rotation may differ from the prior
    const int minInliersKnownR = 14; // when the essential geometry agrees with the prior rotation (< 8°):
                                     // with R known, t has 2 DoF, so a dozen inliers already pin it
                                     // (ceiling frames: 30–60 matches, 15–25 inliers)
    struct PairResult {
        bool ok = false;
        int inliers = 0;
        double dRdeg = 0;           // image-estimated vs prior relative rotation
        Vec3d displacementInJ;     // i → j baseline, expressed in camera j axes
        bool positionOK = false;
        Matx33d RjiEst;             // R_jᵀ R_i from the essential matrix (ARKit/world axes)
        std::vector<std::pair<int, int>> corr;  // (kp index in i, kp index in j)
    };
    std::vector<PairResult> results(pairs.size());
    const Matx33d Sflip(1, 0, 0, 0, -1, 0, 0, 0, -1);  // ARKit cam axes ↔ pinhole axes
    int pairsDone = 0;
    // knn matches are computed once and reused if the pair loop runs a second time
    std::vector<std::vector<cv::DMatch>> goodMatches(pairs.size());
    std::vector<char> matched(pairs.size(), 0);
    auto runPairs = [&](bool onlyFailed) {
        cv::parallel_for_(cv::Range(0, (int)pairs.size()), [&](const cv::Range& rg) {
            for (int pi = rg.start; pi < rg.end; ++pi) {
                ScopedMatchingRng rng(opt.stableMatching, 1234567ULL + uint64_t(pi) * 7919ULL);
                PairResult& pr = results[pi];
                if (onlyFailed && pr.ok) continue;
                const int i = pairs[pi].first, j = pairs[pi].second;
                std::vector<cv::DMatch>& good = goodMatches[pi];
                if (!matched[pi]) {
                    if (flannIdx[j]) {
                        cv::Mat idx, dist;   // squared L2 distances
                        flannIdx[j]->knnSearch(cams[i].desc, idx, dist, 2, cv::flann::SearchParams(48));
                        for (int q = 0; q < idx.rows; ++q) {
                            const float d0 = std::sqrt(std::max(dist.at<float>(q, 0), 0.f));
                            const float d1 = std::sqrt(std::max(dist.at<float>(q, 1), 0.f));
                            if (idx.at<int>(q, 1) >= 0 && d0 < 0.75f * d1) good.emplace_back(q, idx.at<int>(q, 0), d0);
                        }
                    }
                    matched[pi] = 1;
                    if (debugOn() && (int)good.size() < minInliers)
                        std::fprintf(stderr, "pair %d,%d: skip (%zu ratio-test matches)\n", i, j, good.size());
                }
                if ((int)good.size() >= minInliers) {
                    std::vector<cv::Point2d> xa(good.size()), xb(good.size());
                    for (size_t k = 0; k < good.size(); ++k) {
                        const cv::Point2f& a = cams[i].kps[good[k].queryIdx];
                        const cv::Point2f& b = cams[j].kps[good[k].trainIdx];
                        xa[k] = cv::Point2d((a.x - cams[i].cx) / cams[i].fx, (a.y - cams[i].cy) / cams[i].fy);
                        xb[k] = cv::Point2d((b.x - cams[j].cx) / cams[j].fx, (b.y - cams[j].cy) / cams[j].fy);
                    }
                    Matx33d E;
                    std::vector<char> inl;
                    // prior relative pose i→j in pinhole axes: X_j' = (S R_ji S) X_i' + S t_ji
                    Matx33d Rji0 = cams[j].R0.t() * cams[i].R0;
                    Vec3d tji0 = cams[j].R0.t() * (cams[i].p0 - cams[j].p0);
                    int cnt = estimateEssential(xa, xb, 1.5 / cams[i].fx, Sflip * Rji0 * Sflip, Sflip * tji0,
                                                1234567u + (uint64_t)pi * 7919u, E, inl);
                    if (debugOn() && cnt < minInliersKnownR)
                        std::fprintf(stderr, "pair %d,%d: skip (%d inliers of %zu matches)\n", i, j, cnt, good.size());
                    if (cnt >= minInliersKnownR) {
                        // sanity: the image-estimated relative rotation must roughly agree with the prior
                        Matx33d R1, R2;
                        rotationsFromEssential(E, R1, R2);
                        Matx33d Rji = cams[j].R0.t() * cams[i].R0;
                        Matx33d R1w = Sflip * R1 * Sflip, R2w = Sflip * R2 * Sflip;
                        double d1 = angleDeg(R1w, Rji), d2 = angleDeg(R2w, Rji);
                        double dR = std::min(d1, d2);
                        const bool accept = cnt >= minInliers ? dR <= 25.0 : dR <= 8.0;
                        if (debugOn())
                            std::fprintf(stderr, "pair %d,%d: %s (%d inliers of %zu matches, dR %.1f deg)\n", i, j,
                                         accept ? "ok" : "skip", cnt, good.size(), dR);
                        if (accept) {
                            pr.ok = true;
                            pr.inliers = cnt;
                            pr.dRdeg = dR;
                            pr.RjiEst = d1 <= d2 ? R1w : R2w;
                            // E = [t]x R determines the baseline direction; choose its sign
                            // by requiring matched points to lie in front of both cameras.
                            cv::Mat ew, eu, evt;
                            cv::SVD::compute(cv::Mat(E), ew, eu, evt);
                            Vec3d t(eu.at<double>(0, 2), eu.at<double>(1, 2), eu.at<double>(2, 2));
                            Matx33d rel = Sflip * pr.RjiEst * Sflip;
                            int positive = 0, negative = 0;
                            std::vector<double> parallaxes;
                            for (size_t k = 0; k < xa.size(); ++k) if (inl[k]) {
                                Vec3d a = rel * Vec3d(xa[k].x, xa[k].y, 1), b(xb[k].x, xb[k].y, 1);
                                a *= 1 / cv::norm(a); b *= 1 / cv::norm(b);
                                const double ab = a.dot(b), den = 1 - ab * ab;
                                if (den < 1e-7) continue;
                                const double at = a.dot(t), bt = b.dot(t);
                                const double da = (ab * bt - at) / den, db = (bt - ab * at) / den;
                                positive += da > 0 && db > 0;
                                negative += da < 0 && db < 0;
                                parallaxes.push_back(std::acos(std::clamp(ab, -1.0, 1.0)) * 180 / M_PI);
                            }
                            if (negative > positive) t = -t;
                            pr.displacementInJ = -(Sflip * t);
                            if (!parallaxes.empty()) {
                                std::sort(parallaxes.begin(), parallaxes.end());
                                pr.positionOK = std::max(positive, negative) >= cnt * 0.7 &&
                                    parallaxes[parallaxes.size() / 2] > 0.3 && dR < 8;
                            }
                            pr.corr.clear();
                            for (size_t k = 0; k < good.size(); ++k)
                                if (inl[k]) pr.corr.push_back({good[k].queryIdx, good[k].trainIdx});
                        }
                    }
                }
                std::lock_guard<std::mutex> lk(mtx);
                ++pairsDone;
                report(0.35f + 0.4f * pairsDone / std::max<int>(1, (int)pairs.size()), "BA: matching pairs");
            }
        });
    };
    runPairs(false);

    // -------------------------------------------------- 2b. rotation-only graph (opt-in)
    // Independent of the joint solve below: same features, but matched reciprocally and fitted
    // as a pure rotation. Nothing here changes cams[].R0, the pairs, the gates or the LM.
    if (opt.rotationGraph && stats) {
        const double t0rg = elapsed();
        report(0.75f, "BA: rotation graph");
        std::vector<Matx33d> R0(n);
        for (int c = 0; c < n; ++c) R0[c] = cams[c].R0;
        // One keypoint per cell, so a densely textured corner cannot outvote the rest of the
        // overlap. 12 px at the 2000 px working width the offline study used.
        const double cellPx = std::max(3.0, width / 160.0);
        std::vector<RotationEdge> edges, soft;
        std::vector<std::vector<cv::DMatch>> reverse(pairs.size());
        cv::parallel_for_(cv::Range(0, (int)pairs.size()), [&](const cv::Range& rg) {
            for (int pi = rg.start; pi < rg.end; ++pi) {
                const int i = pairs[pi].first;
                if (!flannIdx[i] || cams[pairs[pi].second].desc.empty()) continue;
                ScopedMatchingRng rng(opt.stableMatching, 0x5eedULL + uint64_t(pi) * 7919ULL);
                cv::Mat idx, dist;
                flannIdx[i]->knnSearch(cams[pairs[pi].second].desc, idx, dist, 2, cv::flann::SearchParams(48));
                for (int q = 0; q < idx.rows; ++q) {
                    const float d0 = std::sqrt(std::max(dist.at<float>(q, 0), 0.f));
                    const float d1 = std::sqrt(std::max(dist.at<float>(q, 1), 0.f));
                    if (idx.at<int>(q, 1) >= 0 && d0 < 0.7f * d1)
                        reverse[pi].emplace_back(q, idx.at<int>(q, 0), d0);
                }
            }
        });
        for (size_t pi = 0; pi < pairs.size(); ++pi) {
            const int i = pairs[pi].first, j = pairs[pi].second;
            RotationEdge e;
            e.i = i;
            e.j = j;
            e.Rji = R0[j].t() * R0[i];
            std::unordered_map<int, int> back;   // keypoint in j → its best keypoint in i
            for (const auto& m : reverse[pi]) back[m.queryIdx] = m.trainIdx;
            std::vector<cv::DMatch> forward = goodMatches[pi];
            std::sort(forward.begin(), forward.end(),
                      [](const cv::DMatch& x, const cv::DMatch& y) { return x.distance < y.distance; });
            std::set<std::pair<int, int>> cells;
            std::vector<Vec3d> A, B;
            for (const auto& m : forward) {
                auto it = back.find(m.trainIdx);
                if (it == back.end() || it->second != m.queryIdx) continue;   // not reciprocal
                const cv::Point2f& pa = cams[i].kps[m.queryIdx];
                const cv::Point2f& pb = cams[j].kps[m.trainIdx];
                Vec3d a((pa.x - cams[i].cx) / cams[i].fx, -(pa.y - cams[i].cy) / cams[i].fy, -1);
                Vec3d b((pb.x - cams[j].cx) / cams[j].fx, -(pb.y - cams[j].cy) / cams[j].fy, -1);
                a *= 1.0 / cv::norm(a);
                b *= 1.0 / cv::norm(b);
                // A match the sensor pose cannot explain at all is a mismatch, not a correction.
                if (angleBetweenDeg(R0[i] * a, R0[j] * b) > 15.0) continue;
                const std::pair<int, int> cell{int(pa.x / cellPx), int(pa.y / cellPx)};
                if (!cells.insert(cell).second) continue;
                A.push_back(a);
                B.push_back(b);
            }
            const int kMinRotMatches = 12;
            const int kMinRotInliers = std::max(10, opt.rotationGraphMinInliers);
            Matx33d R = e.Rji;
            int inliers = 0;
            if ((int)A.size() >= kMinRotMatches)
                inliers = rotationConsensus(A, B, e.Rji, 721 + uint64_t(i) * 31 + j, R,
                                            std::max(0.1f, opt.rotationGraphThresholdDeg));
            if (inliers < kMinRotInliers) {
                soft.push_back(e);   // overlapping, but no rotation evidence of its own
                continue;
            }
            for (size_t k = 0; k < A.size(); ++k)
                if (angleBetweenDeg(R * A[k], B[k]) < opt.rotationGraphThresholdDeg) { e.a.push_back(A[k]); e.b.push_back(B[k]); }
            e.Rji = R;
            e.weight = std::min<size_t>(e.a.size(), 40);
            edges.push_back(std::move(e));
        }
        const std::vector<Matx33d> Rg = solveRotationGraph(R0, edges, soft, opt.rotationGraphPriorWeight,
                                                          opt.rotationGraphThresholdDeg);
        std::vector<char> supported(n, 0);
        for (const auto& e : edges) { supported[e.i] = 1; supported[e.j] = 1; }
        stats->rotationGraphRotations.resize(n);
        double moved = 0;
        for (int c = 0; c < n; ++c) {
            stats->rotationGraphRotations[c] = cv::Matx33f(Rg[c]);
            moved = std::max(moved, angleDeg(Rg[c], R0[c]));
            stats->rotationGraphSupportedCameras += supported[c] ? 1 : 0;
        }
        stats->rotationGraphPairs = (int)edges.size();
        if (debugOn()) {
            std::fprintf(stderr, "rotation graph: %zu edges, %d/%d cameras supported, max %.2f deg, %.2fs\n",
                         edges.size(), stats->rotationGraphSupportedCameras, n, moved, elapsed() - t0rg);
            for (const auto& e : edges)
                std::fprintf(stderr, "  rg edge %d,%d: %zu inliers, %.2f deg from sensor\n", e.i, e.j, e.a.size(),
                             angleDeg(e.Rji, R0[e.j].t() * R0[e.i]));
            for (int c = 0; c < n; ++c) {
                std::fprintf(stderr, "  rg cam %d: %s, %.2f deg\n", c, supported[c] ? "solved" : "FOLLOWS",
                             angleDeg(Rg[c], R0[c]));
                std::fprintf(stderr, "  rgR %d", c);
                for (int r = 0; r < 3; ++r) for (int k = 0; k < 3; ++k) std::fprintf(stderr, " %.9f", Rg[c](r, k));
                std::fprintf(stderr, "\n");
            }
        }
    }

    // Sensor poses (gyro fusion) can be several degrees off the true relative rotation — badly
    // timed samples, magnetometer-free heading drift. The essential matrices of the accepted
    // pairs carry the true relative rotations; when they disagree with the prior by more than
    // 3° (median), average them into the rotation prior (Gauss-Seidel chordal mean, first camera
    // anchored, prior kept as a weak vote), re-run the rejected pairs with the corrected prior
    // and keep the corrected rotations as the LM start / absolute prior.
    if (opt.relRotSigmaDeg > 0) {
        std::vector<double> dRs;
        for (const auto& pr : results) if (pr.ok) dRs.push_back(pr.dRdeg);
        double medDR = 0;
        if (!dRs.empty()) { std::nth_element(dRs.begin(), dRs.begin() + dRs.size() / 2, dRs.end()); medDR = dRs[dRs.size() / 2]; }
        if (medDR > 3.0) {
            std::vector<Matx33d> Rp(n);
            for (int c = 0; c < n; ++c) Rp[c] = cams[c].R0;
            std::vector<Matx33d> Rr = Rp;
            const double priorW = 15.0;   // in "inliers"
            for (int sweep = 0; sweep < 20; ++sweep) {
                for (int c = 1; c < n; ++c) {
                    Matx33d M = priorW * Rp[c];
                    for (size_t pi = 0; pi < pairs.size(); ++pi) {
                        const PairResult& pr = results[pi];
                        if (!pr.ok) continue;
                        const int i = pairs[pi].first, j = pairs[pi].second;
                        // RjiEst = R_jᵀ R_i  →  R_i = R_j RjiEst,  R_j = R_i RjiEstᵀ
                        if (i == c) M += (double)pr.inliers * (Rr[j] * pr.RjiEst);
                        else if (j == c) M += (double)pr.inliers * (Rr[i] * pr.RjiEst.t());
                    }
                    Rr[c] = orthonormalize(M);
                }
            }
            double moved = 0;
            for (int c = 0; c < n; ++c) moved = std::max(moved, angleDeg(Rr[c], Rp[c]));
            for (int c = 0; c < n; ++c) cams[c].R0 = Rr[c];
            if (debugOn()) std::fprintf(stderr, "rotation averaging: median pair dR %.1f deg → prior corrected (max %.1f deg), re-running rejected pairs\n", medDR, moved);
            {
                char buf[96];
                std::snprintf(buf, sizeof buf, "BA: rotations corrected by up to %.0f°", moved);
                report(0.6f, buf);
            }
            pairsDone = 0;
            runPairs(true);
        }
    }

    if (opt.sensorTranslationInit && sensorNeedsTranslation) {
        // Fit a position graph before triangulation. An assumed body pivot can place
        // real correspondences behind the camera and discard all tracks of a view.
        int edges = 0;
        for (const auto& pr : results) edges += pr.ok && pr.positionOK;
        cv::Mat A = cv::Mat::zeros(3 * (edges + n), 3 * n, CV_64F);
        cv::Mat b = cv::Mat::zeros(A.rows, 1, CV_64F);
        int row = 0;
        for (size_t k = 0; k < pairs.size(); ++k) {
            const auto& pr = results[k];
            if (!pr.ok || !pr.positionOK) continue;
            const int i = pairs[k].first, j = pairs[k].second;
            // Rotation averaging above may have updated R0 since this pair was matched.
            const Vec3d d = cams[j].R0 * pr.displacementInJ;
            const Matx33d W = Matx33d::eye() - 0.95 * (d * d.t());
            const double length = std::clamp(cv::norm(cams[j].p0 - cams[i].p0), 0.05, 0.3);
            const double weight = std::sqrt(std::min(pr.inliers, 100) / 50.0);
            for (int r = 0; r < 3; ++r) {
                for (int c = 0; c < 3; ++c) {
                    A.at<double>(row + r, 3 * i + c) = -weight * W(r, c);
                    A.at<double>(row + r, 3 * j + c) = weight * W(r, c);
                }
                b.at<double>(row + r) = weight * 0.05 * d[r] * length;
            }
            row += 3;
        }
        for (int i = 0; i < n; ++i) for (int r = 0; r < 3; ++r) {
            A.at<double>(row, 3 * i + r) = 0.02;
            b.at<double>(row++) = 0.02 * cams[i].p0[r];
        }
        cv::Mat x;
        if (edges >= n && cv::solve(A, b, x, cv::DECOMP_SVD)) {
            for (int i = 0; i < n; ++i) {
                cams[i].p0 = Vec3d(x.at<double>(3 * i), x.at<double>(3 * i + 1), x.at<double>(3 * i + 2));
                if (debugOn()) std::fprintf(stderr, "position init %d: %.3f %.3f %.3f\n", i, cams[i].p0[0], cams[i].p0[1], cams[i].p0[2]);
            }
        }
    }

    // ---------------------------------------------------------------- 3. tracks
    report(0.76f, "BA: tracks");
    UnionFind uf;
    auto key = [](int cam, int idx) { return (int64_t)cam * (int64_t)(1 << 24) + idx; };
    int nPairs = 0;
    for (size_t pi = 0; pi < pairs.size(); ++pi) {
        if (!results[pi].ok) continue;
        ++nPairs;
        if (stats) stats->acceptedPairEdges.push_back({pairs[pi].first, pairs[pi].second});
        for (const auto& c : results[pi].corr) uf.unite(key(pairs[pi].first, c.first), key(pairs[pi].second, c.second));
    }
    std::unordered_map<int64_t, std::vector<int64_t>> groups;
    {
        std::vector<int64_t> all;
        all.reserve(uf.parent.size());
        for (const auto& kv : uf.parent) all.push_back(kv.first);
        for (int64_t a : all) groups[uf.find(a)].push_back(a);
    }
    std::vector<std::vector<std::pair<int, int>>> tracks;  // (cam, kp)
    for (auto& kv : groups) {
        std::vector<int64_t>& mem = kv.second;
        mem.push_back(kv.first);
        std::sort(mem.begin(), mem.end());
        mem.erase(std::unique(mem.begin(), mem.end()), mem.end());
        if (mem.size() < 2) continue;
        std::vector<std::pair<int, int>> tr;
        std::set<int> camSet;
        for (int64_t m : mem) {
            int cam = (int)(m >> 24), idx = (int)(m & ((1 << 24) - 1));
            camSet.insert(cam);
            tr.push_back({cam, idx});
        }
        if (camSet.size() != tr.size()) continue;
        tracks.push_back(std::move(tr));
    }
    // deterministic order (unordered_map iteration order is arbitrary)
    std::sort(tracks.begin(), tracks.end());

    // ---------------------------------------------------------------- 4. triangulation
    Problem prob;
    prob.n = n;
    prob.cams = &cams;
    prob.posSigma = std::max(1e-4, (double)opt.posSigmaM);              // 0 would make the prior NaN
    prob.rotSigma = std::max(1e-4, opt.rotSigmaDeg * M_PI / 180.0);
    prob.rotSigmaV = Vec3d(prob.rotSigma, opt.yawSigmaDeg > 0 ? std::max(1e-4, opt.yawSigmaDeg * M_PI / 180.0) : prob.rotSigma, prob.rotSigma);
    prob.relRotSigma = opt.relRotSigmaDeg > 0 ? std::max(1e-4, opt.relRotSigmaDeg * M_PI / 180.0) : 0.0;
    prob.Q.resize(std::max(0, n - 1));
    // (after rotation averaging R0 is the image-corrected prior; the chain then acts as a
    //  smoothness prior around it — the sensor's own relative rotations were unreliable)
    for (int c = 0; c + 1 < n; ++c) prob.Q[c] = cams[c + 1].R0 * cams[c].R0.t();
    prob.R.resize(n);
    prob.p.resize(n);
    prob.dth.assign(n, Vec3d(0, 0, 0));
    prob.fixedCam.assign(n, 0);
    for (int c = 0; c < n; ++c) { prob.R[c] = cams[c].R0; prob.p[c] = cams[c].p0; }
    for (const auto& tr : tracks) {
        cv::Mat A((int)tr.size() * 2, 4, CV_64F);
        int r = 0;
        for (const auto& ci : tr) {
            const Cam& c = cams[ci.first];
            const cv::Point2f& uv = c.kps[ci.second];
            Matx33d Rt = c.R0.t();
            Vec3d tcw = -(Rt * c.p0);
            double x = (uv.x - c.cx) / c.fx, y = -(uv.y - c.cy) / c.fy;
            for (int k = 0; k < 3; ++k) {
                A.at<double>(r, k) = x * Rt(2, k) + Rt(0, k);
                A.at<double>(r + 1, k) = y * Rt(2, k) + Rt(1, k);
            }
            A.at<double>(r, 3) = x * tcw[2] + tcw[0];
            A.at<double>(r + 1, 3) = y * tcw[2] + tcw[1];
            r += 2;
        }
        cv::Mat w, u, vt;
        cv::SVD::compute(A, w, u, vt, cv::SVD::FULL_UV);
        const double* Xh = vt.ptr<double>(3);
        if (std::fabs(Xh[3]) < 1e-9) continue;
        Vec3d X(Xh[0] / Xh[3], Xh[1] / Xh[3], Xh[2] / Xh[3]);
        bool ok = true;
        std::vector<double> errs;
        for (const auto& ci : tr) {
            const Cam& c = cams[ci.first];
            Vec3d Xc = c.R0.t() * (X - c.p0);
            double z = -Xc[2];
            if (z < 0.3 || z > 25) { ok = false; break; }
            double u_ = c.fx * Xc[0] / z + c.cx, v_ = c.cy - c.fy * Xc[1] / z;
            const cv::Point2f& uv = c.kps[ci.second];
            errs.push_back(std::hypot(u_ - uv.x, v_ - uv.y));
        }
        if (!ok) continue;
        size_t m = errs.size() / 2;
        std::nth_element(errs.begin(), errs.begin() + m, errs.end());
        double med = errs[m];
        if (errs.size() % 2 == 0) {
            double lo = *std::max_element(errs.begin(), errs.begin() + m);
            med = 0.5 * (lo + errs[m]);
        }
        if (med > 25) continue;
        int pid = (int)prob.X.size();
        prob.X.push_back(X);
        prob.ptObs.emplace_back();
        for (const auto& ci : tr) {
            const cv::Point2f& uv = cams[ci.first].kps[ci.second];
            prob.ptObs[pid].push_back((int)prob.obs.size());
            prob.obs.push_back({ci.first, pid, (double)uv.x, (double)uv.y});
        }
    }
    const int npts = (int)prob.X.size(), nobs = (int)prob.obs.size();
    {
        char buf[128];
        std::snprintf(buf, sizeof buf, "BA: %d pairs, %zu tracks, %d points, %d observations", nPairs, tracks.size(), npts, nobs);
        report(0.8f, buf);
    }
    if (stats) {
        stats->points = npts; stats->observations = nobs;
        stats->featureTracks = (int)tracks.size();
        std::set<std::array<int, 2>> edges;
        for (const auto& track : prob.ptObs) {
            for (size_t i = 0; i < track.size(); ++i) for (size_t j = i + 1; j < track.size(); ++j) {
                int a = prob.obs[track[i]].cam, b = prob.obs[track[j]].cam;
                edges.insert({std::min(a, b), std::max(a, b)});
            }
        }
        stats->triangulatedEdges.assign(edges.begin(), edges.end());
    }
    // A camera with only a handful of observations is under-determined in 6 DoF and, the ARKit
    // prior being Cauchy-robustified, a single observation could drag it by a degree: hold such
    // cameras at their ARKit pose (their observations still constrain the points).
    {
        std::vector<int> perCam(n, 0);
        for (const Obs& o : prob.obs) ++perCam[o.cam];
        for (int c = 0; c < n; ++c) prob.fixedCam[c] = perCam[c] < kMinObsPerCamera;
        if (stats) {
            stats->cameraObservations = perCam;
            for (int c = 0; c < n; ++c) stats->constrainedCameras += !prob.fixedCam[c];
        }
        // With the relative-rotation chain (sensor poses) a weak camera is not frozen: its rotation
        // is carried by the chain + the absolute tilt prior, its position by the pivot fill below.
        if (prob.relRotSigma > 0)
            for (int c = 0; c < n; ++c) prob.fixedCam[c] = 0;
    }
    if (npts == 0) {
        if (stats) stats->seconds = elapsed();
        report(1.0f, "BA: no points, keeping ARKit poses");
        return out;
    }

    // ---------------------------------------------------------------- 5. LM
    double medBefore = prob.medianReproj();
    if (stats) stats->medianBeforePx = (float)medBefore;
    double lambda = 1e-3;
    double curCost = prob.cost(prob.R, prob.p, prob.dth, prob.X);
    if (debugOn()) {
        std::vector<int> perCam(n, 0);
        for (const Obs& o : prob.obs) ++perCam[o.cam];
        std::fprintf(stderr, "options: width %d posSigma %.4f rotSigma %.4f/%.4f(yaw) rad relRotSigma %.4f rad neighbours %d maxAngle %.1f iters %d\n", width,
                     prob.posSigma, prob.rotSigmaV[0], prob.rotSigmaV[1], prob.relRotSigma, opt.neighbours, opt.maxAngleDeg, opt.iterations);
        double sRep = 0, sPri = 0;
        int nanObs = 0, nanCam = 0;
        for (const Obs& o : prob.obs) {
            double ru, rv;
            prob.residual(o, prob.R[o.cam], prob.p[o.cam], prob.X[o.pt], ru, rv);
            double v = prob.rho(ru) + prob.rho(rv);
            if (std::isnan(v)) ++nanObs; else sRep += v;
        }
        for (int c = 0; c < n; ++c) {
            Vec3d dp = (prob.p[c] - cams[c].p0) / prob.posSigma;
            Vec3d dr(prob.dth[c][0] / prob.rotSigmaV[0], prob.dth[c][1] / prob.rotSigmaV[1], prob.dth[c][2] / prob.rotSigmaV[2]);
            double v = 0;
            for (int k = 0; k < 3; ++k) v += prob.rho(dp[k]) + prob.rho(dr[k]);
            if (std::isnan(v)) { ++nanCam; std::fprintf(stderr, "  cam %d prior NaN: p (%g %g %g) p0 (%g %g %g)\n", c, prob.p[c][0], prob.p[c][1], prob.p[c][2], cams[c].p0[0], cams[c].p0[1], cams[c].p0[2]); }
            else sPri += v;
        }
        std::fprintf(stderr, "cost split: reproj %.1f (nan obs %d) prior %.1f (nan cams %d)\n", sRep, nanObs, sPri, nanCam);
        std::fprintf(stderr, "%d pairs, %zu tracks, %d points, %d observations\n", nPairs, tracks.size(), npts, nobs);
        for (int c = 0; c < n; ++c) std::fprintf(stderr, "cam %2d: obs %d\n", c, perCam[c]);
        std::fprintf(stderr, "LM start cost %.1f median %.2f px\n", curCost, medBefore);
    }
    for (int it = 0; it < opt.iterations; ++it) {
        bool progressed = prob.lmStep(lambda, curCost);
        bool aligned = prob.gaugeAlign(curCost);
        if (debugOn()) std::fprintf(stderr, "LM it %2d: cost %.1f lambda %.2e median %.2f px%s\n", it + 1, curCost, lambda, prob.medianReproj(), aligned ? " (gauge)" : "");
        char buf[96];
        std::snprintf(buf, sizeof buf, "BA: LM iteration %d/%d", it + 1, opt.iterations);
        report(0.8f + 0.2f * (it + 1) / opt.iterations, buf);
        if (!progressed) break;
    }
    double medAfter = prob.medianReproj();
    if (stats) {
        stats->optimized = true;
        for (const auto& p : prob.p) stats->optimizedPositions.emplace_back(p);
    }
    {
        std::vector<double> depths;
        for (const Obs& o : prob.obs) {
            const Vec3d q = prob.R[o.cam].t() * (prob.X[o.pt] - prob.p[o.cam]);
            if (-q[2] > 0) depths.push_back(-q[2]);
        }
        std::sort(depths.begin(), depths.end());
        if (stats && !depths.empty()) {
            stats->depth10 = depths[depths.size()/10];
            stats->medianDepth = depths[depths.size()/2];
            stats->depth95 = depths[depths.size()*19/20];
        }
        if (debugOn() && !depths.empty()) std::fprintf(stderr, "BA depth q05 %.3f q10 %.3f median %.3f q90 %.3f q95 %.3f\n",
            depths[depths.size()/20], depths[depths.size()/10], depths[depths.size()/2], depths[depths.size()*9/10], depths[depths.size()*19/20]);
    }
    if (prob.relRotSigma > 0) {
        // Pivot fill for weak cameras (sensor poses only). The phone moves with the body, so
        // p ≈ c + R·d (c = body pivot, d = lever arm in camera axes) describes the well-observed
        // cameras to ~10 cm; a camera with too few tracks gets that instead of the raw prior.
        std::vector<int> perCam(n, 0);
        for (const Obs& o : prob.obs) ++perCam[o.cam];
        std::vector<int> strong;
        for (int c = 0; c < n; ++c) if (perCam[c] >= kMinObsPerCamera) strong.push_back(c);
        if (strong.size() >= 6 && (int)strong.size() < n) {
            // least squares in (c, d):  p_i = c + R_i d  →  [I  R_i] [c; d] = p_i
            cv::Mat A((int)strong.size() * 3, 6, CV_64F), bvec((int)strong.size() * 3, 1, CV_64F);
            for (size_t k = 0; k < strong.size(); ++k) {
                const Matx33d& Rk = prob.R[strong[k]];
                for (int r = 0; r < 3; ++r) {
                    for (int q = 0; q < 3; ++q) {
                        A.at<double>(3 * k + r, q) = (r == q) ? 1.0 : 0.0;
                        A.at<double>(3 * k + r, 3 + q) = Rk(r, q);
                    }
                    bvec.at<double>(3 * k + r, 0) = prob.p[strong[k]][r];
                }
            }
            cv::Mat x;
            if (cv::solve(A, bvec, x, cv::DECOMP_SVD)) {
                Vec3d cpiv(x.at<double>(0), x.at<double>(1), x.at<double>(2));
                Vec3d dlev(x.at<double>(3), x.at<double>(4), x.at<double>(5));
                double resid = 0;
                for (int c : strong) resid += cv::norm(prob.p[c] - (cpiv + prob.R[c] * dlev));
                resid /= strong.size();
                int filled = 0;
                for (int c = 0; c < n; ++c)
                    if (perCam[c] < kMinObsPerCamera) { prob.p[c] = cpiv + prob.R[c] * dlev; ++filled; }
                if (debugOn())
                    std::fprintf(stderr, "pivot fill: lever (%.2f %.2f %.2f) m, mean residual %.1f cm, %d weak cameras filled\n",
                                 dlev[0], dlev[1], dlev[2], resid * 100, filled);
            }
        }
    }
    for (int c = 0; c < n; ++c) {
        out[c].R = cv::Matx33f(prob.R[c]);
        out[c].p = cv::Vec3f((float)prob.p[c][0], (float)prob.p[c][1], (float)prob.p[c][2]);
    }
    if (stats) {
        stats->medianAfterPx = (float)medAfter;
        stats->seconds = elapsed();
    }
    report(1.0f, "BA: done");
    return out;
}

}  // namespace uy360
