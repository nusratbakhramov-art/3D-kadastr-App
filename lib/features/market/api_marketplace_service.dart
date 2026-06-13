import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'models/market_listing.dart';

class MarketplaceApiException implements Exception {
  const MarketplaceApiException(this.message);
  final String message;
  @override
  String toString() => 'MarketplaceApiException: $message';
}

class MarketplaceListPage {
  const MarketplaceListPage({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  final List<MarketListing> items;
  final int total;
  final int page;
  final int size;

  bool get hasMore => page * size < total;
}

class DownloadInfo {
  const DownloadInfo({
    required this.url,
    required this.format,
    required this.expiresIn,
  });

  /// Absolute URL ready to fetch.
  final String url;
  final String format;
  final int expiresIn;
}

class MarketplaceApiService {
  MarketplaceApiService({http.Client? client, String? baseUrl, String? locale})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _locale = locale;

  final http.Client _client;
  final String _baseUrl;
  final String? _locale;
  static const Duration _timeout = Duration(seconds: 15);

  Map<String, String> _headers([Map<String, String>? extra]) {
    final h = <String, String>{};
    if (_locale != null && _locale.isNotEmpty) h['Accept-Language'] = _locale;
    if (extra != null) h.addAll(extra);
    return h;
  }

  /// Tumanlar (regionlar) ro'yxati — admin paneldan boshqariladi.
  /// `GET /marketplace/regions`. Javob string ro'yxati yoki {name|title}
  /// obyektlari bo'lishi mumkin — ikkalasini ham qo'llab-quvvatlaymiz.
  Future<List<String>> fetchRegions() async {
    final uri = Uri.parse('$_baseUrl/marketplace/regions');
    final res = await _client.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body);
    final list = body is Map ? (body['items'] as List? ?? const []) : body as List;
    final out = <String>[];
    for (final raw in list) {
      if (raw is String) {
        if (raw.trim().isNotEmpty) out.add(raw.trim());
      } else if (raw is Map) {
        final name = (raw['name'] ?? raw['title'] ?? raw['label']) as String?;
        if (name != null && name.trim().isNotEmpty) out.add(name.trim());
      }
    }
    return out;
  }

  Future<List<MarketCategoryRemote>> fetchCategories() async {
    final uri = Uri.parse('$_baseUrl/marketplace/categories');
    final res = await _client.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as List;
    return body
        .cast<Map<String, dynamic>>()
        .map(
          (m) => MarketCategoryRemote(
            id: (m['id'] as num).toInt(),
            slug: m['slug'] as String,
            name: m['name'] as String,
            sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<MarketplaceListPage> listModels({
    String? category,
    String? region,
    String? search,
    int page = 1,
    int size = 20,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'size': '$size',
      if (category != null && category.isNotEmpty) 'category': category,
      if (region != null && region.isNotEmpty) 'region': region,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final uri = Uri.parse(
      '$_baseUrl/marketplace/',
    ).replace(queryParameters: params);

    final res = await _client.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode != 200) _throw(res);

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final rawItems = (body['items'] as List).cast<Map<String, dynamic>>();
    final items = rawItems.map(_parseListing).toList(growable: false);
    return MarketplaceListPage(
      items: items,
      total: (body['total'] as num).toInt(),
      page: (body['page'] as num).toInt(),
      size: (body['size'] as num).toInt(),
    );
  }

  Future<MarketListing> getModel(int id) async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/marketplace/$id'), headers: _headers())
        .timeout(_timeout);
    if (res.statusCode != 200) _throw(res);
    return _parseListing(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Fetch a download URL for [fileId] of [modelId]. Returns an absolute URL
  /// ready to load. The user must be authenticated; pass their bearer token.
  Future<DownloadInfo> getDownloadUrl({
    required int modelId,
    required int fileId,
    required String token,
  }) async {
    final res = await _client
        .get(
          Uri.parse('$_baseUrl/marketplace/$modelId/download/$fileId'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_timeout);
    if (res.statusCode != 200) _throw(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = body['url'] as String;
    return DownloadInfo(
      url: ApiConfig.resolveUrl(raw),
      format: body['format'] as String? ?? 'GLB',
      expiresIn: (body['expires_in'] as num?)?.toInt() ?? 0,
    );
  }

  Never _throw(http.Response res) {
    String msg = 'HTTP ${res.statusCode}';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) msg = body['detail'].toString();
    } catch (_) {}
    throw MarketplaceApiException(msg);
  }

  // ---- Parsing ----

  MarketListing _parseListing(Map<String, dynamic> json) {
    final id = json['id'].toString();
    final name = json['name'] as String? ?? '';
    final region = json['region'] as String? ?? '';
    final isFree = json['is_free'] as bool? ?? false;
    final price = (json['price'] as num?)?.toInt() ?? 0;
    final areaRaw = json['area'];
    final area = areaRaw == null
        ? 0
        : (areaRaw is num ? areaRaw.toInt() : double.parse(areaRaw.toString()).toInt());
    final preview = json['preview_image_url'] as String?;
    final imageUrl = preview == null ? '' : ApiConfig.resolveUrl(preview);

    final scenes = ((json['scenes'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((s) {
          final rawUrl = s['preview_url'] as String?;
          return MarketListingScene(
            id: (s['id'] as num).toInt(),
            name: s['name'] as String? ?? '',
            previewUrl: (rawUrl == null || rawUrl.isEmpty)
                ? null
                : ApiConfig.resolveUrl(rawUrl),
            sortOrder: (s['sort_order'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);

    final files = ((json['files'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (f) => MarketListingFile(
            id: (f['id'] as num).toInt(),
            format: f['format'] as String? ?? 'GLB',
            fileSize: (f['file_size'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);

    return MarketListing(
      id: id,
      imageUrl: imageUrl,
      priceUzs: price,
      title: name,
      district: region,
      areaM2: area,
      categoryId: (json['category'] as String? ?? 'other').toLowerCase(),
      categoryLabel: json['category_label'] as String?,
      description: json['description'] as String?,
      isFree: isFree,
      scenes: scenes,
      files: files,
    );
  }
}

class MarketCategoryRemote {
  const MarketCategoryRemote({
    required this.id,
    required this.slug,
    required this.name,
    required this.sortOrder,
  });

  final int id;
  final String slug;
  final String name;
  final int sortOrder;
}
