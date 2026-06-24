import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../theme/color_tokens.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_toast.dart';
import '../settings/settings_state.dart';
import 'api_payments_service.dart';
import 'payment_model.dart';
import 'payment_receipt_sheet.dart';
import 'payment_status_chip.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<PaymentsScreen> {
  @override
  int get currentToken => 1;

  final _service = ApiPaymentsService();
  List<Payment> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load(initial: true));
  }

  Future<void> _load({bool initial = false}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await _service.fetchPayments();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_items.isEmpty) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      } else {
        // Refresh failed but we still have data — keep it, surface a toast.
        setState(() => _loading = false);
        AppToast.error(context, L.errorOccurred(Localizations.localeOf(context)));
      }
    }
  }

  Future<void> _openReceipt(Payment p) => showPaymentReceiptSheet(context, p);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return Scaffold(
          backgroundColor: ColorTokens.scaffoldBg(context),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const AppGlowBackground(),
              SafeArea(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: ColorTokens.brandPrimary(context),
                  backgroundColor: ColorTokens.cardBg(context),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                        ..._buildBody(locale),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildBody(Locale locale) {
    if (_loading) return const [_LoadingState()];
    if (_error != null) return [_ErrorState(onRetry: () => _load(initial: true))];
    if (_items.isEmpty) {
      return [
        _EmptyState(
          title: _S.emptyTitle(locale),
          message: _S.emptyMessage(locale),
        ),
      ];
    }

    final completedTotal = _items
        .where((p) => p.status.isCompleted)
        .fold<int>(0, (s, p) => s + p.amount);
    final groups = _groupByMonth(_items, locale);

    return [
      AppReveal(
        controller: entryController,
        interval: const Interval(0.1, 0.6, curve: Curves.easeOutCubic),
        child: _SummaryCard(
          total: completedTotal,
          count: _items.length,
          locale: locale,
        ),
      ),
      const SizedBox(height: 22),
      ..._renderGroups(groups, locale),
    ];
  }

  List<Widget> _renderGroups(
    List<({String label, List<Payment> items})> groups,
    Locale locale,
  ) {
    final out = <Widget>[];
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      out.add(
        AppReveal(
          controller: entryController,
          interval: Interval(
            (0.2 + gi * 0.08).clamp(0.0, 0.9),
            (0.7 + gi * 0.08).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Builder(
              builder: (context) => Text(
                g.label,
                style: TextStyle(
                  fontFamily: 'MTSCompact',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: ColorTokens.secondaryText(context),
                ),
              ),
            ),
          ),
        ),
      );
      out.add(
        AppReveal(
          controller: entryController,
          interval: Interval(
            (0.25 + gi * 0.08).clamp(0.0, 0.9),
            (0.8 + gi * 0.08).clamp(0.0, 1.0),
            curve: Curves.easeOutCubic,
          ),
          child: _PaymentGroupCard(
            items: g.items,
            locale: locale,
            onTap: _openReceipt,
          ),
        ),
      );
      out.add(const SizedBox(height: 16));
    }
    return out;
  }

  List<({String label, List<Payment> items})> _groupByMonth(
    List<Payment> items,
    Locale locale,
  ) {
    final map = <String, List<Payment>>{};
    final order = <String>[];
    for (final p in items) {
      final key = '${p.at.year}-${p.at.month}';
      if (!map.containsKey(key)) order.add(key);
      map.putIfAbsent(key, () => []).add(p);
    }
    return [
      for (final k in order)
        (label: _monthLabel(map[k]!.first.at, locale), items: map[k]!),
    ];
  }

  String _monthLabel(DateTime d, Locale l) {
    const months = {
      'uz': [
        'yanvar',
        'fevral',
        'mart',
        'aprel',
        'may',
        'iyun',
        'iyul',
        'avgust',
        'sentabr',
        'oktabr',
        'noyabr',
        'dekabr',
      ],
      'ru': [
        'январь',
        'февраль',
        'март',
        'апрель',
        'май',
        'июнь',
        'июль',
        'август',
        'сентябрь',
        'октябрь',
        'ноябрь',
        'декабрь',
      ],
      'en': [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ],
    };
    final list = months[l.languageCode] ?? months['uz']!;
    final name = list[d.month - 1];
    return '$name ${d.year}';
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.count,
    required this.locale,
  });

  final int total;
  final int count;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26034112),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A6B23), Color(0xFF034112)],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Positioned(
                right: -22,
                top: -22,
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 120,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _S.totalSpent(locale),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          groupDigits(total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w800,
                            fontSize: 30,
                            height: 1.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          soumLabel(locale),
                          style: TextStyle(
                            fontFamily: 'MTSText',
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.swap_vert_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$count ${_S.transactions(locale)}',
                          style: const TextStyle(
                            fontFamily: 'MTSCompact',
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment list
// ---------------------------------------------------------------------------

class _PaymentGroupCard extends StatelessWidget {
  const _PaymentGroupCard({
    required this.items,
    required this.locale,
    required this.onTap,
  });

  final List<Payment> items;
  final Locale locale;
  final ValueChanged<Payment> onTap;

  @override
  Widget build(BuildContext context) {
    final dividerColor = ColorTokens.divider(context);
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(
        _PaymentTile(
          item: items[i],
          locale: locale,
          onTap: () => onTap(items[i]),
        ),
      );
      if (i != items.length - 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.cardBg(context),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({
    required this.item,
    required this.locale,
    required this.onTap,
  });

  final Payment item;
  final Locale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = ColorTokens.brandPrimary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ColorTokens.iconBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(item.type.icon, size: 20, color: brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title(locale),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'MTSCompact',
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: ColorTokens.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.method.displayName} · ${_dayMonth(item.at)}',
                      style: TextStyle(
                        fontFamily: 'MTSText',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: ColorTokens.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatMoney(item.amount, locale),
                    style: TextStyle(
                      fontFamily: 'MTSCompact',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: ColorTokens.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 5),
                  PaymentStatusChip(
                    status: item.status,
                    locale: locale,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: ColorTokens.tertiaryText(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dayMonth(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

// ---------------------------------------------------------------------------
// States: loading / error / empty
// ---------------------------------------------------------------------------

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SkeletonBox(height: 132, radius: 22),
        const SizedBox(height: 22),
        const _SkeletonBox(width: 90, height: 13),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: ColorTokens.cardBg(context),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                const _SkeletonTile(),
                if (i != 2)
                  Padding(
                    padding: const EdgeInsets.only(left: 64),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: ColorTokens.divider(context),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _SkeletonBox(width: 40, height: 40, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 130, height: 13),
                SizedBox(height: 7),
                _SkeletonBox(width: 80, height: 11),
              ],
            ),
          ),
          SizedBox(width: 12),
          _SkeletonBox(width: 64, height: 13),
        ],
      ),
    );
  }
}

/// Lightweight pulsing skeleton placeholder.
class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox({
    this.width = double.infinity,
    required this.height,
    this.radius = 7,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ColorTokens.iconBg(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
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
              Icons.wifi_off_rounded,
              size: 28,
              color: ColorTokens.secondaryText(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            L.errorOccurred(locale),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: ColorTokens.primaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text(L.retry(locale))),
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
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 24),
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
              Icons.receipt_long_outlined,
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

class _S {
  const _S._();

  static String title(Locale l) => switch (l.languageCode) {
    'ru' => 'Платежи',
    'en' => 'Payments',
    _ => 'To‘lovlar',
  };
  static String totalSpent(Locale l) => switch (l.languageCode) {
    'ru' => 'Всего потрачено',
    'en' => 'Total spent',
    _ => 'Jami sarflangan',
  };
  static String transactions(Locale l) => switch (l.languageCode) {
    'ru' => 'операций',
    'en' => 'transactions',
    _ => 'tranzaksiya',
  };
  static String emptyTitle(Locale l) => switch (l.languageCode) {
    'ru' => 'Платежей пока нет',
    'en' => 'No payments yet',
    _ => 'Hali to‘lovlar yo‘q',
  };
  static String emptyMessage(Locale l) => switch (l.languageCode) {
    'ru' => 'История ваших платежей появится здесь.',
    'en' => 'Your payment history will appear here.',
    _ => 'Sizning to‘lov tarixingiz shu yerda paydo bo‘ladi.',
  };
}
