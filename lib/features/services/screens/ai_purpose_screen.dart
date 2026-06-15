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
  late final TextEditingController _basisCtrl =
      TextEditingController(text: widget.bundle.purposeBasis ?? '');
  late final TextEditingController _addresseeCtrl =
      TextEditingController(text: widget.bundle.addressee ?? '');

  @override
  void dispose() {
    _basisCtrl.dispose();
    _addresseeCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    HapticFeedback.lightImpact();
    widget.bundle.purpose = _purpose;
    final basis = _basisCtrl.text.trim();
    final addressee = _addresseeCtrl.text.trim();
    widget.bundle.purposeBasis = basis.isEmpty ? null : basis;
    widget.bundle.addressee = addressee.isEmpty ? null : addressee;
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
                      const SizedBox(height: 8),
                      // Баҳолаш максади (асос) — hisobotda chiqadigan erkin matn.
                      _LabeledField(
                        label: _PurposeStrings.basisLabel(l),
                        hint: _PurposeStrings.basisHint(l),
                        controller: _basisCtrl,
                        minLines: 3,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 14),
                      // Кимга тақдим этилади — илова хатдаги адресат.
                      _LabeledField(
                        label: _PurposeStrings.addresseeLabel(l),
                        hint: _PurposeStrings.addresseeHint(l),
                        controller: _addresseeCtrl,
                        minLines: 1,
                        maxLines: 2,
                      ),
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

  static String basisLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Основание оценки (необязательно)',
    'en' => 'Valuation basis (optional)',
    _ => 'Baholash asosi (ixtiyoriy)',
  };

  static String basisHint(Locale l) => switch (l.languageCode) {
    'ru' =>
      'Напр.: на основании письма Генпрокуратуры РУз № __ от __, для предоставления …',
    'en' => 'e.g. based on letter No. __ dated __, to be submitted to …',
    _ =>
      'Masalan: O‘zR Bosh prokuraturasining __ sonli __ xati asosida, … ga taqdim etish uchun',
  };

  static String addresseeLabel(Locale l) => switch (l.languageCode) {
    'ru' => 'Кому предоставляется (необязательно)',
    'en' => 'Addressee (optional)',
    _ => 'Kimga taqdim etiladi (ixtiyoriy)',
  };

  static String addresseeHint(Locale l) => switch (l.languageCode) {
    'ru' => 'Ф.И.О. / должность',
    'en' => 'Full name / position',
    _ => 'F.I.Sh. / lavozim',
  };
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.controller,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final muted = isDark ? const Color(0xFF9BA1A6) : const Color(0xFF6C7278);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: muted,
            ),
          ),
        ),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          textInputAction:
              maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontSize: 14,
            height: 1.35,
            color: textColor,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'MTSCompact',
              fontSize: 13,
              color: muted,
            ),
            filled: true,
            fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.splashGreen, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
