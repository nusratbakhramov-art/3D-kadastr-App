// Plane-sweep multi-view stereo — C++ port of server/mvs_depth.py. See uy360_mvs.hpp.
//
// Layout / memory (per frame, W×H×D = 1008×756×64):
//   vol     D × (H·W) uint8   guided-filtered cost slices, plane-major      49 MB
//   nvBits  D × (H·⌈W/8⌉)     "≥ minViews neighbours saw it" bitmask         6 MB
//   bt      (H·W) × D uint8   SGM bottom→top direction (the only stored one) 49 MB
// The other three SGM directions are streamed: left/right per row, top→bottom with a
// one-row state, summed block-wise and consumed by the winner-take-all immediately.
// The sweep runs the planes sequentially and parallelises over horizontal bands, so
// the per-thread scratch is a few band-sized images, not full frames.
#include "uy360_mvs.hpp"

#include <opencv2/core/utility.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <numeric>

namespace uy360 {
namespace {

constexpr int kCostScale = 100;       // cost 0..2 → 0..200
constexpr uint8_t kUnseen = 255;      // no neighbour sees the pixel at this plane
constexpr int kUnseenSgm = 100;       // SGM treats unseen as a flat 1.0
constexpr float kSnapTol = 0.12f;     // plane prior tolerance (1/m), as mvs_depth.py --snap-tol

struct Cam {
    double fx = 0, fy = 0, cx = 0, cy = 0;  // intrinsics at the working resolution
    cv::Matx33d R;                          // camera→world
    cv::Vec3d p;                            // camera position
    int W = 0, H = 0;
};

// Pixel-projection matrix K' = [[fx,0,−cx],[0,−fy,−cy],[0,0,−1]]: [u,v,1] ∝ K'·X_cam.
inline cv::Matx33d kmat(const Cam& c) { return cv::Matx33d(c.fx, 0, -c.cx, 0, -c.fy, -c.cy, 0, 0, -1); }
inline cv::Matx33d kinv(const Cam& c) {
    return cv::Matx33d(1 / c.fx, 0, -c.cx / c.fx, 0, -1 / c.fy, c.cy / c.fy, 0, 0, -1);
}

/// Homography mapping pixels of frame i to pixels of frame j for the fronto-parallel
/// plane (in camera i) at z-distance d: n = (0,0,−1), nᵀX = d.
cv::Matx33d planeHomography(const Cam& ci, const Cam& cj, double d) {
    const cv::Matx33d Rji = cj.R.t() * ci.R;
    const cv::Vec3d tji = cj.R.t() * (ci.p - cj.p);
    cv::Matx33d M = Rji;
    for (int r = 0; r < 3; ++r) M(r, 2) += tji[r] * (-1.0) / d;  // t nᵀ / d with n = (0,0,−1)
    return kmat(cj) * M * kinv(ci);
}

std::vector<int> selectNeighbours(const std::vector<Cam>& cams, int i, int k, double maxAngleDeg, double minBase) {
    const cv::Vec3d fi(-cams[i].R(0, 2), -cams[i].R(1, 2), -cams[i].R(2, 2));
    std::vector<std::pair<double, int>> cand;
    for (int j = 0; j < (int)cams.size(); ++j) {
        if (j == i) continue;
        const cv::Vec3d fj(-cams[j].R(0, 2), -cams[j].R(1, 2), -cams[j].R(2, 2));
        const double ang = std::acos(std::clamp(fi.dot(fj), -1.0, 1.0)) * 180.0 / CV_PI;
        const double base = cv::norm(cams[i].p - cams[j].p);
        if (ang <= maxAngleDeg && base >= minBase) cand.emplace_back(ang - 20.0 * std::min(base, 0.4), j);
    }
    std::sort(cand.begin(), cand.end());
    std::vector<int> out;
    for (int n = 0; n < (int)cand.size() && n < k; ++n) out.push_back(cand[n].second);
    return out;
}

inline void box(const cv::Mat& src, cv::Mat& dst, int r) {
    cv::boxFilter(src, dst, -1, cv::Size(2 * r + 1, 2 * r + 1), cv::Point(-1, -1), true, cv::BORDER_REFLECT);
}

/// He et al. guided filter (grey guide); with `w` a weighted guided filter.
cv::Mat guidedFilter(const cv::Mat& I, const cv::Mat& p, int r, float eps, const cv::Mat* w = nullptr) {
    cv::Mat mI, mp, corrI, corrIp, varI, covIp, a, b, ba, bb, t;
    if (!w) {
        box(I, mI, r);
        box(p, mp, r);
        cv::multiply(I, I, t); box(t, corrI, r);
        cv::multiply(I, p, t); box(t, corrIp, r);
        varI = corrI - mI.mul(mI);
        covIp = corrIp - mI.mul(mp);
    } else {
        cv::Mat sw;
        box(*w, sw, r);
        sw += 1e-6f;
        cv::multiply(I, *w, t); box(t, mI, r); cv::divide(mI, sw, mI);
        cv::multiply(p, *w, t); box(t, mp, r); cv::divide(mp, sw, mp);
        cv::multiply(I, I, t); cv::multiply(t, *w, t); box(t, varI, r); cv::divide(varI, sw, varI);
        varI -= mI.mul(mI);
        cv::multiply(I, p, t); cv::multiply(t, *w, t); box(t, covIp, r); cv::divide(covIp, sw, covIp);
        covIp -= mI.mul(mp);
    }
    cv::divide(covIp, varI + eps, a);
    b = mp - a.mul(mI);
    box(a, ba, r);
    box(b, bb, r);
    return ba.mul(I) + bb;
}

/// Interpolate q where weight w (0..1) is low: pyramid pull-push.
cv::Mat pullPush(const cv::Mat& q, const cv::Mat& w, float fallback) {
    std::vector<cv::Mat> num, den;
    num.push_back(q.mul(w));
    den.push_back(w.clone());
    while (std::min(num.back().rows, num.back().cols) > 8) {
        cv::Mat n2, d2;
        cv::pyrDown(num.back(), n2);
        cv::pyrDown(den.back(), d2);
        num.push_back(n2);
        den.push_back(d2);
    }
    const int L = (int)num.size();
    cv::Mat est(num[L - 1].size(), CV_32F);
    for (int y = 0; y < est.rows; ++y) {
        const float* n = num[L - 1].ptr<float>(y);
        const float* d = den[L - 1].ptr<float>(y);
        float* e = est.ptr<float>(y);
        for (int x = 0; x < est.cols; ++x) e[x] = d[x] > 1e-4f ? n[x] / std::max(d[x], 1e-4f) : fallback;
    }
    for (int l = L - 2; l >= 0; --l) {
        cv::Mat up;
        cv::resize(est, up, num[l].size(), 0, 0, cv::INTER_LINEAR);
        cv::Mat next(num[l].size(), CV_32F);
        for (int y = 0; y < next.rows; ++y) {
            const float* n = num[l].ptr<float>(y);
            const float* d = den[l].ptr<float>(y);
            const float* u = up.ptr<float>(y);
            float* e = next.ptr<float>(y);
            for (int x = 0; x < next.cols; ++x) {
                const float wl = std::clamp(d[x], 0.f, 1.f);
                const float val = n[x] / std::max(d[x], 1e-4f);
                e[x] = wl * val + (1.f - wl) * u[x];
            }
        }
        est = next;
    }
    return est;
}

struct Plane { cv::Vec3f n; float c; };  // n·X = c

/// Sequential RANSAC planes over camera-frame points (fit_planes in mvs_depth.py).
std::vector<Plane> fitPlanes(std::vector<cv::Vec3f> pts, int maxPlanes = 3, float thresh = 0.04f, float minFrac = 0.12f,
                             int iters = 300) {
    cv::RNG rng(0);
    std::vector<Plane> planes;
    const int nAll = (int)pts.size();
    const int minIn = std::max(60, (int)(minFrac * nAll));
    std::vector<char> inl;
    while ((int)pts.size() >= minIn && (int)planes.size() < maxPlanes) {
        const int n = (int)pts.size();
        cv::Vec3f bestN;
        float bestC = 0;
        int bestCount = -1;
        for (int it = 0; it < iters; ++it) {
            const int a = rng.uniform(0, n);
            int b = rng.uniform(0, n - 1); if (b >= a) ++b;
            int c = rng.uniform(0, n - 2); if (c >= std::min(a, b)) ++c; if (c >= std::max(a, b)) ++c;
            cv::Vec3f nrm = (pts[b] - pts[a]).cross(pts[c] - pts[a]);
            const float l = (float)cv::norm(nrm);
            if (l < 1e-9f) continue;
            nrm *= 1.f / l;
            const float cc = nrm.dot(pts[a]);
            int count = 0;
            for (const auto& p : pts) count += std::fabs(nrm.dot(p) - cc) < thresh;
            if (count > bestCount) { bestCount = count; bestN = nrm; bestC = cc; }
        }
        if (bestCount < minIn) break;
        // refine: SVD of the centred inliers
        cv::Vec3d cen(0, 0, 0);
        int cnt = 0;
        for (const auto& p : pts) if (std::fabs(bestN.dot(p) - bestC) < thresh) { cen += cv::Vec3d(p); ++cnt; }
        cen *= 1.0 / cnt;
        cv::Matx33d cov = cv::Matx33d::zeros();
        for (const auto& p : pts) {
            if (std::fabs(bestN.dot(p) - bestC) >= thresh) continue;
            const cv::Vec3d d = cv::Vec3d(p) - cen;
            for (int r = 0; r < 3; ++r) for (int s = 0; s < 3; ++s) cov(r, s) += d[r] * d[s];
        }
        cv::Vec3d evals;
        cv::Matx33d evecs;
        cv::eigen(cov, evals, evecs);  // descending; last row = smallest eigenvalue
        const cv::Vec3f nrm((float)evecs(2, 0), (float)evecs(2, 1), (float)evecs(2, 2));
        const float c = nrm.dot(cv::Vec3f((float)cen[0], (float)cen[1], (float)cen[2]));
        planes.push_back({nrm, c});
        std::vector<cv::Vec3f> rest;
        rest.reserve(pts.size());
        for (const auto& p : pts) if (std::fabs(nrm.dot(p) - c) >= thresh) rest.push_back(p);
        pts.swap(rest);
    }
    return planes;
}

// ------------------------------------------------------------------ per-frame state
// Inverse depth (15 bits, linear between inv0 and invLast) + confidence bit.
struct FrameEst {
    cv::Mat q16;  // CV_16U: (quant << 1) | conf
    int W = 0, H = 0;
};

inline float unpackQ(uint16_t v, float inv0, float invStep15) { return inv0 + (float)(v >> 1) * invStep15; }

// ------------------------------------------------------------------ sweep
struct Sweep {
    int W = 0, H = 0, D = 0, Wb = 0;
    int win = 5, gfR = 8;
    float gfEps = 1e-3f;
    int minViews = 2;
    cv::Mat I;                         // float blurred grey of frame i
    cv::Mat mI5, vI5, mI8, varI8;      // box statistics of I (ZNCC radius / guided radius)
    std::vector<cv::Mat> nbrF;         // float blurred grey of the neighbours
    std::vector<cv::Mat> nbrOnes;      // u8 ones of each neighbour's size (mask warps)
    std::vector<std::vector<cv::Matx33d>> Hs;  // [nbr][plane]
    cv::Mat vol;                       // D × (H·W) u8
    cv::Mat nvBits;                    // D × (H·Wb) u8
    cv::Mat pSlice, badSlice;          // per plane: merged cost (float), unseen mask (u8)
    cv::Mat kernel;

