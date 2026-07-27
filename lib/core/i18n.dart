import 'package:flutter/widgets.dart';

import 'i18n/app_translations.dart';

/// Umumiy (takrorlanadigan) UI matnlari. Matnlar backend bundleʼidan (yoki
/// bundik seed assetdan) keladi — bu yerda faqat kalitlar.
class L {
  const L._();
  static String _s(Locale l, String key) => tr(l, key);

  static String retry(Locale l) => _s(l, 'common.retry');
  static String errorOccurred(Locale l) => _s(l, 'common.error_occurred');
  static String cancel(Locale l) => _s(l, 'common.cancel');
  static String add(Locale l) => _s(l, 'common.add');
  static String search(Locale l) => _s(l, 'common.search');
  static String searchAddress(Locale l) => _s(l, 'common.search_address');
  static String roomName(Locale l) => _s(l, 'common.room_name');
  static String authRequired(Locale l) => _s(l, 'common.auth_required');
}
