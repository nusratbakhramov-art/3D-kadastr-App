library;

import 'package:flutter/widgets.dart';

@immutable
class AppTranslations {
  const AppTranslations({required this.version, required this.byLang});

  final int version;
  final Map<String, Map<String, String>> byLang;

  static const AppTranslations empty = AppTranslations(version: 0, byLang: {});

  bool get isEmpty => byLang.isEmpty;

  String? lookup(String lang, String key) {
    final value = byLang[lang]?[key];
    return (value != null && value.isNotEmpty) ? value : null;
  }

  factory AppTranslations.fromJson(Map<String, dynamic> json) {
    final locales = (json['locales'] as Map?) ?? const {};
    final byLang = <String, Map<String, String>>{};
    for (final entry in locales.entries) {
      final inner = (entry.value as Map?) ?? const {};
      byLang[entry.key.toString()] = {
        for (final item in inner.entries)
          item.key.toString(): item.value?.toString() ?? '',
      };
    }
    return AppTranslations(
      version: (json['version'] as num?)?.toInt() ?? 0,
      byLang: byLang,
    );
  }

  Map<String, dynamic> toJson() => {'version': version, 'locales': byLang};
}

final ValueNotifier<AppTranslations> appTranslationsNotifier =
    ValueNotifier<AppTranslations>(AppTranslations.empty);

/// Resolves a UI string from the active translation bundle (backend-driven,
/// with a bundled seed asset as the offline base — see [AppTranslationsStore]).
///
/// There is intentionally NO inline fallback text: if [key] is absent from the
/// bundle, the key itself is returned. That makes any string not yet backed by
/// the bundle instantly visible in the UI (and greppable), instead of silently
/// masking a gap with baked-in text.
String tr(Locale locale, String key) {
  final lang = switch (locale.languageCode) {
    'ru' => 'ru',
    'en' => 'en',
    _ => 'uz',
  };
  return appTranslationsNotifier.value.lookup(lang, key) ?? key;
}
