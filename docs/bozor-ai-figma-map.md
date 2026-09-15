# Bozor AI — «Разместить объявление» wizard: implementation map

Source: 55 Figma frame readings. **Every wizard frame in the set is a RENT (`Тип объявления = В аренду`) variant.** No Sale wizard step was supplied — the only Sale-named node is the shared success screen `Sell Apartment 11` (4135:24924). Readings that failed are flagged in §7.

---

## 1. The flow in one picture

**7-step flow** (Квартира, Дом, Участок, Коммерческая, Гараж/парковка):

| # | Header (verbatim) | Body h1 | Primary action |
|---|---|---|---|
| 1/7 | Тип объявления | Тип объявления | Далее |
| 2/7 | Адрес | Адрес + sub «Укажите адрес или передвиньте метку на карте» | Далее |
| 3/7 | Параметры | Параметры (+ row «Все параметры» → full-sheet) | Далее |
| 4/7 | Цена | Цена | Далее |
| 5/7 | Описание | Описание | Далее |
| 6/7 | Контакты | Контакты + sub «Мы отправим SMS код-верификации на ваш номер телефона» | Далее (in-card «Отправить» sends SMS) |
| 7/7 | Условые размещения *(design typo, verbatim)* | Условые размещения | **Предпросмотр + Разместить** (only 2-up footer in the whole set) |

**6-step flow** (Другая нежилая / `Rent other commerce`) — identical minus **Параметры**, renumbered:

`1/6 Тип объявления → 2/6 Адрес → 3/6 Цена → 4/6 Описание → 5/6 Контакты → 6/6 Условые размещения`

