/// Avtomatik refresh-on-401 wrapper http.Client.
///
/// `http.Client` ni o'rab oladi. Har so'rov uchun:
/// 1. AuthStorage'dan joriy access tokenni o'qiydi va Authorization header'iga
///    qo'shadi (agar so'rov header'ida `_authToken` placeholder bo'lsa).
/// 2. Javob 401 bo'lsa — `/auth/refresh` chaqiradi, yangi tokenlarni saqlaydi
///    va so'rovni qaytadan yuboradi.
/// 3. Refresh ham 401 bo'lsa — sessiyani tozalaydi va xatoni yuqoriga uzatadi.
///
/// Foydalanish:
/// ```dart
/// final client = AuthHttpClient();
/// final res = await client.get(Uri.parse('...'));  // token avtomatik qo'shiladi
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'auth_storage.dart';
import 'models/auth_session.dart';

/// Yagona `lock` — bir vaqtning o'zida faqat bitta refresh chaqiruvi
/// bo'lishini ta'minlaydi (agar 5 ta API parallel 401 olsa, faqat 1 marta
/// `/auth/refresh` chaqiramiz).
class _RefreshLock {
  Completer<bool>? _inProgress;

  /// Refresh allaqachon ishlamoqda bo'lsa, uning natijasini kutadi.
  /// Aks holda yangi refresh boshlaydi.
  Future<bool> runOrAwait(Future<bool> Function() perform) async {
    final existing = _inProgress;
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<bool>();
    _inProgress = completer;
    try {
      final ok = await perform();
      completer.complete(ok);
      return ok;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _inProgress = null;
    }
  }
}

class AuthHttpClient extends http.BaseClient {
  AuthHttpClient({
    http.Client? inner,
    AuthStorage storage = const AuthStorage(),
  })  : _inner = inner ?? http.Client(),
        _storage = storage;

  final http.Client _inner;
  final AuthStorage _storage;
  static final _RefreshLock _refreshLock = _RefreshLock();

  /// Foydalanuvchi sessiyasi yo'q bo'lib qolganda kuzatish uchun callback.
  /// Login ekraniga yo'naltirish uchun ishlatish mumkin (kelajakda main.dart
  /// dan o'rnatilishi mumkin).
  static void Function()? onSessionExpired;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Har qanday so'rovni qayta yuborilishi mumkin bo'lgan (replayable) shaklga
    // keltiramiz — multipart ham. Body bir marta byte'larga o'qiladi, shunda
    // 401 dan keyin retry uchun nusxa olishimiz mumkin.
    final replayable = await _toReplayable(request);

    // 1. Access tokenni qo'shish.
    final session = await _storage.loadSession();
    final firstAttempt = await _attachToken(
      _cloneRequest(replayable),
      session.token,
    );
    final res = await _inner.send(firstAttempt);

    // 2. 401 bo'lsa, refresh va retry.
    if (res.statusCode != 401) {
      return res;
    }

    // 401 keldi — refresh tokenni tekshiramiz.
    if (session.refreshToken == null || session.refreshToken!.isEmpty) {
      // Refresh token yo'q — qaytaramiz (UI logout ga yo'naltiradi).
      return res;
    }

    // Bir vaqtda faqat 1 ta refresh ishlasin (parallel 401 lar uchun).
    final refreshed = await _refreshLock.runOrAwait(() async {
      // Lock ichida — boshqa parallel so'rov allaqachon refresh qilgan
      // bo'lishi mumkin, qayta o'qiymiz.
      final fresh = await _storage.loadSession();
      if (fresh.token != session.token) {
        // Allaqachon yangilangan — true qaytaramiz va retry qiladi.
        return true;
      }
      return _doRefresh(fresh.refreshToken!);
    });

    if (!refreshed) {
      // Refresh fail — sessiyani tozalaymiz.
      await _storage.clear();
      onSessionExpired?.call();
      return res;
    }

    // 3. Yangi token bilan original so'rovni qayta yuboramiz.
    final retrySession = await _storage.loadSession();
    final retried = await _attachToken(
      _cloneRequest(replayable),
      retrySession.token,
    );
    final retryRes = await _inner.send(retried);

    // Refresh muvaffaqiyatli bo'lsa-yu, retry baribir 401 bo'lsa — sessiya
    // haqiqatan ham yaroqsiz. Sessiyani tozalab, UI ni logout ga yo'naltiramiz
    // (cheksiz refresh loop'ining oldini olamiz).
    if (retryRes.statusCode == 401) {
      await _storage.clear();
      onSessionExpired?.call();
    }
    return retryRes;
  }

  /// Har qanday `BaseRequest` ni body'si byte sifatida saqlangan `http.Request`
  /// ga aylantiradi — shunda so'rovni bir necha marta yuborish (retry) mumkin.
  /// Multipart so'rovlarni ham qo'llab-quvvatlaydi: `finalize()` content-type
  /// header'iga boundary'ni yozadi, shuning uchun finalize'dan keyin header'ni
  /// o'qiymiz.
  Future<http.Request> _toReplayable(http.BaseRequest src) async {
    if (src is http.Request) {
      return src;
    }
    final bytes = await src.finalize().toBytes();
    return http.Request(src.method, src.url)
      ..headers.addAll(src.headers)
      ..bodyBytes = bytes
      ..followRedirects = src.followRedirects
      ..maxRedirects = src.maxRedirects
      ..persistentConnection = src.persistentConnection;
  }

  /// Replayable `http.Request` dan yangi nusxa yaratadi (har send uchun yangi
  /// Request kerak — bitta Request faqat bir marta finalize qilinadi).
  http.Request _cloneRequest(http.Request src) {
    return http.Request(src.method, src.url)
      ..headers.addAll(src.headers)
      ..bodyBytes = src.bodyBytes
      ..followRedirects = src.followRedirects
      ..maxRedirects = src.maxRedirects
      ..persistentConnection = src.persistentConnection;
  }

  Future<http.BaseRequest> _attachToken(
    http.BaseRequest request,
    String? token,
  ) async {
    if (token != null && token.isNotEmpty) {
      // Doim joriy access tokenni qo'yamiz (eski qiymatni bezovta yo'qotish).
      // Bu retry paytida ham yangi tokenni ishlatish uchun muhim.
      request.headers['Authorization'] = 'Bearer $token';
    }
    return request;
  }

  /// Backend'ga `/auth/refresh` chaqirib yangi access + refresh tokenlarni
  /// olib saqlaydi.
  Future<bool> _doRefresh(String refreshToken) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/refresh');
      final res = await _inner
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        return false;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final newAccess = body['access_token'] as String?;
      final newRefresh = body['refresh_token'] as String?;
      if (newAccess == null || newAccess.isEmpty) {
        return false;
      }

      // Joriy session ustiga yangi tokenlar
      final current = await _storage.loadSession();
      await _storage.saveSession(
        AuthSession(
          token: newAccess,
          phone: current.phone,
          refreshToken: newRefresh ?? current.refreshToken,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
