import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_glow_background.dart';
import '../../widgets/app_header_back.dart';
import '../../widgets/app_reveal.dart';
import '../ratings/valuation_model.dart' show formatSum;
import '../settings/settings_state.dart';
import 'payment_model.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with SingleTickerProviderStateMixin, RevealEntryMixin<PaymentsScreen> {
  @override
  int get currentToken => 1;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        final items = mockPayments;
        final total = items.fold<int>(0, (s, p) => s + p.amount);
        final groups = _groupByMonth(items, locale);

        return Scaffold(
          backgroundColor: AppColors.lightBackground,
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
                      AppReveal(
                        controller: entryController,
                        interval: const Interval(
                          0.1,
                          0.6,
                          curve: Curves.easeOutCubic,
                        ),
                        child: _SummaryCard(
                          total: total,
                          count: items.length,
                          locale: locale,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (items.isEmpty)
                        _EmptyState(
                          title: _S.emptyTitle(locale),
                          message: _S.emptyMessage(locale),
                        )
                      else
                        ..._renderGroups(groups, locale),
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
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
            child: Text(
              g.label,
              style: TextStyle(
                fontFamily: 'MTSCompact',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: AppColors.textBlack.withValues(alpha: 0.55),
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
          child: _PaymentGroupCard(items: g.items),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF034112), Color(0xFF0A6B23)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _S.totalSpent(locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatSum(total),
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count ${_S.transactions(locale)}',
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Colors.white,
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

class _PaymentGroupCard extends StatelessWidget {
  const _PaymentGroupCard({required this.items});

  final List<Payment> items;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(_PaymentTile(item: items[i]));
      if (i != items.length - 1) {
        children.add(
          const Padding(
            padding: EdgeInsets.only(left: 60),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFEFEFEF)),
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.item});

  final Payment item;

  @override
  Widget build(BuildContext context) {
    final accent = item.method.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.payments_outlined, size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: AppColors.textBlack,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.method.displayName} · ${_dayMonth(item.at)}',
                  style: TextStyle(
                    fontFamily: 'MTSCompact',
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: AppColors.textBlack.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatSum(item.amount),
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textBlack,
            ),
          ),
        ],
      ),
    );
  }

  String _dayMonth(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 28,
              color: AppColors.textBlack,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppColors.textBlack,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'MTSText',
              fontSize: 14,
              color: AppColors.textBlack.withValues(alpha: 0.55),
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
