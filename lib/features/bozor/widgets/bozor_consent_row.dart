/// "Shartlarga roziman" qatori — katakcha + ichida havolasi bor jumla.
///
/// Dizaynda havola jumlaning ICHIDA («Я согласен с *условиями объявления*»),
/// shuning uchun [Text.rich] va faqat ikkinchi bo'lakka [TapGestureRecognizer].
/// Kulrang qismga tegish katakchani almashtiradi, ko'k qismga tegish hujjatni
/// ochadi — ikkalasi bir xil bo'lsa hujjatni ochmoqchi bo'lgan odam roziligini
/// bekor qilib yuborardi.
///
/// Katakchaning ko'rinishi `terms_consent.dart` dagidan olindi (ilovada
/// rozilik katakchasi bitta ko'rinishda bo'lsin).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';

class BozorConsentRow extends StatefulWidget {
  const BozorConsentRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.leadingText,
    required this.linkText,
    required this.onOpenTerms,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Havoladan oldingi kulrang matn (oxiridagi bo'sh joy bilan).
  final String leadingText;

  /// Bosiladigan yashil qism.
  final String linkText;
  final VoidCallback onOpenTerms;

  @override
  State<BozorConsentRow> createState() => _BozorConsentRowState();
}

class _BozorConsentRowState extends State<BozorConsentRow> {
  // Tanuvchi widget bilan birga yashaydi — har build'da yangisini yaratish
  // eski tanuvchini oqizib yuborardi.
  late final TapGestureRecognizer _linkTap = TapGestureRecognizer()
    ..onTap = widget.onOpenTerms;

  @override
  void dispose() {
    _linkTap.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = widget.value
        ? AppColors.splashGreen.withValues(alpha: 0.55)
        : (isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8));
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF6E7480);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              margin: const EdgeInsets.only(top: 1),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: widget.value
                    ? AppColors.splashGreen
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: widget.value
                      ? AppColors.splashGreen
                      : (isDark
                            ? const Color(0xFF4A5054)
                            : const Color(0xFFB9BEC4)),
                  width: 2,
                ),
              ),
              child: widget.value
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: widget.leadingText,
                    recognizer: TapGestureRecognizer()..onTap = _toggle,
                  ),
                  TextSpan(
                    text: widget.linkText,
                    style: const TextStyle(
                      color: AppColors.splashGreen,
                      fontWeight: FontWeight.w700,
                    ),
                    recognizer: _linkTap,
                  ),
                ],
              ),
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
