# 360° panorama — HOLAT va DAVOMI

Bu hujjat **ishni qayerdan davom ettirish** kerakligini aytadi.

Oxirgi yangilanish: **2026-09-12**, branch `feat/bozor-ai-v2`.

> ⚠️ **ARXITEKTURA ALMASHDI.** Ilgari panorama TELEFONDA, sof Dart bilan
> tikilardi ([panorama-360-plan.md](panorama-360-plan.md) — o'sha 23 qadamli
> reja). Endi telefon faqat **kadr yig'adi**, tikish esa **serverda**.
> Reja hujjati TARIX sifatida qoladi; amaldagi holat SHU YERDA.

---

## 1. Bir qarashda

```
Bozor → e'lon qo'shish → 5-qadam (Tavsif) → «360 foto qo'shish»
   → NATIV capture (iOS: ARKit / Android: ARCore) — 30 nishon, avto-zatvor
   → har kadr + KAMERA POZASI serverga yuklanadi
   → foydalanuvchi SHU EKRANDA kutadi (~30 s tikish)
   → tayyor panorama S3 KALITI bilan qoralamaga tushadi
   → bir nechta panorama yig'ilgach — hozirgidek TUR quriladi
```

| | |
|---|---|
| Mobil taraf | iOS (ARKit) **tayyor**, Android (ARCore) **tayyor** — ikkalasi ham QURILMADA SINALMAGAN |
| Server taraf | tayyor — `kadastr-backend` `4ae28b0` |
| Regressiya bazasi | `analyze 27 (0 error, 4 warning)`, `tests 379 / fail 16` |
| Push | branch hali **pushlanmagan** (upstream yo'q) |

### Nega almashdi

Sof Dart bilan telefonda tikish sifat va vaqt bo'yicha yetmasdi, va u
kadr pozasini SENSORdan olardi (gyro/kompas) — xato to'planib panorama
qiyshayardi. Nativ AR sessiyasi har kadr uchun kamera **transform** va
**intrinsics** beradi, ya'ni geometriya taxmin emas, o'lchov bo'ladi.
Server esa SIFT bilan burilishni aniqlashtiradi, chokni kesadi va ko'p
bandli aralashtiradi — telefonda amaliy bo'lmagan narsalar.

### Nima OLIB TASHLANDI

* `lib/features/panorama/stitch/**`, `math/rotation.dart`,
  `models/capture_*`, `data/camera_guard|capture_log|heading_source`,
  sensorga tayangan `pano_capture_screen.dart` — **21 fayl**;
* ularning **19 ta testi**;
* `integration_test/**` va `tool/pano/bench_*.sh` (qurilmada tikishni
  o'lchaydigan MIL-0/MIL-1 darvozalari), `integration_test` dev-bog'liqligi;
* `PanoViewerScreen` — faqat LOKAL fayl o'qirdi; sfera renderi esa
  `render/pano_sphere.dart` da QOLDI va turda ishlatiladi;
* ML: `DeepLabV3` (suratga oluvchini o'chirish) va `LaMa` (qutb
  bo'shliqlarini to'ldirish) serverga **umuman ko'chirilmadi** — qaror.

### Galereyadan yuklash — IZOHGA OLINGAN, o'chirilmagan

`lib/features/bozor/widgets/pano_source_sheet.dart` butunlay izohda,
tiklash yo'riqnomasi shu faylda. Sabab: server tikish uchun har kadrning
kamera pozasini talab qiladi, galereyadagi tayyor equirect'da esa u yo'q.

---

## 2. Buzilmasligi kerak bo'lgan qoidalar

### 2.1 So'ralmagan joyga tegilmaydi

360° ish **Bozor e'lon sehrgari** uchun. Undan tashqaridagi MAVJUD kodga
tegilmaydi — bir marta tegilib qaytarishga to'g'ri kelgan (`e720c90`:
AI Baholash kamerasi, Android CameraX, manifest).

```bash
git diff 966fe3d..HEAD --stat -- lib/features/services/   # BO'SH bo'lishi kerak
```

### 2.2 Har qadamdan keyin baza o'lchanadi

```bash
bash tool/pano/baseline.sh
```

Android tomoni uchun alohida (sof JVM, emulyator kerak emas):

```bash
cd android && ./gradlew :app:testDebugUnitTest   # 14 test
```

`0 error`, `4 warning`, `fail 16` — yomonlashmasin. 16 yiqilgan test
**bizdan oldin** ham yiqilardi, ro'yxati
[tool/pano/README.md](../tool/pano/README.md) da.

### 2.3 Mobil↔server shartnomasi

Server panoramani **oddiy media kaliti** qilib qaytaradi
(`listings/media/{user_id}/pano_*.jpg`), ya'ni e'lon uni yuklangan fotodan
farqsiz qabul qiladi. Shuning uchun sehrgar uchtasini birga yozadi:

```dart
_d.panoramas.add(outcome.storageKey);          // LOKAL YO'L EMAS — KALIT
_d.panoramaUrls[outcome.storageKey] = outcome.url;
_d.uploadedMedia[outcome.storageKey] = outcome.storageKey;   // «yuklangan»
```

Oxirgi qator bo'lmasa `bozor_submit` kalitni fayl yo'li deb bilib
`MultipartFile.fromPath` ga beradi va yuborish **yetti qadam to'ldirilgandan
keyin** yiqiladi. Buni `test/features/bozor/pano_server_media_test.dart`
qo'riqlaydi.

### 2.4 Har tuzatish MUTATSIYA bilan tekshiriladi

Qoidani buzib ko'r → test yiqilishi SHART. Yiqilmasa test hech narsani
qo'riqlamayapti.

---

## 3. Qolgan ish

### 3.1 Qurilmada sinash — ASOSIY QOLGAN ISH

Ikkala platforma ham **yozilgan va kompilyatsiya bo'ladi**, lekin HAQIQIY
qurilmada hali sinalmagan. Simulyator/emulatorda ARKit ham, ARCore ham yo'q —
`isSupported()` `false` qaytaradi va 360 qatori umuman ko'rinmaydi.

Tekshiriladigan uchta narsa (har ikki platformada):

1. 30 nishon aylanib chiqiladi, avtomatik zatvor ishlaydi;
2. yuklash progressi kadrma-kadr o'sadi, keyin «tikilmoqda» ga o'tadi;
3. tayyor panorama eskizi qatorida ko'rinadi (**tarmoqdan** yuklanadi) va
   bosilganda sferada ochiladi.

⚠️ **Android'da birinchi qaraladigan narsa — CHOK.** iOS birinchi kadrdan
keyin ekspozitsiya va oq balansni QULFLAYDI; ARCore'da bunga to'g'ridan
yo'l yo'q (Shared Camera / Camera2 qatlami kerak bo'lardi) va qulf
QO'YILMAGAN. Server gain kompensatsiyasi + ko'p bandli aralashtirish buni
tekislashi kerak. Tekislamasa —
`android/.../pano/PanoCaptureActivity.kt` dagi izohga qarang.

### 3.2 Platformalar orasidagi UCH farq (ataylab)

| | iOS (ARKit) | Android (ARCore) |
|---|---|---|
| Kamera oqimini chizish | `ARSCNView` o'zi chizadi | qo'lda, `PanoBackgroundRenderer` (GL) |
| Yuqori aniqlikdagi kadr | `captureHighResolutionFrame` | yo'q — eng katta CPU kadri (≤1920) tanlanadi |
| Ekspozitsiya qulfi | bor (`AVCaptureDevice`) | **yo'q** (yuqoriga qarang) |

Protokol esa AYNAN bir xil: `camera.transform`/`camera.pose.toMatrix()` —
ikkalasi ham OpenGL konvensiyasi (−Z oldinga), column-major; kadr SENSOR
orientatsiyasida, aylantirilmasdan yuboriladi.

### 3.3 Kichik qarzlar

* `assets/i18n/bundle.json` da o'chirilgan quvurdan **31 ta yetim kalit**
  qolgan (`bozor.pano.stitch.*`, `hint.*`, `resume.*`, `err.*`). Zarar
  yo'q, lekin tozalash backend seed'i bilan birga qilinishi kerak —
  bundle backenddan keladi, faqat mobil tarafdan o'chirish drift beradi.
* `pano_source_sheet.dart` izohda turibdi (yuqoriga qarang).
* ~~eski quvurning paketlari~~ — **tozalandi** (pastga qarang).

### 3.4 Tozalangan: eski quvurning platforma izi (2026-09-12)

`7a2c301` («360° uchun paketlar») qo'shgan TO'RTTA paket `lib/` da umuman
import qilinmay qolgan edi va olib tashlandi: **`image`**, **`camera`**,
**`dchs_motion_sensors`**, **`vector_math`**.

Ular bilan birga ketgani:

| Qayerda | Nima |
|---|---|
| `AndroidManifest.xml` | `RECORD_AUDIO` ni merge'dan chiqarib tashlaydigan blok (uni `camera_android_camerax` qo'shardi) |
| `AndroidManifest.xml` | `camera.any` ni majburiy emas qiladigan `tools:replace` |
| `AndroidManifest.xml` | giroskop/akselerometr `uses-feature` lari |
| `ios/Runner/Info.plist` | `NSMotionUsageDescription` |
| `pubspec.lock` | `camera_avfoundation`, `camera_android_camerax`, `camera_platform_interface`, `camera_web`, `stream_transform` |

⚠️ **`NSMotionUsageDescription` nega xavfsiz olindi.** Uni faqat CoreMotion
SENSOR API'si (`CMMotionManager` / `CMPedometer` / `CMAltimeter`) talab
qiladi. Butun `Pods` va plagin manbalari tekshirildi: uni faqat
`dchs_motion_sensors` va `camera_avfoundation` ishlatardi, ikkalasi ham
ketdi. **ARKit bu kalitni talab qilmaydi** — unga
`NSCameraUsageDescription` yetarli. (`PCScanKit` va `RoomPlanScanner`
`CoreMotion` ni import qiladi, lekin faqat `CMAcceleration` STRUKTURASI
uchun — u sensorga murojaat emas.)

`camera-*` va `guava` gradle bog'liqliklari QOLDI: ularni `:app` ning o'z
`VideoCaptureActivity` si ishlatadi. Versiyalar ham o'zgarmadi — tushirishning
foydasi yo'q.

---

## 4. Xarita — qaysi fayl nima qiladi

### Mobil — capture va yuklash

| Fayl | Nima |
|---|---|
| `ios/Runner/PanoCapture.swift` | ARKit sessiyasi, 30 nishon, avtomatik zatvor, JPEG 1280px + `meta.json` |
| `ios/Runner/AppDelegate.swift` | `kadastr/pano_capture` kanali |
| `android/.../pano/PanoCaptureActivity.kt` | ARCore sessiyasi, o'sha 30 nishon, o'sha zatvor, `meta.json` |
| `android/.../pano/PanoBackgroundRenderer.kt` | kamera oqimini GL bilan chizish (ARCore'da tayyor ko'rinish yo'q) |
| `android/.../pano/PanoOverlayView.kt` | nishon nuqtalari + reticle |
| `android/.../pano/PanoYuv.kt` | YUV_420_888 → NV21 (sof JVM, testlangan) |
| `android/.../pano/PanoTargets.kt` | nishon panjarasi + `meta` modeli (sof JVM, testlangan) |
| `android/.../MainActivity.kt` | `kadastr/pano_capture` kanali |
| `lib/features/panorama/data/pano_capture_channel.dart` | kanal klienti; matnlar SHU YERDA tarjima qilinadi va nativ tarafga uzatiladi |
| `lib/features/panorama/data/pano_api.dart` | `createJob → uploadFrame × N → finish → status` |
| `lib/features/panorama/screens/pano_capture_flow.dart` | kutish ekrani: capture → yuklash → tikish → natija; xatoda qayta urinish KADRLARNI QAYTA ISHLATADI |

### Mobil — ko'rsatish

| Fayl | Nima |
|---|---|
| `lib/features/panorama/render/pano_sphere.dart` | sfera geometriyasi va bo'yoqchisi (`projectSphere`, `SphereMesh`, `ViewBasis`, `SpherePainter`) — ekran EMAS |
| `lib/features/panorama/screens/pano_tour_screen.dart` | tur ekrani; tasvirni **fayldan ham, tarmoqdan ham** oladi (`TourPano.file` / `.url`) |

### Mobil — Bozor tomoni

| Fayl | Nima |
|---|---|
| `lib/features/bozor/screens/bozor_description_step_screen.dart` | `_pano360` bayrog'i (ARKit/ARCore bormi), `_add360`, `_open360` |
| `lib/features/bozor/widgets/media_upload_row.dart` | eskiz; `urlOf` berilsa **tarmoqdan** yuklaydi |
| `lib/features/bozor/models/bozor_draft.dart` | `panoramas` (KALITLAR) + `panoramaUrls` |

### Server (`kadastr-backend`, commit `4ae28b0`)

| Fayl | Nima |
|---|---|
| `app/services/pano_stitch.py` | tikish quvuri (SIFT → gain → DIS → graph-cut → multi-band → qutb) |
| `app/services/pano_frames.py` | har kadr O'Z meta faylini yozadi; `frames.json` `finish` da yig'iladi (ko'p-worker poygasidan himoya) |
| `app/tasks/bozor_pano_task.py` | `panorama.stitch` (alohida navbat, concurrency 1), `panorama.gc_frames` |
| `app/models/bozor_pano_job.py` | `BozorPanoJob`, holatlar: capturing/queued/stitching/done/error |
| `scripts/ensure_bozor_pano_jobs.py` | idempotent DDL (alembic EMAS — ikkita revision deploy'ni buzadi) |

⚠️ **PRODDAGI TUZOQ (2026-09-12 da bir marta tushdik).** Prodning o'z
`docker-compose.override.yml` i bor, u rsync'dan chetlab o'tiladi va
`app`/`celery`/`celery-beat`/`photogrammetry-worker` uchun
`volumes: !override` ishlatadi — bazadagi ro'yxatni TO'LDIRMAY,
ALMASHTIRADI. Shu sababli `docker-compose.yml` ga qo'shilgan
`/data/panoramas` mount'i `app` ga yetib bormadi: API kadrlarni o'z
konteyneri ichiga yozdi, worker bo'sh katalog ko'rdi, har panorama
yiqildi. Tuzatish — override'ga ham qator qo'shish, keyin
`docker compose up -d app`. Tekshirish:
`docker compose config | grep -c kadastr-panoramas` (2 bo'lishi kerak).

**Kadrlar vaqtinchalik:** muvaffaqiyatda **darhol**, xatoda **24 soatdan
keyin** o'chiriladi.

---

## 5. Yangi sessiyada birinchi navbatda

```bash
bash tool/pano/baseline.sh                               # 0 error / 4 warning / fail 16
cd android && ./gradlew :app:testDebugUnitTest           # 14 test (pano)
git -C ~/StudioProjects/kadastr-backend log --oneline -1 # 4ae28b0 bo'lsin
```

Keyin — **3.1 (qurilmada sinash)**.
