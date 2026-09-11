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
   → NATIV capture (iOS: ARKit) — 30 nishon, avtomatik zatvor
   → har kadr + KAMERA POZASI serverga yuklanadi
   → foydalanuvchi SHU EKRANDA kutadi (~30 s tikish)
   → tayyor panorama S3 KALITI bilan qoralamaga tushadi
   → bir nechta panorama yig'ilgach — hozirgidek TUR quriladi
```

| | |
|---|---|
| Mobil taraf | iOS **tayyor**, Android (ARCore) **QOLGAN** |
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

### 3.1 Android capture (ARCore) — ASOSIY QOLGAN ISH

Protokol **platformadan mustaqil**: server ARKit haqida hech narsa
bilmaydi, faqat `transform` (camera→world 4×4, ustun-bo'yicha) va
`intrinsics` (fx, fy, cx, cy) kutadi. ARCore aynan shu konvensiyani
beradi (OpenGL, −Z oldinga):

| iOS (ARKit) | Android (ARCore) |
|---|---|
| `frame.camera.transform` | `frame.camera.pose.toMatrix()` |
| `frame.camera.intrinsics` | `camera.getImageIntrinsics()` |
| `captureHighResolutionFrame` (iOS 16+) | `frame.acquireCameraImage()` |
| `.gravity` worldAlignment | ARCore'da poza allaqachon tortishishga tekis |

Yozilishi kerak: `android/app/src/main/kotlin/.../PanoCapture.kt` +
`MainActivity` da `kadastr/pano_capture` kanali. Dart tarafida **hech narsa
o'zgarmaydi** — [pano_capture_channel.dart](../lib/features/panorama/data/pano_capture_channel.dart)
o'sha kanalni chaqiradi va o'sha natijani kutadi (`dir`, `frames`).

⚠️ ARCore **hamma Android qurilmada yo'q**. `isSupported()` `false`
qaytarsa 360 bo'limi **umuman chizilmaydi** — muqobil taklif qilinmaydi,
chunki eski sensorli oqim ham, galereyadan yuklash ham olib tashlangan.

### 3.2 Qurilmada sinash (iOS)

Simulyatorda ARKit **yo'q** — `isSupported()` `false` qaytaradi va 360
qatori ko'rinmaydi. Haqiqiy telefon kerak (A9+).

Tekshiriladigan uchta narsa:

1. 30 nishon aylanib chiqiladi, avtomatik zatvor ishlaydi;
2. yuklash progressi kadrma-kadr o'sadi, keyin «tikilmoqda» ga o'tadi;
3. tayyor panorama eskizi qatorida ko'rinadi (**tarmoqdan** yuklanadi) va
   bosilganda sferada ochiladi.

### 3.3 Kichik qarzlar

* `assets/i18n/bundle.json` da o'chirilgan quvurdan **31 ta yetim kalit**
  qolgan (`bozor.pano.stitch.*`, `hint.*`, `resume.*`, `err.*`). Zarar
  yo'q, lekin tozalash backend seed'i bilan birga qilinishi kerak —
  bundle backenddan keladi, faqat mobil tarafdan o'chirish drift beradi.
* `pano_source_sheet.dart` izohda turibdi (yuqoriga qarang).

---

## 4. Xarita — qaysi fayl nima qiladi

### Mobil — capture va yuklash

| Fayl | Nima |
|---|---|
| `ios/Runner/PanoCapture.swift` | ARKit sessiyasi, 30 nishon, avtomatik zatvor, JPEG 1280px + `meta.json` |
| `ios/Runner/AppDelegate.swift` | `kadastr/pano_capture` kanali |
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

**Kadrlar vaqtinchalik:** muvaffaqiyatda **darhol**, xatoda **24 soatdan
keyin** o'chiriladi.

---

## 5. Yangi sessiyada birinchi navbatda

```bash
bash tool/pano/baseline.sh          # 0 error / 4 warning / fail 16
git -C ~/StudioProjects/kadastr-backend log --oneline -1   # 4ae28b0 bo'lsin
```

Keyin — **3.1 (Android capture)**.
