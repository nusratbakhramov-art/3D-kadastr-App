/// Professional smeta — HTTP client.
///
/// Talks to the backend's `/abc4/jobs` (full ABC pipeline) and
/// `/abc4/catalog/*` (СНиР code autocomplete) endpoints. The actual
/// computation happens in the ABC-UZ desktop app behind the reverse
/// bridge — runs typically take 60–180 seconds.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api_config.dart';
import '../models/smeta_draft.dart';

class SmetaApiException implements Exception {
  SmetaApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'SmetaApiException($statusCode): $message';
}

class SmetaApiService {
  SmetaApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  // ─── catalog ────────────────────────────────────────────────────────

  Future<List<CatalogBook>> books() async {
    final r = await _client.get(Uri.parse('$_baseUrl/abc4/catalog/books'));
    _ensure2xx(r, 'catalog/books');
    final list = jsonDecode(r.body) as List<dynamic>;
    return list
        .map((e) => CatalogBook.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// `q` is a substring of the code OR the name (server decides).
  /// `book` is the file id (e.g. `00-UZ-E01`).
  Future<List<CatalogCode>> codes({
    String? q,
    String? book,
    int limit = 30,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (q != null && q.isNotEmpty) params['q'] = q;
    if (book != null && book.isNotEmpty) params['book'] = book;
    final uri = Uri.parse('$_baseUrl/abc4/catalog/codes')
        .replace(queryParameters: params);
    final r = await _client.get(uri);
    _ensure2xx(r, 'catalog/codes');
    final list = jsonDecode(r.body) as List<dynamic>;
    return list
        .map((e) => CatalogCode.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ─── jobs ───────────────────────────────────────────────────────────

  /// Enqueue and (optionally) wait. With `wait > 0` the server long-polls
  /// for up to that many seconds before responding. The HTTP timeout is
  /// scaled accordingly so the client doesn't disconnect early.
  Future<SmetaJobSnapshot> enqueue(SmetaDraft draft, {int wait = 0}) async {
    final uri = wait > 0
        ? Uri.parse('$_baseUrl/abc4/jobs?wait=$wait')
        : Uri.parse('$_baseUrl/abc4/jobs');
    final timeout = Duration(seconds: wait > 0 ? wait + 10 : 30);
    final body = jsonEncode(draft.toEstimatePayload());
    final r = await _client
        .post(uri, headers: _jsonHeaders, body: body)
        .timeout(timeout);
    _ensure2xx(r, 'POST jobs');
    return SmetaJobSnapshot.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<SmetaJobSnapshot> status(String jobId, {int wait = 0}) async {
    final uri = wait > 0
        ? Uri.parse('$_baseUrl/abc4/jobs/$jobId?wait=$wait')
        : Uri.parse('$_baseUrl/abc4/jobs/$jobId');
    final timeout = Duration(seconds: wait > 0 ? wait + 10 : 15);
    final r = await _client.get(uri).timeout(timeout);
    _ensure2xx(r, 'GET jobs/$jobId');
    return SmetaJobSnapshot.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Names of the HTM export files (Form N5/N6 ведомость + input echo +
  /// error report + translator output). Empty until the driver finishes.
  Future<List<String>> exports(String jobId) async {
    final r =
        await _client.get(Uri.parse('$_baseUrl/abc4/jobs/$jobId/exports'));
    _ensure2xx(r, 'GET jobs/$jobId/exports');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['files'] as List?) ?? const []).cast<String>();
  }

  /// Absolute URL of one export — pass to a WebView or download intent.
  String exportUrl(String jobId, String filename) =>
      '$_baseUrl/abc4/jobs/$jobId/exports/$filename';

  // ─── plumbing ───────────────────────────────────────────────────────

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  void _ensure2xx(http.Response r, String tag) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    String snippet = r.body;
    if (snippet.length > 200) snippet = '${snippet.substring(0, 200)}…';
    throw SmetaApiException('$tag failed: $snippet', statusCode: r.statusCode);
  }
}
