/// "Videoga olish" bosilganda ochiladigan qo'llanma varag'i — 6 ta qoida
/// birma-bir: tepasida chizma, pastida matn.
///
/// Oxirgi sahifada "Boshlash" bosilsa `true` qaytadi; foydalanuvchi varaqni
/// yopsa `null`. Chaqiruvchi shu bo'yicha xona tanlash varag'iga o'tadi.
///
/// `PageView` ataylab `NeverScrollableScrollPhysics` bilan — varaqning
/// pastga tortib yopish imkoniyati bilan gorizontal surish bir-biriga
/// xalaqit beradi; sahifalar faqat tugmalar orqali almashadi.
///
/// Balandlik ekranning 0.8 iga qadar: chizma + sarlavha + ikki izoh
/// ko'pincha to'liq sig'adi, uzun matnda esa sahifaning o'zi suriladi.
/// Qat'iy balandlik sahifalar almashganda sakrashning oldini oladi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import 'capture_diagram.dart';
import 'capture_rules.dart';

/// Varaqni ochadi. `true` — foydalanuvchi oxirigacha o'qib "Boshlash" bosdi.
Future<bool?> showCaptureGuideSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CaptureGuideSheet(),
  );
}

class _CaptureGuideSheet extends StatefulWidget {
  const _CaptureGuideSheet();

  @override
  State<_CaptureGuideSheet> createState() => _CaptureGuideSheetState();
}

class _CaptureGuideSheetState extends State<_CaptureGuideSheet> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0) return;
    if (next >= captureRules.length) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _index = next);
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF15191B) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final last = _index == captureRules.length - 1;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _S.title(l),
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: textColor,
                      ),
                    ),
                  ),
                  Text(
                    '${_index + 1}/${captureRules.length}',
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: subColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Qolgan bo'sh joyni to'liq egallaydi — varaq har doim bir xil
              // balandlikda turadi, matn esa sahifa ichida suriladi.
              Flexible(
                child: PageView.builder(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: captureRules.length,
                  itemBuilder: (_, i) => _GuidePage(
                    rule: captureRules[i],
                    isDark: isDark,
                    locale: l,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (_index > 0) ...[
                    Expanded(
                      child: TextButton(
                        onPressed: () => _go(-1),
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        child: Text(
                          _S.back(l),
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: subColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: ListingCtaButton(
                      label: last ? _S.start(l) : _S.next(l),
                      onTap: () => _go(1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({
    required this.rule,
    required this.isDark,
    required this.locale,
  });

  final CaptureRule rule;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF8A9097);
    final accent = rule.accent(isDark);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: CaptureDiagram(kind: rule.kind, correct: rule.correct),
          ),
          const SizedBox(height: 14),
          CaptureRuleBadge(correct: rule.correct, locale: locale),
          const SizedBox(height: 8),
          Text(
            rule.title(locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 19,
              height: 1.22,
              color: textColor,
            ),
          ),
          const SizedBox(height: 10),
          CaptureRuleBullet(
            text: rule.first(locale),
            accent: accent,
            color: subColor,
            fontSize: 14,
          ),
          CaptureRuleBullet(
            text: rule.second(locale),
            accent: accent,
            color: subColor,
            fontSize: 14,
          ),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'services.ai.capture.sheet_title');
  static String next(Locale l) => tr(l, 'services.ai.capture.next');
  static String back(Locale l) => tr(l, 'services.ai.capture.back');
  static String start(Locale l) => tr(l, 'services.ai.capture.start');
}
