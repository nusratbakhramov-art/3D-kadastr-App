/// "Oldindan ko'rish" varag'i — qoralamadagi hamma narsani bir joyda
/// ko'rsatadi.
///
/// DIZAYNDA BU EKRAN YO'Q: «Предпросмотр» tugmasi bor, u nima ochishi hech
/// qayerda chizilmagan. Marketdagi `listing_detail_screen` ni ishlatib
/// bo'lmaydi — u backend modelini kutadi, bizda esa hali lokal qoralama.
/// Shu sababli bu yerda oddiy xulosa varag'i: tugma o'lik qolgandan ko'ra
/// foydalanuvchi yuborishdan oldin nima kiritganini tekshira olgani yaxshi.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../data/param_options.dart';
import '../models/bozor_draft.dart';
import '../models/param_schema.dart';
import 'amount_input_formatter.dart';

Future<void> showDraftPreviewSheet(BuildContext context, BozorDraft draft) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DraftPreviewSheet(draft: draft),
  );
}

class _DraftPreviewSheet extends StatefulWidget {
  const _DraftPreviewSheet({required this.draft});

  final BozorDraft draft;

  @override
  State<_DraftPreviewSheet> createState() => _DraftPreviewSheetState();
}

class _DraftPreviewSheetState extends State<_DraftPreviewSheet> {
  /// Ro'yxat kaliti → (kod → yorliq).
  ///
  /// ⚠️ NEGA KERAK. Qoralamada select maydonlarning QIYMATI — kod
  /// (`individual_housing`, `detached`, `combined`), yorliq emas
  /// (`param_options.dart` dagi izohga qarang). Oldindan ko'rishda kod
  /// to'g'ridan-to'g'ri chizilardi va foydalanuvchi e'lon qanday
  /// ko'rinishini tekshirmoqchi bo'lganda ingliz tilidagi texnik kodni
  /// ko'rardi. Yorliqlar backenddan keladi va adminkadan tahrirlanadi.
  Map<String, Map<String, String>> _labels = const {};

  bool _requested = false;