    void prepare(const cv::Mat& gray, const std::vector<cv::Mat>& nbrGray, int planes) {
        W = gray.cols; H = gray.rows; D = planes; Wb = (W + 7) / 8;
        gray.convertTo(I, CV_32F, 1.0 / 255.0);
        cv::Mat t;
        box(I, mI5, win);
        cv::multiply(I, I, t); box(t, vI5, win);
        vI5 -= mI5.mul(mI5);
        cv::max(vI5, 0.f, vI5);
        if (gfR > 0) {
            box(I, mI8, gfR);
            box(t, varI8, gfR);
            varI8 -= mI8.mul(mI8);
        }
        nbrF.resize(nbrGray.size());
        nbrOnes.resize(nbrGray.size());
        for (size_t a = 0; a < nbrGray.size(); ++a) {
            nbrGray[a].convertTo(nbrF[a], CV_32F, 1.0 / 255.0);
            nbrOnes[a] = cv::Mat::ones(nbrGray[a].size(), CV_8U);
        }
        if (vol.rows != D || vol.cols != H * W) vol.create(D, H * W, CV_8U);
        if (nvBits.rows != D || nvBits.cols != H * Wb) nvBits.create(D, H * Wb, CV_8U);
        pSlice.create(H, W, CV_32F);
        badSlice.create(H, W, CV_8U);
        kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(2 * win + 1, 2 * win + 1));
    }

