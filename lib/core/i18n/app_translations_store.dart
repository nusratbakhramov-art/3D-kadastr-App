library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_config.dart';
import 'app_translations.dart';

class AppTranslationsStore {
  AppTranslationsStore._();
  static final AppTranslationsStore instance = AppTranslationsStore._();

  static const String _cacheKey = 'app_translations_v1';
  static const String _seedAsset = 'assets/i18n/bundle.json';
  static const Duration _timeout = Duration(seconds: 12);

  /// Ilova bilan kelgan seed — har doim poydevor sifatida saqlanadi, backend
  /// bundle'i uning ustiga qo'yiladi (`.over(_seed)`).
  AppTranslations _seed = AppTranslations.empty;

  Future<void> loadCachedThenRefresh({http.Client? client}) async {
    await _loadSeed();
    await _loadCache();
    // No prior backend cache on this device (fresh install / offline first run):
    // the seed alone carries the UI until the first successful network fetch.
    if (appTranslationsNotifier.value.isEmpty) {
      appTranslationsNotifier.value = _seed;
    }
    await refresh(client: client);
  }

  Future<void> _loadSeed() async {
    try {
      final raw = await rootBundle.loadString(_seedAsset);
      _seed = AppTranslations.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Seed missing or malformed. Keep defaults (empty).
    }
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      appTranslationsNotifier.value = AppTranslations.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      ).over(_seed);
    } catch (_) {
      // Bad cache. Keep defaults.
    }
  }

  Future<void> refresh({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final versionResponse = await c
          .get(
            Uri.parse('${ApiConfig.baseUrl}/i18n/version'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (versionResponse.statusCode != 200) return;

      final remoteVersion =
          ((jsonDecode(versionResponse.body) as Map)['version'] as num?)
              ?.toInt() ??
          0;
      final current = appTranslationsNotifier.value;
      if (remoteVersion <= current.version && !current.isEmpty) return;

      final bundleResponse = await c
          .get(
            Uri.parse('${ApiConfig.baseUrl}/i18n/bundle'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (bundleResponse.statusCode != 200) return;

      final bundle = AppTranslations.fromJson(
        jsonDecode(bundleResponse.body) as Map<String, dynamic>,
      );
      appTranslationsNotifier.value = bundle.over(_seed);
      final prefs = await SharedPreferences.getInstance();
      // Keshga backend javobi TOZA holda yoziladi — seed o'qishda qo'shiladi,
      // shunda yangi ilova versiyasining seed'i eski keshni ham to'ldiradi.
      await prefs.setString(_cacheKey, jsonEncode(bundle.toJson()));
    } catch (_) {
      // Network or parse error. Keep cache/defaults.
    } finally {
      if (client == null) c.close();
    }
  }
}
