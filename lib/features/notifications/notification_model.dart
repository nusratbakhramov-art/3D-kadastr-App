import 'package:flutter/material.dart';

enum NotificationType { system, payment, scan, valuation, listing }

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.at,
    this.unread = true,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime at;
  final bool unread;

  AppNotification copyWith({bool? unread}) => AppNotification(
    id: id,
    type: type,
    title: title,
    message: message,
    at: at,
    unread: unread ?? this.unread,
  );
}

/// Globally-visible list of notifications. Bell counter is derived from this.
final ValueNotifier<List<AppNotification>> notificationsNotifier =
    ValueNotifier<List<AppNotification>>(_seed());

void markAllNotificationsRead() {
  notificationsNotifier.value = [
    for (final n in notificationsNotifier.value) n.copyWith(unread: false),
  ];
}

void markNotificationRead(String id) {
  notificationsNotifier.value = [
    for (final n in notificationsNotifier.value)
      if (n.id == id) n.copyWith(unread: false) else n,
  ];
}

int unreadNotificationCount() =>
    notificationsNotifier.value.where((n) => n.unread).length;

(IconData, Color) iconForType(NotificationType t) => switch (t) {
  NotificationType.system => (
    Icons.info_outline_rounded,
    const Color(0xFF6B7280),
  ),
  NotificationType.payment => (
    Icons.payments_outlined,
    const Color(0xFF3B82F6),
  ),
  NotificationType.scan => (Icons.crop_free_rounded, const Color(0xFF10B981)),
  NotificationType.valuation => (
    Icons.trending_up_rounded,
    const Color(0xFF8B5CF6),
  ),
  NotificationType.listing => (Icons.list_alt_rounded, const Color(0xFFF59E0B)),
};

List<AppNotification> _seed() {
  final now = DateTime.now();
  DateTime today(int hour, int minute) =>
      DateTime(now.year, now.month, now.day, hour, minute);
  DateTime daysAgo(int days, int hour, int minute) {
    final d = now.subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  return [
    AppNotification(
      id: 'n1',
      type: NotificationType.valuation,
      title: 'AI baholash tayyor',
      message:
          'Toshkent, Yunusobod tumani obyekti uchun yakuniy baho tayyorlandi.',
      at: today(11, 24),
    ),
    AppNotification(
      id: 'n2',
      type: NotificationType.payment,
      title: 'To‘lov muvaffaqiyatli',
      message: '3D skan xizmati uchun 250 000 so‘m to‘landi (Click).',
      at: today(9, 48),
    ),
    AppNotification(
      id: 'n3',
      type: NotificationType.scan,
      title: 'Skan qayta ishlanmoqda',
      message:
          'Sergeli, Quruvchilar ko‘chasi obyekti server tomonida tahlilda.',
      at: daysAgo(1, 18, 12),
    ),
    AppNotification(
      id: 'n4',
      type: NotificationType.listing,
      title: 'E‘lon tasdiqlandi',
      message: '"Yunusobod 2-xonadon" e‘loni moderatsiyadan o‘tdi.',
      at: daysAgo(1, 14, 30),
      unread: false,
    ),
    AppNotification(
      id: 'n5',
      type: NotificationType.system,
      title: 'Yangi qurilmadan kirish',
      message: 'Sizning hisobingizga yangi qurilmadan kirish amalga oshirildi.',
      at: daysAgo(3, 21, 5),
      unread: false,
    ),
    AppNotification(
      id: 'n6',
      type: NotificationType.payment,
      title: 'Hisob-faktura yaratildi',
      message: 'AI baholash uchun 120 000 so‘m miqdorida hisob-faktura tayyor.',
      at: daysAgo(5, 10, 0),
      unread: false,
    ),
  ];
}
