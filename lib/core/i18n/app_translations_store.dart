library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_config.dart';
import 'app_translations.dart';

class AppTranslationsStore {
  AppTranslationsStore._();
  static final AppTranslationsStore instance = AppTranslationsStore._();

  static const String _cacheKey = 'app_translations_v1';
  static const Duration _timeout = Duration(seconds: 12);

  Future<void> loadCachedThenRefresh({http.Client? client}) async {
    await _loadCache();
    await refresh(client: client);
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      appTranslationsNotifier.value = AppTranslations.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
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
      appTranslationsNotifier.value = bundle;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(bundle.toJson()));
    } catch (_) {
      // Network or parse error. Keep cache/defaults.
    } finally {
      if (client == null) c.close();
    }
  }
}
