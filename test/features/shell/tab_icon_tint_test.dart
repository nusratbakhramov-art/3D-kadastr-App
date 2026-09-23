import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadastr/features/shell/app_bottom_nav.dart';
import 'package:kadastr/features/shell/main_shell.dart';
import 'package:kadastr/theme/app_colors.dart';

/// Pastki paneldagi ikonka va yozuv RANGI juftligini qo'riqlaydi.
///
/// ⚠️ NEGA BU TEST BOR. Ikonkalar endi rangli 3D PNG — hech kim ularni
/// bo'yamaydi, yozuvning rangi esa qo'lda beriladi. Ya'ni kimdir ikonkani
/// almashtirsa yoki yangi tab qo'shsa, yozuv eski rangda qolib ketishi
/// mumkin — buni `analyze` ham, boshqa testlar ham ko'rmaydi. Fayl yo'qligi
/// ham xuddi shunday: ilova ishlayveradi, faqat tab bo'sh chiqadi.
void main() {
  const locale = Locale('uz');

  List<AppBottomNavItem> items() => shellNavItems(locale);

  test('to\'rt tab bor', () {
    expect(items(), hasLength(4));
  });

  test('HAR BIR tab ikonkasi haqiqatdan ham bor', () {
    for (final it in items()) {
      // Profil ikonkani o'zi chizadi (avatar) — u uchun asset shart emas.
      if (it.iconBuilder != null) continue;
      expect(
        File(it.iconAsset).existsSync(),
        isTrue,
        reason: '${it.label}: ${it.iconAsset} yo\'q',
      );
    }
  });

  test('yozuv rangi ikonka rangiga mos — har tab o\'ziniki', () {
    final list = items();
    // Asosiy — yashil uy, Market — ko'k sumka, Arizalar — to'q sariq hujjat.
    expect(list[0].labelColorLight, AppColors.brandGreen);
    expect(list[0].labelColorDark, AppColors.splashGreen);
    expect(list[1].labelColorLight, const Color(0xFF1B8FEA));
    expect(list[2].labelColorLight, const Color(0xFFF26522));

    final lightColors = list.map((i) => i.labelColorLight).toSet();
    expect(
      lightColors,
      hasLength(list.length),
      reason: 'ikki tab bir xil rangda — ular bir-biridan ajralmay qoladi',
    );
  });

  test('Profil ataylab NEYTRAL va avatar chizadi', () {
    final profile = items().last;
    expect(profile.labelColorLight, AppColors.textBlack);
    expect(profile.labelColorDark, Colors.white);
    expect(profile.iconBuilder, isNotNull);
  });
}
