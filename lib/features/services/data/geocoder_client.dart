/// Address autocomplete + reverse geocoding for the AI Baholash location step.
///
/// Calls the BACKEND geocoding proxy (`/api/v1/geo/*`) rather than a third-party
/// geocoder directly. Phones hitting Nominatim/Yandex from mobile-carrier IPs
/// get rate-limited/blocked; the backend fronts it (one server IP, caching,
/// policy-compliant User-Agent) and can swap the provider with no app update.
/// [AuthHttpClient] attaches the bearer token automatically.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api_config.dart';
import '../../auth/auth_http_client.dart';

/// One suggestion from forward geocoding (autocomplete).
class GeoSuggestion {
  const GeoSuggestion({
    required this.name,
    required this.description,
    required this.lat,
    required this.lng,
    this.kind,
  });

  final String name;
  final String description;
  final double lat;
  final double lng;

  /// Provider-specific category ("house", "metro", …). UI may use it for an
  /// icon. The backend proxy doesn't emit it today; kept for compatibility.
  final String? kind;

  @override
  String toString() => '$name — $description ($lat, $lng)';
}

class GeocoderException implements Exception {
  GeocoderException(this.message);
  final String message;
  @override
  String toString() => 'GeocoderException: $message';
}

class GeocoderClient {
  GeocoderClient({http.Client? client}) : _client = client ?? AuthHttpClient();

  final http.Client _client;

  void dispose() => _client.close();

  /// Type-as-you-go autocomplete. `query` shorter than 3 chars returns []
  /// (network-noise filter).
  Future<List<GeoSuggestion>> autocomplete(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    final uri = Uri.parse('${ApiConfig.baseUrl}/geo/autocomplete')
        .replace(queryParameters: {'q': q});
    final body = await _getJson(uri);
    final list = (body['results'] as List?) ?? const [];
    return [
      for (final raw in list)
        if (raw is Map) ?_fromJson(raw),
    ];
  }

  /// Reverse: lat/lng → human-readable address text (null if unknown).
  Future<String?> reverse(double lat, double lng) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/geo/reverse')
        .replace(queryParameters: {'lat': '$lat', 'lng': '$lng'});
    final body = await _getJson(uri);
    final addr = body['address'];
    return addr is String && addr.isNotEmpty ? addr : null;
  }

  GeoSuggestion? _fromJson(Map raw) {
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return GeoSuggestion(
      name: (raw['name'] as String?) ?? '',
      description: (raw['description'] as String?) ?? '',
      lat: lat,
      lng: lng,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw GeocoderException('HTTP ${res.statusCode}');
      }
      // Decode bytes as UTF-8 explicitly — addresses are Cyrillic and the http
      // package falls back to latin1 when the response omits a charset.
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw GeocoderException('javob noto\'g\'ri formatda');
      }
      return decoded;
    } on TimeoutException {
      throw GeocoderException('geokoder vaqtida javob bermadi');
    } on FormatException {
      throw GeocoderException('javob JSON emas');
    }
  }
}
