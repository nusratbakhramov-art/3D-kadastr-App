# 360° panorama — capture, tikish va ko'ruvchi (kadastr mobil ilovasi)

> **Manba:** `~/StudioProjects/panorama` loyihasi (branch `1.0.2` — UX, `1.0.1` — asos).
> ⚠️ **Unga TEGILMAYDI.** U faqat o'qish uchun manba; hamma kod shu repoda yoziladi.
>
> Tayyorlandi 2026-09-10. Manba tahlili: 12 agent, 2 tanqid raundi.
> Reja raqamlari tanqidchi tomonidan qayta hisoblangan (§10).

---

## 1. Qisqacha xulosa

Bozor sehrgarining «360 фото» qatori hozir faqat galereyadan rasm tanlaydi. Unga
qo'shiladi:

1. **Capture ekrani** — 76 kadr, sensor bilan yo'naltirish, avtomatik zatvor,
   panorama `1.0.2` dagi UX (nishon aylanasi + strelka + yashil halqa);
2. **Tikish** — equirectangular panorama, **sof Dart**, OpenCV YO'Q, isolate'da;
3. **360° ko'ruvchi** — pan/zoom/gyro;
4. Natija mavjud `role: panorama` yuklash quvuri bilan ketadi.

**Qabul qilingan qaror (foydalanuvchi):** to'liq sfera (76 kadr), tikish
ILOVADA, sof Dart. Backendga chiqarilmaydi.

---

## 2. ⚠️ SIFAT — nima kutish mumkin

### 2.1 Dastlabki ogohlantirish va uning TUZATILISHI

Boshida shunday deyilgandi: OpenCV olib tashlansa `refine` (SIFT bilan
burchak aniqlashtirish) yo'qoladi va natija `1.0.2` sifatiga yetmaydi.
Sensor burchagi 1–2° aniq, bu kanvasda **11–23 piksel** — aynan chok siljishi
o'lchami. Kodning o'z izohi: *«Registration, not blending, is what limits the
result»* (`sensor_stitcher.dart:1280` atrofi).

**Bu ogohlantirish endi asosan kuchini yo'qotdi.** Tahlil ko'rsatdiki
`_refineByFeatures` ning MATEMATIK YADROSI — `_solveFrame` (kichik-burchak
normal tenglamalari, Gauss-Seidel, `_anchorWeight=0.02` bilan gyroga tortish,
`_maxCorrectionRad=8°`) — **feature'lardan mustaqil**. Unga faqat `(a, b)` ray
juftliklari kerak.

Ularni SIFT o'rniga **NCC panjara korrelatsiyasi** bilan olish mumkin, va bu
qolip `1.0.2` da allaqachon bor (`_measurePair`: `matchTemplate` + `minMaxLoc`
+ `_subPixel` parabola).

| | SIFT + BFMatcher | NCC panjara (sof Dart) |
|---|---|---|
| Xarajat | Dart'da **15–50 min** + **1–3 soat** moslashtirish | **688 M MAC** |
| Real vaqt | amalda imkonsiz | **1.4–3.4 s** (1 yadro), **0.4–0.9 s** (4 isolate) |
| Tekis devor | `0dac253`: «has failed to find enough matches on every capture so far» | `sd < 5` → o'lchov TASHLANADI (bo'shliq o'zini xabar qiladi) |
| `_solveFrame` | — | **o'zgarmaydi**, verbatim |

Ya'ni sof Dart yo'li `refine` ni SAQLAB QOLADI. Qolgan farq — NCC va SIFT
o'rtasidagi aniqlik farqi, u o'lchanmagan.

### 2.2 Baribir qoladigan narsa

