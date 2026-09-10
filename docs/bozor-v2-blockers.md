# Bozor AI v2 — bloklovchi so'rovlar (M0-2)

> **Bu hujjat nima?** Rejaning [`docs/bozor-v2-plan.md`](./bozor-v2-plan.md) **M0-2** qadami
> «uchta bloklovchi so'rov yuborilsin» deydi. Bu yerda **yuboriladigan aynan matnlar** turadi —
> nusxa ko'chirib, o'zgartirmasdan jo'natish uchun.
>
> **Muhim.** Hujjatni yozgan agentda tashqi kanal (Telegram/pochta/Figma comment) **yo'q** —
> so'rovlarni **odam** yuboradi. Shuning uchun har bir so'rov ` ``` ` bloki ichida, murojaat va
> imzogacha to'liq yozilgan.
>
> **Tillar:** so'rov matnlari **ruscha** (dizayner / mijoz / operator bilan muloqot tili),
> hujjatning tushuntirish qismlari o'zbekcha. SMS shabloni taklifi — uz/ru/en.
>
> **Bugungi sana: 2026-09-10.** Quyidagi jadvalning «yuborilgan» va «javob» ustunlari
> **ataylab bo'sh** — ularni so'rovni yuborgan odam to'ldiradi.

---

## 1. Holat jadvali

| № | So'rov | Kimga | Qaysi qadamni bloklaydi | Yuborilgan sana | Javob sanasi | Javob |
|---|---|---|---|---|---|---|
| **A** | 7 o'qilmagan Figma freymi (`1414-21717`, `1414-21438`, `1414-21488`, `1414-21563`, `1414-21605`, `293-12538`, `293-12539`) | Dizayner | **M3-18** (`wizardSteps` matritsasi + testlari), **M3-19** («Другая нежилая» varianti). ⚠️ **ZAXIRA yo'l** — asosiy yo'l: ertaga Figma kvotasi tiklangach o'zimiz o'qiymiz | | | |
| **B** | 4 ta option ro'yxatining to'liq qiymatlari: `sale_type`, `ownership_years`, `owners_count`, `registered_count`. ➕ Yo'l-yo'lakay: «Сделка» qadami ijarada ham bormi (reja §7 №15) | Mijoz (dizayner nusxada) | **M2-15** (ustun turi) + **M2-16** (`DealIn` + OPTION_LISTS). Kodlar prod e'lonlarida **abadiy qoladi**. Qo'shimcha savol — **M3-18/M3-19** | | | |
| **C** | «E'lon kontaktini tasdiqlash» uchun yangi SMS shabloni (5 xonali kod) | Operator — PlayMobile | **M4-30** ning **prod'ga chiqishi** (kodning o'zi emas). Ishlab chiqish `DEBUG_OTP_CODE` / demo raqam bilan davom etadi | | | |
| **D** | 3 ta mahsulot qarori: lenta kirish nuqtasi (§7 №7), sevimlilar (§7 №8), e'lon sarlavhasi (Z8) | Mahsulot | **M1-12b** (kirish nuqtasi — ⛔ qattiq blok), **M4-24** (sarlavha — default bor), sevimlilar (rejaga kirmagan) | | | |

### Bloklarning qattiqligi

| So'rov | Javob kelmasa nima bo'ladi |
|---|---|
| **A** | Zaxira yo'l — 2026-09-11 dan Figma MCP kvotasi tiklanadi va freymlarni **o'zimiz o'qiymiz**. Ya'ni A javob kelmasa ham M3 boshlanadi; dizayner javobi faqat **tezlashtiradi** va §0.5 («freym nomlari yolg'on gapiradi») xatarini kamaytiradi |
| **B** | ⛔ **M2-16 boshlanmaydi.** M2-15 esa `String(8)` bilan boshlanadi (§11: `String` ham sof sonni, ham `6_plus` kabi kodni ushlaydi). **5 ish kuni** ichida javob kelmasa — taxminiy to'plam bilan davom etamiz va `docs/` da «o'zgartirish qimmat» ogohlantirishi qoldiramiz |
| **C** | Kod yoziladi va testdan o'tadi, lekin **prod'da SMS yetkazilmaydi** (operator tasdiqlanmagan matnni qabul qiladi-yu yubormaydi — `app/integrations/sms_provider.py:10-16` izohi). Reliz `DEBUG_OTP_CODE` bilan chiqmaydi |
| **D** | №7 (kirish nuqtasi) — ⛔ **M1-12b bloklanadi**, chunki ekran qayerdan ochilishini bilmasdan yozib bo'lmaydi. №8 (sevimlilar) — default «hozircha yo'q». Z8 (sarlavha) — default (a), maydon qoladi |

---

## 2. So'rov A — dizaynerga: 7 o'qilmagan freym

### Nega kerak

Xarita §12 da 89 freymdan **82 tasi** o'qilgan, **7 tasi** yo'q (83–89-qatorlar). Ular `1414-21xxx`
diapazonida, ya'ni **«Другая нежилая»** bo'limiga tegishli bo'lishi ehtimoli yuqori
(`1414:21663` — «Продать другая нежилая» kanvas sarlavhasi, `1414:21355` — o'sha oqimning
**1/7** freymi).

Agar ular **qo'shimcha qadamlar** bo'lib chiqsa, «Другая нежилая» 7 qadamli emas, ko'proq bo'ladi va
xaritaning §0.2 jadvali (variant bo'yicha qadamlar soni) yolg'on chiqadi. Undan esa ikkita qadam
to'g'ridan-to'g'ri oziqlanadi:

- **M3-18** — `wizardSteps` ni `(DealType × PropertyType)` juftligiga o'tkazish va uning testlari;
- **M3-19** — 4/8 «Сделка» ekrani, ya'ni «Другая нежилая» da bu qadam bor-yo'qligi.

Ya'ni javob kechikkani sari M3-18/19 **qayta yozilish** xatari saqlanadi.

### ⚠️ Bu so'rov ZAXIRA yo'l, asosiy emas

2026-09-10 da freymlarni o'qishga qayta urinildi — Figma MCP serveri
`Rate limit exceeded, please try again tomorrow` qaytardi. Kvota **kunlik**, ya'ni:

| Yo'l | Kim bajaradi | Qachon | Nima beradi |
|---|---|---|---|
| **1 — asosiy** | O'zimiz (Figma MCP) | **2026-09-11 dan** kvota tiklangach | Freymlarning **haqiqiy mazmuni**: header'dagi «N/7» matni, maydonlar ro'yxati. Xarita §12 (83–89) va §0.2 shu bilan yopiladi |
| **2 — zaxira** | Dizayner (quyidagi so'rov) | Javob kelganda | Bir gapda tasdiq: «bular qo'shimcha qadam / yordamchi holat / eski avlod». Bizning o'qishimizni **tekshiradi** va §0.5 xatarini (freym nomi ≠ mazmuni) kamaytiradi |

**Amaliy qoida:** 1-yo'l ishlagach ham 2-yo'l javobi **baribir kerak** — chunki xarita §0.5 ga
ko'ra freym nomiga tayanib bo'lmaydi va node ID diapazoni bo'yicha qilingan xulosalar `(?)`
bilan belgilangan. Ya'ni ikkala yo'l bir-birini almashtirmaydi, **tasdiqlaydi**.

Shuning uchun so'rov matni ataylab **«tasdiqlash» shaklida** yozilgan — dizaynerdan freymlarni
qayta eksport qilishni **talab qilmaydi**, faqat bir necha savolga javob so'raydi. Bu javobni
tezlashtiradi.

### Yuboriladigan matn

```
Здравствуйте!

