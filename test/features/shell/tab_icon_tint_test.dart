import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/shell/app_bottom_nav.dart';
import 'package:kadastr/features/shell/main_shell.dart';
import 'package:kadastr/theme/app_colors.dart';

/// Pastki panel HAMMA ikonkasi bir xil yashilda bo'lsin.
///
/// ⚠️ NEGA BU TEST BOR. Market va Arizalar korzinka.uz va my.gov.uz
/// belgilari — ular O'Z BREND RANGLARINI SVG ichida olib yuradi (qizil va
/// ko'k). Tint berilmasa o'sha ranglar chiqadi va panel uch xil rangli
/// bo'lib ko'rinadi. Bu jimgina qaytadi: kimdir ikonkani almashtirsa yoki
/// yangi tab qo'shsa, `analyze` ham, boshqa testlar ham hech narsa demaydi —
/// faqat ekranga qarab bilinadi.
void main() {
  const locale = Locale('uz');

  List<AppBottomNavItem> items() => shellNavItems(locale);

  test('to\'rt tab bor', () {
    expect(items(), hasLength(4));
  });

  test('HAR BIR tab tint beradi — brend rangi chiqib qolmasin', () {
    for (final it in items()) {
      expect(it.tintLight, isNotNull, reason: '${it.label}: tintLight yo\'q');
      expect(it.tintDark, isNotNull, reason: '${it.label}: tintDark yo\'q');
    }
  });

  test('Market va Arizalar — Asosiy bilan BIR XIL yashil', () {
    final list = items();
    final home = list[0];
    for (final i in [1, 2]) {
      expect(list[i].tintLight, home.tintLight,
          reason: '${list[i].label}: yorug\' mavzuda rang farq qilyapti');
      expect(list[i].tintDark, home.tintDark,
          reason: '${list[i].label}: qorong\'i mavzuda rang farq qilyapti');
    }
    expect(home.tintLight, AppColors.brandGreen);
    expect(home.tintDark, AppColors.splashGreen);
  });

  test('Profil ataylab NEYTRAL qoladi', () {
    // Profil — yashil emas, matn rangida: u brend belgisi emas va
    // qolganlaridan ajralib turishi kerak.
    final profile = items().last;
    expect(profile.tintLight, AppColors.textBlack);
    expect(profile.tintDark, Colors.white);
  });
}
