/// Panorama geometriyasining POYDEVORI — burilish matritsasi, kamera nur/piksel
/// almashinuvi va fokus hisobi.
///
/// NEGA ALOHIDA FAYL: manbada (`panorama` 1.0.2) bu funksiyalar
/// `lib/services/sensor_stitcher.dart` ichida yashaydi va `capture_guidance.dart`
/// `rotationMatrix` ni o'shandan import qiladi — ya'ni capture ekranining
/// nishoni butun OpenCV tikuvchisini sudrab keladi. Bu yerda tikish sof Dart'da
/// yoziladi (docs/panorama-360-plan.md §1), shu sababli matematika o'z faylida
/// turadi: uni na tikuvchi, na raster yadrolari, na widget'lar bog'lamaydi.
///
/// NEGA `vector_math` EMAS: bu yerda kerak bo'lgan hamma narsa — 3x3 ko'paytma
/// va atan2. `vector_math` ning `Matrix3` i USTUN-major (column-major) saqlaydi,
/// manbadagi indekslar esa QATOR-major; konvertatsiya jim belgi xatolariga eng
/// qulay joy bo'lardi (aynan shu turdagi xato manbada 5 px → 218 px qoldiq
/// bergan). Qo'shimcha bog'liqlik ham, `Matrix3` obyekt yuki ham keraksiz.
///
/// NEGA `Float64List`: proyektor bu matritsani har kadr uchun bir marta
/// tuzadi, lekin uning elementlarini kanvasning HAR PIKSELI uchun o'qiydi
/// (reja §5.1 — 47 M piksel). `List<double>` literali elementlarni quti ichida
/// (boxed) saqlaydi; `Float64List` ularni tekis xotirada tutadi.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Daraja → radian.
const double _d2r = math.pi / 180;

/// Kamera → dunyo burilishi, QATOR-major 3x3: `R = Ry(ψ) · Rx(−θ) · Rz(φ)`.
///
/// Dunyo konvensiyasi: o'ng qo'l, **Y yuqoriga**, identity kamera **+Z** ga
/// qaraydi. `d.x = cos(lat)·sin(lon)`, `d.y = sin(lat)`, `d.z = cos(lat)·cos(lon)`.
///
/// 2-ustun — optik o'q: `lat = asin(m[5])`, `lon = atan2(m[2], m[8])`.
///
/// ⚠️ O'rta ustundagi IKKI MINUS (`-sy·sp` va `-cy·sp`) — TERIM XATOSI EMAS.
/// Rx TESKARI belgi bilan olinadi, chunki musbat pitch latitude'ni oshirishi va
/// kameraning o'z «yuqori» vektorini orqaga olib ketishi kerak. Ular bo'lmasa
/// matritsa ORTONORMAL bo'lmay qoladi — «yuqori» va «oldinga» o'qlari
/// perpendikulyar bo'lmaydi. Proyektor teskarisini TRANSPOZ bilan oladi, ya'ni
/// ortonormallik yo'qolsa transpoz teskari bo'lishdan to'xtaydi va HAR QANDAY
/// egilgan kadr gorizontga proyeksiya qilinadi (manbada o'lchangan: 138° o'rniga
/// 67° vertikal qamrov). Bu jim xato — na crash, na ogohlantirish.
/// `rotation_test.dart` dagi `dot(col1, col2) == 0` aynan shuni qo'riqlaydi.
Float64List rotationMatrix(double psi, double theta, double phi) {
  final double cy = math.cos(psi), sy = math.sin(psi);
  final double cp = math.cos(theta), sp = math.sin(theta);
  final double cr = math.cos(phi), sr = math.sin(phi);

  // Ry(ψ) · Rx(−θ).
  final double a0 = cy, a1 = -sy * sp, a2 = sy * cp;
  final double a3 = 0, a4 = cp, a5 = sp;
  final double a6 = -sy, a7 = -cy * sp, a8 = cy * cp;

  // · Rz(φ). 3-ustun roll'dan o'zgarmaydi — roll optik o'qni qimirlatmaydi,
  // faqat kadrni o'z o'qi atrofida aylantiradi.
  final Float64List m = Float64List(9);
  m[0] = a0 * cr + a1 * sr;
  m[1] = -a0 * sr + a1 * cr;
  m[2] = a2;
  m[3] = a3 * cr + a4 * sr;
  m[4] = -a3 * sr + a4 * cr;
  m[5] = a5;
  m[6] = a6 * cr + a7 * sr;
  m[7] = -a6 * sr + a7 * cr;
  m[8] = a8;
  return m;
}

