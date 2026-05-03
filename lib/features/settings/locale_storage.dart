/// Foydalanuvchi tanlagan tilni qurilmada saqlaydi (shared_preferences).
///
/// Onboarding va Settings ekranlari `LocaleStorage.save()` orqali tanlangan
/// locale ni yozadi; app start paytida `LocaleStorage.load()` saqlangan
/// qiymatni qaytaradi (yoki `null`, agar foydalanuvchi hali tanlamagan).
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleStorage {
  const LocaleStorage();

  static const String _key = 'app_locale_v1';

  /// Saqlangan locale ni o'qib qaytaradi. Hali yo'q bo'lsa `null`.
  Future<Locale?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  Future<void> save(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
  }
}
