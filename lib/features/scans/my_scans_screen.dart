import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../ratings/valuation_model.dart' show formatSum, formatShortDate;
import '../settings/settings_state.dart';
import 'api_scan_service.dart';
import 'scan_model.dart';

class MyScansScreen extends StatefulWidget {
  const MyScansScreen({super.key});

  @override
  State<MyScansScreen> createState() => _MyScansScreenState();
}

class _MyScansScreenState extends State<MyScansScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<MyScansScreen> {
  @override
  int get currentToken => 1;

  final _service = ApiScanService();
  List<ScanItem> _items = [];
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
      final items = await _service.fetchScans();
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
                            child: _ScanCard(item: items[i], locale: locale),
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

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.item, required this.locale});

  final ScanItem item;
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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusBadge(status: item.status, locale: locale),
                  const Spacer(),
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
              const SizedBox(height: 10),
              Text(
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
              const SizedBox(height: 4),
              Text(
                '${_S.cadastreNo(locale)}: ${item.cadastreNo}',
                style: TextStyle(
                  fontFamily: 'MTSText',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: ColorTokens.secondaryText(context),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    label: _S.objectType(locale),
                    value: item.objectType,
                  ),
                  _MetaChip(
                    label: _S.area(locale),
                    value: '${_fmt(item.totalAreaSqm)} m²',
                  ),
                  _MetaChip(
                    label: _S.accuracy(locale),
                    value: '${item.accuracyCm.toStringAsFixed(1)} sm',
                  ),
                  _MetaChip(
                    label: _S.cadastreValue(locale),
                    value: formatSum(item.cadastreValueUzs),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.locale});

  final ScanStatus status;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      ScanStatus.uploaded => (
        _S.statusUploaded(locale),
        const Color(0xFF6B7280),
      ),
      ScanStatus.processing => (
        _S.statusProcessing(locale),
        const Color(0xFFF59E0B),
      ),
      ScanStatus.valued => (_S.statusValued(locale), const Color(0xFF10B981)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ColorTokens.iconBg(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w400,
              fontSize: 12,
              color: ColorTokens.secondaryText(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: ColorTokens.primaryText(context),
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
              Icons.crop_free_rounded,
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
    final locale = Localizations.localeOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 40, color: ColorTokens.secondaryText(context)),
          const SizedBox(height: 12),
          Text(L.errorOccurred(locale), textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'MTSCompact', fontWeight: FontWeight.w700, fontSize: 16, color: ColorTokens.primaryText(context))),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text(L.retry(locale))),
        ],
      ),
    );
  }
}

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Мои сканирования',
    'en' => 'My scans',
    _ => 'Mening skanerlarim',
  };
  static String cadastreNo(Locale l) => switch (l.languageCode) {
    'ru' => 'Кадастровый №',
    'en' => 'Cadastre №',
    _ => 'Kadastr №',
  };
  static String objectType(Locale l) => switch (l.languageCode) {
    'ru' => 'Тип',
    'en' => 'Type',
    _ => 'Turi',
  };
  static String area(Locale l) => switch (l.languageCode) {
    'ru' => 'Площадь',
    'en' => 'Area',
    _ => 'Maydon',
  };
  static String accuracy(Locale l) => switch (l.languageCode) {
    'ru' => 'Точность',
    'en' => 'Accuracy',
    _ => 'Aniqlik',
  };
  static String cadastreValue(Locale l) => switch (l.languageCode) {
    'ru' => 'Кадастр. стоимость',
    'en' => 'Cadastre value',
    _ => 'Kadastr qiymati',
  };
  static String statusUploaded(Locale l) => switch (l.languageCode) {
    'ru' => 'Загружено',
    'en' => 'Uploaded',
    _ => 'Yuklandi',
  };
  static String statusProcessing(Locale l) => switch (l.languageCode) {
    'ru' => 'Обрабатывается',
    'en' => 'Processing',
    _ => 'Qayta ishlanmoqda',
  };
  static String statusValued(Locale l) => switch (l.languageCode) {
    'ru' => 'Оценено',
    'en' => 'Valued',
    _ => 'Baholandi',
  };
  static String emptyTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Сканирований пока нет',
    'en' => 'No scans yet',
    _ => 'Hali skaner yo‘q',
  };
  static String emptyMessage(Locale l) => switch (l.languageCode) {
    'ru' => 'Запустите 3D-сканирование объекта в разделе «Услуги».',
    'en' => 'Start a 3D scan from Services to populate this list.',
    _ => '«Xizmatlar» bo‘limidan birinchi 3D skanerni boshlang.',
  };
}
