/// Foydalanuvchi tanlagan mavzuni (system / light / dark) qurilmada saqlaydi.
///
/// Sozlamalar ekrani `ThemeStorage.save()` orqali tanlangan mavzuni yozadi;
/// app start paytida `ThemeStorage.load()` saqlangan qiymatni qaytaradi
/// (yoki `null`, agar foydalanuvchi hali tanlamagan bo'lsa).
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeStorage {
  const ThemeStorage();

  static const String _key = 'app_theme_mode_v1';

  /// Saqlangan mavzuni o'qib qaytaradi. Hali yo'q bo'lsa `null`.
  Future<ThemeMode?> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name); // 'system' | 'light' | 'dark'
  }
}
