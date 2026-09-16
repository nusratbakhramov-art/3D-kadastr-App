# Astra 0.5 migration file audit

Snapshot: 2026-09-16. Paths are relative to the `mobile` repository.

## Remaining migration completed in this pass

Compared against file hashes taken before the final end-to-end work; earlier
approved stages were already present in the working tree. No commits or pushes.

| File | Change |
|---|---|
| `assets/i18n/bundle.json` | Modified |
| `docs/astra-0.5-migration-files.md` | Added |
| `docs/panorama-360-plan.md` | Modified |
| `docs/panorama-360-status.md` | Modified |
| `ios/Runner/AppDelegate.swift` | Modified |
| `ios/Runner/CaptureGeometry.swift` | Modified |
| `ios/Runner/PanoCapture.swift` | Modified |
| `ios/Runner/PanoStitch.swift` | Modified |
| `ios/Runner/PanoTour.swift` | Modified |
| `ios/Runner/PanoUltraWideCapture.swift` | Modified |
| `ios/RunnerTests/PanoStitchTests.swift` | Modified |
| `ios/RunnerTests/PanoUltraWideCaptureTests.swift` | Modified |
| `lib/features/bozor/feed/bozor_listing_detail_screen.dart` | Modified |
| `lib/features/bozor/screens/bozor_description_step_screen.dart` | Modified |
| `lib/features/bozor/widgets/media_upload_row.dart` | Modified |
| `lib/features/panorama/data/pano_capture_channel.dart` | Modified |
| `lib/features/panorama/render/pano_sphere.dart` | Modified |
| `lib/features/panorama/screens/pano_capture_flow.dart` | Modified |
| `test/features/bozor/bozor_description_pano_test.dart` | Modified |
| `test/features/bozor/pano_server_media_test.dart` | Modified |
| `test/features/panorama/pano_capture_channel_test.dart` | Modified |
| `test/features/panorama/pano_capture_flow_test.dart` | Modified |
| `test/fixtures/panorama/README.md` | Added |
| `test/fixtures/panorama/pano_32.jpg` | Added |
| `test/fixtures/panorama/pano_6144.jpg` | Added |
| `tool/pano/README.md` | Modified |

The changes to `CaptureGeometry.swift`, `media_upload_row.dart` and
`pano_sphere.dart` in this pass are documentation comments only.

## Earlier-stage work retained unchanged in this pass

These files were already modified/added before this pass and retain exactly
their starting bytes. This includes the user’s existing `pubspec.yaml` edit.

- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner/Info.plist`
- `ios/Runner/PanoCore/UyStitcher.h`
- `ios/Runner/PanoCore/UyStitcher.mm`
- `ios/Runner/PanoCore/uy360_ba.cpp`
- `ios/Runner/PanoCore/uy360_ba.hpp`
- `ios/Runner/PanoCore/uy360_mvs.cpp`
- `ios/Runner/PanoCore/uy360_mvs.hpp`
- `ios/Runner/PanoCore/uy360_pipeline.cpp`
- `ios/Runner/PanoCore/uy360_pipeline.hpp`
- `ios/Runner/PanoCore/uy360_stitch.cpp`
- `ios/Runner/PanoCore/uy360_stitch.hpp`
- `ios/Runner/PanoCore/uy360_types.hpp`
- `pubspec.yaml`
- `ios/Runner/PanoCore/uy360_planar.cpp`
- `ios/Runner/PanoCore/uy360_planar.hpp`
- `ios/Runner/PanoCore/uy360_structural.cpp`
- `ios/Runner/PanoUltraWideCaptureView.swift`
- `ios/RunnerTests/CaptureGeometryTests.swift`
- `ios/RunnerTests/PlanarGeometryTests.mm`
- `ios/RunnerTests/StitchingTests.mm`
