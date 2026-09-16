# Panorama JPEG fixtures

These are generated test images, not captured photos or third-party assets.
Each contains a red left half and blue right half, encoded with macOS AppKit
`NSBitmapImageRep` as an RGB JPEG at quality 0.85.

- `pano_32.jpg`: 32×16, for preview/resume/output-validation widget tests.
- `pano_6144.jpg`: 6144×3072, for full-resolution multipart upload contract tests.

Both have the production 2:1 panorama aspect ratio. The large fixture verifies
that the client uploads the original bytes; it does not demonstrate stitching
quality or physical-camera performance.
