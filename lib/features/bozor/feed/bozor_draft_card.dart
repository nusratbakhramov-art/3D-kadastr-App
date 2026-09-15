/// Tugatilmagan qoralama kartasi.
///
/// E'lon kartasidan ATAYLAB boshqacha ko'rinadi: rasm yo'q (qoralamada faqat
/// qurilma yo'llari bor, ular URL emas), chap chetida chiziq va "Tugatilmagan"
/// nishoni. Foydalanuvchi ro'yxatda qoralamani e'londan bir ko'rishda
/// ajratishi kerak — aks holda "nega e'lonim lentada yo'q?" savoli tug'iladi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/color_tokens.dart';
import '../data/bozor_draft_codec.dart';
import '../models/bozor_listing.dart';

class BozorDraftCard extends StatelessWidget {
  const BozorDraftCard({
    super.key,
    required this.draft,
    required this.onTap,
    required this.onDelete,
  });

  final BozorDraftSummary draft;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF121617) : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textBlack;
    final meta = ColorTokens.secondaryText(context);

    // Sarlavha ham, manzil ham payload'dan olinadi va YO'Q bo'lishi mumkin
    // (foydalanuvchi 1-qadamda chiqib ketgan) — bunda o'rniga izoh chiqadi.
    final title = draft.title ?? tr(l, 'bozor.draft.untitled');
    final subtitle = draft.address;
    // Tahrir-qoralamasi ro'yxatda ASL e'lon bilan YONMA-YON turadi, ya'ni
    // «Tugatilmagan» nishoni bilan u nusxa yaratilgandek ko'rinardi. Bu yerda
    // nishon matni ayiradi: bosilganda yangi e'lon emas, o'sha e'lon
    // tahrirlanadi.
    final badge = editingListingIdOf(draft) != null
        ? 'bozor.draft.badge_editing'
        : 'bozor.draft.badge';

    return Material(
      color: card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: isDark
                ? null
                : const Border.fromBorderSide(
                    BorderSide(color: Color(0xFFE3E5E8)),
                  ),
            // Chap chetdagi sariq chiziq — "tugatilmagan" belgisi.
            gradient: LinearGradient(
              colors: [
                const Color(0xFFE8A33D).withValues(alpha: 0.18),
                card,
              ],
              stops: const [0.012, 0.012],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8A33D).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tr(l, badge),
                          style: const TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: Color(0xFFB9761C),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.25,
                          color: fg,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 13,
                            color: meta,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        tr(l, 'bozor.draft.continue'),
                        style: const TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.splashGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: tr(l, 'bozor.draft.delete'),
                  icon: Icon(Icons.delete_outline_rounded, color: meta),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
