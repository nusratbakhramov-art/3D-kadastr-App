// «Taqiqni tekshirish» ekranining matn kalitlari seed bundle'ida BOR ekani.
//
// `tr()` topilmagan kalit uchun XOM KALITNI qaytaradi (`app_translations.dart`
// da ataylab shunday), ya'ni bitta xato kalit ekranda
// "services.taqiq.clean_title" bo'lib chiqadi — va buni faqat qurilmada,
// aynan ta'qiqli obyekt topilganda ko'rgan bo'lardik.
//
// Test kalitlarni ekran MANBASIDAN o'qiydi, ro'yxatdan emas: keyin qo'shilgan
// yangi kalit ham o'z-o'zidan qamrab olinadi.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const screen = 'lib/features/services/screens/taqiq_check_screen.dart';

  test('ekran ishlatadigan hamma kalit uz/ru/en uchun seed\'da bor', () {
    final source = File(screen).readAsStringSync();
    final keys = RegExp(r"tr\(\s*l\s*,\s*'([^']+)'\s*\)")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    // Ekran kamida ta'qiqqa xos matnlarni ishlatadi — regex ishlamay qolsa
    // test jimgina "hammasi joyida" demasin.
    expect(keys, isNotEmpty);
    expect(keys.where((k) => k.startsWith('services.taqiq.')), isNotEmpty);

    final bundle = jsonDecode(
      File('assets/i18n/bundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final locales = bundle['locales'] as Map<String, dynamic>;

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

  test('olib tashlangan "davreest.uz dan avtomatlik olinadi" qatori qaytmadi',
      () {
    // Ikki ekrandan ham olib tashlangan (kadastr maydoni ostidagi izoh).
    // Kalitlar seed'dan ham chiqarilgan, shuning uchun qaytib kelsa xom kalit
    // ko'rinardi — buni shu yerda ushlaymiz.
    final bundle = jsonDecode(
      File('assets/i18n/bundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final locales = bundle['locales'] as Map<String, dynamic>;
    for (final lang in const ['uz', 'ru', 'en']) {
      final map = locales[lang] as Map<String, dynamic>;
      expect(map.containsKey('services.ai.cadastre.helper_suffix'), isFalse);
      expect(map.containsKey('services.k3d.auto_fetch_suffix'), isFalse);
    }

    for (final path in const [
      'lib/features/services/screens/ai_cadastre_screen.dart',
      'lib/features/services/screens/kadastr_3d_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('_HelperLine')),
        reason: '$path da izoh qatori qaytib kelgan',
      );
    }
  });
}
