# Android Astra 0.5 capture and validation

Status as of 2026-09-17: implementation and automated device checks pass. **Not yet approved for normal Galaxy S23 use.** A person must still complete the guided capture and real-scene/product-flow checklist below. No real-room panorama quality or full listing submission on the phone is claimed by the synthetic tests.

Reference: `360-astra-0.5`, branch `astra-0.5`, commit `3de962b2de43580a249dfa17eb85dc493f62f9d6`. Work is in `mobile` on `master`. Existing iOS migration/viewer work and `pubspec.yaml` are preserved. No commit or push was performed.

## What existed

Android had a separate/partial panorama integration: `PanoCaptureActivity` used ARCore measured poses and intrinsics, converted camera YUV to JPEG, and used 28 required targets (12 horizon, 8 upper, 8 lower), with optional poles. The Flutter platform entry reported capture unsupported. Android did not build or invoke the upgraded local Astra C++ processor.

The reference Astra Android application supplied reusable gyro integration, coordinate/quaternion math and JNI patterns. Its CameraX/callback-arrival timing path was not copied. This integration uses Camera2 to select physical cameras and correlate the actual exposure with sensor samples. CameraX remains available to the unrelated existing video recorder.

## End-to-end architecture

1. Existing description-step capture flow calls `PanoCaptureChannel` (`kadastr/pano_capture`). Capabilities distinguish ultra-wide capture, ARCore capture, native processing and native viewing. Android uses the existing Flutter panorama viewer.
2. Prefer `UltraWideCaptureActivity` when camera, sensor and native capabilities are available. Retain `PanoCaptureActivity` as the ARCore fallback. Startup lens/session failure before a preview maps to the unavailable-ultra-wide error so Flutter can fall back. Do not silently replace an interrupted in-progress capture.
3. Camera2 provides preview and still JPEGs. Motion is collected on a dedicated sensor thread; camera callbacks and image work use a separate worker.
4. Captures persist source JPEGs and `meta.json` under app-private `filesDir/pano`. Frames are indexed by acquisition order; `targetId` is independent. Metadata is atomically replaced after each capture/undo. Existing legacy cache capture directories remain accepted for processing.
5. `MainActivity` reserves one processing job, copies the existing Kadastr nadir asset, and starts a foreground `PanoProcessingService`. The Dart contract and progress channel remain the existing ones.
6. `PanoStorage` validates inputs/provenance. `NativeStitcher` passes explicit `sensorPoses` through JNI. CMake compiles the same `ios/Runner/PanoCore/*.cpp` sources used by the completed iOS migration; no second Android processing implementation or edits to those sources were introduced.
7. The shared core performs sensor BA, support checks, MVS/depth and structural/planar processing where supported, reprojection, seams and blending. Insufficient geometry retains sensor orientations and uses rotation-only stitching. Sensor capture defaults to HQ 6144×3072; ARCore defaults to 4096×2048. Explicit width overrides remain available. `processing.json` records resolution, provenance, time, alignment/fallback and depth-frame count.
8. Both output JPEGs are checked for complete markers, decodability and expected dimensions. Pending outputs are published as `preview.jpg`, then `pano.jpg` as the completion marker. Sources survive processing failures for retry.
9. `PanoPreviewScreen` wraps the existing interactive `PanoTourScreen`. Acceptance is enabled only after its full panorama image decodes; back is cancellation, not acceptance. Retake uses the existing flow.
10. Accepted `pano.jpg` follows the existing local panorama/draft → media upload → storage key/URL → listing/tour path. No API, room order, hotspot coordinates or source-frame upload contract was changed. Failed uploads retain the existing local panorama behavior.

Processing continues through ordinary Activity backgrounding via a foreground service. Process death does not automatically resume a worker: persisted inputs allow the existing retry flow. Backgrounding capture returns a persisted partial result when at least four frames exist; with fewer frames it reports interruption and retains sources. Resuming an interrupted *capture session* from those partial frames is not implemented.

## Camera, timing and pixel contract

### Selection