    // Stage 1 of plane k: warp every neighbour, ZNCC, keep the mean of the best two.
    void zncc(int k) {
        const int nb = (int)nbrF.size();
        const int margin = win;
        const int bandRows = 48;
        const int nBands = (H + bandRows - 1) / bandRows;
        cv::parallel_for_(cv::Range(0, nBands), [&](const cv::Range& rg) {
            cv::Mat Wj, mask, t1, t2, t3, tmp, b1, b2, cnt;
            for (int b = rg.start; b < rg.end; ++b) {
                const int y0 = b * bandRows, y1 = std::min(H, y0 + bandRows);
                const int ya = std::max(0, y0 - margin), yb = std::min(H, y1 + margin);
                const int rows = yb - ya;
                const cv::Mat Ib = I.rowRange(ya, yb);
                b1.create(rows, W, CV_32F); b1.setTo(std::numeric_limits<float>::infinity());
                b2.create(rows, W, CV_32F); b2.setTo(std::numeric_limits<float>::infinity());
                cnt.create(rows, W, CV_8U); cnt.setTo(0);
                for (int a = 0; a < nb; ++a) {
                    cv::Matx33d Hb = Hs[a][k] * cv::Matx33d(1, 0, 0, 0, 1, (double)ya, 0, 0, 1);
                    cv::warpPerspective(nbrF[a], Wj, Hb, cv::Size(W, rows), cv::INTER_LINEAR | cv::WARP_INVERSE_MAP,
                                        cv::BORDER_CONSTANT, cv::Scalar(0));
                    cv::warpPerspective(nbrOnes[a], mask, Hb, cv::Size(W, rows), cv::INTER_NEAREST | cv::WARP_INVERSE_MAP,
                                        cv::BORDER_CONSTANT, cv::Scalar(0));
                    cv::erode(mask, mask, kernel);  // = box(mask) > 0.999
                    box(Wj, t1, win);               // mean of the warped neighbour
                    cv::multiply(Wj, Wj, tmp); box(tmp, t2, win);  // mean of W²
                    cv::multiply(Ib, Wj, tmp); box(tmp, t3, win);  // mean of I·W
                    for (int y = 0; y < rows; ++y) {
                        const float* mw = t1.ptr<float>(y);
                        const float* bww = t2.ptr<float>(y);
                        const float* biw = t3.ptr<float>(y);
                        const float* mi = mI5.ptr<float>(ya + y);
                        const float* vi = vI5.ptr<float>(ya + y);
                        const uint8_t* mk = mask.ptr<uint8_t>(y);
                        float* B1 = b1.ptr<float>(y);
                        float* B2 = b2.ptr<float>(y);
                        uint8_t* CN = cnt.ptr<uint8_t>(y);
                        for (int x = 0; x < W; ++x) {
                            if (!mk[x]) continue;
                            const float vw = std::max(bww[x] - mw[x] * mw[x], 0.f);
                            const float cov = biw[x] - mi[x] * mw[x];
                            const float c = 1.f - cov / std::sqrt(vi[x] * vw + 1e-6f);
                            if (c < B1[x]) { B2[x] = B1[x]; B1[x] = c; }
                            else if (c < B2[x]) B2[x] = c;
                            CN[x]++;
                        }
                    }
                }
                uint8_t* nvRow = nvBits.ptr<uint8_t>(k);
                for (int y = y0; y < y1; ++y) {
                    const float* B1 = b1.ptr<float>(y - ya);
                    const float* B2 = b2.ptr<float>(y - ya);
                    const uint8_t* CN = cnt.ptr<uint8_t>(y - ya);
                    float* P = pSlice.ptr<float>(y);
                    uint8_t* bad = badSlice.ptr<uint8_t>(y);
                    uint8_t* nv = nvRow + (size_t)y * Wb;
                    std::memset(nv, 0, Wb);
                    for (int x = 0; x < W; ++x) {
                        if (CN[x] >= 2) { P[x] = 0.5f * (B1[x] + B2[x]); bad[x] = 0; }
                        else if (CN[x] == 1) { P[x] = B1[x]; bad[x] = 0; }
                        else { P[x] = 1.f; bad[x] = 1; }
                        if (CN[x] >= minViews) nv[x >> 3] |= (uint8_t)(1u << (x & 7));
                    }
                }
            }
        });
    }

