/// "Bozor AI" sehrgarining 3-qadami — `Параметры`.
///
/// Qisqa ro'yxat (`inStep`) shu yerda, qolgani "Barcha parametrlar" ekranida.
/// Ikkalasi ham bitta [ParamForm] va bitta `values` xaritasi ustida ishlaydi.
///
/// Garaj/parkovka istisno: unda hamma maydon qadamning o'zida, "Barcha
/// parametrlar" varag'i dizaynda yo'q — shuning uchun navigatsiya qatori
/// chizilmaydi.
library;

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/i18n/app_translations.dart';
import '../../../theme/app_colors.dart';
import '../../services/widgets/service_app_bar.dart';
import '../../services/widgets/step_progress_bar.dart';
import '../../services/widgets/wizard_nav_bar.dart';
import '../../../widgets/app_toast.dart';
import '../bozor_routes.dart';
import '../data/bozor_draft_store.dart';
import '../data/param_options.dart';
import '../models/bozor_draft.dart';
import '../models/param_schema.dart';
import '../widgets/param_form.dart';
import 'bozor_all_params_screen.dart';
import 'bozor_price_step_screen.dart';

class BozorParamsStepScreen extends StatefulWidget {
  const BozorParamsStepScreen({super.key, required this.draft});

  final BozorDraft draft;

  @override
  State<BozorParamsStepScreen> createState() => _BozorParamsStepScreenState();
}

class _BozorParamsStepScreenState extends State<BozorParamsStepScreen> {
  ParamValues get _values => widget.draft.params;

  /// BITTA nusxa: "Barcha parametrlar" ekraniga ham shu beriladi, shunda
  /// tanlov ro'yxatlari ikkinchi marta so'ralmaydi (repozitoriy keshlaydi).
  ParamOptionsRepository? _options;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _options ??= ApiParamOptions(
      locale: Localizations.localeOf(context).languageCode,
    );
  }

  Future<void> _openAllParams(PropertyType type) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('params/all'),
        builder: (_) => BozorAllParamsScreen(
          fields: type.paramFields,
          values: _values,
          optionsRepository: _options!,
        ),
      ),
    );
    // To'liq ro'yxatda kiritilgan qiymat qadamdagi qatorlarga ham ta'sir
    // qilishi mumkin (masalan shartli maydonlar) — qayta chizamiz.
    if (mounted) setState(() {});
  }

  Future<void> _openPrice() async {
    // Qoralamani fonda saqlaymiz: foydalanuvchi shu qadamda chiqib
    // ketsa "Mening e'lonlarim" dan aynan shu joydan davom etadi.
    // `await` QILINMAYDI — tarmoq navigatsiyani muzlatmasin.
    saveBozorDraftInBackground(widget.draft, WizardStep.price);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: bozorRoute('price'),
        builder: (_) => BozorPriceStepScreen(draft: widget.draft),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Qadam to'ldirilganmi: ixtiyoriy emas va ko'rinib turgan maydonlar bo'sh
  /// bo'lmasligi kerak. Faqat 3/7 dagi qisqa ro'yxat tekshiriladi — to'liq
  /// ro'yxatdagi qo'shimchalar ixtiyoriy.
  bool _isComplete(PropertyType type) {
    final shown = visibleParams(type.stepParamFields, _values);
    for (final f in shown) {
      if (f.optional) continue;
      // Toggle har doim qiymatga ega (yoqilgan/o'chirilgan) — tekshirilmaydi.
      if (f.control == ParamControl.toggle) continue;
      final v = _values[f.key];
      if (v == null) return false;
      if (v is String && v.trim().isEmpty) return false;
      if (v is List && v.isEmpty) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final type = widget.draft.type;

    if (type == null) {
      return Scaffold(backgroundColor: bg, body: const SizedBox());
    }

    final complete = _isComplete(type);

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
                        title: tr(l, 'bozor.params.title'),
                        subtitle:
                            '${widget.draft.stepNumber(WizardStep.params)}'
                            '/${widget.draft.stepCount}',
                        onBack: () => closeBozorWizard(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StepProgressBar(
                        count: widget.draft.stepCount,
                        activeIndex: widget.draft.stepIndex(WizardStep.params),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          ParamForm(
                            fields: type.stepParamFields,
                            values: _values,
                            onChanged: () => setState(() {}),
                            optionsRepository: _options!,
                          ),
                          if (type.hasAllParamsScreen)
                            _AllParamsRow(
                              label: tr(l, 'bozor.params.all'),
                              onTap: () => _openAllParams(type),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: WizardNavBar(
                        onBack: () => Navigator.of(context).maybePop(),
                        continueLabel: tr(l, 'bozor.common.next'),
                        continueEnabled: complete,
                        onContinue: _openPrice,
                        onBlockedTap: () => AppToast.error(
                          context,
                          tr(l, 'bozor.common.fill_required'),
                        ),
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

/// "Barcha parametrlar" — to'liq ro'yxatga o'tadigan qator. Dizaynda ko'k
/// matn + o'ng shevron; bizda brend yashili.
class _AllParamsRow extends StatelessWidget {
  const _AllParamsRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1F2426) : Colors.white;
    final border = isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final radius = BorderRadius.circular(14);

    return Material(
      color: fill,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.splashGreen,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.splashGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
