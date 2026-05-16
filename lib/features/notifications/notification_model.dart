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
    ValueNotifier<List<AppNotification>>(const []);

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

