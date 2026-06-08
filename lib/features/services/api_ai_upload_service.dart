/// Upload client for `POST /api/v1/ai-valuations/upload`.
///
/// The AI Baholash intake screen uploads files per category (kadastr docs,
/// property photos, passport) to S3 via the backend and gets back the object
/// keys. Those keys are echoed into the submit bundle.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../core/api_config.dart';

/// Extension → MIME, so the multipart part is tagged correctly (Flutter's
/// MultipartFile.fromPath otherwise sends application/octet-stream, which the
/// backend would treat as an unknown type).
MediaType? _mediaTypeFor(String path) {
  final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    case 'heic':
      return MediaType('image', 'heic');
    case 'heif':
      return MediaType('image', 'heif');
    case 'pdf':
      return MediaType('application', 'pdf');
    case 'doc':
      return MediaType('application', 'msword');
    case 'docx':
      return MediaType('application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document');
    case 'xls':
      return MediaType('application', 'vnd.ms-excel');
    case 'xlsx':
      return MediaType('application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    default:
      return null;
  }
}

/// Upload categories — must match the backend `_UPLOAD_CATEGORIES` keys.
/// `passport`/`document` belong to AI Baholash; `scan3d` belongs to the
/// 3D Kadastr flow (LiDAR mesh uploads).
enum UploadCategory {
  kadastr('kadastr'),
  propertyPhoto('property_photo'),
  passport('passport'),
  document('document'),
  scan3d('scan_3d'),
  scanModel('scan_model'); // teksturali USDZ 3D model

  const UploadCategory(this.wire);
  final String wire;
}

class AiUploadException implements Exception {
  AiUploadException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'AiUploadException($statusCode): $message';
}

class AiUploadService {
  AiUploadService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Upload [filePaths] under [category]; returns the stored S3 object keys
  /// (in the same order, best-effort). Throws [AiUploadException] on failure.
  ///
  /// [endpoint] selects the backend upload route (relative to the API base):
  /// AI Baholash uses `/ai-valuations/upload` (default), 3D Kadastr passes
  /// `/3d-kadastr-jobs/upload`.
  Future<List<String>> upload({
    required UploadCategory category,
    required List<String> filePaths,
    required String token,
    String endpoint = '/ai-valuations/upload',
  }) async {
    if (filePaths.isEmpty) return const [];
    final uri = Uri.parse('$_baseUrl$endpoint');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['category'] = category.wire;
    for (final path in filePaths) {
      req.files.add(await http.MultipartFile.fromPath(
        'files',
        path,
        contentType: _mediaTypeFor(path),
      ));
    }

    final streamed = await _client.send(req).timeout(const Duration(seconds: 120));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      var msg = res.body;
      if (msg.length > 200) msg = '${msg.substring(0, 200)}…';
      throw AiUploadException('upload failed: $msg', statusCode: res.statusCode);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final files = (body['files'] as List?) ?? const [];
    return files
        .map((f) => (f as Map<String, dynamic>)['key'] as String)
        .toList(growable: false);
  }

  void dispose() => _client.close();
}
