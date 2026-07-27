/// Kadastr combined calculator — per-service object-type steps.
///
/// Runs after the service multi-select, once per selected service whose price
/// depends on an object type (Arxitektura, Kadastr, 3D Kadastr, Baholash) or a
/// service type (Ta'mirlash: repair vs build). Dizayn (area-only) and Yuridik
/// (quote) are skipped. Each pick is written into the shared
/// [CalculatorServiceChoice]; the last step continues to the estimate.
///
/// Steps are sequential pushes, so the system back button walks back through
/// them and a previous pick stays selected when you return.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../models/calculator_draft.dart';
import '../../models/kadastr_estimate.dart';
import '../../widgets/choice_tile.dart';
import '../../widgets/service_app_bar.dart';
import 'kadastr_estimate_screen.dart';

class KadastrTypeStepScreen extends StatefulWidget {
  const KadastrTypeStepScreen({
    super.key,
    required this.areaM2,
    required this.categories,
    required this.steps,
    required this.stepIndex,
    required this.choice,
  });

  /// Property area collected up front.
  final double areaM2;

  /// All selected services (ordered) — carried through to the estimate.
  final List<CalculatorCategory> categories;

  /// The subset of [categories] that need a type step.
  final List<CalculatorCategory> steps;

  /// Index into [steps] for this screen.
  final int stepIndex;

  /// Shared, mutable — filled in step by step.
  final CalculatorServiceChoice choice;

  @override
  State<KadastrTypeStepScreen> createState() => _KadastrTypeStepScreenState();
}

class _KadastrTypeStepScreenState extends State<KadastrTypeStepScreen> {
  CalculatorCategory get _cat => widget.steps[widget.stepIndex];
  bool get _isLast => widget.stepIndex == widget.steps.length - 1;

  bool get _answered => switch (_cat) {
    CalculatorCategory.arxitektura => widget.choice.arxitektura != null,
    CalculatorCategory.kadastr => widget.choice.kadastr != null,
    CalculatorCategory.kadastr3d => widget.choice.kadastr3d != null,
    CalculatorCategory.baholash => widget.choice.baholash != null,
    CalculatorCategory.tamirlash => widget.choice.tamirlash != null,
    CalculatorCategory.dizayn || CalculatorCategory.yuridik => true,
  };

  void _continue() {
    if (!_answered) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _isLast
            ? KadastrEstimateScreen(
                areaM2: widget.areaM2,
                categories: widget.categories,
                choice: widget.choice,
              )
            : KadastrTypeStepScreen(
                areaM2: widget.areaM2,
                categories: widget.categories,
                steps: widget.steps,
                stepIndex: widget.stepIndex + 1,
                choice: widget.choice,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;

    final isTamirlash = _cat == CalculatorCategory.tamirlash;
    final warning = _areaWarningBanner(l);

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
                    title: _cat.title(l),
                    subtitle: widget.steps.length > 1
                        ? tr(l, 'services.kadastr.type.step_counter')
                            .replaceAll(r'$i', '${widget.stepIndex + 1}')
                            .replaceAll(r'$n', '${widget.steps.length}')
                        : _cat.subtitle(l),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      Text(
                        isTamirlash
                            ? tr(l, 'services.kadastr.type.service_heading')
                            : tr(l, 'services.kadastr.type.object_heading'),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          height: 1.2,
                          color: headingColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._options(l),
                    ],
                  ),
                ),
                ?warning,
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ListingCtaButton(
                    label: _isLast
                        ? tr(l, 'services.kadastr.calculate')
                        : tr(l, 'services.kadastr.type.next'),
                    enabled: _answered,
                    onTap: _continue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _options(Locale l) {
    Widget tile(String label, String? hint, bool selected, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _OptionTile(
            label: label,
            hint: hint,
            selected: selected,
            onTap: () => setState(onTap),
          ),
        );

    switch (_cat) {
      case CalculatorCategory.arxitektura:
        return [
          for (final t in ArxitekturaObject.values)
            tile(t.label(l), t.hint(l), widget.choice.arxitektura == t,
                () => widget.choice.arxitektura = t),
        ];
      case CalculatorCategory.kadastr:
        return [
          for (final t in KadastrObjectType.values)
            tile(t.label(l), null, widget.choice.kadastr == t,
                () => widget.choice.kadastr = t),
        ];
      case CalculatorCategory.kadastr3d:
        return [
          for (final t in KadastrObjectType.values)
            tile(t.label(l), null, widget.choice.kadastr3d == t,
                () => widget.choice.kadastr3d = t),
        ];
      case CalculatorCategory.baholash:
        return [
          for (final t in BaholashObject.values)
            tile(t.label(l), null, widget.choice.baholash == t,
                () => widget.choice.baholash = t),
        ];
      case CalculatorCategory.tamirlash:
        return [
          for (final t in TamirlashServiceType.values)
            tile(t.label(l), null, widget.choice.tamirlash == t,
                () => widget.choice.tamirlash = t),
        ];
      case CalculatorCategory.dizayn:
      case CalculatorCategory.yuridik:
        return const [];
    }
  }

  // Kiritilgan maydon tanlangan arxitektura "tier"iga zid bo'lsa — yumshoq
  // ogohlantirish (bloklamaydi). "Katta" = 500 m² dan katta YOKI 12 m dan
  // baland bo'lishi mumkin; balandlik bu oqimda so'ralmaydi, shu sababli
  // maydon < 500 holatida ham qattiq cheklov qo'ymaymiz, faqat eslatamiz.
  String? _arxAreaWarning(Locale l) {
    if (_cat != CalculatorCategory.arxitektura) return null;
    final a = widget.areaM2;
    if (a <= 0) return null;
    final sel = widget.choice.arxitektura;
    if (sel == ArxitekturaObject.yakkaSmall && a >= 500) {
      return tr(l, 'services.kadastr.type.area_over_small')
          .replaceAll(r'$area', _fmtAreaM2(a));
    }
    if (sel == ArxitekturaObject.yakkaLarge && a < 500) {
      return tr(l, 'services.kadastr.type.area_under_large')
          .replaceAll(r'$area', _fmtAreaM2(a));
    }
    return null;
  }

  Widget? _areaWarningBanner(Locale l) {
    final msg = _arxAreaWarning(l);
    if (msg == null) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF3A2E12) : const Color(0xFFFFF4E5);
    final border = isDark ? const Color(0xFF5C4A1E) : const Color(0xFFFFD9A0);
    final fg = isDark ? const Color(0xFFE8C98A) : const Color(0xFF7A4E00);
    final iconColor =
        isDark ? const Color(0xFFE0B257) : const Color(0xFFB26A00);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontSize: 12.5,
                  height: 1.3,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Radio tile with an optional hint line — falls back to [ChoiceTile] when
/// there's no hint (matches the per-service forms).
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (hint == null) {
      return ChoiceTile(label: label, selected: selected, onTap: onTap);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F2426) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF8A9097);
    final idleRadio =
        isDark ? const Color(0xFF3A4042) : const Color(0xFFD1D5D9);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.splashGreen : borderColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hint!,
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12.5,
                        height: 1.3,
                        color: hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _RadioDot(selected: selected, idleColor: idleRadio),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.idleColor});

  final bool selected;
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.splashGreen : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.splashGreen : idleColor,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}

String _fmtAreaM2(double a) {
  final s =
      a == a.roundToDouble() ? a.toInt().toString() : a.toStringAsFixed(1);
  return '$s m²';
}