`UltraWideCamera` enumerates public rear non-logical cameras plus physical members of logical multi-camera devices. `UltraWideSelection` compares `2*atan(sensorWidth/(2*focalLength))`, requiring at least 95° horizontal field of view, JPEG and preview streams, and a REALTIME timestamp source. It chooses the widest usable candidate and prefers a directly openable physical camera when equivalent. IDs and manufacturer strings are never selection rules. A logical-only physical candidate is routed through physical `OutputConfiguration`s. Actual session failure triggers the retained fallback before capture begins.

JPEG selection uses the largest supported size up to 16 megapixels. Electronic/optical stabilization is disabled and crop/rotate controls are explicit where supported.

On the connected **Samsung Galaxy S23 SM-S911N**, enumeration selected public rear physical **camera `2`**, focal length **2.2 mm**, sensor **5.6×4.2 mm**, horizontal FOV **103.6855°**, JPEG **4000×3000**, sensor orientation **90°**, REALTIME clock. This is approximately **0.59×** relative to the phone's standard wide focal/sensor characteristics. No logical physical-ID override is needed for this exposed camera. Runtime JPEG acquisition passed. Human inspection of the displayed field of view remains pending.

### Targets and motion

- Exactly 17 required, unique targets: 8 horizon at 45° yaw intervals; 4 upper at +52° and yaw 45/135/225/315°; 4 lower at −52° with the same yaws; zenith +89°.
- Nearest uncaptured target, acquisition order independent of target ID, undo/recapture, normal completion at 17, confirmed early finish at four or more.
- Aim within 6°, angular speed below approximately 8°/s, roll within 12°, stable dwell 350 ms. Roll is exempt near poles above 75° absolute pitch.
- Reference raw-gyro integration with accelerometer gravity correction avoids rotation-vector pipeline latency. Requested rates: gyro 200 Hz, accelerometer 100 Hz. A gyro gap over 50 ms fails capture instead of fabricating rotation.
- Android-to-Astra conversion yields camera-to-world orientation with world +Y up, image +X right, image +Y up and camera −Z forward. Saved transforms are column-major 4×4, with exactly zero sensor translation. Initial yaw is anchored to the capture session.

### Exposure and intrinsics

