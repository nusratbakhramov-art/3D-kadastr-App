import 'dart:convert';

import '../../core/api_config.dart';
import '../../features/auth/auth_http_client.dart';
import 'payment_model.dart';

class ApiPaymentsService {
  ApiPaymentsService({AuthHttpClient? client})
      : _client = client ?? AuthHttpClient();

  final AuthHttpClient _client;
  static const _timeout = Duration(seconds: 15);

  Future<List<Payment>> fetchPayments({int page = 1, int size = 50}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/payments/')
        .replace(queryParameters: {'page': '$page', 'size': '$size'});
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('To\'lovlarni yuklashda xatolik: ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (body['items'] as List? ?? []);
    return items.map((j) => _fromJson(j as Map<String, dynamic>)).toList();
  }

  static Payment _fromJson(Map<String, dynamic> j) {
    return Payment(
      id: '${j['id']}',
      title: _titleForType(j['payment_type'] as String? ?? ''),
      amount: _toInt(j['amount']),
      method: _parseMethod(j['provider'] as String? ?? ''),
      at: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  static String _titleForType(String type) => switch (type.toLowerCase()) {
        'scan' => '3D skan xizmati',
        'valuation' => 'AI baholash hisoboti',
        'virtual_property' => 'Virtual mulk e\'loni',
        'subscription' => 'Obuna',
        'marketplace' => 'Marketplace xizmati',
        _ => type,
      };

  static PaymentMethod _parseMethod(String p) => switch (p.toLowerCase()) {
        'payme' => PaymentMethod.payme,
        'uzum' => PaymentMethod.uzum,
        _ => PaymentMethod.click,
      };

  static int _toInt(dynamic v) =>
      v == null ? 0 : (double.tryParse(v.toString()) ?? 0).round();
}
