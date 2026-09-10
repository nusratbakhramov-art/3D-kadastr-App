# `tool/pano` — 360° panorama ishining regressiya bazasi

Bu papka [docs/panorama-360-plan.md](../../docs/panorama-360-plan.md) dagi
23 qadamli ish uchun. Har qadamdan keyin:

```bash
bash tool/pano/baseline.sh
```

Chiqishdagi ikki qator oldingisi bilan solishtiriladi. **Raqamlar
yomonlashmasligi kerak.**

---

## Baza — 2026-09-10, commit `966fe3d`

```
analyze: 27 issues (0 error, 4 warning)
tests: testDone=282 success=266 fail=16
```

O'lchandi: Flutter 3.41.4 / Dart 3.11.1, macOS (darwin 25.3.0).
To'liq yugurish **18 sekund** (`otp_step_test.dart` bilan ~600 s bo'lardi).

---

## Mavjud 4 ta `warning`

Bular **bizdan oldin** bor edi. Yangi warning qo'shilsa — bu regressiya.

| Fayl:qator | Qoida |
|---|---|
| `lib/features/home/home_screen.dart:408:10` | `unused_element_parameter` — `subtitle` hech qachon berilmaydi |
| `lib/features/payments/ai_payment_sheet.dart:29:26` | `unused_field` — `click` maydoni ishlatilmaydi |
| `lib/features/profile/profile_screen.dart:298:18` | `unused_element` — `_RowSpec.icon` |
| `lib/features/services/api_ai_valuation_job_service.dart:557:43` | `unnecessary_non_null_assertion` — `!` ta'sir qilmaydi |

Qolgan 23 tasi `info` (asosan `withOpacity` deprecatsiyasi, `curly_braces`,
`use_null_aware_elements`).

---

## Mavjud 16 ta yiqilgan test

Bular ham **bizdan oldin** yiqilardi. Sonini oshirmaslik kerak; kamaytirish
xush kelibsiz, lekin bu ishning maqsadi emas.

| # | Fayl | Test |
|---|---|---|
| 1 | `core/app_version_test.dart` | app_version.dart matches pubspec.yaml |
| 2 | `features/auth/auth_scaffold_test.dart` | renders title and body |
| 3 | `features/auth/phone_step_test.dart` | CTA disabled until 9 digits; then fires onSubmit |
| 4 | `features/auth/profile_step_test.dart` | submit blocked when fields missing |
| 5 | `features/auth/profile_step_test.dart` | submit works when all fields valid |
| 6 | `features/auth/small_widgets_test.dart` | GenderToggle selects and emits |
| 7 | `features/market/market_screen_filter_test.dart` | ListingCard lays out under unbounded height |
| 8–11 | `features/profile/profile_screen_test.dart` | 4 ta: menu rows uz, row callback, guest fallback, ru locale |
| 12 | `features/services/ai_scan_intro_skip_test.dart` | admin=true shows the skip and it opens the video step |
| 13 | `features/services/appraiser_category_fallback_test.dart` | fallback category is named in all three locales |
| 14 | `features/services/calculator_pricing_test.dart` | adminka override yetishmagan kalit default qiymatga tushadi |
| 15 | `widget_test.dart` | returning user: splash → home |
| 16 | `widget_test.dart` | home: logged-in shows greeting with name and the three cards |

**№1** (`app_version`) sababi ma'lum va bir qatorlik: `app_version.dart:15`
da `kAppVersion = '1.0.4'`, `pubspec.yaml` da esa `version: 1.0.5+40`.
Ular qo'lda sinxronlanadi va relizda unutilgan. Bu bizning ishimizga aloqasi
yo'q — tuzatish alohida commit bo'lishi kerak.

---

## ⚠️ `otp_step_test.dart` CHETLAB O'TILADI

Skript `test/features/auth/otp_step_test.dart` ni **yurgizmaydi**.

Sabab: undagi `wrong code shows error toast` testi **596 sekund** ishlaydi va
timeout bilan tugaydi. U bilan butun to'plam ~600 s oladi va vaqtning 99 %i
o'sha bitta testga ketadi — 23 qadam davomida har safar 10 daqiqa kutish
mumkin emas.

**Narxi ochiq aytiladi:** shu fayldagi HAQIQIY regressiya bu skriptga
ko'rinmaydi. Agar `lib/features/auth/` ga tegilsa, o'sha faylni QO'LDA
yurgizish kerak:

