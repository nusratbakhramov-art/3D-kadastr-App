import 'package:flutter/material.dart';

import '../../core/i18n/app_translations.dart';

/// Ro'yxatdagi kun sarlavhasi: "Bugun" / "Kecha" / "12.06.2026" — vaqtsiz.
///
/// Ro'yxatda sana har bir kartada takrorlanardi ("Kecha, 12:35" to'rt marta
/// ketma-ket). Kun — guruh, vaqt — satr; shuning uchun ikkiga ajratilgan.
String notificationDayLabel(DateTime at, Locale locale) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(at.year, at.month, at.day);
  if (d == today) return _today(locale);
  if (d == today.subtract(const Duration(days: 1))) return _yesterday(locale);
  return '${at.day.toString().padLeft(2, '0')}.'
      '${at.month.toString().padLeft(2, '0')}.${at.year}';
}

/// Bir kunning ichida satrlarni ajratadigan yagona narsa — "16:20".
String notificationTime(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

/// Bir kunga tegishli ekanini aniqlaydi (guruhlash uchun).
bool sameNotificationDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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

String _today(Locale l) => tr(l, 'notifications.today');

String _yesterday(Locale l) => tr(l, 'notifications.yesterday');
