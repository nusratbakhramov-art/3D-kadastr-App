/// Wizard 9 stepdan keyin AI baholash natijasi ekrani.
///
/// `initState` da backend `/valuations/ai` ga so'rov yuboradi.
/// Loading paytida skeleton, javobdan keyin real breakdown ko'rsatiladi.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/app_toast.dart';
import '../../auth/auth_storage.dart';
import '../../market/widgets/listing_cta_button.dart';
import '../../settings/settings_state.dart';
import '../api_ai_valuation_service.dart';
import '../models/ai_valuation_result.dart';
import '../models/architecture_order_draft.dart';
import '../widgets/service_app_bar.dart';

class AiResultScreen extends StatefulWidget {
  const AiResultScreen({
    super.key,
    required this.draft,
    required this.scanCompleted,
  });

  final ArchitectureOrderDraft draft;
  final bool scanCompleted;

  @override
  State<AiResultScreen> createState() => _AiResultScreenState();
}

class _AiResultScreenState extends State<AiResultScreen> {
  AiValuationResult? _result;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _confirmationSubmitted = false;

  @override
  void initState() {
    super.initState();
    _runValuation();
  }

  Widget _buildCta(Locale locale) {
    // Loading yoki xato — faqat "Yopish" tugmasi.
    if (_loading || _result == null) {
      return ListingCtaButton(
        label: _AiResultStrings.close(locale),
        enabled: !_loading,
        onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
      );
    }

    // Ariza muvaffaqiyatli yuborilgan — tugma "Yopish" ga o'zgaradi.
    if (_confirmationSubmitted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10,
            ),
            decoration: BoxDecoration(
              color: AppColors.splashGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.splashGreen,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _AiResultStrings.submittedHint(locale),
                    style: TextStyle(
                      fontFamily: 'MTSText',
                      fontSize: 12.5,
                      height: 1.3,
                      color: AppColors.splashGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ListingCtaButton(
            label: _AiResultStrings.close(locale),
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      );
    }

    // Asosiy holat — "Narxni tasdiqlash uchun ariza yuborish" tugmasi.
    return ListingCtaButton(
      label: _submitting
          ? _AiResultStrings.submitting(locale)
          : _AiResultStrings.submitConfirmation(locale),
      enabled: !_submitting && _result?.historyId != null,
      onTap: _submitConfirmation,
    );
  }

  Future<void> _submitConfirmation() async {
    if (_submitting || _confirmationSubmitted) return;
    final result = _result;
    if (result == null || result.historyId == null) return;
    setState(() => _submitting = true);
    try {
      final api = AiValuationApiService();
      await api.submitConfirmation(historyId: result.historyId!);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _confirmationSubmitted = true;
      });
      AppToast.success(
        context,
        _AiResultStrings.submitOk(localeNotifier.value),
      );
    } on AiValuationApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.error(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppToast.error(
        context,
        '${_AiResultStrings.errorTitle(localeNotifier.value)}: $e',
      );
    }
  }

  Future<void> _runValuation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final session = await const AuthStorage().loadSession();
      final token = session.token;
      if (token == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = switch (Localizations.localeOf(context).languageCode) {
              'ru' =>
                'Чтобы воспользоваться AI оценкой, сначала войдите в систему.',
              'en' => 'Please sign in first to use AI valuation.',
              _ => 'AI baholash uchun avval tizimga kiring.',
            };
          });
        }
        return;
      }
      final api = AiValuationApiService();
      final result = await api.compute(
        draft: widget.draft,
        token: token,
        scanCompleted: widget.scanCompleted,
        locale: localeNotifier.value.languageCode,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on AiValuationApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            '${_AiResultStrings.networkError(localeNotifier.value)}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) => _build(context, locale),
    );
  }

  Widget _build(BuildContext context, Locale locale) {
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
                        title: _AiResultStrings.appBarTitle(locale),
                        subtitle: _AiResultStrings.appBarSubtitle(locale),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        children: [
                          if (_loading) ...[
                            _LoadingHeader(
                              headingColor: headingColor,
                              subColor: subColor,
                              locale: locale,
                            ),
                            const SizedBox(height: 16),
                            const _PriceSkeleton(),
                            const SizedBox(height: 14),
                            const _BreakdownSkeleton(),
                          ] else if (_error != null) ...[
                            _ErrorBlock(
                              message: _error!,
                              onRetry: _runValuation,
                              locale: locale,
                            ),
                          ] else if (_result != null) ...[
                            Text(
                              _AiResultStrings.estimatedTitle(locale),
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: subColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PriceCard(result: _result!, locale: locale),
                            if (_result!.fallbackUsed) ...[
                              const SizedBox(height: 12),
                              _FallbackWarning(
                                message: _result!.fallbackReason ??
                                    _AiResultStrings.fallbackDefault(locale),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Text(
                              _AiResultStrings.breakdownTitle(locale),
                              style: TextStyle(
                                fontFamily: 'MTSCompact',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: headingColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _AiResultStrings.basedOn(
                                locale,
                                _result!.comparablesCount,
                              ),
                              style: TextStyle(
                                fontFamily: 'MTSText',
                                fontSize: 12,
                                color: subColor,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _BreakdownCard(
                              result: _result!,
                              locale: locale,
                            ),
                            if (_result!.breakdown.approaches.isNotEmpty) ...[
                              const SizedBox(height: 22),
                              Text(
                                _AiResultStrings.approachesTitle(locale),
                                style: TextStyle(
                                  fontFamily: 'MTSCompact',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: headingColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _AiResultStrings.approachesSubtitle(locale),
                                style: TextStyle(
                                  fontFamily: 'MTSText',
                                  fontSize: 12,
                                  color: subColor,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _ApproachesCard(
                                approaches: _result!.breakdown.approaches,
                              ),
                            ],
                            if (_result!.summary != null &&
                                _result!.summary!.isNotEmpty) ...[
                              const SizedBox(height: 22),
                              Text(
                                _AiResultStrings.summaryTitle(locale),
                                style: TextStyle(
                                  fontFamily: 'MTSCompact',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: headingColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _AiResultStrings.summarySubtitle(locale),
                                style: TextStyle(
                                  fontFamily: 'MTSText',
                                  fontSize: 12,
                                  color: subColor,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _SummaryCard(text: _result!.summary!),
                            ],
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildCta(locale),
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

// ────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ────────────────────────────────────────────────────────────────────────

class _LoadingHeader extends StatelessWidget {
  const _LoadingHeader({
    required this.headingColor,
    required this.subColor,
    required this.locale,
  });
  final Color headingColor;
  final Color subColor;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _AiResultStrings.computing(locale),
          style: TextStyle(
            fontFamily: 'MTSCompact',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: headingColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _AiResultStrings.computingSub(locale),
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
  const _PriceCard({required this.result, required this.locale});
  final AiValuationResult result;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final valueColor = isDark ? Colors.white : AppColors.textBlack;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);

    final confPct = (result.confidence * 100).round();

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
            _fmtUzs(result.estimatedValue, locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 26,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_AiResultStrings.range(locale)}: ${_fmtUzs(result.rangeLow, locale)} – ${_fmtUzs(result.rangeHigh, locale)}',
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: confPct >= 70
                      ? AppColors.splashGreen
                      : (confPct >= 50
                          ? const Color(0xFFE0A82A)
                          : const Color(0xFFE0492A)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_AiResultStrings.confidence(locale)}: $confPct%',
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

class _FallbackWarning extends StatelessWidget {
  const _FallbackWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark
        ? const Color(0xFF332B1A)
        : const Color(0xFFFFF6E0);
    final textColor = isDark
        ? const Color(0xFFFFD68A)
        : const Color(0xFF8A6F1A);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: textColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'MTSText',
                fontSize: 12.5,
                height: 1.3,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.result, required this.locale});
  final AiValuationResult result;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    final adjustments = result.breakdown.adjustments;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Asosiy narx (1 m² ↔ jami)
          _BreakdownRow(
            label: _AiResultStrings.basePricePerSqm(locale),
            valueText: _fmtUzs(result.breakdown.basePricePerSqm, locale),
            badge: '1 m²',
            badgeColor: Colors.transparent,
            badgeTextColor: AppColors.splashGreen,
            labelColor: labelColor,
            valueColor: valueColor,
          ),
          Container(height: 1, color: divider),
          _BreakdownRow(
            label: _AiResultStrings.baseValue(locale),
            valueText: _fmtUzs(result.breakdown.baseValue, locale),
            badge: null,
            badgeColor: Colors.transparent,
            badgeTextColor: AppColors.splashGreen,
            labelColor: labelColor,
            valueColor: valueColor,
          ),
          // Har bir adjustment alohida
          for (var i = 0; i < adjustments.length; i++) ...[
            Container(height: 1, color: divider),
            _BreakdownRow(
              label: adjustments[i].name,
              valueText: '${adjustments[i].delta >= 0 ? '+' : ''}'
                  '${_fmtUzs(adjustments[i].delta, locale)}',
              badge: '${adjustments[i].percent >= 0 ? '+' : ''}'
                  '${adjustments[i].percent.toStringAsFixed(adjustments[i].percent.truncateToDouble() == adjustments[i].percent ? 0 : 1)}%',
              badgeColor: Colors.transparent,
              badgeTextColor: adjustments[i].percent >= 0
                  ? AppColors.splashGreen
                  : const Color(0xFFE0492A),
              labelColor: labelColor,
              valueColor: valueColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.valueText,
    required this.badge,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.labelColor,
    required this.valueColor,
  });

  final String label;
  final String valueText;
  final String? badge;
  final Color badgeColor;
  final Color badgeTextColor;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 13,
                    color: labelColor,
                  ),
                ),
              ),
              if (badge != null)
                Text(
                  badge!,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: badgeTextColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valueText,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApproachesCard extends StatelessWidget {
  const _ApproachesCard({required this.approaches});
  final List<AiApproachResult> approaches;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final divider = isDark ? const Color(0xFF2C3133) : const Color(0xFFEEF0F2);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8A9097);
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < approaches.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          approaches[i].name,
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 13,
                            color: labelColor,
                          ),
                        ),
                      ),
                      Text(
                        '${(approaches[i].weight * 100).toStringAsFixed(0)}%',
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
                    approaches[i].value == null
                        ? '—'
                        : _fmtUzs(approaches[i].value!, locale),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.25,
                      color: approaches[i].value == null
                          ? labelColor
                          : valueColor,
                    ),
                  ),
                ],
              ),
            ),
            if (i != approaches.length - 1)
              Container(height: 1, color: divider),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textBlack;
    final accentBg = isDark
        ? AppColors.splashGreen.withValues(alpha: 0.18)
        : AppColors.splashGreen.withValues(alpha: 0.12);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: AppColors.splashGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'AI',
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppColors.splashGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              height: 1.5,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.message,
    required this.onRetry,
    required this.locale,
  });
  final String message;
  final VoidCallback onRetry;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2426) : Colors.white;
    final valueColor = isDark ? Colors.white : AppColors.textBlack;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 28,
            color: const Color(0xFFE0492A),
          ),
          const SizedBox(height: 10),
          Text(
            _AiResultStrings.errorTitle(locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 13,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(_AiResultStrings.retry(locale)),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Skeletons (loading)
// ────────────────────────────────────────────────────────────────────────

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
              for (var i = 0; i < 4; i++) ...[
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
                if (i != 3) Container(height: 1, color: divider),
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

// ────────────────────────────────────────────────────────────────────────
// Helpers + i18n
// ────────────────────────────────────────────────────────────────────────

String _fmtUzs(num value, Locale l) {
  // Group thousands with non-breaking spaces for readability.
  final rounded = value.abs().round();
  final s = rounded.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  final sign = value < 0 ? '-' : '';
  return '$sign${buf.toString()} ${_AiResultStrings.soum(l)}';
}

class _AiResultStrings {
  static String soum(Locale l) => switch (l.languageCode) {
        'ru' => 'сум',
        'en' => 'soum',
        _ => 'so\'m',
      };

  static String networkError(Locale l) => switch (l.languageCode) {
        'ru' => 'Сетевая ошибка',
        'en' => 'Network error',
        _ => 'Tarmoq xatosi',
      };

  static String appBarTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'AI Оценка',
        'en' => 'AI Valuation',
        _ => 'AI Baholash',
      };

  static String appBarSubtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Результат',
        'en' => 'Result',
        _ => 'Natija',
      };

  static String estimatedTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Ориентировочная рыночная стоимость',
        'en' => 'Estimated market value',
        _ => 'Taxminiy bozor qiymati',
      };

  static String range(Locale l) => switch (l.languageCode) {
        'ru' => 'Диапазон',
        'en' => 'Range',
        _ => 'Diapazon',
      };

  static String confidence(Locale l) => switch (l.languageCode) {
        'ru' => 'Уверенность',
        'en' => 'Confidence',
        _ => 'Ishonchlilik',
      };

  static String breakdownTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Структура расчёта',
        'en' => 'Breakdown',
        _ => 'Hisob-kitob tarkibi',
      };

  static String basedOn(Locale l, int n) => switch (l.languageCode) {
        'ru' => 'Использовано $n похожих объявлений',
        'en' => 'Based on $n similar listings',
        _ => '$n ta o\'xshash e\'lon asosida',
      };

  static String basePricePerSqm(Locale l) => switch (l.languageCode) {
        'ru' => 'Базовая цена за м²',
        'en' => 'Base price per m²',
        _ => 'Asosiy narx (1 m²)',
      };

  static String baseValue(Locale l) => switch (l.languageCode) {
        'ru' => 'Базовая стоимость',
        'en' => 'Base value',
        _ => 'Asosiy qiymat',
      };

  static String computing(Locale l) => switch (l.languageCode) {
        'ru' => 'AI считает оценку...',
        'en' => 'AI is computing the valuation...',
        _ => 'AI baholash hisoblanmoqda...',
      };

  static String computingSub(Locale l) => switch (l.languageCode) {
        'ru' => 'Анализ похожих объявлений и расчёт корректировок.',
        'en' => 'Analyzing similar listings and computing adjustments.',
        _ => 'O\'xshash e\'lonlar tahlil qilinmoqda va korrektirovkalar hisoblanmoqda.',
      };

  static String fallbackDefault(Locale l) => switch (l.languageCode) {
        'ru' => 'Расчёт основан на расширенной выборке.',
        'en' => 'Estimate is based on a broader dataset.',
        _ => 'Hisob kengaytirilgan namuna asosida qilindi.',
      };

  static String errorTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Не удалось рассчитать',
        'en' => 'Could not compute',
        _ => 'Hisoblab bo\'lmadi',
      };

  static String retry(Locale l) => switch (l.languageCode) {
        'ru' => 'Повторить',
        'en' => 'Retry',
        _ => 'Qayta urinish',
      };

  static String close(Locale l) => switch (l.languageCode) {
        'ru' => 'Закрыть',
        'en' => 'Close',
        _ => 'Yopish',
      };

  static String summaryTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'AI анализ',
        'en' => 'AI analysis',
        _ => 'AI tahlili',
      };

  static String summarySubtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Почему получилась такая цена',
        'en' => 'Why the price came out this way',
        _ => 'Nima uchun shunday narx chiqdi',
      };

  static String submitConfirmation(Locale l) => switch (l.languageCode) {
        'ru' => 'Подтвердить цену через специалиста',
        'en' => 'Submit for specialist confirmation',
        _ => 'Narxni tasdiqlash uchun ariza yuborish',
      };

  static String submitting(Locale l) => switch (l.languageCode) {
        'ru' => 'Отправка...',
        'en' => 'Submitting...',
        _ => 'Yuborilmoqda...',
      };

  static String submitOk(Locale l) => switch (l.languageCode) {
        'ru' => 'Заявка отправлена. Специалист рассмотрит её в течение 24 часов.',
        'en' => 'Application sent. A specialist will review it within 24 hours.',
        _ => 'Arizangiz yuborildi. Mutaxassis 24 soat ichida ko\'rib chiqadi.',
      };

  static String submittedHint(Locale l) => switch (l.languageCode) {
        'ru' => 'Заявка в очереди на проверку.',
        'en' => 'Your application is queued for review.',
        _ => 'Arizangiz mutaxassis ko\'rib chiqishida.',
      };

  static String approachesTitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Подходы к оценке',
        'en' => 'Valuation approaches',
        _ => 'Yondashuvlar bo\'yicha',
      };

  static String approachesSubtitle(Locale l) => switch (l.languageCode) {
        'ru' => 'Стоимость рассчитана по 3 классическим методам',
        'en' => 'Value computed via 3 classical methods',
        _ => 'Qiymat 3 klassik usul orqali hisoblandi',
      };
}
