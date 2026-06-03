import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../auth/auth_storage.dart';
import '../../auth/widgets/login_required_sheet.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../api_calculator_order_service.dart';
import '../models/calculator_draft.dart';
import '../widgets/service_app_bar.dart';

class OnlineCalculatorResultScreen extends StatefulWidget {
  const OnlineCalculatorResultScreen({
    super.key,
    required this.result,
    this.onPlaceOrder,
    this.placeOrderLabel,
  });

  final CalculatorResult result;

  /// Agar berilsa, "Yopish" tugmasi ustida qo'shimcha CTA ko'rsatiladi.
  /// Arxitektura kalkulatoridan TZ wizard'iga o'tish uchun.
  final VoidCallback? onPlaceOrder;
  final String? placeOrderLabel;

  @override
  State<OnlineCalculatorResultScreen> createState() =>
      _OnlineCalculatorResultScreenState();
}

class _OnlineCalculatorResultScreenState
    extends State<OnlineCalculatorResultScreen> {
  bool _loading = true;
  Timer? _timer;

  // "Ariza topshirish" submit state (only for the plain online-calculator
  // flow — architecture uses its own onPlaceOrder wizard).
  final CalculatorOrderApiService _orders = CalculatorOrderApiService();
  bool _orderSubmitting = false;
  bool _orderSubmitted = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _orders.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submitOrder() async {
    if (_orderSubmitting || _orderSubmitted) return;
    if (!await ensureLoggedIn(context)) return;
    final session = await const AuthStorage().loadSession();
    final token = session.token;
    if (token == null || token.isEmpty) return;
    if (!mounted) return;
    setState(() => _orderSubmitting = true);
    try {
      await _orders.submit(result: widget.result, token: token);
      if (!mounted) return;
      setState(() {
        _orderSubmitting = false;
        _orderSubmitted = true;
      });
      _snack('Ariza yuborildi');
    } catch (e) {
      if (!mounted) return;
      setState(() => _orderSubmitting = false);
      _snack('Yuborishda xatolik: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.greenBlack : AppColors.lightBackground;
    final headingColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final locale = Localizations.localeOf(context);

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
                        title: _Strings.appBar(locale),
                        subtitle: widget.result.categoryTitle,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        children: [
                          if (_loading) ...[
                            Text(
                              _Strings.calculating(locale),
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: headingColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _Strings.calculatingHint(locale),
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
                              _Strings.totalLabel(locale),
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: subColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PriceCard(result: widget.result, locale: locale),
                            const SizedBox(height: 18),
                            Text(
                              _Strings.breakdown(locale),
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: headingColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _BreakdownCard(result: widget.result),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.onPlaceOrder != null) ...[
                            ListingCtaButton(
                              label: widget.placeOrderLabel ??
                                  _Strings.placeOrder(locale),
                              enabled: !_loading,
                              onTap: widget.onPlaceOrder!,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => Navigator.of(context)
                                  .popUntil((r) => r.isFirst),
                              child: Text(_Strings.close(locale)),
                            ),
                          ] else ...[
                            ListingCtaButton(
                              label: _orderSubmitted
                                  ? _Strings.submitted(locale)
                                  : (_orderSubmitting
                                      ? _Strings.submitting(locale)
                                      : _Strings.submitOrder(locale)),
                              enabled: !_loading &&
                                  !_orderSubmitting &&
                                  !_orderSubmitted,
                              onTap: _submitOrder,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => Navigator.of(context)
                                  .popUntil((r) => r.isFirst),
                              child: Text(_Strings.close(locale)),
                            ),
                          ],
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

class _Strings {
  const _Strings._();

  static String _pick(Locale l, String uz, String ru, String en) =>
      switch (l.languageCode) { 'ru' => ru, 'en' => en, _ => uz };

  static String appBar(Locale l) => _pick(
        l,
        'Hisob natijasi',
        'Результат расчёта',
        'Calculation result',
      );

  static String calculating(Locale l) =>
      _pick(l, 'Hisoblanmoqda...', 'Расчёт...', 'Calculating...');

  static String calculatingHint(Locale l) => _pick(
        l,
        "Tarif jadvali bo'yicha narx aniqlanmoqda.",
        'Цена определяется по тарифной таблице.',
        'Determining price by tariff table.',
      );

  static String totalLabel(Locale l) =>
      _pick(l, 'Umumiy narx', 'Общая стоимость', 'Total');

  static String breakdown(Locale l) =>
      _pick(l, 'Tarkibi', 'Состав', 'Breakdown');

  static String close(Locale l) =>
      _pick(l, 'Yopish', 'Закрыть', 'Close');

  static String placeOrder(Locale l) => _pick(
        l,
        'Buyurtma berish',
        'Оформить заказ',
        'Place order',
      );

  static String submitOrder(Locale l) => _pick(
        l,
        'Ariza topshirish',
        'Подать заявку',
        'Submit application',
      );

  static String submitting(Locale l) => _pick(
        l,
        'Yuborilmoqda...',
        'Отправка...',
        'Submitting...',
      );

  static String submitted(Locale l) => _pick(
        l,
        'Ariza yuborildi ✓',
        'Заявка отправлена ✓',
        'Application sent ✓',
      );
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.result, required this.locale});
  final CalculatorResult result;
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
            fmtUzsPublic(locale, result.totalUzs),
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
            result.note,
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
  final CalculatorResult result;

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
                    rows[i].value,
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
