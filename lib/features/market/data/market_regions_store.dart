/// Market filtridagi hududlar — admin paneldan (API orqali) boshqariladi.
/// `calculator_pricing_store` patterni: global `ValueNotifier`, keshdan o'qiladi,
/// so'ng API'dan yangilanadi. API ishlamasa joriy qiymat (kesh/default) qoladi.
///
/// Ikki shakl:
///   - [marketRegionsNotifier] — tekis tuman ro'yxati (eski chip filtri uchun).
///   - [marketRegionTreeNotifier] — viloyat→tuman daraxti (akkordeon filtri).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_marketplace_service.dart';
import '../models/market_filters.dart';
import '../models/market_region_node.dart';

/// Tekis tuman ro'yxati — boshlang'ich qiymat defaultlar (hech qachon bo'sh emas).
final ValueNotifier<List<String>> marketRegionsNotifier =
    ValueNotifier<List<String>>(kMarketDistricts);

/// Viloyat→tuman daraxti — akkordeon filtri shu yerdan o'qiydi. Boshida bo'sh,
/// keshdan/API'dan to'ladi.
final ValueNotifier<List<MarketRegionNode>> marketRegionTreeNotifier =
    ValueNotifier<List<MarketRegionNode>>(const []);

class MarketRegionsStore {
  MarketRegionsStore._();
  static final MarketRegionsStore instance = MarketRegionsStore._();

  static const String _cacheKey = 'market_regions_v1';
  static const String _treeCacheKey = 'market_region_tree_v1';

  /// App startida chaqiriladi: avval keshdan darhol, keyin API'dan yangilaydi.
  Future<void> loadCachedThenRefresh({MarketplaceApiService? service}) async {
    await _loadCache();
    await refresh(service: service);
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List).cast<String>();
        if (list.isNotEmpty) marketRegionsNotifier.value = list;
      }
      final treeRaw = prefs.getString(_treeCacheKey);
      if (treeRaw != null) {
        final nodes = (jsonDecode(treeRaw) as List)
            .whereType<Map>()
            .map((m) => MarketRegionNode.fromJson(m.cast<String, dynamic>()))
            .toList();
        if (nodes.isNotEmpty) marketRegionTreeNotifier.value = nodes;
      }
    } catch (_) {
      // Buzilgan kesh — joriy qiymatlar qoladi.
    }
  }

  /// API'dan yangilaydi. Xato bo'lsa joriy qiymat (kesh/default) o'zgarmaydi.
  Future<void> refresh({MarketplaceApiService? service, http.Client? client}) async {
    final svc = service ?? MarketplaceApiService(client: client);
    final prefs = await SharedPreferences.getInstance();
    // Tekis ro'yxat (eski filtr) — orqaga moslik uchun.
    try {
      final regions = await svc.fetchRegions();
      if (regions.isNotEmpty) {
        marketRegionsNotifier.value = regions;
        await prefs.setString(_cacheKey, jsonEncode(regions));
      }
    } catch (_) {
      // Tarmoq/serv xatosi — joriy ro'yxat saqlanadi.
    }
    // Viloyat→tuman daraxti (akkordeon filtri).
    try {
      final tree = await svc.fetchRegionTree();
      if (tree.isNotEmpty) {
        marketRegionTreeNotifier.value = tree;
        await prefs.setString(
          _treeCacheKey,
          jsonEncode([for (final n in tree) n.toJson()]),
        );
      }
    } catch (_) {
      // Daraxt yetib bormasa — akkordeon kesh/bo'sh holatda qoladi.
    }
  }
}
