/// Cadastre lookup entry point.
///
/// Was a thin client around the backend `/scans/cadastre-lookup` endpoint
/// (which scraped davreestr.uz server-side). The backend IP kept getting
/// rate-limited by davreestr, so the scrape now runs on each user's phone
/// via [DavreestrClient]. This class is kept as a stable public surface
/// (`CadastreLookupResult` / `CadastreLookupException` types) so the two
/// cadastre input screens didn't need to be rewritten.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import '../auth/auth_http_client.dart';
import 'data/davreestr_client.dart';

class CadastreLookupResult {
  const CadastreLookupResult({
    required this.cadastreNumber,
    this.address,
    this.objectTypeHint,
    this.totalArea,
    this.livingArea,
    this.cadastreValue,
  });

  final String cadastreNumber;
  final String? address;
  final String? objectTypeHint;
  final double? totalArea; // m²
  final double? livingArea; // m²
  final double? cadastreValue; // so'm

  /// Draft payload'dan qayta tiklash (resume). `bundle.toJson()['kadastr']`ga mos.
  factory CadastreLookupResult.fromJson(Map<String, dynamic> j) =>
      CadastreLookupResult(
        cadastreNumber: j['cadastre_number']?.toString() ?? '',
        address: j['address'] as String?,
        objectTypeHint: j['object_type_hint'] as String?,
        totalArea: (j['total_area'] as num?)?.toDouble(),
        livingArea: (j['living_area'] as num?)?.toDouble(),
        cadastreValue: (j['cadastre_value'] as num?)?.toDouble(),
      );
}

class CadastreLookupException implements Exception {
  const CadastreLookupException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'CadastreLookupException: $message';
}

class CadastreApiService {
  CadastreApiService({http.Client? client, String? baseUrl})
      : _backendClient = client,
        _backendBaseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client? _backendClient;
  final String _backendBaseUrl;

  Future<CadastreLookupResult> lookup({
    required String cadastreNumber,
    required String token,
    bool forceRefresh = false,
  }) async {
    final scraper = DavreestrClient(
      backendBaseUrl: _backendBaseUrl,
      authToken: token,
      backendClient: _backendClient,
    );
    try {
      final r = await scraper.lookup(cadastreNumber, forceRefresh: forceRefresh);
      return CadastreLookupResult(
        cadastreNumber: r.cadastreNumber,
        address: r.address,
        objectTypeHint: r.objectTypeHint,
        totalArea: r.totalArea,
        livingArea: r.livingArea,
        cadastreValue: r.cadastreValue,
      );
    } on DavreestrLookupException catch (e) {
      throw CadastreLookupException(e.message, statusCode: e.statusCode);
    } finally {
      // Only dispose if we created the http client internally — caller-owned
      // clients are the caller's responsibility.
      if (_backendClient == null) scraper.dispose();
    }
  }

  /// The user's recently-looked-up kadastr numbers, newest first. Powers the
  /// quick-pick chips on the entry screen. Fails soft to an empty list.
  Future<List<String>> recent({required String token}) async {
    final client = _backendClient ?? AuthHttpClient();
    try {
      final uri = Uri.parse('$_backendBaseUrl/davreestr/recent');
      final res = await client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => e.toString()).toList(growable: false);
    } catch (_) {
      return const [];
    } finally {
      if (_backendClient == null) client.close();
    }
  }
}
