# Bozor AI v2 — Figma xaritasi (SOTUV / «Продажа» oqimi)

> **Bu hujjat nima?** Figma'dagi **«Продажа»** (sotuv) oqimining 89 ta freymidan o'qilgan
> maketlarning kodga tarjimasi. Har qadam uchun: node ID'lar, maydonlar jadvali, bizdagi hozirgi
> holat va **delta** (nima qilish kerak).
>
> **Avvalgi hujjat:** [`docs/bozor-ai-figma-map.md`](./bozor-ai-figma-map.md) — u **IJARA**
> («В аренду») oqimining 55 freymi. Bu hujjat uni almashtirmaydi, ustiga qo'shiladi.
>
> **Qoida:** dizayn yorliqlari **RUSCHA aynan** ko'chirilgan (Figma'dagi imlo xatolari bilan birga —
> ular alohida belgilangan va **kodga ko'chirilmaydi**). Izohlar o'zbekcha.
>
> **Ranglar:** Figma NoMakler namunasidan olingan — ko'k `#0B70F0` va pastdagi 5 tabli bottom bar
> **bizda YO'Q**. Barcha aksent `AppColors.splashGreen` (#00E135), tugma `ListingCtaButton`
> (56dp, radius 999).

---

## 0. Umumiy shakl — sehrgar endi 8 qadam

### 0.1 Qadamlar ketma-ketligi (header raqamlari bo'yicha)

```
1/8 Тип объявления → 2/8 Адрес → 3/8 Параметры → 4/8 Сделка (YANGI)
  → 5/8 Цена → 6/8 Описание → 7/8 Контакты → 8/8 Условия размещения
```

### 0.2 Variant bo'yicha qadamlar soni

| Deal | Mulk turi | Qadamlar | Ro'yxat |
|---|---|---|---|
| `sale` | Квартира, Квартира в новостройке, Дом, Участок, Коммерческая, Гараж/парковочное место | **8** | type, address, params, **deal**, price, description, contacts, terms |
| `sale` | Другая нежилая | **7** | type, address, **deal**, price, description, contacts, terms |
| `rent` | params bor 6 tur | **7** (hozirgidek) | type, address, params, price, description, contacts, terms |
| `rent` | Другая нежилая | **6** (hozirgidek) | type, address, price, description, contacts, terms |

**Muhim:** `1414:21355` freymida header aynan **«1/7»** — ya'ni «Другая нежилая» haqiqatan
7 qadamli variant, eski avlod emas. Bizdagi `wizardSteps` mantig'i (otherNonResidential dan
`params` olib tashlanadi) **o'zgarishsiz** ishlaydi, faqat ro'yxatga `WizardStep.deal` qo'shiladi.

### 0.3 Kod tomondan nima o'zgaradi

Hozir (`lib/features/bozor/models/bozor_draft.dart:86-106`):

```dart
List<WizardStep> get wizardSteps => switch (this) { /* faqat PropertyType */ };
// BozorDraft:
List<WizardStep> get wizardSteps => (type ?? PropertyType.apartment).wizardSteps;
```

Bo'lishi kerak: ro'yxat **(DealType × PropertyType)** juftligiga bog'lanadi, `BozorDraft` da
fallback ham ikki o'lchovli (`deal ?? DealType.rent`, `type ?? PropertyType.apartment`).

Qadam raqamlari **hech qayerda qo'lda yozilmagan** — hamma ekran
`'${draft.stepNumber(WizardStep.X)}/${draft.stepCount}'` naqshini ishlatadi, shuning uchun bitta
shu o'zgarish butun sehrgarni avtomatik 1/8…8/8 ga o'tkazadi.

### 0.4 Eski avlod (7 qadamli) freymlar

`324:8488` (1/7 ustidagi picker), `442-10157` (1/7 ustidagi Балкон picker), `1414-21396` (2/7),
`293:12030` (7/7) — bular Figma'dagi **eski versiya**, 1/8 avlodi yangisi. Ulardan faqat
**picker/holat maketlari** olinadi, qadam raqami emas.

⚠️ **QAYD ETILGAN FARAZ.** `293:12030` — «Топ» **tanlangan** holatning (tarif muddati, tanga
balansi, chek kartochkasi) **yagona** maketi, va u eski 7/7 avlodida chizilgan. Yangi 8/8
freymlarida (`293-11894`, `304:8566`, `1297-23663`, `1297-25418`, `1414-18813`, `1414:20209`)
faqat **standart** holat bor. Biz «7/7 dagi tarif bloki 8/8 ga o'zgarishsiz ko'chiriladi» deb
**qabul qildik** — dizaynda bu **tasdiqlanmagan**. Ta'siri **M6** epic'ga cheklangan
(«Топ» hozircha `bozor_top_enabled = false` bilan yashiriladi), shuning uchun bu **bloklovchi emas**,
lekin M6 ochilganda birinchi tekshiriladigan narsa (reja §7, 17-savol).

### 0.5 ⚠️ METODOLOGIK QOIDA — freym NOMLARI yolg'on gapiradi

Bu qoida butun hujjat bo'ylab qo'llanilgan va **qolgan 7 ta o'qilmagan freymni o'qiyotganda ham
(M0-2) qo'llanilishi shart**.

Figma'dagi deyarli hamma freym `Add new apartment sell` yoki `Sell House N` deb nomlangan, lekin
**ichidagi qiymatlar boshqa oqimga tegishli**. Aniqlangan misollar:

| Freym nomi | Aslida nima |
|---|---|
| «Sell House 1» | **Участок** (yer uchastkasi) |
| «Sell Apartment 8» | **4/8 Сделка** qadami |
| «Sell House 6» | **7/8 Контакты** qadami |

**Ishonchli manba — faqat ikkitasi:**

1. Freym **header'idagi** «N/8 — Nom» matni (masalan «4/8 - Сделка»);
2. **Kanvasdagi bo'lim sarlavhasi** (`293:12536` «Продать квартиру», `1297:25476` «Продать дом»,
   `302:8022` «Продать участок», `1297-23721` «Продать новостройку», `1414-18871`
   «Продать коммерческую», `1414-20267` «Продать гараж парковку», `1414:21663`
   «Продать другая нежилая»).

**Freym nomiga TAYANMANG.** Node ID diapazoni (masalan `1297-23xxx` ≈ новостройка,
`1297-25xxx` ≈ дом) — bu faqat **xulosa**, dalil emas; shunga tayangan qatorlar §12 da `(?)`
bilan belgilangan.

### 0.6 Sotuv oqimining feature-flag'i (`bozor_sale_enabled`)

Butun sotuv oqimi backenddagi `app_settings.bozor_sale_enabled` bayrog'i ostida turadi
(default `false`). Bayroq `GET /api/v1/listings/reference` javobida `sale_enabled` maydoni
sifatida keladi.

⚠️ **Mobil taraf ham shu bayroqni bilishi SHART**, aks holda bayroqning hech qanday ma'nosi yo'q:

- `ListingReference` hozir **faqat** `top_tier_enabled` ni parslaydi
  (`lib/features/bozor/data/bozor_api.dart:218`);
