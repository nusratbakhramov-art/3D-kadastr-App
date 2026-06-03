/// Dizayn loyihasi TZ buyurtmasi uchun backend API client.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'models/design_order_draft.dart';

class DesignOrderApiException implements Exception {
  const DesignOrderApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'DesignOrderApiException: $message';
}

/// Backend qaytaradigan tasdiqlangan order ma'lumotlari.
class CreatedDesignOrder {
  const CreatedDesignOrder({
    required this.id,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final String status;
  final DateTime createdAt;
}

class DesignOrderApiService {
  DesignOrderApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 20);

  /// Wizard yakunida draft'ni backend'ga yuborish.
  Future<CreatedDesignOrder> submit({
    required DizaynOrderDraft draft,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/services/design/orders');
    final body = jsonEncode(draft.toRequestJson());

    final res = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .timeout(_timeout);

    if (res.statusCode != 201 && res.statusCode != 200) {
      _throw(res);
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return CreatedDesignOrder(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'submitted',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  void dispose() => _client.close();

  Never _throw(http.Response res) {
    String msg = 'HTTP ${res.statusCode}';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        final detail = body['detail'];
        if (detail is String) {
          msg = detail;
        } else if (detail is List && detail.isNotEmpty) {
          // Pydantic validation errors — birinchisini ko'rsatamiz.
          final first = detail.first;
          if (first is Map && first['msg'] != null) msg = '${first['msg']}';
        }
      }
    } catch (_) {}
    throw DesignOrderApiException(msg, res.statusCode);
  }
}
