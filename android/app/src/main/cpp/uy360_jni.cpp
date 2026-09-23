#include <opencv2/calib3d.hpp>
// JNI bridge between uz.uy360.capture.stitch.NativeStitcher (Kotlin) and the shared C++ core.
//
//   stitch(...)      — runs uy360::stitchMVS (bundle adjustment + depth-from-motion + depth
//                      re-projection) or the fast rotation-only uy360::stitch, optionally stamps
//                      the nadir logo disc (logoPath → Options.nadirLogoPath), reports progress
//                      through a Kotlin callback and returns a small JSON result string
//                      ({ok,width,height,frames,coverage,seconds,pairs,residualBefore/After,
//                      depthFrames,baSeconds,mvsSeconds,stitchSeconds,baMedianBefore/AfterPx,
//                      blend,align,error}; the PipelineStats fields are 0 in rotation-only mode).
//   rotateJpeg(...)  — physically rotates a JPEG by 0/90/180/270° (EXIF is dropped) so that
//                      the saved frame is an upright portrait image whose +X is camera +X.
//
// The progress callback is invoked from OpenCV worker threads: those are not attached to the
// JVM, so every call attaches (if needed), invokes the callback and detaches again.
#include "uy360_pipeline.hpp"
#include "uy360_stitch.hpp"
#include "uy360_types.hpp"

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include <android/log.h>
#include <jni.h>

#include <cmath>
#include <cstdio>
#include <exception>
#include <mutex>
#include <string>
#include <vector>

#define LOG_TAG "uy360-native"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

JavaVM* g_vm = nullptr;

std::string jstringToStd(JNIEnv* env, jstring s) {
    if (!s) return {};
    const char* c = env->GetStringUTFChars(s, nullptr);
    std::string out = c ? c : "";
    if (c) env->ReleaseStringUTFChars(s, c);
    return out;
}

// Minimal JSON string escaping for the result object.
std::string jsonEscape(const std::string& s) {
    std::string o;
    o.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"': o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default:
                if ((unsigned char)c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", (unsigned)(unsigned char)c);
                    o += buf;
                } else {
                    o += c;
                }
        }
    }
    return o;
}

std::string resultJson(const uy360::Result& r, const uy360::PipelineStats* st, const std::string& errorOverride,
                       bool preservePhotometry) {
    std::string err = errorOverride.empty() ? r.error : errorOverride;
    char buf[1024];
    std::snprintf(buf, sizeof(buf),
                  "{\"ok\":%s,\"width\":%d,\"height\":%d,\"frames\":%d,\"coverage\":%.4f,\"seconds\":%.2f,"
                  "\"pairs\":%d,\"residualBefore\":%.3f,\"residualAfter\":%.3f,\"depthFrames\":%d,"
                  "\"baSeconds\":%.2f,\"mvsSeconds\":%.2f,\"stitchSeconds\":%.2f,"
                  "\"baMedianBeforePx\":%.3f,\"baMedianAfterPx\":%.3f,",
                  (r.ok && err.empty()) ? "true" : "false", r.width, r.height, r.frames, r.coverage, r.seconds,
                  r.pairs, r.residualBeforeDeg, r.residualAfterDeg, r.depthFrames,
                  st ? st->baSeconds : 0.0, st ? st->mvsSeconds : 0.0, st ? st->stitchSeconds : 0.0,
                  st ? st->ba.medianBeforePx : 0.f, st ? st->ba.medianAfterPx : 0.f);
    std::string out = buf;
    out += std::string("\"gainCompensation\":\"") + (preservePhotometry ? "locked-capture" : "overlap") + "\",";
    if (st) {
        out += "\"baConstrainedCameras\":" + std::to_string(st->ba.constrainedCameras) + ",";
        out += "\"baPoints\":" + std::to_string(st->ba.points) + ",";
        out += "\"baCameraObservations\":[";
        for (size_t i = 0; i < st->ba.cameraObservations.size(); ++i) {
            if (i) out += ",";
            out += std::to_string(st->ba.cameraObservations[i]);
        }
        out += "],\"fallbackReason\":\"" + jsonEscape(st->fallbackReason) + "\",";
    }
    out += "\"blend\":\"" + jsonEscape(r.blend) + "\",";
    out += "\"align\":\"" + jsonEscape(r.align) + "\",";
    out += "\"error\":\"" + jsonEscape(err) + "\"}";
    return out;
}

