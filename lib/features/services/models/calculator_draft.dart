/// Online kalkulyator — TZ-aligned models, drafts, and pricing.
///
/// Seven categories. Each has its own form, picker options, and pricing
/// table sourced from `online calculator.doc`.
library;

import 'package:flutter/material.dart';

import 'calculator_pricing.dart';

// ────────────────────────────────────────────────────────────────────────
// Locale helper
// ────────────────────────────────────────────────────────────────────────

String _pick(Locale l, {required String uz, required String ru, required String en}) {
  switch (l.languageCode) {
    case 'ru':
      return ru;
    case 'en':
      return en;
    default:
      return uz;
  }
}

// ────────────────────────────────────────────────────────────────────────
// Categories
// ────────────────────────────────────────────────────────────────────────

enum CalculatorCategory {
  arxitektura,
  kadastr,
  kadastr3d,
  baholash,
  dizayn,
  tamirlash,
  yuridik;

  String title(Locale l) => switch (this) {
    CalculatorCategory.arxitektura => _pick(
      l,
      uz: 'Arxitektura va qurilish loyihasi',
      ru: 'Архитектура и проектирование',
      en: 'Architecture & construction project',
    ),
    CalculatorCategory.kadastr => _pick(
      l,
      uz: 'Kadastr hujjatlari',
      ru: 'Кадастровые документы',
      en: 'Cadastre documents',
    ),
    CalculatorCategory.kadastr3d => _pick(
      l,
      uz: '3D kadastr hujjatlari',
      ru: '3D кадастровые документы',
      en: '3D cadastre documents',
    ),
    CalculatorCategory.baholash => _pick(
      l,
      uz: 'Mulk qiymatini baholash',
      ru: 'Оценка стоимости имущества',
      en: 'Property valuation',
    ),
    CalculatorCategory.dizayn => _pick(
      l,
      uz: 'Dizayn loyihasi',
      ru: 'Дизайн-проект',
      en: 'Design project',
    ),
    CalculatorCategory.tamirlash => _pick(
      l,
      uz: "Ta'mirlash va qurilish ishlari",
      ru: 'Ремонт и строительство',
      en: 'Repair & construction',
    ),
    CalculatorCategory.yuridik => _pick(
      l,
      uz: 'Yuridik xizmat',
      ru: 'Юридические услуги',
      en: 'Legal services',
    ),
  };

  String subtitle(Locale l) => switch (this) {
    CalculatorCategory.arxitektura => _pick(
      l,
      uz: 'Loyiha hajmiga qarab',
      ru: 'По объёму проекта',
      en: 'Based on project size',
    ),
    CalculatorCategory.kadastr => _pick(
      l,
      uz: "Pasport va yig'ma jild",
      ru: 'Паспорт и кадастровое дело',
      en: 'Passport & file',
    ),
    CalculatorCategory.kadastr3d => _pick(
      l,
      uz: "3D pasport va yig'ma jild",
      ru: '3D паспорт и кадастровое дело',
      en: '3D passport & file',
    ),
    CalculatorCategory.baholash => _pick(
      l,
      uz: 'Bozor qiymatini aniqlash',
      ru: 'Определение рыночной стоимости',
      en: 'Determine market value',
    ),
    CalculatorCategory.dizayn => _pick(
      l,
      uz: 'Interyer va eksteryer dizayn',
      ru: 'Интерьер и экстерьер',
      en: 'Interior & exterior design',
    ),
    CalculatorCategory.tamirlash => _pick(
      l,
      uz: "Ta'mir va qurilish xizmatlari",
      ru: 'Услуги ремонта и строительства',
      en: 'Repair & construction services',
    ),
    CalculatorCategory.yuridik => _pick(
      l,
      uz: "Maslahat, sud, ro'yxatga olish",
      ru: 'Консультация, суд, регистрация',
      en: 'Consultation, court, registration',
    ),
  };

  IconData get icon => switch (this) {
    CalculatorCategory.arxitektura => Icons.architecture_rounded,
    CalculatorCategory.kadastr => Icons.description_outlined,
    CalculatorCategory.kadastr3d => Icons.view_in_ar_rounded,
    CalculatorCategory.baholash => Icons.assessment_outlined,
    CalculatorCategory.dizayn => Icons.palette_outlined,
    CalculatorCategory.tamirlash => Icons.construction_rounded,
    CalculatorCategory.yuridik => Icons.gavel_rounded,
  };

