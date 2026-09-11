/// 360° panorama tikish — backend klienti.
///
/// Oqim: [createJob] → har kadr uchun [uploadFrame] → [finish] → [status] ni
/// tayyor bo'lguncha so'rash. Tikish serverda, alohida Celery navbatida
/// (`app/tasks/bozor_pano_task.py`) — o'lchangan ~30 s.
///
/// Natija — ODDIY media kaliti (`listings/media/{user_id}/pano_*.jpg`), ya'ni
/// e'lon uni yuklangan fotodan farqsiz qabul qiladi va `bozor_listing_media`
/// ga hech qanday "kutilmoqda" holati kerak emas.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/api_config.dart';
import '../../auth/auth_http_client.dart';

/// Tikish ishining holati (serverdagi `PanoJobOut`).
@immutable
class PanoJob {
  const PanoJob({
    required this.id,
    required this.status,
    this.progress = 0,
    this.message,
    this.frames = 0,
    this.storageKey,
    this.url,
    this.width,
    this.height,
    this.coverage,
    this.error,
  });

  final int id;

  /// `capturing` | `queued` | `stitching` | `done` | `error`.
  final String status;
  final double progress;
  final String? message;
  final int frames;

  /// Faqat `done` da to'ladi — e'longa SHU kalit qo'shiladi.
  final String? storageKey;
  final String? url;
  final int? width;
  final int? height;
  final double? coverage;

  /// Faqat `error` da to'ladi.
  final String? error;

  bool get isDone => status == 'done';
  bool get isError => status == 'error';
  bool get isFinal => isDone || isError;

  factory PanoJob.fromJson(Map<String, dynamic> j) => PanoJob(
    id: (j['id'] as num?)?.toInt() ?? 0,
    status: (j['status'] ?? '').toString(),
    progress: (j['progress'] as num?)?.toDouble() ?? 0,
    message: j['message']?.toString(),
    frames: (j['frames'] as num?)?.toInt() ?? 0,
    storageKey: j['storage_key']?.toString(),
    url: j['url']?.toString(),
    width: (j['width'] as num?)?.toInt(),
    height: (j['height'] as num?)?.toInt(),
    coverage: (j['coverage'] as num?)?.toDouble(),
    error: j['error']?.toString(),
  );
}

class PanoApiException implements Exception {
  PanoApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PanoApiException($statusCode): $message';
}

class PanoApi {
  PanoApi({http.Client? client}) : _client = client ?? AuthHttpClient();

  final http.Client _client;

  void dispose() => _client.close();

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  static const Map<String, String> _headers = {'Accept': 'application/json'};

  /// Yangi tikish ishi. Kenglikni SERVER hal qiladi (`PANO_OUTPUT_WIDTH`).
  Future<PanoJob> createJob() async {
    final req = http.MultipartRequest('POST', _uri('/listings/pano'))
      ..headers.addAll(_headers)
      ..fields['width'] = '0';
    return _send(req, expect: 201);
  }

  /// Bitta kadr va uning pozasi.
  ///
  /// `meta` — nativ taraf yozgan JSON (`transform`, `intrinsics`, …); u
  /// o'zgartirilmasdan uzatiladi, chunki server `intrinsics` ni `imageWidth`
  /// ga nisbatan qayta masshtablaydi.
  Future<PanoJob> uploadFrame({
    required int jobId,
    required File image,
    required Map<String, dynamic> meta,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      _uri('/listings/pano/$jobId/frames'),
    )
      ..headers.addAll(_headers)
      ..fields['meta'] = jsonEncode(meta)
      ..files.add(await http.MultipartFile.fromPath('file', image.path));
    return _send(req, expect: 200, timeout: const Duration(minutes: 2));
  }

  /// Kadrlar tugadi — tikishni navbatga qo'yadi.
  Future<PanoJob> finish(int jobId) async {
    final req = http.MultipartRequest(
      'POST',
      _uri('/listings/pano/$jobId/finish'),
    )..headers.addAll(_headers);
    return _send(req, expect: 200);
  }

  Future<PanoJob> status(int jobId) async {
    try {
      final res = await _client
          .get(_uri('/listings/pano/$jobId'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw PanoApiException(_errorOf(res), statusCode: res.statusCode);
      }
      return PanoJob.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } on TimeoutException {
      throw PanoApiException('server vaqtida javob bermadi');
    }
  }

  // ── Ichki ─────────────────────────────────────────────────────────────────
  Future<PanoJob> _send(
    http.MultipartRequest req, {
    required int expect,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    try {
      final streamed = await _client.send(req).timeout(timeout);
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != expect) {
        throw PanoApiException(_errorOf(res), statusCode: res.statusCode);
      }
      return PanoJob.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
    } on TimeoutException {
      throw PanoApiException('server vaqtida javob bermadi');
    } on FormatException {
      throw PanoApiException('javob JSON emas');
    }
  }

  /// FastAPI xatosini odam o'qiydigan matnga aylantiradi (`BozorApi` bilan
  /// bir xil qoida).
  static String _errorOf(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final detail = body is Map ? body['detail'] : null;
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) return '${first['msg']}';
      }
    } catch (_) {
      // pastdagi umumiy matnga tushamiz
    }
    return 'HTTP ${res.statusCode}';
  }
}
