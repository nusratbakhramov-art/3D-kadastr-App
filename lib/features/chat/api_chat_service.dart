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
  const ChatStreamEvent._(this.type, {this.content, this.conversationId});

  factory ChatStreamEvent.meta(int? id) =>
      ChatStreamEvent._('meta', conversationId: id);
  factory ChatStreamEvent.delta(String c) =>
      ChatStreamEvent._('delta', content: c);
  factory ChatStreamEvent.error(String c) =>
      ChatStreamEvent._('error', content: c);
  factory ChatStreamEvent.done() => const ChatStreamEvent._('done');

  final String type;
  final String? content;
  final int? conversationId;
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
      final body = await res.stream.bytesToString();
      String detail =
          '${tr(locale, 'chat.server_error')} (${res.statusCode})';
      try {
        final j = jsonDecode(body);
        if (j is Map && j['detail'] != null) detail = j['detail'].toString();
      } catch (_) {
        // generic xabar qoladi
      }
      yield ChatStreamEvent.error(detail);
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
          yield ChatStreamEvent.error(
            d['message'] as String? ?? tr(locale, 'common.error'),
          );
        case 'done':
          yield ChatStreamEvent.done();
          return;
      }
    }
  }
}