  Color get accent => switch (this) {
    CalculatorCategory.arxitektura => const Color(0xFF22D3EE),
    CalculatorCategory.kadastr => const Color(0xFF00E135),
    CalculatorCategory.kadastr3d => const Color(0xFF7C3AED),
    CalculatorCategory.baholash => const Color(0xFFF59E0B),
    CalculatorCategory.dizayn => const Color(0xFFEC4899),
    CalculatorCategory.tamirlash => const Color(0xFF2B7FFF),
    CalculatorCategory.yuridik => const Color(0xFF64748B),
  };
}

// ────────────────────────────────────────────────────────────────────────
// Arxitektura va qurilish loyihasi
// 1m² narxlari TZ jadvalidan
// ────────────────────────────────────────────────────────────────────────

enum ArxitekturaObject {
  yakkaSmall,
  yakkaLarge,
  kopQavatli,
  jamoat,
  sanoat,
  rekonstruksiya;

  /// Backend narx kaliti (`calculator_prices.key`).
  String get priceKey => switch (this) {
    ArxitekturaObject.yakkaSmall => 'arxitektura.yakka_small',
    ArxitekturaObject.yakkaLarge => 'arxitektura.yakka_large',
    ArxitekturaObject.kopQavatli => 'arxitektura.kop_qavatli',
    ArxitekturaObject.jamoat => 'arxitektura.jamoat',
    ArxitekturaObject.sanoat => 'arxitektura.sanoat',
    ArxitekturaObject.rekonstruksiya => 'arxitektura.rekonstruksiya',
  };

  String label(Locale l) => switch (this) {
    ArxitekturaObject.yakkaSmall => _pick(
      l,
      uz: 'Yakka tartibdagi uy (kichik)',
      ru: 'Индивидуальный дом (малый)',
      en: 'Single-family house (small)',
    ),
    ArxitekturaObject.yakkaLarge => _pick(
      l,
      uz: 'Yakka tartibdagi uy (katta)',
      ru: 'Индивидуальный дом (большой)',
      en: 'Single-family house (large)',
    ),
    ArxitekturaObject.kopQavatli => _pick(
      l,
      uz: "Ko'p qavatli turar-joy binosi",
      ru: 'Многоэтажный жилой дом',
      en: 'Multi-storey residential building',
    ),
    ArxitekturaObject.jamoat => _pick(
      l,
      uz: 'Jamoat binolari',
      ru: 'Общественные здания',
      en: 'Public buildings',
    ),
    ArxitekturaObject.sanoat => _pick(
      l,
      uz: 'Sanoat binolari',
      ru: 'Промышленные здания',
      en: 'Industrial buildings',
    ),
    ArxitekturaObject.rekonstruksiya => _pick(
      l,
      uz: 'Rekonstruksiya (qayta qurish)',
      ru: 'Реконструкция',
      en: 'Reconstruction',
    ),
  };

  String? hint(Locale l) => switch (this) {
    ArxitekturaObject.yakkaSmall => _pick(
      l,
      uz: '500 m² dan kichik, balandligi 12 m dan past',
      ru: 'меньше 500 м², высота до 12 м',
      en: 'under 500 m², height under 12 m',
    ),
    ArxitekturaObject.yakkaLarge => _pick(
      l,
      uz: "500 m² dan katta yoki 12 m dan baland",
      ru: 'больше 500 м² или выше 12 м',
      en: 'over 500 m² or above 12 m',
    ),
    ArxitekturaObject.jamoat => _pick(
      l,
      uz: "Ofis, biznes markaz, savdo markaz, restoran",
      ru: 'Офис, бизнес-центр, ТЦ, ресторан',
      en: 'Office, business center, mall, restaurant',
    ),
    ArxitekturaObject.sanoat => _pick(
      l,
      uz: "Ishlab chiqarish, zavod, fabrika, ombor",
      ru: 'Производство, завод, фабрика, склад',
      en: 'Production, plant, factory, warehouse',
    ),
    _ => null,
  };
}

// ────────────────────────────────────────────────────────────────────────
// Kadastr hujjatlari (oddiy va 3D bir xil tuzilma, narxlar boshqacha)
// ────────────────────────────────────────────────────────────────────────

