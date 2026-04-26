import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/ai_valuation_draft.dart';
import '../widgets/service_app_bar.dart';
import '../widgets/step_progress_bar.dart';

class AiResultScreen extends StatefulWidget {
  const AiResultScreen({super.key, required this.draft});

  final AiValuationDraft draft;

  @override
  State<AiResultScreen> createState() => _AiResultScreenState();
}

class _AiResultScreenState extends State<AiResultScreen> {
  bool _loading = true;
  Timer? _timer;
  late final _Valuation _valuation;

  @override
  void initState() {
    super.initState();
    _valuation = _compute(widget.draft);
    _timer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContent = constraints.maxWidth.clamp(0.0, 640.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: const ServiceAppBar(
                        title: 'AI Baholash',
                        subtitle: 'Natija',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const StepProgressBar(count: 4, activeIndex: 3),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          if (_loading) ...[
                            _LoadingHeader(
                              headingColor: headingColor,
                              subColor: subColor,
                            ),
                            const SizedBox(height: 16),
                            const _PriceSkeleton(),
                            const SizedBox(height: 14),
                            const _BreakdownSkeleton(),
                          ] else ...[
                            Text(
                              'Taxminiy bozor qiymati',
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: subColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PriceCard(valuation: _valuation),
                            const SizedBox(height: 18),
                            Text(
                              'Manbalar bo\'yicha',
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: headingColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _BreakdownCard(valuation: _valuation),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListingCtaButton(
                        label: 'Yopish',
                        enabled: !_loading,
                        onTap: () =>
                            Navigator.of(context).popUntil((r) => r.isFirst),
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

class _LoadingHeader extends StatelessWidget {
  const _LoadingHeader({required this.headingColor, required this.subColor});
  final Color headingColor;
  final Color subColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI baholash hisoblanmoqda...',
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: headingColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Rasmiy indekslar, bozor solishtirma va daromadlilik tahlil qilinmoqda.',
          style: TextStyle(
            fontFamily: 'MTSText',
            fontSize: 13,
            height: 1.3,
            color: subColor,
          ),
        ),
      ],
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.valuation});
  final _Valuation valuation;

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
            _fmtUzs(valuation.estimateUzs),
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
            'Diapazon: ${_fmtUzs(valuation.lowUzs)} – ${_fmtUzs(valuation.highUzs)}',
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: subColor,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.splashGreen,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Ishonchlilik: ${valuation.confidencePct}%',
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.valuation});
  final _Valuation valuation;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    final rows = <_BreakdownRow>[
      _BreakdownRow('Rasmiy indeks (ABCCENTER)', valuation.indexUzs, 30),
      _BreakdownRow('Bozor solishtirma', valuation.marketUzs, 50),
      if (valuation.incomeUzs != null)
        _BreakdownRow(
          'Daromadlilik (kapitalizatsiya)',
          valuation.incomeUzs!,
          20,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rows[i].label,
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 13,
                            color: labelColor,
                          ),
                        ),
                      ),
                      Text(
                        '${rows[i].weightPct}%',
                        style: TextStyle(
                          fontFamily: 'MTSCompact',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: AppColors.splashGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fmtUzs(rows[i].valueUzs),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: valueColor,
                    ),
                  ),
                ],
              ),
            ),
            if (i != rows.length - 1) Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow {
  const _BreakdownRow(this.label, this.valueUzs, this.weightPct);
  final String label;
  final int valueUzs;
  final int weightPct;
}

class _PriceSkeleton extends StatefulWidget {
  const _PriceSkeleton();

  @override
  State<_PriceSkeleton> createState() => _PriceSkeletonState();
}

class _PriceSkeletonState extends State<_PriceSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final baseA = isDark ? const Color(0xFF1A2024) : const Color(0xFFE7EAEE);
    final baseB = isDark ? const Color(0xFF262C31) : const Color(0xFFF2F4F7);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final shade = Color.lerp(baseA, baseB, _pulse.value)!;
        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(shade, width: 220, height: 26),
              const SizedBox(height: 14),
              _bar(shade, width: 180, height: 12),
              const SizedBox(height: 18),
              _bar(shade, width: 110, height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(Color color, {required double width, required double height}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      );
}

class _BreakdownSkeleton extends StatefulWidget {
  const _BreakdownSkeleton();

  @override
  State<_BreakdownSkeleton> createState() => _BreakdownSkeletonState();
}

class _BreakdownSkeletonState extends State<_BreakdownSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final baseA = isDark ? const Color(0xFF1A2024) : const Color(0xFFE7EAEE);
    final baseB = isDark ? const Color(0xFF262C31) : const Color(0xFFF2F4F7);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final shade = Color.lerp(baseA, baseB, _pulse.value)!;
        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _bar(shade, width: 160, height: 11),
                          _bar(shade, width: 36, height: 11),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _bar(shade, width: 130, height: 14),
                    ],
                  ),
                ),
                if (i != 2) Container(height: 1, color: divider),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _bar(Color color, {required double width, required double height}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      );
}

class _Valuation {
  const _Valuation({
    required this.estimateUzs,
    required this.lowUzs,
    required this.highUzs,
    required this.indexUzs,
    required this.marketUzs,
    required this.incomeUzs,
    required this.confidencePct,
  });
  final int estimateUzs;
  final int lowUzs;
  final int highUzs;
  final int indexUzs;
  final int marketUzs;
  final int? incomeUzs;
  final int confidencePct;
}

_Valuation _compute(AiValuationDraft draft) {
  // Mock estimator while the real AI pipeline isn't wired.
  // Uses area + viloyat/usage as light signals so different inputs yield
  // visibly different numbers.
  final area = draft.areaM2 ?? 60;
  final premiumViloyat =
      (draft.viloyat == 'Toshkent shahri' ||
          draft.viloyat == 'Toshkent viloyati')
      ? 1.4
      : 1.0;
  final typeFactor = switch (draft.objectType) {
    null => 1.0,
    _ when draft.objectType!.name == 'turarJoy' => 1.0,
    _ when draft.objectType!.name == 'noturarJoy' => 1.15,
    _ when draft.objectType!.name == 'ombor' => 0.7,
    _ => 1.05,
  };
  final pricePerM2 = (10000000 * premiumViloyat * typeFactor).round();
  final indexValue = (area * pricePerM2 * 0.9).round();
  final marketValue = (area * pricePerM2 * 1.05).round();
  final incomeValue =
      draft.usageType == AiUsageType.rental && draft.monthlyIncomeUzs != null
      ? ((draft.monthlyIncomeUzs! * 12) / 0.08).round()
      : null;

  final weighted = incomeValue != null
      ? (indexValue * 0.3 + marketValue * 0.5 + incomeValue * 0.2).round()
      : (indexValue * 0.4 + marketValue * 0.6).round();
  final spread = (weighted * 0.08).round();
  final confidence = incomeValue != null ? 84 : 76;

  return _Valuation(
    estimateUzs: weighted,
    lowUzs: math.max(weighted - spread, 0),
    highUzs: weighted + spread,
    indexUzs: indexValue,
    marketUzs: marketValue,
    incomeUzs: incomeValue,
    confidencePct: confidence,
  );
}

String _fmtUzs(int value) {
  // Group thousands with non-breaking spaces for readability.
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} so\'m';
}
