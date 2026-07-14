/// Fetches the appraisal company's legal credentials (license, certificate,
/// insurance, …) shown on the AI Baholash credentials screen before payment.
/// Admin-managed on the backend (`GET /api/v1/appraiser/credentials`, public).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:http/http.dart' as http;

import '../../core/api_config.dart';

class AppraiserCredential {
  const AppraiserCredential({required this.title, required this.imageUrl});

  final String title;

  /// Absolute, device-loadable URL ('' when no image is set yet).
  final String imageUrl;
}

class AppraiserService {
  AppraiserService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // Session cache — credentials rarely change, so we fetch them once per app
  // process and reuse the result across screen opens (About page, AI Baholash
  // step). Lives only in memory: killing the app clears it, so a fresh launch
  // fetches again. `_inflight` de-dupes concurrent first requests.
  static List<AppraiserCredential>? _cache;
  static Future<List<AppraiserCredential>>? _inflight;

  /// Clears the session cache so the next call re-fetches (e.g. pull-to-refresh
  /// or after an admin update).
  static void invalidateCache() {
    _cache = null;
    _inflight = null;
  }

  void dispose() => _client.close();

  Future<List<AppraiserCredential>> fetchCredentials({
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      // Warm cache → resolve synchronously so FutureBuilder renders instantly
      // (no loading-spinner flash on re-open).
      if (_cache != null) return SynchronousFuture(_cache!);
      if (_inflight != null) return _inflight!;
    }
    final future = _load().then((result) {
      _cache = result; // cache only successful results
      return result;
    });
    _inflight = future;
    future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
    return future;
  }

  Future<List<AppraiserCredential>> _load() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/appraiser/credentials');
    final res = await _client
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return const [];
    return [
      for (final raw in data)
        if (raw is Map)
          AppraiserCredential(
            title: (raw['title'] as String?) ?? '',
            imageUrl: _resolve((raw['image_url'] as String?) ?? ''),
          ),
    ];
  }

  static String _resolve(String url) =>
      url.isEmpty ? '' : ApiConfig.resolveUrl(url);
}
