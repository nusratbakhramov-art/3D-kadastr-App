import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import '../auth/auth_http_client.dart';
import '../auth/auth_storage.dart';
import '../home/user_profile.dart';
import 'notification_model.dart';

/// Backend `/profile/notifications` bilan ishlovchi servis.
class NotificationsApi {
  NotificationsApi({AuthStorage? storage, http.Client? client})
    : _storage = storage ?? const AuthStorage(),
      _client = client ?? AuthHttpClient();

  final AuthStorage _storage;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 15);

  Future<String?> _token() async => (await _storage.loadSession()).token;

  Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  /// Ro'yxat + umumiy va o'qilmagan soni. Login qilmagan bo'lsa bo'sh.
  Future<({List<AppNotification> items, int total, int unread})> fetch({
    int page = 1,
    int size = 50,
  }) async {
    final token = await _token();
    if (token == null) return (items: <AppNotification>[], total: 0, unread: 0);

    final res = await _client
        .get(
          Uri.parse('${ApiConfig.baseUrl}/profile/notifications?page=$page&size=$size'),
          headers: _headers(token),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Bildirishnomalarni yuklab bo\'lmadi (${res.statusCode})');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final rawItems = (body['items'] as List?) ?? const [];
    final items = rawItems
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      items: items,
      total: (body['total'] as int?) ?? items.length,
      unread: (body['unread_count'] as int?) ?? 0,
    );
  }

  Future<void> markRead(String id) async {
    final token = await _token();
    if (token == null) return;
    await _client
        .post(
          Uri.parse('${ApiConfig.baseUrl}/profile/notifications/$id/read'),
          headers: _headers(token),
        )
        .timeout(_timeout);
  }

  /// 2xx bo'lmasa OTADI — chaqiruvchi xatoni ko'rsatishi uchun.
  ///
  /// Avval javob kodi umuman tekshirilmasdi: server 500 qaytarsa ham
  /// "bajarildi" deb hisoblanardi va foydalanuvchi o'qilmagan xabarlar
  /// yo'qolgan deb o'ylardi.
  Future<void> markAllRead() async {
    final token = await _token();
    if (token == null) return;
    final response = await _client
        .post(
          Uri.parse('${ApiConfig.baseUrl}/profile/notifications/read-all'),
          headers: _headers(token),
        )
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('read-all: HTTP ${response.statusCode}');
    }
  }
}

/// Backenddan ro'yxatni olib, global notifierlarni yangilaydi (bell badge ham).
/// Xato/bo'sh holatda jim qaytadi (offline xavfsiz). Yangi unread sonini qaytaradi.
Future<int> refreshNotifications() async {
  try {
    final res = await NotificationsApi().fetch();
    notificationsNotifier.value = res.items;
    notificationUnreadNotifier.value = res.unread;
    return res.unread;
  } catch (_) {
    return notificationUnreadNotifier.value;
  }
}
