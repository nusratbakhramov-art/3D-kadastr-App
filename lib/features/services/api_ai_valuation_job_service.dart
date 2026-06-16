/// HTTP client for the async `/api/v1/ai-valuations` endpoints.
///
/// Pairs with `app/api/v1/ai_valuations.py` on the backend. The mobile
/// AI Baholash status screen creates a job, then polls until the worker
/// flips it to `completed` (or `failed`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/api_config.dart';

/// Mirrors `AiValuationJobStatus` on the backend. Strings match exactly.
enum AiJobStatus {
  draft,
  queued,
  gatheringInfo,
  aiPricing,
  underReview,
  completed,
  failed;

  static AiJobStatus parse(String raw) {
    switch (raw) {
      case 'draft':
        return AiJobStatus.draft;
      case 'queued':
        return AiJobStatus.queued;
      case 'gathering_info':
        return AiJobStatus.gatheringInfo;
      case 'ai_pricing':
        return AiJobStatus.aiPricing;
      case 'under_review':
        return AiJobStatus.underReview;
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

  /// The AI value is ready and viewable (the user can see the result), whether
  /// or not the estimate group has finalized the report. We stop the live poll
  /// here — final completion happens later, off-screen, via the admin.
  bool get hasResult =>
      this == AiJobStatus.underReview || this == AiJobStatus.completed;

  bool get isDraft => this == AiJobStatus.draft;
}

class AiJobSnapshot {
  AiJobSnapshot({
    required this.id,
    required this.status,
    required this.requestPayload,
    this.currentStep,
    this.scanUsdzKey,
    this.resultPayload,
    this.errorMessage,
    this.estimatorComment,
    this.estimatorCause,
    this.nearbyListingsCount = 0,
    this.nearbyPoisCount = 0,
  });

  final int id;
  final AiJobStatus status;
  final Map<String, dynamic> requestPayload;
  final String? currentStep; // DRAFT: qaysi qadamda qolgan
  final String? scanUsdzKey; // teksturali 3D skan backend kaliti (resume ko'rish)
  final Map<String, dynamic>? resultPayload;
  final String? errorMessage;
  // Baholash guruhi xulosasi — natija ekranida foydalanuvchiga ko'rsatiladi.
  final String? estimatorComment;
  final String? estimatorCause;
  final int nearbyListingsCount;
  final int nearbyPoisCount;

  factory AiJobSnapshot.fromJson(Map<String, dynamic> json) => AiJobSnapshot(
        id: json['id'] as int,
        status: AiJobStatus.parse(json['status']?.toString() ?? 'queued'),
        requestPayload:
            (json['request_payload'] as Map?)?.cast<String, dynamic>() ??
                const {},
        currentStep: json['current_step'] as String?,
        scanUsdzKey: json['scan_usdz_key'] as String?,
        resultPayload:
            (json['result_payload'] as Map?)?.cast<String, dynamic>(),
        errorMessage: json['error_message'] as String?,
        estimatorComment: json['estimator_comment'] as String?,
        estimatorCause: json['estimator_cause'] as String?,
        nearbyListingsCount: (json['nearby_listings_count'] as int?) ?? 0,
        nearbyPoisCount: (json['nearby_pois_count'] as int?) ?? 0,
      );
}

/// Lightweight list row from `GET /ai-valuations` — used by the Arizalar
/// screen. Mirrors `AiValuationJobListItem` on the backend.
class AiJobSummary {
  AiJobSummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.cadastreNumber,
    this.estimatedValue,
    this.currentStep,
    this.hasScan = false,
    this.estimatorComment,
    this.estimatorCause,
  });

  final int id;
  final AiJobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt; // oxirgi yangilanish (status o'zgargan vaqt) — sort/ko'rsatish
  final String? cadastreNumber;
  final double? estimatedValue;
  final String? currentStep; // DRAFT: qaysi qadamda qolgan (resume)
  final bool hasScan; // teksturali 3D (USDZ) skan biriktirilganmi
  // Baholash guruhi xulosasi — ariza detalida foydalanuvchiga ko'rsatiladi.
  final String? estimatorComment;
  final String? estimatorCause;

