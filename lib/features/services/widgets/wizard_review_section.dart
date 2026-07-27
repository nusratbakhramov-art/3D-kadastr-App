/// TZ wizardlarining "Tekshirish" (Preview) ekrani uchun umumiy kartochka.
///
/// Har bo'lim sarlavhasi yonida qalamcha ("✎") bo'ladi — `onEdit` orqali o'sha
/// step to'g'ridan-to'g'ri tahrirga ochiladi va saqlangach Preview'ga qaytadi.
/// Arxitektura va Dizayn wizardlari shu bitta primitivni ishlatadi.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';

class WizardReviewSection extends StatelessWidget {
  const WizardReviewSection({
    super.key,
    required this.title,
    required this.onEdit,
    this.rows = const [],
    this.chips = const [],
    this.warning,
  });

  final String title;
  final VoidCallback onEdit;

  /// (label, value) juftliklari. Bo'sh `value` qatorlari ko'rsatilmaydi.
  final List<(String, String)> rows;

  /// Tanlangan boolean xususiyatlar (faqat yoqilganlari) chip ko'rinishida.
  final List<String> chips;

  /// To'ldirilmagan majburiy maydon bo'lsa — qizil ramka + izoh.
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final labelColor =
        isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    final isEmpty = rows.every((r) => r.$2.trim().isEmpty) && chips.isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: warning != null ? const Color(0xFFE0492A) : border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: titleColor,
                  ),
                ),
              ),
              InkWell(
                onTap: hapticTap(onEdit),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 19,
                    color: AppColors.splashGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text(
                _notFilled(Localizations.localeOf(context)),
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 13.5,
                  color: labelColor,
                ),
              ),
            ),
          for (final (label, value) in rows)
            if (value.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 13,
                          color: labelColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 6,
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: valueColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ch in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.splashGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        ch,
                        style: const TextStyle(
                          fontFamily: 'MTSText',
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          color: AppColors.splashGreen,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 10),
              child: Text(
                warning!,
                style: const TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 12.5,
                  color: Color(0xFFE0492A),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _notFilled(Locale l) =>
      tr(l, 'services.widget.wizard_review.not_filled');
}

/// Buyurtmachi bo'limi oxirgi arizadan to'ldirilganini bildiruvchi yumshoq izoh.
class WizardPrefillHint extends StatelessWidget {
  const WizardPrefillHint({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.splashGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded,
              size: 17, color: AppColors.splashGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'MTSText',
                fontSize: 12.5,
                color: AppColors.splashGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
