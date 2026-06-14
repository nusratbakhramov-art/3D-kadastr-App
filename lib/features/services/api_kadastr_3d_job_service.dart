/// HTTP client for the `/api/v1/3d-kadastr-jobs` endpoints.
///
/// Pairs with `app/api/v1/kadastr_3d.py` on the backend. The 3D Kadastr
/// status screen creates a job and shows a confirmation; there is no pipeline
/// polling yet (the job stays `submitted` until a specialist acts on it).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';

/// Mirrors `Kadastr3dJobStatus` on the backend. Strings match exactly.
enum Kadastr3dJobStatus {
  submitted,
  processing,
  completed,
  failed;

  static Kadastr3dJobStatus parse(String raw) {
    switch (raw) {
      case 'processing':
        return Kadastr3dJobStatus.processing;
      case 'completed':
        return Kadastr3dJobStatus.completed;
      case 'failed':
        return Kadastr3dJobStatus.failed;
      case 'submitted':
      default:
        return Kadastr3dJobStatus.submitted;
    }
  }

  bool get isTerminal =>
      this == Kadastr3dJobStatus.completed ||
      this == Kadastr3dJobStatus.failed;
}

/// Lightweight list row from `GET /3d-kadastr-jobs`. Mirrors
/// `Kadastr3dJobListItem` on the backend.
class Kadastr3dJobSummary {
  Kadastr3dJobSummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.cadastreNumber,
    this.objectType,
  });

  final int id;
  final Kadastr3dJobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt; // oxirgi yangilanish — sort/ko'rsatish
  final String? cadastreNumber;
  final String? objectType;

  factory Kadastr3dJobSummary.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return Kadastr3dJobSummary(
      id: json['id'] as int,
      status:
          Kadastr3dJobStatus.parse(json['status']?.toString() ?? 'submitted'),
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? created,
      cadastreNumber: json['cadastre_number'] as String?,
      objectType: json['object_type'] as String?,
    );
  }
}

class Kadastr3dApiException implements Exception {
  Kadastr3dApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'Kadastr3dApiException: $message';
}

class Kadastr3dJobService {
  Kadastr3dJobService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<int> create({
    required Map<String, dynamic> bundleJson,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/3d-kadastr-jobs');
    final res = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(bundleJson),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Kadastr3dApiException(
        _extractDetail(res) ?? 'HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['id'] as int;
  }

  /// Current user's 3D Kadastr jobs, newest-first.
  Future<List<Kadastr3dJobSummary>> list({
    required String token,
    int limit = 100,
  }) async {
    final uri = Uri.parse('$_baseUrl/3d-kadastr-jobs?limit=$limit');
    final res = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Kadastr3dApiException(
        _extractDetail(res) ?? 'HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }
    final body = jsonDecode(res.body) as List<dynamic>;
    return body
        .map((e) => Kadastr3dJobSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  void dispose() => _client.close();

  String? _extractDetail(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        return body['detail'].toString();
      }
    } catch (_) {}
    return null;
  }
}
