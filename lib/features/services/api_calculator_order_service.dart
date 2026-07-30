/// Online kalkulyator arizasi uchun backend API client.
///
/// Foydalanuvchi kalkulyatorda narxni hisoblagandan keyin natijani ariza
/// sifatida yuboradi (one-tap). Keyin "Arizalar" ekranida ko'rinadi.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import '../auth/auth_http_client.dart';
import 'models/calculator_draft.dart';

class CalculatorOrderApiException implements Exception {
  const CalculatorOrderApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'CalculatorOrderApiException: $message';
}

/// Backend list endpoint'idan keladigan ariza yozuvi (xulosaviy).
class CalculatorOrderSummary {
  const CalculatorOrderSummary({
    required this.id,
    required this.status,
    required this.categoryTitle,
    required this.totalUzs,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String status; // submitted/processing/done/cancelled
  final String categoryTitle;
  final double totalUzs;
  final DateTime createdAt;
  final DateTime updatedAt; // oxirgi yangilanish — sort/ko'rsatish
}

class CalculatorOrderApiService {
  CalculatorOrderApiService({http.Client? client, String? baseUrl})
      : _client = client ?? AuthHttpClient(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 20);

  /// Kalkulyator natijasini ariza sifatida yuborish.
  Future<int> submit({
    required CalculatorResult result,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/services/calculator/orders');
    final body = jsonEncode({
      'category_title': result.categoryTitle,
      'category': result.category,
      'total_uzs': result.totalUzs,
      'currency': 'UZS',
      'note': result.note,
      'lines': result.lines
          .map((l) => {'label': l.label, 'value': l.value})
          .toList(growable: false),
    });

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

    if (res.statusCode != 201 && res.statusCode != 200) _throw(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['id'] as num).toInt();
  }

  /// Foydalanuvchi yuborgan kalkulyator arizalari.
  Future<List<CalculatorOrderSummary>> list({
    required String token,
    int page = 1,
    int size = 50,
  }) async {
    final uri = Uri.parse('$_baseUrl/services/calculator/orders')
        .replace(queryParameters: {'page': '$page', 'size': '$size'});

    final res = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_timeout);

    if (res.statusCode != 200) _throw(res);

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['items'] as List).cast<Map<String, dynamic>>();
    return raw.map(_parseSummary).toList(growable: false);
  }

  CalculatorOrderSummary _parseSummary(Map<String, dynamic> json) {
    final total = json['total_uzs'];
    final created = DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now();
    return CalculatorOrderSummary(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'submitted',
      categoryTitle: json['category_title'] as String? ?? 'Kalkulyator',
      totalUzs: total is num
          ? total.toDouble()
          : (total is String ? (double.tryParse(total) ?? 0) : 0),
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? created,
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
          final first = detail.first;
          if (first is Map && first['msg'] != null) msg = '${first['msg']}';
        }
      }
    } catch (_) {}
    throw CalculatorOrderApiException(msg, res.statusCode);
  }
}
