# Android Astra parity audit — 2026-09-18

Compared standalone `360-astra-0.5` at `62887a5` (`astra-android`) with mobile
at `b74d0a2` (`master`). This audit concerns the production Android Astra 0.5
capture/processing path, not all historical features of the standalone app.

## Missing production changes ported

| Change | Mobile implementation |
|---|---|
| Wait for exposure/white balance to settle, request supported locks, confirm locks before shooting | `UltraWideCaptureActivity.kt` |
| Persist actual AE/AWB lock flags, ISO, precise exposure duration, calibration and timestamp diagnostics | `UltraWideCaptureActivity.kt`, `PanoTargets.kt` |
| Retain diagnostics after metadata reload; preserve legacy missing `poseSource` as measured ARCore | `PanoTargets.kt`, `PanoStorage.kt` |
| Bypass overlap gain compensation only for verified consistent Android sensor exposures | `PanoStorage.kt`, `NativeStitcher.kt`, `uy360_jni.cpp` |
| Require all sensor cameras to have triangulated support before Android depth reconstruction | `uy360_pipeline.*`, Android JNI opts in |
| Keep adequately supported BA rotations but discard invented translations when depth is unsupported | `uy360_pipeline.cpp` |
| Match the sensor nadir logo cap to the existing unphotographed cap | `uy360_jni.cpp` |
| Save native support counts, observations, fallback reason, gain mode and stage timings | JNI, `NativeStitcher.kt`, `PanoProcessingService.kt` |
| Native pixel, unsupported zenith, camera-lock and source-preserving dataset replay regressions | Android instrumentation tests, JVM metadata tests, iOS shared-core test |

All twelve production `core/uy360*` C++ source/header files now match standalone
byte-for-byte. JNI matches after its required Java package-symbol substitution.
The strict depth policy remains opt-in: iOS does not enable it.

## Already present

- Required 17-target ultra-wide grid: eight horizon, four +52°, four −52°,
  one zenith (89° numerical pole avoidance), same order and IDs.
- Physical ultra-wide selection, Camera2 JPEG acquisition, gyro integration,
  exposure-midpoint pose interpolation, roll/pole gating, crop/rotation-aware
  intrinsics and JPEG orientation/distortion handling.
- Camera geometry, motion, selection and camera discovery match standalone
  after package/import changes; pose math and gyro integration differ only in
  formatting/comments.
- Shared stitching, BA, MVS, planar and structural code was already identical.
- Sensor HQ output at 6144×3072, transactional JPEG publication and validation.
- Mobile capability routing, ARCore fallback, Flutter preview, uploads, rooms,
  drafts and viewer source handling remain mobile-specific integrations.

## Deliberate differences retained

- Standalone owns its capture library, settings, ZIP export and native viewer.
  Mobile uses the listing/draft flow and Flutter viewer; copying standalone
  screens or record storage would replace that integration.
- Standalone legacy capture offers configurable grids and sensor research modes.
  Mobile retains its existing measured-pose ARCore fallback.
- Mobile retains its in-process processing runner and does not reintroduce
  foreground-service permissions. Android can terminate that process while
  backgrounded; this port does not promise background-job durability.
- Metadata without `poseSource` means legacy ARCore in mobile, whereas standalone
  has a different legacy sensor default. That default must not be copied.
- Native results stay mapped to the existing Flutter channel response. Richer
  diagnostics are stored locally without changing listing/API payloads.

## Unfinished research is not a missing shipped feature

Standalone `android/XONA_NEAR_FIELD_INVESTIGATION.md` explicitly records that
no tested local-alignment experiment met the combined seam-improvement and
straight-architecture requirement. Dense flow, alternate matchers, calibration
changes, seam experiments and forced depth were not promoted to production.
Those ignored prototypes are not included here. Near-field ceiling/floor tears,
ghosts and reconstruction nondeterminism remain known limitations in both apps.

Tests/build results are reported with this change. Passing native processing
does not establish visual quality or replace fresh physical-device captures.
The marketing version/build number and existing AAB are not updated by this port.

## Validation for this port

