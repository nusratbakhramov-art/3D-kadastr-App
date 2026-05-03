/// Backend scan API'sidagi `/cadastre-lookup` endpoint'iga client.
///
/// Davreestr.uz scraper natijasini olib keladi:
/// `address, object_type_hint, total_area, living_area, cadastre_value`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';

class CadastreLookupResult {
  const CadastreLookupResult({
    required this.cadastreNumber,
    this.address,
    this.objectTypeHint,
    this.totalArea,
    this.livingArea,
    this.cadastreValue,
  });

  final String cadastreNumber;
  final String? address;
  final String? objectTypeHint;
  final double? totalArea; // m²
  final double? livingArea; // m²
  final double? cadastreValue; // so'm
}

class CadastreLookupException implements Exception {
  const CadastreLookupException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'CadastreLookupException: $message';
}

class CadastreApiService {
  CadastreApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  // Backend scraper'i 8 ta captcha retry qiladi — har biri ~3-5 sek →
  // umumiy timeout salmoqli kerak.
  static const Duration _timeout = Duration(seconds: 60);

  Future<CadastreLookupResult> lookup({
    required String cadastreNumber,
    required String token,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/scans/cadastre-lookup',
    ).replace(queryParameters: {'number': cadastreNumber});

    final res = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['detail'] != null) {
          msg = body['detail'].toString();
        }
      } catch (_) {}
      throw CadastreLookupException(msg, statusCode: res.statusCode);
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    double? n(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return CadastreLookupResult(
      cadastreNumber: json['cadastre_number']?.toString() ?? cadastreNumber,
      address: json['address'] as String?,
      objectTypeHint: json['object_type_hint'] as String?,
      totalArea: n(json['total_area']),
      livingArea: n(json['living_area']),
      cadastreValue: n(json['cadastre_value']),
    );
  }
}