enum KadastrObjectType {
  yakka,
  xonadon,
  kopKvartirali;

  String label(Locale l) => switch (this) {
    KadastrObjectType.yakka => _pick(
      l,
      uz: 'Yakka tartibdagi uy (hovli-joy)',
      ru: 'Индивидуальный дом (с двором)',
      en: 'Single-family house (with yard)',
    ),
    KadastrObjectType.xonadon => _pick(
      l,
      uz: "Ko'p kvartirali uydagi xonadon",
      ru: 'Квартира в многоквартирном доме',
      en: 'Apartment in multi-unit building',
    ),
    KadastrObjectType.kopKvartirali => _pick(
      l,
      uz: "Ko'p kvartirali xonadonlar (yirik)",
      ru: 'Многоквартирные дома (крупные)',
      en: 'Multi-unit residential (large)',
    ),
  };
}

// ────────────────────────────────────────────────────────────────────────
// Mulk qiymatini baholash
// ────────────────────────────────────────────────────────────────────────

enum BaholashObject {
  uyJoy,
  tijorat,
  tugallanmagan;

  /// 1 m² narx kaliti.
  String get priceKey => switch (this) {
    BaholashObject.uyJoy => 'baholash.uy_joy.per_m2',
    BaholashObject.tijorat => 'baholash.tijorat.per_m2',
    BaholashObject.tugallanmagan => 'baholash.tugallanmagan.per_m2',
  };

  /// ≤200 m² uchun belgilangan minimum bormi (tugallanmaganda yo'q).
  bool get hasMin200 => this != BaholashObject.tugallanmagan;

  /// ≤200 m² belgilangan minimum narx kaliti (faqat [hasMin200] uchun).
  String get min200Key => switch (this) {
    BaholashObject.uyJoy => 'baholash.uy_joy.min200',
    BaholashObject.tijorat => 'baholash.tijorat.min200',
    BaholashObject.tugallanmagan => 'baholash.tugallanmagan.min200',
  };

  String label(Locale l) => switch (this) {
    BaholashObject.uyJoy => _pick(
      l,
      uz: 'Uy-joy mulki',
      ru: 'Жилое имущество',
      en: 'Residential property',
    ),
    BaholashObject.tijorat => _pick(
      l,
      uz: "Tijorat ko'chmas mulki",
      ru: 'Коммерческая недвижимость',
      en: 'Commercial property',
    ),
    BaholashObject.tugallanmagan => _pick(
      l,
      uz: 'Tugallanmagan qurilish va yer uchastkasi',
      ru: 'Незавершённое строительство и земельный участок',
      en: 'Unfinished construction & land plot',
    ),
  };
}

// ────────────────────────────────────────────────────────────────────────
// Dizayn loyihasi
// ────────────────────────────────────────────────────────────────────────

enum DizaynObjectType {
  turar,
  noturar;

  String label(Locale l) => switch (this) {
    DizaynObjectType.turar => _pick(l, uz: 'Turar', ru: 'Жилой', en: 'Residential'),
    DizaynObjectType.noturar => _pick(l, uz: 'Noturar', ru: 'Нежилой', en: 'Non-residential'),
  };
}

enum DizaynStyle {
  highTech,
  klassik,
  neoklassik,
  minimalizm,
  loft,
  japandi;

  String label(Locale l) => switch (this) {
    DizaynStyle.highTech => 'High-tech',
    DizaynStyle.klassik => _pick(l, uz: 'Klassik', ru: 'Классика', en: 'Classic'),
    DizaynStyle.neoklassik => _pick(l, uz: 'Neoklassik', ru: 'Неоклассика', en: 'Neoclassical'),
    DizaynStyle.minimalizm => _pick(l, uz: 'Minimalizm', ru: 'Минимализм', en: 'Minimalism'),
    DizaynStyle.loft => 'Loft',
    DizaynStyle.japandi => 'Japandi',
  };
}

// ────────────────────────────────────────────────────────────────────────
// Ta'mirlash va qurilish ishlari
// ────────────────────────────────────────────────────────────────────────

enum TamirlashObjectType {
  turar,
  noturar;

