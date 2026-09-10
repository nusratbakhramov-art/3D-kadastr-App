/// Xonani videoga olish qoidalari — bitta manba.
///
/// Ikki joyda ko'rsatiladi: AI Baholashning video qadamida ro'yxat sifatida
/// va "Videoga olish" bosilganda ochiladigan bosqichma-bosqich
/// (`capture_guide_sheet.dart`) varaqda. Matnlar `services.ai.capture.*`
/// kalitlarida, chizmalar esa `CaptureDiagram` da.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import 'capture_diagram.dart';

/// Bitta qoida: chizma + sarlavha + ikki izoh. [correct] false — bu xato.
class CaptureRule {
  const CaptureRule({
    required this.kind,
    required this.correct,
    required this.key,
  });

  final CaptureDiagramKind kind;
  final bool correct;

  /// `services.ai.capture.<key>_title|_a|_b` kalitlari uchun prefiks.
  final String key;

  String title(Locale l) => captureRuleText(l, key, 'title');
  String first(Locale l) => captureRuleText(l, key, 'a');
  String second(Locale l) => captureRuleText(l, key, 'b');

  Color accent(bool isDark) =>
      correct ? AppColors.callGreenDeep : AppColors.chatRedDeep;
}

/// Uchtasi to'g'ri usul, uchtasi tez uchraydigan xato — shu tartibda.
const List<CaptureRule> captureRules = [
  CaptureRule(kind: CaptureDiagramKind.loop, correct: true, key: 's1'),
  CaptureRule(kind: CaptureDiagramKind.highLow, correct: true, key: 's2'),
  CaptureRule(kind: CaptureDiagramKind.oblique, correct: true, key: 's3'),
  CaptureRule(kind: CaptureDiagramKind.spinInPlace, correct: false, key: 'w1'),
  CaptureRule(kind: CaptureDiagramKind.cornerSnap, correct: false, key: 'w2'),
  CaptureRule(kind: CaptureDiagramKind.wallParallel, correct: false, key: 'w3'),
];

String captureRuleText(Locale l, String key, String part) =>
    tr(l, 'services.ai.capture.${key}_$part');

String captureBadge(Locale l, bool correct) => tr(
      l,
      correct
          ? 'services.ai.capture.badge_right'
          : 'services.ai.capture.badge_wrong',
    );

/// TO'G'RI / NOTO'G'RI yorlig'i.
class CaptureRuleBadge extends StatelessWidget {
  const CaptureRuleBadge({
    super.key,
    required this.correct,
    required this.locale,
  });

  final bool correct;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final accent =
        correct ? AppColors.callGreenDeep : AppColors.chatRedDeep;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 15,
          color: accent,
        ),
        const SizedBox(width: 5),
        Text(
          captureBadge(locale, correct),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 0.6,
            color: accent,
          ),
        ),
      ],
    );
  }
}

/// Izoh qatori — nuqta + matn.
class CaptureRuleBullet extends StatelessWidget {
  const CaptureRuleBullet({
    super.key,
    required this.text,
    required this.accent,
    required this.color,
    this.fontSize = 13,
  });

  final String text;
  final Color accent;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: fontSize,
                height: 1.4,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ro'yxat ko'rinishi — chizma ustida, matn pastida, kartochka ichida.
class CaptureRuleCard extends StatelessWidget {
  const CaptureRuleCard({
    super.key,
    required this.rule,
    required this.isDark,
    required this.locale,
  });

  final CaptureRule rule;
  final bool isDark;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final accent = rule.accent(isDark);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: CaptureDiagram(kind: rule.kind, correct: rule.correct),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaptureRuleBadge(correct: rule.correct, locale: locale),
                const SizedBox(height: 6),
                Text(
                  rule.title(locale),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.25,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                CaptureRuleBullet(
                  text: rule.first(locale),
                  accent: accent,
                  color: subColor,
                ),
                CaptureRuleBullet(
                  text: rule.second(locale),
                  accent: accent,
                  color: subColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