Мы закончили разбор макетов потока «Продажа» (89 фреймов) и начинаем разработку.
Из 89 фреймов мы прочитали 82. Остались 7, до которых мы не добрались (упёрлись
в дневной лимит Figma), и они как раз в той части, от которой зависит структура
шагов визарда:

1. 1414-21717
2. 1414-21438
3. 1414-21488
4. 1414-21563
5. 1414-21605
6. 293-12538
7. 293-12539

Почему это для нас блокер. По номерам нод первые пять относятся к разделу
«Продать другая нежилая» (заголовок раздела — 1414:21663, а фрейм 1414:21355
имеет в хедере «1/7»). То есть у варианта «Другая нежилая» шагов не 8, а 7.
Мы так и запрограммировали: для «Другая нежилая» шаг «Параметры» пропускается.

Но если эти 5 фреймов — это ДОПОЛНИТЕЛЬНЫЕ шаги того же потока, значит шагов
там больше семи, и нам придётся переписать логику нумерации шагов и её тесты.
Поэтому просим подтвердить это до того, как мы напишем код.

Вопросы (можно отвечать коротко, по номерам):

1) 1414-21717, 1414-21438, 1414-21488, 1414-21563, 1414-21605 — это
   а) дополнительные ШАГИ визарда «Другая нежилая» (тогда напишите, пожалуйста,
      что в хедере каждого: «3/7», «4/7» и т.д.),
   б) состояния/поповеры уже известных шагов (пикер, ошибка, загрузка),
   в) или старая версия макетов, которую реализовывать не нужно?