`cv.Stitcher` (OpenCV'ning tayyor bundle-adjustment quvuri, 12 chaqiruv)
takrorlanmaydi va tashlanadi. Ya'ni **zaxira yo'l yo'q**: sensor+NCC yo'li
sifatsiz chiqsa qaytadigan joy qolmaydi.

---

## 3. Algoritm — sof Dart yozish uchun spetsifikatsiya

Manba: `panorama` tag `1.0.2`, `lib/services/sensor_stitcher.dart` (3827 qator).

### 3.1 Konfiguratsiya

```
outputWidth = 3072  (→ 1536 balandlik, 8.5 px/daraja)   ← QAROR, §10.1
longSideFovDeg = 67.3   ⚠️ qurilmada TEKSHIRILADI, §10.4
refine = true (NCC bilan)   deform = false   routeSeams = true
seamPenalty = 0   blendPower = 16 (O'LIK — yoqilmasin)
kadr = 76
```

### 3.2 Koordinata konvensiyalari — buzilsa hech narsa ishlamaydi

**Dunyo:** o'ng qo'l, **Y yuqoriga**, identity kamera **+Z** ga qaraydi.

```
d.x = cos(lat)·sin(lon)
d.y = sin(lat)
d.z = cos(lat)·cos(lon)
```

**Kamera:** +Z oldinga, +Y yuqoriga → **kamera X o'qi CHAPGA**. Shu sababli
piksel→nur o'tishida **ikki minus** bor:

```
x = −(px − cx)/focal ;  y = −(py − cy)/focal ;  v = normalize(x, y, 1)
px = cx − focal·v.x/v.z ;  py = cy − focal·v.y/v.z
```

Bu **o'lchangan**: mos feature'lar bo'yicha median qoldiq shu belgilarda
**2.9°**, qolgan uch kombinatsiyada 37°, 43°, 30°.

**Fokus (piksel):** `focal = (max(w,h)/2) / tan(67.3°·π/360)`
→ koeffitsiyent **0.7511376**, `focal(3840) = 2884.37 px`,
`hFov(yarim kenglik 1080) = 41.055°`.

### 3.3 `rotationMatrix(ψ, θ, φ)` — world_from_camera

```
R = Ry(ψ) · Rx(−θ) · Rz(φ)        (Rx TESKARI belgi bilan — +pitch → +latitude)

φ = 0 da:
R = [ cosψ,  −sinψ·sinθ,  sinψ·cosθ ]
    [    0,        cosθ,       sinθ ]
    [−sinψ,  −cosψ·sinθ,  cosψ·cosθ ]
```

Xossalari (test bilan qotiriladi):
- 2-ustun = optik o'q: `lat = asin(r5) = θ`, `lon = atan2(r2, r8) = ψ`;
- **ORTONORMAL** — kritik: proyektor teskarisini TRANSPOZ bilan oladi.
  O'rta ustundagi ikki minus bo'lmasa ortonormallik buziladi va **har qanday
  egilgan kadr gorizontga proyeksiya qilinadi** (o'lchangan: 138° o'rniga 67° qamrov);
- `rotationMatrix(0,0,0) == identity`.

### 3.4 `placementLon` + oxirgi flip — `5469e83` ning yuragi

```dart
double placementLon(double yawDeg) => -yawDeg * math.pi / 180;
```

Ilovaning yaw'i telefon **o'nga** burilganda o'sadi; proyektor longitudasi
teskari tomonga o'sadi (kamera X chapga). Konvertatsiya bitta joyda.

**Tarixi:** `4a4bd44` yaw'ni tuzatdi, negatsiya qo'shilmadi → har kadr o'z
o'rnining ko'zgusiga tushdi, mos feature qoldig'i **5 px → 218 px**, 70 kadrdan
30 tasi tuzatilmadi.

Natija sferasi baribir teskari qoladi → oxirida **bitta gorizontal flip**
(`for y: for x: dst[y][W−1−x] = src[y][x]`, crop'dan KEYIN). Equirect'ning
gorizontal flip'i aynan `lon → −lon`, seamsiz.

⚠️ **Ikkisi ham shart.** `placementLon` ni «tuzatib» flip'dan qutulib bo'lmaydi —
o'shanda kadrlar orasidagi kelishuv buziladi.

### 3.5 Proyeksiya — INVERSE

Har kanvas pikseli uchun «bu qaysi kadr pikselidan keladi» hisoblanadi.
Forward (kadr→sfera) hech qayerda yo'q.

```
tx = r0·dx + r3·dy + r6·dz    (TRANSPOZ — dunyodan kameraga)
ty = r1·dx + r4·dy + r7·dz
tz = r2·dx + r5·dy + r8·dz
cz = tz ; if cz <= 1e-6 → yaroqsiz
nx = tx/cz ; ny = ty/cz
x = cx − focal·nx ; y = cy − focal·ny        (k1 = 0)
if x,y kadrdan tashqarida → yaroqsiz
wgt = max((1 − |x−cx|/cx)·(1 − |y−cy|/cy), 1e-8)
```

`lon` uchun `u` **mod QILINMAYDI** — sin/cos davriy.

**Kadr izi (`_footprint`)** — tezlik uchun majburiy:
`radius = atan(diag/focal) + 0.02`; pol yaqinida `halfLon = π`, aks holda
`asin(sin(radius)/cos(lat))`. Wrap FAQAT `_columnBlocks` da hal qilinadi
(ko'pi bilan 2 blok).

### 3.6 Piksel tanlash — winner-take-all

```
mask = (wSrc > wDst)         // QAT'IY katta
```

G'olib = **markazga eng yaqin kadr** (separabel piramidal og'irlik).
Masofa/chuqurlik hisobga OLINMAYDI.

Nega qattiq tanlov: sensor 1–2° aniq → bir pikselni ko'ruvchi 3–4 kadr bir
necha piksel farq qiladi; yumshoq og'irlik ularni o'rtalashtiradi va **butun
panorama xiralashadi**. Qattiq tanlov murosani tor seam yo'lagiga siqadi.

### 3.7 Blending — faqat eng qo'pol oktavalar

`9378c62` ning natijasi: maska piramidasi **l=0,1,2 da QATTIQ** (0.5 threshold),
**l=3,4,5 da yumshoq**. Sabab: 2 metrdagi stul o'rta oktava obyekti; o'rta
oktavalarni blend qilish ikki siljigan stulni o'rtalashtiradi va **eritadi**.

---

## 4. OpenCV → sof Dart

### 4.1 Nima kerak

`sensor_stitcher.dart` da **509** `cv.*` chaqiruvi bor, lekin ular atigi
**6 xil ish** qiladi: rasm o'qish/yozish, `remap` (bilinear), `resize`
(AREA/NEAREST), `pyrDown`/`pyrUp`, element-wise arifmetika, va (tashlanadigan)
SIFT/BFMatcher. Qolgan ~880 satr kod **o'zgarishsiz** ko'chadi.

### 4.2 ⚠️ «Jim va halokatli» farqlar

Bular kompilyatsiya xatosi bermaydi, lekin natijani buzadi:

| Farq | Oqibati |
|---|---|
| `cv.imread` **EXIF orientatsiyani avtomatik qo'llaydi** | Dart dekoderi qilmasa uzun tomon almashadi, focal ~1.78× xato → **hech narsa tikilmaydi**. Eng jim va eng halokatli. |
| `cv.compare(CMP_GT)` **qat'iy** `>` | `>=` qilinsa teng og'irlikda oxirgi kadr yutadi → butun label xaritasi, seam va blend boshqacha |
| `0/0` | OpenCV 0, Dart **NaN**. `_safeDivide` (+1e-6) shart, aks holda bitta qoplanmagan piksel butun bandni NaN qiladi |
| `convertTo(CV_8UC3)` | saturate + **round**. `.toInt()` (truncate) qilinsa panorama bir daraja qorayadi |
| `INTER_AREA` | kasr koeffitsiyentda chegara pikseliga qismiy og'irlik. Oddiy box o'rtacha ≠ |
| `pyrDown` | `[1,4,6,4,1]/16`, chegara **BORDER_REFLECT_101**. Yadro/chegara boshqa bo'lsa feather kengligi (ya'ni `9378c62` sozlagan narsa) o'zgaradi |
| `INTER_NEAREST` indeksi | `floor(dst·src/dstSize)`, yaxlitlash EMAS. Label chegarasi yarim piksel siljisa seam boshqa yo'l tanlaydi |
| `cv.Mat.region()` | parent'ga **ko'rinish**. Tekis `Uint8List` da wrap bloklari va `v0` offsetini xato hisoblash jim buzilish beradi |

⚠️ **Bit-bir xillik kutilmasin.** Bilinear OpenCV'da 5-bitli fixed-point,
Dart'da float; seam DP narxlari kvadrat farqdan hisoblanadi, ya'ni raqamlar
mos kelmaydi. Solishtirish **ko'z bilan va `flatSeamVisibility`** bilan.

### 4.3 Ko'chirilmaydigan bug

`_routeOne` dagi `index(u, −1)` — vertical rejimda bu **oldingi qatorning
oxirgi pikseli**, va `p >= 0` bo'lgani uchun `_sideCost` uni rad etmaydi.
Ya'ni tasmaning chap chetidagi cut narxi tasodifiy qo'shnidan hisoblanadi.

Aynan ko'chirilsa bug ham ko'chadi; tuzatilsa `1.0.2` da o'lchangan 0.78
ko'rsatkichi qaytarilmaydi. **Qaror: tuzatiladi**, va farq o'lchanadi.

---

## 5. Xotira va tezlik

### 5.1 Proyeksiya yuki — TUZATILGAN hisob

```
gorizont  30 × (661×659) = 13.07 M
±45       40 × (1057×659) = 27.86 M     ← halfLon 1/cos(45°) ga KENGAYADI
qutb       6 × (3072×330) =  6.08 M
                            ─────────
                             47.0 M piksel
```

⚠️ Dastlabki hisob 39.4 M degan edi — **xato**. `±45°` qatorlari butun ishning
**59 %ini** tashkil qiladi.

### 5.2 Xotira

76 kadr × 4K × 4 bayt ≈ **3.7 GB** — imkonsiz. Yechim: bosqichma-bosqich dekod
+ diskdagi xom kadr keshi (`PRW1` sarlavhali, 702×1248 / 384×683 / 200×356),
akkumulyator kanvas float EMAS, multi-band `1536×768`.

### 5.3 Isolate

Proyeksiya kanvasni **gorizontal bo'laklarga** bo'lib parallellashadi.
Multi-band parallellashmaydi (piramida global). Progress `SendPort` orqali.

---

## 6. Capture UX

`1.0.2` dan ko'chiriladi: `target_overlay.dart` (200 q.) + `capture_guidance.dart`
(162 q.) + `capture_screen.dart` ning UX qismlari.

⚠️ `capture_guidance.dart` `rotationMatrix` ni `sensor_stitcher.dart` dan
import qiladi → sof Dart `math/rotation.dart` ga ajratiladi.

⚠️ **`BoxFit.cover` shartnomasi**: marker o'rni `max(w/iw, h/ih)` bilan
hisoblanadi. `ClipRect` + `FittedBox(BoxFit.cover)` + `SizedBox(previewSize)`
tuzilishi **aynan saqlanishi** shart, aks holda marker ko'rilayotgan narsadan
siljiydi.

`RingDial` va matn banneri **qoladi** — `1.0.2` da TargetOverlay ular
O'RNIGA emas, USTIGA qo'shilgan.

---

## 7. Platforma — ikki haqiqiy ziddiyat

### 7.1 Android: CameraX majburiy ko'tarilishi

Ilova `androidx.camera:* = 1.4.2` va `guava:33.3.1-android` ni ochiq e'lon
qilgan (izoh: «versiya media3 talab qilgani bilan bir xil»).
`camera_android_camerax 0.7.2` ularni **1.6.0** va **33.5.0** ga ko'taradi.

Ustiga manifestga **`RECORD_AUDIO`** (Play Console'da ko'rinadi + data-safety
savoli) va `uses-feature camera.any` ni `required` bilan qo'shadi — ikkalasi
ham `tools:node="remove"` bilan olib tashlanishi kerak.

### 7.2 iOS: kameraga uch egasi

1. yangi `camera_avfoundation` `CameraController`;
2. mavjud `VideoCaptureRecorder.swift` ning `AVCaptureSession`;
3. PCScanKit ning `ARSession`.

Yechim: **`CameraGuard`** — `acquire/release` bilan yagona egalik.
⚠️ Xato yo'li majburiy: native chaqiruv crash bilan qaytmasa `_owner` abadiy
band qoladi → `finally` + timeout + lifecycle reset.

### 7.3 Boshqa

- `dchs_motion_sensors 2.0.2` `sdk >=3.11.0` talab qiladi; mobil pubspec `^3.10.1`
  → pol ko'tariladi.
- `flutter_cube 0.1.1` (`panorama_viewer` ning renderer'i) — Dart 2 davri,
  ta'mirlanmaydi. Xavf sifatida qayd etiladi.
- **Bo'sh disk** uchun yangi kanal KERAK EMAS — iOS'da allaqachon bor
  (`VideoCaptureRecorder.swift:161` `freeSpaceFloor = 300 MB`, `:308`, `:314`;
  Dart tomoni `video_capture.dart:51/94/112`).

---

## 8. Regressiya bazasi

```
flutter analyze : 27 muammo (0 error, 4 warning)
flutter test    : ~600 s da TUGAYDI — 282 test, 266 o'tdi, 16 yiqildi
```

⚠️ Dastlab «`flutter test` cheksiz osilib qoladi» deb yozilgandi — **xato**.
U tugaydi; `otp_step_test.dart :: wrong code shows error toast` 596 s ishlab
timeout bilan yakunlanadi. Skript uni chetlab o'tadi.

---

## 9. Reja — 23 qadam
| # | Qadam | Asosiy fayllar |
|---|---|---|
| 1 | Regressiya bazasini qotirish + o'lchov skripti | `tool/pano/baseline.sh`, `tool/pano/README.md` |
| 2 | Paketlarni qo'shish va SDK polini to'g'rilash | `pubspec.yaml`, `pubspec.lock` |
| 3 | MIL-0 ⭐ JPEG dekod/resize mikro-benchmark (QURILMADA, AOT) | `integration_test/pano_decode_bench_test.dart`, `tool/pano/bench_decode.sh` |
| 4 | SHARTLI: native JPEG dekod kanali (kadastr/pano_codec) | `lib/features/panorama/data/pano_image_codec.dart`, `ios/Runner/PanoImageCodec.swift` |
| 5 | Platforma: ruxsatlar, manifest merge va Gradle CameraX unifikatsiyasi | `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts` |
| 6 | CameraGuard + kamera ziddiyati proboni (QURILMADA) | `lib/features/panorama/data/camera_guard.dart`, `lib/features/panorama/data/pano_camera.dart` |
| 7 | Sof matematika porti + unit testlar (telefonsiz) | `lib/features/panorama/math/rotation.dart`, `lib/features/panorama/models/capture_guidance.dart` |
| 8 | CaptureRing + selectBand + StitchOutcome porti + testlar | `lib/features/panorama/models/capture_ring.dart`, `lib/features/panorama/models/sensor_shot.dart` |
| 9 | Raster yadrolari (cv.remap/resize/pyr o'rniga) + testlar | `lib/features/panorama/stitch/raster.dart`, `test/features/panorama/raster_test.dart` |
| 10 | Geometriya: focal, footprint, columnBlocks + testlar | `lib/features/panorama/stitch/geometry.dart`, `test/features/panorama/geometry_test.dart` |
| 11 | prepare: WorkDir + kadr keshi (bosqichma-bosqich dekod) | `lib/features/panorama/stitch/work_dir.dart`, `lib/features/panorama/stitch/raw_plane.dart` |
| 12 | project: winner-take-all proyeksiya + isolate bo'laklari | `lib/features/panorama/stitch/project.dart`, `test/features/panorama/project_test.dart` |
| 13 | MIL-1 ⭐⭐ 8 KADRNI TIKIB VAQTNI O'LCHASH (butun yondashuv qarori) | `lib/features/panorama/stitch/dart_stitcher.dart`, `lib/features/panorama/models/pano_progress.dart` |
| 14 | gains: ekspozitsiya tenglashtirish (Gauss-Seidel) | `lib/features/panorama/stitch/gains.dart`, `test/features/panorama/gains_test.dart` |
| 15 | ~~seam routing~~ **BEKOR QILINDI** — pastdagi izohga qarang | — |
| 16 | multiband blend + restoreDetail + to'liq quvur (76 kadr) | `lib/features/panorama/stitch/multiband.dart`, `lib/features/panorama/stitch/dart_stitcher.dart` |
| 17 | Capture UX widgetlari: nishon overlay, banner, RingDial | `lib/features/panorama/widgets/target_overlay.dart`, `lib/features/panorama/widgets/capture_banner.dart` |
| 18 | HeadingSource: sensor → yaw/pitch/roll (30 Hz) | `lib/features/panorama/data/heading_source.dart`, `test/features/panorama/heading_source_test.dart` |
| 19 | PanoCaptureScreen: to'liq capture ekrani (76 kadr, avtomatik zatvor) | `lib/features/panorama/screens/pano_capture_screen.dart`, `lib/features/panorama/data/capture_session.dart` |
| 20 | 360° ko'ruvchi (panorama_viewer) | `lib/features/panorama/pano_geometry.dart`, `lib/features/panorama/screens/pano_viewer_screen.dart` |
| 21 | Bozor sehrgari: «360 фото» qatorini capture'ga ulash | `lib/features/bozor/widgets/pano_source_sheet.dart`, `lib/features/bozor/screens/bozor_description_step_screen.dart` |
| 22 | E'lon detalida 360 ko'rinishi | `lib/features/bozor/models/bozor_listing.dart`, `lib/features/bozor/feed/bozor_listing_detail_screen.dart` |
| 23 | Regressiya yakuni + uslub va sifat tekshiruvi | `tool/pano/baseline.sh`, `tool/pano/README.md` |

### ⚠️ 15-qadam BEKOR QILINDI (2026-09-11)

Chok yo'naltiruvchisi (`_routeSeams`, yorug'lik bo'yicha DP) **ko'chirilmaydi**.

Sabab manbaning o'z tarixida yozilgan (`f85cacd`, «Turn off the deformation
and seam routing that made panoramas worse»):

> The seam router **deletes objects**. Scoring seams on high-frequency detail
> was meant to ignore shading, which blending removes anyway. But a white
> plant pot on a white floor has no high frequencies, so cutting through it
> costs nothing by that measure. The router ran the seam through the pot and
> filled it with the floor behind. **The pot vanished.**

Bu sozlash masalasi emas — yuqori chastota bo'yicha baholashning o'zi
noto'g'ri. Manbada u `routeSeams = false` bilan **o'chirilgan** va HEAD'da
hech qachon chaqirilmaydi.

Nega dastlab sezilmagan (o'sha commitdan): har o'lchov panoramani TEKIS
tasvir sifatida olgan, u esa 4096 enda o'zining 2× kichraytirilgani.
Ko'ruvchi esa ekranga 75° soladi — o'sha piksellarning 2× kattalashtirilgani.
Birinchisida o'rtachalanib yo'qoladigan surtish ikkinchisida ochiq ko'rinadi.

**Chok muammosi 16-qadamda hal qilinadi** — ko'p bandli aralashtirish buni
to'g'ri, oktava bo'yicha bajaradi va u manbada YOQILGAN (`_multiBand`
shartsiz chaqiriladi).

Shu bilan §4.3 dagi «`_routeOne` dagi `index(u, −1)` bug'i tuzatiladi» degan
qaror ham kuchini yo'qotadi — tuzatiladigan kod ko'chirilmaydi.

---

### Mil nuqtalari — har biridan keyin NIMA ISHLAYDI

| Mil | Qadam | Natija |
|---|---|---|
| **MIL-A** | 1–2 | O'lchov bazasi bor, paketlar resolve bo'ldi |
| **MIL-0** ⭐ | 3–4 | **Telefonda JPEG dekod tezligi MA'LUM** — «sof Dart yetadimi yoki native kanal kerakmi» hal qilingan |
| **MIL-B** | 5–6 | **Kamera ziddiyati yopilgan** — bitta CameraX, mavjud video capture ishlashda davom etadi |
| **MIL-C** | 7–10 | Butun geometriya **telefonsiz** tekshirilgan |
| **MIL-1** ⭐⭐ | 13 | **8 kadr telefonda tikildi, vaqt o'lchandi** — butun yondashuv qarori |
| **MIL-D** | 14, 16 | To'liq sifatli tikish ishlaydi (76 kadr). 15 bekor. |
| **MIL-E** | 17–19 | Capture ekrani qurilmada ishlaydi |
| **MIL-F** | 20 | **Uchidan-uchgacha oqim** — suratga olish → sferada ko'rish |
| **MIL-G** | 21–22 | Bozor oqimi to'liq |
| **MIL-H** | 23 | Regressiya toza, sifat raqam bilan tasdiqlangan |

⚠️ **MIL-1 ning qamrovi cheklangan.** 8 kadrli o'lchov gains/seam/blend'siz
qilinadi, ya'ni yakuniy quvurning faqat **~41–60 %ini** ko'radi
(seam 0.11 + blend 0.28 kirmaydi). «≤120 s → GO» mezoni shu sababli zaif —
ekstrapolyatsiya seam va blend ulushini ham qo'shishi kerak.

---

## 10. Hal qilingan ziddiyatlar

| # | Masala | QAROR | Sabab |
|---|---|---|---|
| 10.1 | Chiqish kengligi 4096 vs 3072 | **3072** (×1536) | 37 % kam ish, 8.5 px/daraja — e'lon ko'ruvchisi uchun yetarli; xotira cho'qqisi pasayadi |
| 10.2 | Seam masshtabi d=2 vs d=3 | **768×384** (3072/4) | d=2 da 159.4 MB > 157.3 MB byudjet; 3072 kanvasda bu savol o'z-o'zidan yopiladi |
| 10.3 | `_softBands` off-by-one | Qattiqlashtirish **l=0,1,2** (yumshoq l=3,4,5) | Kod shundoq qiladi; nom chalg'ituvchi |
| 10.4 | FOV 67.3° | **Qurilmada o'lchanadi** | 67.3° panoramaning 1x kamerasi uchun; kadastr recorder ATAYLAB 0.5x/0.6x tanlaydi |
| 10.5 | `_routeOne` bug'i | **Tuzatiladi**, farq o'lchanadi | Bug'ni ko'chirish mantiqsiz |
| 10.6 | SIFT | **NCC panjara** bilan almashtiriladi | §2.1 — `_solveFrame` o'zgarmaydi |

**Olib tashlangan «ziddiyat»:** «`f649593`/`9378c62` ning `4a4bd44`+`5469e83`
bilan birgaligi tekshirilmagan». Bu ziddiyat **yo'q** — `git log 1.0.1..1.0.2`
bo'yicha hammasi bitta shoxda ketma-ket:
`7377853 → 4a4bd44 → 0dac253 → 5469e83 → f649593 → 9378c62`.

---

## 11. Ochiq savollar

1. **Kadrlar qanday olinadi?** Hozirgi `video_capture.dart` VIDEO yozadi.
   Tikuvchi esa alohida STILL'lar + har biriga yaw/pitch talab qiladi.
   `camera` plagini `takePicture()` beradi — lekin bu MIL-B ga bog'liq.
2. **Chiqish JPEG enkoderi** — `image` paketi (sof Dart, sekin) yoki native
   kanal? MIL-0 da hal qilinadi.
3. **Qismiy qamrov metadata'si.** `DescriptionDraft.panoramas` — faqat
   `List<String>`. `verticalCoverDeg` ni ko'ruvchiga yetkazish yo'li hozir
   YO'Q; yechim (`<path>.json` yonma-yon) qoralama codec'iga tegadi.
4. **NCC va SIFT aniqligi farqi** — o'lchanmagan.
5. `test/tools/yaw_sign.dart` va `pano_handedness.dart` (yaw belgisi uchun
   mexanik tekshiruv vositalari) ko'chirilsinmi?
