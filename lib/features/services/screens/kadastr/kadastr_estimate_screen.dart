/// Kadastr combined calculator — final step: the estimate.
///
/// Calculation-only: computes each selected service from the area (default type
/// per service), shows a per-service breakdown + combined total. No application
/// is submitted here — the only action is returning to the home screen.
library;

import 'package:flutter/material.dart';

import '../../../../theme/app_colors.dart';
import '../../../market/widgets/listing_cta_button.dart';
import '../../data/calculator_pricing_store.dart';
import '../../models/calculator_draft.dart';
import '../../models/calculator_pricing.dart';
import '../../models/kadastr_estimate.dart';
import '../../widgets/service_app_bar.dart';

class KadastrEstimateScreen extends StatelessWidget {
  const KadastrEstimateScreen({
    super.key,
    required this.areaM2,
    required this.categories,
    this.choice,
  });

  final double areaM2;
  final List<CalculatorCategory> categories;

  /// Per-service object types picked in the type steps. When null (no service
  /// needed a type), default types are used.
  final CalculatorServiceChoice? choice;

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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ValueListenableBuilder<CalculatorPricing>(
              valueListenable: calculatorPricingNotifier,
              builder: (context, pricing, _) {
                final estimates = categories
                    .map((c) => estimateForCategory(
                          category: c,
                          areaM2: areaM2,
                          pricing: pricing,
                          locale: l,
                          choice: choice,
                        ))
                    .toList(growable: false);
                final total = kadastrCombinedTotalUzs(estimates);
                final hasQuote = estimates.any((e) => e.isQuote);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: ServiceAppBar(
                        title: _S.appBar(l),
                        subtitle: '${_fmtArea(areaM2)} m²',
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        children: [
                          Text(
                            _S.totalLabel(l),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _TotalCard(total: total, locale: l),
                          const SizedBox(height: 18),
                          Text(
                            _S.breakdown(l),
                            style: TextStyle(
                              fontFamily: 'MTSCompact',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: headingColor,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final e in estimates) ...[
                            _ServiceRow(estimate: e, locale: l),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            hasQuote ? _S.footnoteQuote(l) : _S.footnote(l),
                            style: TextStyle(
                              fontFamily: 'MTSText',
                              fontSize: 12,
                              height: 1.4,
                              color: subColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: _S.backHome(l),
                        onTap: () =>
                            Navigator.of(context).popUntil((r) => r.isFirst),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total, required this.locale});
  final int total;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final valueColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fmtUzsPublic(locale, total),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w900,
              fontSize: 28,
              height: 1.1,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _S.approxNote(locale),
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: subColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.estimate, required this.locale});
  final KadastrServiceEstimate estimate;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final cat = estimate.category;
    final priceText = estimate.isQuote
        ? kadastrQuoteLabel(locale)
        : fmtUzsPublic(locale, estimate.totalUzs);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cat.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(cat.icon, color: cat.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat.title(locale),
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    height: 1.2,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  cat.subtitle(locale),
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 12,
                    height: 1.3,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            priceText,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w800,
              fontSize: estimate.isQuote ? 12.5 : 14.5,
              color: estimate.isQuote ? subColor : titleColor,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtArea(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class _S {
  const _S._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  static String appBar(Locale l) =>
      _pick(l, 'Taxminiy hisob', 'Примерный расчёт', 'Estimate');

  static String totalLabel(Locale l) =>
      _pick(l, 'Taxminiy jami', 'Примерно итого', 'Estimated total');

  static String approxNote(Locale l) => _pick(
        l,
        'QQS bilan · taxminiy narx',
        'С НДС · примерная цена',
        'incl. VAT · approximate',
      );

  static String breakdown(Locale l) =>
      _pick(l, 'Tanlangan xizmatlar', 'Выбранные услуги', 'Selected services');

  static String footnote(Locale l) => _pick(
        l,
        '* Narxlar taxminiy. Aniq narx ariza qoldirilgandan keyin belgilanadi.',
        '* Цены примерные. Точная цена определяется после заявки.',
        '* Prices are approximate. The exact price is set after you apply.',
      );

  static String footnoteQuote(Locale l) => _pick(
        l,
        '* Narxlar taxminiy. Yuridik xizmat narxi kelishuv asosida. Aniq narx ariza qoldirilgandan keyin belgilanadi.',
        '* Цены примерные. Юридические услуги — по договорённости. Точная цена определяется после заявки.',
        '* Prices are approximate. Legal services are by agreement. The exact price is set after you apply.',
      );

  static String backHome(Locale l) =>
      _pick(l, 'Asosiyga qaytish', 'На главную', 'Back to home');
}