/// Calls ProgressCallback.onProgress(float, String) from any thread.
class JavaProgress {
public:
    JavaProgress(JNIEnv* env, jobject cb) {
        if (!cb) return;
        ref_ = env->NewGlobalRef(cb);
        jclass cls = env->GetObjectClass(cb);
        mid_ = env->GetMethodID(cls, "onProgress", "(FLjava/lang/String;)V");
        env->DeleteLocalRef(cls);
        if (!mid_) {
            env->ExceptionClear();
            LOGE("ProgressCallback.onProgress(F,String) not found");
        }
    }
    ~JavaProgress() {
        if (!ref_) return;
        JNIEnv* env = nullptr;
        bool attached = false;
        if (acquire(&env, &attached)) {
            env->DeleteGlobalRef(ref_);
            if (attached) g_vm->DetachCurrentThread();
        }
    }
    void operator()(float p, const std::string& msg) {
        if (!ref_ || !mid_) return;
        std::lock_guard<std::mutex> lock(mutex_);   // callbacks may overlap on the worker pool
        JNIEnv* env = nullptr;
        bool attached = false;
        if (!acquire(&env, &attached)) return;
        jstring js = env->NewStringUTF(msg.c_str());
        env->CallVoidMethod(ref_, mid_, (jfloat)p, js);
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
        env->DeleteLocalRef(js);
        if (attached) g_vm->DetachCurrentThread();
    }

private:
    static bool acquire(JNIEnv** env, bool* attached) {
        if (!g_vm) return false;
        int st = g_vm->GetEnv(reinterpret_cast<void**>(env), JNI_VERSION_1_6);
        if (st == JNI_OK) return true;
        if (st == JNI_EDETACHED) {
            JavaVMAttachArgs args{JNI_VERSION_1_6, "uy360-worker", nullptr};
            if (g_vm->AttachCurrentThread(env, &args) == JNI_OK) {
                *attached = true;
                return true;
            }
        }
        return false;
    }
    jobject ref_ = nullptr;
    jmethodID mid_ = nullptr;
    std::mutex mutex_;
};

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jstring JNICALL
Java_uz_kadastr_kadastr_pano_NativeStitcher_version(JNIEnv* env, jobject) {
    std::string v = std::string("uy360 core / OpenCV ") + CV_VERSION + " / threads " + std::to_string(cv::getNumThreads());
    return env->NewStringUTF(v.c_str());
}

