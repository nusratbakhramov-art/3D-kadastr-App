# iOS 360 panorama — Astra 0.5 integration

Implementation/validation snapshot: **2026-09-16**, `mobile` branch `master`.
Astra reference: `360-astra-0.5`, branch `astra-0.5`, commit
**`3de962b2de43580a249dfa17eb85dc493f62f9d6`**. The twelve core C++/header
files and two Objective-C++ bridge files match that source. The source checkout
was read-only during the migration.

The remaining code migration is complete and the relevant automated suites pass.
**Physical ultra-wide validation pending.** Authenticated live backend upload,
listing creation and listing edit acceptance also remain pending.

## Production flow

```text
Bozor AI → add listing → description/Step 6 → 360 foto qo'shish
  → PanoCaptureChannel.startPreferred
  → ultra-wide/CoreMotion when available, otherwise compatible ARKit
  → persistent JPEG frames + meta.json in Application Support/pano/<uuid>
  → PanoStitchCoordinator → UyStitcher.mm → Astra C++/OpenCV
  → validated pano.jpg + preview.jpg
  → existing Kadastr preview / accept or retake
  → POST /api/v1/listings/media, role=panorama, one finished pano.jpg
  → storage key + URL → existing room/draft/listing submission
```

New captures are processed on the iPhone. Source frames and metadata are never
uploaded by this flow. `PanoApi`, `PanoJobWatcher` and `PendingPano` remain for
legacy `job:<id>` drafts; they are not the new-capture processing path. Android
has no native Astra processing port and is outside this iOS migration.

## Capabilities and compatibility

| Capability | Check and behavior |
|---|---|
| Ultra-wide capture | iOS 15.4+, rear physical ultra-wide camera, device motion, camera authorization not denied/restricted. A first-use permission prompt is handled at start. |
| Sensor processing | Independent `isSensorProcessingSupported` query; required before selecting ultra-wide. |
| ARKit capture | Independent `isARKitCaptureSupported`; iOS 15+, world tracking and usable camera authorization. |
| Native tour viewer | Independent `isViewerSupported`; iOS 16+, no capture hardware/permission dependency. The existing Dart tour remains the fallback. Native local result preview supports iOS 15+. |

Step 6 exposes capture when a usable mode exists and keeps existing rooms
accessible when capture is unavailable. Listing detail chooses its viewer using
viewer capability. `startPreferred` rechecks capabilities for each capture.

Legacy direct `start()` callers still default to ARKit. Production calls
`startPreferred()` and explicitly selects ultra-wide first. A hardware/OS/motion
capability failure before presentation can fall back to ARKit once; cancel,
permission denial, interruption or a failed active capture never silently starts
a second capture. No usable mode produces a controlled localized error.

## Capture contract

`PanoUltraWideCapture.swift` uses AVFoundation still photos and CoreMotion at
60 Hz with `xArbitraryZVertical`. It selects `.builtInUltraWideCamera` directly,
not a virtual multi-camera device. Saved JPEGs use landscape sensor pixels;
the portrait preview has its own orientation. Distortion correction is enabled
when supported, stabilization is disabled for the calibration video, and focus,
exposure and white balance are locked after the first accepted photo when supported.

`PanoTargetGrid.ultraWide17()` defines 17 unique required targets:

- Eight horizon targets at 45° yaw intervals.
- Four upper targets at +52° pitch, yaws 45°, 135°, 225°, 315°.
- Four lower targets at −52° with the same yaw offsets.
- One required near-vertical zenith at +89°, matching Astra's convention.

Acquisition order is independent of target IDs. A continuous 0.35-second dwell
requires aim within 6°, angular speed below 8°/s and roll below 12°. Roll is
unconstrained at the poles (`abs(forwardY) > 0.9`), where gravity cannot define it.
Undo removes the last accepted frame. Normal completion uses all 17 targets;
explicitly confirmed early finish is allowed with at least four accepted frames.
Cancel/background/session interruption tears down capture safely; a new motion
reference is never mixed into an existing capture.

Photo timestamps are converted from the capture-session clock to the host clock.
Pose history retains ten seconds of quaternion samples, interpolates with SLERP,
and rejects missing/stale samples, gaps over 100 ms, excessive speed and invalid
exposure-time aim/roll. Endpoint tolerance is 50 ms. Validation uses the photo's
exposure timestamp, not shutter-request or delegate-delivery time.

