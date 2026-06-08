/// Onlayn kalkulyator narxlari — backend'dan olinadi, keshlanadi.
///
/// Narxlar avval `calculator_draft.dart` ichida hard-code edi. Endi ular
/// backend `calculator_prices` jadvalida (adminkadan tahrirlanadi) va mobil
/// ilova `GET /api/v1/calculator/pricing` orqali oladi. Bu yerdagi [defaults]
/// — hujjatdagi (`online calculator.doc`) joriy qiymatlar; backend yetib
/// bormaganda yoki birinchi ishga tushishda ishlatiladi (offline xavfsiz).
library;

import 'package:flutter/material.dart';

/// Yuridik (faqat ko'rsatiladigan) narx satri — til bo'yicha qiymat.
@immutable
class YuridikLine {
  const YuridikLine({required this.key, required this.value});

  final String key;
  final Map<String, String> value; // {'uz':..,'ru':..,'en':..}

  String localized(Locale l) => value[l.languageCode] ?? value['uz'] ?? '';

  factory YuridikLine.fromJson(Map<String, dynamic> j) {
    final v = (j['value'] as Map?) ?? const {};
    return YuridikLine(
      key: j['key'] as String,
      value: {
        for (final loc in const ['uz', 'ru', 'en'])
          if (v[loc] != null) loc: v[loc] as String,
      },
    );
  }
}

/// Kalkulyator narxlari. [rate] kalit bo'yicha summani qaytaradi (topilmasa
/// default). [defaults] hech qachon bo'sh emas — ekranlar null tekshirmaydi.
@immutable
class CalculatorPricing {
  const CalculatorPricing({
    required this.rates,
    required this.yuridik,
    this.version,
  });

  /// key → narx (so'm). Masalan `rates['arxitektura.yakka_small'] == 36000`.
  final Map<String, num> rates;
  final List<YuridikLine> yuridik;

  /// Eng so'nggi `updated_at` (backend) — kesh yangiligini bilish uchun.
  final String? version;

  /// Narx; topilmasa default qiymatga tushadi (har doim mavjud).
  num rate(String key) => rates[key] ?? _defaultRates[key] ?? 0;

  /// Yuridik satr matni (key bo'yicha); topilmasa default.
  String yuridikValue(String key, Locale l) {
    for (final line in yuridik) {
      if (line.key == key) return line.localized(l);
    }
    for (final line in _defaultYuridikLines) {
      if (line.key == key) return line.localized(l);
    }
    return '';
  }

  factory CalculatorPricing.fromJson(Map<String, dynamic> j) {
    final r = (j['rates'] as Map?) ?? const {};
    final y = (j['yuridik'] as List?) ?? const [];
    return CalculatorPricing(
      version: j['version'] as String?,
      rates: {
        for (final e in r.entries) e.key as String: e.value as num,
      },
      yuridik: [
        for (final item in y)
          YuridikLine.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'rates': rates,
        'yuridik': [
          for (final line in yuridik) {'key': line.key, 'value': line.value},
        ],
      };

  /// Hard-code default — `online calculator.doc` qiymatlari (backend bilan bir xil seed).
  static const CalculatorPricing defaults = CalculatorPricing(
    rates: _defaultRates,
    yuridik: _defaultYuridikLines,
  );
}

// ────────────────────────────────────────────────────────────────────────
// Default narxlar (offline / fallback) — backend seed bilan AYNAN bir xil.
// ────────────────────────────────────────────────────────────────────────

const Map<String, num> _defaultRates = {
  // Arxitektura (1 m²)
  'arxitektura.yakka_small': 36000,
  'arxitektura.yakka_large': 60000,
  'arxitektura.kop_qavatli': 84000,
  'arxitektura.jamoat': 108000,
  'arxitektura.sanoat': 60000,
  'arxitektura.rekonstruksiya': 72000,
  // Kadastr
  'kadastr.xonadon': 4900000,
  'kadastr.yakka.le300': 4900000,
  'kadastr.yakka.le500': 9900000,
  'kadastr.yakka.le1000': 14900000,
  'kadastr.yakka.le3000': 19900000,
  'kadastr.yakka.le5000': 24900000,
  'kadastr.yakka.gt5000': 29900000,
  'kadastr.kop_kvartirali.per_m2': 7500,
  // 3D Kadastr
  'kadastr3d.xonadon': 9800000,
  'kadastr3d.yakka.le300': 9800000,
  'kadastr3d.yakka.le500': 19800000,
  'kadastr3d.yakka.le1000': 30800000,
  'kadastr3d.yakka.le3000': 40800000,
  'kadastr3d.yakka.le5000': 50800000,
  'kadastr3d.yakka.gt5000': 50800000,
  'kadastr3d.kop_kvartirali.le10000': 20000,
  'kadastr3d.kop_kvartirali.le25000': 15000,
  'kadastr3d.kop_kvartirali.gt25000': 10000,
  // Baholash
  'baholash.uy_joy.per_m2': 6000,
  'baholash.uy_joy.min200': 490000,
  'baholash.tijorat.per_m2': 10000,
  'baholash.tijorat.min200': 990000,
  'baholash.tugallanmagan.per_m2': 15000,
  // Dizayn
  'dizayn.le100.per_m2': 180000,
  'dizayn.gt100.per_m2': 130000,
  // Ta'mirlash
  'tamirlash.tamir.per_m2': 5000000,
  'tamirlash.qurilish.per_m2': 2400000,
};

const List<YuridikLine> _defaultYuridikLines = [
  YuridikLine(key: 'yuridik.maslahat', value: {
    'uz': "500 000 so'm",
    'ru': '500 000 сум',
    'en': '500,000 UZS',
  }),
  YuridikLine(key: 'yuridik.hujjat', value: {
    'uz': "1 500 000 so'm",
    'ru': '1 500 000 сум',
    'en': '1,500,000 UZS',
  }),
  YuridikLine(key: 'yuridik.sud', value: {
    'uz': "5 000 000 – 20 000 000 so'm",
    'ru': '5 000 000 – 20 000 000 сум',
    'en': '5,000,000 – 20,000,000 UZS',
  }),
  YuridikLine(key: 'yuridik.autsorsing', value: {
    'uz': "2 000 000 – 20 000 000 so'm/oy",
    'ru': '2 000 000 – 20 000 000 сум/мес',
    'en': '2,000,000 – 20,000,000 UZS/month',
  }),
  YuridikLine(key: 'yuridik.royxat', value: {
    'uz': "3 000 000 so'm",
    'ru': '3 000 000 сум',
    'en': '3,000,000 UZS',
  }),
  YuridikLine(key: 'yuridik.qarz', value: {
    'uz': '5–20% komissiya',
    'ru': '5–20% комиссия',
    'en': '5–20% commission',
  }),
];
