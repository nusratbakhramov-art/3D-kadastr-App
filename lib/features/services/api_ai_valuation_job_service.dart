/// HTTP client for the async `/api/v1/ai-valuations` endpoints.
///
/// Pairs with `app/api/v1/ai_valuations.py` on the backend. The mobile
/// AI Baholash status screen creates a job, then polls until the worker
/// flips it to `completed` (or `failed`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';

/// Mirrors `AiValuationJobStatus` on the backend. Strings match exactly.
enum AiJobStatus {
  queued,
  gatheringInfo,
  aiPricing,
  completed,
  failed;

  static AiJobStatus parse(String raw) {
    switch (raw) {
      case 'queued':
        return AiJobStatus.queued;
      case 'gathering_info':
        return AiJobStatus.gatheringInfo;
      case 'ai_pricing':
        return AiJobStatus.aiPricing;
      case 'completed':
        return AiJobStatus.completed;
      case 'failed':
        return AiJobStatus.failed;
      default:
        // Unknown server-side state — treat as in-flight so we keep polling.
        return AiJobStatus.queued;
    }
  }

  bool get isTerminal =>
      this == AiJobStatus.completed || this == AiJobStatus.failed;
}

class AiJobSnapshot {
  AiJobSnapshot({
    required this.id,
    required this.status,
    required this.requestPayload,
    this.resultPayload,
    this.errorMessage,
    this.nearbyListingsCount = 0,
    this.nearbyPoisCount = 0,
  });

  final int id;
  final AiJobStatus status;
  final Map<String, dynamic> requestPayload;
  final Map<String, dynamic>? resultPayload;
  final String? errorMessage;
  final int nearbyListingsCount;
  final int nearbyPoisCount;

  factory AiJobSnapshot.fromJson(Map<String, dynamic> json) => AiJobSnapshot(
        id: json['id'] as int,
        status: AiJobStatus.parse(json['status']?.toString() ?? 'queued'),
        requestPayload:
            (json['request_payload'] as Map?)?.cast<String, dynamic>() ??
                const {},
        resultPayload:
            (json['result_payload'] as Map?)?.cast<String, dynamic>(),
        errorMessage: json['error_message'] as String?,
        nearbyListingsCount: (json['nearby_listings_count'] as int?) ?? 0,
        nearbyPoisCount: (json['nearby_pois_count'] as int?) ?? 0,
      );
}

class AiValuationApiException implements Exception {
  AiValuationApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'AiValuationApiException: $message';
}

class AiValuationJobService {
  AiValuationJobService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<int> create({
    required Map<String, dynamic> bundleJson,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/ai-valuations');
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
      throw AiValuationApiException(
        _extractDetail(res) ?? 'HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['id'] as int;
  }

  Future<AiJobSnapshot> get(int id, {required String token}) async {
    final uri = Uri.parse('$_baseUrl/ai-valuations/$id');
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
      throw AiValuationApiException(
        _extractDetail(res) ?? 'HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }
    return AiJobSnapshot.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  void dispose() => _client.close();

  String? _extractDetail(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) return body['detail'].toString();
    } catch (_) {}
    return null;
  }
}
