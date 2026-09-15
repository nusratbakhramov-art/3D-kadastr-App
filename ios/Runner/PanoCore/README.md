# PanoCore — 360° panoramani TELEFONDA tikish yadrosi

MANBA: `/Users/macshop/360/core/` (Uy360 prototipi), commit `cf844d5`
(2026-09-13, "Revert core/iOS to the 1:48 on-device state"). Fayllar
O'ZGARTIRILMASDAN nusxalangan; `UyStitcher.{h,mm}` — `360/ios/Uy360/Native/`
dan. Yadroni yangilash = o'sha repodan qayta nusxalash (diff bilan).

Olinmagan: `cli/` (desktop), `apple/uy360_mvs_metal.mm` + `uy360_mvs_gpu*`
(Metal plane-sweep — manbada O'CHIQ, BA telefonda regress bergan).

Quvur: `stitchMVS` = BA (SIFT, 6-DoF) → plane-sweep MVS (chuqurlik) →
chuqurlik bo'yicha reproyeksiya + graph-cut chok + multi-band; yoki `stitch`
(faqat rotatsiya, tez). OpenCV — SwiftPM `yeatse/opencv-spm` 5.0 (calib3d YO'Q,
yadro unga bog'liq emas).

⚠️ Debug'da bu fayllar `-O2` bilan kompilyatsiya qilinadi (per-file flag):
`-O0` da yadro yaroqsiz darajada sekin.