  String label(Locale l) => switch (this) {
    TamirlashObjectType.turar => _pick(l, uz: 'Turar', ru: 'Жилой', en: 'Residential'),
    TamirlashObjectType.noturar => _pick(l, uz: 'Noturar', ru: 'Нежилой', en: 'Non-residential'),
  };
}

enum TamirlashLocation {
  toshkentShahar,
  toshkentViloyat,
  boshqa;

  String label(Locale l) => switch (this) {
    TamirlashLocation.toshkentShahar => _pick(
      l,
      uz: 'Toshkent shahar',
      ru: 'г. Ташкент',
      en: 'Tashkent city',
    ),
    TamirlashLocation.toshkentViloyat => _pick(
      l,
      uz: 'Toshkent viloyat',
      ru: 'Ташкентская область',
      en: 'Tashkent region',
    ),
    TamirlashLocation.boshqa => _pick(
      l,
      uz: 'Boshqa viloyat',
      ru: 'Другая область',
      en: 'Other region',
    ),
  };
}

enum TamirlashServiceType {
  tamir,
  qurilish;

  /// 1 m² narx kaliti.
  String get priceKey => switch (this) {
    TamirlashServiceType.tamir => 'tamirlash.tamir.per_m2',
    TamirlashServiceType.qurilish => 'tamirlash.qurilish.per_m2',
  };

  String label(Locale l) => switch (this) {
    TamirlashServiceType.tamir => _pick(l, uz: "Ta'mir", ru: 'Ремонт', en: 'Repair'),
    TamirlashServiceType.qurilish => _pick(
      l,
      uz: 'Qurilish',
      ru: 'Строительство',
      en: 'Construction',
    ),
  };
}

// ────────────────────────────────────────────────────────────────────────
// Result type
// ────────────────────────────────────────────────────────────────────────

class CalculatorResult {
  const CalculatorResult({
    required this.categoryTitle,
    required this.totalUzs,
    required this.note,
    required this.lines,
  });

  final String categoryTitle;
  final int totalUzs;
  final String note;
  final List<CalculatorLine> lines;
}

class CalculatorLine {
  const CalculatorLine(this.label, this.value);
  final String label;
  final String value;
}

// ────────────────────────────────────────────────────────────────────────
// Localised strings used inside compute functions
// ────────────────────────────────────────────────────────────────────────

class _ComputeStrings {
  const _ComputeStrings._();

  static String selectedType(Locale l) =>
      _pick(l, uz: 'Tanlangan turi', ru: 'Тип', en: 'Type');

  static String area(Locale l) =>
      _pick(l, uz: 'Maydon', ru: 'Площадь', en: 'Area');

  static String perM2(Locale l) =>
      _pick(l, uz: '1 m² uchun', ru: 'За 1 м²', en: 'Per 1 m²');

  static String tariff(Locale l) =>
      _pick(l, uz: 'Tarif', ru: 'Тариф', en: 'Rate');

  static String calc(Locale l) =>
      _pick(l, uz: 'Hisob', ru: 'Расчёт', en: 'Calculation');

  static String location(Locale l) =>
      _pick(l, uz: 'Manzil', ru: 'Адрес', en: 'Location');

  static String serviceType(Locale l) =>
      _pick(l, uz: 'Xizmat turi', ru: 'Тип услуги', en: 'Service type');

  static String objectType(Locale l) =>
      _pick(l, uz: "Ob'ekt turi", ru: 'Тип объекта', en: 'Object type');

  static String designStyle(Locale l) =>
      _pick(l, uz: 'Dizayn uslubi', ru: 'Стиль дизайна', en: 'Design style');

  static String inclVat(Locale l) =>
      _pick(l, uz: 'QQS bilan', ru: 'С НДС', en: 'incl. VAT');

  static String fixedPrice(Locale l) => _pick(
        l,
        uz: 'Belgilangan narx',
        ru: 'Фиксированная цена',
        en: 'Fixed price',
      );

  static String fixedMinFor200(Locale l) => _pick(
        l,
        uz: '200 m² gacha belgilangan minimum',
        ru: 'Фиксированный минимум до 200 м²',
        en: 'Fixed minimum for ≤200 m²',
      );

  static String upTo(Locale l, int v) => _pick(
        l,
        uz: '$v m² gacha',
        ru: 'до $v м²',
        en: 'up to $v m²',
      );

