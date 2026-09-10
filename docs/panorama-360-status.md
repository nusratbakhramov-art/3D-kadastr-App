# 360° panorama — HOLAT va DAVOMI

Bu hujjat **ishni qayerdan davom ettirish** kerakligini aytadi. Reja va
qarorlar [panorama-360-plan.md](panorama-360-plan.md) da; bu yerda faqat
holat, tartib va buzilmasligi kerak bo'lgan qoidalar.

Oxirgi yangilanish: **2026-09-11**, branch `feat/bozor-ai-v2`, HEAD `3ad4689`.

---

## 1. Bir qarashda

**360° oqimi UCHIDAN-UCHGACHA ulangan va qurilmada sinash mumkin:**

```
Bozor → e'lon qo'shish → 5-qadam (Tavsif) → «360 foto qo'shish»
   → manba varag'i: [Suratga olish] / [Galereyadan tanlash]
   → PanoCaptureScreen: jonli preview + nishon + avtomatik zatvor
   → stitchSensor: dekod → proyeksiya → yechim → qamrov
   → tikilgan JPEG yo'li qoralamaga qo'shiladi
```

| | |
|---|---|
| Bajarilgan qadam | **17 / 23** (1,2,3,5–14,17,18,19,21) |
| Qolgan qadam | 15, 16, 20, 22, 23 + shartli 4 |
| Commit | 25 ta, branch `feat/bozor-ai-v2` |
| **Push** | **HECH QACHON PUSHLANMAGAN** (upstream yo'q) |
| Panorama kodi | 19 fayl, `lib/features/panorama/` |
| Panorama testlari | **386 test, 386 o'tdi** |
| Regressiya bazasi | `analyze 27 (0 error, 4 warning)`, `tests 674 / fail 16` |

⚠️ **Sifat chegarasi.** Tikish hali **chok tekislashsiz** (15/16-qadamlar
qolgan). Geometriya to'g'ri, lekin kadrlar tutashgan joyda yorug'lik farqi
va to'rtburchak «yamoqlar» ko'rinadi. Bu KUTILGAN holat, xato emas.

---

## 2. Buzilmasligi kerak bo'lgan TO'RT qoida

### 2.1 So'ralmagan joyga tegilmaydi

360° ish **Bozor e'lon sehrgari** uchun. Undan tashqaridagi MAVJUD kodga
tegilmaydi.

Bir marta tegildi va qaytarildi (`e720c90`): AI Baholash kamerasi
`CameraGuard` ga o'ralgan, Android CameraX ko'tarilgan, manifest va ilova
versiyasi o'zgartirilgan edi. Foydalanuvchi buni so'ramagan.

Hozirgi holat — tekshirib turing:

```bash
git diff 966fe3d..HEAD --stat -- lib/features/services/   # BO'SH bo'lishi kerak
```

`room_plan_scanner.dart` va `video_capture.dart` **bayt-baytiga asl holida**.

Platforma sozlamalari (`AndroidManifest.xml`, `build.gradle.kts`,
`Info.plist`) **foydalanuvchi roziligi bilan** o'zgartirilgan (`9177169`) —
capture ekrani `camera` paketini talab qiladi va u muqarrar manifestga
tegadi.

### 2.2 Manba `1.0.2` ni kuzatadi, `1.0.1` ni EMAS

`~/StudioProjects/panorama` repozitoriysining ish daraxti `1.0.1` da
turibdi, port esa **`1.0.2`** ni kuzatadi. Kodni o'qiyotganda:

```bash
git -C ~/StudioProjects/panorama show 1.0.2:lib/services/sensor_stitcher.dart
```

Ish daraxtidagi fayl ikki joyda ESKI: `_multiBand` (qattiq/yumshoq maska
yo'q) va `_restoreDetail`.

⚠️ **`panorama` papkasiga YOZILMAYDI.** U faqat manba. Tekshirish:

```bash
git -C ~/StudioProjects/panorama status --porcelain    # BO'SH bo'lishi kerak
```

### 2.3 Har qadamdan keyin baza o'lchanadi

```bash
bash tool/pano/baseline.sh
```

Raqamlar **yomonlashmasligi kerak**: `0 error`, `4 warning`, `fail 16`.
16 yiqilgan test **bizdan oldin** ham yiqilardi — ro'yxati
[tool/pano/README.md](../tool/pano/README.md) da.

### 2.4 Har tuzatish MUTATSIYA bilan tekshiriladi

Qoidani buzib ko'r → test yiqilishi SHART. Yiqilmasa test hech narsani
qo'riqlamayapti. Shu usul bilan bu ishda manbadagi **uchta haqiqiy xato**
topildi (§5).

---

## 3. Qolgan ish — TARTIB bilan

### 15-qadam — chok yo'naltiruvchisi (YORQINLIK bo'yicha DP)

**Manba:** `git show 1.0.2:lib/services/sensor_stitcher.dart`, `_routeSeams`
(≈3255-qator). Ko'chiriladigan commit — **`f649593`**.

**Chiqish:** `lib/features/panorama/stitch/seam.dart` + testlar.

⚠️ **ADASHMANG.** `f85cacd` (1.0.1) yo'naltiruvchini O'CHIRGAN, chunki u
obyektlarni o'chirardi: choklar YUQORI CHASTOTA bo'yicha baholanardi, oq
polda turgan oq guldonda esa yuqori chastota yo'q — undan kesib o'tish
«bepul» ko'rinardi va guldon yo'qolardi.

Keyingi commit `f649593` uni TUZATGAN: baholash **yorqinlikka** o'tkazilgan
va qayta yoqilgan, aynan guldonni yo'qotgan capture'da tekshirilgan —
«the pot survives», chok ko'rsatkichi 0.93 dan 0.78 ga tushgan.

Ya'ni faqat `1.0.1` ga qarab «bekor qilaman» degan xulosa XATO. Bir marta
shunday qilinib, qaytarishga to'g'ri keldi (`2e080c1` → `350efb8`).

**Rejadagi qo'shimcha qaror** (§4.3): `_routeOne` dagi `index(u, −1)` bug'i
— vertikal rejimda bu OLDINGI qatorning oxirgi pikseli va `p >= 0` bo'lgani
uchun `_sideCost` uni rad etmaydi. **Tuzatiladi**, va farq o'lchanadi.

### 16-qadam — ko'p bandli aralashtirish

**Manba:** `_multiBand` + `_restoreDetail` + `_seamBand`, **`1.0.2` dan**
(`9378c62` qattiq/yumshoq maskani qo'shgan).

**Chiqish:** `lib/features/panorama/stitch/multiband.dart` va
`dart_stitcher.dart` ga ulash.

Kalit faktlar (hammasi o'lchangan):

* `_bands = 5`, ya'ni 0..5 — olti daraja;
* `_softBands = 2` — **faqat eng qo'pol ikkitasi aralashadi**. Qolganlari
  yutuvchini to'liq oladi;
* qattiqlash tsikli `for (l = 0; l < _bands - _softBands; l++)` — ya'ni
  l=0,1,2 QATTIQ (0.5 threshold), l=3,4,5 yumshoq;
* **NEGA:** 2 metrdagi stul — O'RTA oktava obyekti. O'rta oktavalarni
  blend qilish ikki siljigan stulni o'rtalashtiradi va **eritadi**.
  Blendni butunlay o'chirish stulni qaytaradi, lekin devor to'rtburchak
  yamoqlarga bo'linadi. Ya'ni o'rta oktavalar ARALASHMASLIGI, eng
  qo'polari esa ARALASHISHI kerak;
* yarim tuval rezolyutsiyasida ishlaydi, to'liq detal keyin
  `_restoreDetail` bilan qaytariladi.

⚠️ `_restoreDetail` `1.0.2` da O'ZGARGAN: chok bo'ylab detal
so'ndirilmaydi (`f649593`). Ish daraxtidagi `1.0.1` versiyasini
ko'chirmang.

**Tayyor yordamchilar:** `raster.dart` da `pyrDown`, `pyrUp`, `kPyrKernel`,
`reflect101` allaqachon bor va test bilan qoplangan.

### 20-qadam — sferada ko'ruvchi

**Chiqish:** `lib/features/panorama/screens/pano_viewer_screen.dart`.

⚠️ **`panorama_viewer` paketi HALI QO'SHILMAGAN** — u `pubspec.yaml` dan
`e720c90` da olib tashlangan. Qo'shishdan oldin tekshirilsin: u platformaga
tegadimi. Rejadagi qayd: uning renderer'i `flutter_cube 0.1.1` — Dart 2
davri paketi, ta'mirlanmaydi, **xavf sifatida qayd etilgan**.

Muqobil: equirect tasvirni o'zimiz `CustomPainter` bilan ko'rsatish
(`rotation.dart` dagi matematika allaqachon bor).

### 22-qadam — e'lon detalida 360

**Chiqish:** `bozor_listing_detail_screen.dart` — 360 media turini
ko'ruvchiga ulash. `bozor_listing.dart` dagi `MediaOut` allaqachon
`storage_key` beradi.

### 23-qadam — yakun

Regressiya, uslub va sifat tekshiruvi. `tool/pano/README.md` ni
yangilash.

### 4-qadam — SHARTLI

MIL-0 o'lchovi `> 1200 ms` bersagina qilinadi (§4). Native
`kadastr/pano_codec` kanali.

---

## 4. QURILMADA — foydalanuvchi bajaradi

Ikki o'lchov jihozi tayyor va **hali yurgizilmagan**. Ikkalasi ham
haqiqiy telefon talab qiladi (emulyator/simulyator yaramaydi — profil
rejimi ularda yo'q va natija host protsessorini ko'rsatadi).

### MIL-0 — JPEG dekod tezligi

```bash
bash tool/pano/bench_decode.sh -j <4K foto>
```

| `decodeJpg` medianasi | Qaror |
|---|---|
| **≤ 1200 ms** | sof Dart QOLADI, 4-qadam O'TKAZILADI |
| **> 1200 ms** | 4-qadam MAJBURIY (native kanal) |

### MIL-1 — 8 kadrni tikish

```bash
bash tool/pano/bench_stitch.sh -f ~/Desktop/kadrlar
```

Kadrlar `y<yaw>_p<pitch>.jpg` deb nomlanadi (`y000_p0.jpg`, `y045_p0.jpg`…).
iPhone'da adb yo'q → `--device-dir <qurilmadagi papka>`.

⚠️ **QAROR `extrapolated76_s` GA QARAB QABUL QILINADI, `measured_ms` ga
EMAS.** O'lchov quvurning atigi **56 %ini** ko'radi (gains/seam/blend hali
yo'q). 8 kadr 10 sekundda tikilsa bu yaxshi ko'rinadi, lekin
ekstrapolyatsiya **170 s** beradi — 120 s chegarasidan oshadi. Skript buni
o'zi hisoblab GO/NO aytadi.

**NO bo'lsa** — arzonidan qimmatiga:

1. **Isolate'larga bo'lish** — `horizontalSlices` va `roiIntersectsRows`
   allaqachon yozilgan va tasmalarga bo'lingan natija yaxlit natija bilan
   **baytma-bayt bir xilligi** test bilan qotirilgan. 4 yadroda ~4×;
2. tuvalni kichraytirish 3072 → 2048 (yuk ~2.25× kamayadi);
3. kadr sonini kamaytirish 76 → 40 (qamrov tushadi);
4. native kanal.

### Capture ekranini sinash

Kod tomonidan tayyor. Bozor → e'lon qo'shish → 5-qadam → «360 foto
qo'shish» → *Suratga olish*. Bir joyda turib, telefonni tik ushlab sekin
aylaning.

Nimaga qarash kerak:

* nishon aylanasi devorda ko'rsatayotgan narsada TURADIMI (`BoxFit.cover`
  shartnomasi);
* telefon qimirlamay turganda yashil halqa to'ladimi va zatvor ochiladimi;
* kompasda yangi yashil nuqta DARHOL paydo bo'ladimi;
* AI Baholash skani ochiq turganda «Kamera hozir band» xabari chiqadimi.

---

## 5. Manbada topilgan XATOLAR (port'da tuzatilgan)

Bu uchtasi mustaqil tekshirishda topildi — ya'ni manbani aynan ko'chirish
buzuq ekran bergan bo'lardi.

### 5.1 Qutb kadrlarini olib bo'lmasdi — `6818950`

`dueAt`/`nextTarget` to'sig'i `isComplete` edi. U 70 ta MAJBURIY kadr
olingach rost bo'ladi, ya'ni zatvor o'sha lahzada **butunlay to'xtardi**
va ixtiyoriy zenit/nadir (6 kadr) olishning iloji qolmasdi. Ilovaning o'zi
taklif qiladigan narsa amalda erishib bo'lmas edi.

Bu o'lik kod ham keltirgandi: «zenit/nadir qo'shildi» matni hech qachon
chiqmasdi, `isFullyComplete` hech qachon rost bo'lmasdi.

**Tuzatish:** to'siq `isFullyComplete` ga o'tkazildi. `isComplete` o'z
ma'nosini saqlaydi — progress va «Tayyor» tugmasi uchun.

### 5.2 Kompas yangi kadrni ko'rsatmasdi — `04fc8f4`

`RingDial.shouldRepaint` da `old.ring.takenCount != ring.takenCount`.
Capture ekrani BITTA o'zgaruvchan `CaptureRing` beradi, ya'ni `old.ring`
va `ring` — **ayni obyekt** va shart hech qachon rost bo'lmaydi.

Amalda kompas ko'pincha baribir qayta chizilardi (`yaw` doim o'zgaradi),
**lekin aynan zatvor ochiladigan payt bundan mustasno**: kadr olinishi
uchun telefon qimirlamasligi shart, ya'ni `yaw` ham qotgan. Yangi yashil
nuqta aynan u paydo bo'lishi kerak bo'lgan lahzada ko'rinmasdi.

**Tuzatish:** sanoq `build` paytida suratga olinadi (`takenAtBuild`).

### 5.3 Zenit/nadir matni qator indeksiga bog'langan — `2acc4eb`

`target.shot.row == 3 ? 'Tepaga' : 'Pastga'`. Qatorlar tartibi o'zgarsa
matn jimgina teskari bo'lardi.

**Tuzatish:** `_ring.rows[row].pitchDeg > 0` bo'yicha.

### 5.4 Manbadagi hujjat xatolari (kodga ergashildi)

* `heading_source.dart` izohi chegarani «8 grad/s» deydi, kod `3` beradi.
  Izoh eskirgan → port kodga ergashadi;
* `((x % w) + w) % w` — C-izm. Dart'ning `%` si musbat bo'luvchi uchun
  allaqachon manfiy bo'lmagan natija beradi;
* `footprint` dagi qutb shoxi izohi «qutb kadrlarini qutqaradi» deydi —
  bu ROST EMAS. Shart `s >= 1` ga ekvivalent (67.3° FOV'da 1801 kenglikda
  farq yo'q); yagona haqiqiy roli `radius == 0` degenerat holati.

---

## 6. Xarita — qaysi fayl nima qiladi

### Tikish quvuri (sof Dart, platformaga tegmaydi)

| Fayl | Nima |
|---|---|
| `math/rotation.dart` | `rotationMatrix`, `placementLon`, `focalPx`, kamera nuri ↔ piksel |
| `stitch/raster.dart` | OpenCV o'rniga: `remap`, `resize` (AREA/LINEAR/NEAREST), `pyrDown`/`pyrUp` |
| `stitch/geometry.dart` | Ekvirektangulyar tuval, kadr izi (`footprint`), `columnBlocks` |
| `stitch/raw_plane.dart` | `PRW1` xom kadr keshi formati |
| `stitch/work_dir.dart` | Ish papkasi, `sampleWidthFor`, tozalash |
| `stitch/project.dart` | Winner-take-all proyeksiya, `taperWeight`, isolate tasmalari |
| `stitch/gains.dart` | Ekspozitsiya tenglashtirish (Gauss-Seidel) |
| `stitch/image_frame_loader.dart` | JPEG → planar; **EXIF orientatsiyasi** |
| `stitch/dart_stitcher.dart` | Quvurni birlashtiradi, `extrapolateFull` |
| `models/capture_ring.dart` | 76 kadrli reja (30@0° + 20@±45° + 3@±90°) |
| `models/capture_guidance.dart` | Nishon geometriyasi, `GuidanceLevel` |
| `models/stitch_outcome.dart` | Natija turlari, `selectBand` (qamrov) |
| `models/pano_progress.dart` | Bosqichlar va ulushlari (`kPhaseShare`) |

### Capture (kamera/sensor talab qiladi)

| Fayl | Nima |
|---|---|
| `data/heading_source.dart` | Sensor → yaw/pitch/roll, 30 Hz, gimbal-lock yechimi |
| `data/camera_guard.dart` | Kamera egaligi — **faqat panorama tomonida** ishlatiladi |
| `widgets/target_overlay.dart` | Nishon aylanasi, strelka, yashil halqa |
| `widgets/ring_dial.dart` | Capture kompasi |
| `screens/pano_capture_screen.dart` | To'liq ekran: preview, avtomatik zatvor, tikish |

### Bozor tomoni

| Fayl | Nima |
|---|---|
| `bozor/widgets/pano_source_sheet.dart` | Manba varag'i: suratga olish / galereya |
| `bozor/screens/bozor_description_step_screen.dart` | `onAdd: _add360` — kirish nuqtasi |

### Jihozlar

| Fayl | Nima |
|---|---|
| `tool/pano/baseline.sh` | Regressiya bazasi |
| `tool/pano/bench_decode.sh` | MIL-0 |
| `tool/pano/bench_stitch.sh` | MIL-1 |
| `tool/pano/README.md` | Yiqilgan testlar ro'yxati, qaror jadvallari |

---

## 7. Ochiq savollar va xavflar

| # | Narsa | Holat |
|---|---|---|
| 1 | MIL-0 va MIL-1 o'lchovlari | **kutmoqda** — 4-qadam va butun yondashuv shunga bog'liq |
| 2 | Kamera ziddiyatining IKKINCHI tomoni | Panorama ochiq turganda AI Baholash kamerani so'rasa ziddiyat qoladi. Yopish uchun mavjud faylga tegish kerak → **SO'RASH shart** |
| 3 | `flutter_cube 0.1.1` (20-qadam) | Dart 2 davri paketi, ta'mirlanmaydi. Muqobil — o'z `CustomPainter` |
| 4 | `pubspec.yaml` `version` | Hozir `1.0.5+41`, commit qilinmagan. **Foydalanuvchining o'zgarishi**, tegilmadi |
| 5 | `app_version.dart` ↔ `pubspec.yaml` | Qo'lda sinxronlanadi va relizda unutilgan — bu bizning ishimizga aloqasi yo'q, alohida commit bo'lishi kerak (bazadagi 1-yiqilgan test) |
| 6 | Branch pushlanmagan | 25 commit faqat lokalda |

---

## 8. Yangi sessiyada birinchi navbatda

```bash
cd ~/StudioProjects/mobile
git log --oneline -1                                      # 3ad4689 bo'lishi kerak
bash tool/pano/baseline.sh                                # 27 / 0 error / fail 16
git diff 966fe3d..HEAD --stat -- lib/features/services/    # BO'SH
git -C ../panorama status --porcelain                      # BO'SH
```

Keyin bu hujjatning §3 dagi tartibdan davom ettiring: **15 → 16 → 20 →
22 → 23**. Har biridan keyin §2.3 va §2.4.