    // Stage 2 of plane k: guided filter of the merged slice (guide = I), quantise into vol.
    void filterSlice(int k) {
        uint8_t* out = vol.ptr<uint8_t>(k);
        const int margin = 2 * gfR;
        const int bandRows = 96;
        const int nBands = (H + bandRows - 1) / bandRows;
        cv::parallel_for_(cv::Range(0, nBands), [&](const cv::Range& rg) {
            cv::Mat mp, t, cov, a, bb, ba, bbb;
            for (int b = rg.start; b < rg.end; ++b) {
                const int y0 = b * bandRows, y1 = std::min(H, y0 + bandRows);
                const int ya = std::max(0, y0 - margin), yb = std::min(H, y1 + margin);
                const cv::Mat P = pSlice.rowRange(ya, yb);
                const cv::Mat Ib = I.rowRange(ya, yb);
                const cv::Mat mIb = mI8.rowRange(ya, yb);
                const cv::Mat vIb = varI8.rowRange(ya, yb);
                if (gfR > 0) {
                    box(P, mp, gfR);
                    cv::multiply(Ib, P, t); box(t, cov, gfR);
                    cov -= mIb.mul(mp);
                    cv::divide(cov, vIb + gfEps, a);
                    bb = mp - a.mul(mIb);
                    box(a, ba, gfR);
                    box(bb, bbb, gfR);
                }
                for (int y = y0; y < y1; ++y) {
                    const uint8_t* bad = badSlice.ptr<uint8_t>(y);
                    uint8_t* o = out + (size_t)y * W;
                    if (gfR > 0) {
                        const float* BA = ba.ptr<float>(y - ya);
                        const float* BB = bbb.ptr<float>(y - ya);
                        const float* Ii = I.ptr<float>(y);
                        for (int x = 0; x < W; ++x) {
                            if (bad[x]) { o[x] = kUnseen; continue; }
                            const float f = std::clamp(BA[x] * Ii[x] + BB[x], 0.f, 2.f);
                            o[x] = (uint8_t)std::lround(f * kCostScale);
                        }
                    } else {
                        const float* Pp = pSlice.ptr<float>(y);
                        for (int x = 0; x < W; ++x)
                            o[x] = bad[x] ? kUnseen : (uint8_t)std::lround(std::clamp(Pp[x], 0.f, 2.f) * kCostScale);
                    }
                }
            }
        });
    }
};

// ------------------------------------------------------------------ SGM + WTA
struct SgmWta {
    int W = 0, H = 0, D = 0, Wb = 0;
    int P1 = 5;
    bool useSgm = true;
    cv::Mat p2x, p2y;   // per-pixel P2 (u8, cost units) from the guide gradients
    cv::Mat bt;         // (H·W) × D u8: bottom→top aggregated costs
    // WTA parameters
    float inv0 = 0, invStep = 0, invLast = 0, invStep15 = 0;
    int costMaxU = 50;      // raw cost threshold in cost units
    float marginMin = 0.1f;

    void prepare(const cv::Mat& guide8, int planes, float sgmP1, float sgmP2) {
        W = guide8.cols; H = guide8.rows; D = planes; Wb = (W + 7) / 8;
        useSgm = sgmP2 > 0;
        P1 = (int)std::lround(sgmP1 * kCostScale);
        p2x.create(H, W, CV_8U);
        p2y.create(H, W, CV_8U);
        for (int y = 0; y < H; ++y) {
            const uint8_t* g = guide8.ptr<uint8_t>(y);
            const uint8_t* gu = guide8.ptr<uint8_t>(y > 0 ? y - 1 : 0);
            uint8_t* px = p2x.ptr<uint8_t>(y);
            uint8_t* py = p2y.ptr<uint8_t>(y);
            for (int x = 0; x < W; ++x) {
                const float gx = x > 0 ? std::fabs((float)g[x] - (float)g[x - 1]) / 255.f : 0.f;
                const float gy = std::fabs((float)g[x] - (float)gu[x]) / 255.f;
                px[x] = (uint8_t)std::lround(sgmP2 * (0.2f + 0.8f * std::exp(-(gx / 0.06f) * (gx / 0.06f))) * kCostScale);
                py[x] = (uint8_t)std::lround(sgmP2 * (0.2f + 0.8f * std::exp(-(gy / 0.06f) * (gy / 0.06f))) * kCostScale);
            }
        }
        if (useSgm && (bt.rows != H * W || bt.cols != D)) bt.create(H * W, D, CV_8U);
    }

    static inline void gatherRow(const cv::Mat& vol, int y, int x0, int x1, int W, uint8_t* dst) {
        const int D = vol.rows, n = x1 - x0;
        for (int d = 0; d < D; ++d) {
            const uint8_t* s = vol.ptr<uint8_t>(d) + (size_t)y * W + x0;
            for (int x = 0; x < n; ++x) dst[x * D + d] = s[x];
        }
    }

    inline void step(const int16_t* prev, const uint8_t* c, int p2, int16_t* cur) const {
        int m = prev[0];
        for (int d = 1; d < D; ++d) m = std::min(m, (int)prev[d]);
        const int mp2 = m + p2;
        for (int d = 0; d < D; ++d) {
            int best = prev[d];
            if (d > 0) best = std::min(best, prev[d - 1] + P1);
            if (d < D - 1) best = std::min(best, prev[d + 1] + P1);
            best = std::min(best, mp2);
            const int cc = c[d] == kUnseen ? kUnseenSgm : c[d];
            cur[d] = (int16_t)(cc + best - m);
        }
    }

