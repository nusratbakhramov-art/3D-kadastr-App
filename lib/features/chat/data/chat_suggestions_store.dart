/// Yordamchi bot "tez savol" chiplari — keshli, versiya bo'yicha yangilanadigan
/// do'kon (i18n tarjimalari bilan BIR XIL uslub, [AppTranslationsStore]).
///
/// `loadCachedThenRefresh()` app startida chaqiriladi: avval keshdan (agar bor
/// bo'lsa) darhol ko'rsatadi, keyin fonda backend versiyasini so'raydi va faqat
/// versiya yangi bo'lsagina to'liq ro'yxatni qayta yuklab keshni yangilaydi.
/// Tarmoq/parse xatosida jimgina keshda qoladi — chat ekrani baribir ishlaydi
/// (zaxira `_defaultSuggestions`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_config.dart';

/// Backend'dan olingan faol savol matnlari, til bo'yicha guruhlangan + versiya.
@immutable
class ChatSuggestions {
  const ChatSuggestions({this.version = 0, this.locales = const {}});

  final int version;
  final Map<String, List<String>> locales;

  bool get isEmpty => locales.isEmpty;

  /// Berilgan til uchun tartiblangan savol matnlari (yo'q bo'lsa bo'sh).
  List<String> forLocale(String lang) => locales[lang] ?? const [];

  factory ChatSuggestions.fromJson(Map<String, dynamic> json) {
    final rawLocales = (json['locales'] as Map?) ?? const {};
    final locales = <String, List<String>>{};
    rawLocales.forEach((key, value) {
      if (key is String && value is List) {
        locales[key] = value
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    });
    return ChatSuggestions(
      version: (json['version'] as num?)?.toInt() ?? 0,
      locales: locales,
    );
  }

  Map<String, dynamic> toJson() => {'version': version, 'locales': locales};
}

/// Joriy takliflar — chat ekrani shu notifier'ni tinglaydi.
final ValueNotifier<ChatSuggestions> chatSuggestionsNotifier =
    ValueNotifier<ChatSuggestions>(const ChatSuggestions());

class ChatSuggestionsStore {
  ChatSuggestionsStore._();
  static final ChatSuggestionsStore instance = ChatSuggestionsStore._();

  static const String _cacheKey = 'chat_suggestions_v1';
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
      chatSuggestionsNotifier.value = ChatSuggestions.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // Buzuq kesh. Standartda qolamiz (bo'sh).
    }
  }

  Future<void> refresh({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final versionResponse = await c
          .get(
            Uri.parse('${ApiConfig.baseUrl}/chat/suggestions/version'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (versionResponse.statusCode != 200) return;

      final remoteVersion =
          ((jsonDecode(versionResponse.body) as Map)['version'] as num?)
              ?.toInt() ??
          0;
      final current = chatSuggestionsNotifier.value;
      // Versiya yangi emas va keshda bor — hech narsa yuklamaymiz.
      if (remoteVersion <= current.version && !current.isEmpty) return;

      final bundleResponse = await c
          .get(
            Uri.parse('${ApiConfig.baseUrl}/chat/suggestions/bundle'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (bundleResponse.statusCode != 200) return;

      final bundle = ChatSuggestions.fromJson(
        jsonDecode(bundleResponse.body) as Map<String, dynamic>,
      );
      chatSuggestionsNotifier.value = bundle;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(bundle.toJson()));
    } catch (_) {
      // Tarmoq yoki parse xatosi. Kesh/standartda qolamiz.
    } finally {
      if (client == null) c.close();
    }
  }
}
