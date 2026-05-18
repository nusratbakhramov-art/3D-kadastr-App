import 'dart:convert';

import '../../core/api_config.dart';
import '../../features/auth/auth_http_client.dart';
import 'valuation_model.dart';

class ApiValuationHistoryService {
  ApiValuationHistoryService({AuthHttpClient? client})
      : _client = client ?? AuthHttpClient();

  final AuthHttpClient _client;
  static const _timeout = Duration(seconds: 15);

  Future<List<Valuation>> fetchHistory() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/valuations/ai/history');
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Baholashlarni yuklashda xatolik: ${res.statusCode}');
    }
    final list = jsonDecode(res.body) as List;
    return list.map((j) => _fromJson(j as Map<String, dynamic>)).toList();
  }

  static Valuation _fromJson(Map<String, dynamic> j) {
    final address = [
      j['viloyat'] as String?,
      j['tuman'] as String?,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    return Valuation(
      id: '${j['id']}',
      address: address.isNotEmpty ? address : '—',
      objectType: (j['object_type'] as String?) ?? '',
      areaSqm: _toDouble(j['total_area_sqm']),
      at: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      abcValue: _toInt(j['abc_value'] ?? j['estimated_value']),
      marketValue: _toInt(j['market_value'] ?? j['estimated_value']),
      incomeValue: j['income_value'] != null ? _toInt(j['income_value']) : null,
      finalValue: _toInt(j['estimated_value']),
      confidence: _toDouble(j['confidence']),
    );
  }

  static double _toDouble(dynamic v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

  static int _toInt(dynamic v) =>
      v == null ? 0 : (double.tryParse(v.toString()) ?? 0).round();
}
