// Synthetic textured-sphere fixture ported from existing iOS tests; no real-scene quality claim.
#include "uy360_pipeline.hpp"
#include <opencv2/imgproc.hpp>
#include <jni.h>
#include <cmath>
#include <fstream>
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

static std::vector<uy360::FrameInput> rotationCapture(const std::string& dir, const cv::Mat& source,
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
        frame.path = dir + "/frame_" + std::to_string(frames.size()) + ".jpg";
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


extern "C" JNIEXPORT void JNICALL Java_uz_kadastr_kadastr_pano_NativeFixture_create(JNIEnv* env,jobject,jstring path,jfloat pivot,jboolean measured) {
    const char* chars=env->GetStringUTFChars(path,nullptr); std::string dir(chars); env->ReleaseStringUTFChars(path,chars);
    auto frames=rotationCapture(dir,sourceImage(),pivot,measured);
    std::ofstream out(dir+"/meta.json"); out << "[";
    for (size_t i=0;i<frames.size();++i) {
        const auto& f=frames[i]; if(i)out << ",";
        out << "{\"index\":" << i << ",\"targetId\":" << i << ",\"targetYaw\":0,\"targetPitch\":" << f.targetPitch
            << ",\"transform\":[";
        for(int j=0;j<16;++j){if(j)out<<",";out<<f.transform[j];}
        out << "],\"intrinsics\":[" << f.fx << "," << f.fy << "," << f.cx << "," << f.cy << "]"
            << ",\"imageWidth\":" << f.imageWidth << ",\"imageHeight\":" << f.imageHeight
            << ",\"pixelWidth\":" << f.imageWidth << ",\"pixelHeight\":" << f.imageHeight
            << ",\"timestamp\":" << i << ",\"highRes\":true,\"file\":\"frame_" << i << ".jpg\",\"poseSource\":\""
            << (measured ? "arcore" : "sensors:android") << "\"}";
    }
    out << "]";
}