Video calibration is converted to photo pixels with one scale and a vertical
center-crop offset. Independent x/y stretching is not used. If video intrinsics
are unavailable, the existing Astra FOV-based estimate is used; that fallback
and lens calibration accuracy need device validation.

Each accepted frame records `poseSource: "sensors:coremotion"`, a column-major
camera-to-world transform with zero initial translation, intrinsics `[fx,fy,cx,cy]`,
actual JPEG width/height, target ID/angles and host-clock timestamp. JPEG and
metadata reach disk before the frame is accepted. Optional `poseSource` and
`exposureDuration` decode old ARKit metadata unchanged. Exposure duration is
currently omitted by both capture paths, matching Astra; the timestamp is present.

ARKit keeps its own grid: 28 required targets (12 horizon, 8 upper, 8 lower), plus
one optional zenith. Its measured poses, capture UX and metadata remain compatible.

## Processing and output

`PanoStitchCoordinator.ProcessingOptions` checks for the exact metadata marker
`poseSource == "sensors:coremotion"`. One such entry selects sensor processing;
frame count never selects it. Missing, `arkit` or unknown markers alone retain the
legacy route.

| Setting | Ultra-wide/CoreMotion | Legacy ARKit |
|---|---|---|
| `sensorPoses` | `true` | `false` |
| Default output | 6144×3072 | 4096×2048 |
| Processing | Sensor-aware bundle adjustment, high-quality MVS, current planar/structural processing | Existing `auto` / `mvs` / `fast` behavior |
| Low-support fallback | Rotation-only when image evidence cannot support translation/depth | Existing behavior |
| RAM selection | Sensor HQ default is preserved | `auto`: MVS at ≥5.5 GB RAM, otherwise rotation-only |

Explicit valid width overrides remain supported for tests/diagnostics. Production
omits the width, so saved metadata controls the default. Weak sensor reconstruction
still produces a panorama through the rotation fallback; the `mode` result reports
the selected pipeline (`mvs`), not proof that depth reconstruction succeeded.

Astra estimates camera motion from image features with sensor orientation priors,
then reconstructs depth using plane sweep when supported. Its planar/structural
stages regularize supported geometry. Depth-aware or rotation-only composition
projects into a 2:1 equirectangular image, blends seams and applies the existing
Kadastr nadir logo. The preview is 1024×512.

Outputs are first written into a per-run `.stitch-<uuid>` directory. Both JPEGs
must have valid JPEG markers, expected dimensions and a decodable thumbnail
before publication. Each file is atomically written; `pano.jpg` is published last
as the completion point. Normal failures remove the working directory and leave
source frames for retry. A process crash may leave a working directory until the
capture is later cleaned up.

Flutter also validates a saved panorama before resume/preview/upload. Truncated
outputs are restitched. Legacy valid pano-only drafts do not require a preview
file. Failed preview must be accepted before retry can upload. Missing upload
key/URL is an error and retains local data. Successful upload or explicit
retake/delete removes local files; failed best-effort cleanup can leave files on disk.

## Kadastr contracts preserved

The listing wizard, room titles/order, local and legacy drafts, upload endpoint,
storage keys, delete/replace behavior, listing edits, tour links, hotspot
conversion, existing renderers and nadir logo are retained. The draft keeps the
uploaded panorama's storage key in `panoramas`, URL in `panoramaUrls`, and uploaded
status in `uploadedMedia`; submission must not treat the key as a local filename.
New error strings are supplied in Uzbek, Russian and English through the existing
translation bundle and native strings map.

## Main implementation map

