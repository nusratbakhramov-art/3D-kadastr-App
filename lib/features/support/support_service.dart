import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_config.dart';

/// Qo'llab-quvvatlash ma'lumotlari (telefon raqami va h.k.) — backenddan olinadi.
class SupportInfo {
  const SupportInfo({
    required this.phone,
    this.email,
    this.telegram,
    this.workingHours,
    this.callCenter,
  });

  final String phone;
  final String? email;
  final String? telegram;
  final String? workingHours;

  /// «Aloqa markazi» qisqa raqami. Baholab bo'lmaydigan obyektlar uchun
  /// ko'rsatiladi. Adminkada to'ldirilmagan bo'lsa `null` — shunda [callNumber]
  /// oddiy qo'llab-quvvatlash raqamiga qaytadi.
  final String? callCenter;

  /// Aloqa markazi raqami, bo'lmasa — umumiy qo'llab-quvvatlash raqami.
  String get callNumber =>
      (callCenter?.isNotEmpty == true) ? callCenter! : phone;

  factory SupportInfo.fromJson(Map<String, dynamic> json) => SupportInfo(
    phone: (json['phone'] as String?)?.trim().isNotEmpty == true
        ? (json['phone'] as String).trim()
        : SupportService.fallbackPhone,
    email: (json['email'] as String?)?.trim(),
    telegram: (json['telegram'] as String?)?.trim(),
    workingHours: (json['working_hours'] as String?)?.trim(),
    callCenter: (json['call_center'] as String?)?.trim(),
  );
}

/// `GET /api/v1/support/info` orqali qo'llab-quvvatlash ma'lumotlarini oladi.
///
/// Tarmoq xatosi yoki endpoint mavjud bo'lmasa, ilova baribir ishlashi uchun
/// [fallbackPhone] qaytariladi. Natija jarayon davomida keshlanadi.
class SupportService {
  SupportService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 10);

  /// Backend yetib bo'lmasa ishlatiladigan zaxira raqam — aloqa markazining
  /// qisqa raqami (backenddagi `support_contact.DEFAULT_CONTACT` bilan bir xil).
  static const String fallbackPhone = '1269';

  static SupportInfo? _cache;

  Future<SupportInfo> fetchInfo({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;
    try {
      final res = await _client
          .get(
            Uri.parse('$_baseUrl/support/info'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final info = SupportInfo.fromJson(body);
        _cache = info;
        return info;
      }
    } catch (_) {
      // Tarmoq/parsing xatosi — pastdagi zaxira raqamga tushamiz.
    }
    return _cache ?? const SupportInfo(phone: fallbackPhone);
  }
}
