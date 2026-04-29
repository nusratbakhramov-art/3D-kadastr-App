/// Online kalkulyator — TZ-aligned models, drafts, and pricing.
///
/// Seven categories. Each has its own form, picker options, and pricing
/// table sourced from `D:/downloads/tg/online calculator.doc`.
library;

import 'package:flutter/material.dart';

enum CalculatorCategory {
  arxitektura,
  kadastr,
  kadastr3d,
  baholash,
  dizayn,
  tamirlash,
  yuridik;

  String get title => switch (this) {
    CalculatorCategory.arxitektura => 'Arxitektura va qurilish loyihasi',
    CalculatorCategory.kadastr => 'Kadastr hujjatlari',
    CalculatorCategory.kadastr3d => '3D kadastr hujjatlari',
    CalculatorCategory.baholash => 'Mulk qiymatini baholash',
    CalculatorCategory.dizayn => 'Dizayn loyihasi',
    CalculatorCategory.tamirlash => "Ta'mirlash va qurilish ishlari",
    CalculatorCategory.yuridik => 'Yuridik xizmat',
  };

  String get subtitle => switch (this) {
    CalculatorCategory.arxitektura => 'Loyiha hajmiga qarab',
    CalculatorCategory.kadastr => 'Pasport va yig\'ma jild',
    CalculatorCategory.kadastr3d => '3D pasport va yig\'ma jild',
    CalculatorCategory.baholash => 'Bozor qiymatini aniqlash',
    CalculatorCategory.dizayn => 'Interyer va eksteryer dizayn',
    CalculatorCategory.tamirlash => "Ta'mir va qurilish xizmatlari",
    CalculatorCategory.yuridik => 'Maslahat, sud, ro\'yxatga olish',
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
  yakkaSmall(
    "Yakka tartibdagi uy (kichik)",
    "500 m² dan kichik, balandligi 12 m dan past",
    36000,
  ),
  yakkaLarge(
    "Yakka tartibdagi uy (katta)",
    "500 m² dan katta yoki 12 m dan baland",
    60000,
  ),
  kopQavatli("Ko'p qavatli turar-joy binosi", null, 84000),
  jamoat(
    "Jamoat binolari",
    "Ofis, biznes markaz, savdo markaz, restoran",
    108000,
  ),
  sanoat(
    "Sanoat binolari",
    "Ishlab chiqarish, zavod, fabrika, ombor",
    60000,
  ),
  rekonstruksiya("Rekonstruksiya (qayta qurish)", null, 72000);

  const ArxitekturaObject(this.label, this.hint, this.pricePerM2);

  final String label;
  final String? hint;
  final int pricePerM2;
}

// ────────────────────────────────────────────────────────────────────────
// Kadastr hujjatlari (oddiy va 3D bir xil tuzilma, narxlar boshqacha)
// ────────────────────────────────────────────────────────────────────────

enum KadastrObjectType {
  yakka("Yakka tartibdagi uy (hovli-joy)"),
  xonadon("Ko'p kvartirali uydagi xonadon"),
  kopKvartirali("Ko'p kvartirali xonadonlar (yirik)");

  const KadastrObjectType(this.label);
  final String label;
}

// ────────────────────────────────────────────────────────────────────────
// Mulk qiymatini baholash
// ────────────────────────────────────────────────────────────────────────

enum BaholashObject {
  uyJoy("Uy-joy mulki", 6000, 490000),
  tijorat("Tijorat ko'chmas mulki", 10000, 990000),
  tugallanmagan("Tugallanmagan qurilish va yer uchastkasi", 15000, null);

  const BaholashObject(this.label, this.pricePerM2, this.minFor200);

  final String label;
  final int pricePerM2;
  final int? minFor200; // ≤200 m² uchun belgilangan minimum
}

// ────────────────────────────────────────────────────────────────────────
// Dizayn loyihasi
// ────────────────────────────────────────────────────────────────────────

enum DizaynObjectType {
  turar('Turar'),
  noturar('Noturar');

  const DizaynObjectType(this.label);
  final String label;
}

enum DizaynStyle {
  highTech('High-tech'),
  klassik('Klassik'),
  neoklassik('Neoklassik'),
  minimalizm('Minimalizm'),
  loft('Loft'),
  japandi('Japandi');

  const DizaynStyle(this.label);
  final String label;
}

// ────────────────────────────────────────────────────────────────────────
// Ta'mirlash va qurilish ishlari
// ────────────────────────────────────────────────────────────────────────

enum TamirlashObjectType {
  turar('Turar'),
  noturar('Noturar');

  const TamirlashObjectType(this.label);
  final String label;
}

enum TamirlashLocation {
  toshkentShahar('Toshkent shahar'),
  toshkentViloyat('Toshkent viloyat'),
  boshqa('Boshqa viloyat');

  const TamirlashLocation(this.label);
  final String label;
}

enum TamirlashServiceType {
  tamir("Ta'mir", 5000000),
  qurilish('Qurilish', 2400000);

