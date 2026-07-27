/// Online kalkulyator — TZ-aligned models, drafts, and pricing.
///
/// Seven categories. Each has its own form, picker options, and pricing
/// table sourced from `online calculator.doc`.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
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
    CalculatorCategory.arxitektura =>
      tr(l, 'services.model.cat.arxitektura.title'),
    CalculatorCategory.kadastr => tr(l, 'services.model.cat.kadastr.title'),
    CalculatorCategory.kadastr3d => tr(l, 'services.model.cat.kadastr3d.title'),
    CalculatorCategory.baholash => tr(l, 'services.model.cat.baholash.title'),
    CalculatorCategory.dizayn => tr(l, 'services.model.cat.dizayn.title'),
    CalculatorCategory.tamirlash => tr(l, 'services.model.cat.tamirlash.title'),
    CalculatorCategory.yuridik => tr(l, 'services.model.cat.yuridik.title'),
  };

  String subtitle(Locale l) => switch (this) {
    CalculatorCategory.arxitektura =>
      tr(l, 'services.model.cat.arxitektura.subtitle'),
    CalculatorCategory.kadastr => tr(l, 'services.model.cat.kadastr.subtitle'),
    CalculatorCategory.kadastr3d =>
      tr(l, 'services.model.cat.kadastr3d.subtitle'),
    CalculatorCategory.baholash =>
      tr(l, 'services.model.cat.baholash.subtitle'),
    CalculatorCategory.dizayn => tr(l, 'services.model.cat.dizayn.subtitle'),
    CalculatorCategory.tamirlash =>
      tr(l, 'services.model.cat.tamirlash.subtitle'),
    CalculatorCategory.yuridik => tr(l, 'services.model.cat.yuridik.subtitle'),
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

  /// 3D image icon for the service tile. Null → fall back to [icon].
  /// (kadastr3d keeps the AR glyph — no 3D image supplied for it.)
  String? get assetIcon => switch (this) {
    CalculatorCategory.arxitektura =>
      'assets/images/services/architecture.webp',
    CalculatorCategory.kadastr => 'assets/images/services/accounting.webp',
    CalculatorCategory.kadastr3d => 'assets/images/services/kadastr3d.png',
    CalculatorCategory.baholash =>
      'assets/images/services/property-value.webp',
    CalculatorCategory.dizayn => 'assets/images/services/design.webp',
    CalculatorCategory.tamirlash => 'assets/images/services/repair.webp',
    CalculatorCategory.yuridik => 'assets/images/services/legal.webp',
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
    ArxitekturaObject.yakkaSmall =>
      tr(l, 'services.model.arxitektura.yakka_small'),
    ArxitekturaObject.yakkaLarge =>
      tr(l, 'services.model.arxitektura.yakka_large'),
    ArxitekturaObject.kopQavatli =>
      tr(l, 'services.model.arxitektura.kop_qavatli'),
    ArxitekturaObject.jamoat => tr(l, 'services.model.arxitektura.jamoat'),
    ArxitekturaObject.sanoat => tr(l, 'services.model.arxitektura.sanoat'),
    ArxitekturaObject.rekonstruksiya =>
      tr(l, 'services.model.arxitektura.rekonstruksiya'),
  };

  String? hint(Locale l) => switch (this) {
    ArxitekturaObject.yakkaSmall =>
      tr(l, 'services.model.arxitektura.yakka_small.hint'),
    ArxitekturaObject.yakkaLarge =>
      tr(l, 'services.model.arxitektura.yakka_large.hint'),
    ArxitekturaObject.jamoat =>
      tr(l, 'services.model.arxitektura.jamoat.hint'),
    ArxitekturaObject.sanoat =>
      tr(l, 'services.model.arxitektura.sanoat.hint'),
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
    KadastrObjectType.yakka => tr(l, 'services.model.kadastr_obj.yakka'),
    KadastrObjectType.xonadon => tr(l, 'services.model.kadastr_obj.xonadon'),
    KadastrObjectType.kopKvartirali =>
      tr(l, 'services.model.kadastr_obj.kop_kvartirali'),
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
    BaholashObject.uyJoy => tr(l, 'services.model.baholash_obj.uy_joy'),
    BaholashObject.tijorat => tr(l, 'services.model.baholash_obj.tijorat'),
    BaholashObject.tugallanmagan =>
      tr(l, 'services.model.baholash_obj.tugallanmagan'),
  };
}

