import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../models/calculator_draft.dart';
import '../widgets/service_app_bar.dart';

class OnlineCalculatorResultScreen extends StatefulWidget {
  const OnlineCalculatorResultScreen({super.key, required this.draft});

  final CalculatorDraft draft;

  @override
  State<OnlineCalculatorResultScreen> createState() =>
      _OnlineCalculatorResultScreenState();
}

class _OnlineCalculatorResultScreenState
    extends State<OnlineCalculatorResultScreen> {
  bool _loading = true;
  Timer? _timer;
  late final _Result _result;

  @override
  void initState() {
    super.initState();
    _result = _compute(widget.draft);
    _timer = Timer(const Duration(milliseconds: 1500), () {
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
                      child: ServiceAppBar(
                        title: 'Onlayn kalkulyator',
                        subtitle: widget.draft.tab.label,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          if (_loading) ...[
                            Text(
                              'Hisoblanmoqda...',
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: headingColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Materiallar, ish kuchi va xizmatlar tahlil qilinmoqda.',
                              style: TextStyle(
                                fontFamily: 'MTSText',
                                fontSize: 13,
                                height: 1.3,
                                color: subColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const _PriceSkeleton(),
                            const SizedBox(height: 14),
                            const _BreakdownSkeleton(),
                          ] else ...[
                            Text(
                              'Taxminiy umumiy narx',
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: subColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PriceCard(result: _result),
                            const SizedBox(height: 18),
                            Text(
                              'Tarkibi',
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: headingColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _BreakdownCard(result: _result),
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

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.result});
  final _Result result;

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
            _fmtUzs(result.totalUzs),
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
            'Diapazon: ${_fmtUzs(result.lowUzs)} – ${_fmtUzs(result.highUzs)}',
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

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.result});
  final _Result result;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    final rows = result.lines;

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
                  Text(
                    rows[i].label,
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 13,
                      color: labelColor,
                    ),
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
              _bar(shade, width: 160, height: 12),
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
                      _bar(shade, width: 150, height: 11),
                      const SizedBox(height: 8),
                      _bar(shade, width: 110, height: 14),
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

class _Result {
  const _Result({
    required this.totalUzs,
    required this.lowUzs,
    required this.highUzs,
    required this.lines,
  });
  final int totalUzs;
  final int lowUzs;
  final int highUzs;
  final List<_Line> lines;
}

class _Line {
  const _Line(this.label, this.valueUzs);
  final String label;
  final int valueUzs;
}

_Result _compute(CalculatorDraft d) {
  // Mock pricing while real engine is offline.
  // Per-m² baselines per tab (UZS).
  final basePerM2 = switch (d.tab) {
    CalculatorTab.arxitektura => 350000,
    CalculatorTab.dizayn => 600000,
    CalculatorTab.qurilish => 4200000,
  };
  final styleMultiplier = switch (d.style) {
    CalculatorStyle.minimalizm => 1.0,
    CalculatorStyle.klassika => 1.18,
    CalculatorStyle.modern => 1.1,
  };
  final floorMultiplier = 1.0 + (d.floors - 1) * 0.05;
  final residentsMultiplier = 1.0 + (d.residents - 1) * 0.02;

  final buildingTotal =
      (d.buildingM2 * basePerM2 * styleMultiplier * floorMultiplier).round();
  final landSetup = (d.landSotix * 250000).round();
  final overhead = ((buildingTotal + landSetup) * 0.08 * residentsMultiplier)
      .round();
  final total = buildingTotal + landSetup + overhead;
  final spread = (total * 0.07).round();

  return _Result(
    totalUzs: total,
    lowUzs: total - spread,
    highUzs: total + spread,
    lines: [
      _Line(
        'Bino qismi (${d.buildingM2.toStringAsFixed(0)} m²)',
        buildingTotal,
      ),
      _Line(
        'Yer va tayyorlash (${d.landSotix.toStringAsFixed(0)} sotix)',
        landSetup,
      ),
      _Line('Loyiha xizmatlari va kommunikatsiyalar', overhead),
    ],
  );
}

String _fmtUzs(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} so\'m';
}
