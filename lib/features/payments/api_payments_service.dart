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
    final uri = Uri.parse('${ApiConfig.baseUrl}/profile/payments')
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
    final rawType = (j['payment_type'] as String? ?? '').trim();
    final externalId = (j['external_id'] as String?)?.trim();
    return Payment(
      id: '${j['id']}',
      type: PaymentTypeX.fromCode(rawType),
      rawType: rawType,
      amount: _toInt(j['amount']),
      method: PaymentMethodLabel.fromCode(j['provider'] as String? ?? ''),
      status: PaymentStatusX.fromCode(j['status'] as String? ?? ''),
      externalId: (externalId == null || externalId.isEmpty) ? null : externalId,
      at: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  static int _toInt(dynamic v) =>
      v == null ? 0 : (double.tryParse(v.toString()) ?? 0).round();
}
