import 'package:flutter/material.dart';

import '../../core/api_config.dart';

enum NotificationType { system, payment, scan, valuation, listing }

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.at,
    this.imageUrl,
    this.unread = true,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime at;

  /// Ixtiyoriy rasm (adminkadan yuborilgan bildirishnomalarda). Absolyut URL.
  final String? imageUrl;
  final bool unread;

  AppNotification copyWith({bool? unread}) => AppNotification(
    id: id,
    type: type,
    title: title,
    message: message,
    at: at,
    imageUrl: imageUrl,
    unread: unread ?? this.unread,
  );

  /// Backend `/profile/notifications` javobidagi bitta element.
  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawImage = json['image_url'] as String?;
    final created = json['created_at'] as String?;
    return AppNotification(
      id: '${json['id']}',
      type: _typeFromString(json['notification_type'] as String?),
      title: (json['title'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      at: created != null
          ? (DateTime.tryParse(created)?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      imageUrl: (rawImage == null || rawImage.isEmpty)
          ? null
          : ApiConfig.resolveUrl(rawImage),
      unread: !((json['is_read'] as bool?) ?? false),
    );
  }
}

NotificationType _typeFromString(String? t) => switch (t) {
  'payment_status' || 'payment' => NotificationType.payment,
  'scan_completed' || 'scan' => NotificationType.scan,
  'valuation_done' || 'valuation_failed' || 'valuation' => NotificationType.valuation,
  'listing' || 'moderation_result' => NotificationType.listing,
  _ => NotificationType.system,
};

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