- Android Debug and Release builds passed; instrumentation APK compiled.
- Android JVM tests: 39 passed in both Debug and Release.
- Flutter panorama/listing regression suite: 345 passed, two schema-fixture skips.
  The draft-resume test initially failed even in isolation: its second scenario
  began while the first route was still closing. Waiting for that transition in
  the test fixes the failure; production Flutter code was not changed.
- Targeted Dart analysis passed, including the adjusted test.
- iOS simulator: all 81 Runner tests passed, including shared-core stitching,
  the new sensor-support policy regression, capture geometry and viewer tests.
- Android full lint: five errors and 47 warnings. The errors are in untouched
  `MainActivity.kt` Downloads API usage and `values*/styles.xml` API-level
  attributes; they are not suppressed or changed by this port.
- The S23 was initially visible but disconnected before test APK installation.
  Physical camera-lock, JNI pixel and saved-capture replay tests are included
  and compile, but were not run on the device during this port.
- `git diff --check` passed. No version bump, commit, push or store upload.

---

# Second port — 2026-09-24 (rotation-only BA for sensor captures)

Compared mobile at `ea4b272` with the standalone **working tree** (branch
`astra-android`, HEAD still `62887a5`). Mobile matched standalone's committed
core byte-for-byte, so everything below came from standalone's UNCOMMITTED
work — that is what "stale" meant here, not a missed commit.

## Ported

| Change | Files |
|---|---|
| Rotation-only camera graph: per-pair RANSAC rotation consensus over unit bearings, synchronised across the graph, solved separately from the joint BA | `uy360_ba.hpp`, `uy360_ba.cpp` |
| Pipeline passes the rotation-graph options through and uses those rotations when the stitch is rotation-only | `uy360_pipeline.cpp` |
| `BAOptions::stableMatching` — isolates randomized matching from caller RNG history | `uy360_ba.hpp`, `uy360_ba.cpp` |
| BA geometry / MVS confidence diagnostics in the native result JSON | `uy360_ba_diagnostics.hpp` (new), `uy360_jni.cpp` |
| Android opt-in: `popt.ba.rotationGraph = popt.sensorPoses` | `uy360_jni.cpp` |

Why it matters here: Android's production ultra-wide capture is a sensor
(gyro/accelerometer) capture with no measured translation. The joint solve
fitted every rotation together with a translation that the rotation-only
stitch then throws away, so the rotations it kept no longer described a pure
pivot. The graph solves rotations on their own.

The four core files are byte-identical to standalone again. `rotationGraph`
and `stableMatching` default to `false`, and only the Android JNI turns them
on, so **iOS processing is unchanged** — the same rule the first port followed.

## Deliberately NOT ported

The rest of standalone's uncommitted work is the dense-capture experiment and
its instrumentation, which `ANDROID_360_AGENT_HANDOFF.md` records as unvalidated
and requires to stay isolated:

- `UltraWideCaptureMode`, the 29-shot `TargetGrid.ultraWideDense()` grid, the
  `ultrawide_dense` pose mode, its settings entry, strings and routing;
- the `denseExperiment` JNI/`NativeStitcher` parameter and
  `PanoStorage.isDenseExperiment` (mobile keeps its 17-shot signature);
- `CapturePoseHistory.exposureTrace`, `captureMode` / `expectedTargetCount` /
  `exposurePoseTrace` metadata, the ARCore rig-transform and exposure-timing
  probes, and the research markdown.

Mobile therefore still ships exactly the 17-shot production grid.

## Validation for this port

- `:app:externalNativeBuildDebug` — BUILD SUCCESSFUL; `uy360_ba.cpp.o` rebuilt
  for arm64-v8a, armeabi-v7a and x86_64, `libuy360.so` relinked.
- `:app:testDebugUnitTest` — 39 tests, 0 failures.
- iOS `RunnerTests/StitchingTests` on the 16e simulator — 14 tests, 0
  failures, including standalone's own new diagnostics test, ported here
  (`testBAGeometryDiagnosticsSerializeGraphsAndUnscaledPositions`). It is
  the ONLY iOS-side change in this port: the shared core compiles on both
  platforms, so a broken diagnostics format must fail on both.
- NOT verified: a real room capture on hardware. The rotation graph is new in
  standalone too and has no regression test there; standalone's own handoff
  says its quality target is unverified. Treat the visual result as unproven
  until an S23 capture is compared against one from the previous build.
