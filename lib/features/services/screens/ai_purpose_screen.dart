/// AI Baholash wizard — purpose step (baholash maqsadi).
///
/// Required, single-select. Drives the backend's reconciliation weighting
/// (insurance→cost, sale→market, court→balanced …). After selecting,
/// continues to the intake step (photos / kadastr / passport / rooms).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../ai_draft_saver.dart';
import '../models/ai_baholash_bundle.dart';
import '../widgets/choice_tile.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';
import 'ai_intake_screen.dart';

class AiPurposeScreen extends StatefulWidget {
  const AiPurposeScreen({super.key, required this.bundle});

  final AiBaholashBundle bundle;

  @override
  State<AiPurposeScreen> createState() => _AiPurposeScreenState();
}

class _AiPurposeScreenState extends State<AiPurposeScreen> {
  late ValuationPurpose _purpose = widget.bundle.purpose;

  Future<void> _next() async {
    HapticFeedback.lightImpact();
    widget.bundle.purpose = _purpose;
    await saveAiDraftStep(widget.bundle, 'intake'); // qadam saqlash
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ai/intake'),
        builder: (_) => AiIntakeScreen(bundle: widget.bundle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ServiceAppBar(
                    title: _PurposeStrings.title(l),
                    subtitle: _PurposeStrings.subtitle(l),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: StepProgressBar(count: 6, activeIndex: 3),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      for (final p in ValuationPurpose.values) ...[
                        ChoiceTile(
                          label: '${p.label(l)}  ·  ${p.hint(l)}',
                          selected: _purpose == p,
                          onTap: () => setState(() => _purpose = p),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _PurposeStrings.continueLabel(l),
                    enabled: true,
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PurposeStrings {
  const _PurposeStrings._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Цель оценки',
    'en' => 'Valuation purpose',
    _ => 'Baholash maqsadi',
  };

  static String subtitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Для чего определяется стоимость?',
    'en' => 'Why is the value being determined?',
    _ => 'Qiymat nima uchun aniqlanmoqda?',
  };

  static String continueLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Продолжить',
    'en' => 'Continue',
    _ => 'Davom etish',
  };
}
