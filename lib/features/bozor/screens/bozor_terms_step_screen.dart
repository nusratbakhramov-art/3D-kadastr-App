/// "Bozor AI" sehrgarining oxirgi qadami — `Условия размещения`.
///
/// Oltita variantda ham bir xil; farqi faqat qadam raqamida (`7/7` yoki
/// "Boshqa noturar joy" da `6/6`).
///
/// Pastdagi qator dizayndagidek: chapda "Oldindan ko'rish", o'ngda
/// "Joylashtirish" — bu yerda "Ortga" YO'Q (dizaynda ham yo'q). Bir qadam
/// orqaga qaytish iOS'dagi chetdan surish imkoniyati bilan qoladi; yuqoridagi
/// tugma esa boshqa qadamlardagidek butun oqimni yopadi.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../bozor_routes.dart';
import '../data/bozor_api.dart';
import '../data/bozor_submit.dart';
import '../models/bozor_draft.dart';
import '../widgets/bozor_consent_row.dart';
import '../widgets/draft_preview_sheet.dart';
import '../widgets/tier_card.dart';
import 'bozor_success_screen.dart';

class BozorTermsStepScreen extends StatefulWidget {
  const BozorTermsStepScreen({super.key, required this.draft});

  final BozorDraft draft;

  @override
  State<BozorTermsStepScreen> createState() => _BozorTermsStepScreenState();
}

class _BozorTermsStepScreenState extends State<BozorTermsStepScreen> {
  TermsDraft get _t => widget.draft.terms;

  final BozorSubmitter _submitter = BozorSubmitter();
  bool _sending = false;

  @override
  void dispose() {
    _submitter.dispose();
    super.dispose();
  }

  void _showTierInfo(PlacementTier tier) {
    // TODO(design): tariflarning mazmuni va "Top" narxi dizaynda yo'q.
    AppToast.error(
      context,
      tr(Localizations.localeOf(context), 'bozor.terms.info_missing'),
    );
  }

  void _openTerms() {
    // TODO(backend): e'lon shartlari hujjati uchun manzil kerak.
    // `/legal/terms` AI-baholash ofertasi — bu yerga to'g'ri kelmaydi.
    AppToast.error(
      context,
      tr(Localizations.localeOf(context), 'bozor.terms.doc_missing'),
    );
  }

  /// Fayllarni yuklaydi, keyin e'lonni yaratadi.
  ///
  /// Xatolikda qoralama JOYIDA qoladi va tugma yana yonadi — foydalanuvchi
  /// hamma narsani qaytadan kiritmasligi kerak.
  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);
    final l = Localizations.localeOf(context);
    try {
      await _submitter.submit(widget.draft);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          settings: bozorRoute('success'),
          builder: (_) => const BozorSuccessScreen(),
        ),
        // Sehrgarning hamma qadamini olib tashlaymiz: muvaffaqiyat ekranidan
        // formaga qaytib bo'lmaydi.
        (route) {
          final name = route.settings.name;
          return name == null || !name.startsWith(bozorRoutePrefix);
        },
      );
    } on BozorApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (e) {
      if (mounted) AppToast.error(context, tr(l, 'bozor.terms.submit_failed'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final draft = widget.draft;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxContent = c.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: tr(l, 'bozor.terms.title'),
                        subtitle:
                            '${draft.stepNumber(WizardStep.terms)}'
                            '/${draft.stepCount}',
                        onBack: () => closeBozorWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: draft.stepCount,
                        activeIndex: draft.stepIndex(WizardStep.terms),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          TierCard(
                            label: tr(l, 'bozor.terms.tier_standard'),
                            selected: _t.tier == PlacementTier.standard,
                            onTap: () => setState(
                              () => _t.tier = PlacementTier.standard,
                            ),
                            onInfo: () =>
                                _showTierInfo(PlacementTier.standard),
                          ),
                          const SizedBox(height: 12),
                          TierCard(
                            label: tr(l, 'bozor.terms.tier_top'),
                            selected: _t.tier == PlacementTier.top,
                            showRocket: true,
                            onTap: () =>
                                setState(() => _t.tier = PlacementTier.top),
                            onInfo: () => _showTierInfo(PlacementTier.top),
                          ),
                          const SizedBox(height: 16),
                          BozorConsentRow(
                            value: _t.accepted,
                            onChanged: (v) => setState(() => _t.accepted = v),
                            leadingText: tr(l, 'bozor.terms.consent_lead'),
                            linkText: tr(l, 'bozor.terms.consent_link'),
                            onOpenTerms: _openTerms,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _PreviewButton(
                              label: tr(l, 'bozor.terms.preview'),
                              onTap: () =>
                                  showDraftPreviewSheet(context, draft),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _t.accepted
                                  ? null
                                  : () => AppToast.error(
                                      context,
                                      tr(l, 'bozor.terms.accept_first'),
                                    ),
                              child: ListingCtaButton(
                                label: _sending
                                    ? tr(l, 'bozor.terms.submitting')
                                    : tr(l, 'bozor.terms.submit'),
                                enabled: _t.accepted && !_sending,
                                onTap: _submit,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Ikkilamchi tugma — [ListingCtaButton] bilan bir o'lchamda.
class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final fg = isDark ? Colors.white : AppColors.textBlack;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
