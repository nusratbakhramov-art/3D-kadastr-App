/// Hybrid photogrammetry pipeline backend client.
///
/// `/api/v1/photogrammetry/*` endpoint'lari bilan ishlaydi:
/// - `GET /jobs` — foydalanuvchining barcha photogrammetry job'lari
/// - `GET /jobs/{id}` — bitta job holati
/// - `POST /jobs/{id}/cancel` — bekor qilish
/// - `GET /jobs/{id}/download` — yakuniy USDZ
///
/// Auth header AuthHttpClient interceptor tomonidan avtomatik qo'shiladi.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import '../auth/auth_http_client.dart';

class PhotogrammetryApiException implements Exception {
  const PhotogrammetryApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => 'PhotogrammetryApiException: $message';
}

/// Backend'dan keladigan photogrammetry job yozuvi.
class PhotogrammetryJobSummary {
  const PhotogrammetryJobSummary({
    required this.id,
    required this.status,
    required this.photoCount,
    required this.createdAt,
    this.errorMessage,
    this.downloadUrl,
    this.resultFormat,
    this.completedAt,
  });

  factory PhotogrammetryJobSummary.fromJson(Map<String, dynamic> json) {
    return PhotogrammetryJobSummary(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'pending',
      photoCount: (json['photo_count'] as num? ?? 0).toInt(),
      errorMessage: json['error_message'] as String?,
      downloadUrl: json['download_url'] as String?,
      resultFormat: json['result_format'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.tryParse(json['completed_at'] as String),
    );
  }

  final int id;
  final String status; // pending | processing | completed | failed | cancelled
  final int photoCount;
  final String? errorMessage;
  final String? downloadUrl;

  /// Natija fayl formati — backend'dan keladi:
  ///   'splat' — yangi Gaussian Splatting (Flutter WebView orqali ko'rsatiladi)
  ///   'usdz'  — eski mesh (iOS QuickLook orqali ko'rsatiladi)
  /// `null` bo'lsa default `usdz` deb hisoblash mumkin (backward compat).
  final String? resultFormat;
  final DateTime createdAt;
  final DateTime? completedAt;

  bool get isInProgress =>
      status == 'pending' || status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isSplat => resultFormat == 'splat';
}

class PhotogrammetryApiService {
  PhotogrammetryApiService({http.Client? client, String? baseUrl})
    : _client = client ?? AuthHttpClient(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 30);

  /// Foydalanuvchining barcha photogrammetry job'lari (yangidan eskigacha).
  Future<List<PhotogrammetryJobSummary>> listJobs() async {
    final uri = Uri.parse('$_baseUrl/photogrammetry/jobs');
    final res = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(_timeout);
    if (res.statusCode != 200) _throw(res);
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) =>
            PhotogrammetryJobSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Bitta job holati.
  Future<PhotogrammetryJobSummary> getJob(int jobId) async {
    final uri = Uri.parse('$_baseUrl/photogrammetry/jobs/$jobId');
    final res = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(_timeout);
    if (res.statusCode != 200) _throw(res);
    return PhotogrammetryJobSummary.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// Job'ni bekor qilish.
  Future<PhotogrammetryJobSummary> cancelJob(int jobId) async {
    final uri = Uri.parse('$_baseUrl/photogrammetry/jobs/$jobId/cancel');
    final res = await _client
        .post(uri, headers: {'Accept': 'application/json'})
        .timeout(_timeout);
    if (res.statusCode != 200) _throw(res);
    return PhotogrammetryJobSummary.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Never _throw(http.Response res) {
    String message = 'Server xatosi (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        message = body['detail'].toString();
      }
    } catch (_) {}
    throw PhotogrammetryApiException(message, res.statusCode);
  }
}