2) 293-12538 и 293-12539 — они из блока «Продать квартиру» (293-125xx).
   Это отдельные экраны или вспомогательные фрагменты (например, состояние
   «номер подтверждён» / модалка кода)?

3) Подтвердите, пожалуйста, итоговое количество шагов для «Другая нежилая»
   в продаже: 7? Полный список шагов, как мы его поняли:
   1/7 Тип объявления → 2/7 Адрес → 3/7 Сделка → 4/7 Цена →
   5/7 Описание → 6/7 Контакты → 7/7 Условия размещения
   (то есть шага «Параметры» у этого варианта нет). Верно?

4) Отдельно: есть ли ещё фреймы потока «Продажа», которые НЕ входят в эти 89?
   Нам важно знать, что мы видим весь поток целиком.

Ещё одна просьба на будущее: имена фреймов в файле не совпадают с содержимым
(например, «Sell House 1» — это на самом деле «Участок», а «Sell Apartment 8» —
шаг «Сделка»). Мы ориентируемся только на текст в хедере фрейма («N/8 — Название»)
и на заголовок раздела на канвасе. Если это можно поправить в именах слоёв —
разбор следующих потоков пойдёт заметно быстрее и без наших догадок.

Спасибо!
```

> **Yuborilgach** 1-bo'limdagi jadvalning «yuborilgan sana» ustuniga sanani yozing.
> Javob kelmasa ham 2026-09-11 dan asosiy yo'l (o'zimiz o'qish) ishga tushadi — bu so'rov
> M3 ni **to'xtatib turmaydi**.

---

## 3. So'rov B — mijoz/dizaynerga: 4 option ro'yxatining to'liq qiymatlari

### Nega shoshilinch

Bu **eng qattiq** blok. Sabab texnik, mahsulot emas:

1. 4/8 «Сделка» qadamining to'rt maydoni (`sale_type`, `ownership_years`, `owners_count`,
   `registered_count`) `params` JSON'iga **sig'maydi** — `listing_param_schema.validate()`
   faqat `property_type` ni biladi, `deal_type` ni ko'rmaydi (xarita §11). Demak ular
   `bozor_listings` da **alohida ustun** bo'ladi.
2. Ustunlarda **kod** saqlanadi (`free_sale`, `from_3_to_5`, `6_plus` kabi), yorliq emas.
   Foydalanuvchi e'lon bergan zahoti kod bazaga tushadi va **abadiy qoladi**.
3. Kodni keyin o'zgartirish = **ma'lumot migratsiyasi** (`UPDATE … SET sale_type = …`) va
   ehtimol ustun turini o'zgartirish. Bizda esa alembic grafi **3 head bilan buzuq**
   (`davreestr_logs_01`, `f0a1b2c3d4e5`, `legal_docs_01`) — jadval faqat
   `scripts/ensure_bozor_listings.py` orqali boshqariladi. Ya'ni prod'da
   `ALTER COLUMN … TYPE` **qimmat va xatarli**.

Shu uchbirlik natijasi: **noto'g'ri ro'yxat = prod'da abadiy noto'g'ri ma'lumot.**

Dizaynda har bir maydonning faqat **bitta** qiymati ko'ringan (picker yopiq holatda chizilgan),
qolgan variantlar hech qayerda yo'q:

| Maydon (RU) | Node ID | Dizaynda KO'RINGAN yagona qiymat | BIZNING taxminiy ro'yxat (xarita §10) | Majburiylik (dizayn) |
|---|---|---|---|---|
| `Тип продажи` | `1296:22239`, `1297:23777`, `1297:25522` | `Свободная продажа` | ⚠️(?) `free_sale`, `alternative`, `mortgage_sale`, `installment`, `exchange` | ixtiyoriy «(по желанию)» |
| `Лет в собственности` | ayni freymlar | `от 3 до 5` | ⚠️(?) `under_3`, `from_3_to_5`, `over_5` | ixtiyoriy |
| `Собственники` | ayni freymlar | `1` | ⚠️(?) `1`, `2`, `3`, `4`, `5`, `6_plus` | ✅ **yagona majburiy maydon** |
| `Прописано` | `1296:22239` (Дом `1297:23248` va Гараж `1414:20323` da YO'Q) | `0` | ⚠️(?) `0`, `1`, `2`, `3`, `4`, `5`, `6_plus` | ixtiyoriy |

⚠️ **`owners_count` uchun `rooms_count` ro'yxatini qayta ishlatmaymiz** — «6+ mulkdor» xonalar
ro'yxatidan kelib chiqsa mantiqsiz bo'ladi va ikkala ro'yxat bir-biriga yopishib qoladi.

### Ustun turi ham shu javobga bog'liq

M2-15 `owners_count` va `registered_count` ni **`String(8)`** qilib yaratadi,
`SmallInteger` emas. Sabab: agar javobda `6_plus` kabi **son bo'lmagan** kod chiqsa,
`SMALLINT` ustunni prod'da o'zgartirish kerak bo'ladi. `String(8)` ikkala holatni ham ushlaydi:
`"3"` ham, `"6_plus"` ham. Shu tanlov blokni **yumshatadi** — ustunni hozir yaratib,
qiymatlarni javob kelgach cheklaymiz. Lekin `DealIn` sxemasi (M2-16) baribir bloklangan.

### So'rov matnining shakli

Savollar shunday tuzilgan: **mijoz faqat «ha/yo'q» yoki tayyor ro'yxat qaytarsa yetarli.**
Har bir maydonga bizning taklifimiz to'liq yozilgan — mijoz uni tasdiqlashi yoki
qatorlarni qo'shib/olib tashlashi kifoya. Bo'sh sahifaga ro'yxat yozishni **so'ramaymiz**.

Matnning **5-savoli** — reja §7 №15 («Сделка» qadami ijara oqimida ham bormi). U alohida
so'rov qilinmadi, chunki **qabul qiluvchi ayni o'sha odam** va savol ayni o'sha qadam haqida:
ikki xabar yuborsak javob ikki barobar kechikadi. Uning ta'siri boshqa —
M3-18 (`wizardSteps` matritsasi) va M3-19, va unda **default javob bor** («faqat sotuvda»),
shuning uchun u B ni bloklovchi qilmaydi.

### Yuboriladigan matn

```
Здравствуйте!

