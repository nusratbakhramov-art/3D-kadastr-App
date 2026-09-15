# Bozor AI v2 — ketma-ket reja

> Manba: [`docs/bozor-v2-figma-map.md`](./bozor-v2-figma-map.md) (SOTUV oqimi, 89 freym) va
> [`docs/bozor-ai-figma-map.md`](./bozor-ai-figma-map.md) (IJARA oqimi, 55 freym).
>
> Repolar: `mobile` (Flutter) va `kadastr-backend` (FastAPI).

---

## 1. Qisqacha xulosa

### Nima o'zgaradi

1. **Sehrgar 7 → 8 qadam** bo'ladi, lekin **faqat sotuvda**: yangi **4/8 «Сделка»** qadami
   (Тип продажи, Лет в собственности, Собственники, Прописано). Qadamlar ro'yxati endi
   `PropertyType` ga emas, **(DealType × PropertyType)** juftligiga bog'lanadi.
   Ijara oqimi **piksel darajasida o'zgarmaydi**.
2. **7-chi mulk turi** — `Квартира в новостройке` (`new_building_apartment`).
3. **Narx qadami sotuv rejimi** — davr yo'q (`UZS`/`USD`), yorliq mulk turiga qarab,
   sutkalik narx yo'q, yangi **«Ипотека»** toggle.
4. ~~**Kontakt SMS tasdiqlash** haqiqiy bo'ladi (hozir UI stub) — 2 ta yangi backend endpoint.~~ **BEKOR (2026-09-11):** tasdiqlash UMUMAN yo'q — «Yuborish» tugmasi, kod
   kataklari va taymer 6-qadamdan olib tashlandi. Qadamlar **30, 31, 32** bekor qilindi.
5. **Dizayn deltalari**: foto boshqaruv ekrani, maydon birligi dropdowni (`соток`/`м²`),
   xonalar `10+`, `Площадь балкона`, segmented picker'lar, picker qidiruvi, xarita qidiruvi.
