import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Diskka saqlash uchun — backend javobi bilan bir xil kalitlar, shuning
  /// uchun o'qishda ham [fromJson] ishlaydi.
  Map<String, dynamic> toJson() => {
    'phone': phone,
    'email': email,
    'telegram': telegram,
    'working_hours': workingHours,
    'call_center': callCenter,
  };
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

  /// Oxirgi muvaffaqiyatli javob diskda — `AppTranslationsStore` bilan bir xil
  /// yondashuv.
  ///
  /// Xotiradagi kesh jarayon bilan birga o'ladi: ilova YOPILIB, internetsiz
  /// qaytadan ochilsa, aloqa ma'lumotlari yo'qolardi va Yordam sahifasida
  /// faqat zaxira raqam qolardi. Telegram va pochta aynan aloqa yo'q paytda
  /// kerak bo'ladi.
  static const String _prefsKey = 'support_info_v1';

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
        // Kutamiz: yozuv mikrosoniyalik ish, lekin "olindi" deyilgach u
        // DISKDA bo'lishi kerak — aks holda ilova shu zahoti yopilsa,
        // keyingi internetsiz ochilishda hech narsa qolmaydi.
        await _persist(info);
        return info;
      }
    } catch (_) {
      // Tarmoq/parsing xatosi — quyida oxirgi ma'lum qiymatga tushamiz.
    }
    if (_cache != null) return _cache!;
    final stored = await _restore();
    if (stored != null) {
      _cache = stored;
      return stored;
    }
    return const SupportInfo(phone: fallbackPhone);
  }

  Future<void> _persist(SupportInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(info.toJson()));
    } catch (_) {
      // Saqlanmasa ham ilova ishlayveradi — bu faqat qulaylik.
    }
  }

  Future<SupportInfo?> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      return SupportInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Testlar uchun: jarayon keshi statik bo'lgani uchun tozalash kerak.
  static void resetCacheForTest() => _cache = null;
}
