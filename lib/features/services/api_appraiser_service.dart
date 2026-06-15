/// Fetches the appraisal company's legal credentials (license, certificate,
/// insurance, …) shown on the AI Baholash credentials screen before payment.
/// Admin-managed on the backend (`GET /api/v1/appraiser/credentials`, public).
library;

import 'dart:convert';

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

  void dispose() => _client.close();

  Future<List<AppraiserCredential>> fetchCredentials() async {
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
