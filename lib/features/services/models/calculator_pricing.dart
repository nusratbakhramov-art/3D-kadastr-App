/// Onlayn kalkulyator narxlari — backend'dan olinadi, keshlanadi.
///
/// Narxlar avval `calculator_draft.dart` ichida hard-code edi. Endi ular
/// backend `calculator_prices` jadvalida (adminkadan tahrirlanadi) va mobil
/// ilova `GET /api/v1/calculator/pricing` orqali oladi. Bu yerdagi [defaults]
/// — hujjatdagi (`online calculator.doc`) joriy qiymatlar; backend yetib
/// bormaganda yoki birinchi ishga tushishda ishlatiladi (offline xavfsiz).
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';

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

/// Kalkulyator tanlov varianti (rang / uslub / material) — adminkadan
/// tahrirlanadi, mobil ilova backend'dan oladi. `meta` ranglar uchun hex.
@immutable
class CalcOption {
  const CalcOption({required this.value, required this.label, this.meta});

  /// Mashina qiymati: 'high_tech', 'oq', 'gisht' …
  final String value;
  final Map<String, String> label; // {'uz':..,'ru':..,'en':..}
  final String? meta; // ranglar uchun '#RRGGBB', aks holda null

  String localized(Locale l) => label[l.languageCode] ?? label['uz'] ?? value;

  /// Hex `meta` → Color (ranglar uchun). Noto'g'ri bo'lsa null.
  Color? get color {
    final m = meta;
    if (m == null) return null;
    final hex = m.replaceAll('#', '').trim();
    final v = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    return v == null ? null : Color(0xFF000000 | v);
  }

