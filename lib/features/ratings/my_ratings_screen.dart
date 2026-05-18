import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../settings/settings_state.dart';
import 'api_valuation_history_service.dart';
import 'valuation_model.dart';

class MyRatingsScreen extends StatefulWidget {
  const MyRatingsScreen({super.key});

  @override
  State<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends State<MyRatingsScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<MyRatingsScreen> {
  @override
  int get currentToken => 1;

  final _service = ApiValuationHistoryService();
  List<Valuation> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _service.fetchHistory();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        final items = _items;
        return Scaffold(
          backgroundColor: ColorTokens.scaffoldBg(context),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const AppGlowBackground(),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.0,
                          0.4,
                          curve: Curves.easeOutCubic,
                        ),
                        child: AppHeaderBack(title: _S.title(locale)),
                      ),
                      const SizedBox(height: 16),
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_error != null)
                        _ErrorState(onRetry: _load)
                      else if (items.isEmpty)
                        _EmptyState(
                          title: _S.emptyTitle(locale),
                          message: _S.emptyMessage(locale),
                        )
                      else
                        for (var i = 0; i < items.length; i++) ...[
                          AppReveal(
                            controller: entryController,
                            interval: Interval(
                              (0.1 + i * 0.06).clamp(0.0, 0.9),
                              (0.6 + i * 0.06).clamp(0.0, 1.0),
                              curve: Curves.easeOutCubic,
                            ),
                            child: _ValuationCard(
                              item: items[i],
                              locale: locale,
                            ),
                          ),
                          if (i != items.length - 1) const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ValuationCard extends StatelessWidget {
  const _ValuationCard({required this.item, required this.locale});

  final Valuation item;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorTokens.cardBg(context),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.3,
                        color: ColorTokens.primaryText(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatShortDate(item.at),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: ColorTokens.secondaryText(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${item.objectType} · ${item.areaSqm.toStringAsFixed(item.areaSqm.truncateToDouble() == item.areaSqm ? 0 : 1)} m²',
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                  color: ColorTokens.secondaryText(context),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _S.finalValue(locale),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: ColorTokens.secondaryText(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatSum(item.finalValue),
                          style: TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: ColorTokens.primaryText(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ConfidenceChip(value: item.confidence, locale: locale),
                ],
              ),
              const SizedBox(height: 14),
              _ComponentsRow(item: item, locale: locale),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComponentsRow extends StatelessWidget {
  const _ComponentsRow({required this.item, required this.locale});

  final Valuation item;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ComponentChip(
            label: _S.abc(locale),
            value: formatSum(item.abcValue),
            tint: const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ComponentChip(
            label: _S.market(locale),
            value: formatSum(item.marketValue),
            tint: const Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ComponentChip(
            label: _S.income(locale),
            value: item.incomeValue != null
                ? formatSum(item.incomeValue!)
                : '—',
            tint: const Color(0xFF10B981),
            disabled: item.incomeValue == null,
          ),
        ),
      ],
    );
  }
}

class _ComponentChip extends StatelessWidget {
  const _ComponentChip({
    required this.label,
    required this.value,
    required this.tint,
    this.disabled = false,
  });

  final String label;
  final String value;
  final Color tint;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final tintFinal = disabled ? const Color(0xFFE5E7EB) : tint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tintFinal.withValues(alpha: disabled ? 0.5 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tintFinal.withValues(alpha: disabled ? 0.4 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: disabled
                  ? ColorTokens.tertiaryText(context)
                  : tintFinal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.2,
              color: disabled
                  ? ColorTokens.tertiaryText(context)
                  : ColorTokens.primaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.value, required this.locale});

  final double value;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    final tier = value >= 0.85
        ? const Color(0xFF10B981)
        : value >= 0.7
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tier.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_graph_rounded, size: 14, color: tier),
          const SizedBox(width: 4),
          Text(
            '${_S.confidence(locale)} $pct%',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: tier,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: ColorTokens.cardBg(context),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: ColorTokens.shadow(context),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.bar_chart_rounded,
              size: 28,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              color: ColorTokens.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 40, color: ColorTokens.secondaryText(context)),
          const SizedBox(height: 12),
          Text('Xatolik yuz berdi', textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'MTSCompact', fontWeight: FontWeight.w700, fontSize: 16, color: ColorTokens.primaryText(context))),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Qayta urinish')),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Мои оценки',
    'en' => 'My valuations',
    _ => 'Baholashlarim',
  };
  static String finalValue(Locale l) => switch (l.languageCode) {
    'ru' => 'Итоговая оценка',
    'en' => 'Final valuation',
    _ => 'Yakuniy baho',
  };
  static String abc(Locale l) => switch (l.languageCode) {
    'ru' => 'ABC индекс',
    'en' => 'ABC index',
    _ => 'ABC indeks',
  };
  static String market(Locale l) => switch (l.languageCode) {
    'ru' => 'Рынок',
    'en' => 'Market',
    _ => 'Bozor',
  };
  static String income(Locale l) => switch (l.languageCode) {
    'ru' => 'Доходность',
    'en' => 'Income',
    _ => 'Daromadlilik',
  };
  static String confidence(Locale l) => switch (l.languageCode) {
    'ru' => 'Точность',
    'en' => 'Confidence',
    _ => 'Ishonch',
  };
  static String emptyTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Оценок пока нет',
    'en' => 'No valuations yet',
    _ => 'Hali baholashlar yo‘q',
  };
  static String emptyMessage(Locale l) => switch (l.languageCode) {
    'ru' => 'Сделайте 3D-сканирование объекта, чтобы получить AI-оценку.',
    'en' => 'Run a 3D scan to get an AI valuation.',
    _ => 'AI bahoni olish uchun obyektni 3D skan qiling.',
  };
}
