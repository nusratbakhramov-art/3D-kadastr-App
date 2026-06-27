import 'dart:convert';

import '../../core/api_config.dart';
import '../auth/auth_http_client.dart';

/// Server-side belgilangan to'lov summasi (mijoz o'zgartira olmaydi).
class PaymentQuote {
  const PaymentQuote({required this.amount, required this.currency});

  final num amount;
  final String currency;
}

/// To'lovlar tarixidagi bitta yozuv (`GET /payments/`).
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.paymentType,
    required this.provider,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.referenceType,
    this.referenceId,
  });

  final int id;
  final String paymentType; // ai_valuation | marketplace_purchase | ...
  final String provider; // payme | click | uzum
  final num amount;
  final String status; // pending | processing | completed | failed | cancelled | refunded
  final DateTime createdAt;
  final String? referenceType;
  final int? referenceId;

  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
        id: (j['id'] as num).toInt(),
        paymentType: (j['payment_type'] as String?) ?? '',
        provider: (j['provider'] as String?) ?? '',
        amount: num.tryParse('${j['amount']}') ?? 0,
        status: ((j['status'] as String?) ?? 'pending').toLowerCase(),
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        referenceType: j['reference_type'] as String?,
        referenceId: (j['reference_id'] as num?)?.toInt(),
      );
}

/// AI Baholash arizasi to'lovi:
///   • [getQuote] — summani backenddan oladi (UI'da ko'rsatish uchun),
///   • [initiate] — to'lovni boshlaydi va Payme checkout URL'ini qaytaradi.
class PaymentCheckoutService {
  PaymentCheckoutService({AuthHttpClient? client})
      : _client = client ?? AuthHttpClient();

  final AuthHttpClient _client;
  static const _timeout = Duration(seconds: 20);

  /// Backend `PaymentType.AI_VALUATION` (FastAPI enum query = qiymat).
  static const aiValuationType = 'ai_valuation';

  /// Backend `PaymentType.MARKETPLACE_PURCHASE` — marketplace 3D model sotib olish.
  static const marketplacePurchaseType = 'marketplace_purchase';

  Future<PaymentQuote> getQuote(String paymentType) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/payments/quote')
        .replace(queryParameters: {'payment_type': paymentType});
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Narxni olishda xatolik (${res.statusCode})');
    }
    final b = jsonDecode(res.body) as Map<String, dynamic>;
    return PaymentQuote(
      amount: num.tryParse('${b['amount']}') ?? 0,
      currency: b['currency'] as String? ?? 'UZS',
    );
  }

  /// To'lovni boshlaydi → ochish uchun checkout URL qaytaradi. `amount` server
  /// tomonda (ai_valuation uchun) majburlanadi, lekin moslik uchun yuboramiz.
  /// To'lovni boshlaydi → ochish uchun checkout URL + payment id qaytaradi.
  /// payment id app fonдан qaytganda status polling uchun kerak (return-to-app).
  Future<({String url, int paymentId})> initiate({
    required String paymentType,
    required String provider,
    required num amount,
    String? referenceType,
    int? referenceId,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/payments/initiate');
    final res = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'payment_type': paymentType,
            'provider': provider,
            'amount': amount,
            if (referenceType != null) 'reference_type': referenceType,
            if (referenceId != null) 'reference_id': referenceId,
          }),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('To\'lovni boshlashda xatolik (${res.statusCode})');
    }
    final b = jsonDecode(res.body) as Map<String, dynamic>;
    final url = b['checkout_url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Checkout URL bo\'sh keldi');
    }
    return (url: url, paymentId: (b['payment_id'] as num).toInt());
  }

  /// To'lov holati — appga qaytgach polling uchun. `pending` / `processing` /
  /// `completed` / `failed` / `cancelled` (yoki xatoda `unknown`).
  Future<String> getStatus(int paymentId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/payments/$paymentId');
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) return 'unknown';
    final b = jsonDecode(res.body) as Map<String, dynamic>;
    return (b['status'] as String?)?.toLowerCase() ?? 'unknown';
  }

  /// To'lovlar tarixi. [status] berilsa — server tomonда shu status bo'yicha
  /// filtrlanadi (`pending`/`processing`/`completed`/`failed`/`cancelled`).
  Future<({List<PaymentRecord> items, int total})> list({
    int page = 1,
    int size = 100,
    String? status,
  }) async {
    final qp = <String, String>{'page': '$page', 'size': '$size'};
    if (status != null) qp['status'] = status;
    final uri = Uri.parse('${ApiConfig.baseUrl}/payments/')
        .replace(queryParameters: qp);
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('To\'lovlarni olishda xatolik (${res.statusCode})');
    }
    final b = jsonDecode(res.body) as Map<String, dynamic>;
    final items = ((b['items'] as List<dynamic>?) ?? const [])
        .map((e) => PaymentRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (b['total'] as num?)?.toInt() ?? items.length);
  }
}
