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

## Nima bo'ldi: tikish SERVERGA ko'chdi (2026-09-12)

Bu papkada qurilmada tikishni o'lchaydigan ikkita benchmark
(`bench_decode.sh`, `bench_stitch.sh`) va ularning MIL-0/MIL-1 qaror
darvozalari turardi. Ular **o'chirildi**, chunki javob berilgan savolni
o'lchardi: sof Dart bilan telefonda tikish tashlab yuborildi.

Endi telefon faqat KADR YIG'ADI (iOS: ARKit, `ios/Runner/PanoCapture.swift`)
va ularni serverga yuboradi; tikish `kadastr-backend` da, alohida `panorama`
Celery navbatida bajariladi. Shu sababli:

* `lib/features/panorama/stitch/**`, `math/rotation.dart`, sensorga tayangan
  capture ekrani va ularning testlari o'chirildi;
* `integration_test/**` butunlay o'chdi (unda faqat shu ikki benchmark bor
  edi), `integration_test` dev-bog'liqligi ham `pubspec.yaml` dan olindi;
* `CameraGuard` ham o'chdi — nativ capture kamerani o'zi boshqaradi.

`baseline.sh` QOLADI: u panorama ishiga bog'liq emas, oddiy
«analyze + test, `otp_step_test.dart` siz» yugurtirgichi.
