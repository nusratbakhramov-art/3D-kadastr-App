/// Dinamik forma sxemalarini backend'dan oluvchi client (+ yengil kesh).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'models/dynamic_form_schema.dart';

class FormsApiException implements Exception {
  const FormsApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => 'FormsApiException: $message';
}

class FormsApiService {
  FormsApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 20);

  // Sessiya davomida sxemani qayta yuklamaslik uchun oddiy kesh.
  static final Map<String, FormSchema> _cache = {};

  /// `GET /forms/{key}` — aktiv forma sxemasi. Public (auth shart emas).
  Future<FormSchema> getForm(String key, {bool refresh = false}) async {
    if (!refresh && _cache.containsKey(key)) return _cache[key]!;
    final uri = Uri.parse('$_baseUrl/forms/$key');
    final res = await _client
        .get(uri, headers: {'Accept': 'application/json'}).timeout(_timeout);
    if (res.statusCode != 200) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        final b = jsonDecode(res.body);
        if (b is Map && b['detail'] is String) msg = b['detail'] as String;
      } catch (_) {}
      throw FormsApiException(msg, res.statusCode);
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final schema = FormSchema.fromJson(json);
    _cache[key] = schema;
    return schema;
  }

  static void clearCache() => _cache.clear();
}
