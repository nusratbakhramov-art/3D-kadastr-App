/// Upload client for `POST /api/v1/ai-valuations/upload`.
///
/// The AI Baholash intake screen uploads files per category (kadastr docs,
/// property photos, passport) to S3 via the backend and gets back the object
/// keys. Those keys are echoed into the submit bundle.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../core/api_config.dart';

/// MultipartRequest that reports cumulative bytes as its body streams out to the
/// socket. `package:http` exposes no upload progress, so a large multipart looks
/// "frozen" until it finishes — this makes the bar move live. Byte counts are a
/// close approximation (OS socket buffering), good enough for a progress UI.
class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(super.method, super.url, {this.onBytes});

  final void Function(int bytesSent)? onBytes;

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final cb = onBytes;
    if (cb == null) return byteStream;
    var sent = 0;
    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        sent += data.length;
        cb(sent);
        sink.add(data);
      },
    );
    return http.ByteStream(byteStream.transform(transformer));
  }
}

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
    // Teksturali 3D skan modellari (scan_model). Backend kengaytma bo'yicha
    // tekshiradi, lekin MIME'ni to'g'ri belgilash tozaroq.
    case 'glb':
      return MediaType('model', 'gltf-binary');
    case 'gltf':
      return MediaType('model', 'gltf+json');
    case 'usdz':
      return MediaType('model', 'vnd.usdz+zip');
    default:
      return null;
  }
}

/// Upload categories — must match the backend `_UPLOAD_CATEGORIES` keys.
/// `passport`/`document` belong to AI Baholash; `scan3d` belongs to the
/// 3D kadastr flow (LiDAR mesh uploads).
enum UploadCategory {
  kadastr('kadastr'),
  propertyPhoto('property_photo'),
  passport('passport'),
  document('document'),
  smeta('smeta'), // SMETA (qurilish smetasi) hujjatlari — smeta qadamida
  panorama('panorama'), // 360° xona — telefonda tikilgan tayyor equirect JPEG
  scan3d('scan_3d'),
  scanModel('scan_model'), // teksturali 3D model (GLB asosiy, USDZ orqaga moslik)
  scanBundle('scan_bundle'); // to'liq skan to'plami (rasmlar, glb, usdz, mesh, geo…)

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
  /// AI Baholash uses `/ai-valuations/upload` (default), 3D kadastr passes
  /// `/3d-kadastr-jobs/upload`.
  Future<List<String>> upload({
    required UploadCategory category,
    required List<String> filePaths,
    required String token,
    String endpoint = '/ai-valuations/upload',
    Duration timeout = const Duration(seconds: 120),
    void Function(int bytesSent)? onBytes,
  }) async {
    if (filePaths.isEmpty) return const [];
    final uri = Uri.parse('$_baseUrl$endpoint');
    final req = _ProgressMultipartRequest('POST', uri, onBytes: onBytes)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['category'] = category.wire;
    for (final path in filePaths) {
      req.files.add(await http.MultipartFile.fromPath(
        'files',
        path,
        contentType: _mediaTypeFor(path),
      ));
    }

    final streamed = await _client.send(req).timeout(timeout);
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

  /// Upload a FULL scan bundle (every artifact) with file-level progress.
  ///
  /// [entries] are `{path, type, sizeBytes}` (from the native `listScanFiles`).
  /// Types map into the backend `scan_files` shape: every non-`frame` type
  /// becomes a single key (`glb`, `usdz`, `geo`, `png`, `manifest`, …) and all
  /// `frame` entries collect into a `frames` list. Files go up in small batches
  /// so [onProgress] fires often — `(filesDone, filesTotal, bytesSent,
  /// bytesTotal)`. Returns the `scan_files` map for `createDraft(scanFiles:)`.
  ///
  /// Best-effort per file: a key that fails to come back is simply omitted, so
  /// a single bad frame doesn't abort the whole bundle.
  Future<Map<String, dynamic>> uploadBundle({
    required List<({String path, String type, int sizeBytes})> entries,
    required String token,
    String endpoint = '/ai-valuations/upload',
    int batchSize = 6,
    void Function(int filesDone, int filesTotal, int bytesSent, int bytesTotal)?
        onProgress,
  }) async {
    final scanFiles = <String, dynamic>{};
    final frames = <String>[];
    final total = entries.length;
    final totalBytes = entries.fold<int>(0, (s, e) => s + e.sizeBytes);
    if (total == 0) return scanFiles;
    var done = 0, bytesDone = 0; // to'liq tugagan partiyalar bo'yicha
    onProgress?.call(0, total, 0, totalBytes);
    for (var i = 0; i < entries.length; i += batchSize) {
      final end =
          (i + batchSize < entries.length) ? i + batchSize : entries.length;
      final batch = entries.sublist(i, end);
      // Bigger files (GLB/mesh) → longer ceiling so slow uplinks don't time out.
      final batchBytes = batch.fold<int>(0, (s, e) => s + e.sizeBytes);
      final secs = 60 + (batchBytes / (1024 * 1024) * 4).ceil(); // ~4s per MB
      List<String> keys;
      try {
        keys = await upload(
          category: UploadCategory.scanBundle,
          filePaths: batch.map((e) => e.path).toList(growable: false),
          token: token,
          endpoint: endpoint,
          timeout: Duration(seconds: secs.clamp(60, 600)),
          // Jonli bayt-progress: partiya yuklanayotganda bar uzluksiz harakatlanadi
          // (multipart overhead'i bois batchBytes'dan oshib ketmasin deb cheklaymiz).
          onBytes: (sentInBatch) {
            if (onProgress == null) return;
            final capped = sentInBatch > batchBytes ? batchBytes : sentInBatch;
            final live = bytesDone + capped;
            onProgress(done, total, live > totalBytes ? totalBytes : live,
                totalBytes);
          },
        );
      } catch (_) {
        keys = const []; // bu partiya yiqildi — o'tkazib yuboramiz, davom etamiz
      }
      for (var j = 0; j < batch.length; j++) {
        final e = batch[j];
        final key = j < keys.length ? keys[j] : null;
        if (key != null) {
          if (e.type == 'frame') {
            frames.add(key);
          } else {
            scanFiles[e.type] = key;
          }
        }
        done++;
      }
      bytesDone += batchBytes;
      onProgress?.call(done, total, bytesDone, totalBytes);
    }
    if (frames.isNotEmpty) scanFiles['frames'] = frames;
    return scanFiles;
  }

  void dispose() => _client.close();
}
