/// Yordamchi bot — backend SSE (`POST /api/v1/chat/stream`) bilan ishlash.
///
/// `AuthHttpClient` orqali yuboramiz — Bearer token avtomatik qo'shiladi va
/// 401'da refresh+retry bo'ladi. Streamed POST (`http.Request` + `send`)
/// ishlatamiz, javob `text/event-stream`: har `data: {...}` qatori bitta
/// hodisa.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import '../../core/i18n/app_translations.dart';
import '../auth/auth_http_client.dart';

/// SSE hodisasi: meta (conversation_id) | delta (matn bo'lagi) | error | done.
class ChatStreamEvent {
  const ChatStreamEvent._(
    this.type, {
    this.content,
    this.conversationId,
    this.retryable = true,
  });

  factory ChatStreamEvent.meta(int? id) =>
      ChatStreamEvent._('meta', conversationId: id);
  factory ChatStreamEvent.delta(String c) =>
      ChatStreamEvent._('delta', content: c);
  factory ChatStreamEvent.error(String c, {bool retryable = true}) =>
      ChatStreamEvent._('error', content: c, retryable: retryable);
  factory ChatStreamEvent.done() => const ChatStreamEvent._('done');

  final String type;
  final String? content;
  final int? conversationId;

  /// Xatoni qayta urinish mantiqiymi. Sessiya tugagan yoki savol noto'g'ri
  /// bo'lsa — yo'q: bir xil so'rov bir xil natija beradi.
  final bool retryable;
}

class ChatApiService {
  ChatApiService({http.Client? client, String? baseUrl})
    : _client = client ?? AuthHttpClient(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Foydalanuvchi xabarini yuboradi va javobni token-token oqim qiladi.
  Stream<ChatStreamEvent> streamReply({
    required String message,
    int? conversationId,
    String lang = 'uz',
  }) async* {
    final locale = Locale(lang);
    final uri = Uri.parse('$_baseUrl/chat/stream');
    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode({
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        'lang': lang,
      });

    // Faqat ulanish/headerlar uchun timeout (stream'ning o'zi uzoq bo'lishi mumkin).
    final res = await _client.send(req).timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      // Javob tanasi ATAYLAB o'qilmaydi: backend `detail`'i ichki matn
      // ("Xabar bo'sh"), deploy paytida esa nginx'ning HTML 502 sahifasi
      // keladi. Ikkalasi ham foydalanuvchiga ko'rsatiladigan matn emas —
      // status kodni o'zimiz insoniy xabarga o'giramiz.
      await res.stream.drain<void>();
      yield _errorFor(res.statusCode, locale);
      return;
    }

    final lines = res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;

      Map<String, dynamic> d;
      try {
        d = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      switch (d['type'] as String?) {
        case 'meta':
          yield ChatStreamEvent.meta((d['conversation_id'] as num?)?.toInt());
        case 'delta':
          yield ChatStreamEvent.delta(d['content'] as String? ?? '');
        case 'error':
          // Backend `message`'i ham ichki matn — foydalanuvchiga o'z
          // xabarimizni ko'rsatamiz.
          yield ChatStreamEvent.error(tr(locale, 'chat.error_generic'));
        case 'done':
          yield ChatStreamEvent.done();
          return;
      }
    }
  }

  /// HTTP status → foydalanuvchi o'qiydigan xabar. Status kod hech qachon
  /// ekranga chiqmaydi: "502" foydalanuvchiga hech narsa aytmaydi, u faqat
  /// nima bo'lgani va endi nima qilishni bilishi kerak.
  ChatStreamEvent _errorFor(int status, Locale locale) => switch (status) {
    // Prod deploy oynasi: nginx app konteynerga ulana olmayapti. Bir necha
    // soniyadan keyin o'zi tuzaladi — shuning uchun "keyinroq urinib ko'ring".
    502 || 503 || 504 => ChatStreamEvent.error(
      tr(locale, 'chat.error_busy'),
    ),
    401 || 403 => ChatStreamEvent.error(
      tr(locale, 'chat.error_session'),
      retryable: false,
    ),
    429 => ChatStreamEvent.error(tr(locale, 'chat.error_too_many')),
    _ => ChatStreamEvent.error(tr(locale, 'chat.error_generic')),
  };
}
