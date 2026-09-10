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

## Kamera ziddiyati proboni — OLIB TASHLANDI (2026-09-11)

Bu yerda `CameraGuard` ziddiyatini qurilmada tekshiradigan DEV-only ekran
turardi. U OLIB TASHLANDI, chunki tekshiradigan ziddiyatning O'ZI yo'q:

360° ish Bozor e'lon sehrgari uchun so'ralgan. AI Baholash kamerasini
(`video_capture.dart`, `room_plan_scanner.dart`) qayta qurish so'ralmagan
edi va u fayllar ASL HOLIGA qaytarildi. `CameraGuard` ning o'zi
`lib/features/panorama/data/camera_guard.dart` da qoladi — u sof, test
bilan qoplangan va hech kimga bog'lanmagan.

⚠️ **19-qadamda ziddiyat HAQIQIY bo'ladi** — panorama capture ekrani
kamerani ochadi, AI Baholash ham ochadi, iOS'da ikkalasi bir vaqtda
ochilsa sessiya qotadi. O'shanda MAVJUD kodga tegishdan oldin so'raladi.
Birinchi ko'riladigan muqobil — panorama ekrani o'zi ochilishdan oldin
bandlikni tekshirsin, ya'ni AI Baholash fayllariga umuman tegilmasin.

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