  // ⚠️ `initState` EMAS. Yuklash uchun til kerak, til esa
  // `Localizations.localeOf(context)` dan olinadi — bu `initState` da
  // taqiqlangan (InheritedWidget hali ulanmagan) va istisno tashlaydi.
  // `unawaited` uni jimgina yutib yuborardi: yorliqlar hech qachon
  // kelmasdi, ekranda esa kodlar qolaverardi.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    unawaited(_loadLabels());
  }

  Future<void> _loadLabels() async {
    final type = widget.draft.type;
    if (type == null) return;
    final keys = {
      for (final f in type.paramFields)
        if (f.optionsKey != null) f.optionsKey!,
    };
    if (keys.isEmpty) return;
    final repo = ApiParamOptions(
      locale: Localizations.localeOf(context).languageCode,
    );
    final out = <String, Map<String, String>>{};
    for (final k in keys) {
      try {
        final list = await repo.options(k);
        out[k] = {for (final o in list) o.code: o.label};
      } catch (_) {
        // Yorliq kelmasa kod ko'rinadi — ya'ni avvalgi xulq, xatosiz.
      }
    }
    if (mounted && out.isNotEmpty) setState(() => _labels = out);
  }

  /// Kodni yorliqqa aylantiradi; yorliq yo'q bo'lsa kodning o'zi qoladi.
  String _label(String? optionsKey, String code) =>
      _labels[optionsKey]?[code] ?? code;

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final type = draft.type;
    final a = draft.address;
    final p = draft.price;
    final d = draft.description;
    final c = draft.contacts;

    final photos = [...d.planFiles, ...d.photos, ...d.panoramas];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : const Color(0xFFD9DEE1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                tr(l, 'bozor.terms.preview'),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (photos.isNotEmpty) ...[
                      SizedBox(
                        height: 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(photos[i]),
                              width: 128,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(
                                width: 128,
                                child: Icon(Icons.insert_drive_file_rounded),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _Row(tr(l, 'bozor.field.deal_type'), draft.deal?.label(l)),
                    _Row(tr(l, 'bozor.field.property_type'), type?.label(l)),
                    _Row(
                      tr(l, 'bozor.address.title'),
                      [
                        a.regionName,
                        a.districtName,
                        if (a.address.isNotEmpty) a.address,
                      ].nonNulls.join(', '),
                    ),
                    // Narx GURUHLANGAN holda: qoralamada u xom raqam bo'lib
                    // yotadi (`5002323`), e'londa esa har doim ajratgich
                    // bilan chiqadi — oldindan ko'rish ikkinchisiga o'xshashi
                    // kerak, aks holda tekshiruvning ma'nosi yo'qoladi.
                    _Row(
                      tr(l, 'bozor.price.rent'),
                      p.amount.isEmpty
                          ? null
                          : '${groupDigits(digitsOnly(p.amount))} ${p.unit}',
                    ),
                    if (p.dailyAmount.isNotEmpty)
                      _Row(
                        tr(l, 'bozor.price.daily'),
                        '${groupDigits(digitsOnly(p.dailyAmount))} '
                        '${p.dailyUnit}',
                      ),
                    // 3-qadamdagi to'ldirilgan parametrlar.
                    if (type != null)
                      for (final f in type.paramFields)
                        if (_value(draft.params[f.key]) != null)
                          // Birlik BILAN: maydon formada «m²» yozuvi bilan
                          // kiritiladi, qoralama esa faqat sonni saqlaydi.
                          // Birliksiz ko'rsatilsa, e'lon oldidan «78,5» degan
                          // son turardi va uning m²mi yoki sotixmi ekani
                          // ma'lum bo'lmasdi — uy m², yer esa sotix bilan
                          // o'lchanadi (`cadastre_autofill.dart` ga qarang).
                          _Row(
                            tr(l, f.labelKey),
                            _valueWithUnit(
                              draft.params[f.key],
                              f.unit,
                              optionsKey: f.optionsKey,
                              label: _label,
                            ),
                          ),
                    _Row(
                      tr(l, 'bozor.desc.title'),
                      d.text.isEmpty ? null : d.text,
                    ),
                    _Row(tr(l, 'bozor.contacts.name'), c.name),
                    _Row(
                      tr(l, 'bozor.contacts.phone'),
                      c.phones.where((s) => s.isNotEmpty).isEmpty
                          ? null
                          : c.phones
                                .where((s) => s.isNotEmpty)
                                .map((s) => '+998 $s')
                                .join(', '),
                    ),
                    _Row(tr(l, 'bozor.contacts.email'), c.email),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Qiymatni matnga aylantiradi; bo'sh bo'lsa `null` (qator chizilmaydi).
  /// Qiymat + o'lchov birligi. Birlik faqat SON qiymatga qo'shiladi:
  /// belgilangan katakcha («✓») yoki ro'yxatga u mos kelmaydi.
  static String? _valueWithUnit(
    Object? v,
    String? unit, {
    String? optionsKey,
    String Function(String?, String)? label,
  }) {
    final s = _value(v, optionsKey: optionsKey, label: label);
    if (s == null || unit == null || unit.isEmpty) return s;
    if (v is bool || v is List) return s;
    return '$s $unit';
  }

  /// [label] berilsa KOD yorliqqa almashtiriladi (`combined` →
  /// «Sovmeshchennyy»). Ko'p tanlovli maydonda har bir element alohida
  /// almashtiriladi.
  static String? _value(
    Object? v, {
    String? optionsKey,
    String Function(String?, String)? label,
  }) {
    String show(Object? x) {
      final s = x?.toString().trim() ?? '';
      return label == null ? s : label(optionsKey, s);
    }

    if (v == null) return null;
    if (v is bool) return v ? '✓' : null;
    if (v is List) return v.isEmpty ? null : v.map(show).join(', ');
    final s = show(v);
    return s.isEmpty ? null : s;
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null || v.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 12,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            v,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
              height: 1.3,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
