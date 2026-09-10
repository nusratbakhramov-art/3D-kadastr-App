import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../math/rotation.dart' show focalPx, rotationMatrix;

/// Telefon yuborilayotgan nishonga qanchalik yaqin ekani.
///
/// Bosqichlar bor, chunki overlay HAR MASOFADA foydali gap aytishi kerak,
/// faqat oxirida emas: nishon ekrandan tashqarida bo'lsa — strelka, ko'rinishga
/// kirsa — o'sib boradigan belgi, va «to'xta, shu» uchun alohida holat.
enum GuidanceLevel {
  /// Nishon butunlay boshqa joyda. Yo'nalishni ko'rsat, ekran chetiga o'zini
  /// pozitsiya qilib ko'rsatadigan belgi CHIZMA.
  far,

  /// Ekranda yoki unga yaqin, yaqinlashmoqda.
  approaching,

  /// Deyarli yetdi; boshqacha ko'rsatilgani ma'qul — foydalanuvchi sekinlashadi.
  highlighted,

  /// Suratga olish dopuskiga kirdi. Qolgani — qimirlamay turish.
  aligned,
}

/// Nishon telefon hozir qayerga qarab turganidan qanday ko'rinishi.
@immutable
class TargetSight {
  const TargetSight({
    required this.angleErrorDeg,
    required this.offsetPixels,
    required this.onScreen,
    required this.arrowRadians,
    required this.level,
  });

  /// Telefonning optik o'qi bilan nishon o'qi orasidagi burchak, darajada.
  final double angleErrorDeg;

  /// Nishon suratda qayerga tushishi — kadr MARKAZIDAN o'lchangan, piksel
  /// birligida. X o'ngga, Y pastga o'sadi: ham suratning, ham ekranning
  /// konvensiyasi shu.
  ///
  /// Nishon telefonning ORQASIDA bo'lsa `null` — u yerda proyeksiyaning ma'nosi
  /// yo'q, lekin strelka baribir qaysi tomonga burilishni biladi.
  final Offset? offsetPixels;

  /// [offsetPixels] kadr ichiga tushadimi.
  final bool onScreen;

  /// Qaysi tomonga burilish kerakligi — ekran burchagi, radianda: 0 o'ngni
  /// ko'rsatadi va soat strelkasi bo'yicha o'sadi, chunki ekranda Y pastga
  /// o'sadi.
  final double arrowRadians;

  final GuidanceLevel level;
}

/// [GuidanceLevel] chegaralari, burchak xatosining darajasida. Oxirgi chegara —
/// reticle'ni yashil qiladigani — konstanta EMAS: u halqa amalda nimani qabul
/// qilsa, o'sha.
const double kFarDeg = 15;
const double kApproachingDeg = 5;