По потоку «Продажа» нам нужно закрыть один технический вопрос, и он срочный.

На шаге «4/8 Сделка» четыре поля-селекта. В макетах у каждого видно только ОДНО
значение (пикер нарисован закрытым), а остальные варианты нигде не показаны:

  • Тип продажи          — видно «Свободная продажа»
  • Лет в собственности  — видно «от 3 до 5»
  • Собственники         — видно «1»   (единственное обязательное поле)
  • Прописано            — видно «0»   (есть только у квартир; у дома и гаража нет)

Почему это срочно и почему нельзя «доделать потом». В базе мы храним не текст,
а КОД значения (например free_sale, from_3_to_5, 6_plus). Как только первый
пользователь опубликует объявление, эти коды попадают в базу и остаются там
навсегда. Изменить их позже — это миграция данных на проде, а наша схема
объявлений сейчас управляется скриптом, а не миграциями (в графе миграций три
незакрытых ветки). То есть исправление обойдётся заметно дороже, чем сразу
согласовать список. Поэтому мы не начинаем этот шаг, пока не получим ответ.

Ниже — наш вариант списков. Просьба: НЕ писать список с нуля, а просто
подтвердить или поправить (вычеркнуть лишнее / дописать своё).

--- 1. Тип продажи ---------------------------------------------------------
Наш вариант (4 или 5 пунктов):
   1. Свободная продажа
   2. Альтернативная продажа (взамен покупается другое жильё)
   3. Продажа в ипотеку
   4. Продажа в рассрочку
   5. Обмен
Вопрос: этот список подходит? Если нет — какие пункты убрать/добавить?

--- 2. Лет в собственности --------------------------------------------------
Наш вариант (3 пункта):
   1. до 3 лет
   2. от 3 до 5 лет
   3. более 5 лет
Вопросы:
   а) Три диапазона достаточно, или нужен ещё один (например «до 1 года»)?
   б) Это именно выбор из списка, а не ввод числа лет цифрами? (В макете
      у поля стоит иконка пикера, поэтому мы считаем, что список. Да/нет.)

--- 3. Собственники ---------------------------------------------------------
Наш вариант: 1, 2, 3, 4, 5, 6 и более
Вопросы:
   а) Такой диапазон подходит? Да/нет.
   б) Последний пункт — «6 и более» или нужно продолжать числами до 10?
      (Нам это важно: от ответа зависит тип колонки в базе.)

--- 4. Прописано ------------------------------------------------------------
Наш вариант: 0, 1, 2, 3, 4, 5, 6 и более   (начинается с нуля)
Вопросы:
   а) Такой диапазон подходит? Да/нет.
   б) Подтвердите, что это поле показывается ТОЛЬКО для «Квартира» и
      «Квартира в новостройке», а для дома, участка, коммерческой и гаража
      его нет. (В макетах именно так: 1297:23248 и 1414:20323 — без него.) Да/нет.