- `bozor_type_step_screen.dart` da hech qanday gate yo'q;
- `BozorApi.reference()` umuman **chaqirilmaydi** (o'lik kod).

Kerak bo'ladigan mobil ish (reja: **M2-17b**):
`ListingReference.saleEnabled` parsing → sehrgar boshida `reference()` chaqiruvi (offline/xato
holatida `false` fallback) → 1-qadamdagi «Тип объявления» pickerida `Продажа` varianti
**umuman ko'rsatilmaydi**.

---

## 1/8 — «Тип объявления» / E'lon turi

**Node ID'lar:** `293-11278`, `302:7981`, `1297:23413`, `1297:25161`, `1414-18558`, `1414-19959`,
`1414:21355` (1/7), `324:8488` (picker sheet)

**Tegishli variantlar:** hammasi (universal qadam)

### Maydonlar

| Yorliq (RU) | Kontrol | Majburiy | Birlik | Qiymatlar |
|---|---|---|---|---|
| Тип объявления | select → picker sheet | ✅ | — | `Продажа` \| `В аренду` |
| Вид недвижимости | select | ✅ | — | `Жилая` \| `Нежилая` |
| Тип недвижимости | select | ✅ | — | `Квартира` \| `Квартира в новостройке` \| `Дом` \| `Участок` \| `Коммерческая` \| `Гараж/парковочное место` \| `Другая нежилая` |

### Bizdagi holat: **bor**

`lib/features/bozor/screens/bozor_type_step_screen.dart` (196 qator) — 3 ta `SelectField` +
`showOptionPickerSheet`.

### Delta

1. **YANGI MULK TURI** `Квартира в новостройке` (`1297:23413`). Bizda `PropertyType` da 6 qiymat,
   7-si qo'shiladi: `newBuildingApartment`, kod `new_building_apartment`.
   Backendda ham: `PROPERTY_TYPES`, `KIND_TYPES['residential']`, `listing_param_schema.SCHEMA`,
   `listing_option_labels.LABELS`, `primary_area_key()`.
2. **SOTUV TARMOQLANISHI** — `DealType.sale` tanlanganda oqim `deal` qadamli ro'yxatga o'tadi.
   Hozir `sale` hech qayerda tarmoqlanmagan (enum'da bor, `.code` payload'ga ketadi, xolos).
3. Ekranning o'zi (3 ta SelectField) **o'zgarmaydi**.
4. Figma'da «Тип объявления» pickeri **segmented** (2 yonma-yon tugma), bizda `ChoiceTile` ro'yxati.
   `SegmentedTabs<T>` widget'i repoda **bor va ALLAQACHON ISHLATILADI** —
   `lib/features/applications/application_detail_screen.dart:146` (`SegmentedTabs<_DetailTab>`).
   Ya'ni u **o'lik kod EMAS**, prod ekranda ishlab turibdi.
   ✅ Amaliy natija: uni bozor picker'iga ko'chirishdan oldin **noldan sinash shart emas** —
   ko'rinishini va uzun yorliq («В аренду») xatti-harakatini o'sha mavjud ekranda 320pt
   kenglikda tekshirib olish yetarli (M4-28).
5. **Nom nomuvofiqligi tuzatilsin:** mobil i18n kaliti `bozor.type.other_non_res`, backend kodi
   `other_non_residential`. Yangi turda takrorlanmasin: kalit `bozor.type.new_building_apartment`.
6. **`sale_enabled` GATE (§0.6)** — bu qadam bayroqning **yagona ko'rinadigan nuqtasi**.
   Backend `reference()` javobida `sale_enabled` beradi (M2-14), mobil uni parslab
   (`ListingReference.saleEnabled`) va sehrgar boshida chaqirib, bayroq `false` bo'lganda
   «Тип объявления» pickeridan `Продажа` variantini **olib tashlashi kerak** (M2-17b).
   Bayroqsiz M2 va M3 orasida foydalanuvchi yarim ishlaydigan sotuv oqimiga kirib qoladi.
   Xato/offline holatida **`false` fallback** (xavfsiz taraf).

---

## 2/8 — «Адрес» / Manzil

**Node ID'lar:** `293-11360` (Квартира, 8 maydon), `1297:23454` (Квартира, 8), `1297-25202`
(Дом: +Дом, Этажей в доме), `302:8194` (4), `1414-18599` (4), `1414-20000` (Гараж, 4),
`1414-21396` (2/7, 4), `293:12981` (Map picker), `293-13034` (Map loader / spinner)

**Tegishli variantlar:** Квартира va Квартира в новостройке — 8 qator; Дом — 6 qator;
Участок / Коммерческая / Гараж / Другая нежилая — 4 qator.

### Maydonlar

| Yorliq (RU) | Kontrol | Majburiy | Birlik | Izoh |
|---|---|---|---|---|
| Регион | select (list ikonka) | ✅ | — | placeholder «Область, город» |
| Район | select | ✅ | — | viloyat tanlanmaguncha o'chiq |
| Адрес квартиры / Адрес | text + **QIZIL map-pin** tugmasi | ✅ | — | placeholder «Населенный пункт, улица, дом» |
| Ориентир | text | ❌ «(по желанию)» | — | |
| Номер квартиры | number | ✅ | — | faqat kvartira turlari |
| Подъезд | number | ❌ | — | faqat kvartira turlari |
| Дом (номер дома) | number | ✅ | — | faqat Дом |
| Этажей в доме | number | ✅ | — | kvartira + Дом |
| Этаж | number | ✅ | — | faqat kvartira turlari |

### Bizdagi holat: **bor**

`lib/features/bozor/screens/bozor_address_step_screen.dart` (458 qator).
`AddressRow` enum va `PropertyTypeAddressX.addressRows` dizayn bilan **1:1 mos**
(apartment 8, house 6, qolgani 4).

### Delta

1. Yangi `newBuildingApartment` turi uchun `addressRows` = apartment bilan bir xil.
2. **Xarita ekranida QIDIRUV YO'Q** — dizayn `293:12981` da tepada qidiruv maydoni bor, bizdagi
   `MapLocationPickerScreen` da autocomplete yo'q (u faqat `LocationPickerScreen` /
   `AiLocationScreen` da bor). `GeocoderClient.autocomplete()` tayyor — ulash kerak.
3. `293-13034` yuklanish holati (input ichida spinner) — `AddressPinField.busy` allaqachon bor. ✅
4. `1414-21396` dagi katta bo'sh blok («xarita preview») — render bo'lmagan placeholder bo'lishi
   mumkin, **noaniq** (`?`). Xarita preview qo'shilmaydi.
5. Tarmoqlanish: `_onContinue()` hozir `next == params ? 'params' : 'price'` deb yozilgan —
   `deal` shoxini biladigan to'liq `switch` ga o'tkazilsin.

---

## 3/8 — «Параметры» / Parametrlar