  factory CalcOption.fromJson(Map<String, dynamic> j) {
    final lbl = (j['label'] as Map?) ?? const {};
    return CalcOption(
      value: j['value'] as String,
      label: {
        for (final loc in const ['uz', 'ru', 'en'])
          if (lbl[loc] != null) loc: lbl[loc] as String,
      },
      meta: j['meta'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'label': label,
        if (meta != null) 'meta': meta,
      };
}

/// Bitta tarif pog'onasi (progressiv shkala) — obyekt qiymatining shu oraliqqa
/// tushgan qismi uchun narx. [upto] — pog'ona yuqori chegarasi (so'mda);
/// `null` = cheksiz (oxirgi pog'ona).
///
/// [kind] `'fixed'` — oraliqqa tushgan har qanday obyekt uchun qat'iy summa
/// ([value] so'mda). `'percent'` — oraliqdagi qismning ulushi ([value] kasr
/// ko'rinishida: 0.001 = 0,1%).
@immutable
class TariffBand {
  const TariffBand({required this.upto, required this.kind, required this.value});

  final num? upto;
  final String kind; // 'fixed' | 'percent'
  final num value;

  bool get isFixed => kind == 'fixed';

  factory TariffBand.fromJson(Map<String, dynamic> j) => TariffBand(
        upto: j['upto'] as num?,
        kind: (j['kind'] as String?) ?? 'percent',
        value: (j['value'] as num?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'upto': upto,
        'kind': kind,
        'value': value,
      };
}

/// Kalkulyator narxlari. [rate] kalit bo'yicha summani qaytaradi (topilmasa
/// default). [defaults] hech qachon bo'sh emas — ekranlar null tekshirmaydi.
@immutable
class CalculatorPricing {
  const CalculatorPricing({
    required this.rates,
    required this.yuridik,
    this.options = const {},
    this.scales = const {},
    this.version,
  });

  /// key → narx (so'm). Masalan `rates['arxitektura.yakka_small'] == 36000`.
  final Map<String, num> rates;
  final List<YuridikLine> yuridik;

  /// guruh → variantlar (rang/uslub/material). Masalan `options['colors']`.
  final Map<String, List<CalcOption>> options;

  /// shkala kaliti → progressiv tarif pog'onalari. Masalan
  /// `scales['buxgalteriya.value_scale']`.
  final Map<String, List<TariffBand>> scales;

  /// Eng so'nggi `updated_at` (backend) — kesh yangiligini bilish uchun.
  final String? version;

  /// Guruh variantlari; backend bo'sh/yetib bormagan bo'lsa default'ga tushadi.
  List<CalcOption> optionsFor(String group) {
    final r = options[group];
    if (r != null && r.isNotEmpty) return r;
    return _defaultOptions[group] ?? const [];
  }

  /// Narx; topilmasa default qiymatga tushadi (har doim mavjud).
  num rate(String key) => rates[key] ?? _defaultRates[key] ?? 0;

  /// Progressiv shkala pog'onalari; backend bermagan bo'lsa — default.
  List<TariffBand> scale(String key) {
    final r = scales[key];
    if (r != null && r.isNotEmpty) return r;
    return _defaultScales[key] ?? const [];
  }

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
    final o = (j['options'] as Map?) ?? const {};
    final sc = (j['scales'] as Map?) ?? const {};
    return CalculatorPricing(
      version: j['version'] as String?,
      rates: {
        for (final e in r.entries) e.key as String: e.value as num,
      },
      yuridik: [
        for (final item in y)
          YuridikLine.fromJson(item as Map<String, dynamic>),
      ],
      options: {
        for (final e in o.entries)
          e.key as String: [
            for (final item in (e.value as List? ?? const []))
              CalcOption.fromJson(item as Map<String, dynamic>),
          ],
      },
      scales: {
        for (final e in sc.entries)
          e.key as String: [
            for (final item in (e.value as List? ?? const []))
              TariffBand.fromJson(item as Map<String, dynamic>),
          ],
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'rates': rates,
        'yuridik': [
          for (final line in yuridik) {'key': line.key, 'value': line.value},
        ],
        'options': {
          for (final e in options.entries)
            e.key: [for (final o in e.value) o.toJson()],
        },
        'scales': {
          for (final e in scales.entries)
            e.key: [for (final b in e.value) b.toJson()],
        },
      };

  /// Hard-code default — `online calculator.doc` qiymatlari (backend bilan bir xil seed).
  static final CalculatorPricing defaults = CalculatorPricing(
    rates: _defaultRates,
    yuridik: _defaultYuridikLines,
    options: _defaultOptions,
    scales: _defaultScales,
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

/// Backend-driven label map for a default (offline fallback) entry — the three
/// language values are sourced from the translation bundle, not hard-coded.
Map<String, String> _trMap(String key) => {
      for (final loc in const ['uz', 'ru', 'en']) loc: tr(Locale(loc), key),
    };

final List<YuridikLine> _defaultYuridikLines = [
  YuridikLine(
      key: 'yuridik.maslahat',
      value: _trMap('services.model.yuridik.maslahat')),
  YuridikLine(
      key: 'yuridik.hujjat', value: _trMap('services.model.yuridik.hujjat')),
  YuridikLine(
      key: 'yuridik.sud', value: _trMap('services.model.yuridik.sud')),
  YuridikLine(
      key: 'yuridik.autsorsing',
      value: _trMap('services.model.yuridik.autsorsing')),
  YuridikLine(
      key: 'yuridik.royxat', value: _trMap('services.model.yuridik.royxat')),
  YuridikLine(
      key: 'yuridik.qarz', value: _trMap('services.model.yuridik.qarz')),
];

// ────────────────────────────────────────────────────────────────────────
// Default optionlar (ranglar / uslublar / materiallar) — backend
// `calculator_options` seed bilan AYNAN bir xil. Adminkadan tahrirlanadi;
// backend yetib bormaganda shu ro'yxat ishlatiladi.
// ────────────────────────────────────────────────────────────────────────

CalcOption _o(String value, String key, [String? meta]) =>
    CalcOption(value: value, label: _trMap(key), meta: meta);

final Map<String, List<CalcOption>> _defaultOptions = {
  'colors': [
    _o('oq', 'services.model.color.oq', '#FFFFFF'),
    _o('bej', 'services.model.color.bej', '#E6D8C3'),
    _o('kulrang', 'services.model.color.kulrang', '#9AA0A6'),
    _o('qora', 'services.model.color.qora', '#222222'),
    _o('jigarrang', 'services.model.color.jigarrang', '#8B5A2B'),
    _o('yogoch', 'services.model.color.yogoch', '#C89B6C'),
    _o('kok', 'services.model.color.kok', '#2F6FED'),
    _o('moviy', 'services.model.color.moviy', '#56CCF2'),
    _o('yashil', 'services.model.color.yashil', '#3BA55D'),
    _o('sariq', 'services.model.color.sariq', '#F2C94C'),
    _o('toq_sariq', 'services.model.color.toq_sariq', '#E8821E'),
    _o('qizil', 'services.model.color.qizil', '#E0492A'),
    _o('pushti', 'services.model.color.pushti', '#E58FB0'),
    _o('binafsha', 'services.model.color.binafsha', '#7C5CBF'),
  ],
  'arxitektura.style': [
    _o('high_tech', 'services.model.style.high_tech'),
    _o('klassik', 'services.model.style.klassik'),
    _o('neoklassik', 'services.model.style.neoklassik'),
    _o('minimalizm', 'services.model.style.minimalizm'),
    _o('loft', 'services.model.style.loft'),
  ],
  'arxitektura.facade_material': [
    _o('gisht', 'services.model.material.gisht'),
    _o('tosh', 'services.model.material.tosh'),
    _o('kompozit', 'services.model.material.kompozit'),
    _o('shisha', 'services.model.material.shisha'),
    _o('boyoq', 'services.model.material.boyoq_facade'),
  ],
  'dizayn.interior.style': [
    _o('high_tech', 'services.model.style.high_tech'),
    _o('klassik', 'services.model.style.klassik'),
    _o('neoklassik', 'services.model.style.neoklassik'),
    _o('minimalizm', 'services.model.style.minimalizm'),
    _o('loft', 'services.model.style.loft'),
    _o('boshqa', 'services.model.opt.boshqa'),
  ],
  'dizayn.interior.material': [
    _o('boyoq', 'services.model.material.boyoq'),
    _o('tosh', 'services.model.material.tosh'),
    _o('kompozit', 'services.model.material.kompozit'),
    _o('shisha', 'services.model.material.shisha'),
    _o('bambuk', 'services.model.material.bambuk'),
  ],
  'dizayn.floor_material': [
    _o('laminat', 'services.model.material.laminat'),
    _o('tosh', 'services.model.material.tosh'),
    _o('kafel', 'services.model.material.kafel'),
    _o('boshqa', 'services.model.opt.boshqa'),
  ],
  'dizayn.exterior.style': [
    _o('high_tech', 'services.model.style.high_tech'),
    _o('klassik', 'services.model.style.klassik'),
    _o('neoklassik', 'services.model.style.neoklassik'),
    _o('minimalizm', 'services.model.style.minimalizm'),
    _o('loft', 'services.model.style.loft'),
    _o('modern', 'services.model.style.modern'),
  ],
  'dizayn.exterior.material': [
    _o('boyoq', 'services.model.material.boyoq'),
    _o('tosh', 'services.model.material.tosh'),
    _o('kompozit', 'services.model.material.kompozit'),
    _o('shisha', 'services.model.material.shisha'),
  ],
};

// ────────────────────────────────────────────────────────────────────────
// Progressiv tarif shkalalari (offline / fallback) — backend seed bilan bir xil.
//
// Qurilish buxgalteriyasi: xizmat haqi obyekt qiymatiga qarab pog'onali
// hisoblanadi (daromad solig'i kabi) — har pog'ona faqat O'ZIGA tushgan
// qismdan olinadi, natijalar qo'shiladi. 1-pog'ona qat'iy 6 mln so'm, ya'ni
// eng kichik obyekt uchun ham minimal haq.
// ────────────────────────────────────────────────────────────────────────

const String kBuxgalteriyaValueScaleKey = 'buxgalteriya.value_scale';

const Map<String, List<TariffBand>> _defaultScales = {
  kBuxgalteriyaValueScaleKey: [
    TariffBand(upto: 1000000000, kind: 'fixed', value: 6000000), // 1,0 mlrd gacha
    TariffBand(upto: 5000000000, kind: 'percent', value: 0.001), // 1,0–5,0
    TariffBand(upto: 10000000000, kind: 'percent', value: 0.0006), // 5,0–10,0
    TariffBand(upto: 20000000000, kind: 'percent', value: 0.0004), // 10,0–20,0
    TariffBand(upto: 50000000000, kind: 'percent', value: 0.0002), // 20,0–50,0
    TariffBand(upto: 100000000000, kind: 'percent', value: 0.00015), // 50,0–100,0
    TariffBand(upto: null, kind: 'percent', value: 0.0001), // 100,0 dan yuqori
  ],
};