--- 5. И один вопрос про сам шаг «Сделка» -----------------------------------
Шаг «Сделка» есть только при ПРОДАЖЕ, а при сдаче в аренду его нет — верно?
Да/нет. (В 55 фреймах потока «Аренда» такого шага не было, и поля вроде
«Тип продажи» для аренды не имеют смысла, поэтому мы так и заложили. Если
ответ «нет, в аренде тоже нужен» — нам придётся переписать нумерацию шагов
и её тесты, поэтому лучше узнать это сейчас.)

Если по каким-то пунктам решения пока нет — напишите, пожалуйста, по каким
именно. Мы возьмём свой вариант, отметим его в документации как
предварительный и продолжим, но тогда возможное изменение позже будет
стоить дороже.

Спасибо!
```

---

## 4. So'rov C — operatorga (PlayMobile): SMS shabloni

### Nega kerak

7/8 «Контакты» qadamida e'lon kontakt telefonini SMS bilan tasdiqlash bor. Hozir bu **UI stub**:
`lib/features/bozor/screens/bozor_contacts_step_screen.dart` da `_sendCode()`/`_verifyCode()`
hech qanday so'rov yubormaydi. M4-30 ikkita yangi endpoint qo'shadi
(`POST /listings/contact/send-otp`, `/verify-otp`) — bular **token qaytarmaydi**, ya'ni
`/auth/verify-otp` dan farq qiladi (u foydalanuvchini qayta login qiladi).

Yangi shablon **shart**, mavjudini qayta ishlatib bo'lmaydi: mavjud matn «ro'yxatdan o'tish»
deydi, foydalanuvchi esa allaqachon tizimda va **e'lon kontaktini** tasdiqlaydi. Boshqa matnli
SMS yuborsak — PlayMobile so'rovni **qabul qiladi, lekin yetkazmaydi**
(`app/integrations/sms_provider.py:10-16` izohi shu tajribadan yozilgan).

### Kod uzunligi — 5 xonali (Z1)

Dizaynda OTP **6 katak** (`293:12214`, `293:12460`), bizda hamma joyda **5**:

| Joy | Fayl / qator | Qiymat |
|---|---|---|
| Backend generatsiya | `app/services/otp_service.py:33` | `secrets.randbelow(90000) + 10000` → `10000..99999` = **5 xona** |
| Backend validatsiya | `app/schemas/auth.py:11` | `min_length=5, max_length=5` |
| Mobil | `lib/features/bozor/screens/bozor_contacts_step_screen.dart:38` | `const int _codeLength = 5;` |
| Mavjud SMS shabloni | `app/integrations/sms_provider.py:21` | `{code}` → 5 xona uchun tasdiqlangan |

Reja **Z1** qarori: **5 da qolamiz**, 6 ga o'tish backend + shablonni qayta tasdiqlashni
(haftalar) talab qiladi. Shuning uchun yangi shablonda ham kod **5 xonali**.

### Mavjud shablon — NUSXA sifatida

`app/integrations/sms_provider.py:19-26` da uchta shablon bor, ulardan **faqat `register`**
haqiqatda tasdiqlangan va yetkazilishi sinovdan o'tgan:

```
Kodni begonalarga bermang. 3D kadastr ro‘yxatdan o‘tish uchun kod: {code}. nM7qB5fW4kN
```

Shu matnning **uslub qoidalari** kod izohida yozilgan (test orqali aniqlangan) va yangi
shablonda ham **aynan saqlanishi kerak**:

| Qoida | Nega |
|---|---|
| Apostrof = **U+2018** (`‘`), ASCII `'` (U+0027) **EMAS** | Operator shablonni belgi-bechbelgi solishtiradi; ASCII apostrof bilan yetkazilmaydi |
| Koddan keyin **nuqta** bo'lishi shart | Ayni sabab |
| Oxirida `nM7qB5fW4kN` | Android SMS Retriever hash'i — avto-to'ldirish shu bilan ishlaydi. Hash **ilovaga** bog'liq, shuning uchun yangi shablonda ham **o'zi** |
| Boshida «Kodni begonalarga bermang» | Mavjud uslub; SMS'ni fishing sifatida belgilanishidan saqlaydi |

### SMS uzunligi — o'lchangan raqamlar

U+2018 va kirill harflari GSM-7 alifbosiga **kirmaydi**, ya'ni SMS UCS-2 bilan kodlanadi va
bir segmentga **70 belgi** sig'adi (GSM-7 da 160). Quyidagilar hisoblab chiqarilgan:

| Variant | Belgilar | Kodlash | SMS segmenti |
|---|---|---|---|
| MAVJUD `register` (uz) | 85 | UCS-2 | **2** |
| Yangi uz — A-variant (U+2018 bilan, mavjud uslubda) | 93 | UCS-2 | **2** |
| Yangi uz — B-variant (ASCII apostrof, qisqartirilgan) | 88 | GSM-7 | **1** |
| Yangi ru | 98 | UCS-2 | **2** |
| Yangi en | 86 | GSM-7 | **1** |

⚠️ Mavjud `register` shabloni ham allaqachon **2 segment** — ya'ni A-variant **yangi xarajat
qo'shmaydi**, bor holatni takrorlaydi. B-variant esa 2 barobar arzon, lekin apostrof belgisini
o'zgartiradi — shuning uchun so'rovda **ikkalasi ham** taklif qilinadi va tanlov operatorga
qoldiriladi.

### Yuboriladigan matn

```
Здравствуйте!

Просим согласовать НОВЫЙ шаблон SMS для приложения «3D kadastr».

Зачем нужен отдельный шаблон. У нас уже согласован и работает шаблон для
регистрации/входа:

   Kodni begonalarga bermang. 3D kadastr ro‘yxatdan o‘tish uchun kod: 12345. nM7qB5fW4kN

Сейчас мы добавляем новый сценарий: пользователь размещает объявление о
недвижимости и подтверждает КОНТАКТНЫЙ НОМЕР в объявлении. Это другой случай —
пользователь уже вошёл в приложение, и текст про «регистрацию» здесь не подходит
и вводит в заблуждение. Поэтому просим согласовать отдельный текст.

Код в новом шаблоне — 5 цифр, как и в действующем шаблоне.
Хеш в конце (nM7qB5fW4kN) — тот же, он привязан к приложению и нужен для
автозаполнения кода на Android.

--- ВАРИАНТ A (узбекский, в стиле действующего шаблона) --------------------

   Kodni begonalarga bermang. 3D kadastr e‘lon raqamini tasdiqlash uchun kod: 12345. nM7qB5fW4kN

   93 символа. Апостроф — U+2018 (‘), как в действующем шаблоне.
   Кодируется в UCS-2, то есть 2 SMS-сегмента — ровно как действующий шаблон
   (он 85 символов, тоже 2 сегмента). Дополнительных расходов не добавляет.

--- ВАРИАНТ B (узбекский, короче и дешевле) --------------------------------

   Kodni begonalarga bermang. 3D kadastr e'lon raqamini tasdiqlash kodi: 12345. nM7qB5fW4kN

   88 символов, обычный ASCII-апостроф ('), кодируется в GSM-7 —
   это 1 SMS-сегмент вместо двух, то есть вдвое дешевле.
   Мы готовы взять этот вариант, если такой апостроф допустим на вашей стороне.

--- РУССКИЙ ----------------------------------------------------------------

   Не сообщайте код посторонним. Код подтверждения номера в объявлении 3D kadastr: 12345. nM7qB5fW4kN

   98 символов, UCS-2, 2 сегмента.

--- АНГЛИЙСКИЙ -------------------------------------------------------------

   Do not share this code. 3D kadastr listing phone verification code: 12345. nM7qB5fW4kN

   86 символов, GSM-7, 1 сегмент.

Вопросы:

1) Какой из узбекских вариантов согласовываем — A или B? (Нам предпочтительнее B,
   он вдвое дешевле, но мы не знаем, пройдёт ли обычный апостроф проверку
   шаблона на вашей стороне.)
2) Нужно ли согласовывать русскую и английскую версии отдельными шаблонами,
   или достаточно узбекской для всех пользователей? (В приложении три языка
   интерфейса: uz / ru / en.)
3) Сколько занимает согласование по срокам? Нам нужно понимать, к какому релизу
   планировать этот сценарий.
4) Отправитель (originator) остаётся 3700, как сейчас — верно?

Если в каком-то из текстов нужно поправить формулировку под ваши требования —
пришлите, пожалуйста, итоговый вариант ПОСИМВОЛЬНО: мы подставляем текст в код
в точности так, как он согласован (любое расхождение в одном символе приводит к
тому, что сообщения принимаются, но не доставляются).

Спасибо!
```

> **Javob kelgach:** matnni `app/integrations/sms_provider.py` dagi `SMS_TEMPLATES` ga
> `"listing_contact"` kaliti bilan qo'shing va apostrofni `_APOS` konstantasi orqali yozing
> (fayl izohi: tahrirlovchi belgini buzmasligi uchun). Kalitni M4-30 endpointi
> `sms_provider.send_otp(phone, code, otp_type="listing_contact")` deb chaqiradi.

---

## 5. So'rov D — mahsulotga: 3 ta mahsulot qarori

