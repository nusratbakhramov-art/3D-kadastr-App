/// Kadastr combined calculator — step 2: multi-select services.
///
/// Shows the calculator services; the user picks one or more. A sticky bottom
/// bar shows the running (taxminiy) total and continues to the estimate.
library;

import 'package:flutter/material.dart';

import '../../../../core/haptics.dart';
import '../../../../core/i18n/app_translations.dart';
import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/calculator_pricing_store.dart';
import '../../models/calculator_draft.dart';
import '../../models/calculator_pricing.dart';
import '../../models/kadastr_estimate.dart';
import '../../widgets/service_app_bar.dart';
import '../../widgets/service_group_card.dart';
import 'kadastr_estimate_screen.dart';

class KadastrServicesScreen extends StatefulWidget {
  const KadastrServicesScreen({super.key, required this.areaM2});

  final double areaM2;

  @override
  State<KadastrServicesScreen> createState() => _KadastrServicesScreenState();
}

class _KadastrServicesScreenState extends State<KadastrServicesScreen> {
  final Set<CalculatorCategory> _selected = <CalculatorCategory>{};

  void _toggle(CalculatorCategory c) {
    setState(() {
      if (!_selected.remove(c)) _selected.add(c);
    });
  }

  void _next() {
    if (_selected.isEmpty) return;
    // Preserve enum order for a stable layout.
    final ordered = CalculatorCategory.listed
        .where(_selected.contains)
        .toList(growable: false);
    // Calculation-only flow: no per-service type/TZ step — go straight to the
    // estimate. Services that depend on a type are priced with their default.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KadastrEstimateScreen(
          areaM2: widget.areaM2,
          categories: ordered,
          choice: CalculatorServiceChoice(),
        ),
      ),
    );
  }

  /// Bitta xizmat — oddiy tanlanadigan karta; bir nechtasi — akkordeon
  /// (kadastr guruhi: oddiy + 3D). Tanlov baribir alohida xizmat darajasida.
  Widget _groupCard(List<CalculatorCategory> group, Locale l) {
    if (group.length == 1) {
      final c = group.first;
      return _SelectableServiceCard(
        category: c,
        locale: l,
        selected: _selected.contains(c),
        onTap: () => _toggle(c),
      );
    }
    final head = group.first;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBorder =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final chosen = group.where(_selected.contains).length;
    return ServiceGroupCard(
      title: kadastrGroupTitle(l),
      subtitle: kadastrGroupSubtitle(l),
      assetIcon: head.assetIcon,
      iconScale: head.iconScale,
      fallbackIcon: head.icon,
      accent: head.accent,
      badgeCount: chosen,
      // Guruhda allaqachon tanlov bo'lsa ochiq tursin (masalan orqaga
      // qaytganda) — aks holda tanlangan xizmat ko'rinmay qoladi.
      initiallyExpanded: chosen > 0,
      rows: [
        for (final c in group)
          ServiceGroupRow(
            title: c.rowTitle(l),
            subtitle: c.rowSubtitle(l),
            assetIcon: c.rowAssetIcon,
            iconScale: c.iconScale,
            fallbackIcon: c.icon,
            selected: _selected.contains(c),
            trailing: _CheckDot(
              selected: _selected.contains(c),
              unselectedBorder: unselectedBorder,
            ),
            onTap: () => _toggle(c),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Scaffold(
      backgroundColor: bg,
      // bottom:false → the sticky bar fills the bottom inset itself (no black
      // band under the home indicator); the bar adds the inset to its padding.
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: ServiceAppBar(
                    // Bu oqim "Calculator Ai" kartasidan ochiladi. Eski
                    // `services.kadastr.flow.appbar` prod bundle'ida "3D
                    // kadastr"ga o'zgartirilgan (backend seed'ni yengadi),
                    // shuning uchun sarlavha yangi kalitda.
                    title: tr(l, 'services.kadastr.flow.appbar.calc'),
                    subtitle: '${_fmtArea(widget.areaM2)} m²',
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      Text(
                        tr(l, 'services.kadastr.services.heading'),
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          height: 1.2,
                          color: headingColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(l, 'services.kadastr.services.subheading'),
                        style: TextStyle(
                          fontFamily: 'MTSText',
                          fontSize: 13,
                          height: 1.4,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final group in CalculatorCategory.listedGroups) ...[
                        _groupCard(group, l),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
                _BottomBar(
                  areaM2: widget.areaM2,
                  selected: _selected,
                  locale: l,
                  onNext: _next,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sticky footer: selected count + running taxminiy total + continue button.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.areaM2,
    required this.selected,
    required this.locale,
    required this.onNext,
  });

  final double areaM2;
  final Set<CalculatorCategory> selected;
  final Locale locale;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final topBorder =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ValueListenableBuilder<CalculatorPricing>(
      valueListenable: calculatorPricingNotifier,
      builder: (context, pricing, _) {
        final estimates = selected
            .map((c) => estimateForCategory(
                  category: c,
                  areaM2: areaM2,
                  pricing: pricing,
                  locale: locale,
                ))
            .toList(growable: false);
        final total = kadastrCombinedTotalUzs(estimates);

        return Container(
          decoration: BoxDecoration(
            color: barBg,
            border: Border(top: BorderSide(color: topBorder)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(locale, 'services.kadastr.total_label'),
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 12.5,
                            color: labelColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmtUzsPublic(locale, total),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            color: valueColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.splashGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tr(locale, 'services.kadastr.selected_count')
                            .replaceAll(r'$n', '${selected.length}'),
                        style: const TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: AppColors.splashGreen,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ListingCtaButton(
                label: tr(locale, 'services.kadastr.calculate'),
                enabled: selected.isNotEmpty,
                onTap: onNext,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectableServiceCard extends StatelessWidget {
  const _SelectableServiceCard({
    required this.category,
    required this.locale,
    required this.selected,
    required this.onTap,
  });

  final CalculatorCategory category;
  final Locale locale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final unselectedBorder =
        isDark ? const Color(0xFF2C3133) : const Color(0xFFE3E5E8);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hapticTap(onTap),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.splashGreen : unselectedBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              // Same tile as the Onlayn kalkulyator list: the 3D image when the
              // category has one, the flat glyph (accent-tinted) otherwise.
              Container(
                width: 44,
                height: 44,
                padding: category.assetIcon != null
                    ? const EdgeInsets.all(4)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: category.assetIcon != null
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF1F2F4))
                      : category.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: category.assetIcon != null
                    ? Transform.scale(
                        scale: category.iconScale,
                        child: Image.asset(
                          category.assetIcon!,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Icon(category.icon, color: category.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title(locale),
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      category.subtitle(locale),
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontSize: 12.5,
                        height: 1.3,
                        color: subColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CheckDot(selected: selected, unselectedBorder: unselectedBorder),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.selected, required this.unselectedBorder});

  final bool selected;
  final Color unselectedBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.splashGreen : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.splashGreen : unselectedBorder,
          width: 1.6,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded,
              size: 16, color: AppColors.greenBlack)
          : null,
    );
  }
}

String _fmtArea(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