/// Bitta suratga olish nishonini kameraning o'z ko'rinishiga proyeksiya qiladi.
///
/// Bu ataylab tikuvchining [rotationMatrix] ini va uning piksel konvensiyasini
/// ishlatadi, mustaqil yangi hosila emas. Belgining butun qiymati shundaki, u
/// kadr sferaga AMALDA tushadigan joyda turadi; ikkinchi, mustaqil yozilgan
/// proyeksiya taxminan to'g'ri bo'lardi va ikkovidan biri o'zgargan zahoti
/// ajralib ketardi.
///
/// ⚠️ EKRAN X BELGISI — bu yerda ATAYLAB proyektornikiga teskari, va bu
/// HAL QILINGAN masala, «tuzatilishi kerak bo'lgan» narsa emas:
///
///   * Proyektorning kamera X o'qi CHAPGA qaraydi (+Z oldinga, +Y yuqorida
///     bo'lgan o'ng qo'l tizimida boshqacha bo'lolmaydi), shuning uchun
///     `pixelFromCameraRay` markazdan siljishni `−focal·v.x/v.z` deb beradi.
///   * Bu ekranda esa musbat burilish «o'ngga burilish» degani — butun capture
///     ekrani, matn banneri va halqa shunga tayanadi. Shu sababli bu yerda
///     `+focal·cx/cz` olinadi.
///
/// Sfera ham HAQIQATAN gorizontal ko'zguga tushadi — bu «ochiq savol» emas,
/// o'lchangan va hal qilingan: `placementLon` dagi negatsiya bilan birga
/// tikuvchi oxirida BITTA gorizontal flip qiladi (reja §3.4,
/// `docs/panorama-360-plan.md`). Ikkalasi ham SHART. Biror kishi bu yerdagi
/// belgini «to'g'rilashga» urinmasin: u tuzatilsa, ekrandagi belgi matn bilan
/// zid bo'lib qoladi, tikish esa baribir o'zgarmaydi — ular ikki xil masala.
TargetSight sightTarget({
  required double yawDeg,
  required double pitchDeg,
  required double targetYawDeg,
  required double targetPitchDeg,
  required double imageWidth,
  required double imageHeight,
  required double longSideFovDeg,
  required double toleranceDeg,
  double rollDeg = 0,
}) {
  const double d2r = math.pi / 180;
  final List<double> r = rotationMatrix(
    yawDeg * d2r,
    pitchDeg * d2r,
    rollDeg * d2r,
  );

  // Nishonning optik o'qi dunyo yo'nalishi sifatida — proyektor ishlatadigan
  // aynan o'sha longitude/latitude konvensiyasida.
  final double tp = targetPitchDeg * d2r;
  final double ty = targetYawDeg * d2r;
  final double dx = math.cos(tp) * math.sin(ty);
  final double dy = math.sin(tp);
  final double dz = math.cos(tp) * math.cos(ty);

  // Kamera fazosiga. Faqat TRANSPOZ kerak: u dunyo yo'nalishini linza ko'rgan
  // joyga qaytaradi. (Matritsa ortonormal bo'lgani uchun transpoz = teskari —
  // `rotation.dart` dagi ogohlantirishga qarang.)
  final double cx = r[0] * dx + r[3] * dy + r[6] * dz;
  final double cy = r[1] * dx + r[4] * dy + r[7] * dz;
  final double cz = r[2] * dx + r[5] * dy + r[8] * dz;

  // cz — nishon yo'nalishining telefon optik o'qiga skalyar ko'paytmasi, ya'ni
  // burchak xatosi qo'shimcha ishsiz shu yerda.
  final double angleErrorDeg = math.acos(cz.clamp(-1.0, 1.0)) / d2r;

  // Fokus `rotation.dart` dan olinadi, bu yerda qayta yozilmaydi: belgi kadr
  // AMALDA tushadigan joyda turishi kerak, ya'ni tikuvchi bilan bitta formula.
  final double focal = focalPx(imageWidth, imageHeight, longSideFovDeg);

  Offset? offset;
  bool onScreen = false;
  if (cz > 1e-6) {
    offset = Offset(focal * cx / cz, -focal * cy / cz);
    onScreen =
        offset.dx.abs() <= imageWidth / 2 && offset.dy.abs() <= imageHeight / 2;
  }

  // Qaysi tomonga burilish kerakligi nishon telefon ORQASIDA bo'lganda ham
  // ma'noga ega — u yerda o'qiladigan proyeksiya yo'q. Faqat yon
  // komponentlarning o'zi buni aytadi va nishon orqadan aylanib o'tayotganda
  // ham aytishda davom etadi.
  final double arrow = math.atan2(-cy, cx);

  return TargetSight(
    angleErrorDeg: angleErrorDeg,
    offsetPixels: offset,
    onScreen: onScreen,
    arrowRadians: arrow,
    level: _levelFor(angleErrorDeg, toleranceDeg),
  );
}

GuidanceLevel _levelFor(double errorDeg, double toleranceDeg) {
  if (errorDeg > kFarDeg) return GuidanceLevel.far;
  if (errorDeg > kApproachingDeg) return GuidanceLevel.approaching;
  // `aligned` — surat OLINADIGAN holat, undan kengi emas. O'ziga alohida
  // ko'rsatuv chegarasi berilsa, u ertami-kechmi halqaning dopuskidan keng
  // qilib qo'yiladi va reticle yashil bo'lib turaveradi, capture esa jimgina
  // rad etadi — foydalanuvchi qimirlamay turadi, unga «yetding» deyilgan,
  // lekin hech narsa bo'lmayapti.
  if (errorDeg > toleranceDeg) return GuidanceLevel.highlighted;
  return GuidanceLevel.aligned;
}
