import 'package:flutter/material.dart';

import '../../theme/color_tokens.dart';

/// "Bugun, 22:42" ko'rinishidagi sana yorlig'i (dizayndagi kulrang chip).
class NotificationDateChip extends StatelessWidget {
  const NotificationDateChip({super.key, required this.at, required this.locale});

  final DateTime at;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ColorTokens.iconBg(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 13,
            color: ColorTokens.secondaryText(context),
          ),
          const SizedBox(width: 6),
          Text(
            formatNotificationDate(at, locale),
            style: TextStyle(
              fontFamily: 'MTSCompact',
              fontWeight: FontWeight.w500,
              fontSize: 12.5,
              color: ColorTokens.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bugun, 22:42" / "Kecha, 22:42" / "12.06.2026, 22:42" (lokalizatsiya bilan).
String formatNotificationDate(DateTime at, Locale locale) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(at.year, at.month, at.day);
  final time =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  String? rel;
  if (d == today) {
    rel = _today(locale);
  } else if (d == today.subtract(const Duration(days: 1))) {
    rel = _yesterday(locale);
  }
  if (rel != null) return '$rel, $time';

  final date =
      '${at.day.toString().padLeft(2, '0')}.${at.month.toString().padLeft(2, '0')}.${at.year}';
  return '$date, $time';
}

String _today(Locale l) => switch (l.languageCode) {
  'ru' => 'Сегодня',
  'en' => 'Today',
  _ => 'Bugun',
};

String _yesterday(Locale l) => switch (l.languageCode) {
  'ru' => 'Вчера',
  'en' => 'Yesterday',
  _ => 'Kecha',
};