```bash
flutter test test/features/auth/otp_step_test.dart   # ~600 s
```

360° panorama ishi `lib/features/auth/` ga tegmaydi, shuning uchun bu
cheklov qabul qilingan. Tegiladigan bo'lsa — README yangilansin.

---

## Skript nima qiladi

| Rejim | Nima |
|---|---|
| `bash tool/pano/baseline.sh` | analyze + test |
| `bash tool/pano/baseline.sh --analyze` | faqat analyze (~2 s) |
| `bash tool/pano/baseline.sh --tests` | faqat test |

`flutter test --reporter json` ishlatiladi va `testDone` hodisalari sanaladi.
Oddiy chiqish yiqilganlar sonini ishonchli bermaydi — u yiqilish matni orasida
yo'qoladi. `hidden` yozuvlar (guruh, `setUpAll`) sanoqqa kirmaydi.

Test fayllari ro'yxati **har safar qayta** tuziladi (`find test -name
'*_test.dart'`), ya'ni yangi test fayli qo'shilsa o'zi qamrab olinadi.

`analyze` da **error bo'lsa** skript `1` bilan chiqadi va xatolarni ko'rsatadi.
Warning va info faqat sanaladi — ular yuqoridagi baza bilan solishtiriladi.

---

## Probe ekrani — kamera ziddiyati (6-qadam, QURILMA KERAK)

`lib/features/panorama/screens/pano_camera_probe_screen.dart` — DEV-only
ekran. Uch savolga javob beradi: `camera` plagini yolg'iz ishlaydimi, mavjud
`kadastr/video_capture` yo'li buzilmadimi, va ikkalasi bir vaqtda so'ralganda
`CameraGuard` ziddiyatni yiqilishsiz to'xtatadimi.

Simulyator/emulyatorda ma'nosi yo'q — orqa kamera yo'q. **Haqiqiy telefon
kerak** (iOS ham, Android ham alohida).

### 1. Ochish (vaqtincha, commit QILINMAYDI)

Ekran hech qayerdan bog'lanmagan. `.env` da `admin=true` bo'lsin, so'ng
`lib/main.dart` da IKKI qatorni vaqtincha o'zgartiring:

```dart
// import'lar orasiga:
import 'features/panorama/screens/pano_camera_probe_screen.dart';

// MaterialApp ichida `home: _AppRoot(...)` o'rniga:
home: const PanoCameraProbeScreen(),
```

Sinovdan keyin `git checkout lib/main.dart`.

```bash
flutter run --debug -d <device-id>
```

### 2. Uch sinov

Yuqoridagi yashil/qizil «pill» — `CameraGuard` holati. Pastdagi ro'yxat —
natijalar jurnali (yangi qator eng tepada).

| # | Tugma | KUTILGAN natija |
|---|---|---|
| 1 | `1 · Panorama preview — OCH` | Qora maydonda jonli tasvir. Pill qizil: `CameraGuard: panorama (Ns)`. Jurnalda `panorama: OCHILDI (WxH)`. Yana bosilsa preview yopiladi va pill yashil (`bo'sh`). |
| 2 | `2 · Video capture` (preview YOPIQ holda) | Android — tizim kamerasi ochiladi; iOS — bizning recorder. Yozib tugatilsa jurnalda `video: OK 0.5x · 3840x2160@30fps · 00:05 · 12.3 MB`. Bekor qilinsa `video: bekor qilindi (null)`. Ikkalasidan keyin ham pill YANA YASHIL bo'lishi shart. |
| 3 | `3 · Ikkalasi birga (ziddiyat)` | Preview ochiladi, so'ng video capture so'raladi. Jurnalda **`✅ KUTILGANDEK: panorama ushlab turibdi, video rad etildi`**. Ilova YIQILMASLIGI va preview qotib qolmasligi kerak. |

⚠️ **Yiqilish mezoni.** Agar 3-sinovda `⚠️ video guard'dan O'TDI` chiqsa —
guard ishlamayapti. Agar ilova yiqilsa yoki preview qora bo'lib qotsa —
ziddiyat guard'dan oldinroq, native qatlamda sodir bo'lgan.

### 3. Nima qidiriladi log'da

`CameraGuard` har bir hodisani `debugPrint` bilan yozadi, prefiksi
`[CameraGuard]`. Kutilgan ketma-ketlik 3-sinovda:

```
[CameraGuard] TAKE   panorama
[CameraGuard] DENY   video (band: panorama)
```

**Android:**

```bash
adb logcat -c && adb logcat | grep -E "CameraGuard|CameraX|Camera2|VideoCaptureActivity|AndroidRuntime"
```

- `DENY   video (band: panorama)` — guard ishladi;
- `CameraAccessException`, `ERROR_CAMERA_IN_USE`, `CAMERA_DISABLED` —
  ziddiyat guard'dan o'tib ketgan;
- `Camera 0 is now unavailable` ketma-ket ikki marta — ikki egalik.

**iOS (Xcode → Window ▸ Devices and Simulators ▸ Open Console, yoki
`flutter run` konsoli):**

- `[CameraGuard] DENY   video (band: panorama)` — guard ishladi;
- `AVCaptureSessionWasInterruptedNotification` /
  `AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient` —
  ziddiyat guard'dan o'tgan;
- `Multiple audio/video capture sessions` yoki `-11803` — o'sha.

### 4. Ijara qotib qolmaydimi (eng muhim tekshiruv)

`CameraGuard` ning eng xavfli nosozligi — ijara abadiy band qolishi. Uni
qo'lda sinash:

1. `1 · Panorama preview — OCH` bosing (pill qizil bo'ladi);
2. telefonda **Home** tugmasini bosib ilovani fonga tushiring, so'ng qaytib
   kiring;
3. pill **YASHIL** (`bo'sh`) bo'lishi va log'da
   `[CameraGuard] LIFECYCLE panorama (fondan qaytishda bo'shatildi)`
   chiqishi kerak;
4. shundan keyin `2 · Video capture` ishlashi SHART.

Xuddi shu tarzda: 2-sinov davomida kamera ilovasidan bekor qilib chiqing —
`FREE   video` chiqishi va keyingi urinish ishlashi kerak.

### 5. ⚠️ Hali qoplanmagan uchinchi ega — `lidar`

`CameraGuard` da `lidar` egasi e'lon qilingan, lekin PCScanKit chaqiruvlari
(`lib/features/services/data/room_plan_scanner.dart` — `kadastr/room_plan_scanner`
kanali, `startScan` / `startTexturedScan` / `startTexturedRoomPlan` /
`startObjectCapture` / `startHybridScan`) HALI guard ostiga OLINMAGAN — o'sha
fayl 6-qadamning fayl ro'yxatiga kirmagan. Ya'ni hozir probe faqat
`panorama ↔ video` ziddiyatini o'lchaydi; `ARSession ↔ camera` ziddiyati
ochiq qolgan.

Qoplash bir qatorlik: har bir `invokeMethod` ni

```dart
CameraGuard.run(CameraGuard.lidar, () async { /* mavjud tana */ });
```

ichiga olish (guard bo'sh bo'lganda xatti-harakat o'zgarmaydi).

---

# 3-qadam (MIL-0) — JPEG dekod/resize benchmark

**Savol:** 76 ta 4K kadrni **sof Dart** (`package:image`) bilan dekodlash
telefonda amaliymi? Javob 4-qadam (native `kadastr/pano_codec` kanali)
qilinadimi yoki yo'qmi degan qarorni belgilaydi.

## Bitta buyruq

```bash
bash tool/pano/bench_decode.sh
```

Skript o'zi: qurilmalar ro'yxatini ko'rsatadi → haqiqiy telefonni tanlaydi →
`flutter drive --profile` bilan `integration_test/pano_decode_bench_test.dart`
ni yurgizadi → logdan `PANOBENCH ...` qatorini ajratib chiqaradi va qarorni
aytadi.

Variantlari:

```bash
bash tool/pano/bench_decode.sh -d <device-id>          # qurilmani qo'lda tanlash
bash tool/pano/bench_decode.sh -j /tmp/foto.jpg        # haqiqiy 4K foto (Android: adb push)
bash tool/pano/bench_decode.sh --device-jpeg /var/.../pano_bench.jpg   # foto allaqachon qurilmada
bash tool/pano/bench_decode.sh --debug                 # faqat "yuradimi?" (RAQAMLARI YAROQSIZ)
```

## ⚠️ Uchta shart — buzilsa raqam yolg'on

1. **HAQIQIY TELEFON.** Simulyator/emulyator host protsessorining tezligini
   ko'rsatadi (Mac'da dekod ~270 ms, telefonda 3–5× ko'p), ustiga profile
   rejimi ularda umuman qo'llab-quvvatlanmaydi.
2. **AOT (`--profile`).** `flutter test integration_test/...` ilovani DEBUG
   (JIT) da yig'adi va `--profile` bayrog'ini QABUL QILMAYDI — shu sababli
   skript `flutter drive` ishlatadi (`integration_test/pano_bench_driver.dart`).
   Rejim chiqishda `mode=` bilan ko'rinadi; `mode=debug` bo'lsa raqamni
   tashlang.
3. **Manba kadr.** Foto berilmasa test sintetik kadr yasaydi
   (`tool/pano/gen_test_jpeg.dart`) — u ataylab shovqinli, ya'ni dekod
   **PESSIMISTIK** (yuqori chegara). Haqiqiy 4K kamera kadri TAVSIYA etiladi.

Sintetik kadrni qo'lda yasash:

```bash
dart run tool/pano/gen_test_jpeg.dart /tmp/pano_bench.jpg
# 3840x2160, ~2.7 MB
```

## Nima o'lchanadi

Har biri **10 takror** (+1 isitish), natija — **MEDIANA** (o'rtacha emas:
termal throttling va GC bitta-ikkita takrorni ikki barobar cho'zadi).

| O'lchov | Nima uchun |
|---|---|
| `decodeJpg(3840×2160)` | quvurdagi eng og'ir takrorlanuvchi qadam (×76) |
| `copyResize(3840×2160 → 702×1248, AREA)` | reja §5.2 dagi kadr keshini tayyorlash |
| `encodeJpg(3072×1536, q90)` | yakuniy equirect'ni saqlash (§10.1) |
| `peakRss` MB | §5.2 dagi xotira byudjeti haqiqatga to'g'ri keladimi |

Chiqish (mashina o'qiy oladigan qator):

```
PANOBENCH decodeJpg_ms=NNN resizeArea_ms=NN encodeJpg_ms=NNN peakRss_mb=NNN
```

## QAROR jadvali

| median `decodeJpg` | Qaror |
|---|---|
| **≤ 1200 ms** | sof Dart dekod **QOLADI**, 4-qadam **O'TKAZILADI** (native kanal qurilmaydi) |
| **> 1200 ms** | 4-qadam **MAJBURIY** — native `kadastr/pano_codec` kanali |

1200 ms qayerdan: 76 kadr × 1.2 s ≈ **91 s** bitta yadroda, 4 isolate'da
≈ 23 s. Undan yuqorisi 76 kadrli oqimni foydalanuvchi kutolmaydigan
darajaga olib chiqadi.

⚠️ Chegaraga **sintetik** kadr bilan yiqilgan bo'lsa — qaror qilishdan oldin
haqiqiy foto bilan qayta o'lchang: sintetika 1.3–2× jarima qo'shishi mumkin.

## Natija — QURILMADA O'LCHANADI (bo'sh)

O'lchagandan keyin shu jadvalni to'ldiring:

```
sana        :
qurilma     :                     (model, iOS/Android versiyasi)
rejim       :                     (profile bo'lishi SHART)
manba kadr  :                     (haqiqiy foto / sintetik)
```

| O'lchov | Mediana | min | max |
|---|---|---|---|
| `decodeJpg_ms` |  |  |  |
| `resizeArea_ms` |  |  |  |
| `encodeJpg_ms` |  |  |  |
| `peakRss_mb` |  | — | — |

**QAROR:** ☐ sof Dart qoladi (4-qadam o'tkaziladi) ☐ 4-qadam majburiy

**Izoh:**

---

### Ma'lumot uchun: host raqamlari (QAROR UCHUN YARAMAYDI)

Solishtirish uchun, 2026-09-10, MacBook (darwin arm64), sintetik kadr:

| | JIT (`dart run`, host) | iPhone 16 Pro **simulyatori**, debug |
|---|---|---|
| `decodeJpg` | 293 ms | 271 ms |
| `copyResize` | 66 ms | 94 ms |
| `encodeJpg` | 201 ms | 183 ms |
| `peakRss` | 539 MB | 629 MB |

Bu raqamlar Mac protsessorining tezligi — telefonniki EMAS. Ular faqat
harness ishlayotganini ko'rsatadi.

---

# MIL-1 — 8 kadrni tikish (13-qadam, QURILMA KERAK)

**Butun yondashuvning qaror darvozasi.** MIL-0 «kadrni dekod qila
olamizmi» degan savolga javob berdi; bu esa «hammasini TIKA olamizmi»
degan savolga javob beradi.

## Bitta buyruq

```bash
bash tool/pano/bench_stitch.sh -f ~/Desktop/kadrlar
```

Android'da skript kadrlarni `adb push` bilan o'zi ko'chiradi. iOS'da adb
yo'q — kadrlarni qurilmaga o'zingiz joylang va yo'lini bering:

```bash
bash tool/pano/bench_stitch.sh --device-dir <qurilmadagi papka>
```

## Kadrlar qanday nomlanadi

Burchaklar FAYL NOMIDAN o'qiladi, chunki capture ekrani (19-qadam) hali
yozilmagan va sensor yozuvlari yo'q:

```
y000_p0.jpg   y045_p0.jpg   y090_p0.jpg   y135_p0.jpg
y180_p0.jpg   y225_p0.jpg   y270_p0.jpg   y315_p0.jpg
```

`y<yaw>_p<pitch>` — yaw daraja bo'yicha soat yo'nalishida, pitch
gorizontdan yuqoriga musbat. Kamida 2 ta kerak, MIL-1 uchun **8 ta**
tavsiya etiladi (bitta gorizont halqasi).

Kadrlarni qo'lda olsangiz: bir joyda turib, telefonni tik ushlab, har
45° da bitta surat. Aniqlik muhim emas — o'lchov TEZLIKNI ko'radi.

## ⚠️ QAROR `extrapolated76_s` GA QARAB QABUL QILINADI

Bu bosqichda **gains (14), seam (15) va blend (16) hali yozilmagan**,
ya'ni o'lchov yakuniy quvurning atigi **56 %ini** ko'radi
(`kMil1Share` = decode 0.10 + project 0.44 + finish 0.02).

Xom `measured_ms` ga qarash «GO» ni **qariyb ikki barobar optimistik**
qilardi. Skript ekstrapolyatsiyani o'zi hisoblaydi:

```
extrapolated76 = measured × (76 / kadr_soni) / 0.56
```

Masalan 8 kadr 10 sekundda tikilsa — bu yaxshi ko'rinadi, lekin
ekstrapolyatsiya **170 s** beradi, ya'ni 120 s chegarasidan OSHADI.

## QAROR jadvali

| `extrapolated76_s` | Qaror |
|---|---|
| **≤ 120 s** | **GO** — sof Dart yetadi, 14–16-qadamlarga o'tiladi |
| **> 120 s** | **NO** — quvur yengillashtiriladi (pastga qarang) |

120 s qayerdan: foydalanuvchi suratga olishga ~2 daqiqa sarflaydi;
tikish undan uzoq davom etsa oqim tashlab ketiladi.

**NO bo'lsa variantlar** (arzonidan qimmatiga):

1. **Isolate'larga bo'lish** — `horizontalSlices` va `roiIntersectsRows`
   allaqachon yozilgan va test bilan qoplangan (tasmalarga bo'lingan
   natija yaxlit natija bilan baytma-bayt bir xil). 4 yadroda ~4×.
2. **Tuvalni kichraytirish** — 3072 → 2048 proyeksiya yukini ~2.25×
   kamaytiradi (piksel soni kvadratga proporsional).
3. **Kadr sonini kamaytirish** — 76 → 40 (qutblarni tashlash + ±45
   qatorlarini siyraklashtirish). Qamrov tushadi.
4. **Native kanal** — eng qimmati, MIL-0 da o'tkazib yuborilgan bo'lsa
   qaytib kelish.

## Natija — QURILMADA O'LCHANADI (bo'sh)

```
sana        :
qurilma     :                     (model, iOS/Android versiyasi)
rejim       :                     (profile bo'lishi SHART)
kadr soni   :
```

| O'lchov | Qiymat |
|---|---|
| `measured_ms` | |
| `decode_ms` | |
| `project_ms` | |
| `finish_ms` | |
| `extrapolated76_s` | |
| `coverage_deg` | |

**QAROR:** ☐ GO (14-qadamga) ☐ NO (quvur yengillashtiriladi)

**Izoh:**

⚠️ `coverage_deg` ni ham qarang: bitta gorizont halqasi ~46° beradi.
180° ga yaqin son chiqsa — bu XATO alomati (qamrov piksellardan
o'lchanadi, nisbatdan emas).