6. **Uzilgan halqalar yopiladi** (bu dizayndan mustaqil, lekin busiz hech narsa ko'rinmaydi):
   MinIO public-read, thumbnail, moderatsiya UI, «Mening e'lonlarim», e'lonlar lentasi, detal,
   e'lonni tahrirlash.
7. **Butun sotuv oqimi feature-flag ostida** — `app_settings.bozor_sale_enabled`.
   Bayroqning **ikkala yarmi** ham yoziladi: backend (M2-14) va **mobil gate (M2-17b)**;
   yoqilishi — M3-22. Rollback'da bayroq serverdan `false` bo'ladi va yangi ilova versiyasi ham
   sotuvni ko'rsatmaydi.

### HOLAT — 2026-09-11

**M2 (backend) va M3 (mobil) KOD JIHATDAN BAJARILDI.** Sotuv oqimi uchidan-uchiga
yozilgan, lekin **`bozor_sale_enabled` hamon `false`** — foydalanuvchi hali ko'rmaydi.

| Qadam | Holat |
|---|---|
| M2-14…16 (option'lar, ustunlar, `DealIn`) | ✅ backend `feat/bozor-sale-flow` |
| M3-18 (`wizardSteps` → DealType × PropertyType) | ✅ `wizardStepsFor()` |
| M3-19 (4/8 «Сделка» ekrani) | ✅ `bozor_deal_step_screen.dart` |
| M3-20 (sotuv narx rejimi) | ✅ davrsiz birlik, turga mos yorliq, «Ипотека» |
| M3-21 (`newBuildingApartment`) | ✅ 7-chi mulk turi |
| M3-22 (parity) | ✅ fixture qayta generatsiya qilindi (86 → **111** maydon) |
| M3-22 (bayroqni YOQISH) | ⛔ **QILINMADI** — pastdagi shartga qarang |

⚠️ **Option KODLARI hamon TASDIQLANMAGAN** (`sale_type`, `ownership_years`,
`owners_count`, `registered_count` — so'rov B, `docs/bozor-v2-blockers.md`). Ular
dizayndan chiqarilgan taxminiy to'plam. **Hozir o'zgartirish ARZON**: prod'da e'lon
umuman yo'q (`GET /listings/` → `total: 0`) va sotuv yopiq, ya'ni migratsiya ham,
ma'lumot ko'chirish ham kerak emas — ikki faylda bir necha qator.

**Bayroqni yoqish sharti:** (a) mijoz kodlarni tasdiqlasin, (b) backend prod'ga
chiqsin va `ensure_bozor_listings` ustunlarni qo'shsin, (c) haqiqiy qurilmada
sotuv oqimi uchidan-uchiga sinalsin. Uchalasidan keyin:
`UPDATE app_settings SET bozor_sale_enabled = true;` (adminkada bu bayroq YO'Q).

### Nega shu tartibda

Bugun backend to'liq ishlaydi (`POST /listings/` → `pending` → `GET /listings/`), lekin
**uchta halqa uzilgan**:

- moderator e'lonni tasdiqlay olmaydi (UI yo'q — na sqladmin view, na SPA sahifasi);
- `listings/media/` MinIO'da public-read emas → har bir foto 403;
- tasdiqlangan e'lon ilovada **hech qayerda ko'rinmaydi** (lenta yo'q, «E'lonlarim» — mock).

Shu uchtasi yopilgach (M1), keyingi **har bir sotuv qadamini haqiqiy ilovada uchidan-uchiga**
tekshirish mumkin bo'ladi. Aks holda 20+ qadam faqat `curl` bilan sinaladi.

### ⚠️ Tuzatish — «Продажа» YANGI FUNKSIYA EMAS, YARIM QOLGAN FUNKSIYA

Bu 89 freym alohida mahsulot emas: ular **avvalgi 55 freymning davomi**. Eski to'plam
(`1228-*`) **butunlay ijara** edi va `docs/bozor-ai-figma-map.md` §7 №1 aynan shuni yozgan:
«No Sale wizard was supplied… Ask for the Sale frames before finalising the price model.»
Mana o'sha sotuv freymlari. Ya'ni sehrgar **bitta**, dizayn to'plami **bitta**, faqat ikkinchi
yarmi endi keldi.

Buning amaliy oqibati (rejaning boshqa joyida to'g'ri aks etmagan edi):

**Bugun `Продажа` ni tanlash MUMKIN va u BUZUQ ishlaydi.**
`bozor_type_step_screen.dart:41` — `options: DealType.values`, ya'ni pickerda ikkala qiymat ham
turibdi. Tanlansa foydalanuvchi ijara shaklidagi sehrgarni oladi:
`bozor_price_step_screen.dart:148` shartsiz `bozor.price.rent` («Арендная плата») yorlig'ini,
`UZS/oy` birligini va sutkalik narx maydonini ko'rsatadi; «Сделка» qadami yo'q.

Shuning uchun `bozor_sale_enabled` bayrog'i — **yangi funksiya darvozasi emas, buzuq yo'lni
yopadigan qalqon**. Demak **M2-17b (mobil gate) M0 ga ko'chiriladi** va M1 relizidan OLDIN
chiqadi: aks holda M1 ni («ijara oqimi to'liq tirik») relizga bersak, foydalanuvchi hamon
`Продажа` ni tanlab, ijara yorliqli narx qadamiga tushib qoladi.

**Qattiq qoida:** backendda maydon paydo bo'lmaguncha mobil uni yubormaydi —
`listing_param_schema.validate()` notanish kalitni **400** bilan rad etadi.

---

## 2. ⚠️ ZIDDIYATLAR — QAROR KERAK

> Bu jadval **rejadan oldin** o'qilishi kerak. **15 qator (Z1–Z15).** Har qatorda: dizayn nima
> deydi, bizda nima bor, tavsiyamiz, va **javob kelmasa nima qilamiz** (default).
>
> Ular §7 dagi **ochiq savollardan farq qiladi**: bu yerda default javob **bor**, ya'ni javob
> kelmasa ham reja to'xtamaydi. §7 dagilarda default yo'q (yoki bloklovchi).

| # | Mavzu | Dizayn | Bizda | Tavsiya | Default (javob kelmasa) | Bloklaydi |
|---|---|---|---|---|---|---|
| **Z1** | **OTP uzunligi** | 6 katak (`293:12214`, `293:12460`) | 5 — mobil `_codeLength`, backend `generate_code()` 10000..99999, `VerifyOTPRequest` min=max=5, **PlayMobile shabloni 5 uchun tasdiqlangan** | **5 da qolamiz.** 6 ga o'tish = backend + SMS shabloni qayta tasdig'i (haftalar) | 5 | **M4-30, M4-31** |
| **Z2** | **Telefon tasdiqlash majburiymi** | Majburiy demaydi, lekin butun 7/8 shu atrofida qurilgan | Ixtiyoriy (`_isComplete = ism + 9 raqam`) | **Ixtiyoriy qoldiramiz**, `contact_phone_verified` moderatsiyada ko'rinadi | Ixtiyoriy | M4-31 |
| **Z3** | **Qadamlar soni 7 → 8** | 8 (Другая нежилая'da 7) | 7 / 6 | Faqat **sotuv** oqimi 8 ga o'tadi; ijara tegilmaydi | Shunday | M3-18 |
| **Z4** | **Success matni** | «Объявление опубликовано успешно» | `POST /listings/` **HAR DOIM** `status='pending'` | **«E'lon moderatsiyaga yuborildi»** — aks holda foydalanuvchi lentadan e'lonini topmay shikoyat qiladi | Moderatsiya matni | M1-10 |
| **Z5** | **Rozilik checkbox** | Belgilangan holda keladi | `TermsDraft.accepted = false` (ataylab, huquqiy sabab) | **Dizayndan ongli chekinamiz** | `false` | M4-35 |
| **Z6** | **«Все параметры» yulduzchalari** | Безопасность / Удобства / Благоустройство / Инфраструктура = **majburiy** | `optional: true` (ikkala tarafda) | **Ixtiyoriy qoldiramiz** — majburiy qilsak konversiya tushadi va mavjud e'lonlar tahriri buziladi | Ixtiyoriy | M4-29 |
| **Z7** | **Kommunallar** | select «Да» + picker | toggle | **Toggle'da qolamiz** — backend `TOGGLE` sifatida validatsiya qiladi, o'zgartirish `listing_param_schema.py` ni buzadi | Toggle | — |
| **Z8** | **E'lon sarlavhasi (`title`)** | **Hech bir qadamda YO'Q** | 6-qadamda bor, backend `title` NOT NULL (min 3) | (a) maydon qoladi / (b) backend avtomatik yasaydi («3-xonali kvartira, Yunusobod») / (c) dizaynga qo'shiladi. **Tavsiya: (a)** | (a) — maydon qoladi | M4-24 |
| **Z9** | **«Топ» tarifi = tanga iqtisodi** | 14🪙/7 kun, «Выделеные цветом» 7🪙, balans, chek, 6 to'lov usuli, 360 paketlari | **Hech narsa yo'q** (mobil ham, backend ham) | **M6 epic** sifatida ajratiladi; hozircha `app_settings.bozor_top_enabled = false` bilan **«Топ» kartasi umuman yashiriladi** | Yashiriladi | M4-35, M6-39 |
| **Z10** | **Коммерческая yer maydoni birligi** | `соток` (`1414-18872`) | `м²`; backend `_derive()` x100 ni faqat `property_type=='land'` da qiladi | Birlik **foydalanuvchi tanlaydi** va **saqlanadi**; NULL bo'lsa **eski xatti-harakat fallback** | Birlik saqlanadi | M2-15, M4-26 |
| **Z11** | **Bottom bar** | Har ekranda 5 tabli panel | 4 tab, sehrgar to'liq ekran push | **Ko'chirilmaydi** (avvalgi kelishuv) | Ko'chirilmaydi | — |
| **Z12** | **Media moderatsiyagacha ochiq** | — | `listings/media/` public-read qilinsa **tasdiqlanmagan** e'lon rasmlari URL bo'yicha ochiq | Public-read + **yetim fayl GC** (M1-4). Alternativa (private prefiks + proksi / copy-on-approve) — qimmat | Public-read + GC | M1-4 |
| **Z13** | **PDF планировка** | Hujjat ikonkasi (PDF kutilayotgandek) | Backend ruxsat beradi, mobil faqat `ImagePicker` | `file_picker` pubspec'da bor — yoqish arzon | Yoqamiz | M4-23 |
| **Z14** | **1-qadam ro'yxatlarining manbai** | — | Mobil lokal enum + backend `listing.option.*` — **ikki manba**; `BozorApi.reference()` yozilgan lekin **hech qayerdan chaqirilmaydi** | Lokal enum'da qolamiz (offline ishlaydi), lekin `reference()` ni `topTierEnabled` uchun ulaymiz | Lokal enum | M4-35 |
| **Z15** | **Majburiylik belgisi teskari** | **Ixtiyoriy** maydon belgilanadi: yorliq yonida kulrang «(по желанию)» | **Majburiy** maydon belgilanadi: qizil `*` (`0xFFE0492A`, 14pt). 7 ta maydon widget'ida takrorlangan (`WizardField`, `SelectField`, `MultiSelectField`, `BozorPhoneField`, `PriceField`, `AddressPinField`, `ParamForm`) | **Qizil `*` da qolamiz.** «(по желанию)» ga o'tish shu 7 widget'ni o'zgartiradi, ular esa AI Baholash / 3D kadastr / kalkulyator TZ sehrgarlarida ham ishlatiladi — **lokal delta butun ilovaga tarqaydi** | Qizil `*` | **M3-19** (4/8 da 4 maydondan 3 tasi ixtiyoriy — farq eng ko'zga tashlanadigan joy), M4-24 |

---

## 3. Bloklovchilar jadvali (savol → qadam)

| Bloker | Kimdan | Qaysi qadamni bloklaydi | Javob kelmasa |
|---|---|---|---|
| `sale_type`, `ownership_years`, `owners_count`, `registered_count` **to'liq ro'yxatlari** | Mijoz / dizayner | **M2-15 + M2-16** — kodlar prod'da **abadiy qoladi**. ⚠️ M2-15 ham bloklanadi: `owners_count` / `registered_count` **ustun turi** ro'yxat shakliga bog'liq (sof son mi, yoki `6_plus` kabi kodmi) | ⛔ M2-16 **BOSHLANMAYDI**. M2-15 esa **`String(8)` bilan boshlanadi** (xarita §11 izohi: `String` ikkala holatni ham ushlaydi, `SMALLINT` esa `6_plus` chiqsa prod'da `ALTER COLUMN TYPE` talab qiladi — alembic 3 head bilan buzuq). Zaxira: M0-2 da so'rov yuborilgan, javob 5 ish kunida kelmasa taxminiy to'plam + `docs/` da «o'zgartirish qimmat» ogohlantirishi bilan davom etamiz |
| **O'qilmagan 7 freym** (`1414-21717`, `1414-21438`, `1414-21488`, `1414-21563`, `1414-21605`, `293-12538`, `293-12539`) — ⚠️ 2026-09-10 da qayta urinildi: Figma kvotasi tugagan (`try again tomorrow`), **ertaga o'qish mumkin** | Figma (kvota tiklangach) | **M3-18** (`wizardSteps` testlari), «Другая нежилая» varianti | Agar ular qo'shimcha qadam bo'lsa — M3-18 va M3-19 qayta yoziladi. Shuning uchun M0-2 da so'raladi |
| **PlayMobile SMS shabloni** tasdig'i | Operator (tashqi, haftalar) | **M4-30** ning prod'ga chiqishi (kod emas) | Ishlab chiqish `DEBUG_OTP_CODE` / demo raqam bilan davom etadi; prod'ga chiqish shablonsiz **bloklanadi** |
| **4/8 «Сделка» ijara oqimida ham bormi?** | Mijoz / dizayner | **M3-18** (`wizardSteps` matritsasi) va **M3-19** (ekran) | Default: **«faqat sotuvda»** (bizning xulosamiz). «Ha» javobi kelsa — 4 kombinatsiya 2 ga tushadi, testlar va header raqamlari qayta yoziladi. §7, 15-savol |
| **Z8** (title) | Mahsulot | **M4-24** (6/8 ekrani) | Default (a) — maydon qoladi |
| **Z9** (tanga) | Mahsulot | **M6** butun bosqich | Default — «Топ» yashiriladi |

---

## 4. Reliz chizig'i (bosqich = yetkaziladigan qiymat)

| Bosqich | Nima yetkaziladi | Agar shu yerda to'xtasak |
|---|---|---|
| **M0** | Baseline commit, bloklovchi so'rovlar, i18n gigiyenasi | Hech narsa buzilmaydi, deploy xavfsiz |
| **M1** | **IJARA oqimi TO'LIQ TIRIK**: e'lon → moderatsiya → lenta → detal → «E'lonlarim» → tahrirlash | ✅ **Mustaqil reliz mumkin.** Sotuv yo'q, lekin mahsulot ishlaydi |
| **M2** | Sotuv ma'lumot modeli (backend) — ustunlar, option'lar, `DealIn` — **va mobil `sale_enabled` gate'i (17b)** | Mobil hali yubormaydi; eski klientlar buzilmaydi; foydalanuvchi «Продажа» ni ko'rmaydi |
| **M3** | **SOTUV OQIMI TIRIK** (8 qadam, mobil) | ✅ **Mustaqil reliz mumkin** (`bozor_sale_enabled` bayrog'i bilan) |
| **M4** | Dizayn deltalari (foto ekrani, OTP, birlik, picker'lar, xarita, qoralama) | ✅ Reliz mumkin, sifat yaxshilanadi |
| **M5** | Lenta filtrlari, saralash, indekslar, regression, deploy intizomi | ✅ Reliz mumkin |
| **M6** | Tanga / balans / «Топ» / 360º — **alohida epic** | Hujjat yoziladi, kod yozilmaydi |

**Feature-flag:** butun sotuv oqimi `app_settings.bozor_sale_enabled` bayrog'i ostida turadi.
Bayroqning **ikkala yarmi ham** yozilishi shart, aks holda uning hech qanday ma'nosi yo'q:

| Yarim | Qadam | Nima qilinadi |
|---|---|---|
| **Backend** | **M2-14** | `app_settings.bozor_sale_enabled` (default `false`) + `reference()` javobiga `sale_enabled` maydoni |
| **Mobil** | **M0-17b** (⚠️ M2 dan M0 ga ko'chirildi — yuqoridagi tuzatish) | `ListingReference.saleEnabled` parsing + sehrgar boshida `reference()` chaqiruvi + 1-qadamda «Продажа» ni yashirish (xato/offline → `false` fallback) |
| **Yoqish** | **M3-22** | Parity testi yashil bo'lgach `bozor_sale_enabled = true` |

⚠️ Hozir `ListingReference` **faqat** `top_tier_enabled` ni parslaydi
(`lib/features/bozor/data/bozor_api.dart:218`), `BozorApi.reference()` esa umuman
**chaqirilmaydi** — shuning uchun mobil yarim (**M2-17b**) alohida qadam sifatida ajratilgan va
u **M3 dan oldin** bajariladi. M2 va M3 orasida foydalanuvchi 1-qadamda «Продажа» ni
**umuman ko'rmaydi**.

---

# 5. Qadamlar

---

## M0 — Poydevor

### 1. Baseline commit + untracked fayllarni saqlash

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `mobile/lib/features/bozor/` (27 fayl, 5884 qator), `mobile/assets/i18n/bundle.json`, `mobile/lib/features/shell/main_shell.dart`, `kadastr-backend/app/services/listing_option_labels.py`, `kadastr-backend/app/services/app_translation_seed.py` |

**Nega shu o'rinda.** Butun Bozor feature'i hozir **untracked** (`?? lib/features/bozor/`) va
bundle.json'dagi 156 bozor kaliti unstaged. Backendda `listing_option_labels.py` ham `??` —
uning importi `app_translation_seed.py:42` da **try/except DAN TASHQARIDA**, modul darajasida
(`APP_TRANSLATION_SEED = _with_option_labels(...)`, 53-qator). Bu fayl deploy'ga tushmasa
**butun API startup'i yiqiladi**. Keyingi 38 qadamning har biri diff bilan tekshiriladi —
baseline bo'lmasa nima o'zgargani ko'rinmaydi.

**Tugadi mezoni.**
`git status` ikkala repoda toza; `git ls-files kadastr-backend/app/services/listing_option_labels.py`
natija beradi; `cd kadastr-backend && python -c "import app.main"` xatosiz;
`cd mobile && flutter analyze` xatosiz; `pytest -q` natijasi **yozib olingan** (hozir yiqilayotgan
testlar ro'yxati ma'lum — keyingi qadamlarda taqqoslanadi).

**Xavf.** Past. Yagona xavf — `.gitignore` sabab fayl tushmay qolishi; `git ls-files` bilan
tekshiriladi.

---

### 2. Bloklovchi so'rovlar: Figma freymlari, option qiymatlari, SMS shabloni

| | |
|---|---|
| **Repo** | — (tashqi) |
| **Fayllar** | `docs/bozor-v2-figma-map.md` (§12 83–89, §10) |

**So'rov matnlari:** [`docs/bozor-v2-blockers.md`](./bozor-v2-blockers.md)

**Nega shu o'rinda.** Uchta narsa **kalendarga bog'liq** va rejaning ichida turib kutib bo'lmaydi:
(a) 7 ta o'qilmagan freym — agar ular «Другая нежилая» oqimining qo'shimcha qadamlari bo'lsa,
M3-18/19 qayta yoziladi; (b) `sale_type` / `ownership_years` / `owners_count` /
`registered_count` **kod qiymatlari prod e'lonlarida abadiy qoladi** — keyin o'zgartirish
migratsiya talab qiladi, alembic esa 3 head bilan buzuq; (c) PlayMobile shabloni operator
tomonidan tasdiqlanadi (haftalar) — kod tayyor bo'lib shablon kutilib qolmasin.

**Tugadi mezoni.** Uchala so'rov yuborilgan va `docs/bozor-v2-figma-map.md` da javob sanasi
qayd etilgan. PlayMobile'ga yangi shablon matni («e'lon kontaktini tasdiqlash») tasdiqlashga
topshirilgan. Ishlab chiqish shu payt `DEBUG_OTP_CODE` / demo raqam (`+998990000011`, kod `00000`)
bilan davom etadi.

**Xavf.** O'rta. Javob kechiksa M2-16 bloklanadi — §3 dagi zaxira qoidasi qo'llanadi.

---

### 3. i18n seed sinxroni: 269 kalit backendga, 4 kalit mobilga

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `kadastr-backend/app/data/app_translation_seed.json`, `mobile/assets/i18n/bundle.json`, `kadastr-backend/tests/test_i18n_seed_single_source.py` |

**Nega shu o'rinda.** Hozir mobil bundle'da bor, backend seed'da **yo'q 269 kalit**
(bozor 156, services 108, home 4, scan 1) → `test_mobile_bundle_keys_are_all_seeded` **qizil**.
Keyingi har bir qadam yangi kalit qo'shadi — jadval qizil turgan bo'lsa yangi desync **ko'rinmaydi**.
Teskarisiga: `services.scan.status.call_center`, `.cc_generic`, `.cc_low_confidence`,
`.cc_no_comparables` bundle'da yo'q va `ai_status_screen.dart:1738` ularni ishlatadi → **xom kalit**
ekranda.

**Tugadi mezoni.** `pytest tests/test_i18n_seed_single_source.py -q` → **7/7 yashil** (skip emas).
`python -m scripts.seed_app_translations` → `inserted: 269`.
`GET /api/v1/i18n/bundle` javobida `bozor.desc.add_360` bor.

**Xavf.** Past. ⚠️ `listing.option.*` kalitlarini JSON'ga **QO'LDA yozmang** — ular
`listing_option_labels.py` dan generatsiya bo'ladi; dublikat bo'lsa fayl g'olib chiqadi va
kod bilan ajralib ketadi (`test_generated_option_labels_reach_the_seed` shuni ushlaydi).

---

## M1 — Uzilgan halqalarni yopish (mavjud oqim tirik bo'lsin)

### ⚠️ M1 QAMROVI O'ZGARDI (2026-09-10, foydalanuvchi aniqlashtirdi)

**Talab.** Home'dagi «Bozor AI» kartasi **ikki tabli** ekranni ochadi:

| Tab | Nima ko'rinadi |
|---|---|
| **«E'lonlar»** | ommaviy lenta — `approved` e'lonlar (`GET /listings/`) |
| **«Mening e'lonlarim»** | MENING hamma e'lonim: **tugatilmagan qoralamalar**, `pending`, `approved`, `rejected`, `archived` |

«Mening e'lonlarim» tabida **«E'lon qo'shish»** tugmasi turadi — sehrgarni ochadi.

**Rejaga ta'siri:**

1. **8- va 12-qadam BIRLASHADI.** Ular alohida ikki ekran emas, bitta ikki tabli ekranning
   ikki tabi. `my_listings_screen.dart` (hozir `mockListings`) shu tabga aylanadi.
2. **34-qadam (sehrgar qoralamasini saqlash) M4 dan M1 ga KO'CHADI.** Sababi oddiy:
   qoralamalar saqlanmasa «tugatilmagan qoralamalar» ro'yxati BO'SH bo'ladi, ya'ni
   talabning yarmi ishlamaydi. Qoralamasiz bu tabni yozish ma'nosiz.
3. **YANGI backend qadami kerak** — qoralama endpointlari (pastda).
4. Qoralamani bosganda sehrgar **o'sha qadamdan** ochilishi kerak (resume).
   Loyihada naqsh bor: `lib/features/services/ai_draft_resume.dart`.

### Qoralama dizayni — mavjud naqshga ergashiladi

AI Baholash oqimi allaqachon SERVER tomonda qoralama saqlaydi (lokal emas):
`POST /ai-valuations/draft` → `PATCH /{id}/draft` (har qadamda, `current_step` bilan) →
`GET /drafts` → `POST /{id}/submit` (draft → queued). Qismli ma'lumot
`request_payload: Mapped[dict] = mapped_column(JSON)` da yotadi — sxema DB'da emas,
so'rov chegarasida majburlanadi (`ai_valuation_job.py:106`). Bozor qoralamasi ham SHUNDAY.

**Lekin bitta farq bilan: ALOHIDA JADVAL** — `bozor_listing_drafts`, `bozor_listings` emas.

| Variant | Nega tanlanmadi / tanlandi |
|---|---|
| (a) bir jadval, `status='draft'` + ko'p NULL ustun | ⛔ `bozor_listings` da 46 ustun, ularning ko'pi `NOT NULL`, ustiga 16 indeks. Qoralama uchun ularni nullable qilish CHOP ETILGAN e'lonlarning invariantini ham bo'shashtiradi va mavjud jadvalga migratsiya talab qiladi (alembic 3 head bilan buzuq) |
| **(b) alohida `bozor_listing_drafts` jadvali** | ✅ Hech qanday ustun bo'shashmaydi; `submit` qoralamani MAVJUD tekshirilgan yo'l (`ListingCreateRequest` → `create()`) orqali haqiqiy e'longa aylantiradi, ya'ni validatsiya bir joyda qoladi |

Narxi: qoralama va e'lonning `id` fazosi boshqa — «Mening e'lonlarim» tabi IKKI manbani
qo'shib ko'rsatadi. Bu ochiq va ataylab qilingan; UI da qoralama alohida belgi bilan turadi.

**Yangi jadval:** `bozor_listing_drafts(id, user_id FK, payload JSON NOT NULL,
current_step String(32) NULL, created_at, updated_at)` — `scripts/ensure_bozor_listing_drafts.py`
idempotent DDL bilan (alembic YO'Q).

**Yangi endpointlar** (`app/api/v1/listings.py`, literal yo'llar `/{listing_id}` dan OLDIN):

| Metod | Yo'l | Nima qiladi |
|---|---|---|
| `POST` | `/listings/drafts` | qoralama yaratadi → `{id}` |
| `PATCH` | `/listings/drafts/{id}` | qadam saqlaydi (`payload` + `current_step`) |
| `GET` | `/listings/drafts` | mening qoralamalarim |
| `DELETE` | `/listings/drafts/{id}` | qoralamani o'chiradi |
| `POST` | `/listings/drafts/{id}/submit` | qoralama → haqiqiy e'lon (`pending`), qoralama o'chadi |

⚠️ `GET /listings/` (ommaviy) qoralamani KO'RSATMASLIGI shart — u alohida jadvalda
bo'lgani uchun bu o'z-o'zidan ta'minlanadi (qo'shimcha filtr kerak emas).

⚠️ **Maxfiylik:** qoralama `payload` ida telefon raqam va manzil bo'ladi — hamma
qoralama endpointi `user_id` bo'yicha qat'iy tekshirilishi kerak (boshqa odamning
qoralamasi 404, 403 emas: mavjudligini ham oshkor qilmaslik uchun).



> ⚠️ **2026-09-10 da o'lchandi: LOKALDA S3 YO'Q.** `docker-compose.yml` da MinIO xizmati
> yo'q va konteynerda `settings.AWS_S3_ENDPOINT_URL` **bo'sh**. Demak 4- va 5-qadamning
> natijasini lokal tekshirib bo'lmaydi.
>
> Shuning uchun ikkala qadam **ikkiga bo'linadi**:
> - **kod qismi** (prefiksni `storage_status_service._PREFIXES` ga qo'shish, yetim fayl GC
>   vazifasi, thumbnail vazifasi) — yoziladi va soxta (fake) S3 bilan unit-test qilinadi;
> - **ops qismi** (haqiqiy bucket'ga public-read siyosatini qo'llash) — prod kalitlarini
>   talab qiladi, ya'ni **buni men bajarmayman**: buyruq/skript hujjatga yoziladi va
>   egasi qo'llaydi.
>
> Natijada M1 ning tekshirib bo'ladigan qadamlari — **6, 7, 8, 9, 10, 12, 13** — ular
> BIRINCHI bajariladi; 4, 5, 11 keyinroq (kod + fake test + ops yozuvi).

### 4. MinIO: `listings/media/` public-read + yetim fayl siyosati

| | |
|---|---|
| **Repo** | backend (+ infra) |
| **Fayllar** | `app/services/s3_service.py`, `app/services/storage_status_service.py`, `scripts/storage_cutover/`, yangi `scripts/gc_orphan_listing_media.py`, `docs/bozor-listing-integration-plan.md` |

**Nega shu o'rinda.** Butun zanjirning eng pastki halqasi. `s3_service.public_url()` **presigned emas**,
barqaror URL qaytaradi, lekin `listings/media/` bucket siyosatida yo'q → hozir yuklangan har bir foto
**403**. Lenta ham, moderatsiya ham, karta ham rasmsiz.

**Nima qilinadi.**
1. `mc anonymous set download <alias>/<bucket>/listings/media` — **AYNAN shu prefiks**, `*` emas
   (aks holda model fayllari ham ochiladi).
2. `storage_status_service._PREFIXES` ga `("listings/media/", "Bozor listing media")`.
3. **Yetim fayl GC** (Z12): `scripts/gc_orphan_listing_media.py` — S3'dagi `listings/media/` obyektlarini
   `bozor_listing_media.storage_key` bilan solishtiradi, **7 kundan eski** va hech bir e'longa
   bog'lanmaganlarini o'chiradi. Cron/CI'ga qo'yiladi. Tashlab ketilgan sehrgar sessiyasi va
   qayta urinish fayllari abadiy ochiq qolmasin.

**Tugadi mezoni.** Sehrgardan foto yuklab, javobdagi `url` ni `curl -I`: **200** +
`Content-Type: image/jpeg` + `Cache-Control: public, max-age=31536000, immutable`; anonim
(tokensiz) brauzerda ochiladi; `marketplace/` prefiksi hamon presigned; GC skripti `--dry-run`
bilan yetim fayllar sonini to'g'ri chiqaradi.

**Xavf.** Yuqori. Prefiksni keng ochib yuborish. Prod va dev MinIO'da alohida qo'llanadi (CI qilmaydi).
Z12 qaroriga bog'liq.

---

### 5. Thumbnail: `listings.build_thumbs`

| | |
|---|---|
| **Repo** | backend |
| **Fayllar** | `app/api/v1/listings.py`, `app/services/image_derivative_service.py`, `app/tasks/` (Celery), `app/models/bozor_listing.py` |

**Nega shu o'rinda.** `bozor_listing_media.thumb_url` / `width` / `height` / `bytes` ustunlari **bor**,
lekin yuklash endpointi ularni **hech qachon to'ldirmaydi** (`listings.py:213` faqat key+url yozadi).
Ya'ni M1-12 dagi 2-ustunli lenta grid'i **20 MB'lik originallarni** yuklaydi — mobil internetda
lenta amalda ishlamaydi. Lentani yozishdan **oldin** qilinishi shart.

**Tugadi mezoni.** Foto yuklangach `thumb_url` to'ladi (`image_derivative_service.thumb_url()`
naqshi bo'yicha), `width`/`height`/`bytes` yoziladi; `GET /listings/` javobidagi `media[].thumb_url`
bo'sh emas; thumb hajmi < 60 KB; original saqlanib qoladi.

**Xavf.** O'rta. Celery vazifasi yiqilsa `thumb_url` NULL qoladi — mobil tarafda
`thumb_url ?? url` fallback bo'lsin.

---

### 6. Moderatsiya UI (sqladmin) + holat mashinasi + xabarnoma

| | |
|---|---|
| **Repo** | backend |
| **Fayllar** | `app/admin.py`, `app/models/bozor_listing.py`, `app/services/bozor_listing_service.py`, `app/api/v1/admin.py` |

**Nega shu o'rinda.** E'lon `pending` da **qotib qoladi** — uni `approved` ga o'tkazadigan birorta UI
yo'q (na sqladmin view, na React sahifasi). Bu butun oqimning yagona uzilgan bo'g'ini; lentani
yozishdan oldin qo'lda tasdiqlash imkoni bo'lishi shart.

**Nima qilinadi.** `BozorListingAdmin(KxModelView)` — ro'yxat (`status`, `title`, `deal_type`,
`property_type`, `price_uzs`, `created_at`, `created_at ASC` navbat), detal (rasm eskizlari, `params`,
kontakt), **custom action**: «Tasdiqlash» / «Rad etish (sabab bilan)» → to'g'ridan-to'g'ri
`BozorListingService.moderate()` chaqiradi (xom `status` tahriri **EMAS**), shunda
`moderated_by` / `moderated_at` / `published_at` to'ladi va `notify_moderation()` ishlaydi.

**Tugadi mezoni.** `/admin` sidebar'da «Bozor eʼlonlari» (uz yorliqlar `_KX_VIEW_NAME_LABELS` /
`_KX_COLUMN_LABELS` ga qo'shilgan); pending e'lonni tasdiqlagach `GET /api/v1/listings/` da chiqadi,
`moderated_by` = admin id, `published_at` to'lgan, `notifications` jadvalida
`notification_type='moderation_result'`, `reference_type='bozor_listing'` qatori bor;
rad etishda sabab bo'sh bo'lsa forma xato beradi;
`GET /api/v1/admin/listings/pending-count` to'g'ri son qaytaradi.

**Xavf.** O'rta. `KxModelView` dan meros olish **SHART** (bare `ModelView` formatterlarni buzadi);
`user` relationship `lazy="selectin"` bo'lmasa async lazy-load xatosi; `can_create=False`
(admin qo'lda e'lon yaratsa `user_id` va media prefiksi buziladi);
`notify_user` xatosi moderatsiyani **orqaga qaytarmasligi** kerak — commit'dan keyin, try/except ichida.

---

### 7. Mobil: e'lonni O'QISH modeli + `BozorApi` lenta metodlari

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/models/bozor_listing.dart`, `lib/features/bozor/data/bozor_api.dart`, `test/features/bozor/bozor_listing_parse_test.dart` |

**Nega shu o'rinda.** Mobilda e'lonni o'qiydigan model **umuman yo'q** (`BozorDraft` — yozish modeli,
`MyListing` — rasmsiz mock). `BozorApi` da faqat `reference`/`options`/`regions/tree`/`media`/
`POST /listings/`. 8–13-qadamlarning hammasi shu qatlamga tayanadi.

**Tugadi mezoni.** `BozorListing.fromJson` haqiqiy `GET /listings/{id}` javobini (media massivi,
`price_uzs`, `status`, `rejection_reason`, `params`) xatosiz parslaydi — fixture bilan unit test yashil.
`BozorApi.listings(...)`, `.listing(id)`, `.myListings(status:page:size:)` `(items, total)` qaytaradi;
xatolar `BozorApiException` ga o'raladi.

**Xavf.** Past. `ListingOut` da 34 maydon — hammasini modelga solmang.
`area_sqm`/`price_amount` Decimal JSON'da **string** bo'lib kelishi mumkin →
`num.tryParse(v.toString())`. Model `MarketListing` ga adapter qilinsa `MarketController`
tekin keladi — shu yo'l tanlansin.

---

### 8. Mobil: «Mening e'lonlarim» — mock'dan haqiqiy `/listings/my` ga

> ⚠️ **BIRLASHTIRILDI 12-qadam bilan** (M1 qamrovi o'zgarishiga qarang): bu alohida ekran
> emas, ikki tabli «Bozor» ekranining 2-tabi. Qoralamalarni ham ko'rsatadi, ya'ni
> 34-qadamga (qoralama saqlash) bog'liq.


| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/listings/my_listings_screen.dart`, `lib/features/listings/listing_model.dart`, `lib/features/bozor/data/bozor_api.dart`, `assets/i18n/bundle.json` |

**Nega shu o'rinda.** E'lon bergan odam **birinchi shu ekranga** qaraydi (`bozor_success_screen.dart:32`
uni ochadi), va hozir u 4 ta qattiq yozilgan soxta e'lonni ko'radi (`my_listings_screen.dart:39`:
`final items = mockListings;`), barcha tugmalar `() {}`.

**Tugadi mezoni.** `grep mockListings lib/` **bo'sh**; ekran `/listings/my` dan yuklaydi:
skeleton → ro'yxat → bo'sh holat → xato+retry; `pending`/`approved`/`rejected` badge'lari haqiqiy
`status` dan; rad etilganda `rejection_reason` ko'rinadi; rasm `thumb_url ?? url` orqali chiziladi;
pull-to-refresh va sahifalash ishlaydi.

**Xavf.** O'rta. `SingleChildScrollView`+`Column` → `ListView.builder` ga o'tkazish kerak.
`formatSum`/`formatShortDate` importi `features/ratings/valuation_model.dart` dan — **saqlansin**.

---

### 9. Mobil+backend: e'lonni tahrirlash va arxivlash (moderatsiya siklini yopish)

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `lib/features/bozor/screens/bozor_edit_*`, `lib/features/listings/my_listings_screen.dart`, `kadastr-backend/app/schemas/bozor_listing.py` |

**Nega shu o'rinda.** Backendda `PATCH /listings/{id}` va `POST /{id}/archive` **ishlaydi**,
`rejected` e'lon tahrirlangach avtomatik qayta `pending` bo'ladi va `rejection_reason` tozalanadi.
Mobilda esa **hech qanday tahrirlash yo'q** — ya'ni rad etilgan e'lonni foydalanuvchi **tuzata olmaydi**
va moderatsiya sikli yopilmaydi.

**Nima qilinadi.** Minimal: «E'lonlarim» kartasida «Tahrirlash» → sehrgarni **to'ldirilgan qoralama**
bilan qayta ochish (`BozorListing` → `BozorDraft` konvertori) → oxirida `POST` emas `PATCH`.
Va «Arxivlash» tugmasi. ⚠️ `ListingUpdateRequest` da `terms` bo'limi **yo'q** — `deal` qo'shilganda
(M2-16) uni ham qo'shishni unutmang, aks holda tahrirlab bo'lmaydigan maydon qolib ketadi.

**Tugadi mezoni.** Rad etilgan e'lon tahrirlanadi → `PATCH` → status yana `pending`,
`rejection_reason` NULL; arxivlangan e'lon ro'yxatdan yo'qoladi va lentada chiqmaydi;
media almashtirilganda eski fayllar (M1-4 GC) yetim ro'yxatiga tushadi.

**Xavf.** O'rta. `_attach_media(replace=True)` butun media ro'yxatini almashtiradi — tahrirlashda
foydalanuvchi eski rasmlarni **qayta yuklamasligi** kerak; `BozorListing.media[].storage_key`
qaytarilmaydi (ataylab), shuning uchun tahrirlash payloadida mavjud kalitlarni saqlash uchun
`MediaOut` ga `storage_key` qo'shish yoki server tomonda «o'zgarmagan media» rejimi kerak —
qaysi biri arzonligi shu qadamda hal qilinadi.

> ⏭️ **OLDINGA QARAB ESLATMA — bu qadam KEYIN qayta ochiladi.**
> Shu yerda yoziladigan `BozorListing → BozorDraft` konvertori va `PATCH` payload'i hozir faqat
> **ijara** maydonlarini biladi. Keyingi qadamlar unga yangi bo'limlar qo'shadi va **har biri
> o'z tugadi mezonida konvertorni yangilashi shart**:
>
> | Keyingi qadam | Konvertorga nima qo'shiladi |
> |---|---|
> | **M2-16** | `ListingUpdateRequest.deal` (backend) — `terms` allaqachon yo'q, `deal` ham unutilmasin |
> | **M3-19** | `TransactionDraft` ← `sale_type`, `ownership_years`, `owners_count`, `registered_count` |
> | **M3-20** | `PriceDraft.mortgage` ← `mortgage`; sale'da `unit` davrsiz (`'UZS'`) tiklanadi |
> | **M4-26** | `params.land_area_unit` ← `land_area_unit` |
>
> Aks holda sotuv e'loni tahrirlanganda bu bo'limlar qoralamaga **tiklanmaydi** va `PATCH`
> ularni **NULL ga tushirib yuboradi** (jimgina ma'lumot yo'qolishi).

---

### 10. Mobil: success ekrani — «moderatsiyaga yuborildi» + yaratilgan e'longa o'tish

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/screens/bozor_success_screen.dart`, `screens/bozor_terms_step_screen.dart`, `data/bozor_submit.dart`, `assets/i18n/bundle.json` |

**Nega shu o'rinda.** **Z4.** Hozir ekran «muvaffaqiyatli chop etildi» deydi, backend esa har doim
`pending` qaytaradi. 8-qadamdan keyin «Nashrga o'tish» endi haqiqiy ekranga olib boradi.
Yana: `BozorSubmitter.submit()` qaytargan `id` **tashlab yuboriladi**.

**Tugadi mezoni** (⚠️ **bu qadamda detal ekrani hali YO'Q** — u M1-13 da yoziladi):
1. Matn «E'lon moderatsiyaga yuborildi» (uz/ru/en) + tushuntirish qatori;
2. `BozorSubmitter.submit()` qaytargan javobdan `id` **olinadi va tashlab yuborilmaydi** —
   `BozorSuccessScreen(listingId: id)` ga uzatiladi va ekran holatida saqlanadi
   (hozir `await _submitter.submit(...)` natijasi umuman o'qilmaydi);
3. «Eʼlonlarim» tugmasi `MyListingsScreen` ni ochadi (M1-8 da haqiqiy API'ga o'tkazilgan) —
   ya'ni foydalanuvchi o'z e'lonini `pending` badge bilan **ko'radi**;
4. «Bosh sahifaga» butun sehrgarni yopadi (`closeBozorWizard`).

> ⏭️ **OLDINGA QARAB ESLATMA — M1-13 da yopiladi.** Uzatilgan `listingId` shu qadamda faqat
> **saqlanadi**, ishlatilmaydi: e'lon **detali ekrani hali mavjud emas**
> (`lib/features/bozor/feed/bozor_listing_detail_screen.dart` — M1-13). Detal ekrani yozilgach
> success ekranidagi tugma **«Eʼlonimni koʻrish»** ga o'zgaradi va aynan o'sha e'lonni ochadi —
> bu **M1-13 ning tugadi mezoniga** kiritilgan. Shu bilan `id` ning tashlab yuborilishi
> to'liq yopiladi.

**Xavf.** Past. `pushAndRemoveUntil` predikati `bozor/` prefiksiga tayanadi — yangi marshrutga
`RouteSettings` berish shart. Dizaynda 1 tugma, bizda 2 — **ongli chekinish** (izohda yozib qo'yiladi).

---

### 11. Mobil: yuklash progressi + bo'lakli yuklash + qisman muvaffaqiyatni saqlash

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/data/bozor_submit.dart`, `data/bozor_api.dart`, `screens/bozor_terms_step_screen.dart` |

**Nega shu o'rinda.** Foydalanuvchi ko'radigan **birinchi haqiqiy nosozlik** shu bo'ladi:
20 ta foto bitta multipart so'rovda ketadi (5 daqiqa timeout), bitta xato **butun rolni** yiqitadi,
qayta urinishda hamma fayl qaytadan yuklanadi va S3'da yetim obyektlar qoladi.
⚠️ **XOTIRA:** `AuthHttpClient._toReplayable` multipart'ni to'liq baytga o'qiydi va `_cloneRequest`
yana nusxa oladi → 20×20 MB ≈ **800 MB**, telefonda OOM.

**Tugadi mezoni.** Terms ekranida `onProgress` ulangan, tugma «Yuborilmoqda… 3/12» ko'rsatadi;
fayllar **5 tadan** bo'lak bilan (yoki bittalab) yuboriladi; muvaffaqiyatli `key` lar qoralamada
saqlanadi va qayta urinishda **qayta yuklanmaydi**; Wi-Fi uzilib qayta ulanganda faqat yiqilgan
fayl qayta ketadi.

**Xavf.** Yuqori. Backend `_ROLE_LIMITS` cheklovni **bitta so'rov ichida** sanaydi — bo'laklarga
bo'lish limitni chetlab o'tadi, shuning uchun umumiy cheklovni **mobil tarafda o'zingiz** qo'llang
(M4-23). Haqiqiy umumiy shift — `DescriptionIn.media` `max_length=40`.

---

### 12. Mobil: Bozor lentasi — (a) repository, (b) ekran

> ⚠️ **QAYTA TA'RIFLANDI:** ikki tabli ekran («E'lonlar» + «Mening e'lonlarim»),
> 8-qadamni O'Z ICHIGA OLADI, va «E'lon qo'shish» tugmasi shu ekranda.
> Kirish nuqtasi — `main_shell.dart:259 _openBozorAi()`. Marshrutga `bozorRoute(...)`
> BERILMASIN (yuqoridagi tuzoq).


> ⚠️ **Bu bitta o'tirishga sig'maydi.** Ikki qism sifatida bajariladi.

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/feed/bozor_feed_repository.dart`, `feed/bozor_feed_screen.dart`, `lib/features/market/widgets/listing_card.dart`, `lib/features/home/home_screen.dart`, `assets/i18n/bundle.json` |

**Nega shu o'rinda.** E2E oqimning oxirgi bo'g'ini — tasdiqlangan e'lon **ko'rinishi** kerak.
Market tab faqat 3D katalogni ko'rsatadi. `MarketController` butunlay generik:
`class BozorFeedRepository implements MarketRepository` yozilsa debounce, sahifalash, race-token,
skeleton, pull-to-refresh, «tepaga» FAB **tekin** keladi.

**12a — repository + karta moslamalari.** `MarketListing` adapteri; `ListingCard` dan uchta
qattiq bog'lanish ajratiladi: (1) Hero tag `'listing.${id}'` → parametr (`'bozor.${id}'`, aks holda
market bilan **to'qnashadi**); (2) qattiq `' UZS'` suffiksi → parametr (ijarada «so'm/oy»);
(3) `priceUzs <= 0` → «Bepul» mantiqi bozorda **noto'g'ri** (0 = «Kelishiladi»).
Narx formatlash 3 joyda takrorlangan (`listing_card`, `listing_info_card`,
`listing_detail_screen.marketGroupDigits`) — bitta helper ajratiladi.

**12b — ekran + filtrlar.** Sticky header + qidiruv + masonry grid + skeleton + bo'sh/xato holatlari.
Filtrlar (`deal_type`, `property_type`, `region_id`/`district_id`, narx, xonalar, maydon)
**SERVER query param** sifatida — ⚠️ `ApiMarketRepository` naqshi filtrni sahifa **kelgandan keyin**
qo'llaydi (`api_market_repository.dart:32-34`) va sahifalash + `total` ni buzadi; **takrorlamang**.

**Tugadi mezoni.** Kirish nuqtasidan lenta ochiladi; tasdiqlangan e'lonlar 2-ustunli grid'da
`thumb_url` bilan chiqadi; pastga surilganda keyingi sahifa; refresh; bo'sh/xato holatlari;
filtr o'zgarganda so'rov **serverga** ketadi va `total` to'g'ri. `flutter analyze` toza.

**Xavf.** Yuqori. `sharedMarketController()` **global singleton** — bozor uchun **alohida**
`MarketController` yarating. Kirish nuqtasi (Home kartasi / Market tab segmenti / 5-tab) —
**ochiq savol** (§7).

---

### 13. Mobil: e'lon detali ekrani

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/feed/bozor_listing_detail_screen.dart`, `lib/features/market/widgets/listing_gallery_pager.dart`, `listing_info_card.dart`, `lib/features/bozor/data/param_options.dart` |

**Nega shu o'rinda.** Lentadagi kartani bosgach hech narsa bo'lmasa oqim tugamaydi.
`ListingGalleryPager`, `ListingInfoCard`, `ListingMetaPills`, `openFullscreenGallery` **tayyor**.

**Tugadi mezoni.** Kartadan detal ochiladi: galereya (zoom + to'liq ekran), narx + sarlavha + tavsif,
**parametrlar YORLIQ bilan** (`params` da KOD saqlanadi → `ApiParamOptions` orqali yorliqqa
aylantiriladi, ro'yxat yuklanmasa **kod chiqib qolmasin** — fallback), manzil, kontakt telefoni
(qo'ng'iroq tugmasi), ulashish. Anonim foydalanuvchida ham ochiladi.

⏭️ **M1-10 ning ochiq uchi shu yerda yopiladi.** Success ekranidagi tugma matni
«Eʼlonlarim» dan **«Eʼlonimni koʻrish»** ga o'zgaradi va `BozorSuccessScreen.listingId`
(M1-10 da uzatilgan) bilan **aynan o'sha e'lonning detali** ochiladi.
Tekshiruv: e'lon yuboriladi → success → «Eʼlonimni koʻrish» → detal ekranida o'sha sarlavha,
narx va rasm; e'lon hali `pending` bo'lgani uchun **egasi** ko'ra oladi
(`get_for_viewer`: tasdiqlanmagan e'lonni faqat egasi ochadi), lekin lentada chiqmaydi.

**Xavf.** O'rta. 360 panorama oddiy rasm sifatida chiqadi (panorama ko'ruvchi yo'q) — hozircha shunday.

> ✅ **M1 TUGADI — mustaqil reliz mumkin.** Ijara oqimi to'liq tirik: e'lon → moderatsiya →
> lenta → detal → «E'lonlarim» → tahrirlash.

---

## M2 — Sotuv ma'lumot modeli (backend) + mobil gate

### 14. `new_building_apartment` — 7-chi mulk turi + `bozor_sale_enabled` bayrog'i

| | |
|---|---|
| **Repo** | backend |
| **Fayllar** | `app/schemas/listing_options.py` (`PROPERTY_TYPES`, `KIND_TYPES`), `app/services/listing_param_schema.py` (`SCHEMA`, `primary_area_key`), `app/services/listing_option_labels.py` (`LABELS`), `app/models/app_setting.py` (`bozor_sale_enabled`), **`app/schemas/bozor_listing.py`** (`ListingReferenceResponse`, 300-qator — `sale_enabled` maydoni `top_tier_enabled` yoniga, 310-qator), **`app/api/v1/listings.py`** (`get_reference`, 118–137-qatorlar — bayroqni javobga chiqarish), `scripts/ensure_bozor_listings.py` |

**Nega shu o'rinda.** Mobil enum'ga qo'shishdan **oldin** backend bilishi shart: aks holda
`POST /listings/` `property_type` validatorida 400 va `validate()` uchun param jadvali topilmaydi.
Shu bilan birga **butun sotuv oqimi uchun feature-flag** (`app_settings.bozor_sale_enabled`,
default `false`) qo'shiladi — M2 va M3 orasida sotuv yarim holatda ko'rinmasin.

**Tugadi mezoni.** `GET /api/v1/listings/reference?locale=ru` da `types` **7 ta** va
`kind_types.residential` **4 ta**; `POST /listings/` `property_type=new_building_apartment` bilan **201**;
`primary_area_key('new_building_apartment')` → `total_area`;
`reference()` javobida `sale_enabled: false`;
`pytest tests/test_i18n_seed_single_source.py -q` yashil (3 ta yangi yorliq generatsiya orqali).

**Xavf.** O'rta. Bu turga maxsus parametrlar (застройщик, срок сдачи, очередь, тип отделки)
kerakligi dizaynda **ochilmagan** — hozircha `SCHEMA["new_building_apartment"] = SCHEMA["apartment"]`
nusxasi (§7 ochiq savol).

---

### 15. `bozor_listings` ga 6 ta yangi ustun (model + ensure DDL)

| | |
|---|---|
| **Repo** | backend |
| **Fayllar** | `app/models/bozor_listing.py`, `scripts/ensure_bozor_listings.py` |

**Nega shu o'rinda.** Ustunlar `DealIn` sxemasidan **oldin** paydo bo'lishi kerak.
`sale_type`, `ownership_years`, `owners_count`, `registered_count`, `mortgage`, `land_area_unit`.

**Nega `params` emas, ustun.** `listing_param_schema.validate(property_type, params)` **faqat
`property_type` ni biladi**, `deal_type` ni ko'rmaydi. `owners_count` ni `optional=False` qilsak →
**ijara** e'lonlari ham 400 oladi (Store'dagi eski ilova versiyalari butunlay ishdan chiqadi);
`optional=True` qilsak → dizayndagi yagona majburiy maydon serverda **umuman tekshirilmaydi**.
Qo'shimcha sabab: lentada `mortgage` / `sale_type` bo'yicha filtr.

**⚠️ USTUN TURI — `String(8)`, `SmallInteger` EMAS.** `owners_count` va `registered_count`
dizaynda **select** (picker ikonkasi bilan), va §3 dagi bloklangan ro'yxatlarda `6_plus` kabi
**son bo'lmagan kod** bo'lishi mumkin. Agar ustunni `SMALLINT` qilib yaratsak va M2-16 javobida
`6_plus` chiqsa — prod'da `ALTER TABLE … ALTER COLUMN … TYPE varchar` kerak bo'ladi,
**alembic esa 3 head bilan buzuq**. `String(8)` ikkala holatni ham ushlaydi: `"3"` ham,
`"6_plus"` ham. Shu sababli ro'yxatlar **M2-15 ni ham bloklaydi** (§3) — lekin `String(8)`
tanlovi bilan bu blok **yumshatiladi**: ustunni hozir yaratib, qiymatlarni keyin cheklash mumkin.

**Tugadi mezoni.** `docker compose exec -T app python -m scripts.ensure_bozor_listings`
**ikki marta ketma-ket** xatosiz (idempotent); `\d bozor_listings` da:
`sale_type VARCHAR(24) NULL`, `ownership_years VARCHAR(16) NULL`,
**`owners_count VARCHAR(8) NULL`**, **`registered_count VARCHAR(8) NULL`**,
`mortgage BOOLEAN NOT NULL DEFAULT false`, `land_area_unit VARCHAR(8) NULL`.
Eski qatorlar buzilmagan: `SELECT count(*) FROM bozor_listings WHERE mortgage IS NULL` = **0**.
Model (`app/models/bozor_listing.py`) va ensure skript **bir xil tur** e'lon qiladi (qo'lda solishtiriladi —
sxema ikki manbada, §6 texnik qarz).

**Xavf.** Yuqori. ⚠️ **Alembic revisiyasi YOZILMASIN** — grafda 3 head bor
(`davreestr_logs_01`, `f0a1b2c3d4e5`, `legal_docs_01`), ensure skript birinchi ishlaydi va
`op.create_table` mavjud jadvalda portlaydi. `owners_count` ni NOT NULL qilmang — mavjud rent
e'lonlarida u yo'q va migratsiya yiqiladi.

**Texnik qarz eslatmasi.** Bu qadam alembic qarzini **chuqurlashtiradi** (endi 6 ta ustun skriptda).
Alembic head'larini birlashtirish **alohida vazifa** sifatida qayd etiladi (bu rejaga kirmaydi).

---

### 16. `DealIn` sxemasi + 4 ta yangi OPTION_LISTS + servis/DTO/PATCH

| | |
|---|---|
| **Repo** | backend |
| **Fayllar** | `app/schemas/bozor_listing.py`, `app/schemas/listing_options.py`, `app/services/bozor_listing_service.py`, `app/services/listing_option_labels.py`, `app/data/app_translation_seed.json`, `tests/test_bozor_deal_section.py` |

**Nega shu o'rinda.** 15-qadamdagi ustunlar hali API orqali to'ldirilmaydi.
⛔ **BLOKLANGAN:** `sale_type` / `ownership_years` / `owners_count` / `registered_count`
ro'yxatlarining aniq qiymatlari M0-2 da so'ralgan (§3).

**Tugadi mezoni.** `GET /listings/options?locale=ru` da 4 ta yangi ro'yxat to'ldirilgan `label` bilan
(kalitning o'zi emas); `python -c "from app.services.listing_option_labels import missing_labels; print(missing_labels())"` → `[]`.
`tests/test_bozor_deal_section.py` yashil:
(a) `deal` bo'limisiz **rent** payload → **201** (eski klient);
(b) `deal_type='sale'` va `deal.owners_count` yo'q → **400**;
(c) `deal.registered_count` faqat kvartira turlarida qabul qilinadi;
(d) `GET /listings/{id}` javobida 4 ta yangi maydon;
(e) `ListingUpdateRequest` ga ham `deal` qo'shilgan → `PATCH` ishlaydi.

**Xavf.** Yuqori. Kod qiymatlari **abadiy** — §3 zaxira qoidasi.
`ListingUpdateRequest` da `terms` allaqachon yo'q — `deal` ni ham unutish oson.
Validatsiya `check_kind_type()` yonida `model_validator` bo'lsin (`deal_type` va `deal` bog'liq).

---

### 17a. Sotuvda narx davri yo'qligi + `mortgage` + prod audit

| | |
|---|---|
| **Repo** | backend |
| **Fayllar** | `app/schemas/bozor_listing.py`, `app/services/bozor_listing_service.py` |

**Nega shu o'rinda.** Mobil narx qadamini (M3-20) o'zgartirishdan oldin backend qoidasi aniq
bo'lishi kerak, aks holda `price.period='month'` bilan sotuv e'loni yaratiladi va lentada
«820 mln so'm/oy» chiqadi.

**⚠️ AVVAL AUDIT.** Yangi qoidani yoqishdan oldin:
`SELECT count(*) FROM bozor_listings WHERE deal_type='sale' AND price_period IS NOT NULL;`
Natija > 0 bo'lsa — bir martalik `UPDATE … SET price_period = NULL`, aks holda mavjud e'lonlarning
`PATCH` tahriri bloklanadi.

**Tugadi mezoni.** `PriceIn.mortgage: bool = False` → `bozor_listings.mortgage`;
`deal_type='sale'` + `price.period != null` → **400**; `deal_type='sale'` + `daily_amount` → **400**;
audit so'rovi **0** qaytaradi; `pytest tests/test_bozor_deal_section.py -q` yashil.

**Xavf.** O'rta. Audit o'tkazilmasa prod'dagi test e'lonlari tahrirlanmay qoladi.

---

### 17b. Mobil: `sale_enabled` gate'i — «Продажа» ni bayroq bilan yashirish

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/data/bozor_api.dart` (`ListingReference`, 185–221-qatorlar; `reference()`, 61-qator), `lib/features/bozor/screens/bozor_type_step_screen.dart`, `lib/features/bozor/models/bozor_draft.dart`, `assets/i18n/bundle.json`, `test/features/bozor/sale_gate_test.dart` |

**Nega shu o'rinda.** M2-14 bayroqning **backend yarmini** berdi (`reference()` javobida
`sale_enabled: false`), lekin mobil uni **umuman o'qimaydi**:

- `ListingReference.fromJson` hozir faqat `topTierEnabled: j['top_tier_enabled'] == true`
  ni parslaydi (`bozor_api.dart:218`) — `sale_enabled` maydoni **tashlab yuboriladi**;
- `bozor_type_step_screen.dart` da hech qanday gate yo'q — `DealType.values` to'g'ridan-to'g'ri
  pickerga beriladi;
- `BozorApi.reference()` **hech qayerdan chaqirilmaydi** (o'lik kod).

Ya'ni bayroqsiz M3-18 ning butun xavfsizlik dalili («oraliqda ilova sotuvni ko'rsatmaydi»)
**yozilmagan kodga** tayanadi. Shuning uchun mobil yarim M3 dan **oldin** yopiladi.

**Nima qilinadi.**
1. `ListingReference` ga `final bool saleEnabled;` + `fromJson` da
   `saleEnabled: j['sale_enabled'] == true`.
2. Sehrgar kirish nuqtasida (`main_shell.dart:259 _openBozorAi()` yoki
   `BozorTypeStepScreen.initState`) `reference()` **bir marta** chaqiriladi va natija
   qoralamaga/ekran holatiga yoziladi. Tarmoq xatosi / offline → **`false` fallback**
   (xavfsiz taraf: yarim ishlaydigan sotuv oqimini ko'rsatgandan ko'ra ko'rsatmagan yaxshi).
3. `_pickDeal()` da ro'yxat: `saleEnabled ? DealType.values : [DealType.rent]`.
   Bayroq `false` bo'lganda birinchi maydon **umuman tanlov taklif qilmaydi** —
   `deal = DealType.rent` avtomatik qo'yiladi va qator `enabled: false` bo'ladi
   (yoki butunlay chizilmaydi — UI qarori shu qadamda).
4. ⚠️ Bayroqni **keshlash** kerak emas: `reference()` yengil so'rov, lekin javob kelguncha
   1-qadam «yuklanmoqda» holatida turmasin — sukut `false`, javob kelgach `setState`.

**Tugadi mezoni.** `flutter test test/features/bozor/sale_gate_test.dart`:
(a) `sale_enabled: false` javobida 1-qadam pickerida **faqat «Ijaraga»** varianti;
(b) `sale_enabled: true` da ikkalasi;
(c) `reference()` **xato** bersa — «Ijaraga» rejimida qoladi, ekran yiqilmaydi va toast bermaydi.
Qo'lda: backendda bayroqni `true`/`false` qilib almashtirsangiz ilova qayta ochilganda
xatti-harakat o'zgaradi.

**Xavf.** O'rta. `reference()` sehrgar boshida qo'shimcha tarmoq so'rovi qo'shadi — u
**bloklovchi bo'lmasin** (`unawaited` + `setState`), aks holda offline foydalanuvchi sehrgarni
umuman ocholmaydi. Z14: 1-qadamdagi **yorliqlar** hamon lokal enum'dan keladi, `reference()`
faqat **bayroqlar** uchun ishlatiladi (`sale_enabled`, `top_tier_enabled` — M4-35).

---

## M3 — Sotuv oqimi (mobil)

### 18. `wizardSteps` ni (DealType × PropertyType) juftligiga o'tkazish

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/models/bozor_draft.dart`, `test/features/bozor/wizard_steps_test.dart` |

**Nega shu o'rinda.** Butun 8-qadamli oqimning poydevori va **eng arzon** qadam.
Qadam raqamlari hech qayerda qo'lda yozilmagani uchun shu bitta o'zgarish butun sehrgarni
avtomatik 1/8…8/8 ga o'tkazadi. Ekran yozishdan **oldin** test bilan qotiriladi.

**⚠️ Buzuq oraliq holat bo'lmasin.** `WizardStep.deal` ro'yxatga qo'shiladi **va o'sha qadamda**
`stepAfter` tarmoqlanishi ham yangilanadi (19-qadamda ekran keladi).
Oraliqda ilova sotuvni umuman ko'rsatmaydi — **buning dalili M2-17b da yozilgan mobil gate**,
backend bayrog'ining o'zi emas. **M2-17b bajarilmagan bo'lsa bu qadam boshlanmasin**, aks holda
foydalanuvchi 4/8 «Сделка» o'rniga bo'sh ekranga tushadi.

⚠️ **Ijara oqimi tegilmaydi** degan farazning o'zi ochiq savol (§7, 15) — «ijarada ham Сделка bor»
javobi kelsa quyidagi 4 kombinatsiya **2 ga tushadi** va bu qadam qayta yoziladi.

**Tugadi mezoni.** `flutter test test/features/bozor/wizard_steps_test.dart` yashil —
4 kombinatsiya: rent+apartment = **7** (deal YO'Q), rent+otherNonResidential = **6**,
sale+apartment = **8** va `stepNumber(WizardStep.price) == 5`,
sale+otherNonResidential = **7** (params yo'q, deal bor).
`BozorDraft.wizardSteps` fallback ikki o'lchovli (`deal ?? rent`, `type ?? apartment`) — 1-qadamda
«Продажа» tanlanib, mulk turi hali tanlanmagan holatda progress **sakramaydi** (test bilan).
`flutter analyze` toza.

**Xavf.** O'rta. Ikkita tarmoqlanish nuqtasi yangilansin:
`bozor_address_step_screen._onContinue` (hozir `next == params ? 'params' : 'price'`) va
`bozor_params_step_screen._openPrice` — ikkalasi ham `stepAfter()` natijasini **to'liq `switch`**
qilsin, `if/else` emas.

---

### 19. 4/8 «Сделка» ekrani + marshrut + payload

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/screens/bozor_deal_step_screen.dart`, `models/bozor_draft.dart`, `data/bozor_submit.dart`, `bozor_routes.dart`, `assets/i18n/bundle.json`, `kadastr-backend/app/data/app_translation_seed.json`, `test/features/bozor/build_payload_test.dart` |

**Nega shu o'rinda.** Backend (M2-16) va model (18) tayyor. Mavjud andoza to'liq qoplaydi —
**yangi widget kerak emas**.

**Tugadi mezoni.** Sotuv+Квартира: 1/8 → 2/8 → 3/8 → **4/8 Сделка** → 5/8 zanjiri;
Sotuv+Другая нежилая: **3/7** da Сделка; **ijara oqimi o'zgarmagan** (7/6 qadam).
«Далее» faqat `ownersCount != null` bo'lganda; `Прописано` faqat kvartira turlarida.
**Z15 (majburiylik belgisi):** «Собственники» → `SelectField(required: true)` (qizil `*`);
qolgan 3 maydon → `required: false` va **«(по желанию)» matni QO'SHILMAYDI** — bu qadam
konvensiya farqi eng ko'rinadigan joy (4 maydondan 3 tasi ixtiyoriy), shuning uchun qaror
shu yerda qat'iy qo'llanadi.
`flutter test test/features/bozor/build_payload_test.dart`:
(a) rent qoralamasida `deal` kaliti **umuman yo'q**;
(b) sale qoralamasida `deal: {sale_type, ownership_years, owners_count, registered_count}`,
null maydonlar tushib qolgan.
Uchidan-uchiga: sotuv e'loni **201** → adminkada tasdiqlanadi → lentada chiqadi.
⏭️ **M1-9 konvertori yangilangan:** `BozorListing → BozorDraft` da `TransactionDraft`
to'ldiriladi va `PATCH` payload'ida `deal` bo'limi bor — sotuv e'loni tahrirlanib qayta
saqlanganda 4 ta maydon **saqlanib qoladi** (test: tahrirlash → `PATCH` → `GET` da qiymatlar
o'zgarmagan).

**Xavf.** O'rta.
⚠️ **i18n nom to'qnashuvi:** `bozor.deal.rent`/`bozor.deal.sale` **band** → yangi kalitlar
`bozor.transaction.*`.
⚠️ **Model nom to'qnashuvi:** `BozorDraft.deal` `DealType?` uchun band → yangi bo'lim
`BozorDraft.transaction = TransactionDraft()`.
⚠️ `bozorRoute('deal')` **SHART** — nomsiz marshrut `closeBozorWizard` ni to'xtatadi.
`buildPayload` da `draft.deal!` naqshini takrorlamang — `deal_type != 'sale'` bo'lsa bo'limni
umuman qo'shmang.

---

### 20. 5/8 narx qadamining sotuv rejimi

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/screens/bozor_price_step_screen.dart`, `models/bozor_draft.dart`, `data/bozor_submit.dart`, `assets/i18n/bundle.json`, backend seed |

**Nega shu o'rinda.** M2-17a dagi backend qoidasi mobil tarafda bajarilishi kerak, aks holda **400**.

**Tugadi mezoni.** Sotuvda: birlik ro'yxati `['UZS','USD']`, `_periodOf()` → `null`,
sutkalik narx bloki **ko'rinmaydi** (`_hasDailyPrice` ga `deal == rent` sharti),
yorliq mulk turiga qarab (`PropertyTypeX.priceLabel(locale, deal)` + 7 yangi kalit),
«Ипотека» toggle bor. Ijarada **hammasi eskicha** (regression).
`GET /listings/{id}` da `price_period: null`, `mortgage: true`.
⏭️ **M1-9 konvertori yangilangan:** tahrirlashda `mortgage` tiklanadi va sale e'lonida
`PriceDraft.unit` davrsiz (`'UZS'`) qilib qo'yiladi — aks holda `PATCH` `price.period='month'`
yuborib **400** oladi.

**Xavf.** O'rta. `PriceDraft.unit` sukut qiymati 1-qadamda `deal` tanlangandan **keyin**
o'rnatilsin (`setDeal` ichida), aks holda foydalanuvchi rent → sale ga qaytsa `'UZS/oy'` qolib
ketadi va backend 400 beradi.

---

### 21. Mobil: `newBuildingApartment` — 7-chi mulk turi

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/models/bozor_draft.dart`, `models/param_schema.dart`, `data/bozor_submit.dart`, `assets/i18n/bundle.json` |

**Nega shu o'rinda.** M2-14 da backend qabul qiladi — endi mobil taklif qilsin. Bu turga tegadigan
hamma joy **bir vaqtda** yopilishi kerak (`wizardSteps`, `addressRows`, `paramFields`,
`descriptionLabel`, `.code`), aks holda `switch` to'liq bo'lmay `flutter analyze` yiqiladi.

**Tugadi mezoni.** 1-qadamda «Turar joy» ostida 4 variant; yangi turda 2-qadam kvartiradek 8 qator;
3-qadam kvartira parametrlari; sotuvda 8 qadam; `POST /listings/` **201**.
`.code` = `new_building_apartment` (backend kodi bilan **aynan mos**).

**Xavf.** Past. ⚠️ `bozor.type.other_non_res` ↔ `other_non_residential` nomuvofiqligini
**takrorlamang**; imkon bo'lsa o'shani ham shu qadamda to'g'rilang.

---

### 22. Mobil↔backend param sxemasi parity testi + sotuv bayrog'ini yoqish

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `mobile/test/features/bozor/param_schema_parity_test.dart`, `mobile/test/fixtures/param_schema.json`, `kadastr-backend/tests/test_listing_param_schema_parity.py`, `app/models/app_setting.py` |

**Nega shu o'rinda.** 86 ta maydon ikki repoda **qo'lda** ko'chirilgan va hozir tasodifan mos.
M2-14/15/16 va M3-21 sxemaga tegdi, M4 yana 3 marta tegadi.
⚠️ `optional` DEFAULT'i **teskari**: Dart `false` (majburiy), Python `True` (ixtiyoriy) —
jimgina desync uchun mukammal tuzoq.

**Mexanizm (mo'rt parsingsiz).** Mobilda kichik skript `param_schema` ni
`test/fixtures/param_schema.json` ga **eksport qiladi**; backend testi shu faylni o'qib solishtiradi;
mobil testi esa faylni **qayta generatsiya qilib** solishtiradi (fayl eskirsa mobil test yiqiladi,
soxta yashil bo'lmaydi).

**Tugadi mezoni.** Har mulk turi bo'yicha kalit ro'yxati, tartibi, `optionsKey`↔`options`,
`optional`, `visible_when` 1:1; ataylab bitta kalitni o'zgartirsangiz **ikkala** test yiqiladi.
Shundan keyin `app_settings.bozor_sale_enabled = true` yoqiladi.

**⏭️ Bu testdan KEYIN sxemaga tegadigan qadamlar.** Har biri o'z tugadi mezonida
`test/fixtures/param_schema.json` ni **qayta generatsiya qilib**, ikkala parity testini
yashil qilishi **shart** — aks holda fixture eskiradi va test **soxta yashil** bo'ladi:

| Qadam | Sxemaga nima qo'shiladi |
|---|---|
| **M4-26** | `land_area_unit` + birlik dropdowni uchun yangi kontrol (`house`, `land`, `commercial`) |
| **M4-27** | `balcony_area` (`visible_when: balcony != 'none'`), `rooms_count_exact` |

(M2-14 va M3-21 ham sxemaga tegadi, lekin ular **shu qadamdan oldin** — fixture birinchi marta
aynan ulardan keyingi holatdan generatsiya qilinadi.)

**Xavf.** O'rta. Fixture'ni qayta generatsiya qilish CI'da ham bo'lsin.

> ✅ **M3 TUGADI — sotuv oqimi tirik, mustaqil reliz mumkin.**

---

## M4 — Dizayn deltalari

### 23. Rol bo'yicha media limitlari + hajm/format tekshiruvi + PDF планировка

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/screens/bozor_description_step_screen.dart`, `widgets/media_upload_row.dart`, `assets/i18n/bundle.json` |

**Nega shu o'rinda.** Mobil `_maxPhotos = 20` **uchala qatorga** qo'llaniladi, backend esa
plan=5, panorama=5, photo=20 → foydalanuvchi 6-planirovkani qo'shadi va xato faqat **oxirgi
qadamda 400** bo'lib chiqadi. 24-qadamdagi foto ekranidan **oldin** tuzatilsin.

**Tugadi mezoni.** 6-chi planirovka qo'shilmaydi + `bozor.desc.too_many` toast;
25 MB'lik rasm tanlanganda «fayl 20 MB dan katta» toast (`File.length()` bilan);
21-chi foto qo'shilmaydi; hech biri 8/8 qadamgacha yetib bormaydi.
Z13 bo'yicha: планировка uchun `file_picker` (PDF + rasm).
20 foto + 5 plan + 5 panorama bilan e'lon **201**.

**Xavf.** Past.

---

### 24. «Добавить фото» to'liq ekrani + to'ldirilgan qator ko'rinishi

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/screens/bozor_photos_screen.dart`, `widgets/media_upload_row.dart`, `screens/bozor_description_step_screen.dart`, `assets/i18n/bundle.json` |

**Nega shu o'rinda.** Dizayndagi ikkita yangi ko'rinish (`2561-23152`, `2561-23030`).

**Tugadi mezoni.** «Foto qo'shish» → `bozorRoute('description/photos')` ekrani: 3 ustunli 109×109 grid,
har rasmda ×, oxirgi katak punktir «qo'shish», header'da «Готово»; qaytgach qatorda
«N ta rasm qo'shildi» + 3 ta 36×36 stack + «+N». Планировка va 360 qatorlari eskicha (bittalab).
`flutter analyze` toza.

**Xavf.** Past. Marshrutga nom berish shart. Z8 (title) javobi (b) bo'lsa — shu ekran bilan birga
6/8 dagi sarlavha maydoni ham olib tashlanadi.

---

### 25. Muqova tanlash + rasm tartibi

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/screens/bozor_photos_screen.dart`, `data/bozor_submit.dart`, `models/bozor_draft.dart` |

**Nega shu o'rinda.** Protokol **allaqachon** qo'llab-quvvatlaydi: `MediaIn.is_cover` va
`sort_order` backendda qabul qilinadi va saqlanadi. Yetishmayotgani faqat UI: hozir muqova qattiq
qoida (`entry.key=='photo' && i==0`), tartib = tanlash tartibi. **Arzon g'alaba.**

**Tugadi mezoni.** Foto ekranida uzoq bosib surish tartibni o'zgartiradi; birinchi rasmda «Muqova»
nishoni; boshqa rasmni muqova qilish mumkin; `GET /listings/{id}` da tanlangan rasmda
`is_cover: true` va `sort_order` grid tartibiga mos.

**Xavf.** Past. Dizaynda drag ko'rsatilmagan — bu bizning qo'shimchamiz, ixtiyoriy.

---

### 26. Maydon birligi dropdowni (`соток`/`м²`) + backend konvertatsiyasi

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `mobile/lib/features/bozor/models/param_schema.dart`, `widgets/param_form.dart`, `kadastr-backend/app/services/listing_param_schema.py`, `app/services/bozor_listing_service.py`, `app/schemas/listing_options.py` |

**Nega shu o'rinda.** **Z10.** Dizaynda birlik **tanlanadi**; tijoratda dizayn `соток` deydi, bizda
`м²`; backend `_derive()` x100 ni faqat `property_type=='land'` da qiladi.

**Tugadi mezoni.** `OPTION_LISTS['area_unit']`; `land_area_unit` `SCHEMA` ga qo'shilgan
(house/land/commercial); `_derive()` **saqlangan birlikka** qarab konvertatsiya qiladi.
Testlar: yer 6 сотка → `area_sqm = 600`, tijorat 6 сотка → 600, tijorat 600 м² → 600.
⚠️ **FALLBACK:** `params.get('land_area_unit')` **yo'q** bo'lsa — **eski xatti-harakat**
(`land` → x100, qolgani x1). Test: eski (birliksiz) e'lonning `area_sqm` qiymati **o'zgarmaydi**.
⚠️ **PARITY:** bu qadam `SCHEMA` ni **ikkala repoda** o'zgartiradi (`land_area_unit` +
yangi `ParamControl`/`unitOptionsKey`), shuning uchun **M3-22 fixture'i qayta generatsiya qilinadi**:
`mobile/test/fixtures/param_schema.json` yangilangan, `flutter test .../param_schema_parity_test.dart`
**va** `pytest tests/test_listing_param_schema_parity.py` — **ikkalasi ham yashil**.
⚠️ `optional` DEFAULT'i teskari (Dart `false` / Python `True`) — yangi maydonda bayroq
**ikkala tarafda ham aniq yozilsin**, aks holda parity testi aynan shu yerda yiqiladi (yoki bundan
ham yomoni — fixture eskirsa jimgina o'tib ketadi).
⏭️ **M1-9 konvertori yangilangan:** tahrirlashda `params.land_area_unit` qoralamaga tiklanadi,
aks holda foydalanuvchi 6 сотка'ni tahrirlab saqlaganda u 6 м² bo'lib qoladi.

**Xavf.** Yuqori. Fallback'siz prod'dagi `area_sqm` jimgina buziladi va lenta filtri yolg'on chiqadi.

---

### 27. Xonalar `10+` (erkin son) + «Площадь балкона»

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `kadastr-backend/app/schemas/listing_options.py`, `app/services/listing_param_schema.py`, `app/services/listing_option_labels.py`, `mobile/lib/features/bozor/models/param_schema.dart`, `widgets/option_picker_sheet.dart` |

**Nega shu o'rinda.** `1354-18399` va `442-10157`.

**Tugadi mezoni.** Xonalar pickerida 1..10 + `10+`; `10+` tanlanganda ichki ‹ orqaga bilan erkin son
maydoni ochiladi va `params.rooms_count_exact` ga yoziladi; `_derive()` `rooms` ustuniga aniq sonni
yozadi; balkon tanlanganda `balcony_area` maydoni ko'rinadi (`visible_when` ikkala tarafda mos);
eski `6_plus` qiymatli e'lonlar hamon ochiladi; parity testi (22) yashil.

**Xavf.** O'rta. ⚠️ `rooms_count` ro'yxatini kengaytirish `bathrooms_count` ni ham o'zgartiradi
(u shu ro'yxatni **qayta ishlatadi**) — «10 ta sanuzel» mantiqsiz, alohida ro'yxat kerak bo'lishi mumkin.

---

### 28. Picker'lar: segmented + «Подтвердить» + qidiruv + chip-wrap

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/widgets/option_picker_sheet.dart`, `widgets/multi_select_field.dart`, `lib/features/services/widgets/segmented_tabs.dart`, `screens/bozor_type_step_screen.dart`, `screens/bozor_price_step_screen.dart` |

**Nega shu o'rinda.** `324:8488`, `4304-24985`, `442-10157`, `326-9002`. Viloyat/tuman ro'yxati uzun
(14 viloyat / 195 tuman), qidiruv yo'q.

**Tugadi mezoni.** E'lon turi va valyuta pickerlari **segmented** + «Подтвердить»;
ko'p tanlovli sheet **chip-wrap**; 10 tadan ko'p variantda **qidiruv** maydoni chiqadi va filtrlaydi;
qorong'i temada to'g'ri; `flutter analyze` toza.

**Xavf.** Past–o'rta.
✅ **`SegmentedTabs<T>` o'lik kod EMAS** — u `lib/features/applications/application_detail_screen.dart:146`
da `SegmentedTabs<_DetailTab>` sifatida **prod ekranda ishlab turibdi**. Ya'ni ko'rinish, animatsiya
(`AnimatedAlign` 220ms) va `boxShadow` allaqachon sinovdan o'tgan — **noldan tekshirish shart emas**.
Qoladigan yagona nozik joy: **uzun yorliq** («В аренду», «Продажа») 320pt kenglikda kesilishi —
buni o'sha mavjud ekranda tor qurilmada bir marta ko'rib olish yetarli, kerak bo'lsa
`FittedBox(fit: BoxFit.scaleDown)` qo'shiladi.
`showOptionPickerSheet<T>` 5 joyda ishlatiladi → qidiruvni **ixtiyoriy** (`searchable: true`) qiling,
mavjud chaqiruvlar buzilmasin. Ko'k `#0B70F0` emas, `AppColors.splashGreen`.

---

### 29. 3-qadam validatsiyasi + shartli maydonni `params` dan tozalash

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/screens/bozor_params_step_screen.dart`, `screens/bozor_all_params_screen.dart`, `widgets/param_form.dart`, `data/bozor_submit.dart`, `test/features/bozor/params_validation_test.dart` |

**Nega shu o'rinda.** Ikkita **mavjud** bug (dizayndan mustaqil), ular M1/M3 dagi E2E tekshiruvlarni
tasodifan yiqitadi:
(a) `_isComplete()` faqat `stepParamFields` ni ko'radi → «Все параметры» dagi majburiy maydonlar
(kvartirada `living_area`, `freight_elevator`; tijoratda `building_floors`, `floor`, `renovation`)
tekshirilmaydi, xato faqat serverdan;
(b) ko'rinmay qolgan shartli maydon `params` da **qoladi** → backend 400
(«'garage_area' faqat 'parking' = 'garage' boʻlganda yuboriladi»).

**Tugadi mezoni.** `flutter test test/features/bozor/params_validation_test.dart`:
(a) `parking='garage'` → `garage_area` to'ldiriladi → `parking='none'` → e'lon **400'siz** yuboriladi;
xuddi shu `has_annex/annex_area`, `with_land/land_area`, `building_type/business_center_name`;
(b) kvartirada `living_area` bo'sh bo'lsa «Далее» **o'chiq** + toast qaysi bo'lim ekanini aytadi.

**Xavf.** O'rta. Tozalash **`buildPayload` paytida** filtrlash bo'lsin (UI holati saqlanadi,
faqat yuborilmaydi) — aks holda toggle'ni tasodifan o'chirib-yoqqanda kiritilgan qiymat yo'qoladi.
Backend `validate()` da shart qo'yuvchi maydon shartlidan **oldin** turishi load-bearing —
tartibni buzmang. **Z6:** «Все параметры» yulduzchalari **ixtiyoriy qoladi**.

---

### 30–32. ~~E'lon kontaktini SMS bilan tasdiqlash~~ — **BEKOR QILINDI (2026-09-11)**

| | |
|---|---|
| **Repo** | — |
| **Fayllar** | — |

**Mahsulot qarori.** E'lon kontakt raqami **tasdiqlanmaydi**: foydalanuvchi raqamini
kiritadi va o'tib ketadi. Shu sababli uchta qadam ham bekor:

* **30.** `POST /listings/contact/send-otp` va `/verify-otp` — **yozilmaydi**.
* **31.** Mobil OTP modali — **yozilmaydi**. Aksincha, mavjud UI stub'i (dizayndagi
  «Отправить» tugmasi, 5 katak, «Qayta yuborish» taymeri) `bozor_contacts_step_screen.dart`
  dan **olib tashlandi**; `ContactsDraft.phoneVerified` va
  `bozor.contacts.{send,verified,phone_invalid,code_stub}` kalitlari ham o'chirildi.
  Qo'riqchi test: `test/features/bozor/contacts_no_otp_test.dart`.
* **32.** `contact_phone_verified` ni serverda qayta tekshirish — **kerak emas**. Ustun
  joyida qoladi (migratsiya qilinmaydi, alembic 3 head bilan buzuq) va **abadiy `false`**:
  uni `true` qiladigan oqim endi rejada ham yo'q. Adminkadagi «Telefon tasdiqlangan»
  ustuni (`app/admin.py:2268`) shu sababli hamisha «yo'q» ko'rsatadi.

**Oqibatlari.** Z1 (OTP uzunligi) va Z2 (tasdiqlash majburiymi) **ahamiyatsiz** bo'ldi;
PlayMobile SMS shabloni bloklovchisi (§3, M0-2) **olib tashlanadi** — e'lon oqimi uchun
yangi shablon kerak emas (login OTP'si o'z shabloni bilan ishlashda davom etadi).
Dizayndan ongli chekinish: 6/7 (va sotuvda 7/8) ekranida kod bloki chizilgan edi.

---

### 33. Xarita ekraniga qidiruv (autocomplete)

| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/services/screens/map_location_picker_screen.dart`, `lib/features/services/data/geocoder_client.dart` |

**Nega shu o'rinda.** `293:12981` da tepada qidiruv bor; bizda foydalanuvchi Toshkent markazidan
qo'lda surib boradi. `GeocoderClient.autocomplete()` **tayyor** (backend proksisi
`/geo/autocomplete`), faqat ulash kerak.

**Tugadi mezoni.** Xarita ekranida yuqorida input; 3+ belgi kiritilganda taklif ro'yxati;
tanlanganda xarita o'sha nuqtaga uchadi va marker qo'yiladi; `debounce 300ms`.

**Xavf.** Past. Backend Nominatim proksisi **≤1 req/s** global throttle'da — debounce'ni
qisqartirmang. `AiLocationScreen` dagi `_SearchInput`/`_SuggestionList` naqshi ko'chiriladi
(u yerda 3 marta dublikat — imkon bo'lsa umumiy widget'ga ajrating).

---

### 34. Sehrgar qoralamasini saqlash

> ⚠️ **M4 dan M1 ga KO'CHIRILDI** (2026-09-10): «Mening e'lonlarim» tabi tugatilmagan
> qoralamalarni ko'rsatishi shart, aks holda ro'yxatning yarmi bo'sh bo'ladi.
> Dizayni — M1 qamrovi bo'limida (alohida `bozor_listing_drafts` jadvali + 5 endpoint).


| | |
|---|---|
| **Repo** | mobile |
| **Fayllar** | `lib/features/bozor/data/bozor_draft_saver.dart`, `data/bozor_draft_resume.dart`, `models/bozor_draft.dart`, `lib/features/shell/main_shell.dart` |

**Nega shu o'rinda.** Oqim **8 qadamga** uzaydi; hozir `BozorDraft` faqat Navigator stack'ida
yashaydi va ilova yopilsa hammasi yo'qoladi (media yo'llari, kiritilgan matnlar, M1-11 dagi
yuklangan `key` lar). AI Baholashda `ai_draft_saver` / `ai_draft_resume` naqshi tayyor.

**Tugadi mezoni.** 5-qadamgacha to'ldirib ilovani o'ldirib qayta ochilganda «Qoralamani davom
ettirasizmi?» so'raladi va o'sha qadamdan davom etadi; muvaffaqiyatli yuborilgach qoralama o'chadi.

**Xavf.** O'rta. Lokal fayl yo'llari (iOS konteyner) qayta ishga tushirishdan keyin **yaroqsiz**
bo'lishi mumkin — tiklashda `File.existsSync()` bilan tekshirib, yo'q fayllarni ro'yxatdan
chiqaring (`MarketDownloads` faqat fayl **nomini** saqlashi ham shu sababdan).

---

### 35. 8/8: ⓘ tushuntirish sheeti, shartlar hujjati, `topTierEnabled`

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `lib/features/bozor/screens/bozor_terms_step_screen.dart`, `widgets/tier_info_sheet.dart`, `data/bozor_api.dart`, `kadastr-backend/app/api/v1/legal.py`, `assets/i18n/bundle.json` |

**Nega shu o'rinda.** **Z9.** `_showTierInfo()` va `_openTerms()` hozir faqat toast
(`info_missing`, `doc_missing`). `BozorApi.reference()` dagi `topTierEnabled` bayrog'i
**hech qayerdan o'qilmaydi** (o'lik kod) — «Топ» kartasi doim ko'rinadi, holbuki tanga tizimi yo'q.

**Tugadi mezoni.** `reference()` **chaqiriladi**; `bozor_top_enabled == false` bo'lganda «Топ» kartasi
**umuman chizilmaydi**; ⓘ → tarif tushuntirish sheeti (`293-12267` maketi, animatsiyasiz ham bo'ladi);
«условиями объявления» → hujjat sahifasi (`legal_documents` jadvaliga `bozor_terms` slug'i bilan
yozuv qo'shilgan); `grep -c 'info_missing\|doc_missing' lib/features/bozor` = **0**.
**Z5:** rozilik checkbox `false` bo'lib qoladi.

**Xavf.** O'rta. Huquqiy matn kerak (§7).

---

## M5 — Lenta filtrlari, sifat, yetkazish

### 36. Sotuv lentasi filtrlari + saralash + indekslar

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `kadastr-backend/app/api/v1/listings.py`, `app/services/bozor_listing_service.py`, `scripts/ensure_bozor_listings.py`, `mobile/lib/features/bozor/feed/bozor_feed_repository.dart`, `feed/bozor_filter_sheet.dart` |

**Nega shu o'rinda.** M2-15 ustunlarni berdi, M1-12 lentani berdi — endi ular birlashadi.
Hozir `list_public` da saralash parametri **umuman yo'q** (doim `top_rank DESC, created_at DESC`).

**Tugadi mezoni.** `GET /listings/?mortgage=true&sale_type=free_sale&sort=price_asc` ishlaydi;
`sort` ∈ `default | price_asc | price_desc | newest`; mobil filtr varag'ida ipoteka checkbox'i va
saralash tanlovi; `pytest tests/ -k feed -q` yashil.
**Indeks:** `EXPLAIN ANALYZE` bilan tekshirilgan; kerak bo'lsa `CREATE INDEX IF NOT EXISTS`
**`ensure_bozor_listings.py` ga** (alembic emas).

**Xavf.** O'rta. `ix_bozor_feed_filter (status, deal_type, property_type)` bor, lekin `mortgage` +
`price_uzs` saralash sekin bo'lishi mumkin.
⚠️ **Ma'lum qarz (bu rejaga kirmaydi):** `price_uzs` yozish paytida qotib qoladi — `usd_rate`
o'zgarsa eski qatorlar qayta hisoblanmaydi va **narx filtri yolg'on chiqadi**. Qayta hisoblash
skripti alohida vazifa sifatida qayd etiladi.

---

### 37. Regression: variantlar matritsasi + avtomatlashtirilgan testlar

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `mobile/test/features/bozor/wizard_flow_test.dart`, `test/features/bozor/build_payload_test.dart`, `kadastr-backend/tests/test_bozor_listing_create.py` |

**Nega shu o'rinda.** M3 qadamlar ro'yxatini, payload'ni va enum'larni o'zgartirdi;
M4 params mantig'iga 4 marta tegdi. Har bir (DealType × PropertyType) juftligi bo'yicha bir marta
o'tmasdan relizga chiqish xavfli.

**Tugadi mezoni.** `flutter test` to'liq yashil — har juftlik (7 sotuv + 6 ijara = 13) uchun
**payload kalit to'plami** testi (butun JSON snapshot emas — mo'rt bo'ladi);
qo'lda: 13 variant bo'yicha e'lon yaratildi → adminkada tasdiqlandi → lentada rasm bilan chiqdi →
detal ochildi; `flutter analyze` 0 issue; backend `pytest -q` M0-1 baseline'idan **yomon emas**.

Qo'shimcha ikkita **majburiy** ssenariy (ular oldingi qadamlarda yon ta'sir sifatida buzilishi
oson):

| # | Ssenariy | Kutilgan |
|---|---|---|
| R1 | **Tahrirlash aylanasi** (M1-9 konvertori): sotuv e'loni yaratiladi → «E'lonlarim» → «Tahrirlash» → hech narsa o'zgartirmasdan `PATCH` | `deal` 4 maydoni, `mortgage`, `params.land_area_unit`, media **o'zgarmagan** (jimgina NULL bo'lmagan) |
| R2 | **`sale_enabled` gate** (M2-17b): backendda bayroq `false` → ilova qayta ochiladi | 1-qadamda «Продажа» **yo'q**; bayroq `true` → paydo bo'ladi; `reference()` xato bersa — «Ijaraga» rejimi, ekran yiqilmaydi |

**Xavf.** O'rta. Snapshot testlari mo'rt bo'lmasin — kalit to'plami va majburiy qiymatlarni
tekshiring.

---

### 38. Yetkazish: deploy tartibi, versiya-skew, rollback

| | |
|---|---|
| **Repo** | ikkalasi |
| **Fayllar** | `kadastr-backend/scripts/ensure_bozor_listings.py`, `scripts/seed_app_translations.py`, `mobile/pubspec.yaml`, `docs/bozor-listing-integration-plan.md` |

**Nega shu o'rinda.** Ikkala repo o'zgardi va **tartib muhim**.

**Deploy tartibi (qat'iy).**
1. **Backend avval** — yangi option'lar, ustunlar, contact-OTP, moderatsiya UI.
2. Prod'da **qo'lda**: `docker compose exec -T app python -m scripts.ensure_bozor_listings`
   va `python -m scripts.seed_app_translations`.
3. **Keyin mobil** reliz.

Teskarisi bo'lsa `validate()` yangi kalitlarni **400** bilan rad etadi.

**Versiya-skew (Store lag).** Store'da eski ilova versiyasi **haftalab** ishlashda davom etadi.
Moslik matritsasi **test bilan** tekshiriladi, umid bilan emas:

| Klient | Backend | Kutilgan |
|---|---|---|
| eski (rent-only) | yangi | ✅ ishlaydi — `deal` yubormaydi, yangi ustunlar nullable |
| yangi (sale) | eski (rollback) | ⛔ sotuv 400 → **shuning uchun** `bozor_sale_enabled` bayrog'i backenddan keladi va rollback'da avtomatik `false` bo'ladi |

**Tugadi mezoni.** `tests/test_backward_compat.py`: eski payload (deal'siz, mortgage'siz)
**201** qaytaradi; `reference()` `sale_enabled` bayrog'ini beradi va **mobil uni hurmat qiladi**
(bayroq `false` → 1-qadamda «Продажа» ko'rinmaydi) — mobil yarim **M2-17b** da yozilgan,
testi `sale_gate_test.dart`, qo'lda tekshiruvi M5-37/R2;
real qurilmada uchi-uchiga smoke: sale/kvartira 8 qadam → OTP → 5 rasm → e'lon → admin tasdiqlaydi →
lentada thumb bilan ko'rinadi; `docs/` yangilangan.

**Xavf.** Yuqori. Mobil reliznini **qaytarib bo'lmaydi** — shuning uchun sotuv oqimining
o'chirgichi **serverda** turadi.

---

## M6 — Kechiktirilgan epic

### 39. Tanga / balans / «Топ» / 360º — epic hujjati (kod yozilmaydi)

| | |
|---|---|
| **Repo** | backend (hujjat) |
| **Fayllar** | `kadastr-backend/docs/bozor-coins-epic.md` |

**Nega shu o'rinda.** **Z9.** Bu dizayndagi **eng katta ish hajmi** va u sehrgardan tashqariga
(profil, balans, to'lov) chiqadi. «Bayroq bilan yashiramiz» — bu qamrovni **yopish emas,
kechiktirish**; buni ochiq yozib qo'yish shart, aks holda «8/8 tayyor» degan xato taassurot qoladi.

**Hujjatga kiradi.** Kerakli jadvallar (`user_coin_balance` yoki `users.coin_balance`,
`coin_transactions`, `listing_promotions`, `promotion_prices`, `panorama_orders`);
narxlar (1 tanga = 2 000 UZS; «Топ» 14🪙/7 kun; «Выделенные цветом» 7🪙; 360 paketlari
32/120/200🪙); to'lov usullari (payme, apelsin, click, upay, visa, mastercard) va ularning
mavjud `payments` feature bilan mosligi; ochiq savollar.

**`bozor_listings` ga qo'shiladigan M6 ustunlari** (xarita §11 «M6 epic ustunlari» jadvali —
ular asosiy jadvalga kirmaydi, lekin epic'da to'liq sanalishi shart):

| Ustun | Tur | Nima uchun |
|---|---|---|
| `tier_expires_at` | `DateTime(tz)`, nullable | «За 7 дней» muddati (hozir `tier` bor, muddat yo'q) |
| `top_days` / `tier_plan` | `SmallInteger` / `String(16)` | tanlangan tarif kodi |
| `is_highlighted` | `Boolean` | «Выделенные цветом» |
| `highlight_expires_at` | `DateTime(tz)`, nullable | uning muddati |
| **`panorama_order_id`** (yoki `has_panorama_order`) | `Integer` FK → `panorama_orders.id`, nullable | ⚠️ **6/8 «Заказать»** — e'lon ↔ 360º buyurtma bog'lovchisi. Ilgari ro'yxatdan tushib qolgan edi. Ortida `panorama_orders(user_id, listing_id, package, frames, price_coins, status)` jadvali kerak |

⚠️ `panorama_order_id` va `panorama_orders.listing_id` ni e'lon **yaratilishidan oldin**
to'ldirib bo'lmaydi (6/8 da hali `listing_id` yo'q) — §7, 11-savol.

**Tugadi mezoni.** Hujjat yozilgan va §7 dagi **barcha M6 savollari** unda qayd etilgan —
ya'ni 9 («Выделенные цветом» qayerda tanlanadi), 10 («Топ» muddat ro'yxati va narxlari),
11 (360º/balans e'lon yaratilishidan oldin ishlaydimi), **16** (`payment_method` provayderlari
mavjud `payments` feature bilan mos keladimi — **tekshirilmagan**), **17** («Топ» tanlangan
holatning 8/8 maketi yo'q; `293:12030` — eski 7/7 avlodi, ko'chirish **farazimiz**).
`app_settings.bozor_top_enabled = false` bilan prod'ga chiqiladi.

**Xavf.** Kommunikatsiya xavfi: bu qadam **funksiya qo'shmaydi**.

---

## 5.9 ⚠️ TUZATISH — «alembic 3 head» DA'VOSI NOTO'G'RI EDI

Bu hujjat bir necha joyda «alembic 3 head bilan buzuq» deb yozgan va shu bilan
`ensure_*.py` naqshini asoslagan. 2026-09-10 da o'lchandi:

    docker compose exec -T app alembic heads
    → davreestr_logs_01 (head)

Ya'ni **bitta head**, uchta emas. Xato qayerdan chiqqan: lokal bazada
`alembic_version` qatori UMUMAN yo'q (`alembic current` bo'sh) — baza
`ensure_*` skriptlari bilan qurilgan, migratsiyalar bilan emas. Shu sababli
lokal `alembic upgrade head` `type "marketmodelstatus" already exists` bilan
yiqiladi — bu **lokal bazaning artefakti**, migratsiya grafining nuqsoni emas.
Prod esa head'ga stamp qilingan va `.gitlab-ci.yml` 1c izohi buni tasdiqlaydi.

**Qaror o'zgarmaydi** — `ensure_*` naqshi baribir to'g'ri tanlov:
`.gitlab-ci.yml` 1b izohi ~39 obyekt (`app_settings`, `poi_cache`,
`chat_suggestions`, …) HECH QANDAY migratsiya bilan yaratilmaganini yozadi,
ya'ni bu repoda sxema manbai ikkiga bo'lingan va yangi jadval uchun ham shu
yo'l izchil. **Lekin sabab boshqa:** «3 head buzuq» emas, «bu repoda
sxemaning bir qismi tarixan `ensure_*` da yashaydi».

M6 va texnik qarz bo'limlarida «3 head» deb yozilgan joylarni shu izoh
bilan o'qish kerak.

---

## 6. Alohida qayd etilgan texnik qarz (bu rejaga kirmaydi)

| Qarz | Ta'siri | Nega hozir emas |
|---|---|---|
| **Alembic 3 head** — jadval/ustunlar faqat `ensure_bozor_listings.py` orqali | Sxema ikki manbadan (model + skript) ajralib ketishi mumkin; bu reja qarzni **chuqurlashtiradi** (6 ustun) | Head'larni birlashtirish butun repo migratsiyasiga tegadi — alohida vazifa |
| **`price_uzs` qotib qoladi** — `usd_rate` o'zgarsa qayta hisoblanmaydi | Narx filtri va saralash yolg'on chiqadi | Qayta hisoblash skripti + cron — alohida vazifa |
| **`bozor.type.other_non_res` ↔ `other_non_residential`** | Ikki manba matnlari ajralishi | M3-21 da imkon bo'lsa to'g'rilanadi |
| **`ai_location_screen` / `k3d_location_screen` / `location_picker_screen`** — ~1200 qator dublikat | Yangi xarita ekrani = 4-nusxa | M4-33 da umumiy widget'ga ajratish taklif qilinadi |
| **O'lik kod:** `shell/placeholder_screen.dart`, `home/widgets/home_card.dart`, `home_cta.dart`, `services/services_screen.dart` | — | Tozalash — alohida kichik vazifa |

---

## 7. Ochiq savollar

> §2 (ziddiyatlar) da **default** javob bor — bular esa default'siz, javob **kerak**.

1. **`sale_type` to'liq ro'yxati.** Dizaynda faqat «Свободная продажа» ko'rinadi.
   Taxmin: `free_sale`, `alternative`, `mortgage_sale`, `installment`, `exchange`.
   ⛔ **M2-16 ni bloklaydi** — kodlar prod'da abadiy qoladi.
2. **«Лет в собственности» ro'yxati.** Faqat «от 3 до 5» ko'rindi.
   Taxmin: `under_3`, `from_3_to_5`, `over_5`. SELECT bo'ladimi yoki INTEGER (yil soni)?
3. **«Собственники» va «Прописано» diapazonlari.** Faqat `1` va `0` ko'rindi.
   1..6+ va 0..6+ mi, yoki 10+ gacha? «Прописано» faqat kvartira turlaridami?
4. **«Квартира в новостройке» maxsus parametrlari.** `1297-23722` da oddiy kvartira maydonlari.
   Застройщик / срок сдачи / очередь / тип отделки kerakmi?
5. **«Ипотека» toggle qamrovi.** Faqat 2 freymda ko'rindi (`1297-23496`, `1297:25248`).
   Barcha sotuv turlarida ko'rsatiladimi yoki faqat kvartira/yangi binoda?
6. **O'qilmagan 7 freym** (`1414-21717`, `1414-21438`, `1414-21488`, `1414-21563`, `1414-21605`,
   `293-12538`, `293-12539`). Ular «Другая нежилая» oqimining qo'shimcha qadamlari bo'lsa —
   M3-18/19 qayta yoziladi. ⛔ **M3 ni bloklaydi.**
7. ~~**Bozor lentasining kirish nuqtasi.**~~ ✅ **JAVOB BERILDI (2026-09-10):**
   mavjud **Home kartasi «Bozor AI»** endi sehrgarni EMAS, **e'lonlar lentasini** ochadi;
   sehrgarga o'tish lentaning ichidagi tugma orqali. Yangi tab qo'shilmaydi, 4 tab tegilmaydi.
   Ya'ni `main_shell.dart:259 _openBozorAi()` hozir `BozorTypeStepScreen` ni push qiladi —
   u lenta ekraniga o'zgaradi.

   ⚠️ **TUZOQ:** lenta marshrutiga `bozorRoute(...)` BERILMASIN. `closeBozorWizard()`
   `bozor/` prefiksli hamma marshrutni pop qiladi (`bozor_routes.dart`), shuning uchun lenta
   shu prefiks bilan push qilinsa sehrgar tugagach foydalanuvchi lentaga emas, Home'ga
   tushib qoladi — va 8/8 dagi `pushAndRemoveUntil` ham lentani olib tashlaydi.
   Lenta prefikssiz nom bilan (yoki nomsiz) push qilinadi.
8. **Sevimlilar («Избранные»).** Umuman yo'q — na mobil, na backend, na ikonka.
   Bu rejaga **kiritilmagan**. Kerakmi va qachon?
9. **«Выделенные цветом» (7🪙) qayerda tanlanadi?** Chekda ko'rinadi, boshqaruvi `293:12030` da
   topilmadi — «Топ» bilan avtomatik keladimi yoki alohida checkbox? → M6.
10. **«Оплата за Отправить в Топ» muddat ro'yxati va narxlari.** Faqat «За 7 дней» = 14🪙. → M6.
11. **360º va «Пополнить баланс» oqimlari e'lon yaratilishidan OLDIN ishlaydimi** (hali
    `listing_id` yo'q)? Buyurtma qoralamaga bog'lanadimi? → M6.
12. **Moderatsiya `rejection_reason` tili.** Admin erkin matn yozadi va foydalanuvchiga o'sha holicha
    ko'rsatiladi — uz/ru/en farqi yo'q. Tayyor sabablar ro'yxati (lokalizatsiya qilingan) kerakmi?
13. **E'lon shartlari hujjatining huquqiy matni** (M4-35) — kimdan olinadi?
14. **M1-9 tahrirlash oqimida media.** `MediaOut` da `storage_key` yo'q (ataylab) —
    tahrirlashda mavjud rasmlarni saqlash uchun `storage_key` qaytarilsinmi yoki server tomonda
    «o'zgarmagan media» rejimi qo'shilsinmi?
15. **4/8 «Сделка» qadami IJARA oqimida ham bormi?** Ijara freymlarida
    (`docs/bozor-ai-figma-map.md`, 55 freym) bunday qadam **yo'q edi**, va maydonlar
    («Тип продажи», «Лет в собственности») sotuvga xos — shuning uchun **«faqat sotuvda»** deb
    qabul qildik. Lekin bu **bizning xulosamiz**, dizaynda ochiq yozilmagan.
    **Default (javob kelmasa): faqat sotuvda.**
    «Ha, ijarada ham» javobi kelsa: `wizardSteps` matritsasi 4 kombinatsiyadan **2 ga** tushadi
    (`params bor / yo'q`), M3-18 testi va M3-19 ekrani (Прописано/Тип продажи ijarada mantiqsiz)
    **qayta yoziladi**, ijara header raqamlari ham 8/7 bo'ladi.
    ⛔ **M3-18 va M3-19 ni bloklaydi** (§3).
16. **`payment_method` provayderlari mos keladimi?** Dizaynda «Пополнение баланса» modalida
    6 ta logotip: **payme, apelsin, click, upay, VISA, mastercard** (`304-10507`, `304-11012`).
    Ilovada `payments` feature bor (market to'lovlari, Payme deep-link), lekin uning provayderlar
    ro'yxati bu 6 talik bilan **solishtirilmagan** (xarita §10). Mos kelmasa: yo yangi
    integratsiya (har biri alohida ish), yo dizayndan chekinish. → **M6**, lekin javob epic'ni
    baholash uchun **oldindan** kerak.
17. **«Топ» tanlangan holatning 8/8 dagi maketi bormi?** Yagona maket — `293:12030`, u
    **eski 7/7 avlodida** chizilgan; yangi 8/8 freymlarida faqat **standart** holat bor
    (xarita §0.4, §12 №69). Biz «7/7 maketi 8/8 ga o'zgarishsiz ko'chiriladi» deb **qabul qildik** —
    bu **bizning farazimiz**. Ta'sir doirasi M6 bilan cheklangan (hozircha «Топ» yashiriladi),
    shuning uchun **bloklovchi emas**, lekin M6 ochilganda birinchi tasdiqlanadigan narsa.

---

## 8. Revizion — tekshiruvdan keyingi tuzatishlar

> Bu bo'lim hujjatning **ishonchlilik darajasini** ko'rsatadi: quyidagi nuqtalar tashqi
> tekshiruvda topilgan va tuzatilgan. Kelajakda shu joylarga tegilganda ehtiyot bo'ling.

| # | Nima noto'g'ri edi | Endi qanday |
|---|---|---|
| 1 | «`SegmentedTabs<T>` — o'lik kod, hech qayerda ishlatilmagan» (xarita 1/8 delta №4, reja M4-28 xavfi). **Fakt xatosi**, manbadan ko'chirilgan | U `lib/features/applications/application_detail_screen.dart:146` da **prod ekranda ishlaydi**. M4-28 xavfi past–o'rtaga tushirildi, «noldan sinash» talabi olib tashlandi |
| 2 | M2-15 `owners_count` / `registered_count` ni **`SMALLINT`** qilib belgilagan edi, holbuki ro'yxat qiymatlari (`6_plus`) M2-16 da aniqlanadi — ya'ni ustun turi **o'zidan keyingi** qadamga tayanardi | Ikkalasi ham **`String(8)`**; sabab xarita §11 da va M2-15 da yozildi (`SMALLINT` → prod'da `ALTER COLUMN TYPE`, alembic 3 head bilan buzuq) |
| 3 | §3 bloklovchilar jadvali option ro'yxatlari faqat **M2-16** ni bloklaydi degan edi | **M2-15 + M2-16** — M2-15 `String(8)` tanlovi bilan blok **yumshatiladi** |
| 4 | M1-10 tugadi mezoni «"E'lonimni ko'rish" o'sha e'lonni ochadi» degan edi — detal ekrani esa **M1-13** da yoziladi (oldinga bog'liqlik) | M1-10 mezoni `MyListingsScreen` gacha tushirildi, detalga o'tish **M1-13 mezoniga** ko'chirildi (⏭️ eslatma bilan) |
| 5 | M4-26 sxemani ikkala repoda o'zgartiradi, lekin **parity fixture'ini qayta generatsiya qilish** talabi yo'q edi | M4-26 mezoniga qo'shildi; M3-22 ga «bu testdan keyin sxemaga tegadigan qadamlar» jadvali qo'shildi (M4-26, M4-27) |
| 6 | «(по желанию)» vs qizil `*` konvensiya farqi **ziddiyat qatori sifatida yo'q** edi, holbuki 4/8 da 4 maydondan 3 tasi ixtiyoriy | Yangi **Z15** qatori + xarita §14.1 + M3-19 mezonida qat'iy qo'llash |
| 7 | «`293:12030` (7/7) maketi 8/8 ga ko'chiriladi» — **faraz**, hech qayerda qayd etilmagan edi | Xarita §0.4 va §12 №69 da `(?)` bilan belgilandi; reja §7, **17-savol** |
| 8 | `payment_method` provayderlarining mavjud `payments` feature bilan mosligi «tekshirilmagan» deb faqat xaritada turardi, §7 ga kirmagan | Reja §7, **16-savol** + M6-39 tugadi mezoniga kiritildi |
