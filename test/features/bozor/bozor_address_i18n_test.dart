// Manzil qadamining yangi matn kalitlari seed bundle'ida BOR ekani.
//
// `tr()` topilmagan kalit uchun XOM KALITNI qaytaradi, ya'ni bitta xato
// kalit ekranda "bozor.address.manual_pin" bo'lib chiqadi. Qo'lda metka
// qo'yish yo'li aynan shu qatorda yashiringani uchun buni sezmay qolish
// oson: geoportal qamragan obyektlarda hammasi joyida ko'rinadi, va faqat
// uchastka topilmagan foydalanuvchi xom kalitga qaraydi.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const screen = 'lib/features/bozor/screens/bozor_address_step_screen.dart';

  test('manzil qadami ishlatadigan kalitlar uz/ru/en uchun seed\'da bor', () {
    final source = File(screen).readAsStringSync();
    final keys = RegExp(r"tr\(\s*l\s*,\s*'([^']+)'\s*\)")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    expect(keys, isNotEmpty);
    // Uchastka oqimi bilan kelgan uchta yangi kalit shu ro'yxatda bo'lishi
    // kerak — regex ishlamay qolsa test jimgina "joyida" demasin.
    expect(keys, contains('bozor.address.manual_pin'));
    expect(keys, contains('bozor.address.cadastre'));
    expect(keys, contains('bozor.address.cadastre_failed'));

    final locales = (jsonDecode(
      File('assets/i18n/bundle.json').readAsStringSync(),
    ) as Map<String, dynamic>)['locales'] as Map<String, dynamic>;

    final missing = <String>[];
    for (final lang in const ['uz', 'ru', 'en']) {
      final map = locales[lang] as Map<String, dynamic>;
      for (final key in keys) {
        final value = map[key];
        if (value == null || (value as String).trim().isEmpty) {
          missing.add('$lang: $key');
        }
      }
    }
    expect(missing, isEmpty, reason: 'seed bundle\'da yo\'q: $missing');
  });
}