/// Telefon yo'nalishini (yaw, daraja) proyektor longitudasiga (radian)
/// aylantiradi.
///
/// ⚠️ MINUS — butun mazmuni shu, va u kosmetik emas. Ilovaning yaw'i telefon
/// O'NGGA burilganda o'sadi (capture guidance shunga tayanadi); proyektorning
/// longitudasi teskari tomonga o'sadi, chunki +Z oldinga va +Y yuqorida bo'lgan
/// o'ng qo'l tizimida kameraning X o'qi CHAPGA qaraydi. Ikki konvensiya bor va
/// konvertatsiya BITTA joyda bo'lishi kerak.
///
/// Manbadagi tarix: `4a4bd44` yaw'ni to'g'riladi, lekin bu negatsiya
/// qo'shilmadi — har kadr o'z o'rnining ko'zgusiga tushdi, mos feature'lar
/// qoldig'i 5 px dan 218 px ga chiqdi, 70 kadrdan 30 tasi tuzatilmadi.
///
/// ⚠️ Buning natijasida sfera gorizontal ko'zgu bo'lib qoladi va oxirida BITTA
/// gorizontal flip qilinadi (reja §3.4). `placementLon` ni «tuzatib» flip'dan
/// qutulib bo'lmaydi — o'shanda kadrlar orasidagi kelishuv buziladi.
double placementLon(double yawDeg) => -yawDeg * _d2r;

/// Piksel → kamera fazosidagi BIRLIK nur.
///
/// ⚠️ IKKALA MINUS ham ataylab. Kamera +Z ga qaraydi va +Y yuqorida; bu o'ng
/// qo'l tizimi bo'lishi uchun kameraning X o'qi CHAPGA qarashi SHART — ya'ni
/// o'ngga o'sadigan piksel x unga qarshi yuradi, xuddi pastga o'sadigan piksel
/// y kameraning «yuqori»siga qarshi yurgani kabi.
///
/// Bu O'LCHANGAN, taxmin emas: mos feature'lar bo'yicha median qoldiq shu
/// belgilarda 2.9° (gyroning o'z aniqligi), qolgan uch kombinatsiyada 37°, 43°
/// va 30°. Belgini almashtirish har kadrni o'z markazi atrofida ko'zguga
/// aylantiradi, lekin longitudasini TO'G'RI qoldiradi — shuning uchun chok
/// hech qayerda mos kelmaydi va blending bilan tuzatib bo'lmaydi.
///
/// Linza buzilishi (`k1`) ATAYLAB ko'chirilmadi: proyektor `k1 = 0` bilan
/// ishlaydi (reja §3.5), manbadagi `pixelFromCameraRay` esa `k1` ni umuman
/// hisobga olmaydi — ya'ni juftlik `k1 ≠ 0` da bir-birining teskarisi
/// BO'LMAYDI. Yarim ko'chirilgan model jim tuzoq bo'lardi.
Float64List cameraRayFromPixel(
  double px,
  double py,
  double cx,
  double cy,
  double focal,
) {
  final double x = -(px - cx) / focal;
  final double y = -(py - cy) / focal;
  final double m = math.sqrt(x * x + y * y + 1);
  final Float64List v = Float64List(3);
  v[0] = x / m;
  v[1] = y / m;
  v[2] = 1 / m;
  return v;
}

/// Kamera fazosidagi yo'nalish → piksel. [cameraRayFromPixel] ning aynan
/// teskarisi; proyektor tezlik uchun shu arifmetikani o'z ichiga yozadi, shu
/// sababli aylanma yo'l (`piksel → nur → piksel`) test bilan qotiriladi.
Float64List pixelFromCameraRay(
  List<double> v,
  double cx,
  double cy,
  double focal,
) {
  final Float64List p = Float64List(2);
  p[0] = cx - focal * v[0] / v[2];
  p[1] = cy - focal * v[1] / v[2];
  return p;
}

/// Fokus masofasi, pikselda. FOV kadrning UZUN tomoni bo'yicha beriladi, ya'ni
/// portret/landshaft farqi natijani o'zgartirmaydi.
///
/// ⚠️ Bu yerdagi eng jim halokat — EXIF orientatsiyasi (reja §4.2): dekoder
/// uzun tomonni almashtirib yuborsa focal ~1.78× xato chiqadi va hech narsa
/// tikilmaydi. Shu sababli funksiya `w` va `h` ning ikkalasini ham oladi va
/// uzunini O'ZI tanlaydi.
///
/// `focalPx(2160, 3840, 67.3) = 2884.37 px` (koeffitsiyent 0.7511376).
double focalPx(num w, num h, double longSideFovDeg) {
  final num longSide = math.max(w, h);
  return (longSide / 2) / math.tan(longSideFovDeg * math.pi / 360);
}

/// Berilgan YARIM kenglik va fokus uchun gorizontal ko'rish burchagi, daraja.
///
/// Manbadagi `_hFovDeg(w, h, fov)` shuning kompozitsiyasi:
/// `hFovDeg(w / 2, focalPx(w, h, fov))`. Bu yerda ajratilgani sababi — kadr
/// izini (`_footprint`) hisoblaydigan geometriya (7-qadamdan keyingi 10-qadam)
/// ba'zan allaqachon ma'lum focal bilan ishlaydi va FOV ni qayta hisoblash
/// aylanma yo'l bo'lardi.
///
/// `hFovDeg(1080, 2884.37) = 41.055°`.
double hFovDeg(double halfWidth, double focal) =>
    2 * math.atan(halfWidth / focal) / _d2r;