| Path | Responsibility |
|---|---|
| `lib/features/panorama/data/pano_capture_channel.dart` | Separate capabilities, production mode selection, channel contract and localized errors |
| `ios/Runner/AppDelegate.swift` | Native MethodChannel dispatch |
| `ios/Runner/CaptureGeometry.swift` | Metadata, target grids, pose history, pole/roll handling, crop-aware intrinsics |
| `ios/Runner/PanoUltraWideCapture.swift`, `PanoUltraWideCaptureView.swift` | AVFoundation/CoreMotion capture, file transaction and capture UI |
| `ios/Runner/PanoCapture.swift` | ARKit compatibility capture |
| `ios/Runner/PanoStitch.swift`, `PanoCore/*` | Metadata routing, Astra processing, validated output publication |
| `ios/Runner/PanoTour.swift` | Existing local preview and native tour |
| `lib/features/panorama/screens/pano_capture_flow.dart` | Capture → process → accept → upload, recovery and cleanup |
| `lib/features/bozor/screens/bozor_description_step_screen.dart` | Step 6, rooms and draft integration |
| `lib/features/bozor/feed/bozor_listing_detail_screen.dart` | Independent viewer selection |

See [astra-0.5-migration-files.md](astra-0.5-migration-files.md) for the exact
completion-stage file list and the already-present earlier-stage changes.

## Automated validation — measured 2026-09-16

Each functional stage passed focused tests before continuing. Final combined runs:

- `flutter test --no-pub test/features/panorama test/features/bozor --reporter expanded`:
  **341 passed, 2 skipped, zero failures**. The two existing schema-parity tests
  require absent `../kadastr-backend/tests/fixtures/mobile_param_schema.json`.
- Simulator `xcodebuild test`, all `RunnerTests`: **71 passed, zero failures**:
  CaptureGeometry 21, UltraWide 16, PanoStitch 11, PlanarGeometry 10,
  Stitching 12, Runner 1. Swift/Objective-C++ compiled as part of this run.
- Targeted Dart analysis: no issues in changed Dart files.
- All six C++ implementations plus `UyStitcher.mm`: seven arm64 iOS-simulator
  syntax checks passed. Existing OpenCV comma-initializer deprecation warnings remain.
- Xcode also reports existing dependency deployment-target and privacy-resource
  warnings; these are outside the panorama changes and did not fail the build.
- Xcode project and Info.plist lint passed; `git diff --check` passed.

Native coverage includes metadata compatibility, exact grid angles, stale/missing
pose rejection, crop intrinsics, roll/pole behavior, capture lifecycle, routing,
planar geometry, measured-pose ARKit processing, sensor reconstruction/fallback,
6144×3072 output, complete JPEG publication and Kadastr logo stamping.
Flutter covers the capability matrix, production Step 6 path, resume/retry,
preview acceptance, uploads, room ordering/names, delete/replace, drafts and
listing payload/edit regressions.

A deterministic 6144×3072 JPEG was sent through the real client multipart builder
into a mock HTTP endpoint: its bytes stayed unchanged, only `pano.jpg` was sent,
and key/URL handling passed. The live API's read-only OpenAPI schema confirms
media upload plus listing create/update contracts. This is **not** an authenticated
production upload or listing write. No production data was changed.

Re-run native tests with an installed simulator UUID:

```bash
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=iOS Simulator,id=<UUID>' \
  -only-testing:RunnerTests -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
plutil -lint ios/Runner.xcodeproj/project.pbxproj ios/Runner/Info.plist
git diff --check
```

## Before production release

- **Physical ultra-wide validation pending.** No available ultra-wide iPhone was
  connected; the listed iPhone XS was unavailable and has no ultra-wide camera.
- On a supported phone verify automatic Step 6 selection, physical 0.5× lens,
  all 17 targets/zenith, arbitrary order, aim/speed/roll/exposure-time rejection,
  undo, early finish, cancel/background/interruption, JPEG orientation,
  pixel intrinsics and saved metadata, sensor routing and final preview.
- Test plain walls, reflective surfaces, close/moving objects, incomplete capture
  and low light. Measure full 6144×3072 HQ processing time, peak memory,
  thermal behavior and UI responsiveness. Simulator/synthetic timings are not
  device benchmarks; no phone performance or memory claim is established.
- Use an authenticated test account to upload 6144×3072 output, submit/edit a
  listing, test multiple named/ordered rooms, delete/replace, draft recovery and
  tour hotspots against the live backend. Restore the missing schema fixture
  for the two skipped parity tests.
- Exercise first-use/denied camera permission and ARKit fallback on real older
  hardware/iOS. Minimum-iOS paths compiled but were not run on an iOS 15 device.

No commit or push was made. The pre-existing `pubspec.yaml` edit is preserved.
