/// Kalkulyator narxlarini backend'dan olib keshlaydigan store.
///
/// `loadCachedThenRefresh()` app startida chaqiriladi: avval keshdan darhol
/// o'qiydi (tez), keyin API'dan yangilaydi. Narxlar [calculatorPricingNotifier]
/// orqali ekranlarga yetkaziladi (Provider yo'q — `ValueNotifier` global,
/// settings_state.dart patterni). Notifier boshlang'ich qiymati = defaults,
/// shuning uchun hech qachon null emas (offline xavfsiz).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_config.dart';
import '../models/calculator_pricing.dart';

/// Global — kalkulyator ekranlari shu qiymatdan o'qiydi.
final ValueNotifier<CalculatorPricing> calculatorPricingNotifier =
    ValueNotifier<CalculatorPricing>(CalculatorPricing.defaults);

class CalculatorPricingStore {
  CalculatorPricingStore._();
  static final CalculatorPricingStore instance = CalculatorPricingStore._();

  static const String _cacheKey = 'calculator_pricing_v1';
  static const Duration _timeout = Duration(seconds: 12);

  /// 1) Keshdan darhol o'qiydi, 2) API'dan yangilaydi.
  Future<void> loadCachedThenRefresh({http.Client? client}) async {
    await _loadCache();
    await refresh(client: client);
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      calculatorPricingNotifier.value = CalculatorPricing.fromJson(json);
    } catch (_) {
      // Buzilgan kesh — defaults qoladi.
    }
  }

  /// API'dan so'nggi narxlarni oladi va keshga yozadi. Xato bo'lsa joriy
  /// qiymat (kesh yoki defaults) o'zgarmaydi.
  Future<void> refresh({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c.get(
        Uri.parse('${ApiConfig.baseUrl}/calculator/pricing'),
        headers: {'Accept': 'application/json'},
      ).timeout(_timeout);
      if (res.statusCode != 200) return;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final pricing = CalculatorPricing.fromJson(json);
      calculatorPricingNotifier.value = pricing;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(pricing.toJson()));
    } catch (_) {
      // Tarmoq/parse xatosi — jim o'tamiz.
    } finally {
      if (client == null) c.close();
    }
  }
}
