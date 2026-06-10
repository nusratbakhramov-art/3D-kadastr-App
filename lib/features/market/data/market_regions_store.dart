/// Market filtridagi "Tumanlar" ro'yxati — admin paneldan (API orqali)
/// boshqariladi. `calculator_pricing_store` patterni: global `ValueNotifier`
/// boshlang'ich qiymati = hardcoded defaultlar (`kMarketDistricts`), so'ng
/// keshdan o'qiladi va API'dan yangilanadi. API ishlamasa — joriy qiymat
/// (kesh yoki default) saqlanadi, ya'ni ilova doim ishlaydi.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_marketplace_service.dart';
import '../models/market_filters.dart';

/// Ekranlar shu notifier'dan o'qiydi. Boshlang'ich qiymat — defaultlar, shuning
/// uchun hech qachon bo'sh bo'lmaydi.
final ValueNotifier<List<String>> marketRegionsNotifier =
    ValueNotifier<List<String>>(kMarketDistricts);

class MarketRegionsStore {
  MarketRegionsStore._();
  static final MarketRegionsStore instance = MarketRegionsStore._();

  static const String _cacheKey = 'market_regions_v1';

  /// App startida chaqiriladi: avval keshdan darhol, keyin API'dan yangilaydi.
  Future<void> loadCachedThenRefresh({MarketplaceApiService? service}) async {
    await _loadCache();
    await refresh(service: service);
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<String>();
      if (list.isNotEmpty) marketRegionsNotifier.value = list;
    } catch (_) {
      // Buzilgan kesh — defaultlar qoladi.
    }
  }

  /// API'dan yangilaydi. Xato bo'lsa joriy qiymat (kesh/default) o'zgarmaydi.
  Future<void> refresh({MarketplaceApiService? service, http.Client? client}) async {
    final svc = service ?? MarketplaceApiService(client: client);
    try {
      final regions = await svc.fetchRegions();
      if (regions.isEmpty) return;
      marketRegionsNotifier.value = regions;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(regions));
    } catch (_) {
      // Tarmoq/serv xatosi — joriy ro'yxat saqlanadi.
    }
  }
}
