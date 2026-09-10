/// Bitta olingan kadr va uning sensor burchaklari.
///
/// Tikish quvuri feature'lardan emas, SHU burchaklardan boshlanadi: har kadr
/// o'z yaw/pitch'i bo'yicha ekvirektangulyar tuvalga qo'yiladi, keyin
/// nozik moslashtirish ustidan yuriladi.
library;

import 'package:flutter/foundation.dart';

@immutable
class SensorShot {
  const SensorShot({
    required this.path,
    required this.yawDeg,
    required this.pitchDeg,
    this.rollDeg = 0,
    this.row = 0,
  });

  final String path;

  /// Capture'ning BIRINCHI kadriga nisbatan yo'nalish, soat yo'nalishi musbat.
  final double yawDeg;

  /// Balandlik, tortishishga nisbatan. +90 — tik yuqoriga.
  final double pitchDeg;

  /// LINZA O'QI atrofidagi burilish — sensor bergan qurilma roll'i EMAS.
  ///
  /// ⚠️ Bu ikki xil burchak va ularni aralashtirish HALOKATLI. Portretda tik
  /// ushlangan telefon xom qurilma roll'ini ±180 atrofida beradi, chunki bu
  /// holat ishora almashadigan singulyarlikda turadi; haqiqiy capture'da
  /// gorizont qatori -178.6 dan 167.1 gacha tarqalib chiqdi. Uni linza
  /// roll'i deb shu yerga bersak, har kadr teskari aylanadi va panorama
  /// butunlay surtilib ketadi — aynan shu bo'lgan.
  ///
  /// Shu sababli chaqiruvchilar hech narsa bermaydi va bu NOL qoladi: tik
  /// ushlangan telefon uchun to'g'ri, faqat yon egilgan darajasicha xato.
  /// Xom qurilma roll'i sessiya hisobotida saqlanadi, ya'ni keyinchalik
  /// to'g'ri konvertatsiya qilish uchun qayta suratga olish kerak emas —
  /// lekin u KONVERTATSIYA qilinishi va QURILMADA tekshirilishi kerak,
  /// bu yerga yaqinlashishdan oldin.
  final double rollDeg;

  /// Kadr qaysi capture qatoriga tegishli. Qatorlar BUTUN holda
  /// to'g'rilanadi: bir qatorning hamma kadri bir xil xatoni bo'lishadi
  /// (telefon o'sha balandlikda ushlanib turgan), shuning uchun xatoni
  /// qator bo'yicha o'rtachalash kadrma-kadr to'g'rilashdan barqarorroq.
  final int row;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'yawDeg': yawDeg,
    'pitchDeg': pitchDeg,
    'rollDeg': rollDeg,
    'row': row,
  };
}