Off-wizard screens hanging off the flow: **Адрес → map picker** (from step 2's pin button), **Параметры → «Все параметры»** full-screen sheet (from step 3), **success screen** (after Разместить).

---

## 2. The variant matrix

Frame-name prefix → variant. Step count comes from the header counter, not the frame name.

| Variant (Тип объявления / Вид / Тип недвижимости) | Figma frame name | Steps | 1 Тип | 2 Адрес | 3 Параметры | 4 Цена | 5 Описание | 6 Контакты | 7 Условия | «Все параметры» sheet |
|---|---|---|---|---|---|---|---|---|---|---|
| Аренда / Жилая / **Квартира** | `Rent apartment 8…14` | **7** | 1228-14458 | 1228:16777 | 1228:14716 | 1228-14762 | 1228:15457 | 1228-15767 | 1228:16104 | 1228-16162 |
| Аренда / Жилая / **Дом** | `Rent House 8…14` | **7** | 1228:14253 | 1228:14499 | 1228:16561 | 1228-14822 | 1228-15082 | 1228-15532 | 1228:15814 | 1228-16230 |
| Аренда / Жилая / **Участок** | `Rent field` | **7** | 1228:14294 | 1228:14544 | 1228-16622 | 1228-14882 | 1228:15157 | 1228-15579 | 1228-15872 | 1228-16297 |
| Аренда / Нежилая / **Коммерческая** | `Rent commerce` | **7** | 1228:14335 | 1228-14587 | 1228:16673 | 1228:14932 | 1228:15232 | 1228:15626 | 1228:15930 | 1228:16357 |
| Аренда / Нежилая / **Гараж/парковочное место** | `Rent garage/parking` | **7** | 1228-14376 | 1228:14630 | 1228-16724 | 1228-14982 | 1228-15307 | 1228-15673 | 1228-15988 | *(not in set)* |
| Аренда / Нежилая / **Другая нежилая** | `Rent other commerce` | **6** | 1228-14417 (1/6) | 1228-14673 (2/6) | — **absent** | 1228-15032 (3/6) | 1228:15382 (4/6) | 1228:15720 (5/6) | 1228:16046 (6/6) | — |
| **Продажа / любая** | — | ? | — | — | — | — | — | — | — | — |

Canvas section labels (TEXT nodes, not screens — use only for attribution): 1228:16434 «В аренду квартиру», 1228:16429 «В аренду дом», 1228-16430 «В аренду участку», 1228:16431 «В аренду коммерческую», 1228:16432 «В аренду гараж парковку», 1228-16433 «В аренду другая нежилая».

Note: on 1228-14417 (Другая нежилая, 1/6) the `Тип недвижимости` value still reads «Гараж/парковочное место» — a copy-paste leftover in the design, not a real value for that branch.

---

## 3. Where the form branches

### 3.1 The chain
`Тип объявления` → `Вид недвижимости` → `Тип недвижимости` → **selects the whole downstream variant, including the step count**. All three are pickers on step 1 (1228-14458 / 1228:14253 / 1228:14294 / 1228:14335 / 1228-14376 / 1228-14417).

| Вид недвижимости | Тип недвижимости options observed | Evidence |
|---|---|---|
| Жилая | Квартира, Дом, Участок | 1228-14458, 1228:14253, 1228:14294 |
| Нежилая | Коммерческая, Гараж/парковочное место, (Другая нежилая — implied by label 1228-16433) | 1228:14335, 1228-14376, 1228-16433 |

### 3.2 Step 2 «Адрес» — branches on Тип недвижимости

| Тип недвижимости | Fields shown | Evidence |
|---|---|---|
| Квартира | Регион, Район, **Адрес квартиры**(+pin), Ориентир*, **Номер квартиры**, **Подъезд***, **Этажей в доме**, **Этаж** (8 rows, frame h=1026) | 1228:16777 |
| Дом | Регион, Район, **Адрес**(+pin), Ориентир*, **Дом**, **Этажей в доме** (6 rows, h=862) | 1228:14499 |
| Участок / Коммерческая / Гараж / Другая нежилая | Регион, Район, Адрес(+pin), Ориентир* — 4 rows only | 1228:14544, 1228-14587, 1228:14630, 1228-14673 |

`*` = «(по желанию)».

### 3.3 Step 3 «Параметры» — branches on Тип недвижимости (biggest branch)

| Тип недвижимости | Short (in-step) fields | Full sheet adds | Evidence |
|---|---|---|---|
| Квартира | Количество комнат, Общая площадь (м²), [Все параметры] | Жилая площадь, Площадь кухни*, Высока потолков*, Санузел* (Совмещенный), Балкон*, Ремонт*, Вид из окон* (multi), Год постройки*, Лифт*, Грузовой лифт (toggle), Газ (toggle) + **Дополнительные**: Парковка, Высока потолков*, Материал*, Статус*, Название ГСК*, Площадь, Безопасность (гараж), Удобства (гараж), Безопасность*, Удобства*, Благоустройство двора*, Инфраструктура* | 1228:14716 / 1228-16162 |
| Дом | Площадь участка (сот.), Тип участка, Электричество, Водоснабжение, Газ, Канализация (4 toggles), Площадь дома (м2), Количество комнат, Тип дома, [Все параметры] | Поливная площадь*, Застроенная площадь*, Жилая площадь*, Высока потолков*, Санузел* (В доме), **Тип санузла** (Совмещенный), Ремонт* + **Дополнительные**: Безопасность*, Удобства*, Благоустройство двора*, Инфраструктура* | 1228:16561 / 1228-16230 |
| Участок | Площадь участка (сот.), Тип участка (Садовый), **Наличие пристройки** (toggle), Площадь пристройки (м2), Количество комнат, [Все параметры] | 4 utility toggles (Электричество, Водоснабжение, Газ, Канализация) + **Дополнительные**: Удобства*, Инфраструктура* | 1228-16622 / 1228-16297 |
| Коммерческая | Назначение, Тип здания, Площадь помещения (м²), **С участком** (toggle), Площадь участка (м2), [Все параметры] | Название бизнес-центра, Этажей в здании, **Все здание** (toggle), Этаж, Возможное назначение, Количество комнат, Вход, Ремонт, 4 utility toggles, Количество санузлов* + **Дополнительные**: Безопасность*, Удобства*, Инфраструктура* | 1228:16673 / 1228:16357 |
| Гараж/парковка | Тип (Парковка), Тип парковки (Наземная), Высота потолков (м), Материал*, Статус*, Название ГСК*, Площадь (м²), Безопасность (гараж), Удобства (гараж), [Все параметры] | *(sheet not supplied — the same field set appears as the garage sub-block of 1228-16162)* | 1228-16724 |
| Другая нежилая | **step does not exist** | — | 1228-14417/14673/15032 renumber 1/6→3/6 with no Параметры |

**Key evidence that these sets are conditional, not one shared sheet:** apartment sheet 1228-16162 has Лифт/Балкон/Вид из окон/Год постройки and NO plot fields; house sheet 1228-16230 has Площадь участка/Тип участка/Тип дома/Поливная/Застроенная and NO lift/balcony/garage block; the house sheet splits «Санузел» (В доме) from a new «Тип санузла» (Совмещенный) where the apartment sheet has one «Санузел» = Совмещенный.

### 3.4 Within-screen (toggle- and value-driven) branches

| Trigger | Reveals | Evidence |
|---|---|---|
| `Наличие пристройки` = ON | Площадь пристройки | 1228-16622, 1228-16297 |
| `С участком` = ON | Площадь участка | 1228:16673, 1228:16357 |
| `Тип здания` = Бизнес-центр | Название бизнес-центра | 1228:16357 |
| `Парковка` = Гараж | Материал, Статус, Название ГСК, Площадь, Безопасность (гараж), Удобства (гараж) | 1228-16162 |
| `Все здание` = ON | Этаж shown anyway — **contradictory**, see §7 | 1228:16357 |

### 3.5 Step 4 «Цена» — branches on Тип недвижимости

| Тип недвижимости | Fields | Evidence |
|---|---|---|
| Квартира, Дом | Арендная плата (UZS/мес), Торг уместен, **Стоимость в сутки (по желанию)** (UZS) | 1228-14762, 1228-14822 |
| Участок, Коммерческая, Гараж, Другая нежилая | Арендная плата (UZS/мес), Торг уместен — no per-day row | 1228-14882, 1228:14932, 1228-14982, 1228-15032 |

Also branches on **Тип объявления**: label is «Арендная плата» and the unit carries a period `/мес` because every supplied frame is rent. A Sale variant presumably reads «Стоимость» with plain `UZS` — **not in the set**.

### 3.6 Step 5 «Описание» — textarea label only

| Label shown | Variants | Evidence |
|---|---|---|
| «О квартире» | Квартира | 1228:15457 |
| «Об участке» | Дом, Участок, Коммерческая, Гараж, Другая нежилая | 1228-15082, 1228:15157, 1228:15232, 1228-15307, 1228:15382 |

«Об участке» on House/Commerce/Garage is almost certainly design copy-paste (see §7). Placeholder «Расскажите о недвижимости» is common everywhere.

### 3.7 Steps 6 and 7 — **no branching at all**
Контакты is layer-for-layer identical across Квартира/Дом/Участок/Коммерческая/Гараж/Другая (1228-15767 ≡ 1228-15532 ≡ 1228-15579 ≡ 1228:15626 ≡ 1228-15673 ≡ 1228:15720). Условые размещения likewise (1228:16104 ≡ 1228:15814 ≡ 1228-15872 ≡ 1228:15930 ≡ 1228-15988 ≡ 1228:16046).

---

## 4. Field catalogue

`*` after a label = the design renders a grey «(по желанию)» suffix → optional. Variants abbreviated: **A**=Квартира, **H**=Дом, **L**=Участок, **C**=Коммерческая, **G**=Гараж/парковка, **O**=Другая нежилая. "all" = A,H,L,C,G,O.

### Step 1
| Russian label | Control | Options / placeholder | Variants |
|---|---|---|---|
| Тип объявления | single-select picker | В аренду (Продажа implied, unseen) | all |
| Вид недвижимости | single-select picker | Жилая, Нежилая | all |
| Тип недвижимости | single-select picker | Квартира, Дом, Участок / Коммерческая, Гараж/парковочное место, (Другая нежилая) — filtered by Вид | all |

### Step 2
| Russian label | Control | Options / placeholder | Variants |
|---|---|---|---|
| Регион | single-select picker | «Область, город» | all |
| Район | single-select picker | «Район» | all |
| Адрес | text + red map-pin button | «Населенный пункт, улица, дом» | H,L,C,G,O |
| Адрес квартиры | text + red map-pin button | «Населенный пункт, улица, дом» | A |
| Ориентир* | text | «Торговый центр, метро, школа и т.д.» | all |
| Дом | numeric | 0 | H |
| Номер квартиры | numeric | 0 | A |
| Подъезд* | numeric | 0 | A |
| Этажей в доме | numeric | 0 | A,H |
| Этаж | numeric | 0 | A |

### Step 3 + «Все параметры» sheet
| Russian label | Control | Options / placeholder | Variants |
|---|---|---|---|
| Количество комнат | single-select | 4 | A,H,L,C |
| Общая площадь | numeric | suffix м² | A |
| Жилая площадь (A) / Жилая площадь* (H) | numeric | м² | A,H |
| Площадь кухни* | numeric | м² | A |
| Высока потолков* *(design spelling)* | numeric | м | A (×2: main + garage block), H |
| Высота потолков | numeric | м | G |
| Санузел* | single-select | A: Совмещенный · H: В доме | A,H |
| Тип санузла | single-select | Совмещенный | H |
| Количество санузлов* | single-select | 1 | C |
| Балкон* | single-select | 2 | A |
| Ремонт* | single-select | Косметический | A,H,C |
| Вид из окон* | **multi-select** | Парк, улица | A |
| Год постройки* | numeric | г | A |
| Лифт* | single-select | 2 | A |
| Грузовой лифт | toggle | OFF | A |
| Площадь участка | numeric | сот. (A/H/L) · м2 (C) | H,L,C |
| Тип участка | single-select | Индивидуальное жилищное строительство (H), Садовый (L) | H,L |
| Площадь дома | numeric | м2 | H |
| Тип дома | single-select | Отдельный дом | H |
| Поливная площадь* | numeric | м² | H |
| Застроенная площадь* | numeric | м² | H |
| Наличие пристройки | toggle | ON | L |
| Площадь пристройки | numeric | м2 — conditional on the toggle | L |
| Электричество / Водоснабжение / Газ / Канализация | 4 toggles | all ON | H,L,C · (Газ alone also on A) |
| Назначение | single-select | Для офиса | C |
| Возможное назначение | single-select | Помещение банка | C |
| Тип здания | single-select | Бизнес-центр | C |
| Название бизнес-центра | text | «Введите название» — conditional on Тип здания | C |
| Площадь помещения | numeric | м² | C |
| С участком | toggle | ON — reveals Площадь участка | C |
| Этажей в здании | numeric | 0 | C |
| Все здание | toggle | ON | C |
| Этаж | numeric | 0 | C |
| Вход | single-select | Отдельный | C |
| Тип | single-select | Парковка | G |
| Тип парковки | single-select | Наземная | G |
| Материал* | **multi-select** | Кирпичный | G, A(garage block) |
| Статус* | **multi-select** | Кооператив | G, A(garage block) |
| Название ГСК* | text | «Введите название» | G, A(garage block) |
| Площадь | numeric | м² | G, A(garage block) |
| Безопасность (гараж) | **multi-select** | Видеонаблюдение | G, A(garage block) |
| Удобства (гараж) | **multi-select** | Автоматические ворота | G, A(garage block) |
| Парковка | single-select | Гараж — gates the garage sub-block | A |
| Безопасность* | **multi-select** | Домофон, Закрытая территория | A,H,C |
| Удобства* | **multi-select** | Интернет | A,H,L,C |
| Благоустройство двора* | **multi-select** | Детская площадка | A,H |
| Инфраструктура* | **multi-select** | Школа, Детский сад **и еще 3** (overflow pattern) | A,H,L,C |
| Все параметры | navigation row (blue, right chevron) | opens the full sheet | A,H,L,C,G |
| Готово | header text action (right side of sheet header) | closes/commits the sheet | sheet only |

### Step 4
| Russian label | Control | Options / placeholder | Variants |
|---|---|---|---|
| Арендная плата | numeric + inline currency/period selector | placeholder «0»; selector «UZS/мес» + chevron-down, divider inside the same field | all |
| Торг уместен | toggle | ON | all |
| Стоимость в сутки* | numeric + inline currency selector «UZS» | «0» | A,H |

### Step 5
| Russian label | Control | Options / placeholder | Variants |
|---|---|---|---|
| О квартире / Об участке | textarea (~132dp) | «Расскажите о недвижимости» | A / rest |
| Добавить планировку | upload row, floor-plan icon | empty state, no previews shown | all |
| Добавить фото | upload row, doc+ icon | empty state | all |
| Добавить 360 фото | upload row, 360 icon | empty state | all |
| Видео с YouTube* | text | «Ссылка на видео с YouTube» | all |

### Step 6
| Russian label | Control | Options / placeholder | Variants |
|---|---|---|---|
| Имя | text | «Введите имя» | all |
| Номер телефона | phone text | prefilled «+998» | all (repeatable) |
| Электронная почта* | email text | «example@nomakler.uz» | all |
| Добавить номер телефона | text link + «+» icon | appends a phone row | all |
| Отправить | primary button **inside the card** | sends the SMS verification code | all |
| *(caption)* Мы отправим SMS код-верификации на ваш номер телефона | static text | — | all |

### Step 7
| Russian label | Control | Options / placeholder | Variants |
|---|---|---|---|
| Стандартное объявление | radio (selected) + trailing ⓘ | own 54dp card | all |
| Отправить в “Топ” | radio + rocket icon + trailing ⓘ | own 54dp card; typographic quotes | all |
| Я согласен с условиями объявления | checkbox (checked) | «условиями объявления» is a blue link | all |
| Предпросмотр | secondary button (half width) | — | all |
| Разместить | primary button (half width) | submit | all |

### Map sub-screen
| Russian label | Control | Options | Node |
|---|---|---|---|
| *(no label)* address search | text + trailing spinner in loading state | «Населенный пункт, улица, дом» | 1228:16491 |
| Адрес | full-bleed map, draggable house pin | Tashkent default | 1228:16435, 1228:16491 |
| — | 3 round 40dp map controls | locate, zoom +, zoom − | both |
| Далее | primary button floating over the map | — | both |

---

## 5. Screens that are not wizard steps

| Node | What it is | Notes |
|---|---|---|
| 1228:16435 | **Map picker**, header «Адрес», no step counter, no bottom bar | full-bleed map + pin + locate/±, floating «Далее» |
| 1228:16491 | **Map picker — loading state** («Map loader») | search field with iOS spinner instead of the trailing icon; same map + «Далее» |
| 1228-16162 | **«Все параметры» sheet — Квартира** (375×2264 scroll) | header: back + «Параметры» + blue «Готово»; sections Параметры / Дополнительные |
| 1228-16230 | **«Все параметры» — Дом** (375×1778) | same chrome |
| 1228-16297 | **«Все параметры» — Участок** (375×1002) | same chrome |
| 1228:16357 | **«Все параметры» — Коммерческая** (375×1784) | same chrome |
| 4135:24924 | **Success screen** (`Sell Apartment 11`) | no header, no back, no step counter. Texts verbatim: «Объявление успешно отправлен на модерацию» (line break after «успешно»; grammatical error in the design) and «Добавить ещё один ». Buttons: primary «Перейти к публикацию» (#1A73EB, r6), secondary «Добавить ещё один» (#E3EEFC, r8). Green check 124×124 raster `80036-done 2`. Shared across variants despite the Sale-ish frame name. |
| 4129:24923 | Designer annotation frame 66×46 containing the word **«lottie»** | means the green check should be a Lottie animation, not a static PNG |
| 1228:16434 / 16429 / 16430 / 16431 / 16432 / 16433 | Canvas section labels (TEXT nodes) | nothing to implement |

**Not present anywhere in the set:** the OTP/code-entry screen (step 6 shows only the pre-send state), the «Предпросмотр» preview screen, the ⓘ tariff-explainer tooltip/sheet, the picker bottom-sheets themselves (only their closed rows), any upload-filled state, any error/empty/validation state, the terms-of-listing document screen, and every Sale wizard step.

---

## 6. Implementation notes for this codebase

Feature-first, no bloc → put it at `lib/features/bozor/` with `models/`, `screens/`, `widgets/`, state held in a `StatefulWidget` wizard controller (mirror `lib/features/services/screens/ai_*`, which is the same shape). **Drop the Bottom bar instance from every frame** — the footer is `WizardNavBar` only.

### Control → widget map

| Figma control | Existing widget / file | Action |
|---|---|---|
| Header «n/7 - Title» + back chevron | `ServiceAppBar(title, subtitle, onBack)` — `lib/features/services/widgets/service_app_bar.dart` | reuse. Do **not** render "3/7 -" in the title; put the step title in `title` and let `StepProgressBar` carry progress (or pass "3/7" as `subtitle`). |
| Step progress | `StepProgressBar(count, activeIndex)` — `.../widgets/step_progress_bar.dart` | reuse. **`count` must be variant-driven: 7 or 6.** |
| Bottom «Далее» | `WizardNavBar(onBack, onContinue, continueLabel, continueEnabled)` — `.../widgets/wizard_nav_bar.dart` (wraps `ListingCtaButton`) | reuse; `continueLabel = tr(l,'bozor.next')` |
| Standalone primary («Отправить», map «Далее», success CTAs) | `ListingCtaButton(label, onTap, enabled)` — `lib/features/market/widgets/listing_cta_button.dart` (56dp, r999, splashGreen) | reuse |
| Step 7 two-up Предпросмотр + Разместить | `WizardNavBar` already renders a 50/50 secondary-left / primary-right row | reuse, but the left slot is semantically "back" — either add an `onSecondary`/`secondaryLabel` param or compose the row manually. **Flag: small API change.** |
| Text / numeric / textarea fields, unit suffix (м², сот., м, г) | `WizardField(label, controller, placeholder, suffix, maxLines, numericOnly, allowDecimal, phoneFormat, required, errorText)` — `.../widgets/wizard_field.dart` (r14) | reuse; `maxLines: 5` for the description, `suffix:'м²'`, `phoneFormat:true` for +998 |
| Single-select row («Регион», «Тип участка», «Количество комнат»…) | no field widget; the **pattern** exists: `showRoomPickerSheet` in `.../widgets/room_picker_sheet.dart` = `showModalBottomSheet` + `ChoiceTile` list + `ListingCtaButton` | **NEW**: `SelectField` (closed row, same visual as `WizardField`) + generic `showOptionPickerSheet<T>({title, options, selected})` built from `ChoiceTile` |
| Radio rows step 7 | `ChoiceTile(label, selected, onTap)` — r16, splashGreen border when selected | reuse; **NEW**: needs a trailing-widget slot for the ⓘ and the rocket, or wrap it |
| Toggle row («Газ», «Торг уместен», «С участком») | exists only as **private** `_ToggleRow` at `lib/features/services/screens/calculator/dynamic_form_screen.dart:691` (r16 card + `Switch` with `activeThumbColor: splashGreen`) | **EXTRACT** to `lib/features/services/widgets/toggle_row.dart` and reuse in both places |
| Multi-select («Безопасность», «Инфраструктура» with «и еще N») | nothing. `dynamic_form_screen._choiceGroup(multi:true)` renders inline chips, not a closed summary row | **NEW**: `MultiSelectField` (closed row showing `"A, B и еще N"`) + a multi-pick sheet (checkbox variant of `ChoiceTile`) |
| Price field with inline currency/period selector | `WizardField.suffix` is `String` only | **NEW**: `PriceField` — numeric input + divider + tappable `UZS/мес` chip opening a picker. Alternatively extend `WizardField` with a `suffixWidget`. |
| Map picker screen + pin + locate/zoom | `MapLocationPickerScreen(initialPoint,title,subtitle)` (flutter_map + OSM + geolocator) and `MapZoomControls` — `.../screens/map_location_picker_screen.dart`, `.../widgets/map_zoom_controls.dart` | reuse for 1228:16435. Its confirm button is already `ListingCtaButton`. **NEW**: address search field on top + the spinner/geocoding state (1228:16491) — no geocoding exists today. |
| «Адрес» row with the red pin button | `LocationPickerField(label,value,onChanged,required)` — `.../widgets/location_picker_field.dart` | reuse, restyle trailing icon |
| «Добавить фото» / «Добавить планировку» upload rows | `image_picker` is a dependency; upload UI exists only as **private** `_UploadCard` / `_UploadTile` / `_AddTile` / `_EmptyDropZone` in `lib/features/services/screens/ai_intake_screen.dart`; `FilePreviewGallery` is public | **EXTRACT** the upload tile family into `widgets/upload_row.dart`, or rebuild as a 48dp icon+label row per the design |
| «Добавить 360 фото» | nothing | **NEW** — no 360 capture/viewer exists (`Listing3DViewer` is a GLB model viewer, different thing). Decide: pick from gallery vs. capture. |
| Terms checkbox + blue link | `TermsConsent(value, onChanged)` — `.../widgets/terms_consent.dart` (already fetches `GET /legal/terms?lang=` and renders HTML in a sheet) | reuse; swap the label string |
| ⓘ tariff explainer | nothing | **NEW** — info icon → small bottom sheet |
| «Все параметры» navigation row | nothing (`ServiceCard`/`ServiceGroupCard` are visually different) | **NEW**: a one-line card with trailing chevron |
| Repeatable phone rows («Добавить номер телефона») | nothing | **NEW**: list of `WizardField(phoneFormat:true)` + an add-link |
| Success screen + Lottie check | nothing; **`lottie` is NOT in pubspec.yaml** | **NEW** screen; either add the `lottie` dep or ship the static check |
| Colors | `ColorTokens.x(context)` — `lib/theme/color_tokens.dart` (`scaffoldBg`, `cardBg`, `inputFill`, `primaryText`, `secondaryText`, `tertiaryText`, `outline`…) | map Figma blue `#1A73EB` → `AppColors.splashGreen`; light-blue field fill → `ColorTokens.inputFill`; grey secondary button → `ColorTokens` greys |
| Fonts | MTSCompact w700 headings/buttons, MTSText body — already the convention in every widget above | — |
| Strings | `tr(locale, 'key')` — `lib/core/i18n/app_translations.dart` (uz/ru/en) | Figma is RU-only; **uz + en translations must be authored**, ~120 keys |

### Model shape

The branching set is exactly the control vocabulary of the existing schema engine: `FormFieldType { text, textarea, number, integer, toggle, singleChoice, multiChoice, date, rooms, note }` — `lib/features/services/models/dynamic_form_schema.dart`, rendered by `dynamic_form_screen.dart`. **Strong recommendation:** model step 3 + the «Все параметры» sheet as a *client-side* schema keyed by `PropertyType`, with a `visibleWhen` predicate for the toggle-driven rows (Наличие пристройки, С участком, Тип здания=Бизнес-центр, Парковка=Гараж), and render it with a Bozor-specific renderer copied from `dynamic_form_screen`. That collapses five hand-written parameter screens plus five sheets into one renderer plus five data tables.

Suggested Dart skeleton:

```
enum DealType { rent, sale }                    // sale unverified
enum PropertyKind { residential, nonResidential }
enum PropertyType { apartment, house, land, commercial, garage, otherNonResidential }

class BozorDraft {
  DealType deal; PropertyKind kind; PropertyType type;   // step 1
  AddressDraft address;                                   // step 2 (+ apartment/house extras)
  Map<String, Object?> params;                            // step 3 + sheet, schema-driven
  PriceDraft price;                                       // step 4
  DescriptionDraft description;                           // step 5
  ContactsDraft contacts;                                 // step 6 (phones: List<String>)
  PlacementTier tier; bool termsAccepted;                 // step 7
}

int stepCount(PropertyType t) =>
    t == PropertyType.otherNonResidential ? 6 : 7;
```

Drive the step list from `stepCount` / a `List<WizardStep>` builder, not from a hard-coded 7, so the 6-step branch is not a special case sprinkled through the UI.

---

## 7. Open questions

1. **No Sale wizard was supplied.** Only the success frame is Sale-named (`Sell Apartment 11`, 4135:24924). Does Продажа have the same steps? Step 4 must change at minimum («Арендная плата»→«Стоимость», `UZS/мес`→`UZS`, and «Стоимость в сутки» presumably disappears). Ask for the Sale frames before finalising the price model.
2. **«Другая нежилая» has no Параметры step (6/6).** Intentional, or an unfinished branch? If it later gains parameters the step count becomes 7 and the whole numbering shifts.
3. **Гараж/парковка has no «Все параметры» sheet in the set,** yet its 3/7 shows the full garage field list plus an «Все параметры» row. What does that row open?
4. **«Об участке»** is the description label on House, Commercial and Garage variants (1228-15082, 1228:15232, 1228-15307, 1228:15382). Copy-paste bug, or intended? Proposed per-type labels: О квартире / О доме / Об участке / О помещении / О гараже — needs sign-off.
5. **Design typos — reproduce or fix?** «Условые размещения» (should be «Условия размещения») in the header *and* the body h1 on all six 7/7-6/6 frames; «Высока потолков» (should be «Высота») on 1228-16162 and 1228-16230, while 1228-16724 has the correct «Высота потолков»; the success text «Объявление успешно отправлен на модерацию» and the button «Перейти к публикацию» (should be «к публикации»). Because everything goes through `tr()` I would fix them, but that changes the visual diff against Figma.
6. **Unit inconsistency:** the same concept is written `м²` in some fields and `м2` in others (e.g. «Площадь помещения» м² vs «Площадь участка» м2 on 1228:16673). Standardise on `м²`?
7. **Commercial: `Все здание` = ON and `Этаж` both shown** (1228:16357). Should `Этаж` hide when the whole building is rented?
8. **Step 6 SMS flow is undefined.** There is an in-card «Отправить» *and* a bottom «Далее», but no OTP-entry frame anywhere. Where does the code get typed — inline field, sheet, or separate screen? Can «Далее» proceed unverified?
9. **«Предпросмотр» has no screen.** Full listing-detail preview (reuse `listing_detail_screen.dart`?) or a modal?
10. **ⓘ tariff explainers have no content.** Need the copy for «Стандартное объявление» and «Отправить в “Топ”», plus pricing and whether Топ triggers a payment flow (`market_payment_sheet.dart` exists).
11. **Picker option lists are unknown.** Every select shows only one filled value. Full option sets are needed for: Тип объявления, Вид/Тип недвижимости, Регион, Район, Тип участка, Тип дома, Санузел, Тип санузла, Балкон, Ремонт, Лифт, Вид из окон, Парковка, Материал, Статус, Назначение, Возможное назначение, Тип здания, Вход, Тип, Тип парковки, Безопасность, Удобства, Благоустройство двора, Инфраструктура, currency/period. Backend dictionary endpoint or hard-coded?
12. **Multi-select overflow rule.** «Школа, Детский сад и еще 3» — is the visible count fixed at 2, or width-driven?
13. **Upload limits unspecified:** max photos, accepted formats, whether «Планировка» and «360 фото» are single- or multi-file, and whether 360 means an equirectangular image or a capture flow. No filled/preview state exists in the design.
14. **Map:** does the pin drag or does the map move under a fixed pin? Reverse geocoding is required by the loading frame (1228:16491) but no geocoding service exists in the app today (flutter_map + OSM tiles only). Which provider?
15. **Success screen:** «Перейти к публикацию» — go where, the created listing's detail page? And `lottie` is not a dependency; add it or use the static asset?
16. **Reading gaps to be honest about:** screenshots for 1228:16429 and 1228:16431 were refused by a Figma MCP rate limit (metadata confirms both are canvas TEXT labels, so nothing is lost); `get_metadata` for the success frame 4135:24924 repeatedly failed with an MCP transport error, so its strings/node ids come from `get_design_context` + screenshot only; several field labels (description, price, contacts) exist in Figma as component instance overrides and were read from renders, not metadata.