**Node ID'lar:** `293-11448` (Квартира), `1297-23722` (Квартира), `1297-25477` (Дом, 9 maydon),
`304:8183` (Участок), `1414-18872` (Коммерческая), `1414:20268` (Гараж, 9 maydon),
`293-12134` («Все параметры» to'liq ekrani), `326-9002` / `4572-25279` / `1354-18399` /
`442-10157` (picker holatlari)

**Tegishli variantlar:** Другая нежилая'da bu qadam **YO'Q**.

### Maydonlar — variant bo'yicha

**Квартира / Квартира в новостройке** (2 maydon + «Все параметры»)

| Yorliq (RU) | Kontrol | Majburiy | Birlik |
|---|---|---|---|
| Количество комнат | select | ✅ | — |
| Общая площадь | number | ✅ | м² |
| **Все параметры** | qator-tugma → `293-12134` | — | — |

**Дом** (9 maydon + «Все параметры»)

| Yorliq (RU) | Kontrol | Majburiy | Birlik |
|---|---|---|---|
| Площадь участка | number + **BIRLIK DROPDOWN** | ✅ | `соток` ⌄ |
| Тип участка | select | ✅ | — |
| Электричество | select «Да» (bizda toggle) | ✅ | — |
| Водоснабжение | select «Да» | ✅ | — |
| Газ | select «Да» | ✅ | — |
| Канализация | select «Да» | ✅ | — |
| Площадь дома | number | ✅ | м² |
| Количество комнат | select | ✅ | — |
| Тип дома | select | ✅ | — |

**Участок** (4 maydon + «Все параметры»)

| Yorliq (RU) | Kontrol | Majburiy | Birlik |
|---|---|---|---|
| Площадь участка | number + birlik dropdown | ✅ | `соток` |
| Тип участка | select | ✅ | — (ko'ringan: `Садовый`) |
| Площадь участка/дома | number | ✅ | м² — **Figma dublikat xatosi** |
| Количество комнат | select | ✅ | — |

**Коммерческая** (4 maydon + «Все параметры»)

| Yorliq (RU) | Kontrol | Majburiy | Birlik |
|---|---|---|---|
| Назначение | select | ✅ | — (ko'ringan: `Для офиса`) |
| Тип здания | select | ✅ | — (ko'ringan: `Бизнес-центр`) |
| Площадь участка | number | ✅ | м² |
| Площадь участка | number + birlik dropdown | ✅ | `соток` — **dublikat label** |

**Гараж** (9 maydon, «Все параметры» YO'Q)

| Yorliq (RU) | Kontrol | Majburiy | Birlik |
|---|---|---|---|
| Тип | select | ✅ | — (`Парковочное место`) |
| Тип парковки | select | ✅ | — (`Наземная`) |
| Высота потолков | number | ✅ | м |
| Материал | multiselect | ❌ | — |
| Статус | multiselect | ❌ | — |
| Название ГСК | text | ❌ | — |
| Площадь | number | ✅ | м² |
| Безопасность (гараж) | multiselect | ✅ | — |
| Удобства (гараж) | multiselect | ✅ | — |

### Bizdagi holat: **qisman**

`lib/features/bozor/models/param_schema.dart` (522 qator, 86 maydon) +
`lib/features/bozor/widgets/param_form.dart` + `screens/bozor_params_step_screen.dart` +
`screens/bozor_all_params_screen.dart`. Sxema backend `listing_param_schema.py` bilan **86/86 mos**.

### Delta

| # | Farq | Nima qilinadi |
|---|---|---|
| 1 | **Maydon birligi dropdowni** — dizaynda «Площадь участка» ichida vertikal ajratgich + `соток` + chevron. Bizda `unit` faqat statik suffiks. | Yangi `area_unit` option ro'yxati + `ParamControl.numberWithUnit` (yoki `ParamField.unitOptionsKey`) + `params.land_area_unit` |
| 2 | **ZIDDIYAT:** Коммерческая'da «Площадь участка» соток'da (`1414-18872`), bizda `commercial.land_area` = м². Backend `_derive()` sotix→m² ni faqat `property_type=='land'` da qiladi. | Konvertatsiya **saqlangan birlikka** qarab; `land_area_unit` NULL bo'lsa **eski xatti-harakat** fallback (aks holda prod'dagi `area_sqm` jimgina buziladi) |
| 3 | Kommunallar dizaynda **select «Да»**, bizda **toggle** | **Toggle'da qolamiz** (ongli chekinish — backend `TOGGLE` sifatida validatsiya qiladi, o'zgartirish `listing_param_schema.py` ni buzadi) |
| 4 | «Количество комнат» pickerida 10 tagacha + `10+` → **erkin son** (`1354-18399`). Bizda max `6_plus` | `rooms_count` → 1..10 + `10_plus`; `params.rooms_count_exact`; `_derive()` `rooms` ustuniga aniq sonni yozadi |
| 5 | «Балкон» pickeri **segmented 1/2/3** + «Площадь балкона» (м²) bitta sheet ichida (`442-10157`). Bizda `balcony_area` YO'Q | Yangi `balcony_area` ParamField (`visible_when: balcony != 'none'`), ikkala tarafda |
| 6 | Дом 3/8 da 9 maydon `inStep` | Bizda ham 9 ta — **mos** ✅ |
| 7 | Гараж'da «Все параметры» YO'Q | Bizda `hasAllParamsScreen == false` — **mos** ✅ |
| 8 | `Квартира в новостройке` uchun param jadvali dizaynda ochilmagan (`1297-23722` da oddiy kvartira maydonlari) | Hozircha `apartment` nusxasi. Maxsus maydonlar (застройщик, срок сдачи, очередь, тип отделки) — **ochiq savol** |
| 9 | «Высока потолков» — Figma imlo xatosi, 2 marta | Bizda bir marta, to'g'ri ✅ |

### Mavjud buglar (dizayndan mustaqil, lekin shu qadamda)

- `_isComplete()` faqat `stepParamFields` ni tekshiradi → «Все параметры» ekranidagi
  **majburiy** maydonlar (kvartirada `living_area`, `freight_elevator`; tijoratda `building_floors`,
  `floor`, `renovation`) tekshirilmaydi, xato faqat serverdan qaytadi.
- Ko'rinmay qolgan shartli maydon `params` dan **o'chirilmaydi** → backend 400:
  «'garage_area' faqat 'parking' = 'garage' boʻlganda yuboriladi». Xuddi shu
  `has_annex/annex_area`, `with_land/land_area`, `building_type/business_center_name` da.

---

## 4/8 — «Сделка» / Bitim ⚡ BUTUNLAY YANGI

**Node ID'lar:** `1296:22239` (Квартира, 4 maydon), `1297:23777` (Квартира, 4),
`1297:25522` (Квартира, 4), `1297:23248` (Дом, 3), `1414-18932` (3), `1414:20323` (Гараж, 3)

**Tegishli variantlar:** faqat **СОТУВ**. Ijara freymlarida bunday qadam yo'q va maydonlar
(«Тип продажи», «Лет в собственности») sotuvga xos.

> ⚠️ **BU BIZNING XULOSAMIZ, DIZAYNDA OCHIQ YOZILMAGAN.** Ijara oqimining 55 freymida
> (`docs/bozor-ai-figma-map.md`) bunday qadam yo'q edi, lekin «ijarada bo'lmaydi» degan yozuv
> ham yo'q. Agar javob **«ha, ijarada ham bor»** bo'lsa — `wizardSteps` matritsasi (4 kombinatsiya
> → 2 ta), uning testi (reja **M3-18**) va header raqamlari (ijara ham 8/7 bo'ladi) **qayta
> yoziladi**. Shuning uchun bu savol reja §7 da **15-savol** sifatida qayd etilgan;
> **default javob — «faqat sotuvda»**.

### Maydonlar

| Yorliq (RU) | Kontrol | Majburiy | Ko'ringan qiymat | Qaysi variantda |
|---|---|---|---|---|
| Тип продажи | select → picker | ❌ «(по желанию)» | `Свободная продажа` | hammasi |
| Лет в собственности | select | ❌ «(по желанию)» | `от 3 до 5` | hammasi |
| **Собственники** | select | ✅ **yagona majburiy** | `1` | hammasi |
| Прописано | select | ❌ «(по желанию)» | `0` | **faqat Квартира / Квартира в новостройке** (Дом, Гараж da YO'Q) |

### Bizdagi holat: **yo'q**

Mobilda ham, backendda ham hech narsa yo'q. `grep -niE "ownership|owners_count|sale_type|собственн|сделк"`
`app/models`, `app/schemas`, `listing_param_schema.py`, `listings.py` bo'ylab **0 natija**
(yagona o'xshash — `app/integrations/davreestr.py:258` «Количество собственников», kadastr
ma'lumotnomasini parslash, e'longa aloqasi yo'q).

### Delta

**MOBIL:**
- Yangi `WizardStep.deal` enum qiymati.
- Yangi `TransactionDraft { String? saleType; String? ownershipYears; String? ownersCount; String? registeredCount; }`
  va `BozorDraft.transaction`.
  ⚠️ **Nom to'qnashuvi:** `BozorDraft.deal` allaqachon `DealType?` uchun band —
  `deal` nomini ikki ma'noda ishlatmang.
- Yangi ekran `lib/features/bozor/screens/bozor_deal_step_screen.dart` — mavjud andoza bo'yicha
  (`ServiceAppBar` + `StepProgressBar` + 3–4 ta `SelectField` + `showOptionPickerSheet` +
  `WizardNavBar`). **Yangi widget KERAK EMAS.**
- Marshrut `bozorRoute('deal')` — **SHART**, aks holda `closeBozorWizard` shu ekranda to'xtaydi.
- Validatsiya: `continueEnabled = ownersCount != null`.
- ⚠️ **Majburiylik belgisi (§14.1, reja Z15):** dizayn 3 ta ixtiyoriy maydonni «(по желанию)» bilan
  belgilaydi, biz esa `SelectField(required: true)` orqali **majburiy**ni qizil `*` bilan.
  Bu qadam — konvensiya farqi eng ko'zga tashlanadigan joy (4 maydondan 3 tasi ixtiyoriy).
  Default: `*` da qolamiz, ya'ni «Собственники» da `required: true`, qolgan uchtasida
  `required: false` va **hech qanday qo'shimcha matn yo'q**.

**BACKEND:** 4 ta yangi OPTION_LISTS + 4 ta ustun (pastdagi §10, §11).

**i18n:** ⚠️ `bozor.deal.rent` / `bozor.deal.sale` kalitlari **ALLAQACHON band** (1-qadamdagi e'lon
turi uchun). Yangi qadam kalitlari: **`bozor.transaction.*`**
(`title`, `sale_type`, `ownership_years`, `owners_count`, `registered_count`).

---

## 5/8 — «Цена» / Narx

**Node ID'lar:** `293:11548` (Квартира, 2 boshqaruv), `304-8291` (Дом/Участок), `1414-18643`,
`1414:20042` (Гараж), `1297-23496` (+ Ипотека toggle), `1297:25248` (+ Ипотека toggle),
`4304-24985` (valyuta bottom sheet: UZS/USD segmented + «Подтвердить»)

### Maydonlar

| Yorliq (RU) | Kontrol | Majburiy | Birlik | Izoh |
|---|---|---|---|---|
| Стоимость квартиры / дома / участка / гаража / помещения | number + **INLINE VALYUTA DROPDOWN** | ✅ | `UZS` ⌄ | placeholder «Цена». Figma'da hamma joyda «Стоимость участки» — **copy-paste + imlo xatosi** |
| Торг уместен | toggle | — | — | sukut bo'yicha **YOQILGAN** |
| Ипотека | toggle | — | — | sukut **YOQILGAN**; faqat `1297-23496`, `1297:25248` freymlarida |

### Bizdagi holat: **qisman**

`lib/features/bozor/screens/bozor_price_step_screen.dart` (195 qator).

### Delta

| # | Farq | Nima qilinadi |
|---|---|---|
| 1 | **Sotuvda davr YO'Q** — dizaynda faqat `UZS`/`USD`, «/oy» yo'q. Bizda `PriceDraft.unit` sukut `'UZS/oy'`, ro'yxat `['UZS/oy','USD/oy']` | Sale'da `['UZS','USD']`, `_periodOf()` → `null`. Sukut qiymat **1-qadamda deal tanlangandan keyin** o'rnatilsin (`setDeal` ichida), aks holda rent→sale qaytganda `'UZS/oy'` qolib ketadi va backend 400 beradi |
| 2 | **Yorliq** — bizda qat'iy `bozor.price.rent` («Ijara haqi» / «Арендная плата») | `PropertyTypeX.priceLabel(locale, deal)` + 7 ta yangi i18n kalit |
| 3 | **Sutkalik narx** (`dailyAmount`) sotuv dizaynida YO'Q | `_hasDailyPrice` ga `deal == DealType.rent` sharti |
| 4 | **Ипотека toggle YANGI** | `PriceDraft.mortgage` + `bozor_listings.mortgage` USTUN (lentada filtr bo'lishi ehtimoli yuqori) |
| 5 | Valyuta sheeti dizaynda **segmented** (`UZS \| USD`) + «Подтвердить». Bizda ChoiceTile ro'yxati, tanlangach darhol yopiladi | `SegmentedTabs` + tasdiq tugmasi (M4) |
| 6 | `PriceField` widget'i | O'zgarishsiz yaraydi ✅ |

⚠️ «Ипотека» faqat 2 freymda ko'rindi — barcha sotuv turlarida ko'rsatiladimi yoki faqat
kvartira/yangi binoda — **ochiq savol**.

---

## 6/8 — «Описание» / Tavsif

**Node ID'lar:** `293:11660` (Квартира, 360 yonida «Заказать»), `2561-23030` («Вы добавили 8
изображений» + eskiz stack + «+8»), `304-8375`, `1297-23546`, `1297-25301`, `1414-18696`,
`1414-20092`, `2561-23152` («Add photo» — alohida foto boshqarish ekrani),
`2902:23030` / `2902-23139` / `2902:23248` (360 xizmat buyurtma modallari)

### Maydonlar

| Yorliq (RU) | Kontrol | Majburiy | Izoh |
|---|---|---|---|
| О квартире / Об участке / … | textarea (132dp, ~5 qator) | ✅ | placeholder «Расскажите о недвижимости». Figma'da 6 freymdan 4 tasida «Об участке» — **copy-paste xatosi** |
| Добавить планировку | upload qatori (28×28 ikonka + matn) | ❌ | |
| Добавить фото | upload qatori → **alohida ekran** | ❌ | to'ldirilgan: «Вы добавили N изображений» + 3 ta 36×36 stack + «+N» |
| Добавить 360 фото | upload qatori + o'ngda ko'k **«Заказать»** matn-tugmasi | ❌ | pullik 360 xizmatiga buyurtma |
| Видео с YouTube | text (url) | ❌ «(по желанию)» | placeholder «Ссылка на видео с YouTube» |

### Bizdagi holat: **qisman**

`lib/features/bozor/screens/bozor_description_step_screen.dart` (246 qator) +
`widgets/media_upload_row.dart`.

### Delta

| # | Farq | Nima qilinadi |
|---|---|---|
| 1 | **«E'lon sarlavhasi» (title)** — dizaynda **HECH BIR** qadamda yo'q, bizda bor va backend `title` NOT NULL (min 3) | **ZIDDIYAT** — §Ziddiyatlar (plan doc) |
| 2 | To'ldirilgan holat: dizaynda gorizontal eskiz tasmasi EMAS, 2 qatorli matn + 3 ta stack + «+N» | `MediaUploadRow` ga yangi ko'rinish rejimi |
| 3 | «Добавить фото» → **ALOHIDA TO'LIQ EKRAN** (`2561-23152`): 3 ustunli 109×109 grid, har rasmda ×, oxirgi katak punktir ramkali «qo'shish», header'da «Готово», pastda «Сохранить» | Yangi ekran `bozor_photos_screen.dart` |
| 4 | **«Заказать»** (360 xizmat) — yangi CTA + 3 modal + tanga iqtisodi | **Kechiktiriladi** (M6 epic) |
| 5 | 360 / планировка bittalab `pickImage` | Dizaynda ham shunday — **mos** ✅ |
| 6 | **Media limitlari nomuvofiq:** mobil `_maxPhotos = 20` uchala qatorga; backend plan=5, panorama=5, photo=20 | Rol bo'yicha limit + klientda 20 MB hajm tekshiruvi |
| 7 | Backend planirovka uchun **PDF** ga ruxsat beradi, mobil faqat `ImagePicker` | `file_picker` pubspec'da bor — **ochiq savol** |
| 8 | Muqova (`is_cover`) va tartib (`sort_order`) protokolda **qo'llab-quvvatlanadi**, UI yo'q | Foto ekranida muqova nishoni + drag-reorder (dizaynda ko'rsatilmagan — bizning qo'shimchamiz) |
| 9 | **Thumbnail hech qachon yasalmaydi** — `thumb_url`/`width`/`height`/`bytes` to'ldirilmaydi | Lenta grid'i 20 MB originallarni yuklaydi → `listings.build_thumbs` kerak |

---

## 7/8 — «Контакты» / Kontaktlar

**Node ID'lar:** `293-11810` (Имя + Номер + «+ Добавить номер телефона» + Отправить),
`304-8485` («Отправить» + «Далее» ikkalasi), `1297-23621`, `1297-25376`, `1414-18771`,
`1414-20167`, `293:12520` («For authorised»: Моё имя / Мой номер toggle'lari),
`293-12207` («Confirmed»: yashil ✓ + trash), `293:12214` («Number verification» modal, 6 katak, 1/3),
`293:12460` («Number verification error», qizil ramkali OTP)

### Maydonlar

| Yorliq (RU) | Kontrol | Majburiy | Izoh |
|---|---|---|---|
| Имя | text | ✅ | placeholder «Введите имя» |
| Номер телефона | phone | ✅ | `+998` prefiks oldindan |
| + Добавить номер телефона | havola-tugma | — | 1–3 raqam |
| Отправить | birlamchi tugma | — | SMS kod yuborish |
| **Моё имя** | toggle | — | **avtorizatsiya qilinganda**, YOQILGAN (profildagi ismni ishlatish) |
| **Мой номер** | toggle | — | **avtorizatsiya qilinganda**, YOQILGAN |
| [modal] Код подтверждения | **6 ta katak** (OTP) | ✅ | ⚠️ bizda 5 |
| [modal] Отправить код снова через 00:39 | taymer + qayta yuborish | — | ~60s |

### Bizdagi holat: **qisman (UI stub)**

`lib/features/bozor/screens/bozor_contacts_step_screen.dart` (348 qator).
Fayl boshidagi izoh ochiq aytadi: `_sendCode()`/`_verifyCode()` **hech qanday so'rov yubormaydi**
(`bozor.contacts.code_stub` toast), chunki backendda e'lon kontaktini tasdiqlash endpointi yo'q,
`/auth/verify-otp` esa **token qaytaradi va foydalanuvchini qayta login qiladi**.

### Delta

| # | Farq | Nima qilinadi |
|---|---|---|
| 1 | **OTP UZUNLIGI:** dizaynda 6 katak (raqamlar `5 2 6 8 2 9`), bizda va backendda 5 (`generate_code()` 10000..99999, `VerifyOTPRequest` min=max=5, PlayMobile shabloni 5 uchun tasdiqlangan) | **ZIDDIYAT** — tavsiya: 5 da qolish |
| 2 | OTP **alohida to'liq ekranli modal** (✕, tahrirlanadigan telefon chipi + qalam, taymer, ↻), xatoda **qizil ramkalar**. Bizda inline `OtpBoxes` | Yangi ekran `bozor_contact_otp_screen.dart` |
| 3 | Tasdiqlangan holat (`293-12207`): input ichida yashil ✓ + alohida 44×44 **trash** tugmasi | Bizda ✓ matn qatori bor, trash yo'q |
| 4 | **Avtorizatsiya qilingan foydalanuvchi** (`293:12520`): har maydon ostida «Моё имя» / «Мой номер» toggle'lari | Bizda **YO'Q** — yangi. Bu login qilgan foydalanuvchi uchun eng ko'p uchraydigan holat |
| 5 | Ikkita tugma («Отправить» kontent ichida + «Далее» pastda) | `ListingCtaButton` + `WizardNavBar` — mos ✅ |
| 6 | **BACKEND YO'Q** | `POST /listings/contact/send-otp` + `/verify-otp` (token qaytarmaydigan), Redis prefiksi `contact_otp:{phone}`. PlayMobile'da **yangi SMS shabloni tasdiqlanishi shart** |
| 7 | `ResendTimer` default 90s, backend rate-limit 60s, dizaynda 00:39 dan | 60s ga moslash |
| 8 | `contact_phone_verified` ustuni **bor**, uni `true` qiladigan oqim yo'q | Backend Redis bayrog'iga (`contact_otp_verified:{phone}`) qarab qo'yadi — **klientga ishonmaymiz** |

---

## 8/8 — «Условия размещения» / Joylashtirish shartlari

> Figma'da **«Условые размещения»** — imlo xatosi. Bizda to'g'ri: «Условия размещения»
> (`bozor.terms.title`), ataylab tuzatilgan, **saqlanadi**.

**Node ID'lar:** `293-11894` (Квартира, Стандартное tanlangan), `304:8566` (Дом, ⓘ ikkalasida),
`1297-23663`, `1297-25418`, `1414-18813`, `1414:20209`,
`293:12030` (7/7 — **«Топ» TANLANGAN** holat: tarif + balans + chek + «Пополнить баланс»),
`293-12267` («Tariff» promo modal), `293:12382` («Animation» illyustratsiya asseti)

### Maydonlar — ASOSIY (standart tarif)

| Yorliq (RU) | Kontrol | Majburiy | Izoh |
|---|---|---|---|
| Стандартное объявление | radio (54dp karta) | — | o'ngda ⓘ |
| Отправить в "Топ" | radio | — | 🚀 raketa + o'ngda ⓘ |
| Я согласен с условиями объявления | checkbox | ✅ | dizaynda **BELGILANGAN** keladi; «условиями объявления» — havola |
| Предпросмотр | ikkilamchi tugma | — | dizaynda **kulrang/passiv** |
| Разместить | birlamchi tugma | — | |

### Maydonlar — «Топ» TANLANGANDA (`293:12030`)

| Element (RU) | Qiymat |
|---|---|
| Оплата за "Отправить в Топ" | select — `За 7 дней` + **14 🪙** |
| Баланс | `0 🪙` + «+ Пополнить баланс» (pushti konturli tugma) |
| CHEK bloki | Отправить в ТОП (за 7 дней) : **14🪙** / Выделеные цветом (за 7 дней) : **7🪙** / Скидка(0%) 0 UZS / **Итого: 21🪙 (21 000 UZS)** |
| Rozilik matni | «Вы соглашаетесь с Условиями использования и Политикой конфиденциальности…» |

### Bizdagi holat: **qisman**

`lib/features/bozor/screens/bozor_terms_step_screen.dart` (255 qator) — 2 ta `TierCard` +
`BozorConsentRow` + 2 tugma. Asosiy ko'rinish **mos** ✅.

### Delta

| # | Farq | Nima qilinadi |
|---|---|---|
| 1 | «Топ» tanlanganda ochiladigan **butun blok** (tarif muddati, tanga balansi, «Пополнить баланс» modali, chek kartochkasi, «Выделеные цветом», chegirma, «Итого») | **HECH BIRI yo'q** (mobil ham, backend ham). **Kechiktiriladi** — M6 epic; hozircha `app_settings.bozor_top_enabled = false` bilan **«Топ» kartasi umuman yashiriladi** |
| 2 | `_showTierInfo()` hozir faqat `info_missing` toast | ⓘ → tarif tushuntirish sheeti (`293-12267` maketi) |
| 3 | `_openTerms()` hozir faqat `doc_missing` toast | Hujjat sahifasi (`legal_documents` jadvali mavjud) |
| 4 | «Предпросмотр» dizaynda kulrang/passiv, bizda ishlaydigan `showDraftPreviewSheet` | Dizayn bizdan **orqada** — funksiyani o'chirmaymiz |
| 5 | Rozilik checkbox dizaynda **belgilangan**, bizda ataylab `false` | **ZIDDIYAT** — huquqiy sabab, dizayndan ongli chekinamiz |
| 6 | `BozorApi.reference().topTierEnabled` **hech qayerdan chaqirilmaydi** (o'lik kod) | Ulash: bayroq `false` → «Топ» kartasi chizilmaydi |

---

## 9. Sehrgar bo'lmagan ekranlar

| Ekran | Node ID'lar | Bizdagi holat | Delta |
|---|---|---|---|
| **Success** — «Объявление опубликовано успешно» (yashil ✓, «На главную», header/back YO'Q) | `4122:24824` | **BOR** — `screens/bozor_success_screen.dart` | ⚠️ **ZIDDIYAT:** backend HAR DOIM `status='pending'` qaytaradi. Matn «E'lon moderatsiyaga yuborildi» bo'lishi kerak. Dizaynda 1 tugma, bizda 2. Yaratilgan `id` **ishlatilmaydi** |
| **Map picker** — tepada qidiruv, markazda pin, o'ngda locate/+/−, pastda «Далее» | `293:12981`, `293-13034` | **BOR** — `services/screens/map_location_picker_screen.dart` | Qidiruv maydoni YO'Q → `GeocoderClient.autocomplete` ulanadi. Xarita OSM (dizaynda Google Maps skrinshoti — o'z yechimimiz qoladi) |
| **«Все параметры»** — 2 bo'lim («Параметры» 13 + «Дополнительные» 12), header o'ngda ko'k «Готово» | `293-12134`, `4572-25279`, `326-9002`, `1354-18399` | **BOR** — `screens/bozor_all_params_screen.dart` | ⚠️ Dizaynda «Безопасность/Удобства/Благоустройство/Инфраструктура» yorliqlarida **yulduzcha (\*) = majburiy**, bizda `optional: true` — **ZIDDIYAT**. Yana: 3-qadam validatsiyasi bu ekrandagi majburiy maydonlarni tekshirmaydi (mavjud bug) |
| **Bitta tanlovli picker sheet** | `324:8488`, `4572-25279`, `1354-18399`, `442-10157`, `4304-24985` | **BOR** — `widgets/option_picker_sheet.dart` | (a) ba'zilari **segmented**; (b) pastda **«Подтвердить»**, bizda tanlangach darhol yopiladi; (c) «Количество комнат» → `10+` → erkin son; (d) uzun ro'yxatlarga **qidiruv** yo'q |
| **Ko'p tanlovli picker sheet** | `326-9002` (Вид из окон: Парк ✓, Улица ✓, Город, Озеро, Площадка) | **BOR** — `widgets/multi_select_field.dart` | Dizaynda gorizontal **wrap-chiplar**, bizda vertikal ChoiceTile — ko'rinish farqi |
| **«Добавить фото» to'liq ekrani** | `2561-23152` | **YO'Q** | Yangi ekran (3 ustunli 109×109 grid, ×, punktir «qo'shish», «Готово», «Сохранить») |
| **SMS kod modali** + xato holati | `293:12214`, `293:12460` | **QISMAN** — `OtpBoxes` (5 katak) + `ResendTimer` inline | Yangi modal ekran + 2 ta backend endpoint |
| **360º xizmat modallari** — paket tanlash (1 кадр 32🪙 / 4 кадров 120🪙 / 8 кадров 200🪙 / Более 8 кадров) + hisob-kitob + balans + chek | `2902:23030`, `2902-23139`, `2902:23248` | **YO'Q** (mobil ham, backend ham) | **M6 epic** |
| **«Пополнение баланса» modali** — stepper, hisob kartochkasi, to'lov usullari 2×3 grid (Payme, Apelsin, CLICK, upay, VISA, mastercard) | `304-10507` (1 tanga, − o'chiq), `304-11012` (20 tanga, − faol) | **YO'Q** | **M6 epic**. Narx: 1 tanga = 2 000 UZS (chiziqli, chegirma 0%) |
| **«Топ» promo modali** — 🚀 + «В 3 раза больше звонков…» + animatsiya | `293-12267`, `293:12382` | **YO'Q** | ⓘ ning javobi bo'lishi mumkin (`?`). Illyustratsiya alohida asset |
| **Kanvas bo'lim sarlavhalari** (UI EMAS) | `293:12536`, `1297:25476`, `302:8022`, `1297-23721`, `1414-18871`, `1414-20267`, `1414:21663` | — | Implementatsiya qilinmaydi. Qaysi freym qaysi variantga tegishli ekanini aniqlash uchun |
| **Ikonka asseti** (15×15 «+») | `394-9699` | **BOR** — `Icons.add_circle_outline_rounded` | SVG saqlash shart emas |

---

## 10. Yangi option ro'yxatlari

> Kodlar **prod e'lonlarida abadiy saqlanadi** — bir marta tanlanadi va keyin **o'zgartirilmaydi**.
> ⚠️ Belgilangan ro'yxatlar mijoz tasdig'igacha **bloklovchi** (pastdagi «(?)» belgilari).

| Ro'yxat | Qayerda | Ko'ringan qiymat | Taxminiy to'liq to'plam |
|---|---|---|---|
| `sale_type` | 4/8 «Тип продажи» | `Свободная продажа` | ⚠️(?) `free_sale`, `alternative`, `mortgage_sale`, `installment`, `exchange` |
| `ownership_years` | 4/8 «Лет в собственности» | `от 3 до 5` | ⚠️(?) `under_3`, `from_3_to_5`, `over_5`. **SELECT** (INTEGER emas — dizaynda picker ikonkasi bor) |
| `owners_count` | 4/8 «Собственники» | `1` | ⚠️(?) `1`,`2`,`3`,`4`,`5`,`6_plus`. `rooms_count` ni **qayta ishlatmang** («6+ mulkdor» g'alati) |
| `registered_count` | 4/8 «Прописано» | `0` | ⚠️(?) `0`,`1`,`2`,`3`,`4`,`5`,`6_plus`. **Noldan** boshlanadi |
| `area_unit` | 3/8 birlik dropdowni | `соток`, `м²` | `sotix`, `sqm`, (?) `hectare` |
| `yes_no` | 3/8 kommunallar (dizaynda select) | `Да` | **KERAK EMAS** — toggle'da qolamiz (ongli chekinish) |
| `top_duration` | 8/8 «Топ» tanlanganda | `За 7 дней` = 14🪙 | ⚠️(?) 3/7/14/30 kun + narx. Oddiy option list emas — **narxli tarif jadvali** → M6 |
| `promo_addon` | 8/8 chekdan | `Выделеные цветом` = 7🪙 | `top`, `highlight` → M6. UI'da qayerda tanlanishi **noaniq** |
| `panorama_package` | 360 modali | 1 кадр=32🪙, 4 кадров=120🪙, 8 кадров=200🪙, Более 8 кадров=narxsiz | → M6 |
| `payment_method` | Balans to'ldirish | payme, apelsin, click, upay, visa, mastercard | → M6. ⚠️ **OCHIQ SAVOL** (reja §7, 16-savol): bu 6 ta provayder ilovadagi mavjud `payments` feature provayderlari bilan mos keladimi — **tekshirilmagan**. Mos kelmasa M6 epic'da yo yangi integratsiya, yo dizayndan chekinish kerak |
| **`PROPERTY_TYPES` kengaytmasi** | 1/8 | `Квартира в новостройке` | `new_building_apartment` — yangi ro'yxat emas, mavjudini kengaytirish |
| **`rooms_count` kengaytmasi** | 3/8 | 10 tagacha + `10+` | `1`..`10`, `10_plus`. ⚠️ `bathrooms_count` ayni ro'yxatni qayta ishlatadi — «10 ta sanuzel» g'alati, alohida ro'yxat kerak bo'lishi mumkin |

---

## 11. Yangi backend ustunlari

> **MIGRATSIYA QOIDASI:** alembic grafida **3 ta head** bor
> (`davreestr_logs_01`, `f0a1b2c3d4e5`, `legal_docs_01`) va `bozor_listings` jadvali faqat
> `scripts/ensure_bozor_listings.py` orqali yaratiladi. Har bir yangi ustun **AYNAN o'sha skriptga**
> `ALTER TABLE … ADD COLUMN IF NOT EXISTS` sifatida yoziladi. **Alembic revisiyasi yozilmasin.**
> Tekshiruv: skript ikki marta ketma-ket xatosiz ishlashi shart (idempotentlik).
>
> **MOSLIK QOIDASI:** hamma yangi ustun **nullable** (yoki `DEFAULT` bilan NOT NULL);
> `deal` bo'limi payload'da **ixtiyoriy**; majburiylik **DB darajasida emas**, faqat
> `deal_type == 'sale'` bo'lgandagi pydantic validatsiyasida. Shunda prod'dagi eski e'lonlar
> va Store'dagi eski ilova versiyalari ishlashda davom etadi.

| Ustun | Tur | Null | Qadam | Nega ustun (params emas) |
|---|---|---|---|---|
| `sale_type` | `String(24)` | ✅ | 4/8 | Lentada filtr |
| `ownership_years` | `String(16)` | ✅ | 4/8 | — |
| `owners_count` | **`String(8)`** | ✅ | 4/8 | Dizaynda majburiy, lekin DB'da NULL (eski rent e'lonlari). ⚠️ pastdagi izohga qarang |
| `registered_count` | **`String(8)`** | ✅ | 4/8 | Faqat kvartira turlari. ⚠️ pastdagi izohga qarang |
| `mortgage` | `Boolean` | NOT NULL, `server_default 'false'` | 5/8 | «Ipoteka bilan» filtri ehtimoli yuqori |
| `land_area_unit` | `String(8)` | ✅ | 3/8 | `_derive()` konvertatsiyasi shunga qarab ishlaydi |

> ⚠️ **NEGA `SmallInteger` EMAS, `String(8)`.** `owners_count` va `registered_count` —
> **select** maydonlari (dizaynda picker ikonkasi bor), va §10 dagi taxminiy to'plamda
> `6_plus` kabi **son bo'lmagan** kod bor. To'liq ro'yxat esa mijoz javobidan keyin aniqlanadi
> (reja **M2-16**, bloklangan).
>
> Agar ustun `SMALLINT` qilib yaratilsa va javobda `6_plus` (yoki `10_plus`) chiqsa —
> prod'da **`ALTER TABLE … ALTER COLUMN … TYPE varchar`** kerak bo'ladi, alembic esa 3 head bilan
> buzuq. `String(8)` **ikkala holatni ham** ushlaydi: sof son (`"3"`) ham, kodli qiymat
> (`"6_plus"`) ham sig'adi.
>
> Ya'ni option ro'yxatlarining shakli **M2-15 (ustun turi) ni ham bloklaydi**, faqat M2-16 ni emas
> (reja §3, bloklovchilar jadvali).
>
> Boshqa kod-ustunlar (`sale_type`, `ownership_years`, `land_area_unit`) allaqachon `String` —
> ular bilan bir xil naqsh saqlanadi va `listing.option.*` yorliqlari bir xil ishlaydi.

### ⚠️ Nega «Сделка» maydonlari `params` JSON'ga SIG'MAYDI

`listing_param_schema.validate(property_type, params)` **faqat `property_type` ni biladi**,
`deal_type` ni **ko'rmaydi**. Demak:

- `owners_count` ni `Param(optional=False)` qilsak → **IJARA** e'lonlari ham 400 oladi
  (va Store'dagi eski ilova versiyalari butunlay ishdan chiqadi);
- `optional=True` qilsak → dizayndagi yagona majburiy maydon serverda **umuman tekshirilmaydi**.

Shuning uchun: **alohida ustun + `DealIn` pydantic bo'limi + `deal_type=='sale'` shartidagi
`model_validator`**.

### M6 epic ustunlari (hozir YOZILMAYDI — Z9, reja M6-39)

Bular yuqoridagi jadvalga **kirmaydi**, chunki tanga iqtisodi kechiktirilgan. Lekin ular
dizaynda ko'ringan va epic hujjatida qayd etilishi shart:

| Ustun | Tur | Qadam / ekran | Izoh |
|---|---|---|---|
| `tier_expires_at` | `DateTime(tz)`, nullable | 8/8 «За 7 дней» | Hozir `tier` bor, **muddat yo'q**; `top_rank` ni admin qo'lda qo'yadi |
| `top_days` (yoki `tier_plan`) | `SmallInteger` / `String(16)` | 8/8 | Tanlangan tarif muddati kodi |
| `is_highlighted` | `Boolean` | 8/8 chek — «Выделенные цветом» | 7🪙 qo'shimcha xizmat |
| `highlight_expires_at` | `DateTime(tz)`, nullable | 8/8 | — |
| **`panorama_order_id`** (yoki `has_panorama_order: Boolean`) | `Integer` FK → `panorama_orders.id`, nullable | 6/8 «Заказать» (360º) | ⚠️ **Manba ro'yxatida bor, ilgari tushib qolgan edi.** E'lon ↔ 360º buyurtma bog'lovchisi. Ortida alohida `panorama_orders` jadvali kerak: `user_id`, `listing_id`, `package`, `frames`, `price_coins`, `status` |

### Kerak bo'ladigan yangi jadvallar (M6 epic — hozir yozilmaydi)

`user_coin_balance` (yoki `users.coin_balance`), `coin_transactions`, `listing_promotions`,
`promotion_prices`, `panorama_orders`. Hozir backendda **tanga tushunchasi umuman yo'q**.

⚠️ **Muhim nozik jihat:** `panorama_order_id` ustuni ham, `panorama_orders.listing_id` ham
e'lon **yaratilishidan oldin** to'ldirib bo'lmaydi (sehrgar 6/8 da hali `listing_id` yo'q) —
buyurtma qoralamaga bog'lanadimi yoki e'lon yaratilgach mi, dizaynda **tushuntirilmagan**
(reja §7, 11-savol).

### Mavjud, lekin to'ldirilmaydigan ustunlar

`bozor_listing_media.thumb_url`, `width`, `height`, `bytes` — yuklash endpointi ularni
**hech qachon yozmaydi**. `docs/bozor-listing-integration-plan.md` da `listings.build_thumbs`
Celery vazifasi rejalashtirilgan, lekin yozilmagan. Lenta grid'i 20 MB originallarni yuklaydi.

---

## 12. Node ID → qadam ko'rsatkichi (89 node)

> **Qadam ustuni** freym **header'idagi** «N/8» matnidan olingan — bu ishonchli.
>
> **Variant ustuni** kanvasdagi bo'lim sarlavhasidan olingan; u ko'rinmagan joyda **node ID
> diapazoni** bo'yicha xulosa qilingan (`1297-23xxx` ≈ новостройка, `1297-25xxx` ≈ дом).
> Diapazon bo'yicha qilingan xulosalar **`(?)`** bilan belgilangan — ular **dalil emas**
> (§0.5: freym nomlari yolg'on gapiradi). M3-37 dagi 13 variantli regressiya matritsasida
> ular qayta tekshirilishi kerak.

| # | Node ID | Qadam / Ekran | Variant / Izoh |
|---|---|---|---|
| 1 | `293-11278` | 1/8 Тип объявления | Квартира |
| 2 | `302:7981` | 1/8 | Участок |
| 3 | `1297:23413` | 1/8 | **Квартира в новостройке** (yangi tur) |
| 4 | `1297:25161` | 1/8 | Дом |
| 5 | `1414-18558` | 1/8 | Коммерческая |
| 6 | `1414-19959` | 1/8 | Гараж/парковочное место |
| 7 | `1414:21355` | **1/7** | Другая нежилая — haqiqiy 7 qadamli variant |
| 8 | `324:8488` | 1/8 picker sheet | Тип объявления (segmented, eski avlod) |
| 9 | `293-11360` | 2/8 Адрес | Квартира, 8 maydon |
| 10 | `1297:23454` | 2/8 | Квартира, 8 maydon |
| 11 | `1297-25202` | 2/8 | Дом (+Дом, Этажей в доме), 6 maydon |
| 12 | `302:8194` | 2/8 | Участок, 4 maydon |
| 13 | `1414-18599` | 2/8 | Коммерческая, 4 maydon |
| 14 | `1414-20000` | 2/8 | Гараж, 4 maydon |
| 15 | `1414-21396` | **2/7** | Другая нежилая, 4 maydon (eski avlod header) |
| 16 | `293:12981` | Map picker ekrani | Tepada qidiruv — bizda YO'Q |
| 17 | `293-13034` | Map loader | Input ichida spinner — `AddressPinField.busy` ✅ |
| 18 | `293-11448` | 3/8 Параметры | Квартира, 2 maydon |
| 19 | `1297-23722` | 3/8 | Квартира в новостройке **(?)** — ichida oddiy kvartira maydonlari |
| 20 | `1297-25477` | 3/8 | Дом, 9 maydon |
| 21 | `304:8183` | 3/8 | Участок, 4 maydon (dublikat label) |
| 22 | `1414-18872` | 3/8 | Коммерческая — «Площадь участка» **соток** (ziddiyat) |
| 23 | `1414:20268` | 3/8 | Гараж, 9 maydon, «Все параметры» YO'Q |
| 24 | `293-12134` | «Все параметры» ekrani | Параметры 13 + Дополнительные 12; **yulduzchalar** |
| 25 | `326-9002` | Ko'p tanlovli picker | Вид из окон (chip-wrap) |
| 26 | `4572-25279` | Bitta tanlovli picker | Количество комнат, 10 ta radio |
| 27 | `1354-18399` | Picker | Количество комнат → `10+` → **erkin son** |
| 28 | `442-10157` | Picker | Балкон: segmented 1/2/3 + **Площадь балкона** |
| 29 | `1296:22239` | **4/8 Сделка** | Квартира, 4 maydon |
| 30 | `1297:23777` | 4/8 | Квартира, 4 maydon |
| 31 | `1297:25522` | 4/8 | Квартира, 4 maydon |
| 32 | `1297:23248` | 4/8 | Дом, 3 maydon (Прописано YO'Q) |
| 33 | `1414-18932` | 4/8 | 3 maydon |
| 34 | `1414:20323` | 4/8 | Гараж, 3 maydon |
| 35 | `293:11548` | 5/8 Цена | Квартира, 2 boshqaruv |
| 36 | `304-8291` | 5/8 | Дом / Участок |
| 37 | `1414-18643` | 5/8 | Коммерческая |
| 38 | `1414:20042` | 5/8 | Гараж |
| 39 | `1297-23496` | 5/8 | **+ Ипотека toggle** |
| 40 | `1297:25248` | 5/8 | **+ Ипотека toggle** |
| 41 | `4304-24985` | Valyuta bottom sheet | UZS \| USD segmented + «Подтвердить» |
| 42 | `293:11660` | 6/8 Описание | Квартира; 360 yonida «Заказать» |
| 43 | `2561-23030` | 6/8 to'ldirilgan holat | «Вы добавили 8 изображений» + stack + «+8» |
| 44 | `304-8375` | 6/8 | Участок |
| 45 | `1297-23546` | 6/8 | Квартира — diapazon bo'yicha ehtimol **Квартира в новостройке** **(?)** |
| 46 | `1297-25301` | 6/8 | Дом |
| 47 | `1414-18696` | 6/8 | Коммерческая |
| 48 | `1414-20092` | 6/8 | Гараж |
| 49 | `2561-23152` | **«Добавить фото» ekrani** | 3 ustunli grid, «Готово» / «Сохранить» |
| 50 | `2902:23030` | 360 xizmat modali | Paket tanlash |
| 51 | `2902-23139` | 360 xizmat modali | Hisob-kitob + balans |
| 52 | `2902:23248` | 360 xizmat modali | Tasdiqlash |
| 53 | `293-11810` | 7/8 Контакты | Имя + Номер + «+ Добавить» + «Отправить» |
| 54 | `304-8485` | 7/8 | «Отправить» + «Далее» ikkalasi |
| 55 | `1297-23621` | 7/8 | Квартира — diapazon bo'yicha ehtimol **Квартира в новостройке** **(?)** |
| 56 | `1297-25376` | 7/8 | Дом |
| 57 | `1414-18771` | 7/8 | Коммерческая |
| 58 | `1414-20167` | 7/8 | Гараж |
| 59 | `293:12520` | 7/8 fragment | **«For authorised»**: Моё имя / Мой номер toggle'lari |
| 60 | `293-12207` | 7/8 fragment | **«Confirmed»**: yashil ✓ + trash tugmasi |
| 61 | `293:12214` | OTP modali | **6 katak**, «Подтверждение номера (1/3)», taymer 00:39 |
| 62 | `293:12460` | OTP xato holati | **Qizil ramkalar** + «Отправить код снова» ↻ |
| 63 | `293-11894` | 8/8 Условия размещения | Квартира, Стандартное tanlangan |
| 64 | `304:8566` | 8/8 | Дом, ikkala qatorda ⓘ |
| 65 | `1297-23663` | 8/8 | Квартира — diapazon bo'yicha ehtimol **Квартира в новостройке** **(?)** |
| 66 | `1297-25418` | 8/8 | Manbada «Квартира», diapazon bo'yicha ehtimol **Дом** **(?)** |
| 67 | `1414-18813` | 8/8 | Коммерческая |
| 68 | `1414:20209` | 8/8 | Гараж |
| 69 | `293:12030` | **7/7 — «Топ» tanlangan** | Tarif + balans + chek + «Пополнить баланс» → M6. ⚠️ **FARAZ (?)**: bu **eski avlod** (7/7) freymi; «Топ» tanlangan holatning **8/8 dagi** ko'rinishi Figma'da **alohida chizilmagan**. Biz «7/7 dagi maket 8/8 ga o'zgarishsiz ko'chiriladi» deb **qabul qildik** — dizaynda tasdiqlanmagan. M6 epic ochilganda qayta tekshirilsin (reja §7, 17-savol) |
| 70 | `293-12267` | «Топ» promo modali | ⓘ ning javobi bo'lishi mumkin (?) |
| 71 | `293:12382` | «Animation» asseti | Matnsiz illyustratsiya (4 ta e'lon kartasi + raketa) |
| 72 | `4122:24824` | **Success ekrani** | «Объявление опубликовано успешно» — matn ziddiyati |
| 73 | `304-10507` | «Пополнение баланса» | 1 tanga holati, − o'chiq → M6 |
| 74 | `304-11012` | «Пополнение баланса» | 20 tanga holati, − faol → M6 |
| 75 | `394-9699` | Ikonka asseti | 15×15 «+» (Добавить номер телефона) — bizda `Icons.add_circle_outline_rounded` ✅ |
| 76 | `293:12536` | Kanvas sarlavhasi | «Продать квартиру» |
| 77 | `1297:25476` | Kanvas sarlavhasi | «Продать дом» |
| 78 | `302:8022` | Kanvas sarlavhasi | «Продать участок» |
| 79 | `1297-23721` | Kanvas sarlavhasi | «Продать новостройку» |
| 80 | `1414-18871` | Kanvas sarlavhasi | «Продать коммерческую» |
| 81 | `1414-20267` | Kanvas sarlavhasi | «Продать гараж парковку» |
| 82 | `1414:21663` | Kanvas sarlavhasi | «Продать другая нежилая» |
> **⚠️ 2026-09-10 holati:** quyidagi 7 freym Figma MCP kvotasi tugagani uchun o'qilmadi.
> Qayta urinilganda server `Rate limit exceeded, please try again tomorrow` qaytardi —
> ya'ni kvota **kunlik** va **ertaga** tiklanadi. Ish boshlashdan oldin shu 7 tasini
> o'qib, ushbu jadvalni va §0.2 (variant bo'yicha qadamlar soni) ni yangilash kerak.
> Ular «Другая нежилая» oqimining qo'shimcha qadamlari bo'lib chiqsa — reja M3-18/M3-19
> qayta yoziladi (reja §3, §7 №6).

| 83 | `1414-21717` | ⚠️ **O'QILMAGAN** | Figma rate limit. Ehtimol «Другая нежилая» keyingi qadami (?) |
| 84 | `1414-21438` | ⚠️ **O'QILMAGAN** | Ehtimol «Другая нежилая» 3/7 yoki 4/7 (?) |
| 85 | `1414-21488` | ⚠️ **O'QILMAGAN** | rate limit + MCP avtorizatsiyasi |
| 86 | `1414-21563` | ⚠️ **O'QILMAGAN** | rate limit |
| 87 | `1414-21605` | ⚠️ **O'QILMAGAN** | rate limit |
| 88 | `293-12538` | ⚠️ **O'QILMAGAN** | 293-125xx diapazoni — «Продать квартиру» yordamchi fragmenti (?) |
| 89 | `293-12539` | ⚠️ **O'QILMAGAN** | yuqoridagi bilan juft |

**⚠️ 83–89 (7 ta freym) o'qilmagan.** Agar ular «Другая нежилая» oqimining qo'shimcha qadamlari
bo'lsa — `wizardSteps` mantig'i, testlari va header raqamlari qayta yoziladi. **Rejaning
`M0` bosqichida qayta so'rov yuborilishi shart** (bloker).

---

## 13. Figma matn xatolari — kodga KO'CHIRILMAYDI

| Figma'da | To'g'risi | Qayerda |
|---|---|---|
| «Условые размещения» | Условия размещения | 8/8 header |
| «Стоимость участки» | Стоимость участка | 5/8, hamma freymda |
| «Высока потолков» | Высота потолков | 3/8, 2 marta |
| «Выделеные цветом» | Выделенные цветом | 8/8 chek |
| «Об участке» kvartira/uy oqimida | О квартире / О доме | 6/8, 6 freymdan 4 tasida |
| «Адрес квартиры» uy/garaj oqimida | Адрес | 2/8 |
| «Площадь участка» ikki marta | — | `304:8183`, `1414-18872` |
| «Санузел» ikki marta | — | `326-9002` |
| «Вы добавили 8 изоброжений» (layer nomi) | изображений | `2561-23030` — render'da to'g'ri |

---

## 14. Uslub eslatmalari (kodga tarjima qilishda)

| Figma (NoMakler) | Bizda |
|---|---|
| Ko'k `#0B70F0` (havola, aksent, «Все параметры», «Заказать», «Готово») | `AppColors.splashGreen` (#00E135) |
| Pastdagi 5 tabli bottom bar (Главная/Поиск/Добавить/Избранные/Кабинет) | **Ko'chirilmaydi** — bizda 4 tab va sehrgar to'liq ekran push |
| Majburiylik belgisi: «(по желанию)» = ixtiyoriy | Qizil `*` (#E0492A) = majburiy — **teskari konvensiya**. Qaror: reja **Z15** (tavsiya: `*` da qolamiz) |
| Google Maps | OSM / flutter_map |
| Radiuslar | maydon/karta 14, TierCard/ChoiceTile 16, sheet 20, tugma 999 |
| Shriftlar | MTSCompact w700 (yorliq/sarlavha/tugma), MTSText (qiymat/matn) |

⚠️ **`ParamField.optional` DEFAULT'i ikki tarafda TESKARI:** Dart `false` (majburiy),
Python `True` (ixtiyoriy). Yangi maydonni bir tarafda bayroqsiz qo'shsangiz — **jimgina desync**.
Shuning uchun parity testi majburiy (plan doc, M3-22), va **sxemaga tegadigan har bir qadam**
(M2-14, M2-15, M2-16, M3-21, M4-26, M4-27) o'z tugadi mezonida
`test/fixtures/param_schema.json` ni **qayta generatsiya qilib** parity testini yashil qilishi shart.

### 14.1 «(по желанию)» vs qizil `*` — UI qarori (Z15)

Bu shunchaki uslub emas, **4/8 «Сделка» qadamida darhol kerak bo'ladigan qaror**: u yerda 4 ta
maydondan **3 tasi ixtiyoriy** («Тип продажи», «Лет в собственности», «Прописано») va faqat
«Собственники» majburiy.

| | Dizayn | Bizda |
|---|---|---|
| Nima belgilanadi | **Ixtiyoriy** maydon — yorliq yonida kulrang «(по желанию)» matni | **Majburiy** maydon — yorliq yonida qizil `*` (`Color(0xFFE0492A)`, 14pt) |
| Qayerda | Barcha qadamlar | `WizardField`, `SelectField`, `MultiSelectField`, `BozorPhoneField`, `PriceField`, `AddressPinField`, `ParamForm` — **har bir maydon widget'ida takrorlangan** |

**Tavsiya:** qizil `*` da qolamiz — «(по желанию)» ga o'tish 7 ta widget'ni va butun ilovaning
qolgan sehrgarlarini (AI Baholash, 3D kadastr, kalkulyator TZ) ham o'zgartirishni talab qiladi,
chunki ular ayni widget'larni ishlatadi. Ya'ni **lokal dizayn deltasi butun ilovaga tarqaladi**.
To'liq jadval va default javob — reja **§2, Z15**.