    // bottom→top pass, stored in bt (pixel-major)
    void passBT(const cv::Mat& vol) {
        const int nChunks = std::max(1, std::min(W / 32, cv::getNumThreads() * 2));
        cv::parallel_for_(cv::Range(0, nChunks), [&](const cv::Range& rg) {
            for (int ch = rg.start; ch < rg.end; ++ch) {
                const int x0 = W * ch / nChunks, x1 = W * (ch + 1) / nChunks, n = x1 - x0;
                std::vector<uint8_t> c((size_t)n * D);
                std::vector<int16_t> prev((size_t)n * D), cur((size_t)n * D);
                for (int y = H - 1; y >= 0; --y) {
                    gatherRow(vol, y, x0, x1, W, c.data());
                    const uint8_t* p2 = p2y.ptr<uint8_t>(y);
                    for (int x = 0; x < n; ++x) {
                        const uint8_t* cx = c.data() + (size_t)x * D;
                        int16_t* cu = cur.data() + (size_t)x * D;
                        if (y == H - 1) for (int d = 0; d < D; ++d) cu[d] = cx[d] == kUnseen ? kUnseenSgm : cx[d];
                        else step(prev.data() + (size_t)x * D, cx, p2[x0 + x], cu);
                        uint8_t* o = bt.ptr<uint8_t>((size_t)y * W + x0 + x);
                        for (int d = 0; d < D; ++d) o[d] = (uint8_t)cu[d];
                    }
                    prev.swap(cur);
                }
            }
        });
    }

    // Winner-take-all on the total cost of one pixel (units: 4 directions × kCostScale
    // with SGM, or 1 × kCostScale without). Returns packed q16.
    inline uint16_t wta(const int* tot, const uint8_t* craw, int y, int x, const cv::Mat& nvBits, int dirs) const {
        int k = 0;
        for (int d = 1; d < D; ++d) if (tot[d] < tot[k]) k = d;
        const int cmin = tot[k];
        float off = 0.f;
        if (k > 0 && k < D - 1) {
            const int c0 = tot[k - 1], c2 = tot[k + 1];
            const int denom = c0 - 2 * cmin + c2;
            if (denom > 0) off = std::clamp(0.5f * (float)(c0 - c2) / (float)denom, -0.5f, 0.5f);
        }
        const float q = inv0 + ((float)k + off) * invStep;
        int second = std::numeric_limits<int>::max();
        for (int d = 0; d < D; ++d) if (std::abs(d - k) > 2) second = std::min(second, tot[d]);
        const float scale = 1.f / (float)(dirs * kCostScale);
        const float marginV = (second == std::numeric_limits<int>::max() ? 2.f : (float)second * scale) - (float)cmin * scale;
        const int rawU = craw[k] == kUnseen ? 2 * kCostScale : craw[k];
        const bool nvOk = (nvBits.ptr<uint8_t>(k)[(size_t)y * Wb + (x >> 3)] >> (x & 7)) & 1;
        const bool conf = rawU < costMaxU && marginV > marginMin && nvOk;
        int quant = (int)std::lround((q - inv0) / invStep15);
        quant = std::clamp(quant, 0, 32767);
        return (uint16_t)((quant << 1) | (conf ? 1 : 0));
    }

