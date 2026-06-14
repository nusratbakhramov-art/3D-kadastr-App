/// Dizayn loyihasi TZ buyurtmasi uchun backend API client.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'models/design_order_draft.dart';

class DesignOrderApiException implements Exception {
  const DesignOrderApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'DesignOrderApiException: $message';
}

/// Backend qaytaradigan tasdiqlangan order ma'lumotlari.
class CreatedDesignOrder {
  const CreatedDesignOrder({
    required this.id,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final String status;
  final DateTime createdAt;
}

/// Arizalar ro'yxati uchun xulosaviy dizayn order yozuvi.
class DesignOrderSummary {
  const DesignOrderSummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.objectType,
    this.address,
  });

  final int id;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt; // oxirgi yangilanish — sort/ko'rsatish
  final String? objectType;
  final String? address;
}

class DesignOrderListPage {
  const DesignOrderListPage({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  final List<DesignOrderSummary> items;
  final int total;
  final int page;
  final int size;
}

class DesignOrderApiService {
  DesignOrderApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 20);

  /// Wizard yakunida draft'ni backend'ga yuborish.
  Future<CreatedDesignOrder> submit({
    required DizaynOrderDraft draft,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/services/design/orders');
    final body = jsonEncode(draft.toRequestJson());

    final res = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .timeout(_timeout);

    if (res.statusCode != 201 && res.statusCode != 200) {
      _throw(res);
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return CreatedDesignOrder(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'submitted',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Foydalanuvchi yuborgan dizayn TZ buyurtmalarini olish.
  Future<DesignOrderListPage> list({
    required String token,
    int page = 1,
    int size = 50,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/services/design/orders',
    ).replace(queryParameters: {'page': '$page', 'size': '$size'});

    final res = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(_timeout);

    if (res.statusCode != 200) _throw(res);

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['items'] as List).cast<Map<String, dynamic>>();
    return DesignOrderListPage(
      items: raw.map(_parseSummary).toList(growable: false),
      total: (body['total'] as num?)?.toInt() ?? raw.length,
      page: (body['page'] as num?)?.toInt() ?? page,
      size: (body['size'] as num?)?.toInt() ?? size,
    );
  }

  DesignOrderSummary _parseSummary(Map<String, dynamic> json) {
    final created = DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now();
    return DesignOrderSummary(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'submitted',
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? created,
      objectType: json['object_type'] as String?,
      address: json['address'] as String?,
    );
  }

  void dispose() => _client.close();

  Never _throw(http.Response res) {
    String msg = 'HTTP ${res.statusCode}';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        final detail = body['detail'];
        if (detail is String) {
          msg = detail;
        } else if (detail is List && detail.isNotEmpty) {
          // Pydantic validation errors — birinchisini ko'rsatamiz.
          final first = detail.first;
          if (first is Map && first['msg'] != null) msg = '${first['msg']}';
        }
      }
    } catch (_) {}
    throw DesignOrderApiException(msg, res.statusCode);
  }
}
