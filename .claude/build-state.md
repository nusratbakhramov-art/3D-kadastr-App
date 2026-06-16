# Build State — RoomScan pipeline port (RoomScanPlanAI → kadastr)

## Goal
Make scan + texturing work like the RoomScanPlanAI project (a proven native
iOS LiDAR scanner) and produce a final high-quality textured 3D model — while
KEEPING kadastr's Flutter UI and MethodChannel bridge unchanged.

Source project: /Users/macshop/Documents/RoomScanPlanAI (native Swift, RoomPlan +
LiDAR depth + per-triangle atlas texturing with mesh-depth occlusion). Its
texturing was just fixed so furniture renders as solid 3D (mesh-depth occlusion
+ normal-gated shell drop), not a flat colour smear.

## Why port BOTH capture and texturing
RoomScanPlanAI's texturing (`RoomShell.fuse`) depends on `room.json` (RoomPlan
parametric walls/floor) and the scanNNN/{frames,depth,manifest} layout produced
by RoomScanPlanAI's CAPTURE. So capture must be ported too — texturing can't run
on kadastr's anchors.bin format.

## Decision: non-destructive replace
Keep kadastr's existing native pipeline files (TSDF / xatlas / MetalAtlasBaker /
AutoProcessRunner) in the repo, but route the EXISTING MethodChannels
(`kadastr/room_plan_scanner` startTexturedScan, `kadastr/saved_scans` process/
list/outputPath/previewModel) to the ported RoomScanPlanAI pipeline instead.
Flutter UI + bridge contract unchanged. Reversible via git.

## Why NOT fix kadastr's own pipeline
It is architecturally more advanced (GPU TSDF, xatlas, Metal multi-band atlas,
ESRGAN) but its atlas baker occludes against the RAW LiDAR depth (20cm tol, soft
penalty) — the exact class of bug that made RoomScanPlanAI smear. RoomScanPlanAI's
pipeline is already fixed + verifiable headlessly, so porting it is faster than
re-deriving the fix inside the Metal kernel.

