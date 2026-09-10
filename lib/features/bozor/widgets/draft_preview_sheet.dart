/// "Oldindan ko'rish" varag'i — qoralamadagi hamma narsani bir joyda
/// ko'rsatadi.
///
/// DIZAYNDA BU EKRAN YO'Q: «Предпросмотр» tugmasi bor, u nima ochishi hech
/// qayerda chizilmagan. Marketdagi `listing_detail_screen` ni ishlatib
/// bo'lmaydi — u backend modelini kutadi, bizda esa hali lokal qoralama.
/// Shu sababli bu yerda oddiy xulosa varag'i: tugma o'lik qolgandan ko'ra
/// foydalanuvchi yuborishdan oldin nima kiritganini tekshira olgani yaxshi.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../models/bozor_draft.dart';
import '../models/param_schema.dart';

Future<void> showDraftPreviewSheet(BuildContext context, BozorDraft draft) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DraftPreviewSheet(draft: draft),
  );
}

class _DraftPreviewSheet extends StatelessWidget {
  const _DraftPreviewSheet({required this.draft});

  final BozorDraft draft;

  @override
  Widget build(BuildContext context) {
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
                    _Row(
                      tr(l, 'bozor.price.rent'),
                      p.amount.isEmpty ? null : '${p.amount} ${p.unit}',
                    ),
                    if (p.dailyAmount.isNotEmpty)
                      _Row(
                        tr(l, 'bozor.price.daily'),
                        '${p.dailyAmount} ${p.dailyUnit}',
                      ),
                    // 3-qadamdagi to'ldirilgan parametrlar.
                    if (type != null)
                      for (final f in type.paramFields)
                        if (_value(draft.params[f.key]) != null)
                          _Row(tr(l, f.labelKey), _value(draft.params[f.key])),
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
  static String? _value(Object? v) {
    if (v == null) return null;
    if (v is bool) return v ? '✓' : null;
    if (v is List) return v.isEmpty ? null : v.join(', ');
    final s = v.toString().trim();
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
