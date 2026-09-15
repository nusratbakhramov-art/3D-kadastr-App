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
import '../bozor_step_route.dart';
import '../data/param_options.dart';
import '../models/bozor_draft.dart';
import '../models/param_schema.dart';
import '../widgets/param_form.dart';
import 'bozor_all_params_screen.dart';

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

  /// Keyingi qadam — sotuvda «Сделка», ijarada narx.
  Future<void> _openNext() async {
    await openNextBozorStep(context, widget.draft, WizardStep.params);
    if (mounted) setState(() {});
  }

  /// Qadam to'ldirilganmi: ixtiyoriy emas va ko'rinib turgan maydonlar bo'sh
  /// bo'lmasligi kerak. Faqat 3/7 dagi qisqa ro'yxat tekshiriladi — to'liq
  /// ro'yxatdagi qo'shimchalar ixtiyoriy.
  /// To'ldirilmagan MAJBURIY maydonlar — qadam ekranidagilar VA "Barcha
  /// parametrlar" ekranidagilar.
  ///
  /// ⚠️ Ilgari faqat `type.stepParamFields` tekshirilardi, ya'ni qadamda
  /// KO'RINMAYDIGAN majburiy maydonlar (kvartirada `living_area`, `parking`;
  /// uyda `bathroom_type`; tijoratda oltitasi) hech qachon tekshirilmasdi.
  /// Foydalanuvchi 3-qadamdan o'tib ketardi, yetti qadam to'ldirardi va
  /// OXIRIDA `POST /listings/` dan tushunarsiz 400 olardi
  /// (`'bathroom_type' toʻldirilishi shart`). Backend sxemasi bilan
  /// nomuvofiqlik EMAS — ikkalasi ham majburiy deb belgilagan; muammo
  /// tekshiruv qamrovida edi.
  List<ParamField> _missingRequired(PropertyType type) {
    final shown = visibleParams(type.paramFields, _values);
    return [
      for (final f in shown)
        if (!f.optional &&
            // Toggle har doim qiymatga ega (yoqilgan/o'chirilgan).
            f.control != ParamControl.toggle &&
            _isEmpty(_values[f.key]))
          f,
    ];
  }

  static bool _isEmpty(Object? v) {
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty;
    if (v is List) return v.isEmpty;
    return false;
  }

  bool _isComplete(PropertyType type) => _missingRequired(type).isEmpty;

  /// Bloklangan "Далее" bosilganda — QAYSI maydon yetishmayotganini aytadi.
  ///
  /// Shunchaki "maydonlarni to'ldiring" deyish yetmaydi: yetishmayotgan
  /// maydon boshqa ekranda bo'lishi mumkin va foydalanuvchi uni topa olmaydi.
  void _explainMissing(PropertyType type, Locale l) {
    final missing = _missingRequired(type);
    if (missing.isEmpty) return;
    final names = missing.take(3).map((f) => tr(l, f.labelKey)).join(', ');
    final more = missing.length > 3 ? ' +${missing.length - 3}' : '';
    AppToast.error(context, '${tr(l, 'bozor.common.fill_required')}: $names$more');
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
                              // Yetishmayotgan maydon SHU ekranda bo'lsa,
                              // foydalanuvchi uni ochishi kerakligini bilishi
                              // shart — aks holda "Далее" nega o'chiq turgani
                              // umuman ko'rinmaydi.
                              missingCount: _missingRequired(type)
                                  .where((f) => !f.inStep)
                                  .length,
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
                        onContinue: _openNext,
                        onBlockedTap: () => _explainMissing(type, l),
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
  const _AllParamsRow({
    required this.label,
    required this.onTap,
    this.missingCount = 0,
  });

  final String label;
  final VoidCallback onTap;

  /// Shu ekranda to'ldirilmagan majburiy maydonlar soni. 0 bo'lsa nishon yo'q.
  final int missingCount;

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
              if (missingCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0492A).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$missingCount',
                    style: const TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFFE0492A),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
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