// ────────────────────────────────────────────────────────────────────────
// Dizayn loyihasi
// ────────────────────────────────────────────────────────────────────────

enum DizaynObjectType {
  turar,
  noturar;

  String label(Locale l) => switch (this) {
    DizaynObjectType.turar => tr(l, 'services.model.obj.turar'),
    DizaynObjectType.noturar => tr(l, 'services.model.obj.noturar'),
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
    DizaynStyle.highTech => tr(l, 'services.model.style.high_tech'),
    DizaynStyle.klassik => tr(l, 'services.model.style.klassik'),
    DizaynStyle.neoklassik => tr(l, 'services.model.style.neoklassik'),
    DizaynStyle.minimalizm => tr(l, 'services.model.style.minimalizm'),
    DizaynStyle.loft => tr(l, 'services.model.style.loft'),
    DizaynStyle.japandi => tr(l, 'services.model.style.japandi'),
  };
}

// ────────────────────────────────────────────────────────────────────────
// Ta'mirlash va qurilish ishlari
// ────────────────────────────────────────────────────────────────────────

enum TamirlashObjectType {
  turar,
  noturar;

  String label(Locale l) => switch (this) {
    TamirlashObjectType.turar => tr(l, 'services.model.obj.turar'),
    TamirlashObjectType.noturar => tr(l, 'services.model.obj.noturar'),
  };
}

enum TamirlashLocation {
  toshkentShahar,
  toshkentViloyat,
  boshqa;

  String label(Locale l) => switch (this) {
    TamirlashLocation.toshkentShahar =>
      tr(l, 'services.model.tamir_loc.toshkent_shahar'),
    TamirlashLocation.toshkentViloyat =>
      tr(l, 'services.model.tamir_loc.toshkent_viloyat'),
    TamirlashLocation.boshqa => tr(l, 'services.model.tamir_loc.boshqa'),
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
    TamirlashServiceType.tamir =>
      tr(l, 'services.model.tamir_service.tamir'),
    TamirlashServiceType.qurilish =>
      tr(l, 'services.model.tamir_service.qurilish'),
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
      tr(l, 'services.model.compute.selected_type');

  static String area(Locale l) => tr(l, 'services.model.compute.area');

  static String perM2(Locale l) => tr(l, 'services.model.compute.per_m2');

  static String tariff(Locale l) => tr(l, 'services.model.compute.tariff');

  static String calc(Locale l) => tr(l, 'services.model.compute.calc');

  static String location(Locale l) => tr(l, 'services.model.compute.location');

  static String serviceType(Locale l) =>
      tr(l, 'services.model.compute.service_type');

  static String objectType(Locale l) =>
      tr(l, 'services.model.compute.object_type');

  static String designStyle(Locale l) =>
      tr(l, 'services.model.compute.design_style');

  static String inclVat(Locale l) => tr(l, 'services.model.compute.incl_vat');

  static String fixedPrice(Locale l) =>
      tr(l, 'services.model.compute.fixed_price');

  static String fixedMinFor200(Locale l) =>
      tr(l, 'services.model.compute.fixed_min_200');

  static String upTo(Locale l, int v) =>
      tr(l, 'services.model.compute.up_to').replaceAll(r'$v', '$v');

  static String over(Locale l, int v) =>
      tr(l, 'services.model.compute.over').replaceAll(r'$v', '$v');

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