    // left/right + top→bottom streamed, summed with bt, WTA per pixel.
    void aggregateAndSolve(const cv::Mat& vol, const cv::Mat& nvBits, cv::Mat& q16) {
        q16.create(H, W, CV_16U);
        if (!useSgm) {
            cv::parallel_for_(cv::Range(0, H), [&](const cv::Range& rg) {
                std::vector<uint8_t> c((size_t)W * D);
                std::vector<int> tot(D);
                for (int y = rg.start; y < rg.end; ++y) {
                    gatherRow(vol, y, 0, W, W, c.data());
                    for (int x = 0; x < W; ++x) {
                        const uint8_t* cx = c.data() + (size_t)x * D;
                        for (int d = 0; d < D; ++d) tot[d] = cx[d] == kUnseen ? 2 * kCostScale : cx[d];
                        q16.at<uint16_t>(y, x) = wta(tot.data(), cx, y, x, nvBits, 1);
                    }
                }
            });
            return;
        }
        const int B = 24;  // rows per block
        std::vector<uint8_t> blockC((size_t)B * W * D);
        std::vector<uint16_t> blockSum((size_t)B * W * D);
        std::vector<int16_t> tbState((size_t)W * D);
        const int nChunks = std::max(1, std::min(W / 32, cv::getNumThreads() * 2));
        for (int yb = 0; yb < H; yb += B) {
            const int ye = std::min(H, yb + B);
            // step 1: left→right and right→left per row
            cv::parallel_for_(cv::Range(yb, ye), [&](const cv::Range& rg) {
                std::vector<int16_t> lr((size_t)W * D), cur(D), prev(D);
                for (int y = rg.start; y < rg.end; ++y) {
                    uint8_t* c = blockC.data() + (size_t)(y - yb) * W * D;
                    gatherRow(vol, y, 0, W, W, c);
                    const uint8_t* p2 = p2x.ptr<uint8_t>(y);
                    uint16_t* sum = blockSum.data() + (size_t)(y - yb) * W * D;
                    for (int x = 0; x < W; ++x) {
                        const uint8_t* cx = c + (size_t)x * D;
                        int16_t* o = lr.data() + (size_t)x * D;
                        if (x == 0) for (int d = 0; d < D; ++d) o[d] = cx[d] == kUnseen ? kUnseenSgm : cx[d];
                        else step(lr.data() + (size_t)(x - 1) * D, cx, p2[x], o);
                    }
                    for (int x = W - 1; x >= 0; --x) {
                        const uint8_t* cx = c + (size_t)x * D;
                        if (x == W - 1) for (int d = 0; d < D; ++d) cur[d] = cx[d] == kUnseen ? kUnseenSgm : cx[d];
                        else step(prev.data(), cx, p2[x], cur.data());
                        const int16_t* l = lr.data() + (size_t)x * D;
                        uint16_t* s = sum + (size_t)x * D;
                        for (int d = 0; d < D; ++d) s[d] = (uint16_t)(l[d] + cur[d]);
                        prev.swap(cur);
                    }
                }
            });
            // step 2: top→bottom (state per column) + bt + WTA
            cv::parallel_for_(cv::Range(0, nChunks), [&](const cv::Range& rg) {
                std::vector<int16_t> cur(D);
                std::vector<int> tot(D);
                for (int ch = rg.start; ch < rg.end; ++ch) {
                    const int x0 = W * ch / nChunks, x1 = W * (ch + 1) / nChunks;
                    for (int y = yb; y < ye; ++y) {
                        const uint8_t* p2 = p2y.ptr<uint8_t>(y);
                        uint16_t* qrow = q16.ptr<uint16_t>(y);
                        for (int x = x0; x < x1; ++x) {
                            const uint8_t* cx = blockC.data() + ((size_t)(y - yb) * W + x) * D;
                            int16_t* st = tbState.data() + (size_t)x * D;
                            if (y == 0) for (int d = 0; d < D; ++d) cur[d] = cx[d] == kUnseen ? kUnseenSgm : cx[d];
                            else step(st, cx, p2[x], cur.data());
                            const uint16_t* s = blockSum.data() + ((size_t)(y - yb) * W + x) * D;
                            const uint8_t* b = bt.ptr<uint8_t>((size_t)y * W + x);
                            for (int d = 0; d < D; ++d) { tot[d] = s[d] + cur[d] + b[d]; st[d] = cur[d]; }
                            qrow[x] = wta(tot.data(), cx, y, x, nvBits, 4);
                        }
                    }
                }
            });
        }
    }
};

// ------------------------------------------------------------------ cross-frame consistency
void consistency(const std::vector<FrameEst>& est, const std::vector<Cam>& cams, const std::vector<std::vector<int>>& nbrs,
                 float tolInv, float inv0, float invStep15, std::vector<cv::Mat>& conf2) {
    const int n = (int)est.size();
    conf2.assign(n, cv::Mat());
    for (int i = 0; i < n; ++i) {
        const Cam& ci = cams[i];
        const int W = est[i].W, H = est[i].H;
        conf2[i].create(H, W, CV_8U);
        cv::parallel_for_(cv::Range(0, H), [&](const cv::Range& rg) {
            for (int y = rg.start; y < rg.end; ++y) {
                const uint16_t* q = est[i].q16.ptr<uint16_t>(y);
                uint8_t* out = conf2[i].ptr<uint8_t>(y);
                for (int x = 0; x < W; ++x) {
                    if (!(q[x] & 1)) { out[x] = 0; continue; }
                    const float z = 1.f / unpackQ(q[x], inv0, invStep15);
                    const cv::Vec3d Xc(((double)x - ci.cx) / ci.fx * z, -((double)y - ci.cy) / ci.fy * z, -z);
                    const cv::Vec3d Xw = ci.R * Xc + ci.p;
                    int support = 0;
                    for (int j : nbrs[i]) {
                        const Cam& cj = cams[j];
                        const cv::Vec3d Xj = cj.R.t() * (Xw - cj.p);
                        const double zj = -Xj[2];
                        const double inv = 1.0 / std::max(zj, 1e-3);
                        const float uj = (float)(cj.fx * Xj[0] * inv + cj.cx);
                        const float vj = (float)(cj.cy - cj.fy * Xj[1] * inv);
                        const int xi = cvRound(uj), yi = cvRound(vj);
                        if (zj <= 0.05 || xi < 0 || yi < 0 || xi >= est[j].W || yi >= est[j].H) continue;
                        const uint16_t qj = est[j].q16.at<uint16_t>(yi, xi);
                        if (!(qj & 1)) continue;
                        if (std::fabs(unpackQ(qj, inv0, invStep15) - (float)inv) < tolInv) ++support;
                    }
                    out[x] = support >= 1 ? 1 : 0;
                }
            }
        });
    }
}

// ------------------------------------------------------------------ fill
DepthMap fillFrame(const cv::Mat& guide8, const cv::Mat& q16, const cv::Mat& conf, const Cam& cam, float inv0,
                   float invLast, float invStep15, int gfR, int planes, bool hasNeighbours) {
    const int W = q16.cols, H = q16.rows;
    cv::Mat q(H, W, CV_32F), wgt(H, W, CV_32F);
    std::vector<float> confQ;
    for (int y = 0; y < H; ++y) {
        const uint16_t* qq = q16.ptr<uint16_t>(y);
        const uint8_t* c = conf.ptr<uint8_t>(y);
        float* o = q.ptr<float>(y);
        float* w = wgt.ptr<float>(y);
        for (int x = 0; x < W; ++x) {
            if (c[x]) { o[x] = unpackQ(qq[x], inv0, invStep15); confQ.push_back(o[x]); w[x] = 1.f; }
            else { o[x] = 0.f; w[x] = 0.f; }
        }
    }
    cv::Mat wb;
    cv::GaussianBlur(wgt, wb, cv::Size(0, 0), 1.0);
    wgt = wb.mul(wgt);  // soften isolated hits
    float fallback;
    if (!confQ.empty()) {
        const size_t m = confQ.size() / 2;
        std::nth_element(confQ.begin(), confQ.begin() + m, confQ.end());
        fallback = confQ[m];
        if (confQ.size() % 2 == 0) {
            const float lo = *std::max_element(confQ.begin(), confQ.begin() + m);
            fallback = 0.5f * (lo + confQ[m]);
        }
    } else {
        fallback = inv0 + (float)(planes / 2) * (invLast - inv0) / (float)(planes - 1);
    }
    cv::Mat qFill = pullPush(q, wgt, fallback);

    // snap the interpolation onto the dominant planes (walls / floor / ceiling)
    const float fx = (float)cam.fx, fy = (float)cam.fy, cx = (float)cam.cx, cy = (float)cam.cy;
    if (kSnapTol > 0 && confQ.size() > 200) {
        std::vector<cv::Vec3f> pts;
        const int step = std::max<size_t>(1, confQ.size() / 4000);
        int idx = 0;
        for (int y = 0; y < H; ++y) {
            const uint8_t* c = conf.ptr<uint8_t>(y);
            const float* qq = q.ptr<float>(y);
            for (int x = 0; x < W; ++x) {
                if (!c[x]) continue;
                if (idx++ % step == 0) {
                    const float z = 1.f / qq[x];
                    pts.emplace_back(((float)x - cx) / fx * z, -((float)y - cy) / fy * z, -z);
                }
            }
        }
        const std::vector<Plane> planesC = fitPlanes(pts);
        if (!planesC.empty()) {
            cv::Mat qPrior(H, W, CV_32F), res(H, W, CV_32F);
            for (int y = 0; y < H; ++y) {
                const float* qf = qFill.ptr<float>(y);
                const float* qq = q.ptr<float>(y);
                const uint8_t* c = conf.ptr<uint8_t>(y);
                float* pr = qPrior.ptr<float>(y);
                float* rs = res.ptr<float>(y);
                for (int x = 0; x < W; ++x) {
                    const cv::Vec3f dir(((float)x - cx) / fx, -((float)y - cy) / fy, -1.f);
                    float bestD = std::numeric_limits<float>::infinity(), best = qf[x];
                    for (const Plane& pl : planesC) {
                        const float den = dir.dot(pl.n);
                        const float t = std::fabs(den) > 1e-6f ? pl.c / den : -1.f;
                        if (!(t > 0.3f)) continue;
                        const float qp = std::clamp(1.f / std::max(t, 0.3f), inv0, invLast);
                        const float diff = std::fabs(qp - qf[x]);
                        if (diff < bestD) { bestD = diff; best = qp; }
                    }
                    pr[x] = bestD < kSnapTol * 3 ? best : qf[x];
                    rs[x] = c[x] ? qq[x] - pr[x] : 0.f;
                }
            }
            qFill = qPrior + pullPush(res, wgt, 0.f);
        }
    }
    cv::Mat guideF;
    guide8.convertTo(guideF, CV_32F, 1.0 / 255.0);
    cv::Mat w2;
    cv::max(wgt, 0.05f, w2);
    cv::Mat qRef = guidedFilter(guideF, qFill, gfR * 2, 1e-3f, &w2);
    DepthMap dm;
    dm.z.create(H, W, CV_32F);
    for (int y = 0; y < H; ++y) {
        const float* r = qRef.ptr<float>(y);
        float* z = dm.z.ptr<float>(y);
        for (int x = 0; x < W; ++x) z[x] = 1.f / std::clamp(r[x], inv0, invLast);
    }
    cv::medianBlur(dm.z, dm.z, 5);
    dm.conf.create(H, W, CV_8U);
    for (int y = 0; y < H; ++y) {
        const uint8_t* c = conf.ptr<uint8_t>(y);
        uint8_t* o = dm.conf.ptr<uint8_t>(y);
        for (int x = 0; x < W; ++x) o[x] = c[x] ? 2 : (hasNeighbours ? 1 : 0);
    }
    dm.fx = fx; dm.fy = fy; dm.cx = cx; dm.cy = cy;
    return dm;
}

cv::Matx33d orthonormalise(const cv::Matx33d& M) {
    cv::Matx33d u, vt;
    cv::Vec3d w;
    cv::SVD::compute(M, w, u, vt);
    return u * vt;
}

}  // namespace