/// stitch(paths, transforms[16n], intrinsics[4n], sizes[2n], targetPitch[n], width, mvs, sensorPoses, photometryLocked, pano, preview,
///        logoPath, cb)
/// logoPath: PNG stamped as a disc over the bottom cap of the panorama (`Options.nadirLogoPath`, the
/// brand disc that hides feet / the mirror fill — same as iOS); null or "" = no logo. Applies to both
/// the MVS and the rotation-only path (both end in the same stitchImpl).
extern "C" JNIEXPORT jstring JNICALL
Java_uz_kadastr_kadastr_pano_NativeStitcher_stitch(JNIEnv* env, jobject, jobjectArray jpaths, jfloatArray jtransforms,
                                                   jfloatArray jintrinsics, jintArray jsizes, jfloatArray jpitch,
                                                   jint width, jboolean mvs, jboolean sensorPoses, jboolean photometryLocked, jstring jpano,
                                                   jstring jpreview, jstring jlogoPath, jobject jcb) {
    uy360::Result r;
    std::string error;
    uy360::PipelineStats st;
    const bool preservePhotometry = sensorPoses == JNI_TRUE && photometryLocked == JNI_TRUE;
    try {
        const jsize n = jpaths ? env->GetArrayLength(jpaths) : 0;
        if (n <= 0) throw std::runtime_error("no frames");
        if (env->GetArrayLength(jtransforms) != 16 * n || env->GetArrayLength(jintrinsics) != 4 * n ||
            env->GetArrayLength(jsizes) != 2 * n || env->GetArrayLength(jpitch) != n)
            throw std::runtime_error("frame array length mismatch");

        std::vector<float> T(16 * n), K(4 * n), P(n);
        std::vector<jint> S(2 * n);
        env->GetFloatArrayRegion(jtransforms, 0, 16 * n, T.data());
        env->GetFloatArrayRegion(jintrinsics, 0, 4 * n, K.data());
        env->GetIntArrayRegion(jsizes, 0, 2 * n, S.data());
        env->GetFloatArrayRegion(jpitch, 0, n, P.data());

        std::vector<uy360::FrameInput> frames;
        frames.reserve(n);
        for (jsize i = 0; i < n; ++i) {
            uy360::FrameInput f;
            jstring js = (jstring)env->GetObjectArrayElement(jpaths, i);
            f.path = jstringToStd(env, js);
            env->DeleteLocalRef(js);
            for (int k = 0; k < 16; ++k) f.transform[k] = T[16 * i + k];
            f.fx = K[4 * i];
            f.fy = K[4 * i + 1];
            f.cx = K[4 * i + 2];
            f.cy = K[4 * i + 3];
            f.imageWidth = S[2 * i];
            f.imageHeight = S[2 * i + 1];
            f.targetPitch = P[i];
            if (f.imageWidth <= 0 || f.imageHeight <= 0 || f.fx <= 0 || f.fy <= 0) {
                LOGE("frame %d has invalid intrinsics/size — skipped", (int)i);
                continue;
            }
            frames.push_back(std::move(f));
        }
        if (frames.size() < 2) throw std::runtime_error("need at least 2 valid frames");

        const std::string pano = jstringToStd(env, jpano);
        const std::string preview = jstringToStd(env, jpreview);
        const std::string logoPath = jstringToStd(env, jlogoPath);
        JavaProgress progress(env, jcb);
        uy360::Progress prog = [&progress](float p, const std::string& m) { progress(p, m); };

        uy360::Options opt = uy360::optionsForFrameCount((int)frames.size());
        opt.width = width > 0 ? width : 4096;
        // A parallax-contaminated overlap mean can invent exposure differences
        // even with verified AE/AWB locks (S23 stuff-2). Preserve those pixels.
        opt.gainComp = !preservePhotometry;
        // nadir patch (Options.nadirLogoDeg = 20° cap): stamped by stitchImpl in both modes, "" = off
        if (!logoPath.empty()) opt.nadirLogoPath = logoPath;
        LOGI("stitch: %zu frames, width %d, mvs=%d, sensorPoses=%d, logo=%s, threads=%d", frames.size(), opt.width,
             (int)mvs, (int)sensorPoses, logoPath.empty() ? "-" : logoPath.c_str(), cv::getNumThreads());

        if (mvs) {
            // NOTE: MvsOptions defaults = the high-quality preset (1008 px / 96 planes); iOS uses
            // MvsOptions::fast() (756 px / 64 planes) unless "Chuqurlik aniqligi" is on. Android has
            // no such setting yet and keeps the full-quality preset.
            uy360::PipelineOptions popt;  // core defaults = server-validated parameters (ARKit/ARCore poses) ...
            // ... except when the poses come from the phone's gyro/accelerometer (sensor mode:
            // no translation, heading drift) → BAOptions::forSensorPoses(): loose position,
            // tight tilt / loose yaw absolute prior, relative-rotation chain between consecutive
            // shots, rotation-known essential estimation, pivot fill for track-less frames.
            // ARCore captures (6-DoF, metric) use the same accurate-pose priors as iOS.
            popt.sensorPoses = sensorPoses == JNI_TRUE;
            popt.requireAllSensorCameras = popt.sensorPoses;
            // Match the existing missing/feet cap; do not overwrite another 16° of photographed floor.
            if (popt.sensorPoses) opt.nadirLogoDeg = opt.nadirCutDeg;
            r = uy360::stitchMVS(frames, opt, popt, pano, preview, prog, &st);
        } else {
            r = uy360::stitch(frames, opt, pano, preview, prog);
        }
    } catch (const cv::Exception& e) {
        error = std::string("OpenCV: ") + e.what();
        LOGE("%s", error.c_str());
    } catch (const std::exception& e) {
        error = e.what();
        LOGE("%s", error.c_str());
    } catch (...) {
        error = "unknown native error";
    }
    std::string json = resultJson(r, &st, error, preservePhotometry);
    return env->NewStringUTF(json.c_str());
}