  factory AiJobSummary.fromJson(Map<String, dynamic> json) {
    final created = DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return AiJobSummary(
        id: json['id'] as int,
        status: AiJobStatus.parse(json['status']?.toString() ?? 'queued'),
        createdAt: created,
        updatedAt:
            DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? created,
        cadastreNumber: json['cadastre_number'] as String?,
        estimatedValue: (json['estimated_value'] as num?)?.toDouble(),
        currentStep: json['current_step'] as String?,
        hasScan: json['has_scan'] == true,
        estimatorComment: json['estimator_comment'] as String?,
        estimatorCause: json['estimator_cause'] as String?,
      );
  }
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

  /// MAVJUD draft arizani yakunlab navbatga qo'yadi (yangi job YARATMAYDI) —
  /// draft skan USDZ va boshqa biriktirilgan ma'lumotlari bilan saqlanadi.
  /// Draftli oqimda `create` o'rniga shu ishlatiladi.
  Future<int> submitDraft({
    required int draftId,
    required Map<String, dynamic> bundleJson,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/ai-valuations/$draftId/submit');
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

  /// Current user's AI Baholash jobs, newest-first. Powers the Arizalar list.
  Future<List<AiJobSummary>> list({
    required String token,
    int limit = 100,
  }) async {
    final uri = Uri.parse('$_baseUrl/ai-valuations?limit=$limit');
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
    final body = jsonDecode(res.body) as List<dynamic>;
    return body
        .map((e) => AiJobSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
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

  /// Arizaga biriktirilgan teksturali 3D skan (USDZ) ni backend'dan yuklab,
  /// vaqtinchalik faylga yozadi va to'liq yo'lni qaytaradi (QuickLook uchun).
  /// Skan yo'q yoki yuklab bo'lmasa null.
  Future<String?> downloadScanUsdz(int id, {required String token}) async {
    final uri = Uri.parse('$_baseUrl/ai-valuations/$id/scan');
    final res = await _client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ai_scan_$id.usdz');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file.path;
  }

  // ── Draft ariza (real oqim) ──────────────────────────────────────────

  /// Skandan keyin DRAFT ariza yaratadi (request_payload = qisman bundle).
  Future<AiJobSnapshot> createDraft({
    required Map<String, dynamic> payload,
    String? currentStep,
    String? scanUsdzKey,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/ai-valuations/draft');
    final res = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'payload': payload,
            if (currentStep != null) 'current_step': currentStep,
            if (scanUsdzKey != null) 'scan_usdz_key': scanUsdzKey,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw AiValuationApiException(
        _extractDetail(res) ?? 'HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }
    return AiJobSnapshot.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// DRAFT arizani yangilaydi (qadam + qisman bundle saqlash).
  Future<AiJobSnapshot> updateDraft(
    int id, {
    required Map<String, dynamic> payload,
    String? currentStep,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/ai-valuations/$id/draft');
    final res = await _client
        .patch(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'payload': payload,
            if (currentStep != null) 'current_step': currentStep,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw AiValuationApiException(
        _extractDetail(res) ?? 'HTTP ${res.statusCode}',
        statusCode: res.statusCode,
      );
    }
    return AiJobSnapshot.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Tugallanmagan (DRAFT) arizalar — "Mening arizalarim" ro'yxati.
  Future<List<AiJobSummary>> listDrafts({required String token}) async {
    final uri = Uri.parse('$_baseUrl/ai-valuations/drafts');
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
    final body = jsonDecode(res.body) as List<dynamic>;
    return body
        .map((e) => AiJobSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  void dispose() => _client.close();

  String? _extractDetail(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        final detail = body['detail'];
        if (detail is String) return detail;
        // FastAPI/Pydantic 422 → `detail` is a list of error objects. Don't
        // dump the raw JSON; surface just the human-readable `msg` fields.
        if (detail is List) {
          final msgs = detail
              .whereType<Map>()
              .map((e) => e['msg']?.toString())
              .where((m) => m != null && m!.isNotEmpty)
              .cast<String>()
              .toList();
          if (msgs.isNotEmpty) return msgs.join('; ');
        }
        return detail.toString();
      }
    } catch (_) {}
    return null;
  }
}