// ------------------------------------------------------------------ entry point
std::vector<DepthMap> computeDepthMaps(const std::vector<FrameInput>& frames, const std::vector<Pose>& poses,
                                       const MvsOptions& opt, const ProgressFn& progress, MvsStats* stats) {
    const auto t0 = std::chrono::steady_clock::now();
    const int n = (int)frames.size();
    std::vector<DepthMap> out(n);
    if (stats) { stats->seconds = 0; stats->confFraction.assign(n, 0.f); }
    if (n == 0) return out;
    const int D = std::max(2, opt.planes);
    const float inv0 = 1.f / opt.zMax, invLast = 1.f / opt.zMin;
    const float invStep = (invLast - inv0) / (float)(D - 1);
    const float invStep15 = (invLast - inv0) / 32767.f;

    auto report = [&](float p, const std::string& m) { if (progress) progress(p, m); };

    // ---- load: reduced grey images (blurred for matching, unblurred as guide) + cameras
    std::vector<cv::Mat> gray(n), guide(n);
    std::vector<Cam> cams(n);
    std::vector<char> loaded(n, 0);
    report(0.f, "MVS: loading frames");
    cv::parallel_for_(cv::Range(0, n), [&](const cv::Range& rg) {
        for (int i = rg.start; i < rg.end; ++i) {
            cv::Mat img = imreadForWidth(frames[i].path, opt.width, frames[i].imageWidth, true);
            if (img.empty()) continue;
            const int w0 = frames[i].imageWidth > 0 ? frames[i].imageWidth : img.cols;
            const int h0 = frames[i].imageHeight > 0 ? frames[i].imageHeight : img.rows;
            const double s = (double)opt.width / w0;
            const int hs = (int)std::lround(h0 * s);
            cv::Mat small;
            if (img.cols == opt.width && img.rows == hs) small = img;
            else cv::resize(img, small, cv::Size(opt.width, hs), 0, 0, cv::INTER_AREA);
            img.release();
            cv::cvtColor(small, guide[i], cv::COLOR_BGR2GRAY);
            if (opt.blurSigma > 0) {
                cv::Mat g, gb;
                guide[i].convertTo(g, CV_32F, 1.0 / 255.0);
                cv::GaussianBlur(g, gb, cv::Size(0, 0), opt.blurSigma);
                gb.convertTo(gray[i], CV_8U, 255.0);
            } else {
                gray[i] = guide[i].clone();
            }
            Cam& c = cams[i];
            const double iw = frames[i].imageWidth > 0 ? frames[i].imageWidth : w0;
            const double ih = frames[i].imageHeight > 0 ? frames[i].imageHeight : h0;
            c.fx = frames[i].fx * opt.width / iw;
            c.fy = frames[i].fy * hs / ih;
            c.cx = frames[i].cx * opt.width / iw;
            c.cy = frames[i].cy * hs / ih;
            c.W = opt.width; c.H = hs;
            if ((int)poses.size() == n) {
                for (int r = 0; r < 3; ++r) for (int cc = 0; cc < 3; ++cc) c.R(r, cc) = poses[i].R(r, cc);
                c.p = cv::Vec3d(poses[i].p[0], poses[i].p[1], poses[i].p[2]);
            } else {
                const auto& T = frames[i].transform;  // column-major
                cv::Matx33d M;
                for (int r = 0; r < 3; ++r) for (int cc = 0; cc < 3; ++cc) M(r, cc) = T[cc * 4 + r];
                c.R = orthonormalise(M);
                c.p = cv::Vec3d(T[12], T[13], T[14]);
            }
            loaded[i] = 1;
        }
    }, 4 /* limit concurrent full-size decodes */);

    std::vector<std::vector<int>> nbrs(n);
    for (int i = 0; i < n; ++i) {
        if (!loaded[i]) continue;
        auto sel = selectNeighbours(cams, i, opt.neighbours, opt.maxAngleDeg, opt.minBaselineM);
        for (int j : sel) if (loaded[j]) nbrs[i].push_back(j);
    }

    // ---- pass 1: plane sweep per frame
    std::vector<FrameEst> est(n);
    Sweep sweep;
    sweep.win = opt.winRadius; sweep.gfR = opt.gfRadius; sweep.gfEps = opt.gfEps; sweep.minViews = opt.minViews;
    SgmWta sgm;
    sgm.inv0 = inv0; sgm.invStep = invStep; sgm.invLast = invLast; sgm.invStep15 = invStep15;
    sgm.costMaxU = (int)std::lround(opt.costMax * kCostScale);
    sgm.marginMin = opt.margin;
    for (int i = 0; i < n; ++i) {
        est[i].W = cams[i].W; est[i].H = cams[i].H;
        if (!loaded[i] || nbrs[i].empty()) {
            est[i].q16 = cv::Mat::zeros(cams[i].H, cams[i].W, CV_16U);
            continue;
        }
        report(0.05f + 0.75f * i / n, "MVS: sweep " + std::to_string(i + 1) + "/" + std::to_string(n));
        std::vector<cv::Mat> nbrGray;
        for (int j : nbrs[i]) nbrGray.push_back(gray[j]);
        sweep.prepare(gray[i], nbrGray, D);
        sweep.Hs.assign(nbrs[i].size(), std::vector<cv::Matx33d>(D));
        for (size_t a = 0; a < nbrs[i].size(); ++a)
            for (int k = 0; k < D; ++k) sweep.Hs[a][k] = planeHomography(cams[i], cams[nbrs[i][a]], 1.0 / (inv0 + k * invStep));
        for (int k = 0; k < D; ++k) {
            sweep.zncc(k);
            sweep.filterSlice(k);
        }
        sgm.prepare(guide[i], D, opt.sgmP1, opt.sgmP2);
        if (sgm.useSgm) sgm.passBT(sweep.vol);
        sgm.aggregateAndSolve(sweep.vol, sweep.nvBits, est[i].q16);
    }
    sweep = Sweep();
    sgm = SgmWta();

    // ---- pass 2: cross-frame consistency
    report(0.82f, "MVS: consistency");
    std::vector<cv::Mat> conf2;
    if (opt.tolInv > 0) {
        consistency(est, cams, nbrs, opt.tolInv, inv0, invStep15, conf2);
    } else {
        conf2.resize(n);
        for (int i = 0; i < n; ++i) {
            conf2[i].create(est[i].H, est[i].W, CV_8U);
            for (int y = 0; y < est[i].H; ++y)
                for (int x = 0; x < est[i].W; ++x) conf2[i].at<uint8_t>(y, x) = est[i].q16.at<uint16_t>(y, x) & 1;
        }
    }
    gray.clear();

    // ---- pass 3: fill
    for (int i = 0; i < n; ++i) {
        report(0.85f + 0.15f * i / n, "MVS: fill " + std::to_string(i + 1) + "/" + std::to_string(n));
        if (!loaded[i]) continue;
        out[i] = fillFrame(guide[i], est[i].q16, conf2[i], cams[i], inv0, invLast, invStep15, opt.gfRadius, D,
                           !nbrs[i].empty());
        if (stats) stats->confFraction[i] = (float)cv::countNonZero(conf2[i]) / (float)(est[i].W * est[i].H);
        est[i].q16.release();
        conf2[i].release();
        guide[i].release();
    }
    if (stats) stats->seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    report(1.f, "MVS: done");
    return out;
}

}  // namespace uy360