### Nega kerak

Uchtasi ham **kod yozishdan oldin** hal bo'lishi kerak, lekin qattiqligi har xil:

| Qaror | Manba | Qattiqlik |
|---|---|---|
| **1. Bozor lentasining kirish nuqtasi** | reja §7 №7 | ⛔ **Qattiq blok** — M1-12b. Ekran qayerdan ochilishini bilmasdan uni yozib bo'lmaydi, va bu navigatsiyaga (`main_shell.dart`) tegadi |
| **2. Sevimlilar («Избранные»)** | reja §7 №8 | Yumshoq — hozircha rejaga **kirmagan**. Javob kerak, lekin default bor: «hozircha yo'q» |
| **3. E'lon sarlavhasi (`title`)** | reja Z8 | Yumshoq — default (a) bor: maydon qoladi. Lekin M4-24 ekranini qayta chizmaslik uchun oldindan bilish arzon |

### 1. Lenta kirish nuqtasi (§7 №7)

Hozir ilovada **4 tab**: Asosiy / Market / Arizalar / Profil. Dizaynda esa NoMakler namunasidagi
**5 tabli** bottom bar (Главная/Поиск/Добавить/Избранные/Кабинет) — xarita §14 bo'yicha u
**ko'chirilmaydi** (Z11). Ya'ni tasdiqlangan e'lonlar lentasi **qayerdan ochilishi** dizaynda
javobsiz qolgan.

**Tavsiyamiz: (b) — Market tab ichida segment.** Sabablar:

- Market tab allaqachon `MarketController` bilan ishlaydi (debounce, sahifalash, race-token,
  skeleton, pull-to-refresh, «tepaga» FAB) va M1-12a `BozorFeedRepository implements MarketRepository`
  yozsa bularning hammasi **tekin** keladi;
- 5-tab qo'shish bottom bar'ni qayta chizadi va Z11 qaroriga zid;
- Home'dagi karta lentaga **kirish** beradi, lekin lentaning «uyi» bo'lmaydi — foydalanuvchi
  ikkinchi marta qaytishni qidiradi.

**Default (javob kelmasa): (b).**

### 2. Sevimlilar (§7 №8)

Sevimlilar **umuman yo'q**: na mobil ekran, na backend jadval/endpoint, na ikonka.
Dizaynda faqat ko'chirilmaydigan 5 tabli bar ichida «Избранные» yozuvi bor.

