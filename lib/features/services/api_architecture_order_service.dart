/// Arxitektura TZ buyurtmasi uchun backend API client.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';
import 'models/architecture_order_draft.dart';

class ArchitectureOrderApiException implements Exception {
  const ArchitectureOrderApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ArchitectureOrderApiException: $message';
}

/// Backend qaytaradigan tasdiqlangan order ma'lumotlari.
class CreatedOrder {
  const CreatedOrder({
    required this.id,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final String status;
  final DateTime createdAt;
}

/// Backend list endpoint dan keladigan order yozuvi (xulosaviy).
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.objectType,
    required this.customerName,
    this.address,
    this.cadastreNumber,
    this.totalAreaSqm,
  });

  final int id;
  final String status; // submitted/reviewed/quoted/accepted/rejected/draft
  final DateTime createdAt;
  final DateTime updatedAt; // oxirgi yangilanish — sort/ko'rsatish
  final String objectType;
  final String customerName;
  final String? address;
  final String? cadastreNumber;
  final double? totalAreaSqm;
}

class OrderListPage {
  const OrderListPage({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
  });

  final List<OrderSummary> items;
  final int total;
  final int page;
  final int size;
}

class ArchitectureOrderApiService {
  ArchitectureOrderApiService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  static const Duration _timeout = Duration(seconds: 20);

  /// Wizard yakunida draft'ni backend'ga yuborish.
  Future<CreatedOrder> submit({
    required ArchitectureOrderDraft draft,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/services/architecture/orders');
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
    return CreatedOrder(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'submitted',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
              DateTime.now(),
    );
  }

  /// Foydalanuvchi yuborgan TZ buyurtmalarini olish.
  Future<OrderListPage> list({
    required String token,
    int page = 1,
    int size = 50,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/services/architecture/orders',
    ).replace(queryParameters: {'page': '$page', 'size': '$size'});

    final res = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_timeout);

    if (res.statusCode != 200) _throw(res);

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['items'] as List).cast<Map<String, dynamic>>();
    return OrderListPage(
      items: raw.map(_parseSummary).toList(growable: false),
      total: (body['total'] as num).toInt(),
      page: (body['page'] as num).toInt(),
      size: (body['size'] as num).toInt(),
    );
  }

  OrderSummary _parseSummary(Map<String, dynamic> json) {
    final area = json['total_area_sqm'];
    final created = DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now();
    return OrderSummary(
      id: (json['id'] as num).toInt(),
      status: json['status'] as String? ?? 'submitted',
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? created,
      objectType: json['object_type'] as String? ?? 'boshqa',
      customerName: json['customer_name'] as String? ?? '',
      address: json['address'] as String?,
      cadastreNumber: json['cadastre_number'] as String?,
      totalAreaSqm: area is num
          ? area.toDouble()
          : (area is String ? double.tryParse(area) : null),
    );
  }

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
    throw ArchitectureOrderApiException(msg, res.statusCode);
  }
}
