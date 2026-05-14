/// Backend AI baholash endpoint'i bilan ishlash.
///
/// `POST /api/v1/valuations/ai` — wizard 9 step ma'lumotlaridan taxminiy
/// bozor qiymatini market_listings comparables bilan hisoblaydi.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import '../auth/auth_http_client.dart';
import 'models/ai_valuation_result.dart';
import 'models/architecture_order_draft.dart';

class AiValuationApiException implements Exception {
  const AiValuationApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AiValuationApiException: $message';
}

/// Backend'dan keladigan tasdiqlash arizasi yozuvi.
class AiConfirmationSummary {
  const AiConfirmationSummary({
    required this.id,
    required this.valuationHistoryId,
    required this.status,
    required this.aiEstimatedValue,
    required this.createdAt,
    this.finalValue,
    this.adminNotes,
  });

  factory AiConfirmationSummary.fromJson(Map<String, dynamic> json) {
    return AiConfirmationSummary(
      id: (json['id'] as num).toInt(),
      valuationHistoryId: (json['valuation_history_id'] as num).toInt(),
      status: json['status'] as String? ?? 'pending',
      aiEstimatedValue: double.tryParse(
            json['ai_estimated_value']?.toString() ?? '',
          ) ??
          0,
      finalValue: json['final_value'] == null
          ? null
          : double.tryParse(json['final_value'].toString()),
      adminNotes: json['admin_notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final int id;
  final int valuationHistoryId;
  final String status; // pending | approved | adjusted | rejected
  final double aiEstimatedValue;
  final double? finalValue;
  final String? adminNotes;
  final DateTime createdAt;
}

class AiValuationApiService {
  AiValuationApiService({http.Client? client, String? baseUrl})
    : _client = client ?? AuthHttpClient(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 30);

  /// Wizard'dan kelgan to'liq draft + skan natijasi → backend AI baholash.
  ///
  /// `scanCompleted` parametri JSON'ga qo'shiladi (analytics/confidence
  /// uchun); boshqa fieldlar `draft.toRequestJson()` orqali keladi.
  Future<AiValuationResult> compute({
    required ArchitectureOrderDraft draft,
    required String token,
    bool scanCompleted = false,
    String locale = 'uz',
  }) async {
    final uri = Uri.parse('$_baseUrl/valuations/ai');

    // Draft JSON'iga `scan_completed` + `locale` qo'shamiz va details ichidagi
    // sub-modellar (architecture/constructive/engineering/territory/rooms)
    // backend tomonida top-level fieldlar sifatida kerak — flatten qilamiz.
    final draftJson = draft.toRequestJson();
    final details = draftJson.remove('details') as Map<String, dynamic>?;
    final body = <String, dynamic>{
      ...draftJson,
      'scan_completed': scanCompleted,
      'locale': locale,
      if (details != null) ...{
        'rooms': details['rooms'] ?? const [],
        'architecture': details['architecture'] ?? const {},
        'constructive': details['constructive'] ?? const {},
        'engineering': details['engineering'] ?? const {},
        'territory': details['territory'] ?? const {},
        if (details['notes'] != null) 'notes': details['notes'],
      },
    };

    // Authorization header AuthHttpClient interceptor tomonidan avtomatik
    // qo'shiladi. Token parametri faqat backward-compat uchun qabul qilinadi
    // — explicit yuborilsa, interceptor uni qayta yozadi.
    final res = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      _throw(res);
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return AiValuationResult.fromJson(json);
  }

  /// Foydalanuvchining barcha tasdiqlash arizalari ro'yxati (yangidan eskigacha).
  Future<List<AiConfirmationSummary>> listConfirmations() async {
    final uri = Uri.parse('$_baseUrl/valuations/ai/confirmations');
    final res = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
          },
        )
        .timeout(_timeout);
    if (res.statusCode != 200) _throw(res);
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => AiConfirmationSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// AI baholash natijasini admin tomonidan tasdiqlash uchun ariza yuborish.
  /// Idempotent: shu `historyId` uchun PENDING ariza bo'lsa, mavjudini qaytaradi.
  Future<int> submitConfirmation({
    required int historyId,
    String? userNotes,
  }) async {
    final uri = Uri.parse('$_baseUrl/valuations/ai/confirmations');
    final res = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'valuation_history_id': historyId,
            if (userNotes != null && userNotes.isNotEmpty)
              'user_notes': userNotes,
          }),
        )
        .timeout(_timeout);
    if (res.statusCode != 201 && res.statusCode != 200) {
      _throw(res);
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return (json['id'] as num).toInt();
  }

  Never _throw(http.Response res) {
    String message = 'Server xatosi (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        message = body['detail'].toString();
      }
    } catch (_) {
      // ignore — keep generic message
    }
    throw AiValuationApiException(message, res.statusCode);
  }
}