**Tavsiyamiz: hozircha YO'Q, M5 dan keyin alohida vazifa.** Sabab: sevimlilar =
yangi jadval (`bozor_listing_favorites`) + 3 endpoint (qo'shish/o'chirish/ro'yxat) +
autentifikatsiya talabi (anonim foydalanuvchida sevimli qayerda saqlanadi?) + lentadagi va
detaldagi yurak ikonkasi + «Sevimlilar» ekrani. Bu M1 ning yagona maqsadini
(«ijara oqimi to'liq tirik») **kechiktiradi**, o'zi esa uzilgan halqa emas — busiz ham
oqim uchidan-uchiga ishlaydi.

**Default (javob kelmasa): kiritilmaydi.** Agar «kerak» javobi kelsa — M5 dan keyin,
alohida bosqich sifatida baholaymiz.

### 3. E'lon sarlavhasi — Z8

Dizaynning **hech bir qadamida** «Заголовок объявления» maydoni yo'q (89 freym bo'ylab).
Bizda esa u 6-qadamda bor va backend `title` ustuni **NOT NULL (min 3)**.

Uch yo'l bor: (a) maydon qoladi / (b) backend avtomatik yasaydi
(«3-xonali kvartira, Yunusobod») / (c) dizaynga qo'shiladi.

**Tavsiyamiz: (a) — maydon qoladi.** Sabablar: (b) da sarlavha lentada takrorlanadi va
qidiruv sifati tushadi, undan tashqari `title` ni generatsiya qilish `_derive()` ga yana bir
qaramlik qo'shadi; (c) dizaynerdan yangi freym so'rashni talab qiladi va M4-24 ni bloklaydi.
(a) da esa **hech narsa o'zgarmaydi** — bugun ishlaydigan xatti-harakat saqlanadi.

**Default (javob kelmasa): (a).**

### Yuboriladigan matn

```
Здравствуйте!

Три продуктовых решения по потоку «Продажа» / «Бозор». По каждому у нас есть
рекомендация и вариант по умолчанию — если решения нет, мы возьмём default и
пойдём дальше, чтобы не останавливать разработку. Но по первому пункту default
не спасает: он блокирует конкретный экран.

--- 1. ОТКУДА ПОЛЬЗОВАТЕЛЬ ПОПАДАЕТ В ЛЕНТУ ОБЪЯВЛЕНИЙ (это блокер) ---------

Сейчас в приложении 4 таба: Главная / Маркет / Заявки / Профиль.
В макетах внизу нарисован таб-бар из 5 пунктов (Главная/Поиск/Добавить/
Избранные/Кабинет), но это бар из чужого приложения-референса, и мы его не
переносим — у нас другая навигация.

Получается, что лента одобренных объявлений (то, что пользователь видит после
модерации) нигде не имеет входа. Варианты:

   а) новая карточка на Главной;
   б) сегмент внутри таба «Маркет» (сейчас там только каталог 3D-моделей);
   в) новый, пятый таб.

НАША РЕКОМЕНДАЦИЯ: (б) — сегмент внутри «Маркет».
Причина техническая и весомая: таб «Маркет» уже умеет поиск с задержкой,
постраничную загрузку, скелетоны, pull-to-refresh и кнопку «наверх». Если лента
живёт внутри него, всё это достаётся бесплатно. Вариант (в) заставляет
переделывать таб-бар, вариант (а) даёт вход в ленту, но не даёт ей «дома» —
пользователь не найдёт, как вернуться туда во второй раз.

DEFAULT, если ответа нет: (б).
Вопрос: подтверждаете (б)? Да / нет — тогда какой вариант.

--- 2. «ИЗБРАННОЕ» -----------------------------------------------------------

Сейчас избранного нет вообще: ни экрана, ни хранения на сервере, ни иконки.
В макетах слово «Избранные» встречается только в том самом таб-баре, который
мы не переносим.

НАША РЕКОМЕНДАЦИЯ: пока НЕ делать, вынести в отдельную задачу после того, как
поток объявлений заработает целиком.
Причина: это не одна кнопка, а новая таблица на сервере, три метода API,
отдельный вопрос «а что с избранным у неавторизованного пользователя», иконка
в ленте и в карточке объявления и отдельный экран. Сам поток размещения и
просмотра объявлений без избранного работает полностью.

DEFAULT, если ответа нет: не делаем в этом этапе.
Вопрос: избранное нужно? Да / нет. Если да — нужно ли оно в первом релизе
объявлений или можно следующим?

--- 3. ЗАГОЛОВОК ОБЪЯВЛЕНИЯ --------------------------------------------------

Ни на одном из 89 макетов нет поля «Заголовок объявления». А у нас это поле
есть на шаге «Описание», и на сервере заголовок — обязательное поле
(минимум 3 символа). То есть макет и текущая реализация расходятся.

Варианты:
   а) оставить поле как есть (пользователь пишет заголовок сам);
   б) убрать поле, а заголовок собирать автоматически
      (например «3-комнатная квартира, Юнусабад»);
   в) добавить поле в макет.

НАША РЕКОМЕНДАЦИЯ: (а) — оставить как есть.
Причина: при (б) заголовки в ленте станут однотипными и поиск по ним потеряет
смысл; при (в) нужен новый макет, и шаг «Описание» ждёт его. Вариант (а) ничего
не ломает — так работает уже сейчас.

DEFAULT, если ответа нет: (а).
Вопрос: подтверждаете (а)? Да / нет.

Спасибо!
```

---

## 6. Javob kelgach nima qilinadi

| So'rov | Javob qayerga yoziladi |
|---|---|
| **A** | `docs/bozor-v2-figma-map.md` §12 (83–89-qatorlar — `⚠️ O'QILMAGAN` o'rniga haqiqiy mazmun) va §0.2 (variant bo'yicha qadamlar soni). Keyin reja M3-18 / M3-19 mezonlari qayta ko'riladi |
| **B** | `docs/bozor-v2-figma-map.md` §10 (`⚠️(?)` belgilari olib tashlanadi) va §11 (ustun turlari tasdiqlanadi). Keyin M2-16 blokdan chiqadi |
| **C** | `app/integrations/sms_provider.py` → `SMS_TEMPLATES["listing_contact"]`, matn **posimvolno**. Shablon kelmaguncha M4-30 kodi `DEBUG_OTP_CODE` va demo raqam (`+998990000011`, kod `00000`) bilan sinaladi |
| **D** | Reja §7 (№7, №8) va §2 (Z8) qatorlari «hal qilindi» deb belgilanadi; M1-12b ning kirish nuqtasi aniqlanadi |

**Har bir javob kelganda:** yuqoridagi 1-bo'lim jadvalining «javob sanasi» va «javob»
ustunlarini to'ldiring. Bo'sh qator = javob hali kelmagan, ya'ni blok hamon kuchda.