- Camera2 `SENSOR_TIMESTAMP` must equal the JPEG timestamp. REALTIME camera clocks share the sensor elapsed-realtime domain; UNKNOWN clocks are rejected, not calibrated from delayed callback arrival. See [CameraCharacteristics](https://developer.android.com/reference/android/hardware/camera2/CameraCharacteristics).
- Pose history SLERPs bracketed sensor quaternions at the exposure midpoint, including rolling-shutter skew in the readout interval. Require coverage across the interval, bounded interpolation gaps and low angular motion. Stale/missing/moving samples reject that exposure.
- Intrinsics use `LENS_INTRINSIC_CALIBRATION` when present, correctly translating its pre-correction origin and the effective crop. Otherwise use focal length, physical sensor size and pixel dimensions; this lower-confidence fallback is recorded. Crop/stream aspect matching uses one isotropic scale and centered crop, not independent fx/fy stretching.
- On this S23 calibration was approximately `[1639.2587, 1639.492, 1999.6646, 1471.399, 0]`, crop `[0,0,4000,3000]`. Camera metadata provided distortion but no correction-mode control. Software correction uses the actual calibration and Android Brown–Conrady coefficients, reordered for OpenCV. If HAL correction is active, no second software correction is applied.
- `JPEG_ORIENTATION=0`; native preprocessing physically corrects and rotates pixels. K and pose rotate with the saved pixel axes. S23 portrait output is 3000×4000. Unit tests cover 90/180/270° cases; a real JPEG passed native correction/rotation and dimension checks.
- TextureView already applies sensor mount orientation. Its transform compensates aspect stretch and display rotation without double-applying the sensor rotation. See [Camera2 preview](https://developer.android.com/media/camera/camera2/camera-preview). Visual horizon/orientation inspection during a complete capture is still required.

Metadata preserves existing fields (`index`, `targetId`, target angles, transform, K, image/pixel sizes, timestamp, file). New optional fields include `poseSource`, exposure duration and diagnostics. New sensor captures use `sensors:android`; ARCore uses `arcore`. Missing legacy provenance decodes as ARCore. Mixed/unknown provenance is rejected; sensor mode is never inferred from shot count or filenames. JNI sends `sensorPoses=true` only for sensor metadata, false for ARCore.

## Build and tests

Prerequisites: Flutter, JDK 17+ (this Mac uses Android Studio's bundled JBR), Android SDK, NDK `28.2.13676358`, CMake `3.22.1`.

```sh
# From mobile; installs ignored, checksum-verified official OpenCV Android SDK.
sh tool/pano/setup_android.sh
flutter pub get

# Normal application ID and existing signing policy.
flutter build apk --release --target-platform android-arm64

# Opt-in separate debug test app; leaves an existing differently signed app intact.
cd android
./gradlew -PpanoDeviceTest=true -Ptarget-platform=android-arm64 \
  :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest
cd ..
adb install --user 0 -r build/app/outputs/apk/debug/app-debug.apk
adb install --user 0 -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w \
  uz.kadastr.kadastr.astra.test/androidx.test.runner.AndroidJUnitRunner
flutter test
flutter analyze
git diff --check
```

OpenCV is the official 5.0.0 Android 16-KiB-page-fixed SDK, SHA-256 `43ab9792096a4e52e97024913bb21c71a8adb884acbe0ddec3190a00b38b6619`. The setup script pins/downloads/verifies it. JNI uses 16-KiB ELF page alignment. Test fixture C++ is packaged only with the opt-in device-test property. Use that property for debug tests only; normal Release builds exclude it. The separate `.astra` build skips Firebase configuration tied to the production package; this does not validate push/login behavior.

The installed production app rejected the initial debug update due to a signature mismatch. It was **not** uninstalled or cleared. A separate `uz.kadastr.kadastr.astra` debug app and its instrumentation package were installed successfully instead. Existing production signing configuration was not changed. An APK compile success is not a Play distribution/signing certification.

### Completed validation

| Check | Result |
|---|---|
| Android JVM tests | 36 passed, zero failures/errors/skips |
| Flutter regression suite | 345 passed, 2 existing fixture-related skips |
| Changed Dart files analysis | Clean |
| Full Flutter analysis | 32 existing findings (4 warnings, 28 info); not a clean full-project analysis |
| Debug APK, instrumentation APK, JNI/C++ | Built successfully |
| Normal arm64 Release APK including R8 | Built successfully; final run 48 s |
| Android lint | 5 pre-existing errors, 47 warnings; no remaining capture API/back-dispatch errors |
| Final S23 camera, native fallback and preview/cancel tests | 3 passed, 13.107 s |
| Separate S23 synthetic 17-frame HQ MVS test | 1 passed, 105.34 s including fixture/setup |
| Whitespace | `git diff --check` passed |

JVM coverage includes opaque/direct/logical camera selection and fallback; grid; gravity/quaternion/coordinate conversion; roll/pole/speed/dwell gates; REALTIME/missing/stale/gapped exposure poses; intrinsics crop/scaling/fallback/rotations; legacy metadata and explicit routing; zero translation and malformed/mixed input rejection. Flutter coverage includes capability/mode/fallback and existing cancel/retry/retake/upload/listing regressions, plus decoded-image-only preview acceptance.

Final physical camera test acquired an actual JPEG, matched JPEG and sensor exposure timestamps, bracketed it in live motion history and ran calibration-aware native correction/rotation. Exposure in the earlier observation was 16,667,400 ns. Activity smoke verifies a delivered SurfaceTexture frame and cancellation. These tests do not simulate completing 17 physical aim targets.

Remaining lint errors are unrelated existing `MediaStore.Downloads` API-29 access and `forceDarkAllowed`/`windowLayoutInDisplayCutoutMode` resource API guards. Other warnings include existing Gradle 9 deprecations, Flutter/Kotlin migration notices and shared-core OpenCV deprecation warnings. These were not addressed through unrelated edits.

### Measured S23 processing

The HQ fixture uses **17 synthetic 1008×756 input images**, a textured sphere and a known 15 cm camera pivot. It is an algorithm/device benchmark, not a 12-megapixel real-room workload.

| Measurement | Observation |
|---|---|
| Output | 6144×3072, valid panorama and preview |
| Core processing | 103.84 s |
| BA / MVS / stitching | 6.45 / 71.48 / 25.91 s |
| Depth support | 17 frames, depth-reprojection, no rotation fallback |
| Median residual | 1.186 → 0.160 px |
| Coverage reported by core | 0.9333 |
| Sampled peak PSS / RSS | 1490.545 / 1571.023 MiB |
| Sampled AP / skin temperature | 43.1–58.5 / 36.9–39.0 °C |
| Android thermal status | 0 in all samples; no reported throttling or process kill |
| Battery | USB charging; discharge impact cannot be concluded |

The weak four-frame fixture produced valid 1024×512 outputs using `rotation-fallback` for insufficient triangulated observations. Corrupt/truncated input was rejected. No automatic resolution reduction was introduced based on these passing tests. **Real 12 MP capture peak memory, repeated HQ runs, responsiveness and thermal stability still need measurement.** A lower explicit preset can be evaluated if those measurements show HQ is unsafe.

Local detailed logs and test XML are retained under ignored `build/android-astra-validation/`; APKs are under `build/app/outputs/apk/`. These generated files are not committed artifacts.

## Required hands-on acceptance (not completed)

Use the separate `.astra` app with a legitimate test login/draft. Physical camera movement and scene selection require the phone operator; no automated test here substitutes for them.

1. Enter Bozor AI → add listing → description → add 360. Confirm automatic ultra-wide selection and visually confirm the field of view.
2. Complete all 17 targets including zenith, then repeat in a different acquisition order. Check aim/dwell, fast movement rejection, roll rejection and pole behavior by hand.
3. Exercise undo/recapture, confirmed early finish, cancel, background/interruption, retry processing, retake and resumed draft. Inspect saved JPEG orientation and target/pose/K consistency for the actual captures.
4. Process actual 12 MP source sets at 6144 HQ. Record time, sampled PSS, thermal status and responsiveness; repeat to assess accumulated heat. Decide any lower preset from these measurements.
5. Accept preview → return to description → reopen full panorama; upload; resume draft; submit/edit listing; replace/delete panorama; repeat with multiple ordered/named rooms. Check remote viewer and existing tour hotspots/coordinates. Backend/network integration on the S23 has not been exercised in this task.
6. Capture a textured room, plain walls, white ceiling, windows, mirrors, close furniture, doorway edges, moving person, low light, intentionally incomplete coverage and slight translation. Inspect seams, straight walls, ceiling/floor, objects/reflections, poles/nadir/logo, exposure, missing areas and ghosting. **No real-scene visual-quality verdict is available yet.**

ARCore fallback remains in place. Its geometry/unit and Flutter selection contracts are covered, but physical ARCore capture, logical-only camera devices and phones reporting UNKNOWN clocks have not received full on-device acceptance.

## Exact files for this Android change

Paths below are relative to `mobile`; other dirty files belong to the pre-existing work.

Modified:

- `android/.gitignore`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/MainActivity.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/PanoCaptureActivity.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/PanoTargets.kt`
- `lib/features/panorama/data/pano_capture_channel.dart`
- `lib/features/panorama/screens/pano_tour_screen.dart`
- `test/features/panorama/pano_capture_channel_test.dart`

Added:

- `android/app/src/main/cpp/CMakeLists.txt`
- `android/app/src/main/cpp/uy360_jni.cpp`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/CaptureGeometry.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/CaptureMotion.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/GyroIntegrator.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/NativeStitcher.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/PanoProcessingService.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/PanoStorage.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/PoseMath.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/UltraWideCamera.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/UltraWideCaptureActivity.kt`
- `android/app/src/main/kotlin/uz/kadastr/kadastr/pano/UltraWideSelection.kt`
- `android/app/src/test/kotlin/uz/kadastr/kadastr/pano/AstraGeometryTest.kt`
- `android/app/src/test/kotlin/uz/kadastr/kadastr/pano/GyroIntegratorTest.kt`
- `android/app/src/test/kotlin/uz/kadastr/kadastr/pano/PanoStorageTest.kt`
- `android/app/src/test/kotlin/uz/kadastr/kadastr/pano/PoseMathTest.kt`
- `android/app/src/androidTest/cpp/fixture_generator.cpp`
- `android/app/src/androidTest/kotlin/uz/kadastr/kadastr/pano/PanoDeviceTest.kt`
- `lib/features/panorama/screens/pano_preview_screen.dart`
- `test/features/panorama/pano_preview_screen_test.dart`
- `tool/pano/setup_android.sh`
- `docs/android-astra-0.5.md`
