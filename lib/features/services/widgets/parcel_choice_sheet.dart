/// Bitta nuqtada bir nechta uchastka topilganda — qaysi biri kerakligini
/// so'raydigan varaq.
///
/// Bunday holat kam emas: bo'lingan hovli, bino va uning ostidagi yer
/// uchastkasi, xatlovdan o'tmagan chegara — hammasi bir nuqtada kesishadi.
/// Geoportalning o'zi ham ularni `‹ 1/3 ›` sahifalagichi bilan ko'rsatadi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../data/ngis_parcel_client.dart';

/// Tanlangan uchastkani qaytaradi; bekor qilinsa `null`.
Future<NgisParcel?> showParcelChoiceSheet(
  BuildContext context, {
  required List<NgisParcel> parcels,
}) {
  return showModalBottomSheet<NgisParcel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ParcelChoiceSheet(parcels: parcels),
  );
}

class _ParcelChoiceSheet extends StatelessWidget {
  const _ParcelChoiceSheet({required this.parcels});

  final List<NgisParcel> parcels;

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: subColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr(l, 'services.ai.parcel.choose_title'),
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w900,
                fontSize: 19,
                height: 1.2,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(l, 'services.ai.parcel.choose_body'),
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 13,
                height: 1.4,
                color: subColor,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: parcels.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ParcelRow(
                  parcel: parcels[i],
                  isDark: isDark,
                  locale: l,
                  onTap: () => Navigator.of(context).pop(parcels[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParcelRow extends StatelessWidget {
  const _ParcelRow({
    required this.parcel,
    required this.isDark,
    required this.locale,
    required this.onTap,
  });

  final NgisParcel parcel;
  final bool isDark;
  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final place = parcel.placeLabel;

    return Material(
      color: isDark ? const Color(0xFF171B1D) : const Color(0xFFF6F7F8),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parcel.cadastreNumber,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr(locale, 'services.ai.parcel.layer.${parcel.layerId}'),
                      style: const TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.splashGreen,
                      ),
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        place,
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 12,
                          height: 1.35,
                          color: subColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: subColor),
            ],
          ),
        ),
      ),
    );
  }
}
