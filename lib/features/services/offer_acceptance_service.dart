/// Ommaviy oferta AKSEPTINI arizaga biriktiradi.
///
/// Biz mijoz bilan ikki tomonlama shartnoma imzolamaymiz — xizmat ilovadagi
/// ommaviy oferta akseptlanishi bilan rasmiylashadi. Generatsiya qilinadigan
/// hisobotning "Baholash uchun asos" qismi ayni shu akseptga (sanasi, vaqti,
/// raqami va berilgan ikkita rozilikka) tayanadi, shuning uchun rozilik
/// serverda saqlanmasa hisobot huquqiy jihatdan asossiz bo'lib qoladi.
///
/// Pairs with `POST /api/v1/ai-valuations/{id}/offer-acceptance`.
library;

import 'dart:convert';

import '../../core/api_config.dart';
import '../auth/auth_http_client.dart';

class OfferAcceptanceService {
  OfferAcceptanceService({AuthHttpClient? client})
      : _client = client ?? AuthHttpClient();

  final AuthHttpClient _client;
  static const _timeout = Duration(seconds: 20);

  /// Ikkala rozilikni ham saqlaydi. Takroriy chaqiruvda backend BIRINCHI
  /// akseptni qaytaradi (dalil vaqti o'zgarmaydi).
  Future<void> accept({
    required int jobId,
    required String lang,
  }) async {
    final uri =
        Uri.parse('${ApiConfig.baseUrl}/ai-valuations/$jobId/offer-acceptance');
    final res = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'terms_accepted': true,
            'refund_acknowledged': true,
            'lang': lang,
          }),
        )
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }
}
