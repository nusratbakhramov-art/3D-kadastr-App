import 'dart:convert';

import '../../core/api_config.dart';
import '../../features/auth/auth_http_client.dart';
import 'scan_model.dart';

class ApiScanService {
  ApiScanService({AuthHttpClient? client})
      : _client = client ?? AuthHttpClient();

  final AuthHttpClient _client;
  static const _timeout = Duration(seconds: 15);

  Future<List<ScanItem>> fetchScans({int page = 1, int size = 50}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/scans/')
        .replace(queryParameters: {'page': '$page', 'size': '$size'});
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Skanerlarni yuklashda xatolik: ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List? ?? []);
    return items.map((j) => _fromJson(j as Map<String, dynamic>)).toList();
  }

  static ScanItem _fromJson(Map<String, dynamic> j) {
    return ScanItem(
      id: '${j['id']}',
      cadastreNo: (j['cadastre_number'] as String?) ?? '',
      address: _buildAddress(j),
      objectType: (j['object_type'] as String?) ?? '',
      totalAreaSqm: _toDouble(j['total_area']),
      livingAreaSqm: _toDouble(j['living_area']),
      accuracyCm: _toDouble(j['accuracy']),
      cadastreValueUzs: _toInt(j['cadastre_value']),
      status: _parseStatus(j['status'] as String? ?? ''),
      at: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  static String _buildAddress(Map<String, dynamic> j) {
    final parts = <String>[];
    if (j['region'] != null) parts.add(j['region'] as String);
    if (j['district'] != null) parts.add(j['district'] as String);
    if (j['address'] != null) parts.add(j['address'] as String);
    return parts.join(', ');
  }

  static ScanStatus _parseStatus(String s) => switch (s.toUpperCase()) {
        'PROCESSING' => ScanStatus.processing,
        'VALUED' => ScanStatus.valued,
        _ => ScanStatus.uploaded,
      };

  static double _toDouble(dynamic v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  static int _toInt(dynamic v) =>
      v == null ? 0 : (double.tryParse(v.toString()) ?? 0).round();
}