/// rotateJpeg(src, dst, degreesClockwise, quality) → true on success. Reads the JPEG ignoring its
/// EXIF orientation tag, rotates the pixels and writes a plain JPEG (no EXIF) to dst.
extern "C" JNIEXPORT jboolean JNICALL
Java_uz_kadastr_kadastr_pano_NativeStitcher_rotateJpeg(JNIEnv* env, jobject, jstring jsrc, jstring jdst,
                                                       jint degrees, jint quality, jfloatArray jk, jfloatArray jd) {
    try {
        const std::string src = jstringToStd(env, jsrc), dst = jstringToStd(env, jdst);
        cv::Mat img = cv::imread(src, cv::IMREAD_COLOR | cv::IMREAD_IGNORE_ORIENTATION);
        if (img.empty()) {
            LOGE("rotateJpeg: cannot read %s", src.c_str());
            return JNI_FALSE;
        }
        // Camera2 LENS_DISTORTION [k1,k2,k3,p1,p2] uses normalized Brown-Conrady.
        // Correct in sensor axes before rotating. Already-corrected HAL JPEGs pass no coefficients.
        if (jd && env->GetArrayLength(jd) != 0) {
            if (env->GetArrayLength(jd) != 5 || !jk || env->GetArrayLength(jk) != 4) return JNI_FALSE;
            float k[4], d[5];
            env->GetFloatArrayRegion(jk,0,4,k); env->GetFloatArrayRegion(jd,0,5,d);
            for (float v : k) if (!std::isfinite(v)) return JNI_FALSE;
            for (float v : d) if (!std::isfinite(v)) return JNI_FALSE;
            if (k[0] <= 0 || k[1] <= 0) return JNI_FALSE;
            cv::Matx33d K(k[0],0,k[2],0,k[1],k[3],0,0,1);
            cv::Mat coeff = (cv::Mat_<double>(1,5) << d[0],d[1],d[3],d[4],d[2]);
            cv::Mat corrected;
            cv::undistort(img,corrected,K,coeff,K);
            img = std::move(corrected);
        }
        int d = ((degrees % 360) + 360) % 360;
        cv::Mat out;
        switch (d) {
            case 90: cv::rotate(img, out, cv::ROTATE_90_CLOCKWISE); break;
            case 180: cv::rotate(img, out, cv::ROTATE_180); break;
            case 270: cv::rotate(img, out, cv::ROTATE_90_COUNTERCLOCKWISE); break;
            default: out = img; break;
        }
        std::vector<int> params{cv::IMWRITE_JPEG_QUALITY, std::max(1, std::min(100, (int)quality))};
        if (!cv::imwrite(dst, out, params)) {
            LOGE("rotateJpeg: cannot write %s", dst.c_str());
            return JNI_FALSE;
        }
        return JNI_TRUE;
    } catch (const std::exception& e) {
        LOGE("rotateJpeg: %s", e.what());
        return JNI_FALSE;
    }
}
