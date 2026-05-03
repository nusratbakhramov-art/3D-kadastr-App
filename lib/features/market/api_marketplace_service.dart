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
  MarketplaceApiService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 15);

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

    final res = await _client.get(uri).timeout(_timeout);
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
        .get(Uri.parse('$_baseUrl/marketplace/$id'))
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
        .map(
          (s) => MarketListingScene(
            id: (s['id'] as num).toInt(),
            name: s['name'] as String? ?? '',
            previewUrl: s['preview_url'] as String?,
            sortOrder: (s['sort_order'] as num?)?.toInt() ?? 0,
          ),
        )
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
      categoryId: _mapCategory(json['category'] as String? ?? 'other'),
      description: json['description'] as String?,
      isFree: isFree,
      scenes: scenes,
      files: files,
    );
  }

  // Backend has 6 categories; mobile UI groups them into 3 chip-friendly
  // buckets. Mapping is purely for filter UX — the original value is not lost
  // because the chip itself filters server-side via `category` query param.
  String _mapCategory(String backend) {
    switch (backend) {
      case 'residential':
        return 'residential';
      case 'commercial':
      case 'industrial':
        return 'nonresidential';
      case 'architectural':
      case 'interior':
      case 'other':
      default:
        return 'projects';
    }
  }
}