  static String over(Locale l, int v) => _pick(
        l,
        uz: '$v m² dan ortiq',
        ru: 'свыше $v м²',
        en: 'over $v m²',
      );

  static String range(int from, int to) =>
      '${_fmtNumber(from)}–${_fmtNumber(to)} m²';

  static String tierTimesArea(Locale l, int perM2) =>
      '${_fmtUzs(l, perM2)} × m²';

  static String areaWithUnit(double v) => '${_fmtArea(v)} m²';

  static String areaWithTier(Locale l, double v, String tier) =>
      '${_fmtArea(v)} m² ($tier)';

  static String multiplyExpr(Locale l, int rate, double area) =>
      '${_fmtUzs(l, rate)} × ${_fmtArea(area)}';
}

// ────────────────────────────────────────────────────────────────────────
// Compute functions (each takes a Locale)
// ────────────────────────────────────────────────────────────────────────

CalculatorResult computeArxitektura({
  required ArxitekturaObject objectType,
  required double areaM2,
  required CalculatorPricing pricing,
  required Locale locale,
}) {
  final rate = pricing.rate(objectType.priceKey).round();
  final total = (areaM2 * rate).round();
  return CalculatorResult(
    categoryTitle: CalculatorCategory.arxitektura.title(locale),
    totalUzs: total,
    note: _ComputeStrings.inclVat(locale),
    lines: [
      CalculatorLine(_ComputeStrings.selectedType(locale), objectType.label(locale)),
      CalculatorLine(_ComputeStrings.area(locale), _ComputeStrings.areaWithUnit(areaM2)),
      CalculatorLine(_ComputeStrings.perM2(locale), _fmtUzs(locale, rate)),
    ],
  );
}

CalculatorResult computeKadastr({
  required KadastrObjectType objectType,
  required double areaM2,
  required bool is3d,
  required CalculatorPricing pricing,
  required Locale locale,
}) {
  final categoryTitle = is3d
      ? CalculatorCategory.kadastr3d.title(locale)
      : CalculatorCategory.kadastr.title(locale);

  final p = is3d ? 'kadastr3d' : 'kadastr';

  int total;
  String tierLabel;

  switch (objectType) {
    case KadastrObjectType.xonadon:
      total = pricing.rate('$p.xonadon').round();
      tierLabel = _ComputeStrings.fixedPrice(locale);
    case KadastrObjectType.yakka:
      final tiers = [
        (300, pricing.rate('$p.yakka.le300').round(), _ComputeStrings.upTo(locale, 300)),
        (500, pricing.rate('$p.yakka.le500').round(), _ComputeStrings.range(300, 500)),
        (1000, pricing.rate('$p.yakka.le1000').round(), _ComputeStrings.range(500, 1000)),
        (3000, pricing.rate('$p.yakka.le3000').round(), _ComputeStrings.range(1000, 3000)),
        (5000, pricing.rate('$p.yakka.le5000').round(), _ComputeStrings.range(3000, 5000)),
      ];
      final lastPrice = pricing.rate('$p.yakka.gt5000').round();
      final lastLabel = _ComputeStrings.over(locale, 5000);
      var matched = false;
      total = lastPrice;
      tierLabel = lastLabel;
      for (final t in tiers) {
        if (areaM2 <= t.$1) {
          total = t.$2;
          tierLabel = t.$3;
          matched = true;
          break;
        }
      }
      if (!matched) {
        total = lastPrice;
        tierLabel = lastLabel;
      }
    case KadastrObjectType.kopKvartirali:
      final perM2 = is3d
          ? (areaM2 <= 10000
                ? pricing.rate('kadastr3d.kop_kvartirali.le10000').round()
                : areaM2 <= 25000
                ? pricing.rate('kadastr3d.kop_kvartirali.le25000').round()
                : pricing.rate('kadastr3d.kop_kvartirali.gt25000').round())
          : pricing.rate('kadastr.kop_kvartirali.per_m2').round();
      total = (areaM2 * perM2).round();
      tierLabel = _ComputeStrings.tierTimesArea(locale, perM2);
  }

  return CalculatorResult(
    categoryTitle: categoryTitle,
    totalUzs: total,
    note: _ComputeStrings.inclVat(locale),
    lines: [
      CalculatorLine(_ComputeStrings.selectedType(locale), objectType.label(locale)),
      CalculatorLine(_ComputeStrings.area(locale), _ComputeStrings.areaWithUnit(areaM2)),
      CalculatorLine(_ComputeStrings.tariff(locale), tierLabel),
    ],
  );
}