## Phases
- [x] **1. Texturing port + headless harness** — DONE.
      Ported pure pipeline → `ios/Runner/RoomScan/` (17 .swift). macOS harness →
      `Tools/ScanCheck/` (Package.swift + Sources/scancheck/main.swift +
      check.sh, mirrors RoomScanPlanAI's Tools/MeshCheck). Verified on a real
      scan (RoomScanPlanAI scan003): builds, renders the same solid 3D sofa.
      Run: `Tools/ScanCheck/check.sh <scanFolder> _check --atlas --look --cameras N`
- [ ] **2. Capture port** — RoomCaptureView (RoomPlan) + ARSession depth/photo
      polling + CoverageGrid green-wireframe overlay + RoomScanRecorder writing
      the scanNNN/{frames,depth,manifest,room.json} format. From
      RoomScanPlanAI/Capture, Scanning, UI/RoomCaptureScreen, UI/CoverageOverlayView.
- [x] **3. Wire to kadastr UI/bridge** — DONE, COMPILES (simulator build green).
      `ios/Runner/RoomScan/RoomScanBridge.swift` routes the existing channels:
      `room_plan_scanner/startTexturedScan` → presents `RoomCaptureScreen`
      (UIHostingController, with an `onFinished:(String?)->Void` callback added),
      saves via RoomScanRecorder, returns {savedScanId, mode:"saved_raw",...};
      `saved_scans` list/get/process/outputPath/delete/viewLidarMesh → ScanStore +
      TexturingService (atlas.usdz). ID map N⇄"scanNNN". createdAt = epoch SECONDS
      (Dart does *1000). AppDelegate: startTexturedScan + the saved_scans switch
      route to the bridge (debug-log helpers kept). Capture types guarded
      `@available(iOS 17, *)` (app stays at deployment 15.0); DeviceCapability
      .supportsRoomPlan guarded `#available(iOS 16)`. Files added to the Runner
      target via `ios/add_roomscan.rb` (xcodeproj gem). NO type-name collisions
      with kadastr's own native scan code.
- [ ] **4. Device build, scan, verify, polish** — NEXT. Needs a LiDAR device
      (live RoomPlan capture can't run in the Simulator). Flow to test:
      AI Baholash → scan (RoomPlan + green coverage wireframe) → "Tugatish" →
      toast "Skan saqlandi" → Profil → Mening skanlarim → process → view USDZ.
      Verify: 3D objects solid (mesh-depth occlusion), walls clean.

## Round 2 (quality + wireframe) — IN PROGRESS
User: result quality is bad (blurry walls/objects, **sofa & soft objects merge INTO the wall**), and the green wireframe is unclear. Pulled the latest device scan to `_kadastr_scans/scan002` (168 frames, big room) and tuned headlessly.

Diagnosis (harness, scan002):
- **Objects merge into wall** = RoomShell drop was too aggressive: it replaced furniture surfaces near+parallel to a wall/floor with the clean quad, so low/flush objects (futon, beanbags) lost their volume. `removeSmallComponents` was NOT the cause (only −111 tris).
- **Blur/ghosting** = (a) per-texel blend was a plain average across views (ghosting), (b) atlas texel density on a big room.

Fixes (all in `ios/Runner/RoomScan/`, validated on harness):
- **RoomShell.fuse** drop loosened: wall near 0.08→**0.04**, floor 0.12→**0.05**, parallel gate 0.6→**0.8** (env: KADASTR_WALL_NEAR / KADASTR_FLOOR_NEAR / KADASTR_PARALLEL). Keeps furniture volume; walls stay clean. shell tris 174k→296k, atlas 28k→40k.
- **ProjectiveSampler.sample** gained `peak` (weights^peak). **AtlasTexturer.Options.viewPeak=6** ⇒ best-view-dominant blend (crisp, not ghosted). `minObjectTriangles=8`.
- **AtlasTexturer maxAtlasSize 4096→5120** (~100 MB, sharper big-room walls).
- **TexturingService.textureMaxWidth** now adaptive: caps total keyframe RAM ~420 MB by frame count (was fixed 640) → a 167-frame room won't OOM. env KADASTR_TEX_W overrides.
- **USDZ export fixed earlier**: SceneKit `SCNScene.write` (ModelIO failed silently on device → empty QuickLook). `MeshExporter.exportAtlasUSDZSceneKit`.
- **Coverage overlay redesigned** (CoverageOverlayView + RoomScanRecorder.projectedCoverageEdges minCount): NOT-captured surface → translucent BLUE 20% (one Path, no darkening); captured (voxel views ≥3) → faint green wireframe. Legend: "ko'k joylar yo'qolguncha skanlang".
- New harness flags: `--peak --cell-texels --minc`, env RENDER_W (render canvas px — 512 was hiding atlas detail), KADASTR_TEX_W.

Result on harness (scan002): sofa is a distinct 3D object (not merged), boxes readable, walls clean. Pending: device verify + push improved scan002 result (device was briefly unavailable during build).

## Round 3 (wireframe = Polycam look + sharper texture)
User showed the Polycam capture overlay (fine WHITE triangle wireframe on scanned, BLUE on unscanned) and that our blue-DOTS overlay looked nothing like it.
- **Constraint found:** RoomCaptureSession does NOT emit ARMeshAnchors (mesh counter = 0), so we can't render Polycam's true reconstruction mesh — only the depth-coverage voxel grid. Overlay rebuilt from that to look as close as possible.
- **CoverageGrid voxelSize 0.08 → 0.05** (denser, more mesh-like).
- **CoverageOverlayView**: not-captured (voxel views < 2) → SOLID translucent BLUE (tiled 28px squares, one Path so no darkening — continuous skin, not dots); captured (views ≥ 2) → WHITE wireframe (was green). Legend already "ko'k joylar yo'qolguncha skanlang".
- **Texture sharper**: AtlasTexturer maxAtlasSize 5120→**6144**, targetCellTexels 24→**32** (~144 MB, atlas 6030 for scan002, 32 texels/tri). cam080 boxes now readable on harness.
- Perf risk: 0.05 voxels = more voxels to project each tick on a big room; revert to 0.06 if the live overlay lags. AR-mesh-anchors path is blocked (RoomPlan doesn't expose them); a GPU depth-mesh overlay would be the next step for exact Polycam fineness.

## Round 4 (FLAT surfaces — plane-SNAPPING, not substitution)
User goal sharpened: needs FLAT clean surfaces + sharp ("tekis yuza va tiniq"); USDZ optional (in-app view is fine). Device showed SPIKY/faceted walls+floor+furniture. Ran a Workflow (diagnose+extract+design) → spec.
- **Root cause:** the loosened plane-SUBSTITUTION drop kept noisy depth walls *next to* the clean quad (spiky), and there was NO smoothing pass anywhere.
- **Fix = replace substitution with plane-SNAPPING + object-only smoothing** (RoomShell.fuse rewritten):
  - `fuse` now returns `(mesh, snapped:[Bool])`. Per vertex: find nearest RoomPlan plane it's within ±band(0.03) AND parallel to (|n·planeN|≥0.85); snap those onto the plane (graded feather) → dead-flat walls, mesh stays CONNECTED so furniture is never deleted. Planes with <200 votes (unscanned/ceiling) still get a substituted quad. env: KADASTR_SNAP_BAND/_FEATHER/_DOT/_VOTES.
  - `MeshCleanup` gained `removeSpeckle` (clamp stalactite outlier verts), `taubinSmooth` (λ0.5/μ-0.53, edgeSharpness 12, **skip mask** so snapped walls stay flat), `buildAdjacency`, `recomputeVertexNormals`.
  - Pipeline (TexturingService.resolveGeometry + harness): DepthMesher → removeSpeckle(5) → RoomShell.fuse(snap) → taubinSmooth(iters3, edgeSharp12, skip:snapped) → AtlasTexturer (area-proportional cells, 6144).
- **Verified on harness (scan002):** textured orbit shows FLAT smooth walls+floor, no spikes, sofa/beanbags/boxes kept as 3D, tri count preserved (~660k, snapping deletes nothing). atlas 6144/58k tris, USDZ 36MB.
- Harness tuning env: KADASTR_SPECKLE / KADASTR_TAUBIN / KADASTR_EDGESHARP, plus the SNAP_* above; RENDER_W for render canvas px.
- Perf note: smoothing 291k verts w/ Set adjacency adds ~6-8s on Mac (~15-25s device) — acceptable one-time. If it lags, switch buildAdjacency to CSR flat arrays.
- AtlasTexturer also now AREA-PROPORTIONAL (cell edge ∝ √area) so walls+objects get uniform texel/m² (sharper walls). maxAtlasSize 6144, viewPeak 6 (best-view blend), minObjectTriangles 8, textureMaxWidth memory-adaptive.

## ✅ WORKING CONFIG (user-confirmed "natija yaxshi", 2026-06-15 ~07:52, scan005 in sim)
The combination that finally produced a good, flat, RoomScanPlanAI-grade result:
1. **Geometry (TexturingService.resolveGeometry):** DepthMesher → VoxelWelder.weld(0.02 pre-decimate) → MeshCleanup.removeSpeckle(5) → **RoomShell.fuse = plane-SNAPPING** (band **0.07**, feather 0.02, normalCos **0.75**, minVotes 200 → walls snap dead-flat onto RoomPlan planes, furniture protected by normal gate, mesh stays connected) → MeshCleanup.taubinSmooth(iters 3, edgeSharpness 12, skip:snapped).
2. **Texture (AtlasTexturer):** area-proportional cells, maxAtlasSize 6144, viewPeak 6 (best-view blend), minObjectTriangles 8. textureMaxWidth memory-adaptive (~280 MB cap → 560–1024 px).
3. **VIEWER = RoomScanPlanAI's direct atlas viewer, NOT USDZ.** `RoomScanBridge.presentResultViewer` loads `result/atlas.geo` + `result/atlas.png` via AtlasIO.read → AtlasSceneBuilder.makeNode → `SceneKitModelViewerController(scene:)`. AppDelegate `previewModel` routed to the bridge. (RoomScanPlanAI confirmed: it views atlas.geo+png in-app SceneKit; USDZ is best-effort export only. No USDZ round-trip = crisper.)
4. **Process works on device** (debug log: process START→DONE 13-21s; it was NEVER crashing — "ishlamadi" meant bad quality / Debug-slow sim). Native built with **SWIFT_OPTIMIZATION_LEVEL=-O** even in Debug (set on Runner target) so sim texturing is fast too. `flutter build ios --simulator` is Debug-only ("Release not supported for simulators") — the -O override is what makes sim processing usable.
5. **Sim iteration loop:** seed scans into the sim container (simctl get_app_container data → Documents/Scans); to push a quality change WITHOUT a rebuild, re-bake on the harness and copy rt.geo/rt.png → the sim's scanNNN/result/atlas.geo+png, then re-open v1 in the app.

Device deploy state at this point: device still had band 0.03 + USDZ viewer (older); deploying the WORKING config to device next.

## How to test
- Headless texturing (Mac, no device): `Tools/ScanCheck/check.sh <scanFolder> _check --atlas --look --cameras N`
- Native compile check: `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination 'id=<sim>' CODE_SIGNING_ALLOWED=NO build`
- Device: `flutter run` (or build+install) on a LiDAR iPhone, then walk the scan flow above.

## Ported files now in repo
- `ios/Runner/RoomScan/` — AtlasTexturer, DepthMesher, MeshCleanup,
  ProjectiveSampler, RoomShell, VoxelWelder, TexturingService, AtlasSceneBuilder,
  VertexColorTexturer, ProjectiveTexturer, ScanModels, MathHelpers, AtlasIO,
  GeometryIO, ScanRecord, ScanStore, MeshExporter.
- `Tools/ScanCheck/` — headless macOS verifier (NOT shipped in the app).

## Key bridge contract to preserve (Flutter side, do NOT change)
- `kadastr/room_plan_scanner`: startTexturedScan → returns {savedScanId, mode:"saved_raw", floorAreaSqm, walls,...}; previewModel{filePath}.
- `kadastr/saved_scans`: list / get{id} / process{id,params} / outputPath{id,version} / delete{id} / viewLidarMesh{id}.
- USDZ shown via iOS QuickLook (previewModel).