  const TamirlashServiceType(this.label, this.pricePerM2);
  final String label;
  final int pricePerM2;
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
  final String note; // e.g. "QQS bilan"
  final List<CalculatorLine> lines;
}

class CalculatorLine {
  const CalculatorLine(this.label, this.value);
  final String label;
  final String value;
}

// ────────────────────────────────────────────────────────────────────────
// Compute functions
// ────────────────────────────────────────────────────────────────────────

CalculatorResult computeArxitektura({
  required ArxitekturaObject objectType,
  required double areaM2,
}) {
  final rate = objectType.pricePerM2;
  final total = (areaM2 * rate).round();
  return CalculatorResult(
    categoryTitle: CalculatorCategory.arxitektura.title,
    totalUzs: total,
    note: 'QQS bilan',
    lines: [
      CalculatorLine('Tanlangan turi', objectType.label),
      CalculatorLine('Maydon', '${_fmtArea(areaM2)} m²'),
      CalculatorLine('1 m² uchun', _fmtUzs(rate)),
    ],
  );
}

CalculatorResult computeKadastr({
  required KadastrObjectType objectType,
  required double areaM2,
  required bool is3d,
}) {
  final categoryTitle = is3d
      ? CalculatorCategory.kadastr3d.title
      : CalculatorCategory.kadastr.title;

  int total;
  String tierLabel;

  switch (objectType) {
    case KadastrObjectType.xonadon:
      total = is3d ? 9800000 : 4900000;
      tierLabel = 'Belgilangan narx';
    case KadastrObjectType.yakka:
      final tiers = is3d
          ? const [
              (300, 9800000, '300 m² gacha'),
              (500, 19800000, '300–500 m²'),
              (1000, 30800000, '500–1 000 m²'),
              (3000, 40800000, '1 000–3 000 m²'),
              (5000, 50800000, '3 000–5 000 m²'),
            ]
          : const [
              (300, 4900000, '300 m² gacha'),
              (500, 9900000, '300–500 m²'),
              (1000, 14900000, '500–1 000 m²'),
              (3000, 19900000, '1 000–3 000 m²'),
              (5000, 24900000, '3 000–5 000 m²'),
            ];
      final lastPrice = is3d ? 50800000 : 29900000;
      const lastLabel = '5 000 m² dan ortiq';
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
                ? 20000
                : areaM2 <= 25000
                ? 15000
                : 10000)
          : 7500;
      total = (areaM2 * perM2).round();
      tierLabel = '${_fmtUzs(perM2)} × m²';
  }

  return CalculatorResult(
    categoryTitle: categoryTitle,
    totalUzs: total,
    note: 'QQS bilan',
    lines: [
      CalculatorLine('Tanlangan turi', objectType.label),
      CalculatorLine('Maydon', '${_fmtArea(areaM2)} m²'),
      CalculatorLine('Tarif', tierLabel),
    ],
  );
}

CalculatorResult computeBaholash({
  required BaholashObject objectType,
  required double areaM2,
}) {
  final rate = objectType.pricePerM2;
  final byArea = (areaM2 * rate).round();
  int total;
  String calc;

  if (areaM2 <= 200 && objectType.minFor200 != null) {
    total = objectType.minFor200!;
    calc = '200 m² gacha belgilangan minimum';
  } else {
    total = byArea;
    calc = '${_fmtUzs(rate)} × ${_fmtArea(areaM2)}';
  }

  return CalculatorResult(
    categoryTitle: CalculatorCategory.baholash.title,
    totalUzs: total,
    note: 'QQS bilan',
    lines: [
      CalculatorLine('Tanlangan turi', objectType.label),
      CalculatorLine('Maydon', '${_fmtArea(areaM2)} m²'),
      CalculatorLine('Hisob', calc),
    ],
  );
}

CalculatorResult computeDizayn({
  required DizaynObjectType objectType,
  required DizaynStyle style,
  required double areaM2,
}) {
  final rate = areaM2 <= 100 ? 180000 : 130000;
  final total = (areaM2 * rate).round();
  final tierLabel = areaM2 <= 100 ? '100 m² gacha' : '100 m² dan ortiq';

  return CalculatorResult(
    categoryTitle: CalculatorCategory.dizayn.title,
    totalUzs: total,
    note: 'QQS bilan',
    lines: [
      CalculatorLine('Ob\'ekt turi', objectType.label),
      CalculatorLine('Dizayn uslubi', style.label),
      CalculatorLine('Maydon', '${_fmtArea(areaM2)} m² ($tierLabel)'),
      CalculatorLine('1 m² uchun', _fmtUzs(rate)),
    ],
  );
}

CalculatorResult computeTamirlash({
  required TamirlashObjectType objectType,
  required TamirlashLocation location,
  required TamirlashServiceType serviceType,
  required double areaM2,
}) {
  final rate = serviceType.pricePerM2;
  final total = (areaM2 * rate).round();
  return CalculatorResult(
    categoryTitle: CalculatorCategory.tamirlash.title,
    totalUzs: total,
    note: 'QQS bilan',
    lines: [
      CalculatorLine('Xizmat turi', serviceType.label),
      CalculatorLine('Ob\'ekt turi', objectType.label),
      CalculatorLine('Manzil', location.label),
      CalculatorLine('Maydon', '${_fmtArea(areaM2)} m²'),
      CalculatorLine('1 m² uchun', _fmtUzs(rate)),
    ],
  );
}

// ────────────────────────────────────────────────────────────────────────
// Helpers (also used by result screen via re-export)
// ────────────────────────────────────────────────────────────────────────

String fmtUzsPublic(int value) => _fmtUzs(value);

String _fmtUzs(int value) {
  final sign = value < 0 ? '-' : '';
  final s = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return "$sign${buf.toString()} so'm";
}

String _fmtArea(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
