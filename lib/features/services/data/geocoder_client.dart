/// Address autocomplete + reverse geocoding for the AI Baholash location
/// step.
///
/// Tries Yandex first (when `ApiConfig.yandexGeocoderApiKey` is non-empty
/// — better UZ coverage), otherwise falls back to OpenStreetMap Nominatim
/// (free, no key, slower, weaker UZ coverage but works).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api_config.dart';

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

  /// Provider-specific category ("house", "metro", "biz", "amenity", …).
  /// UI may use it for an icon.
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
  GeocoderClient({
    http.Client? client,
    this.userAgent = 'uz.kadastr.kadastr',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;

  bool get _hasYandex => ApiConfig.yandexGeocoderApiKey.isNotEmpty;

  /// Type-as-you-go autocomplete. `query` shorter than 3 chars returns []
  /// (network noise filter). Cancel-via-token is the caller's job — we just
  /// honor [http.Client.close] from `dispose`.
  Future<List<GeoSuggestion>> autocomplete(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    if (_hasYandex) return _yandexAutocomplete(q);
    return _nominatimAutocomplete(q);
  }

  /// Reverse: lat/lng → human-readable address text.
  Future<String?> reverse(double lat, double lng) async {
    if (_hasYandex) return _yandexReverse(lat, lng);
    return _nominatimReverse(lat, lng);
  }

  void dispose() => _client.close();

  // ── Yandex ────────────────────────────────────────────────────────────

  Future<List<GeoSuggestion>> _yandexAutocomplete(String q) async {
    final uri = Uri.https('geocode-maps.yandex.ru', '/1.x/', {
      'apikey': ApiConfig.yandexGeocoderApiKey,
      'format': 'json',
      'lang': 'uz_UZ',
      'results': '8',
      'bbox': '55.9,37.1~73.2,45.6', // UZ bbox: filters out non-UZ noise
      'rspn': '1',
      'geocode': q,
    });
    final body = await _getJson(uri);
    final features =
        (((body['response'] as Map?)?['GeoObjectCollection'] as Map?)?[
                'featureMember'] as List?) ??
            const [];
    return [
      for (final f in features)
        if (_geoFromYandex(f as Map) case final s?) s,
    ];
  }

  GeoSuggestion? _geoFromYandex(Map feature) {
    final obj = feature['GeoObject'] as Map?;
    if (obj == null) return null;
    final point = (obj['Point'] as Map?)?['pos'] as String?;
    if (point == null) return null;
    final parts = point.split(' ');
    if (parts.length != 2) return null;
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    final meta = (((obj['metaDataProperty'] as Map?)?['GeocoderMetaData']
        as Map?));
    final kind = meta?['kind'] as String?;
    final addressText = meta?['text'] as String?;
    return GeoSuggestion(
      name: (obj['name'] as String?) ?? (addressText ?? 'Joy'),
      description: (obj['description'] as String?) ?? (addressText ?? ''),
      lat: lat,
      lng: lng,
      kind: kind,
    );
  }

  Future<String?> _yandexReverse(double lat, double lng) async {
    final uri = Uri.https('geocode-maps.yandex.ru', '/1.x/', {
      'apikey': ApiConfig.yandexGeocoderApiKey,
      'format': 'json',
      'lang': 'uz_UZ',
      'results': '1',
      // Yandex wants `lng,lat`.
      'geocode': '$lng,$lat',
    });
    final body = await _getJson(uri);
    final features =
        (((body['response'] as Map?)?['GeoObjectCollection'] as Map?)?[
                'featureMember'] as List?) ??
            const [];
    if (features.isEmpty) return null;
    final obj = (features.first as Map)['GeoObject'] as Map?;
    return (((obj?['metaDataProperty'] as Map?)?['GeocoderMetaData'] as Map?)?[
        'text'] as String?);
  }

  // ── OpenStreetMap Nominatim (free fallback) ─────────────────────────

  Future<List<GeoSuggestion>> _nominatimAutocomplete(String q) async {
    final uri =
        Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '8',
      // Bias toward UZ. Other countries still possible but UZ first.
      'countrycodes': 'uz',
      'accept-language': 'uz,ru,en',
    });
    final body = await _getJson(uri, listExpected: true);
    final list = body is List ? body : <dynamic>[];
    return [
      for (final raw in list)
        if (_geoFromNominatim(raw as Map) case final s?) s,
    ];
  }

  GeoSuggestion? _geoFromNominatim(Map raw) {
    final lat = double.tryParse(raw['lat']?.toString() ?? '');
    final lon = double.tryParse(raw['lon']?.toString() ?? '');
    if (lat == null || lon == null) return null;
    final addr = raw['address'] as Map? ?? const {};
    // Use the "name" / first-line address from `display_name` for the title
    // and the rest for the description.
    final display = (raw['display_name'] as String?) ?? '';
    final commaIdx = display.indexOf(',');
    final name = commaIdx == -1 ? display : display.substring(0, commaIdx).trim();
    final desc =
        commaIdx == -1 ? '' : display.substring(commaIdx + 1).trim();
    return GeoSuggestion(
      name: name.isNotEmpty ? name : (addr['road']?.toString() ?? 'Joy'),
      description: desc,
      lat: lat,
      lng: lon,
      kind: raw['type'] as String?,
    );
  }

  Future<String?> _nominatimReverse(double lat, double lng) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat',
      'lon': '$lng',
      'format': 'jsonv2',
      'accept-language': 'uz,ru,en',
      'zoom': '18',
    });
    final body = await _getJson(uri);
    return body['display_name'] as String?;
  }

  // ── Plumbing ─────────────────────────────────────────────────────────

  Future<dynamic> _getJson(Uri uri, {bool listExpected = false}) async {
    try {
      final res = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
        },
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw GeocoderException('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      if (listExpected) return decoded;
      if (decoded is! Map) {
        throw GeocoderException('javob noto\'g\'ri formatda');
      }
      return decoded;
    } on TimeoutException {
      throw GeocoderException('Yandex/Nominatim vaqtida javob bermadi');
    } on FormatException {
      throw GeocoderException('javob JSON emas');
    }
  }
}
