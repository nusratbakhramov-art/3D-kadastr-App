import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/i18n.dart';
import '../../core/i18n/app_translations.dart';
import '../../theme/app_colors.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import 'payment_checkout_service.dart';

/// To'lovlar tarixi — status bo'yicha filtr chiplar bilan. Backend `GET
/// /payments/?status=...` server tomonда filtrlaydi.
class MyPaymentsScreen extends StatefulWidget {
  const MyPaymentsScreen({super.key, this.service});

  final PaymentCheckoutService? service;

  @override
  State<MyPaymentsScreen> createState() => _MyPaymentsScreenState();
}

/// Filtr chip — `value` null = barchasi, aks holda backend status qiymati.
class _Filter {
  const _Filter(this.value);
  final String? value;
}

const _filters = <_Filter>[
  _Filter(null),
  _Filter('completed'),
  _Filter('pending'),
  _Filter('processing'),
  _Filter('cancelled'),
  _Filter('failed'),
];

class _MyPaymentsScreenState extends State<MyPaymentsScreen> {
  late final PaymentCheckoutService _service;
  String? _filter; // null = barchasi
  bool _loading = true;
  Object? _error;
  List<PaymentRecord> _items = const [];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PaymentCheckoutService();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.list(status: _filter);
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _selectFilter(String? value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Scaffold(
      backgroundColor: ColorTokens.scaffoldBg(context),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AppGlowBackground(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: AppHeaderBack(title: _S.title(locale)),
                ),
                const SizedBox(height: 12),
                _FilterChips(
                  selected: _filter,
                  onSelect: _selectFilter,
                  locale: locale,
                ),
                const SizedBox(height: 12),
                Expanded(child: _body(context, locale)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, Locale locale) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.wifi_off_rounded,
        title: _S.errorTitle(locale),
        actionLabel: L.retry(locale),
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return _CenteredMessage(
        icon: Icons.receipt_long_outlined,
        title: _S.empty(locale),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _PaymentTile(record: _items[i], locale: locale),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.onSelect,
    required this.locale,
  });

  final String? selected;
  final ValueChanged<String?> onSelect;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final active = f.value == selected;
          return GestureDetector(
            onTap: hapticSelect(() => onSelect(f.value)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.splashGreen
                    : ColorTokens.cardBg(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? AppColors.splashGreen
                      : ColorTokens.outline(context),
                  width: 1,
                ),
              ),
              child: Text(
                _S.filterLabel(locale, f.value),
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: active
                      ? AppColors.buttonTextBlack
                      : ColorTokens.secondaryText(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.record, required this.locale});

  final PaymentRecord record;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final (Color sColor, String sLabel) = _statusStyle(context, locale, record.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ColorTokens.iconBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _typeIcon(record.paymentType),
              size: 21,
              color: ColorTokens.secondaryText(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _S.typeLabel(locale, record.paymentType),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: ColorTokens.primaryText(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_fmtDate(record.createdAt)} · ${record.provider.toUpperCase()}',
                  style: TextStyle(
                    fontFamily: 'MTSText',
                    fontSize: 12,
                    color: ColorTokens.tertiaryText(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_fmtAmount(record.amount)} ${_S.currency(locale)}',
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: ColorTokens.primaryText(context),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  sLabel,
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: sColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: ColorTokens.tertiaryText(context)),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: ColorTokens.secondaryText(context),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

// ── helpers ───────────────────────────────────────────────────────────────

IconData _typeIcon(String type) => switch (type) {
      'ai_valuation' => Icons.analytics_outlined,
      'marketplace_purchase' => Icons.view_in_ar_outlined,
      'subscription' => Icons.workspace_premium_outlined,
      'virtual_property_view' => Icons.home_work_outlined,
      _ => Icons.receipt_long_outlined,
    };

(Color, String) _statusStyle(BuildContext context, Locale l, String status) {
  return switch (status) {
    'completed' => (AppColors.splashGreen, _S.statusLabel(l, 'completed')),
    'pending' => (const Color(0xFFF27523), _S.statusLabel(l, 'pending')),
    'processing' => (const Color(0xFFF27523), _S.statusLabel(l, 'processing')),
    'failed' => (const Color(0xFFE0492A), _S.statusLabel(l, 'failed')),
    'cancelled' => (const Color(0xFFE0492A), _S.statusLabel(l, 'cancelled')),
    'refunded' => (ColorTokens.secondaryText(context), _S.statusLabel(l, 'refunded')),
    _ => (ColorTokens.secondaryText(context), status),
  };
}

String _fmtAmount(num v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _two(int n) => n < 10 ? '0$n' : '$n';

String _fmtDate(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';

// ── i18n ──────────────────────────────────────────────────────────────────

class _S {
  const _S._();

  static String title(Locale l) => tr(l, 'payments.my.title');

  static String empty(Locale l) => tr(l, 'payments.my.empty');

  static String errorTitle(Locale l) => tr(l, 'payments.my.load_failed');

  // Bare currency unit glued to the amount — locale-neutral, kept inline.
  static String currency(Locale l) => switch (l.languageCode) {
        'ru' => 'сум',
        'en' => 'UZS',
        _ => "so'm",
      };

  static String filterLabel(Locale l, String? value) => switch (value) {
        null => tr(l, 'payments.filter.all'),
        _ => statusLabel(l, value),
      };

  static String statusLabel(Locale l, String status) => switch (status) {
        'completed' => tr(l, 'payments.record.status.completed'),
        'pending' => tr(l, 'payments.record.status.pending'),
        'processing' => tr(l, 'payments.record.status.processing'),
        'failed' => tr(l, 'payments.record.status.failed'),
        'cancelled' => tr(l, 'payments.record.status.cancelled'),
        'refunded' => tr(l, 'payments.record.status.refunded'),
        _ => status,
      };

  static String typeLabel(Locale l, String type) => switch (type) {
        'ai_valuation' => tr(l, 'payments.record.type.ai_valuation'),
        'marketplace_purchase' => tr(l, 'payments.record.type.marketplace_purchase'),
        'subscription' => tr(l, 'payments.record.type.subscription'),
        'virtual_property_view' => tr(l, 'payments.record.type.virtual_property_view'),
        _ => tr(l, 'payments.record.type.other'),
      };
}