CalculatorResult computeBaholash({
  required BaholashObject objectType,
  required double areaM2,
  required CalculatorPricing pricing,
  required Locale locale,
}) {
  final rate = pricing.rate(objectType.priceKey).round();
  final byArea = (areaM2 * rate).round();
  int total;
  String calcStr;

  if (areaM2 <= 200 && objectType.hasMin200) {
    total = pricing.rate(objectType.min200Key).round();
    calcStr = _ComputeStrings.fixedMinFor200(locale);
  } else {
    total = byArea;
    calcStr = _ComputeStrings.multiplyExpr(locale, rate, areaM2);
  }

  return CalculatorResult(
    categoryTitle: CalculatorCategory.baholash.title(locale),
    totalUzs: total,
    note: _ComputeStrings.inclVat(locale),
    lines: [
      CalculatorLine(_ComputeStrings.selectedType(locale), objectType.label(locale)),
      CalculatorLine(_ComputeStrings.area(locale), _ComputeStrings.areaWithUnit(areaM2)),
      CalculatorLine(_ComputeStrings.calc(locale), calcStr),
    ],
  );
}

CalculatorResult computeDizayn({
  required DizaynObjectType objectType,
  required DizaynStyle style,
  required double areaM2,
  required CalculatorPricing pricing,
  required Locale locale,
}) {
  final rate = (areaM2 <= 100
          ? pricing.rate('dizayn.le100.per_m2')
          : pricing.rate('dizayn.gt100.per_m2'))
      .round();
  final total = (areaM2 * rate).round();
  final tierLabel =
      areaM2 <= 100 ? _ComputeStrings.upTo(locale, 100) : _ComputeStrings.over(locale, 100);

  return CalculatorResult(
    categoryTitle: CalculatorCategory.dizayn.title(locale),
    totalUzs: total,
    note: _ComputeStrings.inclVat(locale),
    lines: [
      CalculatorLine(_ComputeStrings.objectType(locale), objectType.label(locale)),
      CalculatorLine(_ComputeStrings.designStyle(locale), style.label(locale)),
      CalculatorLine(
        _ComputeStrings.area(locale),
        _ComputeStrings.areaWithTier(locale, areaM2, tierLabel),
      ),
      CalculatorLine(_ComputeStrings.perM2(locale), _fmtUzs(locale, rate)),
    ],
  );
}

CalculatorResult computeTamirlash({
  required TamirlashObjectType objectType,
  required TamirlashLocation location,
  required TamirlashServiceType serviceType,
  required double areaM2,
  required CalculatorPricing pricing,
  required Locale locale,
}) {
  final rate = pricing.rate(serviceType.priceKey).round();
  final total = (areaM2 * rate).round();
  return CalculatorResult(
    categoryTitle: CalculatorCategory.tamirlash.title(locale),
    totalUzs: total,
    note: _ComputeStrings.inclVat(locale),
    lines: [
      CalculatorLine(_ComputeStrings.serviceType(locale), serviceType.label(locale)),
      CalculatorLine(_ComputeStrings.objectType(locale), objectType.label(locale)),
      CalculatorLine(_ComputeStrings.location(locale), location.label(locale)),
      CalculatorLine(_ComputeStrings.area(locale), _ComputeStrings.areaWithUnit(areaM2)),
      CalculatorLine(_ComputeStrings.perM2(locale), _fmtUzs(locale, rate)),
    ],
  );
}

// ────────────────────────────────────────────────────────────────────────
// Currency / number formatting
// ────────────────────────────────────────────────────────────────────────

String fmtUzsPublic(Locale l, int value) => _fmtUzs(l, value);

String _currencySuffix(Locale l) =>
    _pick(l, uz: "so'm", ru: 'сум', en: 'UZS');

String _fmtUzs(Locale l, int value) {
  final sign = value < 0 ? '-' : '';
  final s = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return "$sign${buf.toString()} ${_currencySuffix(l)}";
}

String _fmtNumber(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _fmtArea(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
