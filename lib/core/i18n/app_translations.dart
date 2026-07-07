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

String tr(
  Locale locale,
  String key, {
  required String uz,
  required String ru,
  required String en,
}) {
  final lang = switch (locale.languageCode) {
    'ru' => 'ru',
    'en' => 'en',
    _ => 'uz',
  };
  final override = appTranslationsNotifier.value.lookup(lang, key);
  if (override != null) return override;
  return switch (lang) {
    'ru' => ru,
    'en' => en,
    _ => uz,
  };
}
